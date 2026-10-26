--[[
    EqInfoDisplay.lua
    Shows the four stats wherever RLRM already shows a horse's fitness and riding.

    A player sees each stat's trained level as a number, and its potential (the ceiling) only
    as RLRM's genetics word (Average, High, Very high...), on our own ladder that follows the
    event tiers (STAT_BANDS). The exact ceiling stays hidden, as a real owner could only judge it.

    - AnimalHorse.addHorseInfos feeds the stat rows of RLRM's menu and the pen's animal screen:
      a bar of the trained level with "54 (High)" as its text.
    - When you look at a horse, a Skills box of our own sits below RLRM's Genetics box:
      "54 - Amateur (High)" for each stat, the skill and the potential in their stat colour
      (EqSkillsHudBox), then whether the potential is still the dealer's view
      and the horse's competition status.
    - Stat names take a soft version of the stat's colour (STAT_COLOR); skills, and potentials by
      their ceiling, shade from white at 0 to a saturated one at 100 (STAT_FULL_COLOR). A skill
      shows its net change over the last seven days to one decimal, "54 - Amateur (+2.8)", left
      out when it rounds to 0.0.

    In RLRM's menu the stats get a section of their own under Pedigree and Genetics, laid out
    like it: SKILL POTENTIAL on the left (the word only, "High"), SKILLS on the right (the
    trained level, "54 - High"), the four stats in the same order in both, coloured on RLRM's
    red-to-green genetics scale. SKILLS ends with the horse's favourite event (EqExperience). The section is a clone of RLRM's Pedigree/Genetics row, made
    the first time a frame shows a horse and hidden for other animals. For a horse the stat grid
    then has only RLRM's rows (and our status line), so the grid and the Pedigree/Genetics row
    are shrunk to what they show, which keeps the pane short enough not to scroll.

    Meat quality: for horses only, RLRM's Meat Quality row is taken out of the menu's genetics
    column and the look-at genetics box. It is a display preference, saved per machine in
    modSettings, and eqMeatQuality show|hide switches it. RLRM's own data is never changed.
]]

EqInfoDisplay = {}

-- Index our stat block starts at in the menu's grid: after Age and one RLRM row, so it fills
-- two whole lines (Stamina | Speed, Agility | Temperament). Only used when the stats cannot go
-- in the Genetics column.
EqInfoDisplay.MENU_FIRST_ROW = 3

-- True once RLDetailPaneHelper.updateAnimalDisplay is hooked: the stats then live in their own
-- section and the stat grid leaves them out.
EqInfoDisplay.statsInSection = false

-- RLRM's stat grid: 10px top padding, then 35px a line (rlMenu_animalStatsSection, 185px for
-- five lines).
EqInfoDisplay.GRID_PADDING = 10
EqInfoDisplay.GRID_LINE = 35
EqInfoDisplay.GRID_LINES = 5

EqInfoDisplay.MEAT_LABEL_KEY = "rl_ui_meat"
EqInfoDisplay.hideMeatQuality = true

local Log = EqLog
local settingsDirectory = g_currentModSettingsDirectory


--- @param stat string
--- @return string title
local function statTitle(stat)
    return g_i18n:getText("eq_stat_" .. stat)
end


-- Each stat's colour for its name: the training panel's colour, softened toward grey so the
-- names don't glare.
EqInfoDisplay.STAT_COLOR = {
    stamina = { 0.58, 0.76, 0.94, 1 },
    speed = { 0.94, 0.67, 0.43, 1 },
    agility = { 0.66, 0.76, 0.34, 1 },
    temperament = { 0.82, 0.67, 0.94, 1 },
}

-- Where a stat's values end up at 100: the same hues, more saturated than the names, so a
-- strong horse stands out. Values shade from white to these.
EqInfoDisplay.STAT_FULL_COLOR = {
    stamina = { 0.15, 0.55, 1, 1 },
    speed = { 1, 0.45, 0, 1 },
    agility = { 0.7, 1, 0, 1 },
    temperament = { 0.65, 0.3, 1, 1 },
}


--- @param change number net change over the recent days
--- @return string|nil "(+2.8)" to one decimal, nil when it rounds to 0.0
function EqInfoDisplay.gainText(change)
    local tenths = math.floor(math.abs(change or 0) * 10 + 0.5)
    if tenths == 0 then return nil end
    return string.format("(%s%d.%d)", change > 0 and "+" or "-", math.floor(tenths / 10), tenths % 10)
end


--- @param record table
--- @return table stat -> change over the last EqHorseRecord.GAIN_DAYS days
local function recentGains(record)
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    return record:getRecentGains(env ~= nil and env.currentMonotonicDay or 0)
end


-- Our ladder for a stat's potential (its ceiling), in RLRM's words and colours, since potential
-- is genetic like RLRM's own traits. It follows the event tiers rather than RLRM's gene scale:
-- Average is a Novice horse, High an Intermediate one, Very high Advanced and Extremely high
-- Championship class.
EqInfoDisplay.STAT_BANDS = {
    { from = 85, key = "rl_ui_genetics_extremelyHigh" },
    { from = 70, key = "rl_ui_genetics_veryHigh" },
    { from = 55, key = "rl_ui_genetics_high" },
    { from = 40, key = "rl_ui_genetics_average" },
    { from = 30, key = "rl_ui_genetics_low" },
    { from = 20, key = "rl_ui_genetics_veryLow" },
    { from = -math.huge, key = "rl_ui_genetics_extremelyLow" },
}


-- Words for a trained level. Training changes it, so it reads as progress, not as a verdict:
-- white for an untrained horse, greener as it learns.
EqInfoDisplay.SKILL_BANDS = {
    { from = 98, key = "eq_skill_legend" },
    { from = 90, key = "eq_skill_champion" },
    { from = 80, key = "eq_skill_contender" },
    { from = 70, key = "eq_skill_competitor" },
    { from = 60, key = "eq_skill_promising" },
    { from = 50, key = "eq_skill_amateur" },
    { from = 25, key = "eq_skill_trainee" },
    { from = 10, key = "eq_skill_novice" },
    { from = -math.huge, key = "eq_skill_untrained" },
}
-- Skill colours by level: white for an untrained horse, through yellow, to RLRM's own genetics
-- greens at the top. RLRM's palette (RLDetailPaneHelper.GENETICS_COLOR) is used where it has the
-- colour; the values here are the same, as a fallback.
EqInfoDisplay.SKILL_COLOR_STOPS = {
    { at = 0, color = { 1, 1, 1, 1 } },
    { at = 25, color = { 1, 1, 0.6, 1 } },
    { at = 50, key = "average", color = { 1, 1, 0, 1 } },
    { at = 65, key = "high", color = { 0.52, 1, 0, 1 } },
    { at = 80, key = "veryHigh", color = { 0.2, 1, 0, 1 } },
    { at = 95, key = "extremelyHigh", color = { 0, 1, 0, 1 } },
}


--- @param value number a trained level, 0-100
--- @return string key l10n key for its word
function EqInfoDisplay.skillBandKey(value)
    for _, band in ipairs(EqInfoDisplay.SKILL_BANDS) do
        if value >= band.from then return band.key end
    end
end


--- @param stop table from SKILL_COLOR_STOPS
--- @return table color
local function stopColor(stop)
    local helper = EqRLRM.get("RLDetailPaneHelper")
    local palette = helper ~= nil and helper.GENETICS_COLOR or nil
    return stop.key ~= nil and palette ~= nil and palette[stop.key] or stop.color
end


--- @param value number a trained level, 0-100
--- @param stat string|nil with a stat, white at 0 shading to its STAT_FULL_COLOR at 100
--- @return table color { r, g, b, a }: without a stat, white at 0, yellow by 50, RLRM's brightest green from 95
function EqInfoDisplay.skillColor(value, stat)
    local full = stat ~= nil and EqInfoDisplay.STAT_FULL_COLOR[stat] or nil
    if full ~= nil then
        -- White for an untrained horse, shading to the stat's own colour at 100.
        local t = EqStats.clamp(value or 0, 0, 100) / 100
        local color = {}
        for c = 1, 4 do color[c] = 1 + (full[c] - 1) * t end
        return color
    end
    local stops = EqInfoDisplay.SKILL_COLOR_STOPS
    value = EqStats.clamp(value or 0, 0, 100)
    for i = 2, #stops do
        if value <= stops[i].at then
            local from, to = stops[i - 1], stops[i]
            local t = (value - from.at) / (to.at - from.at)
            local a, b = stopColor(from), stopColor(to)
            local color = {}
            for c = 1, 4 do color[c] = a[c] + (b[c] - a[c]) * t end
            return color
        end
    end
    local top = stopColor(stops[#stops])
    return { top[1], top[2], top[3], top[4] }
end


--- @param trained number
--- @param change number|nil recent change, shown after the skill when it rounds to 0.1 or more
--- @param stat string|nil colours the skill from white to this stat's colour
--- @return string valueText "54 - Amateur", or "54 - Amateur (+2.8)" with a recent change
--- @return table color
function EqInfoDisplay.skillValue(trained, change, stat)
    local shown = math.floor(trained + 0.5)
    local text = string.format("%d - %s", shown, g_i18n:getText(EqInfoDisplay.skillBandKey(shown)))
    local gain = EqInfoDisplay.gainText(change)
    if gain ~= nil then text = text .. " " .. gain end
    return text, EqInfoDisplay.skillColor(trained, stat)
end


--- @param value number a stat level or ceiling, 0-100
--- @return string key RLRM's l10n key for the band
function EqInfoDisplay.statBandKey(value)
    for _, band in ipairs(EqInfoDisplay.STAT_BANDS) do
        if value >= band.from then return band.key end
    end
end


--- @param value number
--- @return string word such as "High"
local function bandText(value)
    return g_i18n:getText(EqInfoDisplay.statBandKey(value), EqRLRM.MOD_NAME)
end


--- @param ceiling number
--- @param unvetted boolean|nil true while the word is still the dealer's view
--- @return string word for the horse's potential in a stat, "High?" while unvetted
function EqInfoDisplay.potentialText(ceiling, unvetted)
    local word = bandText(ceiling)
    if unvetted then return string.format(g_i18n:getText("eq_potential_unvetted"), word) end
    return word
end


--- @param record table
--- @return boolean true while the shown potential is the dealer's view
local function isUnvetted(record)
    return record.advertised ~= nil and not record.revealed
end


--- @param trained number
--- @param ceiling number
--- @param unvetted boolean
--- @param change number|nil recent change
--- @return string text such as "54 - Amateur (High)": the skill in our words, then the potential
local function statText(trained, ceiling, unvetted, change)
    local skill = EqInfoDisplay.skillValue(trained, change)
    return string.format("%s (%s)", skill, EqInfoDisplay.potentialText(ceiling, unvetted))
end


--- @param record table
--- @param animal table|nil RLRM Animal
--- @return string|nil text "Injured, 3 month(s)", "Retired" or "Settling in", nil for a horse in work
local function statusText(record, animal)
    if record.injury ~= nil then return string.format(g_i18n:getText("eq_status_injured"), EqInjury.monthsLeft(record, animal) or 1) end
    if record.retired then return g_i18n:getText("eq_status_retired") end
    if record:isSettling() then return g_i18n:getText("eq_status_settling") end
    return nil
end


--- Append the horse's status (injured, retired, settling in) to an RLRM info list. Our stats
--- are not added: the game's Animals screen shows only five rows and RLRM's horse rows take
--- three, so they would not all fit; RLRM's menu and the look-at box show them.
--- @param animal table RLRM Animal (a horse)
--- @param infos table Rows shaped { title, value, ratio, valueText }
function EqInfoDisplay.addHorseInfos(animal, infos)
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return end

    local status = statusText(record, animal)
    if status ~= nil then
        table.insert(infos, { title = g_i18n:getText("eq_status_title"), text = "", value = 0, ratio = 0,
            valueText = status, eqBlock = true })
    end

    -- RLRM remakes its riding row's text every time, so this never stacks up.
    local riding = animal.infoRiding
    if EqInfoDisplay.isRidingFull(animal) and riding ~= nil and riding.valueText ~= nil then
        riding.valueText = string.format(g_i18n:getText("eq_ui_ridingFullValue"), riding.valueText)
    end
end


-- A full riding bar, in red wherever it shows: no more training today.
EqInfoDisplay.FULL_COLOR = { 1, 0.32, 0.25, 1 }


--- @param animal table|nil RLRM Animal
--- @return boolean true when the horse's riding bar is full for today, so it trains no more
function EqInfoDisplay.isRidingFull(animal)
    return animal ~= nil and (animal.riding or 0) >= 100
end


--- Fill the look-at Skills box: the role and a full riding bar first, then one line per stat,
--- the dealer's-view note and the status.
--- @param record table EqHorseRecord
--- @param box table HUD key-value box
--- @param animal table RLRM Animal
local function fillSkillsBox(record, box, animal)
    -- The game's plain box takes a warning flag where ours takes a colour.
    local colored = box.eqColored == true
    if EqRole.has(record) and not record.retired then
        box:addLine(g_i18n:getText("eq_role_title"), EqRole.text(EqRole.get(record)), colored and EqRole.COLOR or nil)
    end
    if EqInfoDisplay.isRidingFull(animal) then
        box:addLine(g_i18n:getText("eq_ui_riding"), g_i18n:getText("eq_ui_ridingFull"), colored and EqInfoDisplay.FULL_COLOR or nil)
    end
    local ceilings, unvetted, gains = record:getShownCeilings(), isUnvetted(record), recentGains(record)
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local trained = record.trained[stat] or 0
        if box.eqColored then
            local skill, skillColor = EqInfoDisplay.skillValue(trained, gains[stat], stat)
            local potentialColor = EqInfoDisplay.skillColor(ceilings[stat], stat)
            box:addLine(statTitle(stat), skill, skillColor,
                string.format("(%s)", EqInfoDisplay.potentialText(ceilings[stat], unvetted)), potentialColor,
                EqInfoDisplay.STAT_COLOR[stat])
        else
            box:addLine(statTitle(stat), statText(trained, ceilings[stat], unvetted, gains[stat]))
        end
    end
    box:addLine(g_i18n:getText("eq_specialty_title"), EqCompetitionManager.specialtyText(record))
    if unvetted then box:addLine(g_i18n:getText("eq_ui_potentialTitle"), g_i18n:getText("eq_ui_potentialDealer")) end
    local status = statusText(record, animal)
    if status ~= nil then box:addLine(g_i18n:getText("eq_status_title"), status) end
end


--- @param animal table|nil
--- @return boolean
local function isHorse(animal)
    return animal ~= nil and animal.isHorse ~= nil and animal:isHorse()
end


--- Appended to PlayerHUDUpdater:showAnimalInfo after RLRM's, so the Skills box is made after
--- RLRM's Genetics box and shows below it. Runs every frame while looking at an animal.
--- @param hudUpdater table PlayerHUDUpdater
--- @param animal table|nil RLRM Animal under the crosshair
function EqInfoDisplay.showSkillsBox(hudUpdater, animal)
    if not isHorse(animal) then return end
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return end

    if hudUpdater.eqSkillsBox == nil then
        -- Our coloured box when RLRM's box class is there to draw it like Genetics, else the
        -- game's plain one.
        local colored = EqSkillsHudBox.isAvailable()
        hudUpdater.eqSkillsBox = g_currentMission.hud.infoDisplay:createBox(colored and EqSkillsHudBox or InfoDisplayKeyValueBox)
        hudUpdater.eqSkillsBox.eqColored = colored
    end
    local box = hudUpdater.eqSkillsBox
    box:clear()
    box:setTitle(g_i18n:getText("eq_ui_skills"))
    fillSkillsBox(record, box, animal)
    box:showNextFrame()

    EqInfoDisplay.markAnimalBox(hudUpdater.objectBox, animal)
end


--- The base game's look-at box for the animal: its title says only "Animal", and the name is a
--- line among many. Head it with the horse's name instead, and say so when the riding bar is
--- full. That box draws every line white, so the red is on the Skills box.
--- @param box table|nil PlayerHUDUpdater.objectBox, filled for this animal this frame
--- @param animal table RLRM Animal (a horse)
function EqInfoDisplay.markAnimalBox(box, animal)
    if box == nil or type(box.lines) ~= "table" then return end
    local name = animal.getName ~= nil and animal:getName() or nil
    if name ~= nil and name ~= "" and box.setTitle ~= nil then box:setTitle(name) end

    if not EqInfoDisplay.isRidingFull(animal) then return end
    local key = g_i18n:getText("infohud_riding")
    for _, line in ipairs(box.lines) do
        if line.isActive and line.key == key and type(line.value) == "string" then
            line.value = string.format(g_i18n:getText("eq_ui_ridingFullValue"), line.value)
        end
    end
end


--- Move our stat rows together, to MENU_FIRST_ROW, drop Meat Quality from the genetics rows, and
--- swap the base game's horse blurb (sold for profit, ride daily to raise value) for a one-line
--- version that is true with this mod and leaves room for a pregnant mare's extra rows.
--- @param animal table RLRM Animal
--- @param display table|nil RLAnimalInfoService.getAnimalDisplay's result, changed in place
function EqInfoDisplay.arrangeMenuDisplay(animal, display)
    if display == nil or not isHorse(animal) then return end

    local rows = display.statRows
    if rows ~= nil and EqInfoDisplay.statsInSection then
        -- The stats have their own section, so the grid keeps only the status line.
        for i = #rows, 1, -1 do
            if rows[i].eqStat ~= nil then table.remove(rows, i) end
        end
    elseif rows ~= nil then
        local ours, others = {}, {}
        for _, row in ipairs(rows) do
            table.insert(row.eqBlock and ours or others, row)
        end
        if #ours > 0 then
            local at = math.min(EqInfoDisplay.MENU_FIRST_ROW, #others + 1)
            for i = #rows, 1, -1 do rows[i] = nil end
            for i, row in ipairs(others) do
                if i == at then for _, own in ipairs(ours) do table.insert(rows, own) end end
                table.insert(rows, row)
            end
            if at > #others then for _, own in ipairs(ours) do table.insert(rows, own) end end
        end
    end

    if display.description ~= nil and display.description ~= "" then
        display.description = g_i18n:getText("eq_ui_horseDescription")
    end

    if EqInfoDisplay.hideMeatQuality and display.geneticsRows ~= nil then
        for i = #display.geneticsRows, 1, -1 do
            if display.geneticsRows[i].labelKey == EqInfoDisplay.MEAT_LABEL_KEY then
                table.remove(display.geneticsRows, i)
            end
        end
    end
end




--- @param trained number
--- @return string valueText "54 - High", in RLRM's genetics style
--- @return table|nil color { r, g, b, a } from RLRM's genetics palette
function EqInfoDisplay.geneticsValue(trained)
    local bandKey = EqInfoDisplay.statBandKey(trained)
    local text = string.format("%d - %s", math.floor(trained + 0.5), g_i18n:getText(bandKey, EqRLRM.MOD_NAME))
    return text, EqInfoDisplay.bandColor(bandKey)
end


--- @param bandKey string RLRM's l10n key for a genetics band, such as "rl_ui_genetics_high"
--- @return table|nil color { r, g, b, a } from RLRM's genetics palette
function EqInfoDisplay.bandColor(bandKey)
    local formatter = EqRLRM.get("RLGeneticsFormatter")
    local helper = EqRLRM.get("RLDetailPaneHelper")
    local colorKey = formatter ~= nil and formatter.VALUE_KEY_TO_COLOR_KEY ~= nil and formatter.VALUE_KEY_TO_COLOR_KEY[bandKey] or nil
    return colorKey ~= nil and helper ~= nil and helper.GENETICS_COLOR ~= nil and helper.GENETICS_COLOR[colorKey] or nil
end


--- @param element table
--- @return number height the element's height plus its top and bottom margins
local function outerHeight(element)
    local margin = element.margin or { 0, 0, 0, 0 }
    return element.size[2] + (margin[2] or 0) + (margin[4] or 0)
end


--- @param column table a vertical BoxLayout
--- @return number height of its visible children stacked
local function contentHeight(column)
    local height = 0
    for _, child in ipairs(column.elements) do
        if child.visible then height = height + outerHeight(child) end
    end
    return height
end


--- Set an element's height, remembering RLRM's own so it can be put back.
--- @param element table
--- @param height number|nil nil restores RLRM's height
local function setHeight(element, height)
    if element.eqHeight == nil then element.eqHeight = element.size[2] end
    height = height or element.eqHeight
    if element.size[2] ~= height then element:setSize(element.size[1], height) end
end


--- Fit a row of columns (RLRM's Pedigree/Genetics row, or ours) to its tallest column, with
--- some space to spare (half a line unless told otherwise).
--- @param row table horizontal BoxLayout of vertical BoxLayouts
--- @param line number one info row's height
--- @param spare number|nil
local function fitRow(row, line, spare)
    local tallest = 0
    for _, column in ipairs(row.elements) do
        if column.visible and column.elements ~= nil then
            local height = contentHeight(column)
            setHeight(column, height)
            tallest = math.max(tallest, height)
        end
    end
    if tallest > 0 then setHeight(row, tallest + (spare or line / 2)) end
end


--- Build the Skill potential / Skills section once per frame: a clone of RLRM's
--- Pedigree/Genetics row, placed right after it, with two copies of the Genetics column.
--- @param frame table RLRM menu frame
--- @return table|nil section { row, potential = column, skills = column }
local function ensureSection(frame)
    if frame.eqSkills ~= nil then return frame.eqSkills end
    local source, genetics = frame.animalColumnsRow, frame.geneticsColumn
    if source == nil or genetics == nil or source.parent == nil or source.clone == nil then return nil end

    local scroll = source.parent
    local row = source:clone(scroll, false, true)
    -- Move it from the end of the pane to just after Pedigree/Genetics.
    for i, element in ipairs(scroll.elements) do
        if element == row then table.remove(scroll.elements, i) break end
    end
    for i, element in ipairs(scroll.elements) do
        if element == source then table.insert(scroll.elements, i + 1, row) break end
    end

    -- Keep only the Genetics column's clone, then copy it for the right-hand column.
    local potential
    for i = #row.elements, 1, -1 do
        local column = row.elements[i]
        if i == #row.elements then potential = column else column:delete() end
    end
    if potential == nil then return nil end
    local skills = potential:clone(row, false, true)

    local section = { row = row, potential = potential, skills = skills }
    potential.elements[1]:setText(g_i18n:getText("eq_ui_skillPotential"))
    skills.elements[1]:setText(g_i18n:getText("eq_ui_skills"))
    -- Each column has one more line than the stats: the horse's role, and its favourite event.
    for i, column in ipairs({ potential, skills }) do
        local lines = #EqConstants.STAT_KEYS + 1
        for index = 2, #column.elements do
            column.elements[index]:setVisible(index - 1 <= lines)
        end
    end
    frame.eqSkills = section
    return section
end


--- @param cell table an info row: label, value
--- @param title string
--- @param text string
--- @param color table|nil for the value, and the title when titleColor is nil
--- @param titleColor table|nil
local function fillCell(cell, title, text, color, titleColor)
    local label, value = cell.elements[1], cell.elements[2]
    label:setText(title)
    value:setText(text)
    titleColor = titleColor or color
    if titleColor ~= nil and label.setTextColor ~= nil then label:setTextColor(unpack(titleColor)) end
    if color ~= nil and value.setTextColor ~= nil then value:setTextColor(unpack(color)) end
end


--- Shrink RLRM's stat grid to the lines it shows (or give it back its height).
--- @param frame table
--- @param shrink boolean
local function fitGrid(frame, shrink)
    local first = frame.statRow ~= nil and frame.statRow[1] or nil
    local grid = first ~= nil and first.parent or nil
    if grid == nil or grid.setSize == nil then return end
    if not shrink then setHeight(grid, nil) return end

    local shown = 0
    for _, cell in ipairs(frame.statRow) do
        if cell.visible then shown = shown + 1 end
    end
    local lines = math.ceil(shown / 2)
    local full = EqInfoDisplay.GRID_PADDING + EqInfoDisplay.GRID_LINES * EqInfoDisplay.GRID_LINE
    if grid.eqHeight == nil then grid.eqHeight = grid.size[2] end
    setHeight(grid, grid.eqHeight * (EqInfoDisplay.GRID_PADDING + lines * EqInfoDisplay.GRID_LINE) / full)
end


--- Fit RLRM's Information box to its text (or give it back its height). RLRM sizes it for four
--- lines; the horse blurb is one, so the rest was empty space pushing the skills off the pane.
--- The text element itself keeps RLRM's 100px whatever it shows, so it is cut to its lines too:
--- without that a pregnant mare's three extra rows pushed the Skills box off the bottom.
--- @param frame table
--- @param fit boolean
--- @param line number one info row's height
local function fitDescription(frame, fit, line)
    local section = frame.descriptionSection
    if section == nil or section.setSize == nil or section.elements == nil then return end
    local text = frame.animalDescriptionText
    local canFitText = text ~= nil and text.setSize ~= nil and text.getTextHeight ~= nil
    if not fit then
        if canFitText then setHeight(text, nil) end
        setHeight(section, nil)
        return
    end
    if canFitText then
        if text.eqHeight == nil then text.eqHeight = text.size[2] end
        local height = text:getTextHeight()
        if height ~= nil and height > 0 then setHeight(text, math.min(height, text.eqHeight)) end
    end
    if section.invalidateLayout ~= nil then section:invalidateLayout() end
    local height = contentHeight(section)
    if height > 0 then setHeight(section, math.min(height + line / 2, section.eqHeight or section.size[2])) end
end


EqInfoDisplay.NO_ROLE_COLOR = { 0.6, 0.6, 0.6, 1 }


--- Turn the Daily riding value in RLRM's stat grid red while the bar is full, and give every
--- other value back the colour it had.
--- @param frame table RLRM menu frame
--- @param animal table|nil
function EqInfoDisplay.colorRiding(frame, animal)
    if type(frame.statLabel) ~= "table" or type(frame.statValue) ~= "table" then return end
    local full = isHorse(animal) and EqInfoDisplay.isRidingFull(animal)
    local title = g_i18n:getText("ui_horseDailyRiding")
    for index, value in pairs(frame.statValue) do
        local label = frame.statLabel[index]
        if value.setTextColor ~= nil and type(value.textColor) == "table" then
            if value.eqColor == nil then value.eqColor = { unpack(value.textColor) } end
            local red = full and label ~= nil and label.text == title
            value:setTextColor(unpack(red and EqInfoDisplay.FULL_COLOR or value.eqColor))
        end
    end
end


--- Appended to RLDetailPaneHelper.updateAnimalDisplay: fill the Skill potential / Skills section
--- for a horse, or hide it and put RLRM's layout back for any other animal.
--- @param frame table RLRM menu frame
--- @param animal table|nil
function EqInfoDisplay.renderSkills(frame, animal)
    EqInfoDisplay.colorRiding(frame, animal)
    local record = isHorse(animal) and EqRegistry.getOrCreate(animal) or nil
    local section = record ~= nil and ensureSection(frame) or frame.eqSkills

    if section ~= nil then section.row:setVisible(record ~= nil) end
    fitGrid(frame, record ~= nil and section ~= nil)

    local columnsRow = frame.animalColumnsRow
    if record == nil or section == nil then
        if columnsRow ~= nil and columnsRow.eqHeight ~= nil then
            for _, column in ipairs(columnsRow.elements) do
                if column.eqHeight ~= nil then setHeight(column, nil) end
            end
            setHeight(columnsRow, nil)
        end
        fitDescription(frame, false)
    else
        local ceilings, unvetted, gains = record:getShownCeilings(), isUnvetted(record), recentGains(record)
        section.potential.elements[1]:setText(g_i18n:getText(unvetted and "eq_ui_skillPotentialDealer" or "eq_ui_skillPotential"))
        for i, stat in ipairs(EqConstants.STAT_KEYS) do
            local potentialColor = EqInfoDisplay.skillColor(ceilings[stat], stat)
            local statColor = EqInfoDisplay.STAT_COLOR[stat]
            fillCell(section.potential.elements[i + 1], statTitle(stat),
                EqInfoDisplay.potentialText(ceilings[stat], unvetted), potentialColor, statColor)
            local text, color = EqInfoDisplay.skillValue(record.trained[stat] or 0, gains[stat], stat)
            fillCell(section.skills.elements[i + 1], statTitle(stat), text, color, statColor)
        end
        local specialtyCell = section.skills.elements[#EqConstants.STAT_KEYS + 2]
        if specialtyCell ~= nil then
            fillCell(specialtyCell, g_i18n:getText("eq_specialty_title"), EqCompetitionManager.specialtyText(record))
        end
        local roleCell = section.potential.elements[#EqConstants.STAT_KEYS + 2]
        if roleCell ~= nil then
            local role = EqRole.shown(record)
            fillCell(roleCell, g_i18n:getText("eq_role_title"), EqRole.text(role),
                EqRole.isShown(record) and EqRole.COLOR or EqInfoDisplay.NO_ROLE_COLOR, EqRole.COLOR)
        end

        local line = section.potential.elements[2].size[2]
        fitDescription(frame, true, line)
        if columnsRow ~= nil then
            for _, column in ipairs(columnsRow.elements) do
                if column.invalidateLayout ~= nil then column:invalidateLayout() end
            end
            fitRow(columnsRow, line)
        end
        section.potential:invalidateLayout()
        section.skills:invalidateLayout()
        -- Last on the pane, so it only needs a little room below it.
        fitRow(section.row, line, line / 4)
        section.row:invalidateLayout()
    end

    local scroll = columnsRow ~= nil and columnsRow.parent or nil
    if scroll ~= nil and scroll.invalidateLayout ~= nil then scroll:invalidateLayout() end
end


--- The Meat Quality title as RLRM writes it.
--- @return string
local function meatTitle()
    return g_i18n:getText(EqInfoDisplay.MEAT_LABEL_KEY, EqRLRM.MOD_NAME)
end


--- Run RLRM's showGeneticsInfo with the Meat Quality line filtered out of the box.
--- @param original function Animal.showGeneticsInfo
--- @param animal table
--- @param box table HUD key/value box
function EqInfoDisplay.showGeneticsWithoutMeat(original, animal, box)
    local own = rawget(box, "addLine")
    local addLine = box.addLine
    local skip = meatTitle()
    box.addLine = function(target, title, ...)
        if title == skip then return end
        return addLine(target, title, ...)
    end
    local ok, err = pcall(original, animal, box)
    box.addLine = own
    if not ok then error(err, 0) end
end


--- Read the meat quality preference from modSettings.
function EqInfoDisplay.loadPreferences()
    if settingsDirectory == nil then return end
    local xmlFile = XMLFile.loadIfExists("eqPreferences", settingsDirectory .. "preferences.xml")
    if xmlFile == nil then return end
    EqInfoDisplay.hideMeatQuality = xmlFile:getBool("preferences.display#hideMeatQuality", EqInfoDisplay.hideMeatQuality)
    xmlFile:delete()
end


--- Save the meat quality preference to modSettings.
function EqInfoDisplay.savePreferences()
    if settingsDirectory == nil then return end
    createFolder(settingsDirectory)
    local xmlFile = XMLFile.create("eqPreferences", settingsDirectory .. "preferences.xml", "preferences")
    if xmlFile == nil then return end
    xmlFile:setBool("preferences.display#hideMeatQuality", EqInfoDisplay.hideMeatQuality)
    xmlFile:save()
    xmlFile:delete()
end


--- Hook RLRM's menu layout and genetics box: the stat block's position and Meat Quality.
--- Call once, after EqRLRM.init succeeded with the menuLayout feature.
--- @param guarded function main.lua's error guard
function EqInfoDisplay.installMenu(guarded)
    guarded("display preferences", EqInfoDisplay.loadPreferences)

    local infoService = EqRLRM.get("RLAnimalInfoService")
    local getAnimalDisplay = infoService.getAnimalDisplay
    infoService.getAnimalDisplay = function(animal, husbandry, ...)
        local display = getAnimalDisplay(animal, husbandry, ...)
        guarded("menu layout", function() EqInfoDisplay.arrangeMenuDisplay(animal, display) end)
        return display
    end

    if EqRLRM.features.menuGenetics then
        local helper = EqRLRM.get("RLDetailPaneHelper")
        helper.updateAnimalDisplay = Utils.appendedFunction(helper.updateAnimalDisplay, function(frame, animal)
            guarded("skills section", function() EqInfoDisplay.renderSkills(frame, animal) end)
        end)
        EqInfoDisplay.statsInSection = true
    end

    local animalClass = EqRLRM.get("Animal")
    local showGeneticsInfo = animalClass.showGeneticsInfo
    animalClass.showGeneticsInfo = function(animal, box, ...)
        if EqInfoDisplay.hideMeatQuality and EqMain.isActive and isHorse(animal) then
            return EqInfoDisplay.showGeneticsWithoutMeat(showGeneticsInfo, animal, box)
        end
        return showGeneticsInfo(animal, box, ...)
    end

    Log:debug("EqInfoDisplay: hooked RLAnimalInfoService.getAnimalDisplay and Animal.showGeneticsInfo")
end


--- Hook RLRM's horse display functions. Call once, after EqRLRM.init succeeded.
--- @param guarded function main.lua's error guard, so a display bug never breaks RLRM's panel
function EqInfoDisplay.install(guarded)
    local animalHorse = EqRLRM.get("AnimalHorse")

    animalHorse.addHorseInfos = Utils.appendedFunction(animalHorse.addHorseInfos, function(animal, infos)
        guarded("horse info rows", function() EqInfoDisplay.addHorseInfos(animal, infos) end)
    end)

    PlayerHUDUpdater.showAnimalInfo = Utils.appendedFunction(PlayerHUDUpdater.showAnimalInfo, function(hudUpdater, animal)
        guarded("horse skills box", function() EqInfoDisplay.showSkillsBox(hudUpdater, animal) end)
    end)
    PlayerHUDUpdater.delete = Utils.prependedFunction(PlayerHUDUpdater.delete, function(hudUpdater)
        if hudUpdater.eqSkillsBox ~= nil then
            g_currentMission.hud.infoDisplay:destroyBox(hudUpdater.eqSkillsBox)
            hudUpdater.eqSkillsBox = nil
        end
    end)

    -- The Esc > Animals page shows the base game's stallion text, which still lists sorghum.
    if InGameMenuAnimalsFrame ~= nil and InGameMenuAnimalsFrame.displayCluster ~= nil then
        InGameMenuAnimalsFrame.displayCluster = Utils.appendedFunction(InGameMenuAnimalsFrame.displayCluster,
            function(frame, animal)
                guarded("animals page description", function()
                    if isHorse(animal) and frame.detailDescriptionText ~= nil then
                        frame.detailDescriptionText:setText(g_i18n:getText("eq_ui_horseDescription"))
                    end
                end)
            end)
    end

    Log:debug("EqInfoDisplay: hooked AnimalHorse.addHorseInfos and PlayerHUDUpdater.showAnimalInfo")
end

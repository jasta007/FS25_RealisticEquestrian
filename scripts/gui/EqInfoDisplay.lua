--[[
    EqInfoDisplay.lua
    Shows the four stats wherever RLRM already shows a horse's fitness and riding.

    A player sees each stat's trained level as a number, and its potential (the ceiling) only
    as RLRM's genetics word (Average, High, Very high...), on our own ladder that follows the
    event tiers (STAT_BANDS). The exact ceiling stays hidden, as a real owner could only judge it.

    - AnimalHorse.addHorseInfos feeds the stat rows of RLRM's menu and the pen's animal screen:
      a bar of the trained level with "54 (High)" as its text.
    - AnimalHorse.showHorseHudInfo feeds the info box you get when looking at a horse, the same
      "54 (High)".

    In RLRM's menu the two halves are split, as James asked:
    - The stat grid shows potential: our rows become "Stamina potential  High" and move up to
      its second and third lines, where the grid's ten slots never push them off.
    - The Genetics column shows the trained level like RLRM's own rows, "54 - High", label and
      value coloured on RLRM's red-to-green scale. The column has six rows in RLRM's XML, so the
      first time a frame shows a horse we clone its last row for the extra slots. RLRM's loop
      only touches rows 1-6, and ours are hidden for other animals.

    Meat quality: for horses only, RLRM's Meat Quality row is taken out of the menu's genetics
    column and the look-at genetics box. It is a display preference, saved per machine in
    modSettings, and eqMeatQuality show|hide switches it. RLRM's own data is never changed.
]]

EqInfoDisplay = {}

-- Index our stat block starts at in the menu's grid: after Age and one RLRM row, so it fills
-- two whole lines (Stamina | Speed, Agility | Temperament). Only used when the stats cannot go
-- in the Genetics column.
EqInfoDisplay.MENU_FIRST_ROW = 3

-- True once RLDetailPaneHelper.updateAnimalDisplay is hooked: trained levels then live in the
-- Genetics column and the stat grid shows potential only.
EqInfoDisplay.statsInGenetics = false

EqInfoDisplay.MEAT_LABEL_KEY = "rl_ui_meat"
EqInfoDisplay.hideMeatQuality = true

local Log = EqLog
local settingsDirectory = g_currentModSettingsDirectory


--- @param stat string
--- @return string title
local function statTitle(stat)
    return g_i18n:getText("eq_stat_" .. stat)
end


-- Our own ladder for a 0-100 stat, in RLRM's words and colours. It follows the event tiers
-- rather than RLRM's gene scale: Average is a Novice horse, High an Intermediate one, Very high
-- Advanced and Extremely high Championship class. Used for both potential (the ceiling) and
-- trained level, so a horse trained to its potential shows the same word for both.
EqInfoDisplay.STAT_BANDS = {
    { from = 85, key = "rl_ui_genetics_extremelyHigh" },
    { from = 70, key = "rl_ui_genetics_veryHigh" },
    { from = 55, key = "rl_ui_genetics_high" },
    { from = 40, key = "rl_ui_genetics_average" },
    { from = 30, key = "rl_ui_genetics_low" },
    { from = 20, key = "rl_ui_genetics_veryLow" },
    { from = -math.huge, key = "rl_ui_genetics_extremelyLow" },
}


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
--- @return string text such as "54 (High)"
local function statText(trained, ceiling, unvetted)
    return string.format("%d (%s)", math.floor(trained + 0.5), EqInfoDisplay.potentialText(ceiling, unvetted))
end


--- @param record table
--- @return string|nil text "Injured, 3 month(s)", "Retired" or "Settling in", nil for a horse in work
local function statusText(record)
    if record.injury ~= nil then return string.format(g_i18n:getText("eq_status_injured"), record.injury.monthsLeft) end
    if record.retired then return g_i18n:getText("eq_status_retired") end
    if record:isSettling() then return g_i18n:getText("eq_status_settling") end
    return nil
end


--- Append one row per stat to an RLRM info list.
--- @param animal table RLRM Animal (a horse)
--- @param infos table Rows shaped { title, value, ratio, valueText }
function EqInfoDisplay.addHorseInfos(animal, infos)
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return end

    local ceilings, unvetted = record:getShownCeilings(), isUnvetted(record)
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local trained = record.trained[stat] or 0
        local ratio = EqStats.clamp(trained / 100, 0, 1)
        table.insert(infos, {
            title = statTitle(stat),
            text = "",
            value = ratio,
            ratio = ratio,
            valueText = statText(trained, ceilings[stat], unvetted),
            eqStat = stat,
            eqCeiling = ceilings[stat],
            eqUnvetted = unvetted,
            eqBlock = true,
        })
    end

    local status = statusText(record)
    if status ~= nil then
        table.insert(infos, { title = g_i18n:getText("eq_status_title"), text = "", value = 0, ratio = 0,
            valueText = status, eqBlock = true })
    end
end


--- Append one line per stat to the look-at info box.
--- @param animal table RLRM Animal (a horse)
--- @param box table HUD info box
function EqInfoDisplay.showHorseHudInfo(animal, box)
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return end

    local ceilings, unvetted = record:getShownCeilings(), isUnvetted(record)
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        box:addLine(statTitle(stat), statText(record.trained[stat] or 0, ceilings[stat], unvetted))
    end
    local status = statusText(record)
    if status ~= nil then box:addLine(g_i18n:getText("eq_status_title"), status) end
end


--- @param animal table|nil
--- @return boolean
local function isHorse(animal)
    return animal ~= nil and animal.isHorse ~= nil and animal:isHorse()
end


--- Move our stat rows together, to MENU_FIRST_ROW, and drop Meat Quality from the genetics rows.
--- @param animal table RLRM Animal
--- @param display table|nil RLAnimalInfoService.getAnimalDisplay's result, changed in place
function EqInfoDisplay.arrangeMenuDisplay(animal, display)
    if display == nil or not isHorse(animal) then return end

    local rows = display.statRows
    if rows ~= nil and EqInfoDisplay.statsInGenetics then
        -- Trained levels are in the Genetics column, so the grid shows potential only.
        for _, row in ipairs(rows) do
            if row.eqStat ~= nil then
                row.title = g_i18n:getText("eq_potential_" .. row.eqStat)
                row.valueText = EqInfoDisplay.potentialText(row.eqCeiling, row.eqUnvetted)
            end
        end
    end
    if rows ~= nil then
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

    local formatter = EqRLRM.get("RLGeneticsFormatter")
    local helper = EqRLRM.get("RLDetailPaneHelper")
    local colorKey = formatter ~= nil and formatter.VALUE_KEY_TO_COLOR_KEY ~= nil and formatter.VALUE_KEY_TO_COLOR_KEY[bandKey] or nil
    local color = colorKey ~= nil and helper.GENETICS_COLOR ~= nil and helper.GENETICS_COLOR[colorKey] or nil
    return text, color
end


--- Make sure a frame's Genetics column has at least `count` rows, cloning its last one.
--- @param frame table RLRM menu frame
--- @param count number
--- @return boolean ok
local function ensureGeneticsRows(frame, count)
    local rows, labels, values = frame.geneticsRow, frame.geneticsLabel, frame.geneticsValue
    if rows == nil or labels == nil or values == nil or #rows == 0 then return false end

    while #rows < count do
        local template = rows[#rows]
        if template.parent == nil or template.clone == nil then return false end
        local row = template:clone(template.parent, false, true)
        local label, value = row.elements[1], row.elements[2]
        if label == nil or value == nil then
            row:setVisible(false)
            return false
        end
        table.insert(rows, row)
        labels[#rows] = label
        values[#rows] = value
    end
    return true
end


--- Appended to RLDetailPaneHelper.updateAnimalDisplay: fill the Genetics column rows after
--- RLRM's own with the four stats, or hide our extra rows for any other animal.
--- @param frame table RLRM menu frame
--- @param animal table|nil
function EqInfoDisplay.renderGenetics(frame, animal)
    local rows = frame.geneticsRow
    if rows == nil then return end
    local rlrmRows = EqRLRM.get("RLDetailPaneHelper").NUM_GENETICS_ROWS or 6

    local record = isHorse(animal) and EqRegistry.getOrCreate(animal) or nil
    local first = nil
    if record ~= nil then
        -- RLRM shows its rows from the top and hides the rest; ours follow the last shown one.
        first = 1
        while first <= rlrmRows and rows[first] ~= nil and rows[first].visible do first = first + 1 end
        if not ensureGeneticsRows(frame, first + #EqConstants.STAT_KEYS - 1) then record = nil end
    end

    if record ~= nil then
        for i, stat in ipairs(EqConstants.STAT_KEYS) do
            local index = first + i - 1
            local label, value = frame.geneticsLabel[index], frame.geneticsValue[index]
            local text, color = EqInfoDisplay.geneticsValue(record.trained[stat] or 0)
            rows[index]:setVisible(true)
            label:setText(statTitle(stat))
            value:setText(text)
            if color ~= nil then
                if label.setTextColor ~= nil then label:setTextColor(unpack(color)) end
                if value.setTextColor ~= nil then value:setTextColor(unpack(color)) end
            end
        end
        first = first + #EqConstants.STAT_KEYS
    else
        first = rlrmRows + 1
    end

    for index = first, #rows do
        if index > rlrmRows then rows[index]:setVisible(false) end
    end

    local column = rows[1].parent
    if column ~= nil and column.invalidateLayout ~= nil then column:invalidateLayout() end
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
            guarded("genetics column", function() EqInfoDisplay.renderGenetics(frame, animal) end)
        end)
        EqInfoDisplay.statsInGenetics = true
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

    animalHorse.showHorseHudInfo = Utils.appendedFunction(animalHorse.showHorseHudInfo, function(animal, box)
        guarded("horse info box", function() EqInfoDisplay.showHorseHudInfo(animal, box) end)
    end)

    Log:debug("EqInfoDisplay: hooked AnimalHorse.addHorseInfos and showHorseHudInfo")
end

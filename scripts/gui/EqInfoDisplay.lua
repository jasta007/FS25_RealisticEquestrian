--[[
    EqInfoDisplay.lua
    Shows the four stats wherever RLRM already shows a horse's fitness and riding:

    - AnimalHorse.addHorseInfos feeds the stat rows of RLRM's menu (Info, Sell and Buy tabs)
      and the pen's animal screen. Each stat becomes a bar of trained level out of 100, with
      "trained / ceiling" as its text.
    - AnimalHorse.showHorseHudInfo feeds the info box you get when looking at a horse.

    Both are RLRM functions that run for horses only, so appending to them adds our rows in
    the right place without touching any other animal or any RLRM file.

    In RLRM's menu the four stats go in the Genetics column instead, styled like RLRM's own
    rows: "54 / 77 - High", label and value coloured by the band of the horse's potential
    (its ceiling, read back as a gene on RLRM's scale). The column has six rows in RLRM's XML,
    so the first time a frame shows a horse we clone the last row for the extra slots we
    need. RLRM's own loop only ever touches rows 1-6, and ours are hidden for other animals.
    A wrap on RLAnimalInfoService.getAnimalDisplay takes our rows out of the stat grid there,
    so they are not shown twice. If the column hook is unavailable they stay in the grid,
    moved up to its second and third lines.

    Meat quality: for horses only, RLRM's Meat Quality row is taken out of the menu's genetics
    column and the look-at genetics box. It is a display preference, saved per machine in
    modSettings, and eqMeatQuality show|hide switches it. RLRM's own data is never changed.
]]

EqInfoDisplay = {}

-- Index our stat block starts at in the menu's grid: after Age and one RLRM row, so it fills
-- two whole lines (Stamina | Speed, Agility | Temperament). Only used when the stats cannot go
-- in the Genetics column.
EqInfoDisplay.MENU_FIRST_ROW = 3

-- True once RLDetailPaneHelper.updateAnimalDisplay is hooked: the stats then live in the
-- Genetics column, not the stat grid.
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


--- @param trained number
--- @param ceiling number
--- @return string text such as "54 / 77"
local function statText(trained, ceiling)
    return string.format("%d / %d", math.floor(trained + 0.5), math.floor(ceiling + 0.5))
end


--- Append one row per stat to an RLRM info list.
--- @param animal table RLRM Animal (a horse)
--- @param infos table Rows shaped { title, value, ratio, valueText }
function EqInfoDisplay.addHorseInfos(animal, infos)
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return end

    local ceilings = record:getCeilings()
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local trained = record.trained[stat] or 0
        local ratio = EqStats.clamp(trained / 100, 0, 1)
        table.insert(infos, {
            title = statTitle(stat),
            text = "",
            value = ratio,
            ratio = ratio,
            valueText = statText(trained, ceilings[stat]),
            eqStat = stat,
        })
    end
end


--- Append one line per stat to the look-at info box.
--- @param animal table RLRM Animal (a horse)
--- @param box table HUD info box
function EqInfoDisplay.showHorseHudInfo(animal, box)
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return end

    local ceilings = record:getCeilings()
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        box:addLine(statTitle(stat), statText(record.trained[stat] or 0, ceilings[stat]))
    end
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
        for i = #rows, 1, -1 do
            if rows[i].eqStat ~= nil then table.remove(rows, i) end
        end
    elseif rows ~= nil then
        local ours, others = {}, {}
        for _, row in ipairs(rows) do
            table.insert(row.eqStat ~= nil and ours or others, row)
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
--- @param ceiling number
--- @return string valueText "54 / 77 - High"
--- @return table|nil color { r, g, b, a } from RLRM's genetics palette
function EqInfoDisplay.geneticsValue(trained, ceiling)
    local gene = EqStats.clampGene((ceiling - EqConstants.CEILING_BASE) / EqConstants.CEILING_PER_GENE)
    local bandKey = EqRLRM.get("RLGenetics").perTrait(gene)
    local text = string.format("%s - %s", statText(trained, ceiling), g_i18n:getText(bandKey, EqRLRM.MOD_NAME))

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
        local ceilings = record:getCeilings()
        for i, stat in ipairs(EqConstants.STAT_KEYS) do
            local index = first + i - 1
            local label, value = frame.geneticsLabel[index], frame.geneticsValue[index]
            local text, color = EqInfoDisplay.geneticsValue(record.trained[stat] or 0, ceilings[stat])
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

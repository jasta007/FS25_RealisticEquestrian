--[[
    EqInfoDisplay.lua
    Shows the four stats wherever RLRM already shows a horse's fitness and riding:

    - AnimalHorse.addHorseInfos feeds the stat rows of RLRM's menu (Info, Sell and Buy tabs)
      and the pen's animal screen. Each stat becomes a bar of trained level out of 100, with
      "trained / ceiling" as its text.
    - AnimalHorse.showHorseHudInfo feeds the info box you get when looking at a horse.

    Both are RLRM functions that run for horses only, so appending to them adds our rows in
    the right place without touching any other animal or any RLRM file.

    In RLRM's menu the stat rows sit in a 2 x 5 grid that drops whatever does not fit, so a
    wrap on RLAnimalInfoService.getAnimalDisplay moves our four rows up to the second and third
    lines, where they always show and read as one block.

    Meat quality: for horses only, RLRM's Meat Quality row is taken out of the menu's genetics
    column and the look-at genetics box. It is a display preference, saved per machine in
    modSettings, and eqMeatQuality show|hide switches it. RLRM's own data is never changed.
]]

EqInfoDisplay = {}

-- Index our stat block starts at in the menu's grid: after Age and one RLRM row, so it fills
-- two whole lines (Stamina | Speed, Agility | Temperament).
EqInfoDisplay.MENU_FIRST_ROW = 3

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
    if rows ~= nil then
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

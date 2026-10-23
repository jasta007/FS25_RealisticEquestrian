--[[
    EqInfoDisplay.lua
    Shows the four stats wherever RLRM already shows a horse's fitness and riding:

    - AnimalHorse.addHorseInfos feeds the stat rows of RLRM's menu (Info, Sell and Buy tabs)
      and the pen's animal screen. Each stat becomes a bar of trained level out of 100, with
      "trained / ceiling" as its text.
    - AnimalHorse.showHorseHudInfo feeds the info box you get when looking at a horse.

    Both are RLRM functions that run for horses only, so appending to them adds our rows in
    the right place without touching any other animal or any RLRM file.
]]

EqInfoDisplay = {}

local Log = EqLog


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

--[[
    EqConsole.lua
    Developer console commands. Open the console with the tilde key (needs
    <development><controls>true</controls></development> in game.xml).
]]

EqConsole = {}

local Log = EqLog


--- Format one stat as "trained/ceiling (RLRM band of the gene)".
local function formatStat(record, ceilings, stat)
    return string.format("%-12s %3.0f/%3.0f %-16s  ", stat, record.trained[stat] or 0, ceilings[stat],
        "(" .. EqRLRM.geneBandText(record.genes[stat]) .. ")")
end


--- eqHorses: print every horse on the player's farm with its four stats.
function EqConsole:consoleListHorses()
    if g_currentMission == nil then return "No mission loaded" end

    local farmId = g_currentMission:getFarmId()
    local horses = EqRLRM.listHorsesForFarm(farmId)
    if #horses == 0 then return string.format("No horses on farm %s", tostring(farmId)) end

    for _, animal in ipairs(horses) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil then
            local ceilings = record:getCeilings()
            local total = 0
            for _, stat in ipairs(EqConstants.STAT_KEYS) do total = total + ceilings[stat] end

            print(string.format("%s '%s' age %dm  budget %.0f/%.0f", record.id, animal:getName() or "",
                animal.age or 0, total, EqStats.budgetFromGene(record.budgetGene)))
            print("    " .. formatStat(record, ceilings, "stamina") .. formatStat(record, ceilings, "speed"))
            print("    " .. formatStat(record, ceilings, "agility") .. formatStat(record, ceilings, "temperament"))
        end
    end

    return string.format("%d horse(s), %d record(s) in the registry", #horses, EqRegistry.count())
end


function EqConsole.register()
    addConsoleCommand("eqHorses", "Lists your horses' Realistic Equestrian stats", "consoleListHorses", EqConsole)
    Log:debug("EqConsole: commands registered")
end


function EqConsole.unregister()
    removeConsoleCommand("eqHorses")
end

--[[
    EqConsole.lua
    Developer console commands. Open the console with the tilde key (needs
    <development><controls>true</controls></development> in game.xml).
]]

EqConsole = {}

local Log = EqLog


--- Format one stat as "trained/ceiling (RLRM band of the gene)".
local function formatStat(record, ceilings, stat)
    return string.format("%-12s %5.1f/%3.0f %-16s  ", stat, record.trained[stat] or 0, ceilings[stat],
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

            print(string.format("%s '%s' age %dm %s  budget %.0f/%.0f", record.id, animal:getName() or "",
                animal.age or 0, record.origin, total, EqStats.budgetFromGene(record.budgetGene)))
            print("    " .. formatStat(record, ceilings, "stamina") .. formatStat(record, ceilings, "speed"))
            print("    " .. formatStat(record, ceilings, "agility") .. formatStat(record, ceilings, "temperament"))
        end
    end

    return string.format("%d horse(s), %d record(s) in the registry", #horses, EqRegistry.count())
end


--- @param animal table
--- @param record table
--- @param query string
--- @return boolean matches when query is the horse's name or identifier, ignoring case
local function matchesHorse(animal, record, query)
    query = string.lower(query)
    local name = animal.getName ~= nil and animal:getName() or nil
    return string.lower(record.id) == query or (name ~= nil and string.lower(name) == query)
end


--- eqTraining: each horse's focus, idle days and today's riding so far.
function EqConsole:consoleTraining()
    if g_currentMission == nil then return "No mission loaded" end

    local horses = EqRLRM.listHorsesForFarm(g_currentMission:getFarmId())
    for _, animal in ipairs(horses) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil then
            local sheet = EqTrainingHooks.sheets[record.id]
            local effort = EqTraining.playerEffort(sheet)
            print(string.format("%s '%s' focus=%s idle=%dd riding=%s (yours %.0f)  today: sta %.0f%% spd %.0f%% agi %.0f%% tem %.0f%%  jumps %d",
                record.id, animal:getName() or "", record.focus, record.idleDays or 0, tostring(animal.riding),
                EqTraining.playerRidingPoints(sheet), effort.stamina * 100, effort.speed * 100,
                effort.agility * 100, effort.temperament * 100, sheet ~= nil and sheet.jumps or 0))
        end
    end

    return string.format("%d horse(s). Staff train to the focus up to %d%% of each ceiling.", #horses,
        EqConstants.STAFF_CAP * 100)
end


--- eqFocus <name or id> <focus>: what staff train this horse for.
function EqConsole:consoleSetFocus(...)
    local args = { ... }
    local focus = args[#args]
    local usage = "Usage: eqFocus <horse name or id> <" .. table.concat(EqTraining.FOCUS_ORDER, "|") .. ">"
    if #args < 2 or EqTraining.FOCUS[focus] == nil then return usage end
    if g_currentMission == nil then return "No mission loaded" end
    if not g_currentMission:getIsServer() then return "Only the host can change focus for now" end

    local query = table.concat(args, " ", 1, #args - 1)
    for _, animal in ipairs(EqRLRM.listHorsesForFarm(g_currentMission:getFarmId())) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil and matchesHorse(animal, record, query) then
            record.focus = focus
            return string.format("%s '%s' now trains for %s", record.id, animal:getName() or "", focus)
        end
    end

    return string.format("No horse called '%s' on your farm. %s", query, usage)
end


function EqConsole.register()
    addConsoleCommand("eqHorses", "Lists your horses' Realistic Equestrian stats", "consoleListHorses", EqConsole)
    addConsoleCommand("eqTraining", "Shows each horse's training focus and today's riding", "consoleTraining", EqConsole)
    addConsoleCommand("eqFocus", "Sets what staff train a horse for: eqFocus <name or id> <focus>", "consoleSetFocus", EqConsole)
    Log:debug("EqConsole: commands registered")
end


function EqConsole.unregister()
    removeConsoleCommand("eqHorses")
    removeConsoleCommand("eqTraining")
    removeConsoleCommand("eqFocus")
end

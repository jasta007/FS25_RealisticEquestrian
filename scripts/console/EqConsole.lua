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

            local status = ""
            if record.injury ~= nil then
                status = string.format("  INJURED (%s, %d month(s), %s/month)", record.injury.name, record.injury.monthsLeft,
                    g_i18n:formatMoney(record.injury.monthlyCost, 0, true, true))
            elseif record.retired then
                status = record.careerEnded and "  RETIRED (career-ending injury)" or "  RETIRED"
            end
            print(string.format("%s '%s' age %dm %s  budget %.0f/%.0f%s", record.id, animal:getName() or "",
                animal.age or 0, record.origin, total, EqStats.budgetFromGene(record.budgetGene), status))
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


--- @param query string horse name or identifier
--- @return table|nil animal one of the player's horses
local function findOwnHorse(query)
    for _, animal in ipairs(EqRLRM.listHorsesForFarm(g_currentMission:getFarmId())) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil and matchesHorse(animal, record, query) then return animal end
    end
    return nil
end


--- @return boolean ok
--- @return string|nil message when competitions cannot be used here
local function competitionsReady()
    if g_currentMission == nil then return false, "No mission loaded" end
    if EqCompetitionManager.config == nil then return false, "Competitions are off: data/events.xml did not load" end
    if not g_currentMission:getIsServer() then return false, "Only the host can use competitions for now" end
    return true
end


--- eqEvents: every open event, cheapest first within each kind.
function EqConsole:consoleEvents()
    local ok, message = competitionsReady()
    if not ok then return message end

    local list = {}
    for _, event in pairs(EqCompetitionManager.events) do table.insert(list, event) end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind > b.kind end
        if a.discipline ~= b.discipline then return a.discipline < b.discipline end
        return a.fee < b.fee
    end)

    local horses = EqRLRM.listHorsesForFarm(g_currentMission:getFarmId())
    local anyEligible = false
    for _, event in ipairs(list) do
        local tier = EqCompetitionManager.config.tierByName[event.tier]
        local eligible = EqCompetitionManager.countEligible(event, horses)
        if eligible > 0 then anyEligible = true end
        local ages = tier.maxAge > 0 and string.format("%d-%dm", tier.minAge, tier.maxAge) or string.format("%dm+", tier.minAge)
        print(string.format("%s #%-4d %-7s %-28s %-6s age %-7s fee %7s  prize %9s  rating %d-%d  entries %d",
            eligible > 0 and string.format("[%d can enter]", eligible) or "              ", event.id,
            event.kind == EqCompetition.KIND_MONTH and "monthly" or "round",
            EqCompetitionManager.tierTitle(event.tier) .. " " .. EqCompetitionManager.disciplineTitle(event.discipline),
            event.going ~= nil and g_i18n:getText("eq_going_" .. event.going) or "",
            ages, g_i18n:formatMoney(event.fee, 0, true, true), g_i18n:formatMoney(event.prize, 0, true, true),
            tier.minRating, tier.maxRating, #event.entries))
    end

    if not anyEligible then
        print("None of your horses can enter anything open right now (age or rating). New events are drawn next round.")
    end

    return string.format("%d open event(s). Results come at the start of the next %s (monthly events: next month). Enter with eqEnter <event number> <horse>.",
        #list, EqCompetitionManager.settings.cadence)
end


--- eqRedraw: for testing, close the open round events without results and draw a new set.
function EqConsole:consoleRedraw()
    local ok, message = competitionsReady()
    if not ok then return message end

    for id, event in pairs(EqCompetitionManager.events) do
        if event.kind == EqCompetition.KIND_ROUND and #event.entries == 0 then EqCompetitionManager.events[id] = nil end
    end
    EqCompetitionManager.openRound(EqCompetition.KIND_ROUND)
    return "Drew a new set of round events (events with entries were kept). Run eqEvents."
end


--- eqRatings [horse]: each horse's rating per discipline on good going.
function EqConsole:consoleRatings(...)
    local ok, message = competitionsReady()
    if not ok then return message end

    local query = table.concat({ ... }, " ")
    local config = EqCompetitionManager.config
    for _, animal in ipairs(EqRLRM.listHorsesForFarm(g_currentMission:getFarmId())) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil and (query == "" or matchesHorse(animal, record, query)) then
            local parts = {}
            for _, discipline in ipairs(config.disciplines) do
                table.insert(parts, string.format("%s %.0f", EqCompetitionManager.disciplineTitle(discipline.name),
                    EqCompetition.rating(record.trained, discipline, nil)))
            end
            local career = record.career
            print(string.format("'%s' age %dm  starts %d wins %d places %d eliminated %d injuries %d earned %s",
                animal:getName() or record.id, animal.age or 0, career.starts, career.wins, career.places,
                career.eliminations, career.injuries, g_i18n:formatMoney(career.earnings, 0, true, true)))
            print("    " .. table.concat(parts, "  "))
        end
    end

    return "Ratings on good going. Firm going favours speed, soft favours stamina, on outdoor courses."
end


--- eqEnter <event number> <horse name or id>
function EqConsole:consoleEnter(eventId, ...)
    local ok, message = competitionsReady()
    if not ok then return message end

    local id = tonumber(eventId)
    local query = table.concat({ ... }, " ")
    if id == nil or query == "" then return "Usage: eqEnter <event number> <horse name or id>" end

    local animal = findOwnHorse(query)
    if animal == nil then return string.format("No horse called '%s' on your farm", query) end

    local _, text = EqCompetitionManager.enter(id, animal, g_currentMission:getFarmId())
    return text
end


--- eqResults: the latest results your horses took part in.
function EqConsole:consoleResults()
    local ok, message = competitionsReady()
    if not ok then return message end

    local farmId, shown = g_currentMission:getFarmId(), 0
    for _, summary in ipairs(EqCompetitionManager.results) do
        for _, placing in ipairs(summary.placings) do
            if placing.farmId == farmId then
                shown = shown + 1
                local outcome = placing.status ~= nil and string.upper(placing.status)
                    or string.format("%d of %d", placing.place, summary.field)
                print(string.format("day %d  %s %s #%d  '%s' %s  %s", summary.day,
                    EqCompetitionManager.tierTitle(summary.tier), EqCompetitionManager.disciplineTitle(summary.discipline),
                    summary.eventId, placing.name, outcome, g_i18n:formatMoney(placing.prize, 0, true, true)))
            end
        end
    end

    return string.format("%d result(s)", shown)
end


--- eqRetire <horse> [undo]: retire a horse from competition, or bring it back.
function EqConsole:consoleRetire(...)
    local ok, message = competitionsReady()
    if not ok then return message end

    local args = { ... }
    local undo = args[#args] ~= nil and string.lower(args[#args]) == "undo"
    if undo then table.remove(args) end
    local query = table.concat(args, " ")
    if query == "" then return "Usage: eqRetire <horse name or id> [undo]" end

    local animal = findOwnHorse(query)
    if animal == nil then return string.format("No horse called '%s' on your farm", query) end
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return string.format("No record for '%s'", query) end

    local _, text = EqCompetitionManager.setRetired(record, not undo)
    return text
end


--- eqSettings [cadence day|month] [racing on|off] [injuries on|off] [forcedRetirement on|off]
function EqConsole:consoleSettings(name, value)
    local ok, message = competitionsReady()
    if not ok then return message end

    local settings = EqCompetitionManager.settings
    if name == "cadence" and (value == EqCompetitionManager.CADENCE_DAY or value == EqCompetitionManager.CADENCE_MONTH) then
        settings.cadence = value
    elseif name == "racing" and (value == "on" or value == "off") then
        settings.racing = value == "on"
    elseif name == "injuries" and (value == "on" or value == "off") then
        settings.injuries = value == "on"
    elseif name == "forcedRetirement" and (value == "on" or value == "off") then
        settings.forcedRetirement = value == "on"
    elseif name ~= nil then
        return "Usage: eqSettings [cadence day|month] [racing on|off] [injuries on|off] [forcedRetirement on|off]"
    end

    local onOff = function(flag) return flag and "on" or "off" end
    return string.format("cadence=%s (round events run every %s)  racing=%s  injuries=%s  forcedRetirement=%s. Changes apply from the next round.",
        settings.cadence, settings.cadence, onOff(settings.racing), onOff(settings.injuries), onOff(settings.forcedRetirement))
end


--- eqMeatQuality [show|hide]: a display preference for this machine, so it works for clients too.
function EqConsole:consoleMeatQuality(value)
    if value == "show" or value == "hide" then
        EqInfoDisplay.hideMeatQuality = value == "hide"
        EqInfoDisplay.savePreferences()
    elseif value ~= nil then
        return "Usage: eqMeatQuality [show|hide]"
    end
    return string.format("Meat Quality is %s for horses", EqInfoDisplay.hideMeatQuality and "hidden" or "shown")
end


function EqConsole.register()
    addConsoleCommand("eqHorses", "Lists your horses' Realistic Equestrian stats", "consoleListHorses", EqConsole)
    addConsoleCommand("eqEvents", "Lists the events open for entries", "consoleEvents", EqConsole)
    addConsoleCommand("eqEnter", "Enters a horse: eqEnter <event number> <horse name or id>", "consoleEnter", EqConsole)
    addConsoleCommand("eqRatings", "Shows your horses' rating in each discipline and their record", "consoleRatings", EqConsole)
    addConsoleCommand("eqResults", "Shows your horses' latest results", "consoleResults", EqConsole)
    addConsoleCommand("eqRedraw", "Testing: draws a new set of round events", "consoleRedraw", EqConsole)
    addConsoleCommand("eqSettings", "Shows or changes settings: eqSettings [cadence day|month] [racing on|off] [injuries on|off] [forcedRetirement on|off]", "consoleSettings", EqConsole)
    addConsoleCommand("eqRetire", "Retires a horse from competition: eqRetire <horse> [undo]", "consoleRetire", EqConsole)
    addConsoleCommand("eqTraining", "Shows each horse's training focus and today's riding", "consoleTraining", EqConsole)
    addConsoleCommand("eqFocus", "Sets what staff train a horse for: eqFocus <name or id> <focus>", "consoleSetFocus", EqConsole)
    addConsoleCommand("eqMeatQuality", "Shows or hides RLRM's Meat Quality for horses: eqMeatQuality [show|hide]", "consoleMeatQuality", EqConsole)
    Log:debug("EqConsole: commands registered")
end


function EqConsole.unregister()
    removeConsoleCommand("eqHorses")
    removeConsoleCommand("eqTraining")
    removeConsoleCommand("eqFocus")
    for _, name in ipairs({ "eqEvents", "eqEnter", "eqRatings", "eqResults", "eqSettings", "eqRedraw", "eqMeatQuality", "eqRetire" }) do removeConsoleCommand(name) end
end

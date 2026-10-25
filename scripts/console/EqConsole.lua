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
            elseif record:isSettling() then
                status = "  SETTLING IN"
            end
            if record.ownedMonths ~= nil then
                status = status .. string.format("  from the dealer, %d month(s) here, %s", record.ownedMonths,
                    record.revealed and "potential known" or "potential still the dealer's view")
            end
            status = status .. string.format("  starts this month %d/%d", record.monthStarts or 0, EqConstants.MAX_ROUND_STARTS)
            print(string.format("%s '%s' age %dm %s  budget %.0f/%.0f%s", record.id, animal:getName() or "",
                animal.age or 0, record.origin, total, EqStats.budgetFromGene(record.budgetGene), status))
            print("    " .. formatStat(record, ceilings, "stamina") .. formatStat(record, ceilings, "speed"))
            print("    " .. formatStat(record, ceilings, "agility") .. formatStat(record, ceilings, "temperament"))
        end
    end

    return string.format("%d horse(s), %d record(s) in the registry", #horses, EqRegistry.count())
end


--- eqDealer: testing aid. The dealer's horses with their real potential, the dealer's view of
--- it, and the price.
function EqConsole:consoleDealer()
    if g_currentMission == nil or g_currentMission.animalSystem == nil then return "No mission loaded" end

    local count = 0
    for _, animal in ipairs(g_currentMission.animalSystem:getSaleAnimalsByTypeIndex(AnimalType.HORSE) or {}) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil then
            count = count + 1
            local ceilings, advertised = record:getCeilings(), record.advertised or record:getCeilings()
            local parts = {}
            for _, stat in ipairs(EqConstants.STAT_KEYS) do
                table.insert(parts, string.format("%s %.0f/%.0f (says %.0f)", string.sub(stat, 1, 3),
                    record.trained[stat] or 0, ceilings[stat], advertised[stat]))
            end
            print(string.format("%s '%s' age %dm  talent %.0f (says %.0f)  %s  value %s", record.id,
                animal.getName ~= nil and animal:getName() or "", animal.age or 0, EqDealer.talentScore(ceilings),
                EqDealer.talentScore(advertised), table.concat(parts, "  "),
                g_i18n:formatMoney(animal:getSellPrice(), 0, true, true)))
        end
    end
    return string.format("%d horse(s) at the dealer. Value is before the dealer's markup.", count)
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


--- eqEvents: every open event, grouped by type then level, in the same order as the Events tab.
function EqConsole:consoleEvents()
    local ok, message = competitionsReady()
    if not ok then return message end

    local list = {}
    for _, event in pairs(EqCompetitionManager.events) do table.insert(list, event) end
    table.sort(list, EqEventsView.compareEvents)

    local horses = EqRLRM.listHorsesForFarm(g_currentMission:getFarmId())
    local anyEligible = false
    for _, event in ipairs(list) do
        local tier = EqCompetitionManager.config.tierByName[event.tier]
        local eligible = EqCompetitionManager.countEligible(event, horses)
        if eligible > 0 then anyEligible = true end
        local ages = tier.maxAge > 0 and string.format("%d-%dm", tier.minAge, tier.maxAge) or string.format("%dm+", tier.minAge)
        print(string.format("%s #%-4d %-7s %-44s %-8s age %-7s fee %7s  prize %9s  rating %d-%d  entries %d",
            eligible > 0 and string.format("[%d can enter]", eligible) or "              ", event.id,
            event.kind == EqCompetition.KIND_MONTH and "monthly" or "round",
            EqCompetitionManager.eventName(event.discipline, event.tier, event.venue) .. " (" .. EqCompetitionManager.tierTitle(event.tier) .. ")",
            EqCompetitionManager.conditionsText(event.going),
            ages, g_i18n:formatMoney(event.fee, 0, true, true), g_i18n:formatMoney(event.prize, 0, true, true),
            tier.minRating, tier.maxRating, #event.entries))
    end

    if not anyEligible then
        print("None of your horses can enter anything open right now (age or rating). New events are drawn next round.")
    end

    local left = EqCompetitionManager.entriesLeft(g_currentMission:getFarmId())
    return string.format("%d open event(s). Results come at the start of the next %s (monthly events: next month). %s Enter with eqEnter <event number> <horse> [auto|manual]; Auto Transport is paid on top of the fee, Manual means delivering the horse yourself.",
        #list, EqCompetitionManager.settings.cadence,
        left ~= nil and string.format("You have %d of %d entries left this month.", left, EqCompetitionManager.settings.entriesPerMonth) or "No monthly entry limit.")
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
                local experience = EqExperience.get(record, discipline.name)
                local rating = EqCompetitionManager.ratingFor(record, { discipline = discipline.name })
                if experience >= 0.5 then
                    table.insert(parts, string.format("%s %.0f (experience %.0f, +%.1f)", EqCompetitionManager.disciplineTitle(discipline.name),
                        rating, experience, EqExperience.ratingBonus(record, discipline.name)))
                else
                    table.insert(parts, string.format("%s %.0f", EqCompetitionManager.disciplineTitle(discipline.name), rating))
                end
            end
            local career = record.career
            print(string.format("'%s' age %dm  starts %d wins %d places %d eliminated %d injuries %d earned %s",
                animal:getName() or record.id, animal.age or 0, career.starts, career.wins, career.places,
                career.eliminations, career.injuries, g_i18n:formatMoney(career.earnings, 0, true, true)))
            print("    " .. table.concat(parts, "  "))
            print("    Favourite event: " .. EqCompetitionManager.specialtyText(record))
        end
    end

    return "Ratings on good going. Firm going favours speed, soft favours stamina, on outdoor courses."
end


--- eqEnter <event number> <horse name or id> [auto|manual]
function EqConsole:consoleEnter(eventId, ...)
    local ok, message = competitionsReady()
    if not ok then return message end

    local words = { ... }
    local transport = EqCompetitionManager.TRANSPORT_AUTO
    local last = words[#words] ~= nil and string.lower(words[#words]) or nil
    if last == EqCompetitionManager.TRANSPORT_MANUAL or last == EqCompetitionManager.TRANSPORT_AUTO then
        transport = last
        table.remove(words)
    end

    local id = tonumber(eventId)
    local query = table.concat(words, " ")
    if id == nil or query == "" then return "Usage: eqEnter <event number> <horse name or id> [auto|manual]" end

    local animal = findOwnHorse(query)
    if animal == nil then return string.format("No horse called '%s' on your farm", query) end

    local _, text = EqCompetitionManager.enter(id, animal, g_currentMission:getFarmId(), transport)
    return text
end


--- eqProbe: testing, writes the loading triggers to the log.
function EqConsole:consoleProbe()
    return EqProbe.run()
end


--- eqDeliver <horse name or id>: testing, delivers without driving to the dealer.
function EqConsole:consoleDeliver(...)
    local ok, message = competitionsReady()
    if not ok then return message end

    local query = table.concat({ ... }, " ")
    if query == "" then return "Usage: eqDeliver <horse name or id>" end
    local animal = findOwnHorse(query)
    if animal == nil then return string.format("No horse called '%s' on your farm", query) end

    local count = EqCompetitionManager.deliver(animal)
    if count == 0 then return string.format("%s has no Manual Transport entry waiting for delivery", query) end
    return string.format("%s delivered: it leaves for %d event(s)", query, count)
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
                print(string.format("day %d  %s (%s) #%d  '%s' %s  %s", summary.day,
                    EqCompetitionManager.eventName(summary.discipline, summary.tier, summary.venue), EqCompetitionManager.tierTitle(summary.tier),
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


--- eqExperience <horse> <discipline> <0-100>: testing, sets a horse's event experience.
function EqConsole:consoleExperience(...)
    local ok, message = competitionsReady()
    if not ok then return message end

    local args = { ... }
    local value, name = tonumber(args[#args]), args[#args - 1]
    local usage = "Usage: eqExperience <horse name or id> <discipline> <0-100>"
    if value == nil or name == nil or EqCompetitionManager.config.disciplineByName[name] == nil then
        local names = {}
        for _, discipline in ipairs(EqCompetitionManager.config.disciplines) do table.insert(names, discipline.name) end
        return usage .. "\nDisciplines: " .. table.concat(names, " ")
    end
    local query = table.concat(args, " ", 1, #args - 2)
    local animal = findOwnHorse(query)
    if animal == nil then return string.format("No horse called '%s' on your farm", query) end
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return string.format("No record for '%s'", query) end

    record.experience = record.experience or {}
    record.experience[name] = { value = EqStats.clamp(value, 0, EqExperience.MAX), idle = 0 }
    return string.format("'%s': %s experience %.0f, favourite event %s", animal:getName() or record.id, name,
        record.experience[name].value, EqCompetitionManager.specialtyText(record))
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
    elseif name == "entriesPerMonth" and tonumber(value) ~= nil and tonumber(value) >= 0 then
        settings.entriesPerMonth = math.floor(tonumber(value))
    elseif name ~= nil then
        return "Usage: eqSettings [cadence day|month] [racing on|off] [injuries on|off] [forcedRetirement on|off] [entriesPerMonth <n, 0 = no limit>]"
    end

    local onOff = function(flag) return flag and "on" or "off" end
    return string.format("cadence=%s (round events run every %s)  racing=%s  injuries=%s  forcedRetirement=%s  entriesPerMonth=%s  homeRegion=%s. Changes apply from the next round.",
        settings.cadence, settings.cadence, onOff(settings.racing), onOff(settings.injuries), onOff(settings.forcedRetirement),
        settings.entriesPerMonth > 0 and tostring(settings.entriesPerMonth) or "no limit",
        tostring(EqCompetitionManager.homeRegion()))
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


--- @return number|nil x, number|nil y, number|nil z the local player's position, or the
---     ridden horse's
local function localPosition()
    local ok, x, y, z = pcall(function()
        if g_localPlayer ~= nil and g_localPlayer.getPosition ~= nil then return g_localPlayer:getPosition() end
        return nil
    end)
    if ok then return x, y, z end
    return nil
end


--- eqFacilities [near]: the farm's horse facilities and what they give. "near" lists the map
--- nodes and placeables around you, to find the names of buildings data/facilities.xml should
--- match.
function EqConsole:consoleFacilities(mode)
    if g_currentMission == nil then return "No mission loaded" end
    local config = EqFacilityHooks.config
    if config == nil then return "data/facilities.xml did not load; see log.txt" end
    local farmId = g_currentMission:getFarmId()

    if mode == "near" then
        local x, y, z = localPosition()
        if x == nil then return "Could not find your position" end
        local radius = 30
        local names = {}
        local terrain = g_currentMission.terrainRootNode
        local stack = { (terrain ~= nil and terrain ~= 0) and getParent(terrain) or getRootNode() }
        while #stack > 0 do
            local node = table.remove(stack)
            local nx, _, nz = getWorldTranslation(node)
            local name = getName(node)
            if (nx - x) ^ 2 + (nz - z) ^ 2 <= radius * radius and getNumOfChildren(node) > 0 and names[name] == nil then
                names[name] = math.sqrt((nx - x) ^ 2 + (nz - z) ^ 2)
            end
            for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
        end
        local sorted = {}
        for name, distance in pairs(names) do table.insert(sorted, { name = name, distance = distance }) end
        table.sort(sorted, function(a, b) return a.distance < b.distance end)
        for i = 1, math.min(#sorted, 60) do print(string.format("  node %5.1fm  %s", sorted[i].distance, sorted[i].name)) end

        for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
            if placeable.rootNode ~= nil then
                local px, _, pz = getWorldTranslation(placeable.rootNode)
                local distance = math.sqrt((px - x) ^ 2 + (pz - z) ^ 2)
                if distance <= 80 then
                    print(string.format("  placeable %5.1fm  '%s' farm %s kind %s  %s", distance, placeable:getName() or "",
                        tostring(placeable:getOwnerFarmId()), tostring(EqFacilityHooks.kindOfPlaceable(placeable)),
                        tostring(placeable.configFileName)))
                end
            end
        end
        local inside = {}
        for kind in pairs(EqFacilityHooks.kindsAt(farmId, x, y, z)) do table.insert(inside, kind) end
        return string.format("%d node names within %dm (first 60 shown). Inside your facilities: %s", #sorted, radius,
            #inside > 0 and table.concat(inside, ", ") or "none")
    end

    for _, entry in ipairs(EqFacilityHooks.listPlaceables()) do
        local placeable = entry.placeable
        if placeable:getOwnerFarmId() == farmId then
            print(string.format("  %s: '%s'  %s", entry.kind, placeable:getName() or "", tostring(placeable.configFileName)))
        end
    end
    for _, point in ipairs(EqFacilityHooks.mapPoints) do
        local owner = EqFacilityHooks.farmlandOwnerAt(point.x, point.z)
        print(string.format("  %s: map %s at %.0f, %.0f (%s)", point.kind, point.name, point.x, point.z,
            owner == farmId and "yours" or string.format("farmland owner %s", tostring(owner))))
    end

    local counts = EqFacilityHooks.countsForFarm(farmId)
    local owned = EqFacility.boosts(config, counts, nil)
    local lines = {}
    for _, kind in ipairs(config.kinds) do
        if (counts[kind.name] or 0) > 0 then
            table.insert(lines, string.format("%s x%d (%.0f%%)", kind.name, counts[kind.name], EqFacility.scale(kind, counts[kind.name]) * 100))
        end
    end
    print(string.format("Training rate from owned facilities: sta +%.0f%% spd +%.0f%% agi +%.0f%% tem +%.0f%%",
        owned.stamina * 100, owned.speed * 100, owned.agility * 100, owned.temperament * 100))
    local events = {}
    for _, discipline in ipairs(EqCompetitionManager.config ~= nil and EqCompetitionManager.config.disciplines or {}) do
        local bonus = EqFacility.eventBonus(config, counts, discipline.name)
        if bonus > 0 then table.insert(events, string.format("%s +%.1f%%", discipline.name, bonus * 100)) end
    end
    print("Event day bonus: " .. (#events > 0 and table.concat(events, ", ") or "none"))
    return "Facilities: " .. (#lines > 0 and table.concat(lines, ", ") or "none") .. ". Use 'eqFacilities near' to list what is around you."
end


--- eqForceInjury [on|off]: testing, every horse that starts an event is injured (not saved).
function EqConsole:consoleForceInjury(value)
    local ok, message = competitionsReady()
    if not ok then return message end

    local settings = EqCompetitionManager.settings
    if value == "on" or value == "off" then
        settings.forceInjuries = value == "on"
    elseif value ~= nil then
        return "Usage: eqForceInjury [on|off]"
    end
    if not settings.forceInjuries then return "Forced injuries are off: events use the normal injury chance" end
    return "Forced injuries are ON: every horse that starts an event is injured (even with eqSettings injuries off). "
        .. "Career-ending ones still need eqSettings forcedRetirement on. Turns off on reload, or with eqForceInjury off."
end


--- eqDirt <horse> <0-100>: testing, sets a horse's dirt (RLRM shows Cleanliness = 100 - dirt).
function EqConsole:consoleDirt(...)
    if g_currentMission == nil then return "No mission loaded" end
    if not g_currentMission:getIsServer() then return "Only the host can change dirt" end

    local args = { ... }
    local value = tonumber(args[#args])
    local query = table.concat(args, " ", 1, #args - 1)
    if value == nil or query == "" then
        return "Usage: eqDirt <horse name or id> <0-100>  (0 = spotless, 100 = filthy; groomed counts at "
            .. EqConstants.GROOMED_DIRT .. " or less)"
    end
    local animal = findOwnHorse(query)
    if animal == nil then return string.format("No horse called '%s' on your farm", query) end

    local before = animal.dirt or 0
    value = math.floor(EqStats.clamp(value, 0, 100))
    if animal.changeDirt ~= nil then animal:changeDirt(value - before) else animal.dirt = value end
    if animal.setDirty ~= nil then animal:setDirty() end
    return string.format("'%s' dirt %s -> %s (Cleanliness %s%%). RLRM adds 10 dirt at each day's end, after the groomed check.",
        animal:getName() or query, tostring(before), tostring(animal.dirt), tostring(100 - (animal.dirt or 0)))
end


--- eqChanges <horse> [days]: testing, what changed the horse's stats and why, from today back.
function EqConsole:consoleChanges(...)
    if g_currentMission == nil then return "No mission loaded" end

    local args = { ... }
    local days = tonumber(args[#args])
    if days ~= nil then table.remove(args) end
    days = math.max(1, math.floor(days or 2))
    local query = table.concat(args, " ")
    if query == "" then return "Usage: eqChanges <horse name or id> [days, default 2 = today and yesterday]" end
    local animal = findOwnHorse(query)
    if animal == nil then return string.format("No horse called '%s' on your farm", query) end
    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return string.format("No record for '%s'", query) end

    local today = g_currentMission.environment.currentMonotonicDay or 0
    local entries = EqStatLog.since(record.id, today - days + 1)
    print(string.format("'%s' (%s), today is day %d. Now: %s", animal:getName() or record.id, record.id, today,
        EqStatLog.statLine(record.trained, "%.2f")))
    print(string.format("    RLRM now: fitness %s health %s dirt %s riding %s, age %dm", tostring(animal.fitness), tostring(animal.health),
        tostring(animal.dirt), tostring(animal.riding), animal.age or 0))
    for _, entry in ipairs(entries) do
        print(string.format("  day %d %s: %s%s", entry.day, entry.source, EqStatLog.statLine(entry.deltas, "%+.2f"),
            entry.after ~= nil and ("  -> " .. EqStatLog.statLine(entry.after, "%.2f")) or ""))
        for _, note in ipairs(entry.notes) do print("      " .. note) end
    end
    return string.format("%d change(s) in the last %d day(s). The log is kept for %d days and starts again on reload; the host keeps it.",
        #entries, days, EqStatLog.KEEP_DAYS)
end


function EqConsole.register()
    addConsoleCommand("eqHorses", "Lists your horses' Realistic Equestrian stats", "consoleListHorses", EqConsole)
    addConsoleCommand("eqEvents", "Lists the events open for entries", "consoleEvents", EqConsole)
    addConsoleCommand("eqEnter", "Enters a horse: eqEnter <event number> <horse name or id> [auto|manual]", "consoleEnter", EqConsole)
    addConsoleCommand("eqProbe", "Testing: writes the animal loading triggers (dealer) and any trailer in them to log.txt", "consoleProbe", EqConsole)
    addConsoleCommand("eqDeliver", "Testing: delivers a Manual Transport horse as if at the dealer: eqDeliver <horse>", "consoleDeliver", EqConsole)
    addConsoleCommand("eqRatings", "Shows your horses' rating in each discipline and their record", "consoleRatings", EqConsole)
    addConsoleCommand("eqExperience", "Testing: sets a horse's event experience: eqExperience <horse> <discipline> <0-100>", "consoleExperience", EqConsole)
    addConsoleCommand("eqResults", "Shows your horses' latest results", "consoleResults", EqConsole)
    addConsoleCommand("eqRedraw", "Testing: draws a new set of round events", "consoleRedraw", EqConsole)
    addConsoleCommand("eqSettings", "Shows or changes settings: eqSettings [cadence day|month] [racing on|off] [injuries on|off] [forcedRetirement on|off] [entriesPerMonth n]", "consoleSettings", EqConsole)
    addConsoleCommand("eqRetire", "Retires a horse from competition: eqRetire <horse> [undo]", "consoleRetire", EqConsole)
    addConsoleCommand("eqDealer", "Testing: lists the dealer's horses with their real potential and price", "consoleDealer", EqConsole)
    addConsoleCommand("eqTraining", "Shows each horse's training focus and today's riding", "consoleTraining", EqConsole)
    addConsoleCommand("eqFocus", "Sets what staff train a horse for: eqFocus <name or id> <focus>", "consoleSetFocus", EqConsole)
    addConsoleCommand("eqFacilities", "Shows your farm's horse facilities and their bonuses: eqFacilities [near]", "consoleFacilities", EqConsole)
    addConsoleCommand("eqForceInjury", "Testing: every horse that starts an event is injured: eqForceInjury [on|off]", "consoleForceInjury", EqConsole)
    addConsoleCommand("eqDirt", "Testing: sets a horse's dirt: eqDirt <horse> <0-100>", "consoleDirt", EqConsole)
    addConsoleCommand("eqChanges", "Testing: what changed a horse's stats and why: eqChanges <horse> [days]", "consoleChanges", EqConsole)
    addConsoleCommand("eqMeatQuality", "Shows or hides RLRM's Meat Quality for horses: eqMeatQuality [show|hide]", "consoleMeatQuality", EqConsole)
    Log:debug("EqConsole: commands registered")
end


function EqConsole.unregister()
    removeConsoleCommand("eqHorses")
    removeConsoleCommand("eqExperience")
    removeConsoleCommand("eqDealer")
    removeConsoleCommand("eqTraining")
    removeConsoleCommand("eqFocus")
    for _, name in ipairs({ "eqEvents", "eqEnter", "eqDeliver", "eqProbe", "eqRatings", "eqResults", "eqSettings", "eqRedraw", "eqMeatQuality", "eqRetire", "eqFacilities", "eqForceInjury", "eqDirt", "eqChanges" }) do removeConsoleCommand(name) end
end

--[[
    EqCompetitionManager.lua
    Runs the event calendar on the server.

    Two kinds of events:
    - Round events (Training, Novice, Intermediate) open every round and resolve at the start of
      the next one. A round is a day or a month, by the "cadence" setting, so players on long
      months (7+ days) and on 1 day a month both get a sensible pace.
    - Monthly events (Advanced, Championship) open at the start of each month and resolve at the
      start of the next.

    Players enter from the Events tab or with eqEnter and pay the fee and the horse's transport at
    once. A farm makes at most entriesPerMonth entries a month (a setting, 3 by default). A horse starts at
    most MAX_ROUND_STARTS round events a month, so a good horse is not a daily money tap, and a
    horse bought from the dealer settles in for a month before it can compete. Results, prize
    money and the career record follow when the event resolves. EqRisk decides scratches,
    eliminations and injuries first; injured horses rest for some months, and their vet bills
    are charged at the start of each month until they recover. Horses from every farm can be
    entered into the same event; each farm pays its own fee and gets its own prize.

    Server only for now: entering from a multiplayer client needs a network event (milestone 7).
]]

EqCompetitionManager = {}

local Log = EqLog

EqCompetitionManager.CADENCE_DAY = "day"
EqCompetitionManager.CADENCE_MONTH = "month"
EqCompetitionManager.RESULTS_KEPT = 40

-- Entries a farm may make a month, whatever the event kind; 0 means no limit. A setting.
EqCompetitionManager.DEFAULT_ENTRIES_PER_MONTH = 3

-- Getting a horse to an event costs a share of its transport price (the base game's, by age:
-- $600 for an adult), paid with the entry fee. A quarter keeps Novice worth entering.
EqCompetitionManager.TRANSPORT_SHARE = 0.25
-- Used when the horse's subtype has no transport price.
EqCompetitionManager.TRANSPORT_FALLBACK = 150

-- A Training Event under the monthly cadence counts as this share of a month's work.
EqCompetitionManager.MONTHLY_BOOST_MONTHS = 0.25


function EqCompetitionManager.reset()
    EqCompetitionManager.config = nil
    EqCompetitionManager.events = {}
    EqCompetitionManager.results = {}
    EqCompetitionManager.nextEventId = 1
    EqCompetitionManager.settings = { cadence = EqCompetitionManager.CADENCE_DAY, racing = true,
        injuries = true, forcedRetirement = false, entriesPerMonth = EqCompetitionManager.DEFAULT_ENTRIES_PER_MONTH }
    EqCompetitionManager.farmEntries = {}   -- farmId -> entries made this month
end

EqCompetitionManager.reset()


--- @param modDirectory string
function EqCompetitionManager.loadConfig(modDirectory)
    EqCompetitionManager.config = EqEventConfig.load(modDirectory .. "data/events.xml")
end


--- @return table rng seeded by the game day, so a round's draw does not depend on frame timing
local function roundRng(salt)
    local environment = g_currentMission.environment
    return EqRandom.new(string.format("%s %d %d", salt, environment.currentMonotonicDay or 0, EqCompetitionManager.nextEventId))
end


--- @param kind string EqCompetition.KIND_ROUND or KIND_MONTH
function EqCompetitionManager.openRound(kind)
    local config = EqCompetitionManager.config
    if config == nil then return end

    local drawn = EqCompetition.drawSchedule(config, roundRng(kind), kind, EqCompetitionManager.settings.racing)
    for _, event in ipairs(drawn) do
        event.id = EqCompetitionManager.nextEventId
        event.entries = {}
        EqCompetitionManager.nextEventId = EqCompetitionManager.nextEventId + 1
        EqCompetitionManager.events[event.id] = event
    end
    Log:info("EqCompetition: %d %s event(s) open for entries", #drawn, kind)
end


--- Every horse on every farm, by identifier.
--- @return table id -> { animal, farmId }
local function indexHorses()
    local index = {}
    for _, farm in pairs(g_farmManager:getFarms()) do
        local farmId = farm.farmId
        if farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID then
            for _, animal in ipairs(EqRLRM.listHorsesForFarm(farmId)) do
                local id = EqRegistry.getId(animal)
                if id ~= nil then index[id] = { animal = animal, farmId = farmId } end
            end
        end
    end
    return index
end


--- @param farmId number
--- @param text string
local function notify(farmId, text)
    if g_currentMission:getFarmId() == farmId then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
end


--- @param name string
--- @return string title
function EqCompetitionManager.disciplineTitle(name)
    return g_i18n:getText("eq_discipline_" .. name)
end


--- @param name string
--- @return string title
function EqCompetitionManager.tierTitle(name)
    return g_i18n:getText("eq_tier_" .. name)
end


--- The event's own name, such as "1.20m Jumping" or "Prix St Georges": eq_event_<discipline>_<tier>,
--- or the tier and discipline when there is no such text.
--- @param discipline string
--- @param tier string
--- @return string name
function EqCompetitionManager.eventName(discipline, tier)
    local key = string.format("eq_event_%s_%s", discipline, tier)
    if g_i18n.hasText == nil or g_i18n:hasText(key) then return g_i18n:getText(key) end
    return string.format("%s %s", EqCompetitionManager.tierTitle(tier), EqCompetitionManager.disciplineTitle(discipline))
end


--- @param going string|nil the event's conditions, nil indoors
--- @return string text such as "Firm", or "Indoor"
function EqCompetitionManager.conditionsText(going)
    return g_i18n:getText(going ~= nil and ("eq_going_" .. going) or "eq_going_indoor")
end


--- @param event table
--- @return string title such as "1.20m Jumping (Intermediate) #12"
function EqCompetitionManager.eventTitle(event)
    return string.format("%s (%s) #%d", EqCompetitionManager.eventName(event.discipline, event.tier),
        EqCompetitionManager.tierTitle(event.tier), event.id)
end


--- @param event table
--- @return table|nil going config entry
local function getGoing(event)
    if event.going == nil then return nil end
    for _, going in ipairs(EqCompetitionManager.config.goings) do
        if going.name == event.going then return going end
    end
    return nil
end


--- A horse's rating for an event, from its record.
--- @param record table
--- @param event table
--- @return number rating
function EqCompetitionManager.ratingFor(record, event)
    local discipline = EqCompetitionManager.config.disciplineByName[event.discipline]
    return EqCompetition.rating(record.trained, discipline, getGoing(event))
end


--- @param name string injury name from events.xml
--- @return string text such as "a tendon injury"
function EqCompetitionManager.injuryTitle(name)
    return g_i18n:getText("eq_injury_" .. name)
end


--- Put a horse on box rest, or end its career, after an injury at an event.
--- @param record table
--- @param entry table { name, farmId }
--- @param injury table EqRisk.rollInjury outcome
--- @param event table
function EqCompetitionManager.applyInjury(record, entry, injury, event)
    record.career.injuries = record.career.injuries + 1
    if injury.careerEnding then
        record.retired = true
        record.careerEnded = true
        record.injury = nil
        notify(entry.farmId, string.format(g_i18n:getText("eq_injury_careerEnding"), entry.name,
            EqCompetitionManager.eventTitle(event)))
        return
    end

    record.injury = { name = injury.name, monthsLeft = injury.months, monthlyCost = injury.monthlyCost }
    notify(entry.farmId, string.format(g_i18n:getText("eq_injury_new"), entry.name, EqCompetitionManager.eventTitle(event),
        EqCompetitionManager.injuryTitle(injury.name), injury.months,
        g_i18n:formatMoney(injury.monthlyCost, 0, true, true)))
end


--- Resolve one closed event: scratches, eliminations and injuries, then score the field, pay
--- prizes, update careers and tell the owners.
--- @param event table
--- @param horses table from indexHorses
function EqCompetitionManager.resolve(event, horses)
    local config = EqCompetitionManager.config
    local tier = config.tierByName[event.tier]
    local discipline = config.disciplineByName[event.discipline]
    local riskRng = EqRandom.new("risk " .. event.id)
    local summary = { eventId = event.id, discipline = event.discipline, tier = event.tier, going = event.going,
        field = 0, day = g_currentMission.environment.currentMonotonicDay or 0, placings = {} }
    local starters, byKey = {}, {}

    for _, entry in ipairs(event.entries) do
        local horse = horses[entry.horseId]
        local record = EqRegistry.getById(entry.horseId)
        if horse == nil or record == nil then
            notify(entry.farmId, string.format(g_i18n:getText("eq_result_gone"), entry.name, EqCompetitionManager.eventTitle(event)))
        else
            local reason = EqRisk.scratchReason(record, horse.animal.health, riskRng)
            if reason ~= nil then
                local refund = math.floor((event.fee or 0) * EqRisk.SCRATCH_REFUND + 0.5)
                if refund > 0 then
                    g_currentMission:addMoney(refund, entry.farmId, MoneyType.EQ_ENTRY_FEES or MoneyType.OTHER, true, true)
                end
                table.insert(summary.placings, { horseId = entry.horseId, name = entry.name, farmId = entry.farmId,
                    place = 0, prize = 0, status = "scratched" })
                notify(entry.farmId, string.format(g_i18n:getText("eq_result_scratched"), entry.name,
                    EqCompetitionManager.eventTitle(event), g_i18n:getText("eq_scratch_" .. reason),
                    g_i18n:formatMoney(refund, 0, true, true)))
            else
                table.insert(starters, {
                    key = entry.horseId,
                    rating = EqCompetitionManager.ratingFor(record, event),
                    condition = EqCompetition.condition(horse.animal.fitness, horse.animal.health),
                    temperament = record.trained.temperament or 0,
                    stamina = record.trained.stamina or 0,
                    fitness = horse.animal.fitness or 0,
                })
                byKey[entry.horseId] = { entry = entry, record = record, animal = horse.animal }
                if event.kind == EqCompetition.KIND_ROUND then record.monthStarts = (record.monthStarts or 0) + 1 end
            end
        end
    end

    local outcomes = EqRisk.rollEvent(event, config, starters, riskRng, EqCompetitionManager.settings)
    local finishers, eliminated = {}, {}
    for _, starter in ipairs(starters) do
        table.insert(outcomes[starter.key].eliminated and eliminated or finishers, starter)
    end

    -- Simulated rivals fill the field around the finishers; an eliminated horse takes its place
    -- in the field but not in the placings.
    local results = {}
    if #starters > 0 then
        results = EqCompetition.run(event, config, finishers, EqRandom.new("result " .. event.id), tier.field - #eliminated)
    end
    summary.field = #results + #eliminated

    for _, runner in ipairs(results) do
        local mine = runner.key ~= nil and byKey[runner.key] or nil
        if mine ~= nil then
            local entry, record = mine.entry, mine.record
            local career = record.career
            career.starts = career.starts + 1
            if runner.place == 1 then career.wins = career.wins + 1 end
            if runner.place <= 3 then career.places = career.places + 1 end

            if runner.prize > 0 then
                career.earnings = career.earnings + runner.prize
                g_currentMission:addMoney(runner.prize, entry.farmId, MoneyType.EQ_PRIZE_MONEY or MoneyType.OTHER, true, true)
            end

            if tier.trainingBoost > 0 then
                local cadenceDay = EqCompetitionManager.settings.cadence == EqCompetitionManager.CADENCE_DAY
                local timeAdjustment = cadenceDay and (g_currentMission.environment.timeAdjustment or 1)
                    or EqCompetitionManager.MONTHLY_BOOST_MONTHS
                EqTraining.applyBoost(record, record:getCeilings(), discipline.weights,
                    tier.trainingBoost, mine.animal.age or 0, timeAdjustment)
            end

            table.insert(summary.placings, { horseId = runner.key, name = entry.name, farmId = entry.farmId,
                place = runner.place, prize = runner.prize })

            notify(entry.farmId, string.format(g_i18n:getText("eq_result_placed"), entry.name, runner.place, summary.field,
                EqCompetitionManager.eventTitle(event), g_i18n:formatMoney(runner.prize, 0, true, true)))
        end
    end

    for _, starter in ipairs(eliminated) do
        local mine = byKey[starter.key]
        local career = mine.record.career
        career.starts = career.starts + 1
        career.eliminations = career.eliminations + 1
        table.insert(summary.placings, { horseId = starter.key, name = mine.entry.name, farmId = mine.entry.farmId,
            place = 0, prize = 0, status = "eliminated" })
        notify(mine.entry.farmId, string.format(g_i18n:getText(discipline.racing and "eq_result_pulledUp" or "eq_result_eliminated"),
            mine.entry.name, EqCompetitionManager.eventTitle(event)))
    end

    for _, starter in ipairs(starters) do
        local injury = outcomes[starter.key].injury
        if injury ~= nil then
            local mine = byKey[starter.key]
            EqCompetitionManager.applyInjury(mine.record, mine.entry, injury, event)
        end
    end

    if #summary.placings == 0 then return end
    table.insert(EqCompetitionManager.results, 1, summary)
    while #EqCompetitionManager.results > EqCompetitionManager.RESULTS_KEPT do table.remove(EqCompetitionManager.results) end
end


--- Start of a month: charge each injured horse's vet bill to its farm and count down its rest,
--- reset the month's starts, and count a bought horse's months on the farm (its real potential
--- shows after REVEAL_MONTHS).
--- @param horses table from indexHorses
function EqCompetitionManager.monthlyCare(horses)
    local ids = {}
    for id in pairs(horses) do table.insert(ids, id) end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local record = EqRegistry.getOrCreate(horses[id].animal)
        local horse = horses[id]
        local name = horse.animal.getName ~= nil and horse.animal:getName() or id
        if record ~= nil then
            record.monthStarts = 0
            EqCompetitionManager.countOwnedMonth(record, horse.farmId, name)
        end

        local injury = record ~= nil and record.injury or nil
        if injury ~= nil then
            if injury.monthlyCost > 0 then
                g_currentMission:addMoney(-injury.monthlyCost, horse.farmId, MoneyType.EQ_VET_BILLS or MoneyType.OTHER, true, true)
            end
            injury.monthsLeft = injury.monthsLeft - 1
            if injury.monthsLeft <= 0 then
                record.injury = nil
                notify(horse.farmId, string.format(g_i18n:getText("eq_injury_recovered"), name))
            end
        end
    end
end


--- One more month on the farm for a horse bought from the dealer; at REVEAL_MONTHS its real
--- potential shows, and the owner hears how it compares with what the dealer said.
--- @param record table
--- @param farmId number
--- @param name string
function EqCompetitionManager.countOwnedMonth(record, farmId, name)
    if record.ownedMonths == nil then return end
    record.ownedMonths = record.ownedMonths + 1
    if record.advertised ~= nil and not record.revealed and record.ownedMonths >= EqConstants.REVEAL_MONTHS then
        record.revealed = true
        local verdict = EqDealer.verdict(record.advertised, record:getCeilings())
        notify(farmId, string.format(g_i18n:getText("eq_reveal_" .. verdict), name))
    end
end


--- Why a horse cannot be entered in anything right now, whatever the event.
--- @param record table
--- @param kind string the event's kind
--- @return string|nil reason "retired", "injured", "settling" or "rested", nil when it can go
function EqCompetitionManager.unavailableReason(record, kind)
    if record.retired then return "retired" end
    if record.injury ~= nil then return "injured" end
    if record:isSettling() then return "settling" end
    if kind == EqCompetition.KIND_ROUND and (record.monthStarts or 0) >= EqConstants.MAX_ROUND_STARTS then
        return "rested"
    end
    return nil
end


--- Retire a horse from competition, or bring it back. Retiring an injured horse stops its
--- treatment and the vet bills with it.
--- @param record table
--- @param retired boolean
--- @return boolean ok
--- @return string message
function EqCompetitionManager.setRetired(record, retired)
    if not retired and record.careerEnded then return false, g_i18n:getText("eq_retire_careerEnded") end
    record.retired = retired
    if retired then
        local wasInjured = record.injury ~= nil
        record.injury = nil
        return true, g_i18n:getText(wasInjured and "eq_retire_doneInjured" or "eq_retire_done")
    end
    return true, g_i18n:getText("eq_retire_undone")
end


--- Close and resolve every open event of a kind, then open the next round of that kind.
--- @param kind string
function EqCompetitionManager.turnOver(kind)
    local horses = indexHorses()
    local ids = {}
    for id, event in pairs(EqCompetitionManager.events) do
        if event.kind == kind then table.insert(ids, id) end
    end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local event = EqCompetitionManager.events[id]
        EqCompetitionManager.events[id] = nil
        EqCompetitionManager.resolve(event, horses)
    end

    EqCompetitionManager.openRound(kind)
end


function EqCompetitionManager.onDayChanged()
    if EqCompetitionManager.settings.cadence == EqCompetitionManager.CADENCE_DAY then
        EqCompetitionManager.turnOver(EqCompetition.KIND_ROUND)
    end
end


function EqCompetitionManager.onPeriodChanged()
    EqCompetitionManager.farmEntries = {}
    EqCompetitionManager.monthlyCare(indexHorses())
    if EqCompetitionManager.settings.cadence == EqCompetitionManager.CADENCE_MONTH then
        EqCompetitionManager.turnOver(EqCompetition.KIND_ROUND)
    end
    EqCompetitionManager.turnOver(EqCompetition.KIND_MONTH)
end


--- Open the first rounds on a new game, or after loading a save that had none.
function EqCompetitionManager.ensureOpen()
    local hasRound, hasMonth = false, false
    for _, event in pairs(EqCompetitionManager.events) do
        if event.kind == EqCompetition.KIND_ROUND then hasRound = true else hasMonth = true end
    end
    if not hasRound then EqCompetitionManager.openRound(EqCompetition.KIND_ROUND) end
    if not hasMonth then EqCompetitionManager.openRound(EqCompetition.KIND_MONTH) end
end


--- @param horseId string
--- @param kind string
--- @return table|nil event the open event of this kind the horse is already entered in
function EqCompetitionManager.findEntry(horseId, kind)
    for _, event in pairs(EqCompetitionManager.events) do
        if event.kind == kind then
            for _, entry in ipairs(event.entries) do
                if entry.horseId == horseId then return event end
            end
        end
    end
    return nil
end


--- How many of a farm's horses could enter an event now.
--- @param event table
--- @param horses table RLRM Animals
--- @return number count
function EqCompetitionManager.countEligible(event, horses)
    local tier = EqCompetitionManager.config.tierByName[event.tier]
    local count = 0
    for _, animal in ipairs(horses) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil and EqCompetitionManager.unavailableReason(record, event.kind) == nil
            and EqCompetition.canEnter(tier, animal.age or 0, EqCompetitionManager.ratingFor(record, event)) then
            count = count + 1
        end
    end
    return count
end


--- @param farmId number
--- @return number|nil left entries the farm can still make this month, nil when there is no limit
function EqCompetitionManager.entriesLeft(farmId)
    local limit = EqCompetitionManager.settings.entriesPerMonth or 0
    if limit <= 0 then return nil end
    return math.max(limit - (EqCompetitionManager.farmEntries[farmId] or 0), 0)
end


--- What it costs to take a horse to an event: a share of the base game's transport price for its age.
--- @param animal table RLRM Animal
--- @return number cost
function EqCompetitionManager.transportCost(animal)
    local subType = animal.getSubType ~= nil and animal:getSubType() or nil
    if subType ~= nil and subType.transportPrice ~= nil then
        local price = subType.transportPrice:get(math.max(animal.age or 0, 0))
        return math.floor(price * EqCompetitionManager.TRANSPORT_SHARE / 10 + 0.5) * 10
    end
    return EqCompetitionManager.TRANSPORT_FALLBACK
end


--- Enter a horse. One round entry and one monthly entry per horse at a time, and at most
--- entriesPerMonth entries a month per farm. The entry fee and the transport are paid at once.
--- @param eventId number
--- @param animal table RLRM Animal
--- @param farmId number
--- @return boolean ok
--- @return string message translated text for the player
function EqCompetitionManager.enter(eventId, animal, farmId)
    local event = EqCompetitionManager.events[eventId]
    if event == nil then return false, g_i18n:getText("eq_enter_noEvent") end

    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return false, g_i18n:getText("eq_enter_noEvent") end
    local left = EqCompetitionManager.entriesLeft(farmId)
    if left ~= nil and left <= 0 then
        return false, string.format(g_i18n:getText("eq_enter_farmLimit"), EqCompetitionManager.settings.entriesPerMonth)
    end

    local unavailable = EqCompetitionManager.unavailableReason(record, event.kind)
    if unavailable == "injured" then
        return false, string.format(g_i18n:getText("eq_enter_injured"), record.injury.monthsLeft)
    elseif unavailable == "rested" then
        return false, string.format(g_i18n:getText("eq_enter_rested"), EqConstants.MAX_ROUND_STARTS)
    elseif unavailable ~= nil then
        return false, g_i18n:getText("eq_enter_" .. unavailable)
    end

    local already = EqCompetitionManager.findEntry(record.id, event.kind)
    if already ~= nil then
        return false, string.format(g_i18n:getText("eq_enter_already"), EqCompetitionManager.eventTitle(already))
    end

    local tier = EqCompetitionManager.config.tierByName[event.tier]
    local rating = EqCompetitionManager.ratingFor(record, event)
    local ok, reason = EqCompetition.canEnter(tier, animal.age or 0, rating)
    if not ok then
        local text = g_i18n:getText("eq_enter_" .. reason)
        if reason == "tooYoung" then return false, string.format(text, tier.minAge, animal.age or 0) end
        if reason == "tooOld" then return false, string.format(text, tier.maxAge, animal.age or 0) end
        return false, string.format(text, rating, tier.minRating, tier.maxRating)
    end

    local transport = EqCompetitionManager.transportCost(animal)
    local farm = g_farmManager:getFarmById(farmId)
    if farm ~= nil and farm:getBalance() < event.fee + transport then return false, g_i18n:getText("eq_enter_noMoney") end

    g_currentMission:addMoney(-event.fee, farmId, MoneyType.EQ_ENTRY_FEES or MoneyType.OTHER, true, true)
    if transport > 0 then
        g_currentMission:addMoney(-transport, farmId, MoneyType.EQ_TRANSPORT or MoneyType.OTHER, true, true)
    end
    EqCompetitionManager.farmEntries[farmId] = (EqCompetitionManager.farmEntries[farmId] or 0) + 1
    local name = animal.getName ~= nil and animal:getName() or record.id
    table.insert(event.entries, { horseId = record.id, farmId = farmId, name = name })

    return true, string.format(g_i18n:getText("eq_enter_done"), name, EqCompetitionManager.eventTitle(event), rating,
        g_i18n:formatMoney(transport, 0, true, true))
end


-- SAVE AND LOAD (inside rlEquestrian.xml)

--- @param xmlFile table
--- @param key string such as "rlEquestrian.competition"
function EqCompetitionManager.saveToXMLFile(xmlFile, key)
    xmlFile:setString(key .. ".settings#cadence", EqCompetitionManager.settings.cadence)
    xmlFile:setBool(key .. ".settings#racing", EqCompetitionManager.settings.racing)
    xmlFile:setBool(key .. ".settings#injuries", EqCompetitionManager.settings.injuries)
    xmlFile:setBool(key .. ".settings#forcedRetirement", EqCompetitionManager.settings.forcedRetirement)
    xmlFile:setInt(key .. ".settings#entriesPerMonth", EqCompetitionManager.settings.entriesPerMonth)
    xmlFile:setInt(key .. "#nextEventId", EqCompetitionManager.nextEventId)

    local farmIds = {}
    for farmId in pairs(EqCompetitionManager.farmEntries) do table.insert(farmIds, farmId) end
    table.sort(farmIds)
    for i, farmId in ipairs(farmIds) do
        local farmKey = string.format("%s.farmEntries.farm(%d)", key, i - 1)
        xmlFile:setInt(farmKey .. "#farmId", farmId)
        xmlFile:setInt(farmKey .. "#entries", EqCompetitionManager.farmEntries[farmId])
    end

    local ids = {}
    for id in pairs(EqCompetitionManager.events) do table.insert(ids, id) end
    table.sort(ids)
    for i, id in ipairs(ids) do
        local event = EqCompetitionManager.events[id]
        local eventKey = string.format("%s.events.event(%d)", key, i - 1)
        xmlFile:setInt(eventKey .. "#id", event.id)
        xmlFile:setString(eventKey .. "#kind", event.kind)
        xmlFile:setString(eventKey .. "#discipline", event.discipline)
        xmlFile:setString(eventKey .. "#tier", event.tier)
        if event.going ~= nil then xmlFile:setString(eventKey .. "#going", event.going) end
        xmlFile:setFloat(eventKey .. "#fee", event.fee)
        xmlFile:setFloat(eventKey .. "#prize", event.prize)
        for j, entry in ipairs(event.entries) do
            local entryKey = string.format("%s.entry(%d)", eventKey, j - 1)
            xmlFile:setString(entryKey .. "#horseId", entry.horseId)
            xmlFile:setInt(entryKey .. "#farmId", entry.farmId)
            xmlFile:setString(entryKey .. "#name", entry.name)
        end
    end

    for i, summary in ipairs(EqCompetitionManager.results) do
        local resultKey = string.format("%s.results.result(%d)", key, i - 1)
        xmlFile:setInt(resultKey .. "#eventId", summary.eventId)
        xmlFile:setString(resultKey .. "#discipline", summary.discipline)
        xmlFile:setString(resultKey .. "#tier", summary.tier)
        if summary.going ~= nil then xmlFile:setString(resultKey .. "#going", summary.going) end
        xmlFile:setInt(resultKey .. "#field", summary.field)
        xmlFile:setInt(resultKey .. "#day", summary.day)
        for j, placing in ipairs(summary.placings) do
            local placingKey = string.format("%s.placing(%d)", resultKey, j - 1)
            xmlFile:setString(placingKey .. "#horseId", placing.horseId)
            xmlFile:setString(placingKey .. "#name", placing.name)
            xmlFile:setInt(placingKey .. "#farmId", placing.farmId)
            xmlFile:setInt(placingKey .. "#place", placing.place)
            xmlFile:setFloat(placingKey .. "#prize", placing.prize)
            if placing.status ~= nil then xmlFile:setString(placingKey .. "#status", placing.status) end
        end
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqCompetitionManager.loadFromXMLFile(xmlFile, key)
    local config = EqCompetitionManager.config
    EqCompetitionManager.reset()
    EqCompetitionManager.config = config
    if xmlFile == nil then return end

    local settings = EqCompetitionManager.settings
    settings.cadence = xmlFile:getString(key .. ".settings#cadence", settings.cadence)
    settings.racing = xmlFile:getBool(key .. ".settings#racing", settings.racing)
    settings.injuries = xmlFile:getBool(key .. ".settings#injuries", settings.injuries)
    settings.forcedRetirement = xmlFile:getBool(key .. ".settings#forcedRetirement", settings.forcedRetirement)
    settings.entriesPerMonth = xmlFile:getInt(key .. ".settings#entriesPerMonth", settings.entriesPerMonth)
    EqCompetitionManager.nextEventId = xmlFile:getInt(key .. "#nextEventId", 1)

    local f = 0
    while true do
        local farmKey = string.format("%s.farmEntries.farm(%d)", key, f)
        if not xmlFile:hasProperty(farmKey) then break end
        local farmId = xmlFile:getInt(farmKey .. "#farmId")
        if farmId ~= nil then EqCompetitionManager.farmEntries[farmId] = xmlFile:getInt(farmKey .. "#entries", 0) end
        f = f + 1
    end

    local i = 0
    while true do
        local eventKey = string.format("%s.events.event(%d)", key, i)
        if not xmlFile:hasProperty(eventKey) then break end
        local event = {
            id = xmlFile:getInt(eventKey .. "#id"),
            kind = xmlFile:getString(eventKey .. "#kind"),
            discipline = xmlFile:getString(eventKey .. "#discipline"),
            tier = xmlFile:getString(eventKey .. "#tier"),
            going = xmlFile:getString(eventKey .. "#going"),
            fee = xmlFile:getFloat(eventKey .. "#fee", 0),
            prize = xmlFile:getFloat(eventKey .. "#prize", 0),
            entries = {},
        }
        local j = 0
        while true do
            local entryKey = string.format("%s.entry(%d)", eventKey, j)
            if not xmlFile:hasProperty(entryKey) then break end
            table.insert(event.entries, {
                horseId = xmlFile:getString(entryKey .. "#horseId"),
                farmId = xmlFile:getInt(entryKey .. "#farmId"),
                name = xmlFile:getString(entryKey .. "#name", ""),
            })
            j = j + 1
        end
        -- Drop events whose discipline or tier a newer events.xml no longer has.
        if config ~= nil and config.disciplineByName[event.discipline] ~= nil and config.tierByName[event.tier] ~= nil then
            EqCompetitionManager.events[event.id] = event
        end
        i = i + 1
    end

    i = 0
    while true do
        local resultKey = string.format("%s.results.result(%d)", key, i)
        if not xmlFile:hasProperty(resultKey) then break end
        local summary = {
            eventId = xmlFile:getInt(resultKey .. "#eventId", 0),
            discipline = xmlFile:getString(resultKey .. "#discipline"),
            tier = xmlFile:getString(resultKey .. "#tier"),
            going = xmlFile:getString(resultKey .. "#going"),
            field = xmlFile:getInt(resultKey .. "#field", 0),
            day = xmlFile:getInt(resultKey .. "#day", 0),
            placings = {},
        }
        local j = 0
        while true do
            local placingKey = string.format("%s.placing(%d)", resultKey, j)
            if not xmlFile:hasProperty(placingKey) then break end
            table.insert(summary.placings, {
                horseId = xmlFile:getString(placingKey .. "#horseId"),
                name = xmlFile:getString(placingKey .. "#name", ""),
                farmId = xmlFile:getInt(placingKey .. "#farmId", 0),
                place = xmlFile:getInt(placingKey .. "#place", 0),
                prize = xmlFile:getFloat(placingKey .. "#prize", 0),
                status = xmlFile:getString(placingKey .. "#status"),
            })
            j = j + 1
        end
        table.insert(EqCompetitionManager.results, summary)
        i = i + 1
    end

    local open = 0
    for _ in pairs(EqCompetitionManager.events) do open = open + 1 end
    Log:info("EqCompetition: loaded %d open event(s), %d result(s)", open, #EqCompetitionManager.results)
end

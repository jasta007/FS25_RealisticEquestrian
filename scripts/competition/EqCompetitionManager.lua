--[[
    EqCompetitionManager.lua
    Runs the event calendar on the server.

    Two kinds of events:
    - Round events (Training, Novice, Intermediate) open every round and resolve at the start of
      the next one. A round is a day or a month, by the "cadence" setting, so players on long
      months (7+ days) and on 1 day a month both get a sensible pace.
    - Monthly events (Advanced, Championship) open at the start of each month and resolve at the
      start of the next.

    The calendar holds a few events at a time, a number drawn afresh each round from the "Events
    shown" settings (3 to 8 by default, more in multiplayer for each farm with horses), and at
    least half of each draw is events some farm's horse could enter.

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
-- Events on the calendar at once, Advanced and Championship included. Settings.
EqCompetitionManager.DEFAULT_EVENTS_MIN = 3
EqCompetitionManager.DEFAULT_EVENTS_MAX = 8

-- Getting a horse to an event costs a share of its transport price (the base game's, by age:
-- $600 for an adult), paid with the entry fee. A quarter keeps Novice worth entering.
EqCompetitionManager.TRANSPORT_SHARE = 0.25
-- Used when the horse's subtype has no transport price.
EqCompetitionManager.TRANSPORT_FALLBACK = 150
-- Horses a farm may enter in one event; more would make one event too lucrative.
EqCompetitionManager.MAX_HORSES_PER_EVENT = 2
-- An extra horse on the same Auto Transport trip (the farm already has one going to the event)
-- shares the truck: it pays this share of the haul. Quarantine abroad is still per horse.
EqCompetitionManager.TRANSPORT_EXTRA_HORSE_SHARE = 0.25

-- How an entry gets to the event: Auto pays transport and leaves at once; Manual is hauled to
-- the dealer by the player and must be delivered before the event runs.
EqCompetitionManager.TRANSPORT_AUTO = "auto"
EqCompetitionManager.TRANSPORT_MANUAL = "manual"

-- A Training Event under the monthly cadence counts as this share of a month's work.
EqCompetitionManager.MONTHLY_BOOST_MONTHS = 0.25


function EqCompetitionManager.reset()
    EqCompetitionManager.config = nil
    EqCompetitionManager.events = {}
    EqCompetitionManager.results = {}
    EqCompetitionManager.nextEventId = 1
    EqCompetitionManager.settings = { cadence = EqCompetitionManager.CADENCE_DAY, racing = true,
        injuries = true, forcedRetirement = false, entriesPerMonth = EqCompetitionManager.DEFAULT_ENTRIES_PER_MONTH,
        trainingRate = 1, eventsMin = EqCompetitionManager.DEFAULT_EVENTS_MIN,
        eventsMax = EqCompetitionManager.DEFAULT_EVENTS_MAX }
    EqCompetitionManager.farmEntries = {}   -- farmId -> entries made this month
    EqCompetitionManager.rivalSeed = nil     -- the save's named rivals are drawn from this (EqRivals)
    EqCompetitionManager.rivals = nil
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


--- Every farm's horses, for the schedule: farms with no horses are left out.
--- @return table list of lists of RLRM Animals
local function horsesByFarm()
    local farms = {}
    for _, farm in pairs(g_farmManager:getFarms()) do
        local farmId = farm.farmId
        if farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID then
            local horses = EqRLRM.listHorsesForFarm(farmId)
            if #horses > 0 then table.insert(farms, horses) end
        end
    end
    return farms
end


--- The range of events on the calendar at once, from the settings, widened for each further
--- farm with horses in multiplayer.
--- @param farmCount number farms with horses
--- @return number lo, number hi, number scale the multiplayer widening
function EqCompetitionManager.eventRange(farmCount)
    local settings, config = EqCompetitionManager.settings, EqCompetitionManager.config
    local lo = settings.eventsMin or EqCompetitionManager.DEFAULT_EVENTS_MIN
    local hi = math.max(lo, settings.eventsMax or EqCompetitionManager.DEFAULT_EVENTS_MAX)
    local scale = 1 + (config ~= nil and config.extraFarmShare or 0.5) * math.max(0, farmCount - 1)
    return math.floor(lo * scale + 0.5), math.floor(hi * scale + 0.5), scale
end


--- How many events of a kind to open: monthly events take a small share of the range, and the
--- round events fill the rest of it next to the monthly events already open.
--- @param kind string
--- @param rng table EqRandom
--- @param farmCount number farms with horses
--- @return number count
function EqCompetitionManager.eventCount(kind, rng, farmCount)
    local config = EqCompetitionManager.config
    local lo, hi, scale = EqCompetitionManager.eventRange(farmCount)
    if kind == EqCompetition.KIND_MONTH then
        local count = EqCompetition.drawCount(rng, math.floor((config.monthlyMin or 1) * scale + 0.5),
            math.floor((config.monthlyMax or 2) * scale + 0.5))
        -- Leave room for at least one round event.
        return math.max(0, math.min(count, hi - 1))
    end
    local monthly = 0
    for _, event in pairs(EqCompetitionManager.events) do
        if event.kind == EqCompetition.KIND_MONTH then monthly = monthly + 1 end
    end
    return math.max(1, EqCompetition.drawCount(rng, lo, hi) - monthly)
end


--- @param farms table from horsesByFarm
--- @param kind string
--- @return function enterable(disciplineName, tierName) true when some farm's horse could enter
local function enterableBy(farms, kind)
    local config = EqCompetitionManager.config
    local ready = {}
    for _, horses in ipairs(farms) do
        for _, animal in ipairs(horses) do
            local record = EqRegistry.getOrCreate(animal)
            if record ~= nil and EqCompetitionManager.unavailableReason(record, kind, animal) == nil then
                table.insert(ready, { record = record, age = animal.age or 0 })
            end
        end
    end
    local known = {}
    return function(disciplineName, tierName)
        local key = disciplineName .. " " .. tierName
        if known[key] == nil then
            known[key] = false
            local tier = config.tierByName[tierName]
            for _, horse in ipairs(ready) do
                local rating = EqCompetitionManager.ratingFor(horse.record, { discipline = disciplineName, tier = tierName })
                if EqCompetition.canEnter(tier, horse.age, rating) then
                    known[key] = true
                    break
                end
            end
        end
        return known[key]
    end
end


--- @param kind string EqCompetition.KIND_ROUND or KIND_MONTH
function EqCompetitionManager.openRound(kind)
    local config = EqCompetitionManager.config
    if config == nil then return end

    local farms = horsesByFarm()
    local rng = roundRng(kind)
    local options = { count = EqCompetitionManager.eventCount(kind, rng, #farms), enterable = enterableBy(farms, kind) }
    local drawn = EqCompetition.drawSchedule(config, rng, kind, EqCompetitionManager.settings.racing,
        EqCompetitionManager.homeRegion(), options)
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


--- Tell the farm's player, and write the same line in the farm's RLRM message log.
--- @param farmId number
--- @param text string
--- @param messageId string|nil one of EqMessages.TYPES, nil for no log line
--- @param animal table|nil RLRM Animal the line is about
--- @param horseId string|nil the horse whose results the log line opens
local function notify(farmId, text, messageId, animal, horseId)
    if g_currentMission:getFarmId() == farmId then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
    if messageId ~= nil then EqMessages.post(farmId, messageId, text, animal, horseId) end
end


--- @return table rivals the save's named rivals, drawn the first time they are needed
function EqCompetitionManager.getRivals()
    local config = EqCompetitionManager.config
    if config == nil then return {} end
    if EqCompetitionManager.rivals == nil then
        if EqCompetitionManager.rivalSeed == nil then EqCompetitionManager.rivalSeed = math.random(1, 999999999) end
        EqCompetitionManager.rivals = EqRivals.generate(EqCompetitionManager.rivalSeed, config.disciplines)
    end
    return EqCompetitionManager.rivals
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


--- The event's own name, such as "1.20m Jumping" or "Pallegney Grand Prix": eq_event_<discipline>_<tier>,
--- or the tier and discipline when there is no such text. A named event's text holds %s for its venue.
--- @param discipline string
--- @param tier string
--- @param venue string|nil the event's venue; nil (a save from before venues) uses the first one
--- @return string name
function EqCompetitionManager.eventName(discipline, tier, venue)
    local key = string.format("eq_event_%s_%s", discipline, tier)
    if g_i18n.hasText ~= nil and not g_i18n:hasText(key) then
        return string.format("%s %s", EqCompetitionManager.tierTitle(tier), EqCompetitionManager.disciplineTitle(discipline))
    end
    local text = g_i18n:getText(key)
    if not text:find("%%s") then return text end
    return string.format(text, venue or EqCompetitionManager.defaultVenue())
end


--- @return string venue the first venue in events.xml, for named events saved without one
function EqCompetitionManager.defaultVenue()
    local regions = EqCompetitionManager.config ~= nil and EqCompetitionManager.config.regions or nil
    local first = regions ~= nil and regions[1] ~= nil and regions[1].venues[1] or nil
    return first or "Riverbend Springs"
end


--- @param going string|nil the event's conditions, nil indoors
--- @return string text such as "Firm", or "Indoor"
function EqCompetitionManager.conditionsText(going)
    return g_i18n:getText(going ~= nil and ("eq_going_" .. going) or "eq_going_indoor")
end


--- @param event table
--- @return string title such as "1.20m Jumping (Intermediate)", without the event number players never need
function EqCompetitionManager.eventTitle(event)
    return string.format("%s (%s)", EqCompetitionManager.eventName(event.discipline, event.tier, event.venue),
        EqCompetitionManager.tierTitle(event.tier))
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


--- A horse's rating for an event, from its record: its stats, plus its experience in the
--- discipline.
--- @param record table
--- @param event table
--- @return number rating 0..100
function EqCompetitionManager.ratingFor(record, event)
    local discipline = EqCompetitionManager.config.disciplineByName[event.discipline]
    local rating = EqCompetition.rating(record.trained, discipline, getGoing(event))
    return math.min(100, rating + EqExperience.ratingBonus(record, event.discipline))
end


--- A horse as it starts an event: its rating, condition on the day, stats for its checks, and
--- for eventing its phase ratings.
--- @param record table
--- @param animal table RLRM Animal
--- @param event table
--- @param farmId number|nil the horse's farm, for its facilities
--- @return table entrant for EqCompetition.run
function EqCompetitionManager.entrantFor(record, animal, event, farmId)
    local config = EqCompetitionManager.config
    local discipline = config.disciplineByName[event.discipline]
    local rating = EqCompetitionManager.ratingFor(record, event)
    local phaseRatings = nil
    if discipline.phases ~= nil then
        local ratings = {}
        for _, name in ipairs(discipline.phases) do
            if config.disciplineByName[name] ~= nil then
                ratings[name] = EqCompetitionManager.ratingFor(record, { discipline = name, going = event.going })
            end
        end
        phaseRatings = EqPerformance.scalePhases(ratings, rating)
    end
    return {
        key = record.id,
        rating = rating,
        condition = EqCompetition.condition(animal.fitness, animal.health)
            * EqFacilityHooks.conditionFactor(farmId, event.discipline),
        stats = record.trained,
        phaseRatings = phaseRatings,
    }
end


--- @param record table
--- @return string text the horse's specialty, such as "Dressage", "3 Day Eventer" or "All Rounder"
function EqCompetitionManager.specialtyText(record)
    local kind, names = EqExperience.specialty(record, EqCompetitionManager.config.disciplines)
    if kind == "one" then return EqCompetitionManager.disciplineTitle(names[1]) end
    if kind == "pair" then
        return string.format(g_i18n:getText("eq_specialty_pair"), EqCompetitionManager.disciplineTitle(names[1]),
            EqCompetitionManager.disciplineTitle(names[2]))
    end
    return g_i18n:getText("eq_specialty_" .. kind)
end


--- What a horse could expect from an event, for the Events tab.
--- @param record table
--- @param animal table RLRM Animal
--- @param event table
--- @return table prospects { chance, success (a SUCCESS_BANDS name), benefit (a BENEFIT_BANDS
---     name, nil when the event gives no training), risk (an EqRisk.RISK_BANDS name, nil with
---     injuries off) }
function EqCompetitionManager.prospects(record, animal, event)
    local config = EqCompetitionManager.config
    local discipline = config.disciplineByName[event.discipline]
    local tier = config.tierByName[event.tier]
    local entrant = EqCompetitionManager.entrantFor(record, animal, event, EqFacilityHooks.farmOfAnimal(animal))
    local rating = entrant.rating
    local elimination = EqRisk.eliminationChance(discipline, tier, rating, record.trained.temperament or 0)
    -- Seeded by event and horse, so the word doesn't flicker each time the tab opens.
    local rng = EqRandom.new(string.format("odds %s %s", tostring(event.id), record.id))
    local chance = EqCompetition.podiumChance(event, config, rating, entrant.condition, elimination, rng, nil, entrant)

    local benefit = nil
    if tier.trainingBoost > 0 then
        local _, band = EqTraining.boostBenefit(record.trained, record:getShownCeilings(), discipline.weights, animal.age or 0,
            tier.trainingBoost)
        benefit = band
    end

    local risk = nil
    if EqCompetitionManager.settings.injuries then
        local going = EqCompetitionManager.goingByName(event.going)
        risk = EqRisk.riskBand(EqRisk.runInjuryChance(discipline, tier, going, animal.fitness or 0,
            record.trained.stamina or 0, elimination, EqCompetitionManager.travelInjury(event), animal.health))
    end
    return { chance = chance, success = EqCompetition.successBand(chance), benefit = benefit, risk = risk }
end


--- @param name string|nil
--- @return table|nil going from events.xml
function EqCompetitionManager.goingByName(name)
    for _, going in ipairs(EqCompetitionManager.config.goings) do
        if going.name == name then return going end
    end
    return nil
end


--- An event's injury risk for a typical horse: discipline, level, conditions and the trip.
--- @param event table
--- @return string|nil band an EqRisk.RISK_BANDS name, nil with injuries off
function EqCompetitionManager.eventRisk(event)
    if not EqCompetitionManager.settings.injuries then return nil end
    local config = EqCompetitionManager.config
    return EqRisk.riskBand(EqRisk.eventInjuryChance(config.disciplineByName[event.discipline],
        config.tierByName[event.tier], EqCompetitionManager.goingByName(event.going), EqCompetitionManager.travelInjury(event)))
end


--- @param band string|nil from eventRisk or prospects
--- @return string text
function EqCompetitionManager.riskText(band)
    return g_i18n:getText("eq_risk_" .. (band or "off"))
end


--- @param name string injury name from events.xml
--- @return string text such as "a tendon injury"
function EqCompetitionManager.injuryTitle(name)
    return g_i18n:getText("eq_injury_" .. name)
end


--- Give a horse its injury after an event, or end its career.
--- @param record table
--- @param entry table { name, farmId }
--- @param injury table EqRisk.rollInjury outcome
--- @param event table
--- @param animal table|nil RLRM Animal, for the message log and the Diseases page
function EqCompetitionManager.applyInjury(record, entry, injury, event, animal)
    record.career.injuries = record.career.injuries + 1
    local info = EqInjury.info[injury.name]
    EqStatLog.add(record.id, g_currentMission.environment.currentMonotonicDay or 0, "injury", nil,
        { string.format("Injured at %s: %s%s. No training until it heals.", EqCompetitionManager.eventTitle(event),
            injury.name, injury.careerEnding and ", career-ending" or "") }, record.trained)
    if injury.careerEnding then
        record.retired = true
        record.careerEnded = true
        record.injury = nil
        notify(entry.farmId, string.format(g_i18n:getText("eq_injury_careerEnding"), entry.name,
            EqCompetitionManager.eventTitle(event)), "EQ_CAREER_ENDED", animal, record.id)
        return
    end

    local onRLRM = EqInjury.start(record, animal, injury.name)
    local rest = EqInjury.wholeMonths(EqInjury.restMonths(injury.name))
    local text
    if onRLRM and info ~= nil then
        local course = info.treatDays ~= nil
            and string.format(g_i18n:getText(info.treatDays == 1 and "eq_ui_dayCount" or "eq_ui_days"), info.treatDays)
            or string.format(g_i18n:getText("eq_ui_months"), EqInjury.wholeMonths(info.treatMonths))
        local fee = g_i18n:formatMoney(EqInjury.fee(info.cost, record.retired), 0, true, true)
        if info.treatDays == nil then fee = string.format(g_i18n:getText("eq_ui_perMonth"), fee) end
        text = string.format(g_i18n:getText("eq_injury_newTreatable"), entry.name, EqCompetitionManager.eventTitle(event),
            EqCompetitionManager.injuryTitle(injury.name), course, fee, rest)
    else
        text = string.format(g_i18n:getText("eq_injury_newRest"), entry.name, EqCompetitionManager.eventTitle(event),
            EqCompetitionManager.injuryTitle(injury.name), rest)
    end
    notify(entry.farmId, text, "EQ_INJURED", animal, record.id)
end


--- The names of the top three: our horses (any farm's) by their names, simulated rivals by one
--- of the save's named rivals at their level (EqRivals.pick).
--- @param results table from EqCompetition.run
--- @param byKey table horse id -> { entry }
--- @param discipline string
--- @param rng table EqRandom
--- @return table names first place first, up to three
function EqCompetitionManager.podiumNames(results, byKey, discipline, rng)
    local rivals, used, names = EqCompetitionManager.getRivals(), {}, {}
    for _, runner in ipairs(results) do
        if runner.place > #EqCompetition.PRIZE_SHARES then break end
        local mine = runner.key ~= nil and byKey[runner.key] or nil
        local name = mine ~= nil and mine.entry.name or EqRivals.pick(rivals, discipline, runner.rating or 0, used, rng)
        table.insert(names, name or "?")
    end
    return names
end


--- Keep a result on the horse's record, for the Events tab's Results page.
--- @param record table
--- @param summary table the event's summary
--- @param placing table { place, prize, status }
--- @param lines table the story lines
local function keepResult(record, summary, placing, lines)
    if record == nil then return end
    record:addResult({ day = summary.day, discipline = summary.discipline, tier = summary.tier, venue = summary.venue,
        place = placing.place, field = summary.field, prize = placing.prize, status = placing.status, lines = lines })
end


--- Resolve one closed event: scratches, eliminations and injuries, then score the field, pay
--- prizes, update careers, and tell the owners how their horses got on: one line now (with how
--- the run went), and a few lines kept on the horse for the Results page.
--- @param event table
--- @param horses table from indexHorses
function EqCompetitionManager.resolve(event, horses)
    local config = EqCompetitionManager.config
    local tier = config.tierByName[event.tier]
    local discipline = config.disciplineByName[event.discipline]
    local riskRng = EqRandom.new("risk " .. event.id)
    local summary = { eventId = event.id, discipline = event.discipline, tier = event.tier, going = event.going,
        venue = event.venue, region = event.region, field = 0, day = g_currentMission.environment.currentMonotonicDay or 0, placings = {} }
    local starters, byKey = {}, {}
    local title = EqCompetitionManager.eventTitle(event)

    for _, entry in ipairs(event.entries) do
        local horse = horses[entry.horseId]
        local record = EqRegistry.getById(entry.horseId)
        if horse == nil or record == nil then
            notify(entry.farmId, string.format(g_i18n:getText("eq_result_gone"), entry.name, title), "EQ_GONE")
        elseif not EqCompetitionManager.isDelivered(entry) then
            -- Manual Transport, never delivered: a non-starter, and the fee is gone.
            local placing = { horseId = entry.horseId, name = entry.name, farmId = entry.farmId,
                place = 0, prize = 0, status = "notDelivered" }
            table.insert(summary.placings, placing)
            local text = string.format(g_i18n:getText("eq_result_notDelivered"), entry.name, title)
            notify(entry.farmId, text, "EQ_NOT_DELIVERED", horse.animal, entry.horseId)
            keepResult(record, summary, placing, { text })
        else
            -- A mare entered early in her pregnancy can pass the limit before the event runs.
            local reason = EqRisk.scratchReason(record, horse.animal.health, riskRng)
            if reason == nil and EqCompetitionManager.isTooFarInFoal(horse.animal) then reason = "inFoal" end
            if reason == nil and EqInjury.isSick(horse.animal) then reason = "sick" end
            local reasonKey = reason ~= nil and ("eq_scratch_" .. reason) or nil
            if reason == nil then
                -- Off the lorry, tacked up and to the start: only a very fractious horse fails.
                local started, variant = EqPerformance.startCheck(record.trained,
                    EqCompetition.condition(horse.animal.fitness, horse.animal.health), EqRandom.new("start " .. event.id .. " " .. entry.horseId))
                if not started then reason, reasonKey = "fractious", "eq_scratch_fractious_" .. variant end
            end
            if reason ~= nil then
                local refund = math.floor((event.fee or 0) * EqRisk.SCRATCH_REFUND + 0.5)
                if refund > 0 then
                    g_currentMission:addMoney(refund, entry.farmId, MoneyType.EQ_ENTRY_FEES or MoneyType.OTHER, true, true)
                end
                local placing = { horseId = entry.horseId, name = entry.name, farmId = entry.farmId,
                    place = 0, prize = 0, status = "scratched" }
                table.insert(summary.placings, placing)
                local text = string.format(g_i18n:getText("eq_result_scratched"), entry.name, title,
                    g_i18n:getText(reasonKey), g_i18n:formatMoney(refund, 0, true, true))
                notify(entry.farmId, text, "EQ_SCRATCHED", horse.animal, entry.horseId)
                keepResult(record, summary, placing, { text })
            else
                local starter = EqCompetitionManager.entrantFor(record, horse.animal, event, entry.farmId)
                starter.temperament = record.trained.temperament or 0
                starter.stamina = record.trained.stamina or 0
                starter.fitness = horse.animal.fitness or 0
                starter.travel = EqCompetitionManager.travelInjury(event)
                starter.health = horse.animal.health
                table.insert(starters, starter)
                byKey[entry.horseId] = { entry = entry, record = record, animal = horse.animal }
                EqExperience.addStart(record, discipline)
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
    local podium = EqStory.podiumLine(EqCompetitionManager.podiumNames(results, byKey, event.discipline,
        EqRandom.new("podium " .. event.id)))

    -- Each starter's story, finished once its injuries are known.
    local stories = {}

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

            local deltas = nil
            if tier.trainingBoost > 0 then
                local cadenceDay = EqCompetitionManager.settings.cadence == EqCompetitionManager.CADENCE_DAY
                local timeAdjustment = cadenceDay and (g_currentMission.environment.timeAdjustment or 1)
                    or EqCompetitionManager.MONTHLY_BOOST_MONTHS
                deltas = EqTraining.applyBoost(record, record:getCeilings(), discipline.weights,
                    tier.trainingBoost, mine.animal.age or 0, timeAdjustment,
                    EqSettings.trainingRate(EqCompetitionManager.settings))
                EqStatLog.add(record.id, summary.day, "event", deltas, { string.format("Training boost from %s (%s), placed %d of %d: %.0f%% of a day's work at staff level",
                    title, event.tier, runner.place, summary.field, tier.trainingBoost * 100) }, record.trained)
            end

            local placing = { horseId = runner.key, name = entry.name, farmId = entry.farmId, place = runner.place, prize = runner.prize }
            table.insert(summary.placings, placing)

            local performance = g_i18n:getText(EqPerformance.storyKey(discipline, runner.run, false, config, runner.place))
            local text
            if runner.prize > 0 then
                text = string.format(g_i18n:getText("eq_result_placed"), entry.name, runner.place, summary.field,
                    title, g_i18n:formatMoney(runner.prize, 0, true, true))
            else
                text = string.format(g_i18n:getText("eq_result_placedNoPrize"), entry.name, runner.place, summary.field, title)
            end
            notify(entry.farmId, text .. " " .. performance, runner.prize > 0 and "EQ_PLACED" or "EQ_FINISHED", mine.animal, runner.key)
            stories[runner.key] = { placing = placing, performance = performance, podium = podium,
                phases = EqStory.phasesLine(discipline.phases, runner.phasePlaces), gains = EqStory.gainsLine(deltas) }
        end
    end

    -- How an eliminated horse went out: its checks, run for the story alone.
    local storyRng = EqRandom.new("story " .. event.id)
    local luck = discipline.racing and EqCompetition.RACING_LUCK_SD or EqCompetition.LUCK_SD
    for _, starter in ipairs(eliminated) do
        local mine = byKey[starter.key]
        local career = mine.record.career
        career.starts = career.starts + 1
        career.eliminations = career.eliminations + 1
        local placing = { horseId = starter.key, name = mine.entry.name, farmId = mine.entry.farmId,
            place = 0, prize = 0, status = "eliminated" }
        table.insert(summary.placings, placing)
        local run = EqPerformance.run(discipline, config, tier, starter, luck, storyRng)
        local performance = g_i18n:getText(EqPerformance.storyKey(discipline, run, true, config))
        notify(mine.entry.farmId, string.format(g_i18n:getText(discipline.racing and "eq_result_pulledUp" or "eq_result_eliminated"),
            mine.entry.name, title) .. " " .. performance, "EQ_ELIMINATED", mine.animal, starter.key)
        stories[starter.key] = { placing = placing, performance = performance, podium = podium }
    end

    -- A show is a crowd, a lorry ride and a hard day: every starter rolls RLRM's horse diseases too.
    local illnessRng = EqRandom.new("illness " .. event.id)
    for _, starter in ipairs(starters) do
        local mine = byKey[starter.key]
        local injury = outcomes[starter.key].injury
        if injury ~= nil then
            EqCompetitionManager.applyInjury(mine.record, mine.entry, injury, event, mine.animal)
        end
        for _, illness in ipairs(EqInjury.rollIllness(mine.animal, starter.travel, illnessRng)) do
            notify(mine.entry.farmId, string.format(g_i18n:getText("eq_illness_new"), mine.entry.name, illness, title),
                "EQ_ILL", mine.animal, starter.key)
        end
        local story = stories[starter.key]
        if story ~= nil then
            story.injury = EqStory.injuryLine(injury)
            keepResult(mine.record, summary, story.placing, EqStory.lines(story))
        end
    end

    if #summary.placings == 0 then return end
    table.insert(EqCompetitionManager.results, 1, summary)
    while #EqCompetitionManager.results > EqCompetitionManager.RESULTS_KEPT do table.remove(EqCompetitionManager.results) end
end


--- Start of a month: reset the month's starts, fade event experience not kept up, and count a bought horse's months on the farm (its real potential
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
            EqExperience.monthlyFade(record)
            EqCompetitionManager.countOwnedMonth(record, horse.farmId, name, horse.animal)
        end

    end
end


--- Every day: move each injured horse's rest along (see EqInjury.daily), and say when one has
--- healed. Treatment is the player's choice on RLRM's Diseases page, and RLRM bills it.
--- @param horses table from indexHorses
function EqCompetitionManager.dailyCare(horses)
    local ids = {}
    for id in pairs(horses) do table.insert(ids, id) end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local horse = horses[id]
        local record = EqRegistry.getById(id)
        if record ~= nil and record.injury ~= nil and EqInjury.daily(record, horse.animal) then
            local name = horse.animal.getName ~= nil and horse.animal:getName() or id
            notify(horse.farmId, string.format(g_i18n:getText("eq_injury_recovered"), name), "EQ_RECOVERED", horse.animal)
        end
    end
end


--- One more month on the farm for a horse bought from the dealer; at REVEAL_MONTHS its real
--- potential shows, and the owner hears how it compares with what the dealer said.
--- @param record table
--- @param farmId number
--- @param name string
--- @param animal table|nil RLRM Animal, for the message log
function EqCompetitionManager.countOwnedMonth(record, farmId, name, animal)
    if record.ownedMonths == nil then return end
    record.ownedMonths = record.ownedMonths + 1
    if record.advertised ~= nil and not record.revealed and record.ownedMonths >= EqConstants.REVEAL_MONTHS then
        record.revealed = true
        local verdict = EqDealer.verdict(record.advertised, record:getCeilings())
        notify(farmId, string.format(g_i18n:getText("eq_reveal_" .. verdict), name), "EQ_REVEAL_" .. string.upper(verdict), animal)
    end
end


--- Why a horse cannot be entered in anything right now, whatever the event.
--- @param record table
--- @param kind string the event's kind
--- @param animal table|nil RLRM Animal, for the in-foal check
--- @return string|nil reason "retired", "injured", "sick", "unwell", "settling", "inFoal", "foaled" or "rested", nil when it can go
function EqCompetitionManager.unavailableReason(record, kind, animal)
    if record.retired then return "retired" end
    if record.injury ~= nil then return "injured" end
    if EqInjury.isSick(animal) then return "sick" end
    if animal ~= nil and (animal.health or 100) <= EqRisk.ENTRY_HEALTH_MIN then return "unwell" end
    if record:isSettling() then return "settling" end
    if EqCompetitionManager.isTooFarInFoal(animal) then return "inFoal" end
    if EqCompetitionManager.isRecoveringFromFoaling(animal) then return "foaled" end
    if kind == EqCompetition.KIND_ROUND and (record.monthStarts or 0) >= EqConstants.MAX_ROUND_STARTS then
        return "rested"
    end
    return nil
end


--- @param animal table|nil RLRM Animal
--- @return boolean true for a mare past IN_FOAL_LIMIT of her pregnancy
function EqCompetitionManager.isTooFarInFoal(animal)
    return animal ~= nil and animal.isPregnant == true and (animal.reproduction or 0) > EqConstants.IN_FOAL_LIMIT
end


--- @param animal table|nil RLRM Animal
--- @return boolean true for a mare that foaled less than FOALING_REST_MONTHS ago
function EqCompetitionManager.isRecoveringFromFoaling(animal)
    return animal ~= nil and animal.isParent == true and animal.gender == "female"
        and (animal.monthsSinceLastBirth or EqConstants.FOALING_REST_MONTHS) < EqConstants.FOALING_REST_MONTHS
end


--- Retire a horse from competition, or bring it back. An injured horse still has to heal, but
--- its treatment fee drops to EqInjury.RETIRED_FEE_SHARE (back up if it returns).
--- @param record table
--- @param retired boolean
--- @return boolean ok
--- @return string message
function EqCompetitionManager.setRetired(record, retired)
    if not retired and record.careerEnded then return false, g_i18n:getText("eq_retire_careerEnded") end
    record.retired = retired
    if retired then
        if record.injury ~= nil then
            return true, string.format(g_i18n:getText("eq_retire_doneInjured"),
                math.floor((1 - EqInjury.RETIRED_FEE_SHARE) * 100 + 0.5))
        end
        return true, g_i18n:getText("eq_retire_done")
    end
    return true, g_i18n:getText("eq_retire_undone")
end


--- @param kind string|nil only events of this kind, nil for all
--- @param horses table|nil from indexHorses, built when nil
--- @return table animals RLRM Animals entered in open events
function EqCompetitionManager.enteredAnimals(kind, horses)
    horses = horses or indexHorses()
    local animals = {}
    for _, event in pairs(EqCompetitionManager.events) do
        if kind == nil or event.kind == kind then
            for _, entry in ipairs(event.entries) do
                local horse = horses[entry.horseId]
                if horse ~= nil then table.insert(animals, horse.animal) end
            end
        end
    end
    return animals
end


--- Redraw the pastures of horses leaving for, or back from, events. Does nothing when the
--- away-horses hook is off (it needs RLRM's visual update).
--- @param animals table RLRM Animals
function EqCompetitionManager.refreshAway(animals)
    if EqAway ~= nil and EqRLRM.features.awayVisuals and #animals > 0 then EqAway.refreshAll(animals) end
end


--- Close and resolve every open event of a kind, then open the next round of that kind.
--- @param kind string
function EqCompetitionManager.turnOver(kind)
    local horses = indexHorses()
    local returning = EqCompetitionManager.enteredAnimals(kind, horses)
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
    EqCompetitionManager.refreshAway(returning)
end


function EqCompetitionManager.onDayChanged()
    EqCompetitionManager.dailyCare(indexHorses())
    if EqCompetitionManager.settings.cadence == EqCompetitionManager.CADENCE_DAY then
        EqCompetitionManager.turnOver(EqCompetition.KIND_ROUND)
    end
end


function EqCompetitionManager.onPeriodChanged()
    EqCompetitionManager.farmEntries = {}
    EqCompetitionManager.monthlyCare(indexHorses())
    -- Monthly events first, so the round's draw knows how many are already on the calendar.
    EqCompetitionManager.turnOver(EqCompetition.KIND_MONTH)
    if EqCompetitionManager.settings.cadence == EqCompetitionManager.CADENCE_MONTH then
        EqCompetitionManager.turnOver(EqCompetition.KIND_ROUND)
    end
end


--- Open the first rounds on a new game, or after loading a save that had none.
function EqCompetitionManager.ensureOpen()
    local hasRound, hasMonth = false, false
    for _, event in pairs(EqCompetitionManager.events) do
        if event.kind == EqCompetition.KIND_ROUND then hasRound = true else hasMonth = true end
    end
    if not hasMonth then EqCompetitionManager.openRound(EqCompetition.KIND_MONTH) end
    if not hasRound then EqCompetitionManager.openRound(EqCompetition.KIND_ROUND) end
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
        if record ~= nil and EqCompetitionManager.unavailableReason(record, event.kind, animal) == nil
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
    local transport = EqCompetitionManager.config ~= nil and EqCompetitionManager.config.transport or nil
    local share = transport ~= nil and transport.share or EqCompetitionManager.TRANSPORT_SHARE
    local subType = animal.getSubType ~= nil and animal:getSubType() or nil
    if subType ~= nil and subType.transportPrice ~= nil then
        local price = subType.transportPrice:get(math.max(animal.age or 0, 0))
        return math.floor(price * share / 10 + 0.5) * 10
    end
    return transport ~= nil and transport.fallback or EqCompetitionManager.TRANSPORT_FALLBACK
end


--- @param text string
--- @return string text lower case, letters and digits only (accented letters dropped)
local function simplify(text)
    return (text:lower():gsub("[^%w]", ""))
end


--- The player's home region: a map listed in events.xml by its title, else RLRM's map country
--- (which RLRM's own "map country" setting can change), else the default. Every client reads
--- the same map, so the schedule draws the same events everywhere.
--- @return string|nil region nil before the config is loaded
function EqCompetitionManager.homeRegion()
    local config = EqCompetitionManager.config
    if config == nil or config.home == nil then return nil end
    local home = config.home

    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if info ~= nil then
        -- Match loosely: the title may be translated or spelt without its accents (Catuai).
        local names = simplify(tostring(info.mapTitle or "")) .. " " .. simplify(tostring(info.mapId or ""))
        for title, region in pairs(home.maps) do
            local key = simplify(title)
            if key ~= "" and names:find(key, 1, true) then return region end
        end
    end

    local rl = EqRLRM.get("RealisticLivestock")
    if rl ~= nil and rl.getMapCountryCode ~= nil then
        local ok, code = pcall(rl.getMapCountryCode)
        if ok and code ~= nil and home.countries[code] ~= nil then return home.countries[code] end
    end
    return home.default
end


--- @param event table|nil
--- @return string distance "local", "near" or "far" from the player's home region
function EqCompetitionManager.eventDistance(event)
    local config = EqCompetitionManager.config
    if event == nil or event.region == nil or config == nil then return "local" end
    return EqCompetition.distanceBetween(config, EqCompetitionManager.homeRegion(), event.region)
end


--- @param event table
--- @param farmId number
--- @return boolean true when the farm has entered MAX_HORSES_PER_EVENT horses in the event
function EqCompetitionManager.eventFull(event, farmId)
    local count = 0
    for _, entry in ipairs(event.entries or {}) do
        if entry.farmId == farmId then count = count + 1 end
    end
    return count >= EqCompetitionManager.MAX_HORSES_PER_EVENT
end


--- @param event table
--- @param farmId number|nil
--- @return boolean true when the farm already sends a horse to the event by Auto Transport
function EqCompetitionManager.sharesTruck(event, farmId)
    if farmId == nil or event.entries == nil then return false end
    for _, entry in ipairs(event.entries) do
        if entry.farmId == farmId and entry.transport ~= EqCompetitionManager.TRANSPORT_MANUAL then return true end
    end
    return false
end


--- @param event table|nil
--- @return number factor how much the trip raises the injury chance (1 at home)
function EqCompetitionManager.travelInjury(event)
    local config = EqCompetitionManager.config
    local distance = config ~= nil and config.distances ~= nil and config.distances[EqCompetitionManager.eventDistance(event)] or nil
    return distance ~= nil and distance.injury or 1
end


--- What getting a horse to an event costs, on top of the entry fee.
--- @param animal table RLRM Animal
--- @param event table
--- @param farmId number|nil the entering farm; a second Auto Transport horse shares the truck
--- @return number auto Auto Transport (long-haul and quarantine included for a trip abroad)
--- @return number manual Manual Transport (nothing locally; the dealer's quarantine yard abroad)
function EqCompetitionManager.transportCosts(animal, event, farmId)
    local haul = EqCompetitionManager.transportCost(animal)
    local config = EqCompetitionManager.config
    local distance = config ~= nil and config.distances ~= nil and config.distances[EqCompetitionManager.eventDistance(event)] or nil
    local quarantine, quarantineYard = 0, 0
    if distance ~= nil then
        haul = haul * distance.factor
        quarantine, quarantineYard = distance.quarantine, distance.quarantineYard
    end
    if EqCompetitionManager.sharesTruck(event, farmId) then haul = haul * EqCompetitionManager.TRANSPORT_EXTRA_HORSE_SHARE end
    return math.floor(haul / 10 + 0.5) * 10 + quarantine, quarantineYard
end


--- @param entry table
--- @return boolean true when the horse is at (or on its way to) the event
function EqCompetitionManager.isDelivered(entry)
    return entry.transport ~= EqCompetitionManager.TRANSPORT_MANUAL or entry.delivered == true
end


--- Mark a horse's Manual entries as delivered: the horse leaves its pasture for the event.
--- EqDelivery calls this at the dealer; the eqDeliver console command does too, for testing.
--- @param animal table RLRM Animal
--- @return number count entries delivered
function EqCompetitionManager.deliver(animal)
    local id = EqRegistry.getId(animal)
    local count = 0
    for _, event in pairs(EqCompetitionManager.events) do
        for _, entry in ipairs(event.entries) do
            if entry.horseId == id and not EqCompetitionManager.isDelivered(entry) then
                entry.delivered = true
                count = count + 1
            end
        end
    end
    if count > 0 then EqCompetitionManager.refreshAway({ animal }) end
    return count
end


--- @param animal table RLRM Animal
--- @return boolean true when the horse has a Manual entry still waiting for delivery
function EqCompetitionManager.awaitingDelivery(animal)
    local id = EqRegistry.getId(animal)
    for _, event in pairs(EqCompetitionManager.events) do
        for _, entry in ipairs(event.entries) do
            if entry.horseId == id and not EqCompetitionManager.isDelivered(entry) then return true end
        end
    end
    return false
end


--- Enter a horse. One round entry and one monthly entry per horse at a time, and at most
--- entriesPerMonth entries a month per farm. The entry fee and the transport are paid at once.
--- @param eventId number
--- @param animal table RLRM Animal
--- @param farmId number
--- @param transport string|nil TRANSPORT_AUTO (default) or TRANSPORT_MANUAL
--- @return boolean ok
--- @return string message translated text for the player
function EqCompetitionManager.enter(eventId, animal, farmId, transport)
    local manual = transport == EqCompetitionManager.TRANSPORT_MANUAL
    local event = EqCompetitionManager.events[eventId]
    if event == nil then return false, g_i18n:getText("eq_enter_noEvent") end

    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return false, g_i18n:getText("eq_enter_noEvent") end
    local left = EqCompetitionManager.entriesLeft(farmId)
    if left ~= nil and left <= 0 then
        return false, string.format(g_i18n:getText("eq_enter_farmLimit"), EqCompetitionManager.settings.entriesPerMonth)
    end

    local unavailable = EqCompetitionManager.unavailableReason(record, event.kind, animal)
    if unavailable == "injured" then
        return false, string.format(g_i18n:getText("eq_enter_injured"), EqInjury.monthsLeft(record, animal) or 1)
    elseif unavailable == "rested" then
        return false, string.format(g_i18n:getText("eq_enter_rested"), EqConstants.MAX_ROUND_STARTS)
    elseif unavailable ~= nil then
        return false, g_i18n:getText("eq_enter_" .. unavailable)
    end

    local already = EqCompetitionManager.findEntry(record.id, event.kind)
    if already ~= nil then
        return false, string.format(g_i18n:getText("eq_enter_already"), EqCompetitionManager.eventTitle(already))
    end
    if EqCompetitionManager.eventFull(event, farmId) then
        return false, string.format(g_i18n:getText("eq_enter_eventFull"), EqCompetitionManager.MAX_HORSES_PER_EVENT)
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

    local autoCost, manualCost = EqCompetitionManager.transportCosts(animal, event, farmId)
    local cost = manual and manualCost or autoCost
    local farm = g_farmManager:getFarmById(farmId)
    -- Everything is paid now, so a farm that cannot cover it all is turned away rather than sent negative.
    local total = event.fee + cost
    if farm ~= nil and farm:getBalance() < total then
        local money = function(amount) return g_i18n:formatMoney(amount, 0, true, true) end
        return false, string.format(g_i18n:getText("eq_enter_noMoney"), money(total), money(event.fee), money(cost))
    end

    g_currentMission:addMoney(-event.fee, farmId, MoneyType.EQ_ENTRY_FEES or MoneyType.OTHER, true, true)
    if cost > 0 then
        g_currentMission:addMoney(-cost, farmId, MoneyType.EQ_TRANSPORT or MoneyType.OTHER, true, true)
    end
    EqCompetitionManager.farmEntries[farmId] = (EqCompetitionManager.farmEntries[farmId] or 0) + 1
    local name = animal.getName ~= nil and animal:getName() or record.id
    table.insert(event.entries, { horseId = record.id, farmId = farmId, name = name,
        transport = manual and EqCompetitionManager.TRANSPORT_MANUAL or EqCompetitionManager.TRANSPORT_AUTO,
        delivered = not manual })
    if not manual then EqCompetitionManager.refreshAway({ animal }) end

    local text
    if manual then
        text = string.format(g_i18n:getText("eq_enter_doneManual"), name, EqCompetitionManager.eventTitle(event), rating,
            g_i18n:getText(event.kind == EqCompetition.KIND_MONTH and "eq_ui_deadline_month" or "eq_ui_deadline_round"))
    else
        text = string.format(g_i18n:getText("eq_enter_done"), name, EqCompetitionManager.eventTitle(event), rating,
            g_i18n:formatMoney(cost, 0, true, true))
    end
    local warning = EqCompetitionManager.healthWarning(animal)
    if warning ~= nil then text = text .. " " .. warning end
    return true, text
end


--- @param animal table RLRM Animal
--- @return string|nil text the chance it is scratched on the day for poor health, nil when healthy
function EqCompetitionManager.healthWarning(animal)
    local unsound = EqRisk.unsoundChance(animal.health)
    if unsound <= 0 or unsound >= 1 then return nil end
    return string.format(g_i18n:getText("eq_enter_lowHealth"), math.floor(animal.health or 0),
        math.floor(unsound * 100 + 0.5), EqRisk.ENTRY_HEALTH_MIN)
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
    xmlFile:setFloat(key .. ".settings#trainingRate", EqCompetitionManager.settings.trainingRate)
    xmlFile:setInt(key .. ".settings#eventsMin", EqCompetitionManager.settings.eventsMin)
    xmlFile:setInt(key .. ".settings#eventsMax", EqCompetitionManager.settings.eventsMax)
    xmlFile:setInt(key .. "#nextEventId", EqCompetitionManager.nextEventId)
    if EqCompetitionManager.rivalSeed ~= nil then xmlFile:setInt(key .. "#rivalSeed", EqCompetitionManager.rivalSeed) end

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
        if event.venue ~= nil then xmlFile:setString(eventKey .. "#venue", event.venue) end
        if event.region ~= nil then xmlFile:setString(eventKey .. "#region", event.region) end
        xmlFile:setFloat(eventKey .. "#fee", event.fee)
        xmlFile:setFloat(eventKey .. "#prize", event.prize)
        for j, entry in ipairs(event.entries) do
            local entryKey = string.format("%s.entry(%d)", eventKey, j - 1)
            xmlFile:setString(entryKey .. "#horseId", entry.horseId)
            xmlFile:setInt(entryKey .. "#farmId", entry.farmId)
            xmlFile:setString(entryKey .. "#name", entry.name)
            xmlFile:setString(entryKey .. "#transport", entry.transport or EqCompetitionManager.TRANSPORT_AUTO)
            xmlFile:setBool(entryKey .. "#delivered", EqCompetitionManager.isDelivered(entry))
        end
    end

    for i, summary in ipairs(EqCompetitionManager.results) do
        local resultKey = string.format("%s.results.result(%d)", key, i - 1)
        xmlFile:setInt(resultKey .. "#eventId", summary.eventId)
        xmlFile:setString(resultKey .. "#discipline", summary.discipline)
        xmlFile:setString(resultKey .. "#tier", summary.tier)
        if summary.going ~= nil then xmlFile:setString(resultKey .. "#going", summary.going) end
        if summary.venue ~= nil then xmlFile:setString(resultKey .. "#venue", summary.venue) end
        if summary.region ~= nil then xmlFile:setString(resultKey .. "#region", summary.region) end
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
    settings.trainingRate = xmlFile:getFloat(key .. ".settings#trainingRate", settings.trainingRate)
    settings.eventsMin = xmlFile:getInt(key .. ".settings#eventsMin", settings.eventsMin)
    settings.eventsMax = xmlFile:getInt(key .. ".settings#eventsMax", settings.eventsMax)
    EqCompetitionManager.nextEventId = xmlFile:getInt(key .. "#nextEventId", 1)
    EqCompetitionManager.rivalSeed = xmlFile:getInt(key .. "#rivalSeed")

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
            venue = xmlFile:getString(eventKey .. "#venue"),
            region = xmlFile:getString(eventKey .. "#region"),
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
                transport = xmlFile:getString(entryKey .. "#transport", EqCompetitionManager.TRANSPORT_AUTO),
                delivered = xmlFile:getBool(entryKey .. "#delivered", true),
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
            venue = xmlFile:getString(resultKey .. "#venue"),
            region = xmlFile:getString(resultKey .. "#region"),
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

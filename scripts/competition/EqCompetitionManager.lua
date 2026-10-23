--[[
    EqCompetitionManager.lua
    Runs the event calendar on the server.

    Two kinds of events:
    - Round events (Training, Novice, Intermediate) open every round and resolve at the start of
      the next one. A round is a day or a month, by the "cadence" setting, so players on long
      months (7+ days) and on 1 day a month both get a sensible pace.
    - Monthly events (Advanced, Championship) open at the start of each month and resolve at the
      start of the next.

    Players enter with eqEnter (a screen comes later) and pay the fee at once. Results, prize
    money and the career record follow when the event resolves. Horses from every farm can be
    entered into the same event; each farm pays its own fee and gets its own prize.

    Server only for now: entering from a multiplayer client needs a network event (milestone 7).
]]

EqCompetitionManager = {}

local Log = EqLog

EqCompetitionManager.CADENCE_DAY = "day"
EqCompetitionManager.CADENCE_MONTH = "month"
EqCompetitionManager.RESULTS_KEPT = 40

-- A Training Event under the monthly cadence counts as this share of a month's work.
EqCompetitionManager.MONTHLY_BOOST_MONTHS = 0.25


function EqCompetitionManager.reset()
    EqCompetitionManager.config = nil
    EqCompetitionManager.events = {}
    EqCompetitionManager.results = {}
    EqCompetitionManager.nextEventId = 1
    EqCompetitionManager.settings = { cadence = EqCompetitionManager.CADENCE_DAY, racing = true }
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


--- @param event table
--- @return string title such as "Novice Show Jumping #12"
function EqCompetitionManager.eventTitle(event)
    return string.format("%s %s #%d", EqCompetitionManager.tierTitle(event.tier),
        EqCompetitionManager.disciplineTitle(event.discipline), event.id)
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


--- Resolve one closed event: score the field, pay prizes, update careers, tell the owners.
--- @param event table
--- @param horses table from indexHorses
function EqCompetitionManager.resolve(event, horses)
    local config = EqCompetitionManager.config
    local tier = config.tierByName[event.tier]
    local entrants, byKey = {}, {}

    for _, entry in ipairs(event.entries) do
        local horse = horses[entry.horseId]
        local record = EqRegistry.getById(entry.horseId)
        if horse == nil or record == nil then
            notify(entry.farmId, string.format(g_i18n:getText("eq_result_gone"), entry.name, EqCompetitionManager.eventTitle(event)))
        else
            table.insert(entrants, {
                key = entry.horseId,
                rating = EqCompetitionManager.ratingFor(record, event),
                condition = EqCompetition.condition(horse.animal.fitness, horse.animal.health),
            })
            byKey[entry.horseId] = { entry = entry, record = record, animal = horse.animal }
        end
    end

    if #entrants == 0 then return end

    local results = EqCompetition.run(event, config, entrants, EqRandom.new("result " .. event.id))
    local summary = { eventId = event.id, discipline = event.discipline, tier = event.tier, going = event.going,
        field = #results, day = g_currentMission.environment.currentMonotonicDay or 0, placings = {} }

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
                EqTraining.applyBoost(record, record:getCeilings(), config.disciplineByName[event.discipline].weights,
                    tier.trainingBoost, mine.animal.age or 0, timeAdjustment)
            end

            table.insert(summary.placings, { horseId = runner.key, name = entry.name, farmId = entry.farmId,
                place = runner.place, prize = runner.prize })

            notify(entry.farmId, string.format(g_i18n:getText("eq_result_placed"), entry.name, runner.place, #results,
                EqCompetitionManager.eventTitle(event), g_i18n:formatMoney(runner.prize, 0, true, true)))
        end
    end

    table.insert(EqCompetitionManager.results, 1, summary)
    while #EqCompetitionManager.results > EqCompetitionManager.RESULTS_KEPT do table.remove(EqCompetitionManager.results) end
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
        if record ~= nil and not record.retired
            and EqCompetition.canEnter(tier, animal.age or 0, EqCompetitionManager.ratingFor(record, event)) then
            count = count + 1
        end
    end
    return count
end


--- Enter a horse. One round entry and one monthly entry per horse at a time.
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
    if record.retired then return false, g_i18n:getText("eq_enter_retired") end

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

    local farm = g_farmManager:getFarmById(farmId)
    if farm ~= nil and farm:getBalance() < event.fee then return false, g_i18n:getText("eq_enter_noMoney") end

    g_currentMission:addMoney(-event.fee, farmId, MoneyType.EQ_ENTRY_FEES or MoneyType.OTHER, true, true)
    local name = animal.getName ~= nil and animal:getName() or record.id
    table.insert(event.entries, { horseId = record.id, farmId = farmId, name = name })

    return true, string.format(g_i18n:getText("eq_enter_done"), name, EqCompetitionManager.eventTitle(event), rating)
end


-- SAVE AND LOAD (inside rlEquestrian.xml)

--- @param xmlFile table
--- @param key string such as "rlEquestrian.competition"
function EqCompetitionManager.saveToXMLFile(xmlFile, key)
    xmlFile:setString(key .. ".settings#cadence", EqCompetitionManager.settings.cadence)
    xmlFile:setBool(key .. ".settings#racing", EqCompetitionManager.settings.racing)
    xmlFile:setInt(key .. "#nextEventId", EqCompetitionManager.nextEventId)

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
    EqCompetitionManager.nextEventId = xmlFile:getInt(key .. "#nextEventId", 1)

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

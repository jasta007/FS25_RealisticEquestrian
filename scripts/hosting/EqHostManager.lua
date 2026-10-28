--[[
    EqHostManager.lua
    Bookings for hosting your own event, on the server (James, 2026-10-28).

    - A farm books one event at a time, for a month at least one month ahead and at most
      BOOK_AHEAD months ahead, and at least the "Months between hosted events" setting after
      its last one. Booking checks the farm against the rating (EqHosting) and pays the setup fee.
    - Cancelling more than a month ahead refunds REFUND_SHARE of the fee; later, nothing.
    - When the booked month starts the event opens on the calendar as one more monthly event,
      held at the farm (EqCompetitionManager.openHosted): the farm's own horses enter it from the
      Events tab, with no fee or transport, and it is resolved at the end of the month with the
      other monthly events.
    - The event month: the farm is checked again when it opens and every day. Short of anything
      (the visitors' feed for the day included), it gets a warning; still short a day later, the
      event is cancelled, which costs reputation. Each day the visitors' feed is taken from the
      farm's silos, then its troughs.
    - At the end of the month popularity is worked out again (a Champion of yours entered draws
      a crowd), which sets the turnout and the field; the visitors' entry fees and the gate are
      paid, and the farm's reputation goes up.

    Months are counted as EqCompetitionManager.month counts them (months played), so a booking
    keeps its place whatever the calendar says.

    Part of Realistic Equestrian by Jasta007.
]]

EqHostManager = {}

-- How far ahead a month can be booked.
EqHostManager.BOOK_AHEAD = 12
-- Cancelling at least this many months before the event refunds REFUND_SHARE of the setup fee.
EqHostManager.REFUND_MONTHS = 2
EqHostManager.REFUND_SHARE = 0.5
-- An entered horse rated this high for the event (Champion and up) makes it a star event.
EqHostManager.STAR_RATING = 90

local Log = EqLog


--- @param farmId number
--- @param kind string EqMessages type
--- @param text string
--- @param level number|nil FSBaseMission notification type
local function tell(farmId, kind, text, level)
    if g_currentMission:getFarmId() == farmId then
        g_currentMission:addIngameNotification(level or FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
    EqMessages.post(farmId, kind, text)
end



function EqHostManager.reset()
    EqHostManager.bookings = {}     -- farmId -> { type, rating, month, setupFee, previousLast }
    EqHostManager.lastMonth = {}    -- farmId -> month of the farm's last hosted event (booked or held)
    EqHostManager.reputation = {}   -- farmId -> hosting reputation (EqHosting.nextReputation)
end

EqHostManager.reset()


--- @return number months between two events a farm hosts, from the settings
function EqHostManager.interval()
    local settings = EqCompetitionManager.settings
    return math.max(1, tonumber(settings ~= nil and settings.hostInterval or nil) or 6)
end


--- The months a farm could book. Pure: the current month, the farm's last hosted month and
--- the interval are passed in.
--- @param now number the month now (EqCompetitionManager.month)
--- @param last number|nil the month of the farm's last hosted event
--- @param interval number
--- @return table months list of month numbers, soonest first
function EqHostManager.choices(now, last, interval)
    local first = now + 1
    if last ~= nil then first = math.max(first, last + interval) end
    local months = {}
    for month = first, now + EqHostManager.BOOK_AHEAD do table.insert(months, month) end
    return months
end


--- @param booking table
--- @param now number the month now
--- @return number refund what cancelling now gives back
function EqHostManager.refundFor(booking, now)
    if booking.month - now >= EqHostManager.REFUND_MONTHS then
        return math.floor((booking.setupFee or 0) * EqHostManager.REFUND_SHARE + 0.5)
    end
    return 0
end


--- @param month number a month as EqCompetitionManager.month counts them
--- @return string text the calendar month's name, such as "July"
function EqHostManager.monthText(month)
    local now = EqCompetitionManager.month or 0
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    local period = environment ~= nil and environment.currentPeriod or nil
    if period ~= nil and g_i18n.formatPeriod ~= nil then
        local target = ((period - 1 + month - now) % 12) + 1
        local ok, text = EqLog.try("EqHostManager.monthText formatPeriod", g_i18n.formatPeriod, g_i18n, target, false)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return string.format(g_i18n:getText("eq_host_monthsAhead"), month - now)
end


--- @param farmId number
--- @return string name the farm's name, where its events are held
function EqHostManager.venueName(farmId)
    local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
    local name = farm ~= nil and farm.name or nil
    if name == nil or name == "" then name = g_i18n:getText("eq_host_yourFarm") end
    return name
end


--- @param farmId number
--- @return table|nil event the farm's event open on the calendar now
function EqHostManager.openEvent(farmId)
    for _, event in pairs(EqCompetitionManager.events) do
        if event.hosted ~= nil and event.hosted.farmId == farmId then return event end
    end
    return nil
end


--- Why a farm cannot book this now, or nil when it can.
--- @param farmId number
--- @param typeName string
--- @param ratingName string
--- @param month number
--- @param result table|nil from EqHosting.check, read from the farm when nil
--- @return string|nil reason an eq_host_book_* text key
function EqHostManager.bookProblem(farmId, typeName, ratingName, month, result)
    local config = EqHostVenue.config
    if config == nil or EqCompetitionManager.config == nil then return "eq_host_book_noConfig" end
    if EqHostManager.bookings[farmId] ~= nil or EqHostManager.openEvent(farmId) ~= nil then return "eq_host_book_already" end
    local allowed = false
    for _, choice in ipairs(EqHostManager.choices(EqCompetitionManager.month, EqHostManager.lastMonth[farmId], EqHostManager.interval())) do
        if choice == month then allowed = true end
    end
    if not allowed then return "eq_host_book_month" end
    result = result or EqHosting.check(config, typeName, ratingName, EqHostVenue.read(farmId))
    if not result.ok then return "eq_host_book_requirements" end
    local farm = g_farmManager:getFarmById(farmId)
    if farm ~= nil and farm:getBalance() < result.setupFee then return "eq_host_book_money" end
    return nil
end


--- Book an event: checks, the setup fee, and the booking kept until its month.
--- @param farmId number
--- @param typeName string
--- @param ratingName string
--- @param month number
--- @return boolean ok
--- @return string text for the player
function EqHostManager.book(farmId, typeName, ratingName, month)
    local config = EqHostVenue.config
    local result = config ~= nil and EqHosting.check(config, typeName, ratingName, EqHostVenue.read(farmId)) or nil
    local problem = EqHostManager.bookProblem(farmId, typeName, ratingName, month, result)
    if problem ~= nil then
        if problem == "eq_host_book_money" then
            return false, string.format(g_i18n:getText(problem), g_i18n:formatMoney(result.setupFee, 0, true, true))
        end
        return false, g_i18n:getText(problem)
    end

    g_currentMission:addMoney(-result.setupFee, farmId, MoneyType.EQ_HOSTING or MoneyType.OTHER, true, true)
    EqHostManager.bookings[farmId] = { type = typeName, rating = ratingName, month = month, setupFee = result.setupFee,
        previousLast = EqHostManager.lastMonth[farmId] }
    EqHostManager.lastMonth[farmId] = month
    Log:info("EqHostManager: farm %d booked %s %s for month %d (%d)", farmId, typeName, ratingName, month, result.setupFee)
    return true, string.format(g_i18n:getText("eq_host_book_done"), EqHostManager.title(typeName, ratingName),
        EqHostManager.monthText(month), g_i18n:formatMoney(result.setupFee, 0, true, true))
end


--- Cancel a farm's booking before its month starts.
--- @param farmId number
--- @return boolean ok
--- @return string text for the player
function EqHostManager.cancel(farmId)
    local booking = EqHostManager.bookings[farmId]
    if booking == nil then return false, g_i18n:getText("eq_host_cancel_none") end
    local refund = EqHostManager.refundFor(booking, EqCompetitionManager.month)
    if refund > 0 then g_currentMission:addMoney(refund, farmId, MoneyType.EQ_HOSTING or MoneyType.OTHER, true, true) end
    EqHostManager.bookings[farmId] = nil
    EqHostManager.lastMonth[farmId] = booking.previousLast
    Log:info("EqHostManager: farm %d cancelled its %s %s, refund %d", farmId, booking.type, booking.rating, refund)
    return true, string.format(g_i18n:getText("eq_host_cancel_done"), EqHostManager.title(booking.type, booking.rating),
        g_i18n:formatMoney(refund, 0, true, true))
end


--- @param typeName string
--- @param ratingName string
--- @return string title such as "Championship 3 Day Event"
function EqHostManager.title(typeName, ratingName)
    return string.format("%s %s", g_i18n:getText("eq_host_rating_" .. ratingName), g_i18n:getText("eq_host_type_" .. typeName))
end


--- A new month: open the events booked for it.
--- @param month number the month that has just started
function EqHostManager.onMonthStarted(month)
    local farmIds = {}
    for farmId, booking in pairs(EqHostManager.bookings) do
        if booking.month <= month then table.insert(farmIds, farmId) end
    end
    table.sort(farmIds)
    for _, farmId in ipairs(farmIds) do
        local booking = EqHostManager.bookings[farmId]
        EqHostManager.bookings[farmId] = nil
        local event = EqCompetitionManager.openHosted(farmId, booking.type, booking.rating, EqHostManager.venueName(farmId))
        if event ~= nil then
            tell(farmId, "EQ_HOST_OPENED", string.format(g_i18n:getText("eq_host_opened"), EqCompetitionManager.eventTitle(event)))
            if EqHostVenue.config ~= nil then EqHostManager.startMonth(event) end
        end
    end
end


-- THE EVENT MONTH

--- Feed the visitors eat in a day. Pure.
--- @param feedPerHorse number litres a horse eats in a month
--- @param horses number visiting horses
--- @param daysPerPeriod number
--- @return number litres
function EqHostManager.dailyFeed(feedPerHorse, horses, daysPerPeriod)
    return math.ceil((feedPerHorse or 0) * (horses or 0) / math.max(1, daysPerPeriod or 1))
end


--- The checks a running event fails. Pure.
--- @param result table from EqHosting.check
--- @param skipFeed boolean leave out the month's feed (it is checked a day at a time)
--- @return table ids of the failed checks
function EqHostManager.failedChecks(result, skipFeed)
    local failed = {}
    for _, check in ipairs(result.checks or {}) do
        if not check.ok and not (skipFeed and check.id == "feed") then table.insert(failed, check.id) end
    end
    return failed
end


--- @return number day
local function today()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    return environment ~= nil and environment.currentMonotonicDay or 0
end


--- @return boolean true in winter
local function isWinter()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    return environment ~= nil and Season ~= nil and environment.currentSeason == Season.WINTER
end


--- Popularity and turnout for a hosted event, from the farm as it is now.
--- @param event table
--- @param star boolean|nil
--- @return table result from EqHosting.check
--- @return number popularity
--- @return table takings from EqHosting.takings
local function assess(event, star)
    local config = EqHostVenue.config
    local hosted = event.hosted
    local venue = EqHostVenue.read(hosted.farmId)
    local result = EqHosting.check(config, event.discipline, hosted.rating, venue)
    local context = { facilityKinds = venue.facilityKinds, reputation = EqHostManager.reputation[hosted.farmId] or 0,
        star = star, winter = isWinter() }
    local score = EqHosting.popularity(config, event.discipline, result, context)
    local takings = EqHosting.takings(config, event.discipline, config.ratingByName[hosted.rating], score, result.seatingTotal)
    return result, score, takings, venue
end


--- @param ids table failed check ids
--- @return string their names, such as "Horse feed, Free stable places"
local function checkNames(ids)
    local names = {}
    for _, id in ipairs(ids) do table.insert(names, g_i18n:getText("eq_host_check_" .. id)) end
    return table.concat(names, ", ")
end


--- A hosted event has just opened: settle its expected turnout and check the farm.
--- @param event table
function EqHostManager.startMonth(event)
    local hosted = event.hosted
    local result, score, takings, venue = assess(event, false)
    hosted.openedDay = today()
    hosted.popularity = score
    hosted.competitors = takings.competitors
    hosted.feedPerHorse = venue.feedPerHorse
    event.field = takings.competitors + EqHostVenue.config.ownPlaces
    local failed = EqHostManager.failedChecks(result, false)
    if #failed > 0 then
        hosted.warned = true
        tell(hosted.farmId, "EQ_HOST_WARNING", string.format(g_i18n:getText("eq_host_warning"),
            EqCompetitionManager.eventTitle(event), checkNames(failed)), FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
    end
end


--- Cancel a running hosted event: it leaves the calendar and the farm's reputation drops.
--- @param event table
--- @param failed table check ids it failed
function EqHostManager.cancelRunning(event, failed)
    local hosted = event.hosted
    EqCompetitionManager.events[event.id] = nil
    local config = EqHostVenue.config
    EqHostManager.reputation[hosted.farmId] = EqHosting.nextReputation(config, EqHostManager.reputation[hosted.farmId] or 0, false)
    Log:info("EqHostManager: farm %d's event %d cancelled (%s)", hosted.farmId, event.id, table.concat(failed, " "))
    tell(hosted.farmId, "EQ_HOST_CANCELLED", string.format(g_i18n:getText("eq_host_cancelled"),
        EqCompetitionManager.eventTitle(event), checkNames(failed)), FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
end


--- A new day: feed the visitors and check every running hosted event.
function EqHostManager.onDayChanged()
    if EqHostVenue.config == nil then return end
    local events = {}
    for _, event in pairs(EqCompetitionManager.events) do
        if event.hosted ~= nil and event.hosted.openedDay ~= today() then table.insert(events, event) end
    end
    table.sort(events, function(a, b) return a.id < b.id end)
    local environment = g_currentMission.environment
    for _, event in ipairs(events) do
        local hosted = event.hosted
        local result = EqHosting.check(EqHostVenue.config, event.discipline, hosted.rating, EqHostVenue.read(hosted.farmId))
        local failed = EqHostManager.failedChecks(result, true)
        local need = EqHostManager.dailyFeed(hosted.feedPerHorse, hosted.competitors, environment.daysPerPeriod)
        local taken = need > 0 and EqHostVenue.takeFeed(hosted.farmId, need) or 0
        if taken < need - 0.5 then table.insert(failed, "feed") end
        if #failed == 0 then
            hosted.warned = nil
        elseif hosted.warned then
            EqHostManager.cancelRunning(event, failed)
        else
            hosted.warned = true
            tell(hosted.farmId, "EQ_HOST_WARNING", string.format(g_i18n:getText("eq_host_warning"),
                EqCompetitionManager.eventTitle(event), checkNames(failed)), FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
        end
    end
end


--- @param event table
--- @return boolean star one of the farm's entries is rated Champion or better for it
local function hasStar(event)
    for _, entry in ipairs(event.entries) do
        local record = EqRegistry.getById(entry.horseId)
        if record ~= nil and EqCompetitionManager.ratingFor(record, event) >= EqHostManager.STAR_RATING then return true end
    end
    return false
end


--- The month is over: the final popularity sets the turnout, which sets the field.
--- @param event table
function EqHostManager.beforeResolve(event)
    if EqHostVenue.config == nil then return end
    local _, score, takings = assess(event, hasStar(event))
    event.hosted.popularity = score
    event.hosted.takings = takings
    event.field = takings.competitors + EqHostVenue.config.ownPlaces
end


--- Pay the takings and raise the farm's reputation.
--- @param event table
function EqHostManager.afterResolve(event)
    local hosted = event.hosted
    local takings = hosted.takings
    if takings == nil then return end
    if takings.total > 0 then
        g_currentMission:addMoney(takings.total, hosted.farmId, MoneyType.EQ_HOSTING or MoneyType.OTHER, true, true)
    end
    EqHostManager.reputation[hosted.farmId] = EqHosting.nextReputation(EqHostVenue.config,
        EqHostManager.reputation[hosted.farmId] or 0, true)
    local money = function(amount) return g_i18n:formatMoney(amount, 0, true, true) end
    tell(hosted.farmId, "EQ_HOST_DONE", string.format(g_i18n:getText("eq_host_done"), EqCompetitionManager.eventTitle(event),
        takings.competitors, money(takings.total), money(takings.entries), money(takings.gate), hosted.popularity))
end


--- @param xmlFile table
--- @param key string the event's hosted key
--- @param hosted table
function EqHostManager.saveEventState(xmlFile, key, hosted)
    if hosted.openedDay ~= nil then xmlFile:setInt(key .. "#openedDay", hosted.openedDay) end
    if hosted.popularity ~= nil then xmlFile:setInt(key .. "#popularity", hosted.popularity) end
    if hosted.competitors ~= nil then xmlFile:setInt(key .. "#competitors", hosted.competitors) end
    if hosted.feedPerHorse ~= nil then xmlFile:setFloat(key .. "#feedPerHorse", hosted.feedPerHorse) end
    if hosted.warned then xmlFile:setBool(key .. "#warned", true) end
end


--- @param xmlFile table
--- @param key string
--- @param hosted table filled in
function EqHostManager.loadEventState(xmlFile, key, hosted)
    hosted.openedDay = xmlFile:getInt(key .. "#openedDay")
    hosted.popularity = xmlFile:getInt(key .. "#popularity")
    hosted.competitors = xmlFile:getInt(key .. "#competitors")
    hosted.feedPerHorse = xmlFile:getFloat(key .. "#feedPerHorse")
    hosted.warned = xmlFile:getBool(key .. "#warned", false) or nil
end


-- SAVE AND LOAD (inside rlEquestrian.xml)

--- @param xmlFile table
--- @param key string such as "rlEquestrian.hosting"
function EqHostManager.saveToXMLFile(xmlFile, key)
    local farmIds, seen = {}, {}
    for _, list in ipairs({ EqHostManager.bookings, EqHostManager.lastMonth, EqHostManager.reputation }) do
        for farmId in pairs(list) do
            if not seen[farmId] then
                seen[farmId] = true
                table.insert(farmIds, farmId)
            end
        end
    end
    table.sort(farmIds)
    for i, farmId in ipairs(farmIds) do
        local farmKey = string.format("%s.farm(%d)", key, i - 1)
        xmlFile:setInt(farmKey .. "#farmId", farmId)
        if EqHostManager.lastMonth[farmId] ~= nil then xmlFile:setInt(farmKey .. "#lastMonth", EqHostManager.lastMonth[farmId]) end
        if EqHostManager.reputation[farmId] ~= nil then xmlFile:setFloat(farmKey .. "#reputation", EqHostManager.reputation[farmId]) end
        local booking = EqHostManager.bookings[farmId]
        if booking ~= nil then
            xmlFile:setString(farmKey .. ".booking#type", booking.type)
            xmlFile:setString(farmKey .. ".booking#rating", booking.rating)
            xmlFile:setInt(farmKey .. ".booking#month", booking.month)
            xmlFile:setFloat(farmKey .. ".booking#setupFee", booking.setupFee or 0)
            if booking.previousLast ~= nil then xmlFile:setInt(farmKey .. ".booking#previousLast", booking.previousLast) end
        end
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqHostManager.loadFromXMLFile(xmlFile, key)
    EqHostManager.reset()
    if xmlFile == nil then return end
    local i = 0
    while true do
        local farmKey = string.format("%s.farm(%d)", key, i)
        if not xmlFile:hasProperty(farmKey) then break end
        local farmId = xmlFile:getInt(farmKey .. "#farmId")
        if farmId ~= nil then
            EqHostManager.lastMonth[farmId] = xmlFile:getInt(farmKey .. "#lastMonth")
            EqHostManager.reputation[farmId] = xmlFile:getFloat(farmKey .. "#reputation")
            if xmlFile:hasProperty(farmKey .. ".booking") then
                local booking = {
                    type = xmlFile:getString(farmKey .. ".booking#type", ""),
                    rating = xmlFile:getString(farmKey .. ".booking#rating", ""),
                    month = xmlFile:getInt(farmKey .. ".booking#month", 0),
                    setupFee = xmlFile:getFloat(farmKey .. ".booking#setupFee", 0),
                    previousLast = xmlFile:getInt(farmKey .. ".booking#previousLast"),
                }
                if EqHosting.isType(booking.type) then EqHostManager.bookings[farmId] = booking end
            end
        end
        i = i + 1
    end
end

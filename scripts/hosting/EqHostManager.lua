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
    - Ridden rounds: while the event runs, a round ridden on one of your horses entered in it,
      on a course that qualifies, or the dressage test in an arena that does (the test then has
      the rating's length), is that horse's phase, scored by EqHosting. Once per horse and phase.

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
-- Reports of a farm's past hosted events kept for the Results tab.
EqHostManager.HISTORY_KEPT = 12
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
    EqHostManager.history = {}      -- farmId -> list of EqHostManager.report, newest first
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
--- @return boolean named true when it is a month's name, false for the "in N months" fallback
function EqHostManager.monthText(month)
    local now = EqCompetitionManager.month or 0
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    local period = environment ~= nil and environment.currentPeriod or nil
    -- The game's own I18N, not our proxy: through the proxy formatPeriod overflowed the stack
    -- with another mod's getText hook (FS25_BankCredit, James's log 2026-10-29).
    local i18n = EqI18N.globalI18N()
    if period ~= nil and i18n ~= nil and i18n.formatPeriod ~= nil then
        local target = ((period - 1 + month - now) % 12) + 1
        local ok, text = EqLog.try("EqHostManager.monthText formatPeriod", i18n.formatPeriod, i18n, target, false)
        if ok and type(text) == "string" and text ~= "" then return text, true end
    end
    if month == now then return g_i18n:getText("eq_host_monthNow"), false end
    return string.format(g_i18n:getText("eq_host_monthsAhead"), month - now), false
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
    -- A running event doesn't block the next booking: the wait between events does (eqHostWait clears it).
    if EqHostManager.bookings[farmId] ~= nil then return "eq_host_book_already" end
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


--- Testing (eqHostWait): forget the farm's last hosted month, so the wait between events is over.
--- A booking still waiting for its month stays booked.
--- @param farmId number
--- @return boolean true when there was a wait to clear
function EqHostManager.clearWait(farmId)
    local booking = EqHostManager.bookings[farmId]
    local had = EqHostManager.lastMonth[farmId] ~= nil
    EqHostManager.lastMonth[farmId] = nil
    if booking ~= nil then booking.previousLast = nil end
    return had
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
            event.hosted.setupFee = booking.setupFee
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
        -- The visiting horses really eat it (James, 2026-10-29): counted for the Results tab.
        hosted.feedEaten = (hosted.feedEaten or 0) + taken
        hosted.feedDaily = need
        Log:info("EqHostManager: event %s visitors ate %.0f of %.0f l feed (%.0f l so far)", tostring(event.id), taken, need, hosted.feedEaten)
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
    event.field = takings.competitors + math.min(#event.entries, EqHostVenue.config.ownPlaces)
end


--- What a finished hosted event came to, kept for the Results tab. Pure.
--- @param event table the resolved event (hosted.report from EqCompetitionManager.resolve)
--- @param day number
--- @return table report
function EqHostManager.report(event, day)
    local hosted = event.hosted
    local takings = hosted.takings or {}
    local result = hosted.report or {}
    local mine = {}
    for _, placing in ipairs(result.placings or {}) do
        table.insert(mine, { name = placing.name, place = placing.place or 0, status = placing.status })
    end
    return { day = day, discipline = event.discipline, rating = hosted.rating, venue = event.venue,
        field = result.field or 0, competitors = takings.competitors or 0, visitors = takings.visitors or 0,
        popularity = hosted.popularity or 0, entries = takings.entries or 0, gate = takings.gate or 0,
        total = takings.total or 0, setupFee = hosted.setupFee or 0, feed = hosted.feedEaten or 0, podium = result.podium or {}, mine = mine }
end


--- Keep a report on the farm's history, newest first.
--- @param farmId number
--- @param report table
function EqHostManager.keepReport(farmId, report)
    local list = EqHostManager.history[farmId] or {}
    table.insert(list, 1, report)
    while #list > EqHostManager.HISTORY_KEPT do table.remove(list) end
    EqHostManager.history[farmId] = list
end


--- Pay the takings and raise the farm's reputation.
--- @param event table
function EqHostManager.afterResolve(event)
    local hosted = event.hosted
    local takings = hosted.takings
    if takings == nil then return end
    local environment = g_currentMission.environment
    EqHostManager.keepReport(hosted.farmId, EqHostManager.report(event, environment ~= nil and environment.currentMonotonicDay or 0))
    if takings.total > 0 then
        g_currentMission:addMoney(takings.total, hosted.farmId, MoneyType.EQ_HOSTING or MoneyType.OTHER, true, true)
    end
    EqHostManager.reputation[hosted.farmId] = EqHosting.nextReputation(EqHostVenue.config,
        EqHostManager.reputation[hosted.farmId] or 0, true)
    local money = function(amount) return g_i18n:formatMoney(amount, 0, true, true) end
    tell(hosted.farmId, "EQ_HOST_DONE", string.format(g_i18n:getText("eq_host_done"), EqCompetitionManager.eventTitle(event),
        takings.competitors, money(takings.total), money(takings.entries), money(takings.gate), hosted.popularity))
end


-- RIDDEN ROUNDS

--- @param horseId string|nil
--- @return table|nil event the running hosted event the horse is entered in
function EqHostManager.liveEventFor(horseId)
    if horseId == nil then return nil end
    for _, event in pairs(EqCompetitionManager.events) do
        if event.hosted ~= nil then
            for _, entry in ipairs(event.entries) do
                if entry.horseId == horseId then return event end
            end
        end
    end
    return nil
end


--- @param event table
--- @param phase string
--- @return boolean the event has this phase
local function hasPhase(event, phase)
    for _, name in ipairs(EqHosting.phasesOf(event.discipline)) do
        if name == phase then return true end
    end
    return false
end


--- @param vehicle table a ridden horse
--- @return string|nil horseId
function EqHostManager.horseIdOf(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    local cluster = spec ~= nil and spec.cluster or nil
    if cluster == nil or cluster.isHorse == nil or not cluster:isHorse() then return nil end
    return EqRegistry.getId(cluster)
end


--- @param event table
--- @return table|nil rating from data/hosting.xml
local function ratingOf(event)
    local config = EqHostVenue.config
    return config ~= nil and config.ratingByName[event.hosted.rating] or nil
end


--- Keep a ridden phase, once, and tell the rider.
--- @param event table
--- @param horseId string
--- @param phase string
--- @param sheet table
--- @return boolean kept
local function keepRidden(event, horseId, phase, sheet)
    local hosted = event.hosted
    hosted.ridden = hosted.ridden or {}
    local mine = hosted.ridden[horseId] or {}
    local title, phaseName = EqCompetitionManager.eventTitle(event), g_i18n:getText("eq_discipline_" .. phase)
    if mine[phase] ~= nil then
        tell(hosted.farmId, "EQ_HOST_RIDDEN", string.format(g_i18n:getText("eq_host_ride_already"), phaseName, title))
        return false
    end
    mine[phase] = sheet
    hosted.ridden[horseId] = mine
    local text = sheet.eliminated and string.format(g_i18n:getText("eq_host_ride_out"), phaseName, title)
        or string.format(g_i18n:getText("eq_host_ride_counted"), phaseName, title, EqStory.penalties(sheet.penalties, phase == "dressage"))
    Log:info("EqHostManager: %s rode %s for event %d: %s", horseId, phase, event.id,
        sheet.eliminated and "eliminated" or tostring(sheet.penalties))
    tell(hosted.farmId, "EQ_HOST_RIDDEN", text)
    if EqTrainingHud ~= nil and EqTrainingHud.announce ~= nil then
        local days = EqHostManager.daysLeft()
        local headline = sheet.eliminated and g_i18n:getText("eq_host_ann_out")
            or string.format(g_i18n:getText("eq_host_ann_counted"), EqStory.penalties(sheet.penalties, phase == "dressage"))
        local sub = days ~= nil and days > 0 and string.format(g_i18n:getText("eq_host_ann_resultsIn"), title, days)
            or string.format(g_i18n:getText("eq_host_ann_resultsSoon"), title)
        EqTrainingHud.announce(headline, sub)
    end
    return true
end


--- Would a round on this course count in the horse's own event? For the start line's fanfare.
--- @param vehicle table the ridden horse
--- @param course table EqCourse course
--- @return table|nil event the running hosted event the horse is entered in, with this phase
--- @return string|nil status "counts", "ridden" (this phase is done) or "small" (the course is too small)
function EqHostManager.competitionFor(vehicle, course)
    local horseId = EqHostManager.horseIdOf(vehicle)
    local event = EqHostManager.liveEventFor(horseId)
    if event == nil or course == nil then return nil end
    local phase = course.kind or EqCourse.SHOW_JUMPING
    local rating = ratingOf(event)
    if rating == nil or not hasPhase(event, phase) then return nil end
    local ridden = event.hosted.ridden ~= nil and event.hosted.ridden[horseId] or nil
    if ridden ~= nil and ridden[phase] ~= nil then return event, "ridden" end
    local shape = { kind = phase, jumps = #course.jumps, length = course.length or EqCourse.pathLength(course.points) }
    if not EqHosting.courseQualifies(rating, phase, shape) then return event, "small" end
    return event, "counts"
end


--- How many days are left in the month, for "results in N days".
--- @return number|nil days
function EqHostManager.daysLeft()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment == nil or environment.daysPerPeriod == nil or environment.currentDayInPeriod == nil then return nil end
    return math.max(0, environment.daysPerPeriod - environment.currentDayInPeriod)
end


--- A show jumping or cross country round has ended (EqCourseHooks).
--- @param vehicle table
--- @param course table EqCourse course
--- @param sj table the EqShowJumping round, its result set
function EqHostManager.onRoundDone(vehicle, course, sj)
    local horseId = EqHostManager.horseIdOf(vehicle)
    local event = EqHostManager.liveEventFor(horseId)
    if event == nil or sj.result == nil then return end
    local phase = course.kind or EqCourse.SHOW_JUMPING
    local rating = ratingOf(event)
    if rating == nil or not hasPhase(event, phase) then return end
    local shape = { kind = phase, jumps = #course.jumps, length = course.length or EqCourse.pathLength(course.points) }
    if not EqHosting.courseQualifies(rating, phase, shape) then
        tell(event.hosted.farmId, "EQ_HOST_RIDDEN", string.format(g_i18n:getText("eq_host_ride_small"),
            EqCompetitionManager.eventTitle(event)))
        return
    end
    keepRidden(event, horseId, phase, EqHosting.roundSheet(sj.result, sj.refusals, sj.allowed))
end


--- The dressage test for an arena in the month of your own event: the event's fixed test,
--- the same for every horse and every ride (training is random in other months, James
--- 2026-10-29). It counts for a horse entered in the event that has not ridden its dressage yet,
--- in an arena big enough for the event's rating. nil when no event of yours with a dressage
--- phase is on.
--- @param horseId string|nil the ridden horse
--- @param markers table the dressage course's markers
--- @return table|nil test { seed, moves, counts }
function EqHostManager.dressageTestFor(horseId, markers)
    local mine = EqHostManager.liveEventFor(horseId)
    local event = mine ~= nil and hasPhase(mine, "dressage") and mine or nil
    if event == nil then
        for _, other in pairs(EqCompetitionManager.events) do
            if other.hosted ~= nil and hasPhase(other, "dressage") and (event == nil or other.id < event.id) then event = other end
        end
    end
    if event == nil then return nil end
    local rating = ratingOf(event)
    if rating == nil then return nil end
    local counts = false
    if event == mine then
        local ridden = event.hosted.ridden ~= nil and event.hosted.ridden[horseId] or nil
        if ridden == nil or ridden.dressage == nil then
            for _, arena in ipairs(EqHosting.arenasFromMarkers(markers or {})) do
                if arena.length >= rating.dressageArena then counts = true end
            end
        end
    end
    return { seed = string.format("dressage %s %s", tostring(event.id), tostring(event.hosted.rating)), moves = rating.dressageMoves, counts = counts }
end


--- A competition dressage test has ended (EqTrainingHooks).
--- @param vehicle table
--- @param percent number|nil the test's score
--- @param lost boolean eliminated (three errors of course)
function EqHostManager.onTestDone(vehicle, percent, lost)
    local horseId = EqHostManager.horseIdOf(vehicle)
    local event = EqHostManager.liveEventFor(horseId)
    if event == nil or not hasPhase(event, "dressage") then return end
    keepRidden(event, horseId, "dressage", EqHosting.testSheet(percent, lost))
end


--- @param xmlFile table
--- @param key string the event's hosted key
--- @param hosted table
function EqHostManager.saveEventState(xmlFile, key, hosted)
    if hosted.openedDay ~= nil then xmlFile:setInt(key .. "#openedDay", hosted.openedDay) end
    if hosted.popularity ~= nil then xmlFile:setInt(key .. "#popularity", hosted.popularity) end
    if hosted.setupFee ~= nil then xmlFile:setFloat(key .. "#setupFee", hosted.setupFee) end
    if hosted.competitors ~= nil then xmlFile:setInt(key .. "#competitors", hosted.competitors) end
    if hosted.feedPerHorse ~= nil then xmlFile:setFloat(key .. "#feedPerHorse", hosted.feedPerHorse) end
    if hosted.feedEaten ~= nil then xmlFile:setFloat(key .. "#feedEaten", hosted.feedEaten) end
    if hosted.feedDaily ~= nil then xmlFile:setFloat(key .. "#feedDaily", hosted.feedDaily) end
    if hosted.warned then xmlFile:setBool(key .. "#warned", true) end
    local horseIds = {}
    for horseId in pairs(hosted.ridden or {}) do table.insert(horseIds, horseId) end
    table.sort(horseIds)
    local i = 0
    for _, horseId in ipairs(horseIds) do
        for phase, sheet in pairs(hosted.ridden[horseId]) do
            local rideKey = string.format("%s.ridden(%d)", key, i)
            xmlFile:setString(rideKey .. "#horseId", horseId)
            xmlFile:setString(rideKey .. "#phase", phase)
            xmlFile:setFloat(rideKey .. "#penalties", sheet.penalties or 0)
            xmlFile:setInt(rideKey .. "#down", sheet.down or 0)
            xmlFile:setInt(rideKey .. "#refusals", sheet.refusals or 0)
            xmlFile:setFloat(rideKey .. "#time", sheet.time or 0)
            if sheet.eliminated then xmlFile:setBool(rideKey .. "#eliminated", true) end
            if sheet.grade ~= nil then xmlFile:setFloat(rideKey .. "#grade", sheet.grade) end
            i = i + 1
        end
    end
end


--- @param xmlFile table
--- @param key string
--- @param hosted table filled in
function EqHostManager.loadEventState(xmlFile, key, hosted)
    hosted.openedDay = xmlFile:getInt(key .. "#openedDay")
    hosted.popularity = xmlFile:getInt(key .. "#popularity")
    hosted.setupFee = xmlFile:getFloat(key .. "#setupFee")
    hosted.competitors = xmlFile:getInt(key .. "#competitors")
    hosted.feedPerHorse = xmlFile:getFloat(key .. "#feedPerHorse")
    hosted.feedEaten = xmlFile:getFloat(key .. "#feedEaten")
    hosted.feedDaily = xmlFile:getFloat(key .. "#feedDaily")
    hosted.warned = xmlFile:getBool(key .. "#warned", false) or nil
    local i = 0
    while true do
        local rideKey = string.format("%s.ridden(%d)", key, i)
        if not xmlFile:hasProperty(rideKey) then break end
        local horseId, phase = xmlFile:getString(rideKey .. "#horseId"), xmlFile:getString(rideKey .. "#phase")
        if horseId ~= nil and phase ~= nil then
            hosted.ridden = hosted.ridden or {}
            hosted.ridden[horseId] = hosted.ridden[horseId] or {}
            hosted.ridden[horseId][phase] = { penalties = xmlFile:getFloat(rideKey .. "#penalties", 0),
                down = xmlFile:getInt(rideKey .. "#down", 0), refusals = xmlFile:getInt(rideKey .. "#refusals", 0),
                time = xmlFile:getFloat(rideKey .. "#time", 0), eliminated = xmlFile:getBool(rideKey .. "#eliminated", false) or nil,
                grade = xmlFile:getFloat(rideKey .. "#grade") }
        end
        i = i + 1
    end
end


-- SAVE AND LOAD (inside rlEquestrian.xml)

--- @param xmlFile table
--- @param key string such as "rlEquestrian.hosting"
function EqHostManager.saveToXMLFile(xmlFile, key)
    local farmIds, seen = {}, {}
    for _, list in ipairs({ EqHostManager.bookings, EqHostManager.lastMonth, EqHostManager.reputation, EqHostManager.history }) do
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
        for r, report in ipairs(EqHostManager.history[farmId] or {}) do
            EqHostManager.saveReport(xmlFile, string.format("%s.report(%d)", farmKey, r - 1), report)
        end
    end
end


local REPORT_INTS = { "day", "field", "competitors", "visitors", "popularity" }
local REPORT_FLOATS = { "entries", "gate", "total", "setupFee", "feed" }
local REPORT_STRINGS = { "discipline", "rating", "venue" }


--- @param xmlFile table
--- @param key string
--- @param report table
function EqHostManager.saveReport(xmlFile, key, report)
    for _, name in ipairs(REPORT_INTS) do xmlFile:setInt(key .. "#" .. name, report[name] or 0) end
    for _, name in ipairs(REPORT_FLOATS) do xmlFile:setFloat(key .. "#" .. name, report[name] or 0) end
    for _, name in ipairs(REPORT_STRINGS) do xmlFile:setString(key .. "#" .. name, report[name] or "") end
    for i, name in ipairs(report.podium or {}) do xmlFile:setString(string.format("%s.podium(%d)#name", key, i - 1), name) end
    for i, horse in ipairs(report.mine or {}) do
        local horseKey = string.format("%s.horse(%d)", key, i - 1)
        xmlFile:setString(horseKey .. "#name", horse.name or "")
        xmlFile:setInt(horseKey .. "#place", horse.place or 0)
        if horse.status ~= nil then xmlFile:setString(horseKey .. "#status", horse.status) end
    end
end


--- @param xmlFile table
--- @param key string
--- @return table report
function EqHostManager.loadReport(xmlFile, key)
    local report = { podium = {}, mine = {} }
    for _, name in ipairs(REPORT_INTS) do report[name] = xmlFile:getInt(key .. "#" .. name, 0) end
    for _, name in ipairs(REPORT_FLOATS) do report[name] = xmlFile:getFloat(key .. "#" .. name, 0) end
    for _, name in ipairs(REPORT_STRINGS) do report[name] = xmlFile:getString(key .. "#" .. name, "") end
    local i = 0
    while xmlFile:hasProperty(string.format("%s.podium(%d)", key, i)) do
        table.insert(report.podium, xmlFile:getString(string.format("%s.podium(%d)#name", key, i), "?"))
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("%s.horse(%d)", key, i)) do
        local horseKey = string.format("%s.horse(%d)", key, i)
        table.insert(report.mine, { name = xmlFile:getString(horseKey .. "#name", ""), place = xmlFile:getInt(horseKey .. "#place", 0),
            status = xmlFile:getString(horseKey .. "#status") })
        i = i + 1
    end
    return report
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
            local r = 0
            while xmlFile:hasProperty(string.format("%s.report(%d)", farmKey, r)) do
                local report = EqHostManager.loadReport(xmlFile, string.format("%s.report(%d)", farmKey, r))
                EqHostManager.history[farmId] = EqHostManager.history[farmId] or {}
                table.insert(EqHostManager.history[farmId], report)
                r = r + 1
            end
        end
        i = i + 1
    end
end

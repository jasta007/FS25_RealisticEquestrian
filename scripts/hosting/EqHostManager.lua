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
    - Each hour while it runs the weather is counted (EqHosting.countWeather): rain, snow, hail
      and tornadoes keep people away, unless the course or arena is indoors.
    - At the end of the month popularity is worked out again (a good horse of yours entered draws
      a crowd), which sets the turnout and the field; visitors buy souvenirs and refreshments
      from the farm's stock if the booking said so; the entry fees, the gate and the sales are
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
-- Sell souvenirs and refreshments unless the booking says not to (James, 2026-11-01: a toggle).
EqHostManager.SELL_DEFAULT = true

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
--- @param extra number|nil paid on top of the setup fee (advertising)
--- @return string|nil reason an eq_host_book_* text key
function EqHostManager.bookProblem(farmId, typeName, ratingName, month, result, extra)
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
    if farm ~= nil and farm:getBalance() < result.setupFee + (extra or 0) then return "eq_host_book_money" end
    return nil
end


--- Book an event: checks, the setup fee, and the booking kept until its month.
--- @param farmId number
--- @param typeName string
--- @param ratingName string
--- @param month number
--- @param options table|nil { advert (level name or nil), sell (souvenirs and refreshments) }
--- @return boolean ok
--- @return string text for the player
function EqHostManager.book(farmId, typeName, ratingName, month, options)
    options = options or {}
    local config = EqHostVenue.config
    local result = config ~= nil and EqHosting.check(config, typeName, ratingName, EqHostVenue.read(farmId)) or nil
    local advert = config ~= nil and EqHosting.advert(config, options.advert) or nil
    local advertCost = advert ~= nil and EqHosting.advertCost(config, advert.name, ratingName) or 0
    local problem = EqHostManager.bookProblem(farmId, typeName, ratingName, month, result, advertCost)
    if problem ~= nil then
        if problem == "eq_host_book_money" then
            return false, string.format(g_i18n:getText(problem), g_i18n:formatMoney(result.setupFee + advertCost, 0, true, true))
        end
        return false, g_i18n:getText(problem)
    end

    g_currentMission:addMoney(-(result.setupFee + advertCost), farmId, MoneyType.EQ_HOSTING or MoneyType.OTHER, true, true)
    local sell = options.sell
    if sell == nil then sell = EqHostManager.SELL_DEFAULT end
    EqHostManager.bookings[farmId] = { type = typeName, rating = ratingName, month = month, setupFee = result.setupFee,
        previousLast = EqHostManager.lastMonth[farmId], monthsAhead = month - EqCompetitionManager.month,
        advert = advert ~= nil and advert.name or nil, advertCost = advertCost, sell = sell and true or false,
        buzz = EqHosting.rollBuzz(config) }
    EqHostManager.lastMonth[farmId] = month
    Log:info("EqHostManager: farm %d booked %s %s for month %d (%d, advert %s %d, buzz %d)", farmId, typeName, ratingName, month,
        result.setupFee, tostring(EqHostManager.bookings[farmId].advert), advertCost, EqHostManager.bookings[farmId].buzz)
    local text = string.format(g_i18n:getText("eq_host_book_done"), EqHostManager.title(typeName, ratingName),
        EqHostManager.monthText(month), g_i18n:formatMoney(result.setupFee, 0, true, true))
    if advertCost > 0 then
        text = text .. " " .. string.format(g_i18n:getText("eq_host_book_advert"), g_i18n:formatMoney(advertCost, 0, true, true))
    end
    return true, text
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
            -- A sponsor that backs the rating names the event and draws a crowd (EqSponsorManager).
            if EqSponsorManager ~= nil then EqSponsorManager.onEventOpened(event) end
            EqHostManager.copyBooking(booking, event.hosted)
            tell(farmId, "EQ_HOST_OPENED", string.format(g_i18n:getText("eq_host_opened"), EqCompetitionManager.eventTitle(event)))
            if EqHostVenue.config ~= nil then EqHostManager.startMonth(event) end
        end
    end
end


--- What a booking chose that the event keeps. Pure.
--- @param booking table
--- @param hosted table changed
function EqHostManager.copyBooking(booking, hosted)
    hosted.monthsAhead = booking.monthsAhead
    hosted.advert = booking.advert
    hosted.advertCost = booking.advertCost
    hosted.sell = booking.sell
    hosted.buzz = booking.buzz
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


-- Once an event runs, its courses, arena and bleachers no longer decide whether it goes ahead
-- (James, 2026-11-01): a course made too short just means your rides there are practice, and the
-- event runs in the background without them. Only the visitors' stables and feed can stop it.
EqHostManager.VENUE_CHECKS = { arena = true, dressageSeating = true, showJumps = true, showJumpingSeating = true,
    xcLength = true, xcJumps = true }

--- The checks a running event fails. Pure.
--- @param result table from EqHosting.check
--- @param skipFeed boolean leave out the month's feed (it is checked a day at a time)
--- @return table ids of the failed checks: stables and feed, never the courses (VENUE_CHECKS)
function EqHostManager.failedChecks(result, skipFeed)
    local failed = {}
    for _, check in ipairs(result.checks or {}) do
        if not check.ok and not (skipFeed and check.id == "feed") and not EqHostManager.VENUE_CHECKS[check.id] then
            table.insert(failed, check.id)
        end
    end
    return failed
end


--- @return number day
local function today()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    return environment ~= nil and environment.currentMonotonicDay or 0
end


--- The popularity context of a running event. Pure apart from the reputation.
--- @param hosted table
--- @param venue table from EqHostVenue.read
--- @param starRating number|nil your best entry's rating for the event
--- @return table context for EqHosting.popularity
function EqHostManager.contextFor(hosted, venue, starRating)
    return { facilityKinds = venue.facilityKinds, reputation = EqHostManager.reputation[hosted.farmId] or 0,
        starRating = starRating, monthsAhead = hosted.monthsAhead, advert = hosted.advert, shops = venue.shops,
        buzz = hosted.buzz, weather = hosted.weather, sponsor = hosted.sponsorPopularity }
end


--- Popularity and turnout for a hosted event, from the farm as it is now.
--- @param event table
--- @param starRating number|nil
--- @return table result from EqHosting.check
--- @return number popularity
--- @return table takings from EqHosting.takings
--- @return table venue
--- @return table parts from EqHosting.popularity
local function assess(event, starRating)
    local config = EqHostVenue.config
    local hosted = event.hosted
    local venue = EqHostVenue.read(hosted.farmId)
    local result = EqHosting.check(config, event.discipline, hosted.rating, venue)
    local score, parts = EqHosting.popularity(config, event.discipline, result, EqHostManager.contextFor(hosted, venue, starRating))
    local takings = EqHosting.takings(config, event.discipline, config.ratingByName[hosted.rating], score, result.seatingTotal,
        hosted.weather)
    return result, score, takings, venue, parts
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
    local result, score, takings, venue = assess(event, nil)
    hosted.openedDay = today()
    -- How much of it is out in the weather, measured once (James, 2026-11-01: keep it light).
    local picks = result.picks or {}
    if picks.crossCountry ~= nil then picks.crossCountry.outdoor = EqHostVenue.outdoorShareOf(hosted.farmId, picks.crossCountry) end
    hosted.outdoor = EqHosting.outdoorShare(event.discipline, picks)
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
    -- Machines the sponsors lent for the month go back now.
    if EqSponsorLoans ~= nil then EqLog.try("EqSponsorLoans.onEventCancelled", EqSponsorLoans.onEventCancelled, event) end
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
--- @return number|nil rating the best of the farm's entries' ratings for it
--- @return string|nil name that horse's name
local function bestEntry(event)
    local best, name
    for _, entry in ipairs(event.entries) do
        local record = EqRegistry.getById(entry.horseId)
        local rating = record ~= nil and EqCompetitionManager.ratingFor(record, event) or nil
        if rating ~= nil and (best == nil or rating > best) then best, name = rating, entry.name end
    end
    return best, name
end


--- @param parts table from EqHosting.popularity
--- @param id string
--- @return number points
local function partPoints(parts, id)
    for _, part in ipairs(parts or {}) do
        if part.id == id then return part.points end
    end
    return 0
end


--- Sell souvenirs and refreshments from the farm's stock (James, 2026-11-01).
--- @param event table
--- @param venue table from EqHostVenue.read
--- @return table sale from EqHosting.goodsSale, the goods taken
local function sellGoods(event, venue)
    local hosted = event.hosted
    local stock = {}
    for _, item in ipairs(venue.shops ~= nil and venue.shops.stock or {}) do
        table.insert(stock, { name = item.name, index = item.index, litres = item.litres, price = EqHostVenue.bestPrice(item.index) })
    end
    local sale = EqHosting.goodsSale(EqHostVenue.config, hosted.rating, hosted.popularity or 0, stock)
    local indexOf = {}
    for _, item in ipairs(stock) do indexOf[item.name] = item.index end
    sale.total = 0
    for _, item in ipairs(sale.items) do
        local taken = EqHostVenue.takeGoods(hosted.farmId, indexOf[item.name], item.litres)
        if taken < item.litres then
            item.money = math.floor(item.money * taken / math.max(1, item.litres) + 0.5)
            item.litres = math.floor(taken)
        end
        sale.total = sale.total + item.money
    end
    Log:info("EqHostManager: event %s sold %d goods for %d", tostring(event.id), #sale.items, sale.total)
    return sale
end


--- The month is over: the final popularity sets the turnout, which sets the field; visitors
--- buy souvenirs and refreshments.
--- @param event table
function EqHostManager.beforeResolve(event)
    if EqHostVenue.config == nil then return end
    local hosted = event.hosted
    local starRating, starName = bestEntry(event)
    local _, score, takings, venue, parts = assess(event, starRating)
    hosted.popularity = score
    hosted.parts = parts
    -- People came to see your star (James, 2026-11-01: say so in the results).
    hosted.star = partPoints(parts, "star") > 0 and starName or nil
    hosted.weatherPoints = partPoints(parts, "weather")
    takings.goods = 0
    if hosted.sell then
        local ok, sale = EqLog.try("EqHostManager sellGoods", sellGoods, event, venue)
        if ok and sale ~= nil then
            takings.goods = sale.total
            takings.goodsLitres = sale.litres
        end
    end
    takings.total = takings.total + takings.goods
    hosted.takings = takings
    event.field = takings.competitors + math.min(#event.entries, EqHostVenue.config.ownPlaces)
end


--- @return string|nil name the WeatherType now, such as "RAIN"
local function weatherNow()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    local weather = environment ~= nil and environment.weather or nil
    if weather == nil or weather.getCurrentWeatherType == nil or WeatherType == nil then return nil end
    local ok, current = EqLog.try("EqHostManager weather", weather.getCurrentWeatherType, weather)
    if not ok or current == nil then return nil end
    for name, value in pairs(WeatherType) do
        if value == current and type(name) == "string" then return name end
    end
    return nil
end


--- A new hour: count the weather at every running hosted event (James, 2026-11-01: once an
--- hour, and only while one runs).
function EqHostManager.onHourChanged()
    local config = EqHostVenue.config
    if config == nil or config.weather == nil then return end
    local events = {}
    for _, event in pairs(EqCompetitionManager.events) do
        if event.hosted ~= nil then table.insert(events, event) end
    end
    if #events == 0 then return end
    local environment = g_currentMission.environment
    local hour = environment ~= nil and environment.currentHour or 12
    if hour < config.weather.hourFrom or hour >= config.weather.hourTo then return end
    local name = weatherNow()
    table.sort(events, function(a, b) return a.id < b.id end)
    for _, event in ipairs(events) do
        local hosted = event.hosted
        hosted.weather = hosted.weather or {}
        local first = EqHosting.countWeather(config, hosted.weather, name, hosted.outdoor or 1)
        if first then
            Log:info("EqHostManager: %s hit event %s", tostring(name), tostring(event.id))
            tell(hosted.farmId, "EQ_HOST_WEATHER", string.format(g_i18n:getText("eq_host_twister"), EqCompetitionManager.eventTitle(event)),
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
        end
    end
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
        table.insert(mine, { name = placing.name, place = placing.place or 0, status = placing.status,
            penalties = placing.penalties, phases = placing.phases })
    end
    return { day = day, discipline = event.discipline, rating = hosted.rating, venue = event.venue, sponsor = hosted.sponsor,
        field = result.field or 0, competitors = takings.competitors or 0, visitors = takings.visitors or 0,
        popularity = hosted.popularity or 0, entries = takings.entries or 0, gate = takings.gate or 0,
        total = takings.total or 0, setupFee = hosted.setupFee or 0, feed = hosted.feedEaten or 0, podium = result.podium or {}, mine = mine,
        goods = takings.goods or 0, goodsLitres = takings.goodsLitres or 0, advertCost = hosted.advertCost or 0, star = hosted.star,
        wetHours = math.floor((hosted.weather ~= nil and hosted.weather.bad or 0) + 0.5), weatherPoints = hosted.weatherPoints or 0,
        twister = hosted.weather ~= nil and (hosted.weather.flat or 0) > 0 or nil,
        totals = result.totals or {}, phases = result.phases or {} }
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


--- Pay the takings (and the sponsor's fee) and raise the farm's reputation.
--- @param event table
function EqHostManager.afterResolve(event)
    local hosted = event.hosted
    local takings = hosted.takings
    if takings == nil then return end
    local environment = g_currentMission.environment
    local report = EqHostManager.report(event, environment ~= nil and environment.currentMonotonicDay or 0)
    if EqSponsorManager ~= nil then EqLog.try("EqSponsorManager.afterEvent", EqSponsorManager.afterEvent, event, report) end
    EqHostManager.keepReport(hosted.farmId, report)
    if takings.total > 0 then
        g_currentMission:addMoney(takings.total, hosted.farmId, MoneyType.EQ_HOSTING or MoneyType.OTHER, true, true)
    end
    EqHostManager.reputation[hosted.farmId] = EqHosting.nextReputation(EqHostVenue.config,
        EqHostManager.reputation[hosted.farmId] or 0, true)
    local money = function(amount) return g_i18n:formatMoney(amount, 0, true, true) end
    local text = string.format(g_i18n:getText("eq_host_done"), EqCompetitionManager.eventTitle(event),
        takings.competitors, money(takings.total), money(takings.entries), money(takings.gate), hosted.popularity)
    if (takings.goods or 0) > 0 then text = text .. " " .. string.format(g_i18n:getText("eq_host_done_goods"), money(takings.goods)) end
    if hosted.star ~= nil then text = text .. " " .. string.format(g_i18n:getText("eq_host_star"), hosted.star) end
    tell(hosted.farmId, "EQ_HOST_DONE", text)
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
    keepRidden(event, horseId, phase, EqHosting.roundSheet(sj.result, sj.refusals))
end


--- The dressage test for an arena in the month of your own event: the event's fixed test,
--- the same for every horse and every ride (training is random in other months, James
--- 2026-10-29). It counts for a horse entered in the event that has not ridden its dressage yet,
--- in an arena big enough for the event's rating. nil when no event of yours with a dressage
--- phase is on.
--- @param horseId string|nil the ridden horse
--- @param markers table the dressage course's markers
--- @return table|nil test { seed, moves, counts, event, status }: status for the notice at A,
--- as competitionFor's ("counts", "ridden" or "small") or "notEntered"
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
    -- A horse that isn't entered rides the event's test as practice, and is told so.
    local counts, status = false, "notEntered"
    if event == mine then
        local ridden = event.hosted.ridden ~= nil and event.hosted.ridden[horseId] or nil
        if ridden ~= nil and ridden.dressage ~= nil then
            status = "ridden"
        else
            status = "small"
            for _, arena in ipairs(EqHosting.arenasFromMarkers(markers or {})) do
                if arena.length >= rating.dressageArena then counts, status = true, "counts" end
            end
        end
    end
    return { seed = string.format("dressage %s %s", tostring(event.id), tostring(event.hosted.rating)), moves = rating.dressageMoves, counts = counts,
        event = event, status = status, steps = EqHosting.testSteps(rating) }
end


-- SETTING COURSES AND TESTS
-- Courses and tests are set before the event month: during it you can't delete one that is big
-- enough for the event, and one made too short is practice only (James, 2026-11-01).

--- @return number|nil farmId the local player's farm
local function playerFarm()
    local mission = g_currentMission
    return mission ~= nil and mission.getFarmId ~= nil and mission:getFarmId() or nil
end


--- @param farmId number|nil
--- @param phase string
--- @return table|nil event the farm's hosted event running now with this phase
function EqHostManager.runningFor(farmId, phase)
    if farmId == nil then return nil end
    local found = nil
    for _, event in pairs(EqCompetitionManager.events) do
        if event.hosted ~= nil and event.hosted.farmId == farmId and hasPhase(event, phase) and (found == nil or event.id < found.id) then
            found = event
        end
    end
    return found
end


--- @param course table EqCourse course
--- @return table|nil event the running event of yours this course is big enough for: it can't be
---     deleted until the event is over
function EqHostManager.courseLocked(course)
    if course == nil or EqHostVenue.config == nil then return nil end
    local phase = course.kind or EqCourse.SHOW_JUMPING
    local event = EqHostManager.runningFor(playerFarm(), phase)
    local rating = event ~= nil and ratingOf(event) or nil
    if rating == nil then return nil end
    local shape = { kind = phase, jumps = #(course.jumps or {}), length = course.length or EqCourse.pathLength(course.points or {}) }
    return EqHosting.courseQualifies(rating, phase, shape) and event or nil
end


--- @param frame table EqDressagePath.frameFor, the arena
--- @param plan table|nil the arena's own test
--- @return table|nil event the running event of yours this test (in this arena) is good for: it
---     can't be deleted until the event is over
function EqHostManager.testLocked(frame, plan)
    if frame == nil or plan == nil or EqHostVenue.config == nil then return nil end
    local event = EqHostManager.runningFor(playerFarm(), "dressage")
    local rating = event ~= nil and ratingOf(event) or nil
    if rating == nil then return nil end
    if #plan.steps < EqHosting.testSteps(rating) then return nil end
    if EqHosting.arenaLength((frame.halfL or 0) * 2) < rating.dressageArena then return nil end
    return event
end


--- Is a test too short for your hosted event, running or booked? For the editor's save.
--- @param steps number the test's steps
--- @return string|nil title the event's, when the test is too short for it
--- @return number|nil need the steps it needs
function EqHostManager.testTooShort(steps)
    local config = EqHostVenue.config
    if config == nil then return nil end
    local farmId = playerFarm()
    local event = EqHostManager.runningFor(farmId, "dressage")
    local rating, title = nil, nil
    if event ~= nil then
        rating, title = ratingOf(event), EqCompetitionManager.eventTitle(event)
    else
        local booking = farmId ~= nil and EqHostManager.bookings[farmId] or nil
        if booking ~= nil and EqHosting.hasPart(booking.type, "dressage") then
            rating, title = config.ratingByName[booking.rating], EqHostManager.title(booking.type, booking.rating)
        end
    end
    if rating == nil then return nil end
    local need = EqHosting.testSteps(rating)
    if steps < need then return title, need end
    return nil
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
    if hosted.sponsor ~= nil then xmlFile:setString(key .. "#sponsor", hosted.sponsor) end
    if hosted.sponsorBrand ~= nil then xmlFile:setString(key .. "#sponsorBrand", hosted.sponsorBrand) end
    if hosted.sponsorBrands ~= nil then xmlFile:setString(key .. "#sponsorBrands", hosted.sponsorBrands) end
    if hosted.sponsorPopularity ~= nil then xmlFile:setInt(key .. "#sponsorPopularity", hosted.sponsorPopularity) end
    if hosted.monthsAhead ~= nil then xmlFile:setInt(key .. "#monthsAhead", hosted.monthsAhead) end
    if hosted.advert ~= nil then xmlFile:setString(key .. "#advert", hosted.advert) end
    if hosted.advertCost ~= nil then xmlFile:setFloat(key .. "#advertCost", hosted.advertCost) end
    if hosted.sell ~= nil then xmlFile:setBool(key .. "#sell", hosted.sell) end
    if hosted.buzz ~= nil then xmlFile:setInt(key .. "#buzz", hosted.buzz) end
    if hosted.outdoor ~= nil then xmlFile:setFloat(key .. "#outdoor", hosted.outdoor) end
    local weather = hosted.weather
    if weather ~= nil then
        xmlFile:setInt(key .. ".weather#hours", weather.hours or 0)
        xmlFile:setFloat(key .. ".weather#bad", weather.bad or 0)
        xmlFile:setFloat(key .. ".weather#flat", weather.flat or 0)
        local seen = {}
        for name in pairs(weather.seen or {}) do table.insert(seen, name) end
        table.sort(seen)
        if #seen > 0 then xmlFile:setString(key .. ".weather#seen", table.concat(seen, " ")) end
    end
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
    hosted.sponsor = xmlFile:getString(key .. "#sponsor")
    hosted.sponsorBrand = xmlFile:getString(key .. "#sponsorBrand")
    hosted.sponsorBrands = xmlFile:getString(key .. "#sponsorBrands")
    hosted.sponsorPopularity = xmlFile:getInt(key .. "#sponsorPopularity")
    hosted.monthsAhead = xmlFile:getInt(key .. "#monthsAhead")
    hosted.advert = xmlFile:getString(key .. "#advert")
    hosted.advertCost = xmlFile:getFloat(key .. "#advertCost")
    hosted.sell = xmlFile:getBool(key .. "#sell")
    hosted.buzz = xmlFile:getInt(key .. "#buzz")
    hosted.outdoor = xmlFile:getFloat(key .. "#outdoor")
    if xmlFile:hasProperty(key .. ".weather") then
        hosted.weather = { hours = xmlFile:getInt(key .. ".weather#hours", 0), bad = xmlFile:getFloat(key .. ".weather#bad", 0),
            flat = xmlFile:getFloat(key .. ".weather#flat", 0) }
        local seen = xmlFile:getString(key .. ".weather#seen")
        if seen ~= nil then
            hosted.weather.seen = {}
            for name in string.gmatch(seen, "%S+") do hosted.weather.seen[name] = true end
        end
    end
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
                time = xmlFile:getFloat(rideKey .. "#time", 0), eliminated = xmlFile:getBool(rideKey .. "#eliminated", false) or nil }
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
            if booking.monthsAhead ~= nil then xmlFile:setInt(farmKey .. ".booking#monthsAhead", booking.monthsAhead) end
            if booking.advert ~= nil then xmlFile:setString(farmKey .. ".booking#advert", booking.advert) end
            if booking.advertCost ~= nil then xmlFile:setFloat(farmKey .. ".booking#advertCost", booking.advertCost) end
            if booking.sell ~= nil then xmlFile:setBool(farmKey .. ".booking#sell", booking.sell) end
            if booking.buzz ~= nil then xmlFile:setInt(farmKey .. ".booking#buzz", booking.buzz) end
        end
        for r, report in ipairs(EqHostManager.history[farmId] or {}) do
            EqHostManager.saveReport(xmlFile, string.format("%s.report(%d)", farmKey, r - 1), report)
        end
    end
end


local REPORT_INTS = { "day", "field", "competitors", "visitors", "popularity", "goodsLitres", "wetHours", "weatherPoints" }
local REPORT_FLOATS = { "entries", "gate", "total", "setupFee", "feed", "sponsorFee", "goods", "advertCost" }
local REPORT_STRINGS = { "discipline", "rating", "venue", "sponsor", "sponsors" }


--- @param xmlFile table
--- @param key string
--- @param report table
function EqHostManager.saveReport(xmlFile, key, report)
    for _, name in ipairs(REPORT_INTS) do xmlFile:setInt(key .. "#" .. name, report[name] or 0) end
    for _, name in ipairs(REPORT_FLOATS) do xmlFile:setFloat(key .. "#" .. name, report[name] or 0) end
    for _, name in ipairs(REPORT_STRINGS) do
        if report[name] ~= nil then xmlFile:setString(key .. "#" .. name, report[name]) end
    end
    for i, name in ipairs(report.podium or {}) do
        local podiumKey = string.format("%s.podium(%d)", key, i - 1)
        xmlFile:setString(podiumKey .. "#name", name)
        if report.totals ~= nil and report.totals[i] ~= nil then xmlFile:setFloat(podiumKey .. "#penalties", report.totals[i]) end
    end
    for i, phase in ipairs(report.phases or {}) do
        local phaseKey = string.format("%s.phase(%d)", key, i - 1)
        xmlFile:setString(phaseKey .. "#name", phase.name)
        for j, entry in ipairs(phase.top or {}) do
            local topKey = string.format("%s.top(%d)", phaseKey, j - 1)
            xmlFile:setString(topKey .. "#name", entry.name or "?")
            xmlFile:setFloat(topKey .. "#penalties", entry.penalties or 0)
        end
    end
    for i, horse in ipairs(report.mine or {}) do
        local horseKey = string.format("%s.horse(%d)", key, i - 1)
        xmlFile:setString(horseKey .. "#name", horse.name or "")
        xmlFile:setInt(horseKey .. "#place", horse.place or 0)
        if horse.status ~= nil then xmlFile:setString(horseKey .. "#status", horse.status) end
        if horse.penalties ~= nil then xmlFile:setFloat(horseKey .. "#penalties", horse.penalties) end
        for j, phase in ipairs(horse.phases or {}) do
            local phaseKey = string.format("%s.phase(%d)", horseKey, j - 1)
            xmlFile:setString(phaseKey .. "#name", phase.name)
            xmlFile:setInt(phaseKey .. "#place", phase.place or 0)
            xmlFile:setFloat(phaseKey .. "#penalties", phase.penalties or 0)
        end
    end
    if report.star ~= nil then xmlFile:setString(key .. "#star", report.star) end
    if report.twister then xmlFile:setBool(key .. "#twister", true) end
end


--- @param xmlFile table
--- @param key string
--- @return table report
function EqHostManager.loadReport(xmlFile, key)
    local report = { podium = {}, mine = {}, totals = {}, phases = {} }
    report.star = xmlFile:getString(key .. "#star")
    report.twister = xmlFile:getBool(key .. "#twister", false) or nil
    for _, name in ipairs(REPORT_INTS) do report[name] = xmlFile:getInt(key .. "#" .. name, 0) end
    for _, name in ipairs(REPORT_FLOATS) do report[name] = xmlFile:getFloat(key .. "#" .. name, 0) end
    for _, name in ipairs(REPORT_STRINGS) do report[name] = xmlFile:getString(key .. "#" .. name) end
    local i = 0
    while xmlFile:hasProperty(string.format("%s.podium(%d)", key, i)) do
        local podiumKey = string.format("%s.podium(%d)", key, i)
        table.insert(report.podium, xmlFile:getString(podiumKey .. "#name", "?"))
        local total = xmlFile:getFloat(podiumKey .. "#penalties")
        if total ~= nil then report.totals[i + 1] = total end
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("%s.phase(%d)", key, i)) do
        local phaseKey = string.format("%s.phase(%d)", key, i)
        local phase = { name = xmlFile:getString(phaseKey .. "#name", ""), top = {} }
        local j = 0
        while xmlFile:hasProperty(string.format("%s.top(%d)", phaseKey, j)) do
            local topKey = string.format("%s.top(%d)", phaseKey, j)
            table.insert(phase.top, { name = xmlFile:getString(topKey .. "#name", "?"), penalties = xmlFile:getFloat(topKey .. "#penalties", 0) })
            j = j + 1
        end
        table.insert(report.phases, phase)
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("%s.horse(%d)", key, i)) do
        local horseKey = string.format("%s.horse(%d)", key, i)
        local horse = { name = xmlFile:getString(horseKey .. "#name", ""), place = xmlFile:getInt(horseKey .. "#place", 0),
            status = xmlFile:getString(horseKey .. "#status"), penalties = xmlFile:getFloat(horseKey .. "#penalties") }
        local j = 0
        while xmlFile:hasProperty(string.format("%s.phase(%d)", horseKey, j)) do
            local phaseKey = string.format("%s.phase(%d)", horseKey, j)
            horse.phases = horse.phases or {}
            table.insert(horse.phases, { name = xmlFile:getString(phaseKey .. "#name", ""), place = xmlFile:getInt(phaseKey .. "#place", 0),
                penalties = xmlFile:getFloat(phaseKey .. "#penalties", 0) })
            j = j + 1
        end
        table.insert(report.mine, horse)
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
                    monthsAhead = xmlFile:getInt(farmKey .. ".booking#monthsAhead"),
                    advert = xmlFile:getString(farmKey .. ".booking#advert"),
                    advertCost = xmlFile:getFloat(farmKey .. ".booking#advertCost"),
                    sell = xmlFile:getBool(farmKey .. ".booking#sell"),
                    buzz = xmlFile:getInt(farmKey .. ".booking#buzz"),
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

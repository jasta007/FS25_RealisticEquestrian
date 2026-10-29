--[[
    EqHostView.lua
    Builds the rows the Events page's Host tab shows: every event type and rating the farm
    could host, with whether it is ready, its popularity, setup fee and most it could take; the checks for
    the selected one; and the farm's booking. Text only, no GUI elements.

    Part of Realistic Equestrian by Jasta007.
]]

EqHostView = {}

local function money(amount)
    return g_i18n:formatMoney(amount or 0, 0, true, true)
end


--- @param farmId number
--- @param venue table from EqHostVenue.read
--- @return table rows { type, rating, title, ready, ok, popularity, score, parts, setup, takings, maxTakings, result }
function EqHostView.optionRows(farmId, venue)
    local config = EqHostVenue.config
    local rows = {}
    if config == nil then return rows end
    local context = EqHostView.context(farmId, venue)
    for _, typeName in ipairs(EqHosting.TYPES) do
        for _, rating in ipairs(config.ratings) do
            local result = EqHosting.check(config, typeName, rating.name, venue)
            local score, parts = EqHosting.popularity(config, typeName, result, context)
            local takings = EqHosting.takings(config, typeName, rating, score, result.seatingTotal)
            -- popularity can still change before the event, so the list shows the most it could take
            local most = EqHosting.takings(config, typeName, rating, 100, result.seatingTotal)
            local missing = 0
            for _, check in ipairs(result.checks) do
                if not check.ok then missing = missing + 1 end
            end
            table.insert(rows, {
                type = typeName, rating = rating.name, result = result, score = score, parts = parts, takings = takings,
                title = EqHostManager.title(typeName, rating.name),
                ok = result.ok,
                ready = result.ok and g_i18n:getText("eq_host_ready")
                    or string.format(g_i18n:getText("eq_host_missing"), missing),
                popularity = tostring(score),
                setup = money(result.setupFee),
                maxTakings = most.total,
                takingsText = money(most.total),
            })
        end
    end
    return rows
end


--- What popularity needs beyond the venue: facilities and the farm's reputation. Your horses
--- and the season are only known in the event's month.
--- @param farmId number
--- @param venue table
--- @return table context for EqHosting.popularity
function EqHostView.context(farmId, venue)
    return { facilityKinds = venue.facilityKinds, reputation = EqHostManager.reputation[farmId] or 0 }
end


--- @param check table { id, have, need }
--- @param value number
--- @return string
local function checkValue(check, value)
    if check.id == "arena" then
        if value <= 0 then return g_i18n:getText("eq_host_none") end
        return string.format("%dx%d", value == 30 and 15 or 20, value)
    elseif check.id == "xcLength" then
        return string.format(g_i18n:getText("eq_host_metres"), value)
    elseif check.id == "feed" then
        return string.format(g_i18n:getText("eq_host_litres"), value)
    end
    return tostring(value)
end


--- @param result table from EqHosting.check
--- @return table rows { label, have, need, ok }
function EqHostView.checkRows(result)
    local rows = {}
    for _, check in ipairs(result ~= nil and result.checks or {}) do
        table.insert(rows, { label = g_i18n:getText("eq_host_check_" .. check.id), have = checkValue(check, check.have),
            need = checkValue(check, check.need), ok = check.ok })
    end
    return rows
end


--- @param parts table from EqHosting.popularity
--- @return string such as "Base 30, course +15, reputation -5"
function EqHostView.partsText(parts)
    local texts = {}
    for _, part in ipairs(parts or {}) do
        local points = part.id == "base" and tostring(part.points) or string.format("%+d", part.points)
        table.insert(texts, string.format("%s %s", g_i18n:getText("eq_host_part_" .. part.id), points))
    end
    return table.concat(texts, ", ")
end


--- The month picker's texts: "March (in 2 months)".
--- @param months table months as EqCompetitionManager.month counts them
--- @return table texts
function EqHostView.monthOptions(months)
    local texts = {}
    local now = EqCompetitionManager.month or 0
    for _, month in ipairs(months) do
        local ahead = month - now
        local key = ahead == 1 and "eq_host_monthOption1" or "eq_host_monthOption"
        table.insert(texts, string.format(g_i18n:getText(key), EqHostManager.monthText(month), ahead))
    end
    return texts
end


--- The panel under the checks: the farm's booking and what the selected row would be.
--- @param farmId number
--- @param row table|nil the selected option row
--- @param month number|nil the month the Book button books
--- @return table lines list of { label, value }
function EqHostView.panelLines(farmId, row, month)
    local lines = {}
    local booking = EqHostManager.bookings[farmId]
    local open = EqHostManager.openEvent(farmId)
    local yours
    local booked = booking ~= nil and string.format(g_i18n:getText("eq_host_yours_booked"),
        EqHostManager.title(booking.type, booking.rating), EqHostManager.monthText(booking.month)) or nil
    if open ~= nil then
        yours = string.format(g_i18n:getText("eq_host_yours_open"), EqCompetitionManager.eventTitle(open))
        if booked ~= nil then yours = yours .. "; " .. booked end
    else
        yours = booked or g_i18n:getText("eq_host_yours_none")
    end
    -- What month it is now (James forgot and had to leave the menu to look).
    table.insert(lines, 1, { label = g_i18n:getText("eq_host_label_now"), value = EqHostManager.monthText(EqCompetitionManager.month) })
    table.insert(lines, { label = g_i18n:getText("eq_host_label_yours"), value = yours })

    -- When the next event can be, and why not sooner: one at a time, and the months between.
    local now = EqCompetitionManager.month
    local choices = EqHostManager.choices(now, EqHostManager.lastMonth[farmId], EqHostManager.interval())
    local soonest = choices[1]
    if soonest ~= nil and (booking ~= nil or soonest > now + 1) then
        local why = booking ~= nil and g_i18n:getText("eq_host_next_oneAtATime")
            or string.format(g_i18n:getText("eq_host_next_interval"), EqHostManager.interval())
        table.insert(lines, { label = g_i18n:getText("eq_host_label_next"),
            value = string.format("%s (%s)", EqHostManager.monthText(soonest), why) })
    end

    if row ~= nil then
        local takings = row.takings
        table.insert(lines, { label = g_i18n:getText("eq_host_label_setup"), value = row.setup })
        table.insert(lines, { label = g_i18n:getText("eq_host_label_popularity"), value = row.popularity })
        table.insert(lines, { label = g_i18n:getText("eq_host_label_visitors"),
            value = string.format(g_i18n:getText("eq_host_visitors"), takings.competitors, takings.visitors) })
        table.insert(lines, { label = g_i18n:getText("eq_host_label_takings"),
            value = string.format(g_i18n:getText("eq_host_takingsLine"), money(takings.entries), money(takings.gate)) })
        table.insert(lines, { label = g_i18n:getText("eq_host_col_takings"), value = money(row.maxTakings) })
    end
    table.insert(lines, { label = g_i18n:getText("eq_host_label_reputation"),
        value = string.format("%+d", math.floor((EqHostManager.reputation[farmId] or 0) + 0.5)) })
    return lines
end


--- The "Your events" row's lines on the Results tab: the event on now, then each finished one
--- with its winners, turnout, money and how your horses did.
--- @param farmId number
--- @return table rows { title = true|nil, text }
function EqHostView.reportRows(farmId)
    local manager = EqCompetitionManager
    local rows = {}
    local open = EqHostManager.openEvent(farmId)
    if open ~= nil then
        local days = EqHostManager.daysLeft()
        table.insert(rows, { title = true, text = string.format(g_i18n:getText("eq_host_report_running"), manager.eventTitle(open)) })
        table.insert(rows, { text = string.format(g_i18n:getText("eq_host_report_runningLine"), days or 0) })
    end
    for _, report in ipairs(EqHostManager.history[farmId] or {}) do
        local parts = {
            string.format(g_i18n:getText("eq_ui_day"), report.day),
            string.format("%s (%s)", manager.eventName(report.discipline, report.rating, report.venue, true), manager.tierTitle(report.rating)),
            string.format(g_i18n:getText("eq_host_report_field"), report.field),
        }
        table.insert(rows, { title = true, text = table.concat(parts, "  |  ") })
        local podium = EqStory.podiumLine(report.podium or {})
        if podium ~= nil then table.insert(rows, { text = podium }) end
        table.insert(rows, { text = string.format(g_i18n:getText("eq_host_report_turnout"), report.competitors, report.visitors,
            report.popularity) })
        table.insert(rows, { text = string.format(g_i18n:getText("eq_host_report_money"), money(report.total), money(report.entries),
            money(report.gate), money(report.setupFee), money(report.total - report.setupFee)) })
        for _, horse in ipairs(report.mine or {}) do
            local how = horse.status ~= nil and g_i18n:getText("eq_ui_result_" .. horse.status)
                or string.format(g_i18n:getText("eq_ui_result_placeOrd"), EqStory.ordinal(horse.place), report.field)
            table.insert(rows, { text = string.format(g_i18n:getText("eq_host_report_mine"), horse.name, how) })
        end
    end
    return rows
end


--- The "Your events" row for the Results tab's horse list, or nil before the farm has hosted.
--- @param farmId number
--- @return table|nil row shaped like EqEventsView.resultHorseRows' rows
function EqHostView.resultsRow(farmId)
    local history = EqHostManager.history[farmId] or {}
    local open = EqHostManager.openEvent(farmId)
    if #history == 0 and open == nil then return nil end
    local last = history[1]
    local winner = last ~= nil and last.podium ~= nil and last.podium[1] or nil
    return { hosted = true, record = { id = "eqHostedEvents" }, name = g_i18n:getText("eq_host_results_row"),
        starts = tostring(#history), wins = "-",
        last = open ~= nil and g_i18n:getText("eq_host_results_running")
            or (winner ~= nil and string.format(g_i18n:getText("eq_host_results_winner"), winner) or "-") }
end

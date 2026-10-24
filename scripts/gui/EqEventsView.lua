--[[
    EqEventsView.lua
    Builds the rows the Events tab shows: open events, the player's horses for one event, and
    the player's results. Text only, no GUI elements, so the smoke test can check it headless.
]]

EqEventsView = {}

EqEventsView.TIER_ORDER = { training = 1, novice = 2, intermediate = 3, advanced = 4, championship = 5 }


--- @param amount number
--- @return string
local function money(amount)
    return g_i18n:formatMoney(amount or 0, 0, true, true)
end


--- @param animal table
--- @param record table
--- @return string
local function horseName(animal, record)
    local name = animal.getName ~= nil and animal:getName() or nil
    if name == nil or name == "" then return record.id end
    return name
end


--- Open events, round events first, then by tier, discipline and fee.
--- @param farmId number
--- @return table rows { event, title, level, going, when, fee, prize, yours }
function EqEventsView.eventRows(farmId)
    local manager = EqCompetitionManager
    local horses = EqRLRM.listHorsesForFarm(farmId)
    local list = {}
    for _, event in pairs(manager.events) do table.insert(list, event) end

    local disciplineOrder = {}
    for i, discipline in ipairs(manager.config.disciplines) do disciplineOrder[discipline.name] = i end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind == EqCompetition.KIND_ROUND end
        local ta, tb = EqEventsView.TIER_ORDER[a.tier] or 9, EqEventsView.TIER_ORDER[b.tier] or 9
        if ta ~= tb then return ta < tb end
        local da, db = disciplineOrder[a.discipline] or 99, disciplineOrder[b.discipline] or 99
        if da ~= db then return da < db end
        if a.fee ~= b.fee then return a.fee < b.fee end
        return a.id < b.id
    end)

    local cadence = manager.settings.cadence == manager.CADENCE_DAY and "eq_ui_when_tomorrow" or "eq_ui_when_nextMonth"
    local rows = {}
    for _, event in ipairs(list) do
        local entered = {}
        for _, entry in ipairs(event.entries) do
            if entry.farmId == farmId then table.insert(entered, entry.name) end
        end

        local yours
        if #entered > 0 then
            yours = string.format(g_i18n:getText("eq_ui_entered"), table.concat(entered, ", "))
        elseif manager.entriesLeft(farmId) == 0 then
            yours = g_i18n:getText("eq_ui_farmLimit")
        else
            local count = manager.countEligible(event, horses)
            yours = count > 0 and string.format(g_i18n:getText("eq_ui_canEnter"), count) or g_i18n:getText("eq_ui_noneEligible")
        end

        table.insert(rows, {
            event = event,
            title = manager.eventName(event.discipline, event.tier),
            level = manager.tierTitle(event.tier),
            going = manager.conditionsText(event.going),
            when = g_i18n:getText(event.kind == EqCompetition.KIND_MONTH and "eq_ui_when_nextMonth" or cadence),
            fee = money(event.fee),
            prize = event.prize > 0 and money(event.prize) or g_i18n:getText("eq_ui_trainingOnly"),
            yours = yours,
            hasEntry = #entered > 0,
        })
    end
    return rows
end


--- The player's horses for one event: rating, and whether and why not they can enter.
--- @param event table
--- @param farmId number
--- @return table rows { animal, record, name, age, rating, status, canEnter, transport }
function EqEventsView.horseRows(event, farmId)
    local manager = EqCompetitionManager
    local tier = manager.config.tierByName[event.tier]
    local outOfEntries = manager.entriesLeft(farmId) == 0
    local rows = {}

    for _, animal in ipairs(EqRLRM.listHorsesForFarm(farmId)) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil then
            local age = animal.age or 0
            local rating = manager.ratingFor(record, event)
            local status, canEnter

            local entered = manager.findEntry(record.id, event.kind)
            local unavailable = manager.unavailableReason(record, event.kind)
            if entered ~= nil then
                status = entered == event and g_i18n:getText("eq_ui_status_enteredHere") or g_i18n:getText("eq_ui_status_enteredElsewhere")
            elseif unavailable == "injured" then
                status = string.format(g_i18n:getText("eq_status_injured"), record.injury.monthsLeft)
            elseif unavailable ~= nil then
                status = g_i18n:getText("eq_status_" .. unavailable)
            else
                local ok, reason = EqCompetition.canEnter(tier, age, rating)
                canEnter = ok and not outOfEntries
                if ok and outOfEntries then
                    status = g_i18n:getText("eq_ui_farmLimit")
                else
                    status = g_i18n:getText(ok and "eq_ui_status_ok" or ("eq_ui_status_" .. reason))
                end
            end

            table.insert(rows, {
                animal = animal,
                record = record,
                name = horseName(animal, record),
                age = string.format(g_i18n:getText("eq_ui_ageMonths"), age),
                rating = string.format("%d", math.floor(rating + 0.5)),
                ratingValue = rating,
                status = status,
                canEnter = canEnter == true,
                transport = manager.transportCost(animal),
            })
        end
    end

    -- Horses that can enter first, best rating first.
    table.sort(rows, function(a, b)
        if a.canEnter ~= b.canEnter then return a.canEnter end
        return a.ratingValue > b.ratingValue
    end)
    return rows
end


--- The player's latest results, newest first.
--- @param farmId number
--- @return table rows { day, title, horse, result, prize }
function EqEventsView.resultRows(farmId)
    local manager = EqCompetitionManager
    local rows = {}
    for _, summary in ipairs(manager.results) do
        for _, placing in ipairs(summary.placings) do
            if placing.farmId == farmId then
                local result
                if placing.status ~= nil then
                    result = g_i18n:getText("eq_ui_result_" .. placing.status)
                else
                    result = string.format(g_i18n:getText("eq_ui_result_place"), placing.place, summary.field)
                end
                table.insert(rows, {
                    day = string.format(g_i18n:getText("eq_ui_day"), summary.day),
                    title = manager.eventName(summary.discipline, summary.tier),
                    horse = placing.name,
                    result = result,
                    prize = placing.prize > 0 and money(placing.prize) or "-",
                })
            end
        end
    end
    return rows
end

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


--- Sort order for open events: by type (alphabetical, as the table shows it), then level from
--- lowest to highest, then fee, so similar events sit together. The console listing uses it too.
--- @param a table event
--- @param b table event
--- @return boolean
function EqEventsView.compareEvents(a, b)
    local typeA, typeB = g_i18n:getText("eq_type_" .. a.discipline), g_i18n:getText("eq_type_" .. b.discipline)
    if typeA ~= typeB then return typeA < typeB end
    local ta, tb = EqEventsView.TIER_ORDER[a.tier] or 9, EqEventsView.TIER_ORDER[b.tier] or 9
    if ta ~= tb then return ta < tb end
    if a.fee ~= b.fee then return a.fee < b.fee end
    return a.id < b.id
end


--- Open events, grouped by type then level (see compareEvents).
--- @param farmId number
--- @return table rows { event, title, type, level, going, risk, riskBand, when, fee, prize, yours }
function EqEventsView.eventRows(farmId)
    local manager = EqCompetitionManager
    local horses = EqRLRM.listHorsesForFarm(farmId)
    local list = {}
    for _, event in pairs(manager.events) do table.insert(list, event) end
    table.sort(list, EqEventsView.compareEvents)

    local cadence = manager.settings.cadence == manager.CADENCE_DAY and "eq_ui_when_tomorrow" or "eq_ui_when_nextMonth"
    local rows = {}
    for _, event in ipairs(list) do
        local entered = {}
        for _, entry in ipairs(event.entries) do
            if entry.farmId == farmId then
                table.insert(entered, manager.isDelivered(entry) and entry.name
                    or string.format(g_i18n:getText("eq_ui_awaiting"), entry.name))
            end
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

        local riskBand = manager.eventRisk(event)
        table.insert(rows, {
            event = event,
            title = manager.eventName(event.discipline, event.tier, event.venue),
            type = g_i18n:getText("eq_type_" .. event.discipline),
            level = manager.tierTitle(event.tier),
            going = manager.conditionsText(event.going),
            risk = manager.riskText(riskBand),
            riskBand = riskBand,
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
--- @return table rows { animal, record, name, age, status, canEnter, transport (= autoCost), autoCost,
---     manualCost, success, successBand, training, trainingBand (nil when the event gives no training),
---     risk, riskBand (this horse's injury risk) }
function EqEventsView.horseRows(event, farmId)
    local manager = EqCompetitionManager
    local tier = manager.config.tierByName[event.tier]
    local outOfEntries = manager.entriesLeft(farmId) == 0
    local eventFull = manager.eventFull(event, farmId)
    local rows = {}

    for _, animal in ipairs(EqRLRM.listHorsesForFarm(farmId)) do
        local record = EqRegistry.getOrCreate(animal)
        -- Retired horses are left off: they will never enter, so they only crowd the list.
        if record ~= nil and not record.retired then
            local age = animal.age or 0
            local rating = manager.ratingFor(record, event)
            local status, canEnter

            local entered = manager.findEntry(record.id, event.kind)
            local unavailable = manager.unavailableReason(record, event.kind, animal)
            if entered ~= nil then
                status = entered == event and g_i18n:getText("eq_ui_status_enteredHere") or g_i18n:getText("eq_ui_status_enteredElsewhere")
                if entered == event and manager.awaitingDelivery(animal) then
                    status = g_i18n:getText("eq_ui_status_awaitingDelivery")
                end
            elseif unavailable == "injured" then
                status = string.format(g_i18n:getText("eq_status_injured"), record.injury.monthsLeft)
            elseif unavailable ~= nil then
                status = g_i18n:getText("eq_status_" .. unavailable)
            else
                local ok, reason = EqCompetition.canEnter(tier, age, rating)
                canEnter = ok and not outOfEntries and not eventFull
                if ok and outOfEntries then
                    status = g_i18n:getText("eq_ui_farmLimit")
                elseif ok and eventFull then
                    status = g_i18n:getText("eq_ui_status_eventFull")
                else
                    status = g_i18n:getText(ok and "eq_ui_status_ok" or ("eq_ui_status_" .. reason))
                end
            end

            -- Odds and training only mean something for a horse that is or could be in this event.
            local relevant = canEnter or entered == event
            local prospects = manager.prospects(record, animal, event)
            local autoCost, manualCost = manager.transportCosts(animal, event, farmId)
            table.insert(rows, {
                animal = animal,
                record = record,
                name = horseName(animal, record),
                age = string.format(g_i18n:getText("eq_ui_ageMonths"), age),
                ratingValue = rating,
                success = relevant and g_i18n:getText("eq_success_" .. prospects.success) or "",
                successBand = relevant and prospects.success or nil,
                chance = prospects.chance,
                training = (relevant and prospects.benefit ~= nil) and g_i18n:getText("eq_benefit_" .. prospects.benefit) or "-",
                trainingBand = relevant and prospects.benefit or nil,
                status = status,
                canEnter = canEnter == true,
                transport = autoCost,
                autoCost = autoCost,
                manualCost = manualCost,
                risk = manager.riskText(prospects.risk),
                riskBand = prospects.risk,
            })
        end
    end

    -- Horses that can enter first, best chance first.
    table.sort(rows, function(a, b)
        if a.canEnter ~= b.canEnter then return a.canEnter end
        if a.chance ~= b.chance then return a.chance > b.chance end
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
                    title = manager.eventName(summary.discipline, summary.tier, summary.venue),
                    horse = placing.name,
                    result = result,
                    prize = placing.prize > 0 and money(placing.prize) or "-",
                })
            end
        end
    end
    return rows
end

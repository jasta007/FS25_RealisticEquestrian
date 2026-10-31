--[[
    EqSponsorView.lua
    Builds the rows the Events page's Sponsors tab shows: the farm's sponsor and this year's
    offers in the table, and for the selected one its demands, rewards and whether the farm can
    sign. Text only, no GUI elements.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsorView = {}

local function money(amount)
    return g_i18n:formatMoney(amount or 0, 0, true, true)
end


--- @param share number 0..1
--- @return string such as "25%"
local function percent(share)
    return string.format("%d%%", math.floor((share or 0) * 100 + 0.5))
end


--- @param years number
--- @return string "1 year" or "3 years"
local function yearsText(years)
    return string.format(g_i18n:getText(years == 1 and "eq_sponsor_year1" or "eq_sponsor_years"), years)
end


--- @param farmId number
--- @return table rows { offer, contract (true for the farm's sponsor), title, size, deal, years, fee }
function EqSponsorView.rows(farmId)
    local rows = {}
    if EqSponsorManager.config == nil then return rows end
    local function add(offer, isContract)
        local years = yearsText(offer.years or 1)
        if isContract then
            local monthsLeft = math.max(0, (offer.endMonth or 0) - (EqCompetitionManager.month or 0))
            years = string.format(g_i18n:getText("eq_sponsor_yoursLeft"), yearsText(math.max(1, math.ceil(monthsLeft / 12))))
        end
        table.insert(rows, { offer = offer, contract = isContract, title = EqSponsorManager.brandTitle(offer.brand),
            size = g_i18n:getText("eq_sponsor_size_" .. offer.size), deal = g_i18n:getText("eq_sponsor_word_" .. (offer.word or "fair")),
            years = years, fee = money(offer.fee) })
    end
    local contract = EqSponsorManager.contracts[farmId]
    if contract ~= nil then add(contract, true) end
    for _, offer in ipairs(EqSponsorManager.openOffers(farmId)) do add(offer, false) end
    return rows
end


--- @param name string|nil a hosting rating
--- @return string its title
local function ratingTitle(name)
    return g_i18n:getText("eq_host_rating_" .. tostring(name))
end


--- @param offer table
--- @return string which events the sponsor pays for, such as "Championship (25% at Intermediate)"
function EqSponsorView.backsText(offer)
    local size = EqSponsorManager.config.sizeByName[offer.size]
    if size == nil then return "" end
    local ratings = EqHostVenue.config ~= nil and EqHostVenue.config.ratings or {}
    local lowest = ratings[1] ~= nil and ratings[1].name or nil
    local last = ratings[#ratings] ~= nil and ratings[#ratings].name or nil
    local text
    if size.minRating == lowest then
        text = g_i18n:getText("eq_sponsor_backs_all")
    elseif size.minRating == last then
        text = ratingTitle(size.minRating)
    else
        text = string.format(g_i18n:getText("eq_sponsor_backs_from"), ratingTitle(size.minRating))
    end
    if size.lowerShare > 0 and size.lowerRating ~= nil then
        text = string.format(g_i18n:getText("eq_sponsor_backs_lower"), text, percent(size.lowerShare), ratingTitle(size.lowerRating))
    end
    return text
end


--- @param offer table
--- @return string the yearly target, such as "An Intermediate or better event at popularity 65, with a top 3 finish"
function EqSponsorView.targetText(offer)
    local size = EqSponsorManager.config.sizeByName[offer.size]
    local lowest = size ~= nil and (size.lowerShare > 0 and size.lowerRating or size.minRating) or nil
    local text = string.format(g_i18n:getText("eq_sponsor_target"), ratingTitle(lowest), offer.target or 0)
    if offer.top3 then text = text .. g_i18n:getText("eq_sponsor_targetTop3") end
    return text
end


--- The panel's lines for the selected row: label, value and whether it is met (true/false,
--- nil for plain).
--- @param farmId number
--- @param row table|nil
--- @return table lines list of { label, value, ok }
--- @return table clashes the farm's machines breaking the competitor clause
function EqSponsorView.panelLines(farmId, row)
    local lines = {}
    if row == nil then return lines, {} end
    local offer = row.offer
    local function add(key, value, ok) table.insert(lines, { label = g_i18n:getText("eq_sponsor_label_" .. key), value = value, ok = ok }) end
    local checks, clashes = EqSponsorManager.checksFor(farmId, offer)
    local byId = {}
    for _, check in ipairs(checks) do byId[check.id] = check end

    add("deal", g_i18n:getText("eq_sponsor_word_" .. (offer.word or "fair")))
    add("fee", string.format(g_i18n:getText("eq_sponsor_feeLine"), money(offer.fee), EqSponsorView.backsText(offer)))
    add("popularity", string.format("%+d", offer.popularity or 0))
    add("target", EqSponsorView.targetText(offer))
    local boards = byId.boards
    add("boards", string.format(g_i18n:getText("eq_sponsor_boardsLine"), boards.have, offer.signsFull or 1), boards.ok)
    local machines = byId.machines
    add("machines", string.format(g_i18n:getText("eq_sponsor_machinesLine"), machines.have, machines.need, offer.categories or 0), machines.ok)
    local rivals = byId.rivals
    add("rivals", rivals.have == 0 and string.format(g_i18n:getText("eq_sponsor_rivalsNone"), percent(offer.window))
        or string.format(g_i18n:getText("eq_sponsor_rivalsSome"), rivals.have, percent(offer.window)), rivals.ok)
    add("discounts", string.format(g_i18n:getText("eq_sponsor_discountsLine"), percent(offer.repaint), percent(offer.repair), percent(offer.purchase)))

    if row.contract then
        add("ends", EqHostManager.monthText(offer.endMonth or 0))
        local yearText = offer.met and g_i18n:getText("eq_sponsor_yearMet")
            or string.format(g_i18n:getText("eq_sponsor_yearOpen"), EqHostManager.monthText(offer.yearEnd or 0))
        add("thisYear", yearText, offer.met and true or nil)
        if (offer.misses or 0) > 0 then
            add("missed", string.format(g_i18n:getText("eq_sponsor_missedLine"), offer.misses, percent(offer.feeFactor or 1)), false)
        end
        add("paid", money(offer.paid))
        local cost = EqSponsorManager.cancelCost(farmId)
        add("cancel", money(cost))
    else
        add("years", yearsText(offer.years or 1))
        local status
        if byId.exclusive ~= nil and not byId.exclusive.ok then
            status = g_i18n:getText("eq_sponsor_status_taken")
        elseif checks.ok then
            status = g_i18n:getText("eq_sponsor_status_ready")
        else
            status = g_i18n:getText("eq_sponsor_status_notReady")
        end
        add("status", status, checks.ok)
    end
    return lines, row.contract and {} or clashes
end


--- @param clashes table owned machines breaking the competitor clause
--- @return string text naming them, "" for none
function EqSponsorView.clashText(clashes)
    if #clashes == 0 then return "" end
    local names = {}
    for _, machine in ipairs(clashes) do table.insert(names, string.format("%s (%s)", machine.name or "?", money(machine.price))) end
    return string.format(g_i18n:getText("eq_sponsor_clashes"), table.concat(names, ", "))
end


--- The summary under the tab.
--- @param farmId number
--- @return string
function EqSponsorView.summary(farmId)
    if EqSponsorManager.offersOpen(farmId) then
        local record = EqSponsorManager.offersFor(farmId)
        return string.format(g_i18n:getText("eq_sponsor_summaryOpen"),
            EqHostManager.monthText(record.madeMonth + EqSponsorManager.config.offerMonths))
    end
    return g_i18n:getText("eq_sponsor_summaryClosed")
end

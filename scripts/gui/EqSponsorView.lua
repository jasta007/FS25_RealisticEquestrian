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
--- @return table rows { offer, contract (true for the farm's sponsor), brand, title, size, deal, years, fee,
---     eligibility, eligible (true, false, or nil for the farm's own sponsor) }
function EqSponsorView.rows(farmId)
    local rows = {}
    if EqSponsorManager.config == nil then return rows end
    local function add(offer, isContract)
        local years = yearsText(offer.years or 1)
        local eligibility, eligible
        if isContract then
            local monthsLeft = math.max(0, (offer.endMonth or 0) - (EqCompetitionManager.month or 0))
            years = string.format(g_i18n:getText("eq_sponsor_yoursLeft"), yearsText(math.max(1, math.ceil(monthsLeft / 12))))
            eligibility = g_i18n:getText("eq_sponsor_eligible_yours")
        else
            local checks = EqSponsorManager.checksFor(farmId, offer)
            eligible = checks.ok
            local exclusive = nil
            for _, check in ipairs(checks) do
                if check.id == "exclusive" then exclusive = check end
            end
            if exclusive ~= nil and not exclusive.ok then
                eligibility = g_i18n:getText("eq_sponsor_eligible_taken")
            else
                eligibility = g_i18n:getText(checks.ok and "eq_sponsor_eligible_yes" or "eq_sponsor_eligible_no")
            end
        end
        table.insert(rows, { offer = offer, contract = isContract, brand = offer.brand, title = EqSponsorManager.brandTitle(offer.brand),
            size = g_i18n:getText("eq_sponsor_size_" .. offer.size), deal = g_i18n:getText("eq_sponsor_word_" .. (offer.word or "fair")),
            years = years, fee = money(offer.fee), eligibility = eligibility, eligible = eligible })
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


--- The panel's lines for the selected row: label, value and whether it is met (true/false,
--- nil for plain). Long values take a second line with no label (James, 2026-10-31).
--- @param farmId number
--- @param row table|nil
--- @return table lines list of { label, value, ok }
--- @return table clashes the farm's machines breaking the competitor clause
function EqSponsorView.panelLines(farmId, row)
    local lines = {}
    if row == nil then return lines, {} end
    local offer = row.offer
    local function add(key, value, ok)
        table.insert(lines, { label = key ~= nil and g_i18n:getText("eq_sponsor_label_" .. key) or "", value = value, ok = ok })
    end
    local checks, clashes = EqSponsorManager.checksFor(farmId, offer)
    local byId = {}
    for _, check in ipairs(checks) do byId[check.id] = check end

    add("deal", g_i18n:getText("eq_sponsor_word_" .. (offer.word or "fair")))
    add("fee", string.format(g_i18n:getText("eq_sponsor_feePerEvent"), money(offer.fee)))
    add(nil, EqSponsorView.backsText(offer))
    add("popularity", string.format("%+d", offer.popularity or 0))
    add("target", string.format(g_i18n:getText("eq_sponsor_targetPopularity"), offer.target or 0))
    add(nil, EqSponsorView.targetRatingText(offer))
    local boards = byId.boards
    add("boards", string.format(g_i18n:getText("eq_sponsor_boardsLine"), boards.have, offer.signsFull or 1), boards.ok)
    local machines = byId.machines
    add("machines", string.format(g_i18n:getText("eq_sponsor_haveOf"), machines.have, machines.need), machines.ok)
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
    end
    return lines, row.contract and {} or clashes
end


--- @param offer table
--- @return string the target's rating line, such as "Intermediate or better, with a top 3 finish"
function EqSponsorView.targetRatingText(offer)
    local size = EqSponsorManager.config.sizeByName[offer.size]
    local lowest = size ~= nil and (size.lowerShare > 0 and size.lowerRating or size.minRating) or nil
    local text = string.format(g_i18n:getText("eq_sponsor_targetRating"), ratingTitle(lowest))
    if offer.top3 then text = text .. g_i18n:getText("eq_sponsor_targetTop3") end
    return text
end


--- The notes under the panel: the equipment to own, the competitor clause, and the rival
--- machines to sell or return first, one a line (James, 2026-10-31).
--- @param row table|nil
--- @param clashes table owned machines breaking the competitor clause
--- @param maxLines number how many note lines there are
--- @return table lines texts
function EqSponsorView.noteLines(row, clashes, maxLines)
    local lines = {}
    if row == nil then return lines end
    local offer = row.offer
    table.insert(lines, string.format(g_i18n:getText(row.contract and "eq_sponsor_mustKeep" or "eq_sponsor_mustOwn"), offer.machines or 1))
    table.insert(lines, string.format(g_i18n:getText("eq_sponsor_noRivals"), percent(offer.window)))
    if #clashes > 0 then
        table.insert(lines, g_i18n:getText("eq_sponsor_sellFirst"))
        local room = maxLines - #lines
        for i, machine in ipairs(clashes) do
            if i == room and #clashes > room then
                table.insert(lines, string.format(g_i18n:getText("eq_sponsor_sellMore"), #clashes - room + 1))
                break
            end
            table.insert(lines, string.format("%s (%s)", machine.name or "?", money(machine.price)))
        end
    end
    return lines
end


--- The sponsor's speciality: its shop categories with the most machines, biggest first.
--- @param brand string
--- @param count number how many
--- @return table titles
function EqSponsorView.speciality(brand, count)
    local shop = EqSponsorManager.readShop()
    local profile = shop ~= nil and shop.profiles[brand] or nil
    local list = {}
    for name, prices in pairs(profile ~= nil and profile.byCategory or {}) do table.insert(list, { name = name, count = #prices }) end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    local titles = {}
    for i = 1, math.min(count, #list) do
        local category = g_storeManager ~= nil and g_storeManager:getCategoryByName(list[i].name) or nil
        local title = category ~= nil and category.title ~= nil and category.title ~= "" and category.title or list[i].name
        table.insert(titles, string.format(g_i18n:getText("eq_sponsor_specialityLine"), title, list[i].count))
    end
    return titles
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

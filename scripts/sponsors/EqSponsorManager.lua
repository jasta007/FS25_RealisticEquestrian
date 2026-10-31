--[[
    EqSponsorManager.lua
    Sponsors for the events a farm hosts, on the server (James, 2026-10-29 and 2026-10-31): the
    game side of EqSponsorship's rules.

    - The shop is read once a session: every machine (store items of the vehicle and tool
      category types, shown in the shop, priced) by brand, so brands are sized from the player's
      own shop, mods and all. Lizard and the game's "no brand" are left out (data/sponsors.xml).
    - Offers come at the start of each year (the year's first month), like staff candidates:
      a few sponsors of each size, each with its own demands and rewards. They stay a few months.
      A farm the mod meets for the first time gets this year's offers at once.
    - A farm signs one offer at a time, from the Events page's Sponsors tab, once it meets its
      terms. The contract then runs its years: each hosted event at a rating the sponsor backs is
      named after it, gains its popularity, and pays its fee when the results come in, if the
      farm still owns enough of its machines and has sponsor boards on show.
    - Each contract year ends with its target checked; a miss cuts next year's fee, two in a row
      end the contract. Cancelling early costs a share of a fee for each year left.

    Discounts on the sponsor's machines and the shop's block on rival machines come next.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsorManager = {}

local Log = EqLog

EqSponsorManager.config = nil


function EqSponsorManager.reset()
    EqSponsorManager.offers = {}     -- farmId -> { madeMonth, year, list = offers }
    EqSponsorManager.contracts = {}  -- farmId -> contract (EqSponsorship.contractFrom)
    EqSponsorManager.seed = nil      -- the save's own seed, so two saves get different sponsors
    EqSponsorManager.shop = nil      -- the shop read this session: { items, byStoreItem, profiles, ranked }
end

EqSponsorManager.reset()


--- @param modDirectory string
function EqSponsorManager.loadConfig(modDirectory)
    EqSponsorManager.config = EqSponsorship.load(modDirectory .. "data/sponsors.xml")
end


--- @param farmId number
--- @param kind string EqMessages type
--- @param text string
--- @param level number|nil
local function tell(farmId, kind, text, level)
    if g_currentMission ~= nil and g_currentMission:getFarmId() == farmId then
        g_currentMission:addIngameNotification(level or FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
    EqMessages.post(farmId, kind, text)
end


--- @param amount number
--- @return string
local function money(amount)
    return g_i18n:formatMoney(amount or 0, 0, true, true)
end


-- THE SHOP

--- @param storeItem table
--- @param config table
--- @param why table reason -> count, for the log
--- @return table|nil categories the item's machine categories, nil when it is no machine
local function machineCategories(storeItem, config, why)
    local function reject(reason)
        why[reason] = (why[reason] or 0) + 1
        return nil
    end
    if storeItem == nil then return reject("nil") end
    if storeItem.isBundleItem then return reject("bundle") end
    if storeItem.showInStore == false then return reject("hidden") end
    if (tonumber(storeItem.price) or 0) <= 0 then return reject("noPrice") end
    -- Placeables and hand tools are no machines; anything else (vehicles) is.
    if StoreSpecies ~= nil and storeItem.species ~= nil
        and ((StoreSpecies.PLACEABLE ~= nil and storeItem.species == StoreSpecies.PLACEABLE)
        or (StoreSpecies.HANDTOOL ~= nil and storeItem.species == StoreSpecies.HANDTOOL)) then
        return reject("species")
    end
    local categories = {}
    local names = storeItem.categoryNames
    if type(names) ~= "table" or #names == 0 then names = { storeItem.categoryName } end
    for _, name in ipairs(names) do
        local category = name ~= nil and g_storeManager:getCategoryByName(name) or nil
        local kind = category ~= nil and category.type ~= nil and string.upper(tostring(category.type)) or nil
        if kind ~= nil then
            why.types = why.types or {}
            why.types[kind] = (why.types[kind] or 0) + 1
        end
        if kind ~= nil and not config.skipCategoryTypes[kind] then table.insert(categories, category.name or name) end
    end
    if #categories == 0 then return reject("category") end
    return categories
end


--- @param why table from machineCategories
--- @return string the reasons items were left out, for the log
local function whyText(why)
    local parts = {}
    for reason, count in pairs(why) do
        if reason ~= "types" then table.insert(parts, string.format("%s %d", reason, count)) end
    end
    local types = {}
    for kind, count in pairs(why.types or {}) do table.insert(types, string.format("%s %d", kind, count)) end
    table.sort(parts)
    table.sort(types)
    return string.format("left out: %s; category types: %s", table.concat(parts, ", "), table.concat(types, ", "))
end


--- The shop's machines by brand, read once a session (again later while it comes up empty).
--- @return table|nil shop { items, byStoreItem, profiles, ranked }
function EqSponsorManager.readShop()
    local config = EqSponsorManager.config
    if EqSponsorManager.shop ~= nil or config == nil then return EqSponsorManager.shop end
    if g_storeManager == nil or g_brandManager == nil then return nil end
    local all = g_storeManager.getItems ~= nil and g_storeManager:getItems() or g_storeManager.items or {}
    local items, byStoreItem, why, noBrand = {}, {}, {}, 0
    for _, storeItem in ipairs(all) do
        local categories = machineCategories(storeItem, config, why)
        local brand = categories ~= nil and storeItem.brandIndex ~= nil and g_brandManager:getBrandByIndex(storeItem.brandIndex) or nil
        if brand ~= nil and brand.name ~= nil then
            local item = { brand = brand.name, categories = categories, price = storeItem.price, name = storeItem.name }
            table.insert(items, item)
            byStoreItem[storeItem] = item
        elseif categories ~= nil then
            noBrand = noBrand + 1
        end
    end
    local profiles = EqSponsorship.profiles(config, items)
    local ranked = EqSponsorship.rank(config, profiles)
    local shop = { items = items, byStoreItem = byStoreItem, profiles = profiles, ranked = ranked }
    Log:info("EqSponsorManager: %d machines from %d brands in the shop (%d store items, %d without a brand; %s)",
        #items, #ranked, #all, noBrand, whyText(why))
    -- An empty shop is read again next time: the store may not be loaded yet.
    if #ranked > 0 then EqSponsorManager.shop = shop end
    return shop
end


--- @param name string a brand name
--- @return table|nil brand from the brand manager
function EqSponsorManager.brand(name)
    if g_brandManager == nil or name == nil then return nil end
    if g_brandManager.getBrandByName ~= nil then return g_brandManager:getBrandByName(name) end
    return g_brandManager.nameToBrand ~= nil and g_brandManager.nameToBrand[name] or nil
end


--- @param name string a brand name
--- @return string title the brand as the shop shows it
function EqSponsorManager.brandTitle(name)
    local brand = EqSponsorManager.brand(name)
    return brand ~= nil and brand.title ~= nil and brand.title ~= "" and brand.title or tostring(name)
end


--- @param vehicle table
--- @return boolean true for a machine borrowed for a contract (they don't count, James 2026-10-29)
local function isBorrowed(vehicle)
    local state = vehicle.propertyState
    if vehicle.getPropertyState ~= nil then state = vehicle:getPropertyState() end
    if VehiclePropertyState ~= nil and VehiclePropertyState.MISSION ~= nil and state == VehiclePropertyState.MISSION then return true end
    if Vehicle ~= nil and Vehicle.PROPERTY_STATE_MISSION ~= nil and state == Vehicle.PROPERTY_STATE_MISSION then return true end
    return false
end


--- The farm's machines, owned or leased.
--- @param farmId number
--- @return table list of { brand, categories, price, name }
function EqSponsorManager.ownedMachines(farmId)
    local shop = EqSponsorManager.readShop()
    local owned = {}
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    if shop == nil or system == nil then return owned end
    for _, vehicle in ipairs(system.vehicles or {}) do
        if vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farmId and vehicle.configFileName ~= nil and not isBorrowed(vehicle) then
            local item = shop.byStoreItem[g_storeManager:getItemByXMLFilename(vehicle.configFileName) or false]
            if item ~= nil then
                local name = vehicle.getName ~= nil and vehicle:getName() or item.name
                table.insert(owned, { brand = item.brand, categories = item.categories, price = item.price, name = name or item.name })
            end
        end
    end
    return owned
end


--- @param farmId number
--- @return number boards the farm's sponsor boards
function EqSponsorManager.boards(farmId)
    return EqSponsors ~= nil and EqSponsors.countBoards ~= nil and EqSponsors.countBoards(farmId) or 0
end


-- OFFERS

--- @return number year the game's year
function EqSponsorManager.year()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment ~= nil and environment.currentYear ~= nil then return environment.currentYear end
    return math.floor((EqCompetitionManager.month or 0) / 12)
end


--- @return number seed the save's seed, drawn the first time it is needed
local function saveSeed()
    if EqSponsorManager.seed == nil then EqSponsorManager.seed = math.random(1, 999999999) end
    return EqSponsorManager.seed
end


--- Make a farm's offers for this year.
--- @param farmId number
--- @return table record { madeMonth, year, list }
function EqSponsorManager.makeOffers(farmId)
    local shop = EqSponsorManager.readShop()
    local config = EqSponsorManager.config
    local year = EqSponsorManager.year()
    local list = {}
    if shop ~= nil and config ~= nil then
        list = EqSponsorship.makeOffers(config, shop.ranked, string.format("sponsors %d %d %d", saveSeed(), farmId, year))
    end
    local record = { madeMonth = EqCompetitionManager.month or 0, year = year, list = list }
    EqSponsorManager.offers[farmId] = record
    Log:info("EqSponsorManager: farm %d has %d sponsor offers for year %d", farmId, #list, year)
    return record
end


--- @param farmId number
--- @return table record the farm's offers, made the first time they are asked for
function EqSponsorManager.offersFor(farmId)
    local record = EqSponsorManager.offers[farmId]
    -- None at all this year means the shop was read before it was ready (James's log,
    -- 2026-10-31: 0 machines): try again, keeping when they first came.
    if record ~= nil and #record.list == 0 and record.year == EqSponsorManager.year()
        and EqSponsorManager.shop == nil and not record.retried then
        local madeMonth = record.madeMonth
        record = EqSponsorManager.makeOffers(farmId)
        record.madeMonth = madeMonth
        if #record.list == 0 then record.retried = true end
    end
    return record or EqSponsorManager.makeOffers(farmId)
end


--- @param farmId number
--- @return boolean the farm's offers are still open
function EqSponsorManager.offersOpen(farmId)
    local record = EqSponsorManager.offersFor(farmId)
    local config = EqSponsorManager.config
    return config ~= nil and (EqCompetitionManager.month or 0) < record.madeMonth + config.offerMonths
end


--- @param farmId number
--- @return table offers the open offers, empty once they have gone
function EqSponsorManager.openOffers(farmId)
    if not EqSponsorManager.offersOpen(farmId) then return {} end
    return EqSponsorManager.offersFor(farmId).list
end


--- @return table ratingOrder rating name -> index, from data/hosting.xml
function EqSponsorManager.ratingOrder()
    local order = {}
    local config = EqHostVenue ~= nil and EqHostVenue.config or nil
    for i, rating in ipairs(config ~= nil and config.ratings or {}) do order[rating.name] = i end
    return order
end


--- Everything the Sponsors tab shows about one offer for one farm.
--- @param farmId number
--- @param offer table
--- @return table checks from EqSponsorship.signChecks (with .ok)
--- @return table clashes
function EqSponsorManager.checksFor(farmId, offer)
    local shop = EqSponsorManager.readShop()
    local state = { owned = EqSponsorManager.ownedMachines(farmId), profile = shop ~= nil and shop.profiles[offer.brand] or nil,
        boards = EqSponsorManager.boards(farmId), contract = EqSponsorManager.contracts[farmId] }
    return EqSponsorship.signChecks(EqSponsorManager.config, offer, state)
end


--- Sign one of the farm's offers.
--- @param farmId number
--- @param offer table one of the farm's open offers
--- @return boolean ok
--- @return string text for the player
function EqSponsorManager.sign(farmId, offer)
    local config = EqSponsorManager.config
    if config == nil then return false, g_i18n:getText("eq_sponsor_noConfig") end
    local open = EqSponsorManager.openOffers(farmId)
    local index = nil
    for i, candidate in ipairs(open) do
        if candidate == offer then index = i end
    end
    if index == nil then return false, g_i18n:getText("eq_sponsor_sign_gone") end
    local checks = EqSponsorManager.checksFor(farmId, offer)
    if not checks.ok then return false, g_i18n:getText("eq_sponsor_sign_notReady") end
    local contract = EqSponsorship.contractFrom(offer, EqCompetitionManager.month or 0)
    EqSponsorManager.contracts[farmId] = contract
    table.remove(open, index)
    if EqSponsors ~= nil and EqSponsors.refresh ~= nil then EqSponsors.refresh() end
    local title = EqSponsorManager.brandTitle(offer.brand)
    Log:info("EqSponsorManager: farm %d signed with %s for %d year(s), fee %d", farmId, offer.brand, offer.years, offer.fee)
    local text = string.format(g_i18n:getText("eq_sponsor_signed"), title, offer.years)
    tell(farmId, "EQ_SPONSOR_SIGNED", text)
    return true, text
end


--- @param farmId number
--- @return number cost what cancelling the farm's contract costs now
--- @return number yearsLeft
function EqSponsorManager.cancelCost(farmId)
    local contract = EqSponsorManager.contracts[farmId]
    if contract == nil or EqSponsorManager.config == nil then return 0, 0 end
    return EqSponsorship.cancelCost(EqSponsorManager.config, contract, EqCompetitionManager.month or 0)
end


--- Cancel the farm's contract early.
--- @param farmId number
--- @return boolean ok
--- @return string text
function EqSponsorManager.cancel(farmId)
    local contract = EqSponsorManager.contracts[farmId]
    if contract == nil then return false, g_i18n:getText("eq_sponsor_cancel_none") end
    local cost = EqSponsorManager.cancelCost(farmId)
    if cost > 0 then g_currentMission:addMoney(-cost, farmId, MoneyType.EQ_SPONSORSHIP or MoneyType.OTHER, true, true) end
    EqSponsorManager.contracts[farmId] = nil
    if EqSponsors ~= nil and EqSponsors.refresh ~= nil then EqSponsors.refresh() end
    Log:info("EqSponsorManager: farm %d cancelled its contract with %s (cost %d)", farmId, contract.brand, cost)
    local text = string.format(g_i18n:getText("eq_sponsor_cancelled"), EqSponsorManager.brandTitle(contract.brand), money(cost))
    tell(farmId, "EQ_SPONSOR_ENDED", text)
    return true, text
end


-- HOSTED EVENTS

--- The popularity a farm's sponsor brings to an event at this rating, 0 when it doesn't back it.
--- @param farmId number
--- @param ratingName string
--- @return number points
function EqSponsorManager.popularityFor(farmId, ratingName)
    local contract = EqSponsorManager.contracts[farmId]
    local config = EqSponsorManager.config
    if contract == nil or config == nil then return 0 end
    if EqSponsorship.feeShare(config, contract, ratingName, EqSponsorManager.ratingOrder()) <= 0 then return 0 end
    return contract.popularity or 0
end


--- A hosted event has opened: if the farm's sponsor backs its rating, it carries the sponsor's
--- name and popularity.
--- @param event table
function EqSponsorManager.onEventOpened(event)
    local hosted = event.hosted
    local contract = EqSponsorManager.contracts[hosted.farmId]
    if contract == nil or EqSponsorManager.popularityFor(hosted.farmId, hosted.rating) <= 0 then return end
    hosted.sponsor = EqSponsorManager.brandTitle(contract.brand)
    hosted.sponsorBrand = contract.brand
    hosted.sponsorPopularity = contract.popularity
end


--- @param farmId number
--- @param contract table
--- @return boolean the farm still owns enough of the sponsor's machines
local function machinesOk(farmId, contract)
    return EqSponsorship.ownedOf(contract.brand, EqSponsorManager.ownedMachines(farmId)) >= (contract.machines or 1)
end


--- A hosted event's results are in: the sponsor pays, and the yearly target is checked.
--- @param event table
--- @param report table EqHostManager.report, filled in with the sponsor's fee
--- @return number fee paid
function EqSponsorManager.afterEvent(event, report)
    local hosted = event.hosted
    local farmId = hosted.farmId
    local contract = EqSponsorManager.contracts[farmId]
    local config = EqSponsorManager.config
    if contract == nil or config == nil or hosted.sponsorBrand ~= contract.brand then return 0 end
    local order = EqSponsorManager.ratingOrder()
    local title = EqSponsorManager.brandTitle(contract.brand)
    local fee, why = EqSponsorship.eventFee(config, contract, hosted.rating, order, EqSponsorManager.boards(farmId),
        machinesOk(farmId, contract))
    if fee > 0 then
        g_currentMission:addMoney(fee, farmId, MoneyType.EQ_SPONSORSHIP or MoneyType.OTHER, true, true)
        contract.paid = (contract.paid or 0) + fee
        tell(farmId, "EQ_SPONSOR_PAID", string.format(g_i18n:getText("eq_sponsor_paid"), title, money(fee), EqCompetitionManager.eventTitle(event)))
    elseif why ~= nil and why ~= "rating" then
        tell(farmId, "EQ_SPONSOR_WARNING", string.format(g_i18n:getText("eq_sponsor_unpaid_" .. why), title,
            EqCompetitionManager.eventTitle(event)), FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
    end
    report.sponsor = title
    report.sponsorFee = fee

    local best = nil
    for _, horse in ipairs(report.mine or {}) do
        if horse.status == nil and (horse.place or 0) > 0 and (best == nil or horse.place < best) then best = horse.place end
    end
    if not contract.met and EqSponsorship.meetsTarget(config, contract, hosted.rating, order, hosted.popularity, best) then
        contract.met = true
        tell(farmId, "EQ_SPONSOR_PAID", string.format(g_i18n:getText("eq_sponsor_targetMet"), title))
    end
    return fee
end


-- THE CALENDAR

--- A new month: contract years close, contracts end, and a new year brings new offers.
--- @param month number the month that has just started
function EqSponsorManager.onMonthStarted(month)
    local config = EqSponsorManager.config
    if config == nil then return end
    local farmIds = {}
    for farmId in pairs(EqSponsorManager.contracts) do table.insert(farmIds, farmId) end
    table.sort(farmIds)
    for _, farmId in ipairs(farmIds) do
        local contract = EqSponsorManager.contracts[farmId]
        local title = EqSponsorManager.brandTitle(contract.brand)
        local ended = false
        if month >= (contract.yearEnd or month + 1) then
            local met = contract.met
            local leaves = EqSponsorship.closeYear(config, contract)
            contract.yearEnd = contract.yearEnd + 12
            if leaves then
                ended = true
                tell(farmId, "EQ_SPONSOR_ENDED", string.format(g_i18n:getText("eq_sponsor_leaves"), title), FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
            elseif not met and month < contract.endMonth then
                tell(farmId, "EQ_SPONSOR_WARNING", string.format(g_i18n:getText("eq_sponsor_missed"), title,
                    math.floor((contract.feeFactor or 1) * 100 + 0.5)), FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
            end
        end
        if not ended and month >= contract.endMonth then
            ended = true
            tell(farmId, "EQ_SPONSOR_ENDED", string.format(g_i18n:getText("eq_sponsor_finished"), title, money(contract.paid)))
        end
        if ended then
            EqSponsorManager.contracts[farmId] = nil
            Log:info("EqSponsorManager: farm %d's contract with %s has ended", farmId, contract.brand)
            if EqSponsors ~= nil and EqSponsors.refresh ~= nil then EqSponsors.refresh() end
        end
    end

    -- The year's first month: new offers for every farm.
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment ~= nil and environment.currentPeriod == 1 then
        for _, farm in pairs(g_farmManager:getFarms()) do
            local farmId = farm.farmId
            if farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID then
                local record = EqSponsorManager.makeOffers(farmId)
                if #record.list > 0 then
                    tell(farmId, "EQ_SPONSOR_OFFERS", string.format(g_i18n:getText("eq_sponsor_newOffers"), #record.list))
                end
            end
        end
    end
end


-- SAVE AND LOAD (inside rlEquestrian.xml)

--- @param xmlFile table
--- @param key string such as "rlEquestrian.sponsors"
function EqSponsorManager.saveToXMLFile(xmlFile, key)
    if EqSponsorManager.seed ~= nil then xmlFile:setInt(key .. "#seed", EqSponsorManager.seed) end
    local farmIds, seen = {}, {}
    for _, list in ipairs({ EqSponsorManager.offers, EqSponsorManager.contracts }) do
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
        local record = EqSponsorManager.offers[farmId]
        if record ~= nil then
            xmlFile:setInt(farmKey .. ".offers#madeMonth", record.madeMonth or 0)
            xmlFile:setInt(farmKey .. ".offers#year", record.year or 0)
            for o, offer in ipairs(record.list) do
                EqSponsorship.saveOffer(xmlFile, string.format("%s.offers.offer(%d)", farmKey, o - 1), offer)
            end
        end
        local contract = EqSponsorManager.contracts[farmId]
        if contract ~= nil then EqSponsorship.saveOffer(xmlFile, farmKey .. ".contract", contract) end
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqSponsorManager.loadFromXMLFile(xmlFile, key)
    local shop = EqSponsorManager.shop
    EqSponsorManager.reset()
    EqSponsorManager.shop = shop
    if xmlFile == nil then return end
    EqSponsorManager.seed = xmlFile:getInt(key .. "#seed")
    local i = 0
    while true do
        local farmKey = string.format("%s.farm(%d)", key, i)
        if not xmlFile:hasProperty(farmKey) then break end
        local farmId = xmlFile:getInt(farmKey .. "#farmId")
        if farmId ~= nil then
            if xmlFile:hasProperty(farmKey .. ".offers") then
                local record = { madeMonth = xmlFile:getInt(farmKey .. ".offers#madeMonth", 0),
                    year = xmlFile:getInt(farmKey .. ".offers#year", 0), list = {} }
                local o = 0
                while xmlFile:hasProperty(string.format("%s.offers.offer(%d)", farmKey, o)) do
                    local offer = EqSponsorship.loadOffer(xmlFile, string.format("%s.offers.offer(%d)", farmKey, o))
                    if offer ~= nil then table.insert(record.list, EqSponsorship.tidy(EqSponsorManager.config, offer)) end
                    o = o + 1
                end
                EqSponsorManager.offers[farmId] = record
            end
            if xmlFile:hasProperty(farmKey .. ".contract") then
                local contract = EqSponsorship.loadOffer(xmlFile, farmKey .. ".contract")
                EqSponsorManager.contracts[farmId] = contract ~= nil and EqSponsorship.tidy(EqSponsorManager.config, contract) or nil
            end
        end
        i = i + 1
    end
end

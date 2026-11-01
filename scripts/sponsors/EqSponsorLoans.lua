--[[
    EqSponsorLoans.lua
    Sponsors lend the farm a machine for its event month (James, 2026-11-01), on the server.

    - Some sponsors' offers say they lend one (EqSponsorship.rollLoan); Lizard's one-off
      sponsorship always does (data/sponsors.xml, loans.always).
    - On the first day of a hosted event's month each sponsor backing it that lends delivers one
      of its machines to the dealer: one of its dearest, something that drives itself when it
      makes any. A popup says what came and where it is.
    - The machine is leased to the farm, so it shows and works like any leased machine and can
      be returned early, but it is free: its price is set to 0, so there is no leasing cost (daily
      or per hour) and repairs cost nothing. The farm can use it for anything, plinths included.
      It doesn't count toward a sponsor's machines or its competitor clause.
    - When the month ends (or the event is cancelled) the sponsor takes it back.
    - If the dealer's yard is full the delivery is tried again each day of the month.

    Spawned the way the game spawns contract machines (AbstractMission:spawnVehicle), with a
    leased property state instead of a mission one.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsorLoans = {}

local Log = EqLog

EqSponsorLoans.STATE_PENDING = "pending"   -- waiting for room at the dealer
EqSponsorLoans.STATE_LENT = "lent"


function EqSponsorLoans.reset()
    -- list of { farmId, brand, month, state, ids = vehicle uniqueIds, item = store xml, name, told }
    EqSponsorLoans.loans = {}
    EqSponsorLoans.loading = 0
end

EqSponsorLoans.reset()


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


--- @return boolean true on the server (or in single player)
local function isServer()
    return g_currentMission ~= nil and (g_currentMission.getIsServer == nil or g_currentMission:getIsServer())
end


--- @param uniqueId string|nil
--- @return table|nil vehicle
local function vehicleById(uniqueId)
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    if system == nil or uniqueId == nil or system.getVehicleByUniqueId == nil then return nil end
    return system:getVehicleByUniqueId(uniqueId)
end


--- @param vehicle table|nil
--- @return table|nil loan the loan the vehicle belongs to
function EqSponsorLoans.loanOf(vehicle)
    local uniqueId = vehicle ~= nil and vehicle.uniqueId or nil
    if uniqueId == nil then return nil end
    for _, loan in ipairs(EqSponsorLoans.loans) do
        for _, id in ipairs(loan.ids or {}) do
            if id == uniqueId then return loan end
        end
    end
    return nil
end


--- @param vehicle table|nil
--- @return boolean true for a machine a sponsor has lent the farm
function EqSponsorLoans.isLoan(vehicle)
    return EqSponsorLoans.loanOf(vehicle) ~= nil
end


--- @param farmId number
--- @return table loans the farm's loans
function EqSponsorLoans.loansFor(farmId)
    local list = {}
    for _, loan in ipairs(EqSponsorLoans.loans) do
        if loan.farmId == farmId then table.insert(list, loan) end
    end
    return list
end


-- WHAT IS LENT

--- @param storeItem table
--- @return boolean true when the item is in a shop group of self-driven machines
local function isDrivable(storeItem)
    local names = storeItem.categoryNames
    if type(names) ~= "table" or #names == 0 then names = { storeItem.categoryName } end
    for _, name in ipairs(names) do
        local category = name ~= nil and g_storeManager:getCategoryByName(name) or nil
        if category ~= nil and category.type ~= nil and string.upper(tostring(category.type)) == "DRIVABLES" then return true end
    end
    return false
end


--- The brand's machines a sponsor could lend.
--- @param brand string
--- @return table candidates list of { storeItem, price, drivable, key, name }
function EqSponsorLoans.candidates(brand)
    local list = {}
    local shop = EqSponsorManager.readShop()
    if shop == nil or brand == nil then return list end
    for storeItem, item in pairs(shop.byStoreItem) do
        if item.brand ~= nil and string.upper(item.brand) == string.upper(brand) and storeItem.xmlFilename ~= nil then
            table.insert(list, { storeItem = storeItem, price = item.price or 0, drivable = isDrivable(storeItem),
                key = storeItem.xmlFilename, name = item.name })
        end
    end
    return list
end


--- @param storeItem table
--- @return table|nil configurations the default ones, with one of the item's sets picked at random
local function configurationsFor(storeItem)
    local result = nil
    if storeItem.defaultConfigurationIds ~= nil then
        result = {}
        for name, id in pairs(storeItem.defaultConfigurationIds) do result[name] = id end
    end
    local sets = storeItem.configurationSets
    if type(sets) == "table" and #sets > 0 then
        result = result or {}
        local set = sets[math.random(1, #sets)]
        for name, id in pairs(set.configurations or set) do
            if type(id) == "number" then result[name] = id end
        end
    end
    return result
end


-- DELIVERY

--- The sponsors that lend for a hosted event: those backing it whose contract says so, and
--- Lizard's one-off sponsorship.
--- @param event table a hosted event
--- @return table brands
function EqSponsorLoans.lendersFor(event)
    local hosted = event.hosted
    local config = EqSponsorManager.config
    local brands, seen = {}, {}
    local function add(brand)
        if brand ~= nil and not seen[string.upper(brand)] then
            seen[string.upper(brand)] = true
            table.insert(brands, brand)
        end
    end
    for _, brand in ipairs(EqSponsorManager.eventBrands(hosted)) do
        if EqSponsorship.lends(config, brand, EqSponsorManager.contractOf(hosted.farmId, brand)) then add(brand) end
    end
    if hosted.lizard then add("LIZARD") end
    return brands
end


--- Bring a loan's machine to the dealer, or try again tomorrow when there is no room.
--- @param loan table
function EqSponsorLoans.spawn(loan)
    if VehicleLoadingData == nil or g_storeManager == nil then return end
    local storeItem = g_storeManager:getItemByXMLFilename(loan.item)
    if storeItem == nil then
        Log:warning("EqSponsorLoans: %s's machine %s is no longer in the shop", tostring(loan.brand), tostring(loan.item))
        return
    end
    local data = VehicleLoadingData.new()
    data:setStoreItem(storeItem)
    local configurations = configurationsFor(storeItem)
    if configurations ~= nil and data.setConfigurations ~= nil then data:setConfigurations(configurations) end
    data:setLoadingPlace(g_currentMission.storeSpawnPlaces, g_currentMission.usedStorePlaces)
    data:setPropertyState(VehiclePropertyState.LEASED)
    data:setOwnerFarmId(loan.farmId)
    loan.loading = true
    EqSponsorLoans.loading = EqSponsorLoans.loading + 1
    data:load(EqSponsorLoans.onLoaded, EqSponsorLoans, loan)
end


--- @param vehicles table
--- @param loadingState number VehicleLoadingState
--- @param loan table
function EqSponsorLoans:onLoaded(vehicles, loadingState, loan)
    loan.loading = nil
    EqSponsorLoans.loading = math.max(0, EqSponsorLoans.loading - 1)
    local still = false
    for _, entry in ipairs(EqSponsorLoans.loans) do
        if entry == loan then still = true end
    end
    -- Collected (the month ended or the event was cancelled) while it was on its way.
    if not still or loadingState ~= VehicleLoadingState.OK then
        for _, vehicle in ipairs(vehicles or {}) do vehicle:delete() end
        if still then
            Log:info("EqSponsorLoans: no room at the dealer for %s's %s (state %s), trying again tomorrow",
                loan.brand, loan.name or "?", tostring(loadingState))
            if not loan.toldNoRoom then
                loan.toldNoRoom = true
                tell(loan.farmId, "EQ_SPONSOR_WARNING", string.format(g_i18n:getText("eq_loan_noRoom"),
                    EqSponsorManager.brandTitle(loan.brand), loan.name or "?"), FSBaseMission.INGAME_NOTIFICATION_CRITICAL)
            end
        end
        return
    end
    loan.ids = {}
    for _, vehicle in ipairs(vehicles) do
        -- Free: no leasing costs and free repairs, all worked out from the price (saved with it).
        vehicle.price = 0
        if vehicle.uniqueId ~= nil then table.insert(loan.ids, vehicle.uniqueId) end
    end
    loan.state = EqSponsorLoans.STATE_LENT
    Log:info("EqSponsorLoans: %s lent farm %d a %s (%s) for month %d", loan.brand, loan.farmId, loan.name or "?",
        tostring(loan.item), loan.month)
    EqSponsorLoans.announce(loan)
end


--- Popup and message: what has come, and that it waits at the dealer.
--- @param loan table
function EqSponsorLoans.announce(loan)
    local brand = EqSponsorManager.brandTitle(loan.brand)
    local text = string.format(g_i18n:getText("eq_loan_popup"), brand, loan.name or "?")
    tell(loan.farmId, "EQ_SPONSOR_LOAN", string.format(g_i18n:getText("eq_loan_delivered"), brand, loan.name or "?"))
    if g_currentMission == nil or g_currentMission:getFarmId() ~= loan.farmId or EqTrainingHud == nil then return end
    local page = { title = g_i18n:getText("eq_loan_popupTitle"), text = text }
    -- After any popup already showing (or another sponsor's loan), never instead of it.
    if EqTrainingHud.isHelpShowing() and EqTrainingHud.place == nil then
        table.insert(EqTrainingHud.pages, page)
    else
        EqTrainingHud.showHelp({ page }, nil, nil)
    end
end


--- A sponsor lends a farm a machine for this month.
--- @param farmId number
--- @param brand string
--- @param month number
--- @return table|nil loan nil when the brand has nothing to lend
function EqSponsorLoans.lend(farmId, brand, month)
    for _, loan in ipairs(EqSponsorLoans.loans) do
        if loan.farmId == farmId and loan.brand == brand and loan.month == month then return loan end
    end
    local pick = EqSponsorship.pickLoan(EqSponsorLoans.candidates(brand), math.random(),
        EqSponsorManager.config ~= nil and EqSponsorManager.config.loanTop or nil)
    if pick == nil then
        Log:info("EqSponsorLoans: %s has no machine in the shop to lend", tostring(brand))
        return nil
    end
    local loan = { farmId = farmId, brand = brand, month = month, state = EqSponsorLoans.STATE_PENDING, ids = {},
        item = pick.storeItem.xmlFilename, name = pick.storeItem.name or pick.name }
    table.insert(EqSponsorLoans.loans, loan)
    EqSponsorLoans.spawn(loan)
    return loan
end


--- Deliver the loans for the farm's hosted event that has just opened.
--- @param event table
--- @param month number
function EqSponsorLoans.deliverFor(event, month)
    for _, brand in ipairs(EqSponsorLoans.lendersFor(event)) do
        EqLog.try("EqSponsorLoans.lend", EqSponsorLoans.lend, event.hosted.farmId, brand, month)
    end
end


-- TAKING THEM BACK

--- The sponsor takes its machine back.
--- @param loan table
--- @param quiet boolean|nil no message (the machine was already gone)
function EqSponsorLoans.collect(loan, quiet)
    for i = #EqSponsorLoans.loans, 1, -1 do
        if EqSponsorLoans.loans[i] == loan then table.remove(EqSponsorLoans.loans, i) end
    end
    local found = false
    for _, id in ipairs(loan.ids or {}) do
        local vehicle = vehicleById(id)
        if vehicle ~= nil and not (vehicle.getIsBeingDeleted ~= nil and vehicle:getIsBeingDeleted()) then
            found = true
            -- Whatever the farm loaded into it goes first, as when a contract ends. Only a vehicle
            -- with an <unloading> block can (the game checks the same).
            local spec = vehicle.spec_fillUnit
            if vehicle.unloadFillUnits ~= nil and spec ~= nil and spec.unloading ~= nil then
                EqLog.try("EqSponsorLoans unload", vehicle.unloadFillUnits, vehicle, true)
            end
            vehicle:delete()
        end
    end
    Log:info("EqSponsorLoans: %s took back its %s from farm %d (%s)", loan.brand, loan.name or "?", loan.farmId,
        found and "collected" or "already gone")
    if found and not quiet then
        tell(loan.farmId, "EQ_SPONSOR_LOAN", string.format(g_i18n:getText("eq_loan_collected"),
            EqSponsorManager.brandTitle(loan.brand), loan.name or "?"))
    end
end


--- @param farmId number
function EqSponsorLoans.collectFor(farmId)
    for _, loan in ipairs(EqSponsorLoans.loansFor(farmId)) do EqSponsorLoans.collect(loan) end
end


-- THE CALENDAR

--- A new month (after the ended month's results and the new month's events opened): last
--- month's loans go back and the new month's hosted events get theirs.
--- @param month number
function EqSponsorLoans.onMonthStarted(month)
    if not isServer() then return end
    local old = {}
    for _, loan in ipairs(EqSponsorLoans.loans) do
        if loan.month < month then table.insert(old, loan) end
    end
    for _, loan in ipairs(old) do EqSponsorLoans.collect(loan) end
    local events = {}
    for _, event in pairs(EqCompetitionManager.events) do
        if event.hosted ~= nil then table.insert(events, event) end
    end
    table.sort(events, function(a, b) return a.id < b.id end)
    for _, event in ipairs(events) do EqSponsorLoans.deliverFor(event, month) end
end


--- A new day: deliveries that found no room try again.
function EqSponsorLoans.onDayChanged()
    if not isServer() then return end
    for _, loan in ipairs(EqSponsorLoans.loans) do
        if loan.state == EqSponsorLoans.STATE_PENDING and not loan.loading then EqSponsorLoans.spawn(loan) end
    end
end


--- A hosted event was cancelled: its loans go back now.
--- @param event table
function EqSponsorLoans.onEventCancelled(event)
    if not isServer() or event == nil or event.hosted == nil then return end
    EqSponsorLoans.collectFor(event.hosted.farmId)
end


--- The game swaps a reset vehicle for a new one: the loan follows it.
--- @param oldVehicle table
--- @param newVehicle table
function EqSponsorLoans:onVehicleReset(oldVehicle, newVehicle)
    local loan = EqSponsorLoans.loanOf(oldVehicle)
    if loan == nil or newVehicle == nil then return end
    for i, id in ipairs(loan.ids) do
        if id == oldVehicle.uniqueId then loan.ids[i] = newVehicle.uniqueId end
    end
    newVehicle.price = 0
end


--- Follow reset vehicles. Subscribed when a game loads (the mission's message center).
function EqSponsorLoans.subscribe()
    if g_messageCenter == nil or MessageType == nil or MessageType.VEHICLE_RESET == nil then return end
    g_messageCenter:unsubscribeAll(EqSponsorLoans)
    g_messageCenter:subscribe(MessageType.VEHICLE_RESET, function(_, oldVehicle, newVehicle)
        EqLog.try("EqSponsorLoans.onVehicleReset", EqSponsorLoans.onVehicleReset, EqSponsorLoans, oldVehicle, newVehicle)
    end, EqSponsorLoans)
end


-- SAVE AND LOAD (inside rlEquestrian.xml)

--- @param xmlFile table
--- @param key string such as "rlEquestrian.sponsorLoans"
function EqSponsorLoans.saveToXMLFile(xmlFile, key)
    for i, loan in ipairs(EqSponsorLoans.loans) do
        local loanKey = string.format("%s.loan(%d)", key, i - 1)
        xmlFile:setInt(loanKey .. "#farmId", loan.farmId)
        xmlFile:setString(loanKey .. "#brand", loan.brand)
        xmlFile:setInt(loanKey .. "#month", loan.month)
        xmlFile:setString(loanKey .. "#state", loan.state)
        if loan.item ~= nil then xmlFile:setString(loanKey .. "#item", loan.item) end
        if loan.name ~= nil then xmlFile:setString(loanKey .. "#name", loan.name) end
        if loan.toldNoRoom then xmlFile:setBool(loanKey .. "#toldNoRoom", true) end
        for v, id in ipairs(loan.ids or {}) do
            xmlFile:setString(string.format("%s.vehicle(%d)#uniqueId", loanKey, v - 1), id)
        end
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqSponsorLoans.loadFromXMLFile(xmlFile, key)
    EqSponsorLoans.reset()
    EqLog.try("EqSponsorLoans.subscribe", EqSponsorLoans.subscribe)
    if xmlFile == nil then return end
    local i = 0
    while true do
        local loanKey = string.format("%s.loan(%d)", key, i)
        if not xmlFile:hasProperty(loanKey) then break end
        local loan = { farmId = xmlFile:getInt(loanKey .. "#farmId"), brand = xmlFile:getString(loanKey .. "#brand"),
            month = xmlFile:getInt(loanKey .. "#month", 0), state = xmlFile:getString(loanKey .. "#state", EqSponsorLoans.STATE_LENT),
            item = xmlFile:getString(loanKey .. "#item"), name = xmlFile:getString(loanKey .. "#name"),
            toldNoRoom = xmlFile:getBool(loanKey .. "#toldNoRoom", false), ids = {} }
        local v = 0
        while true do
            local id = xmlFile:getString(string.format("%s.vehicle(%d)#uniqueId", loanKey, v))
            if id == nil then break end
            table.insert(loan.ids, id)
            v = v + 1
        end
        if loan.farmId ~= nil and loan.brand ~= nil then table.insert(EqSponsorLoans.loans, loan) end
        i = i + 1
    end
end

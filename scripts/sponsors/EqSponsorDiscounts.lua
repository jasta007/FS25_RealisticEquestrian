--[[
    EqSponsorDiscounts: a sponsor's discounts on its own machines, from the contract's third month
    (James, 2026-11-01: a sponsor must back you for 3 months before discounts start).

    - Buying (and leasing) a sponsor's machine in the shop: the contract's purchase discount
      (EconomyManager.getBuyPrice; BuyVehicleData.updatePrice tells it which farm is buying).
    - Repairing one: the repair discount, on the game's repair (getRepairPrice) and on the
      Advanced Damage System mod's services (getServicePrice: inspection, maintenance, repair,
      overhaul), so the discount works with it as well.
    - Repainting one: the repaint discount (getRepaintPrice).

    Repair and repaint prices are wrapped on each vehicle (both the game and ADS call them on
    the vehicle), checked every few seconds for new vehicles.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsorDiscounts = {}

EqSponsorDiscounts.SCAN_MS = 3000
EqSponsorDiscounts.WRAPS = {
    getRepairPrice = "repair",
    getServicePrice = "repair",    -- Advanced Damage System
    getRepaintPrice = "repaint",
}


--- @param storeItem table|nil
--- @return string|nil brand name
function EqSponsorDiscounts.brandOf(storeItem)
    if storeItem == nil or storeItem.brandIndex == nil or g_brandManager == nil then return nil end
    local brand = g_brandManager:getBrandByIndex(storeItem.brandIndex)
    return brand ~= nil and brand.name or nil
end


--- @param farmId number|nil
--- @param storeItem table|nil
--- @param kind string "purchase", "repair" or "repaint"
--- @return number share off, 0 for none
function EqSponsorDiscounts.shareFor(farmId, storeItem, kind)
    if farmId == nil or EqSponsorManager == nil or EqSponsorManager.config == nil then return 0 end
    local brand = EqSponsorDiscounts.brandOf(storeItem)
    if brand == nil then return 0 end
    return EqSponsorship.discount(EqSponsorManager.contractsFor(farmId), brand, kind,
        EqCompetitionManager.month or 0, EqSponsorManager.config.discountMonths or 0)
end


--- @param price number|nil
--- @param share number
--- @return number|nil
local function cut(price, share)
    if type(price) ~= "number" or share <= 0 then return price end
    return price * (1 - share)
end


--- @param vehicle table
local function wrapVehicle(vehicle)
    vehicle.eqDiscountsWrapped = true
    local storeItem = g_storeManager ~= nil and vehicle.configFileName ~= nil
        and g_storeManager:getItemByXMLFilename(vehicle.configFileName) or nil
    if EqSponsorDiscounts.brandOf(storeItem) == nil then return end
    for name, kind in pairs(EqSponsorDiscounts.WRAPS) do
        local original = vehicle[name]
        if type(original) == "function" then
            vehicle[name] = function(self, ...)
                local price, a, b, c = original(self, ...)
                local farmId = self.getOwnerFarmId ~= nil and self:getOwnerFarmId() or nil
                local ok, share = pcall(EqSponsorDiscounts.shareFor, farmId, storeItem, kind)
                return cut(price, ok and share or 0), a, b, c
            end
        end
    end
end


--- Wrap any vehicle not wrapped yet.
function EqSponsorDiscounts.update()
    local now = g_time or 0
    if EqSponsorDiscounts.scannedAt ~= nil and now - EqSponsorDiscounts.scannedAt < EqSponsorDiscounts.SCAN_MS
        and now >= EqSponsorDiscounts.scannedAt then return end
    EqSponsorDiscounts.scannedAt = now
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, vehicle in ipairs(system ~= nil and system.vehicles or {}) do
        if not vehicle.eqDiscountsWrapped then wrapVehicle(vehicle) end
    end
end


--- @param guarded function main.lua's error guard
function EqSponsorDiscounts.install(guarded)
    if EconomyManager ~= nil and EconomyManager.getBuyPrice ~= nil then
        local original = EconomyManager.getBuyPrice
        EconomyManager.getBuyPrice = function(self, storeItem, ...)
            local price, a, b, c = original(self, storeItem, ...)
            if not EqMain.isActive then return price, a, b, c end
            local farmId = EqSponsorDiscounts.buyingFarm
            if farmId == nil and g_currentMission ~= nil then farmId = g_currentMission:getFarmId() end
            local ok, share = pcall(EqSponsorDiscounts.shareFor, farmId, storeItem, "purchase")
            return cut(price, ok and share or 0), a, b, c
        end
    end
    if BuyVehicleData ~= nil and BuyVehicleData.updatePrice ~= nil then
        local original = BuyVehicleData.updatePrice
        BuyVehicleData.updatePrice = function(self, ...)
            local farmId = self.ownerFarmId
            if AccessHandler ~= nil and farmId == AccessHandler.EVERYONE then farmId = nil end
            EqSponsorDiscounts.buyingFarm = farmId
            local ok, result = pcall(original, self, ...)
            EqSponsorDiscounts.buyingFarm = nil
            if not ok then error(result) end
            return result
        end
    end
    Log:info("EqSponsorDiscounts: buy price %s, buy data %s", tostring(EconomyManager ~= nil and EconomyManager.getBuyPrice ~= nil),
        tostring(BuyVehicleData ~= nil and BuyVehicleData.updatePrice ~= nil))
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("sponsor discounts", EqSponsorDiscounts.update)
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        EqSponsorDiscounts.scannedAt = nil
    end)
end

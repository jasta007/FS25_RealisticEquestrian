--[[
    EqSponsorDiscounts: a sponsor's discounts on its own machines, from the contract's third month
    (James, 2026-11-01: a sponsor must back you for 3 months before discounts start).

    - Buying (and leasing) a sponsor's machine in the shop: the contract's purchase discount
      (EconomyManager.getBuyPrice; BuyVehicleData.updatePrice tells it which farm is buying).
    - Repairing one: the repair discount, on the game's repair (getRepairPrice) and on the
      Advanced Damage System mod's services (getServicePrice: inspection, maintenance, repair,
      overhaul), so the discount works with it as well.
    - Repainting one: the repaint discount (getRepaintPrice).
    - Used machines (the shop's sale items) get no sponsor discount: their price is already cut.
    - The shop's buy screen shows a "Sponsor discount" row with the sponsor's logo.

    Repair and repaint prices are wrapped on each vehicle (both the game and ADS call them on
    the vehicle), checked every few seconds for new vehicles.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsorDiscounts = {}

local Log = EqLog

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
                local ok, share = EqLog.try("EqSponsorDiscounts vehicle share", EqSponsorDiscounts.shareFor, farmId, storeItem, kind)
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


--- The purchase share the player's farm gets on a new (not used) store item.
--- @param storeItem table|nil
--- @param saleItem table|nil the used machine on sale, if any
--- @return number share off, 0 for none
function EqSponsorDiscounts.shopShare(storeItem, saleItem)
    if saleItem ~= nil or g_currentMission == nil then return 0 end
    return EqSponsorDiscounts.shareFor(g_currentMission:getFarmId(), storeItem, "purchase")
end


--- Adds a "Sponsor discount: 20%" row with the sponsor's logo to the shop's buy screen
--- (ShopConfigScreen.processAttributeData, the same rows as power, capacity and so on).
--- @param screen table ShopConfigScreen
--- @param storeItem table|nil
--- @param saleItem table|nil
function EqSponsorDiscounts.addShopRow(screen, storeItem, saleItem)
    local share = EqSponsorDiscounts.shopShare(storeItem, saleItem)
    if share <= 0 or screen.attributeItem == nil or screen.attributesLayout == nil then return end
    local row = screen.attributeItem:clone(screen.attributesLayout)
    local icon = row:getDescendantByName("icon")
    local text = row:getDescendantByName("text")
    if icon ~= nil then
        local brand = g_brandManager ~= nil and g_brandManager:getBrandByIndex(storeItem.brandIndex) or nil
        if brand ~= nil and brand.image ~= nil and ShopConfigScreen.GUI_PROFILE ~= nil
            and ShopConfigScreen.GUI_PROFILE.CAPACITY ~= nil then
            icon:applyProfile(ShopConfigScreen.GUI_PROFILE.CAPACITY)
            icon:setImageFilename(brand.image)
            icon:setImageUVs(nil, 0, 0, 0, 1, 1, 0, 1, 1)
            icon:setVisible(true)
        else
            icon:setVisible(false)
        end
    end
    if text ~= nil then
        text:setText(string.format(g_i18n:getText("eq_shop_sponsorDiscount"), math.floor(share * 100 + 0.5)))
    end
    screen.attributesLayout:invalidateLayout()
end


--- Testing (eqShopProbe): writes the open shop's list and details layout to the log, so the
--- discount on the shop tiles can be drawn the way the game draws a used machine's.
function EqSponsorDiscounts.probeShop()
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
    local function tree(element, depth)
        if element == nil or depth > 12 or #lines > 1500 then return end
        local text = type(element.text) == "string" and element.text or ""
        add("%s%s name=%s id=%s profile=%s visible=%s text=%q", string.rep("  ", depth),
            tostring(element.typeName or "?"), tostring(element.name), tostring(element.id),
            tostring(element.profile), tostring(element.visible), text)
        for _, child in ipairs(element.elements or {}) do tree(child, depth + 1) end
    end
    local function functions(class, label)
        if type(class) ~= "table" then add("%s: missing", label) return end
        local names = {}
        for key, value in pairs(class) do
            if type(value) == "function" then names[#names + 1] = tostring(key) end
        end
        table.sort(names)
        add("%s functions: %s", label, table.concat(names, ", "))
    end
    functions(ShopItemsFrame, "ShopItemsFrame")
    functions(ShopMenu, "ShopMenu")
    if ShopConfigScreen ~= nil and type(ShopConfigScreen.GUI_PROFILE) == "table" then
        local keys = {}
        for key, value in pairs(ShopConfigScreen.GUI_PROFILE) do keys[#keys + 1] = tostring(key) .. "=" .. tostring(value) end
        table.sort(keys)
        add("ShopConfigScreen.GUI_PROFILE: %s", table.concat(keys, ", "))
    end
    local menu = g_shopMenu
    if menu == nil and g_gui ~= nil and g_gui.screenControllers ~= nil and ShopMenu ~= nil then
        menu = g_gui.screenControllers[ShopMenu]
    end
    if menu == nil then add("Shop menu not found") end
    for key, value in pairs(menu or {}) do
        if type(value) == "table" and value.attributesLayout ~= nil and value.detailsTemplates ~= nil then
            add("Items frame: menu.%s", tostring(key))
            local fields = {}
            for field, v in pairs(value) do
                if type(v) ~= "function" then fields[#fields + 1] = tostring(field) .. ":" .. type(v) end
            end
            table.sort(fields)
            add("  fields: %s", table.concat(fields, ", "))
            local templates = {}
            for name in pairs(value.detailsTemplates) do templates[#templates + 1] = tostring(name) end
            table.sort(templates)
            add("  details templates: %s", table.concat(templates, ", "))
            -- the shape of any list the frame holds (its display items are one of them)
            for field, v in pairs(value) do
                if type(v) == "table" and type(v[1]) == "table" and v[1].elements == nil then
                    local keys = {}
                    for k, kv in pairs(v[1]) do keys[#keys + 1] = tostring(k) .. ":" .. type(kv) end
                    table.sort(keys)
                    add("  %s[1] (%d): %s", tostring(field), #v, table.concat(keys, ", "))
                end
            end
            add("  badge element found: %s", tostring(EqSponsorDiscounts.badgeName))
            tree(value, 1)
        end
    end
    for _, line in ipairs(lines) do print("[eqShopProbe] " .. line) end
    return #lines
end


--- The green "-35%" badge on a used machine's shop tile is the tile's "priceTag" (a
--- ThreePartBitmap holding the Text "priceTagText"), seen with eqShopProbe on James's game
--- 2026-11-04. The first descendant with one of these names (lower case) is used.
EqSponsorDiscounts.BADGE_NAMES = { "pricetag" }


--- @param cell table a shop list tile
--- @return table|nil the tile's discount badge text element
function EqSponsorDiscounts.findBadge(cell)
    if cell.eqBadge ~= nil then return cell.eqBadge or nil end
    local found = false
    local stack = { cell }
    while #stack > 0 and not found do
        local element = table.remove(stack)
        local name = type(element.name) == "string" and string.lower(element.name) or ""
        for _, part in ipairs(EqSponsorDiscounts.BADGE_NAMES) do
            if element ~= cell and name == part then found = element break end
        end
        for _, child in ipairs(element.elements or {}) do table.insert(stack, child) end
    end
    cell.eqBadge = found
    if found and EqSponsorDiscounts.badgeName == nil then
        EqSponsorDiscounts.badgeName = found.name
        Log:info("EqSponsorDiscounts: shop tile badge is '%s'", tostring(found.name))
    end
    return found or nil
end


--- Before the game fills a reused shop tile: take off a badge we put on it.
--- @param cell table
function EqSponsorDiscounts.resetTile(cell)
    if not cell.eqSponsorBadge then return end
    cell.eqSponsorBadge = false
    local badge = EqSponsorDiscounts.findBadge(cell)
    if badge ~= nil then badge:setVisible(false) end
end


--- After the game fills a shop tile: a new sponsor machine gets the same "-20%" badge a used
--- machine has. Only when the game left the badge hidden, so a used machine keeps its own.
--- @param frame table ShopItemsFrame
--- @param index number
--- @param cell table
function EqSponsorDiscounts.decorateTile(frame, index, cell)
    local badge = EqSponsorDiscounts.findBadge(cell)
    if badge == nil then return end
    -- the label inside the badge's box, if the badge is a box
    local label = badge.setText ~= nil and badge or nil
    if label == nil then
        for _, child in ipairs(badge.elements or {}) do
            if child.setText ~= nil then label = child break end
        end
    end
    if label == nil then return end
    if badge.visible then return end
    local items = frame.displayItems
    local item = type(items) == "table" and items[index] or nil
    local storeItem = item ~= nil and (item.storeItem or item) or nil
    if storeItem == nil or storeItem.brandIndex == nil or (item.saleItem ~= nil) then return end
    local share = EqSponsorDiscounts.shopShare(storeItem, nil)
    if share <= 0 then return end
    label:setText(string.format("-%d%%", math.floor(share * 100 + 0.5)))
    badge:setVisible(true)
    cell.eqSponsorBadge = true
end


--- @param guarded function main.lua's error guard
function EqSponsorDiscounts.install(guarded)
    if ShopItemsFrame ~= nil and ShopItemsFrame.populateCellForItemInSection ~= nil then
        ShopItemsFrame.populateCellForItemInSection = Utils.prependedFunction(ShopItemsFrame.populateCellForItemInSection,
            function(frame, list, section, index, cell)
                if cell == nil then return end
                guarded("sponsor discount shop tile reset", function() EqSponsorDiscounts.resetTile(cell) end)
            end)
        ShopItemsFrame.populateCellForItemInSection = Utils.appendedFunction(ShopItemsFrame.populateCellForItemInSection,
            function(frame, list, section, index, cell)
                if not EqMain.isActive or cell == nil then return end
                guarded("sponsor discount shop tile", function()
                    EqSponsorDiscounts.decorateTile(frame, index, cell)
                end)
            end)
    end
    if EconomyManager ~= nil and EconomyManager.getBuyPrice ~= nil then
        local original = EconomyManager.getBuyPrice
        EconomyManager.getBuyPrice = function(self, storeItem, configurations, saleItem, ...)
            local price, a, b, c = original(self, storeItem, configurations, saleItem, ...)
            -- used machines already carry their own sale discount: no sponsor discount on top
            if not EqMain.isActive or saleItem ~= nil then return price, a, b, c end
            local farmId = EqSponsorDiscounts.buyingFarm
            if farmId == nil and g_currentMission ~= nil then farmId = g_currentMission:getFarmId() end
            local ok, share = EqLog.try("EqSponsorDiscounts purchase share", EqSponsorDiscounts.shareFor, farmId, storeItem, "purchase")
            return cut(price, ok and share or 0), a, b, c
        end
    end
    if BuyVehicleData ~= nil and BuyVehicleData.updatePrice ~= nil then
        local original = BuyVehicleData.updatePrice
        BuyVehicleData.updatePrice = function(self, ...)
            local farmId = self.ownerFarmId
            if AccessHandler ~= nil and farmId == AccessHandler.EVERYONE then farmId = nil end
            EqSponsorDiscounts.buyingFarm = farmId
            local result = EqLog.finally(function() EqSponsorDiscounts.buyingFarm = nil end, original, self, ...)
            return result
        end
    end
    if ShopConfigScreen ~= nil and ShopConfigScreen.processAttributeData ~= nil then
        ShopConfigScreen.processAttributeData = Utils.appendedFunction(ShopConfigScreen.processAttributeData,
            function(screen, storeItem, vehicle, saleItem)
                if not EqMain.isActive then return end
                guarded("sponsor discount shop row", function()
                    EqSponsorDiscounts.addShopRow(screen, storeItem, saleItem)
                end)
            end)
    end
    Log:info("EqSponsorDiscounts: shop tiles %s", tostring(ShopItemsFrame ~= nil and ShopItemsFrame.populateCellForItemInSection ~= nil))
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

--[[
    EqPlinths.lua
    Sponsor plinths (James, 2026-10-31): a machine of the signed sponsor's brand parked on a
    plinth's deck counts towards the farm's branding, as MACHINE boards. Our plinths
    (placeables/sponsorPlinths/, art/source/plinths.py) and the drop walls' decks (which stay
    jumps too) have decks, listed here in each placeable's own space:

        x, y, z   the deck's middle (y its surface there)
        hx, hz    half its size across and along
        slope     how much the surface rises for each metre of z (a display ramp)
        r         a round deck's radius instead of hx, hz (the turntable)
        value     boards a machine there is worth, if not MACHINE

    A machine counts when the middle of its footprint is over a deck and it stands on it (its
    root, which sits on the ground in every FS25 vehicle, near the surface there). Each deck
    counts one machine and each machine one deck. Owned and leased machines count; ones borrowed
    for a contract don't (as with the sponsor's machine rule). Pure checks (inArea, best) are
    tested; the scan is cheap, done when the branding is counted.

    Part of Realistic Equestrian by Jasta007.
]]

EqPlinths = {}

-- Branding a parked sponsor machine adds, in boards (James, 2026-10-31: plinths give extra).
EqPlinths.MACHINE = 2
-- How far a machine's root may be below and above the deck's surface and still stand on it.
EqPlinths.BELOW = 0.4
EqPlinths.ABOVE = 1.0

local function drop(depth)
    return { { x = 0, y = 0.05, z = -1 + depth / 2, hx = 2.0, hz = depth / 2, slope = 0 } }
end

-- Keep in step with art/source/plinths.py and xc_jumps.py (DROP_WALLS, drop_depth, DROP_LIP).
EqPlinths.AREAS = {
    ["placeables/sponsorplinths/plinthdrive.xml"] = { { x = 0, y = 0.75, z = 0, hx = 1.6, hz = 3.0, slope = 0 } },
    ["placeables/sponsorplinths/plinthramp.xml"] = { { x = 0, y = 0.6, z = 0, hx = 1.5, hz = 2.0, slope = -1.2 / 4.6 } },
    ["placeables/sponsorplinths/plinthramplarge.xml"] = { { x = 0, y = 0.8, z = 0, hx = 1.9, hz = 3.0, slope = -1.6 / 6.6 } },
    ["placeables/sponsorplinths/plinthproductjump.xml"] = {
        -- each bank mostly ramp (from 3.1 m to 10.6 m out, 2 m high at the top): the machine
        -- stands on the slope, nose up to the short flat top
        { x = 0, y = 1.0, z = 6.85, hx = 2.0, hz = 4.25, slope = -2.0 / 7.5 },
        { x = 0, y = 1.0, z = -6.85, hx = 2.0, hz = 4.25, slope = 2.0 / 7.5 },
        { x = 0, y = 0, z = 0, hx = 2.0, hz = 1.6, slope = 0 },
    },
    ["placeables/sponsorplinths/plinthturntable.xml"] = { { x = 0, y = 0.73, z = 0, r = 2.9, slope = 0, value = 3 } },
    ["placeables/xcjumps/xcdropwall08.xml"] = drop(2.4),
    ["placeables/xcjumps/xcdropwall12.xml"] = drop(3.0),
    ["placeables/xcjumps/xcdropwall16.xml"] = drop(4.0),
}


--- @param filename string|nil
--- @return table|nil the decks of one of our plinths
function EqPlinths.areasFor(filename)
    if type(filename) ~= "string" then return nil end
    local path = string.lower(string.gsub(filename, "\\", "/"))
    for suffix, areas in pairs(EqPlinths.AREAS) do
        if string.sub(path, -#suffix) == suffix then return areas end
    end
    return nil
end


--- @param area table
--- @param x number a machine's root, in the plinth's space
--- @param y number
--- @param z number
--- @return boolean true when it stands on the deck
function EqPlinths.inArea(area, x, y, z)
    if area.r ~= nil then
        if (x - area.x) ^ 2 + (z - area.z) ^ 2 > area.r ^ 2 then return false end
    elseif math.abs(x - area.x) > area.hx or math.abs(z - area.z) > area.hz then
        return false
    end
    local surface = area.y + (area.slope or 0) * (z - area.z)
    local up = y - surface
    return up >= -EqPlinths.BELOW and up <= EqPlinths.ABOVE
end


--- Pair machines with decks, each deck one machine and each machine one deck.
--- @param decks table list of { area, plinth key }
--- @param machines table list of { x, y, z } per deck's plinth: machines[i][key] = { x, y, z } in its space
--- @return number boards the machines on the decks are worth
function EqPlinths.best(decks, machines)
    local used, count = {}, 0
    for _, deck in ipairs(decks) do
        for i, machine in ipairs(machines) do
            local p = not used[i] and machine[deck.key] or nil
            if p ~= nil and EqPlinths.inArea(deck.area, p[1], p[2], p[3]) then
                used[i] = true
                count = count + (deck.area.value or EqPlinths.MACHINE)
                break
            end
        end
    end
    return count
end


--- @param vehicle table
--- @return boolean true for a machine borrowed for a contract
local function borrowed(vehicle)
    local states = VehiclePropertyState
    return states ~= nil and states.MISSION ~= nil and vehicle.propertyState == states.MISSION
end


--- @param vehicle table
--- @return string|nil its brand's name
local function brandOf(vehicle)
    if vehicle.configFileName == nil or g_storeManager == nil or g_brandManager == nil then return nil end
    local item = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local brand = item ~= nil and item.brandIndex ~= nil and g_brandManager:getBrandByIndex(item.brandIndex) or nil
    return brand ~= nil and brand.name or nil
end


--- @param vehicle table
--- @return number|nil x, y, z the middle of its footprint on the ground, in the world
function EqPlinths.footprint(vehicle)
    local node = vehicle.rootNode
    if type(node) ~= "number" or node == 0 then return nil end
    local size = vehicle.size or {}
    return localToWorld(node, size.widthOffset or 0, 0, size.lengthOffset or 0)
end


--- @param farmId number
--- @param brand string|nil the farm's sponsor
--- @return number boards the sponsor's machines on the farm's plinths are worth
function EqPlinths.count(farmId, brand)
    if brand == nil or g_currentMission == nil then return 0 end
    local placeables = g_currentMission.placeableSystem ~= nil and g_currentMission.placeableSystem.placeables or {}
    local decks, plinths = {}, {}
    for _, placeable in ipairs(placeables) do
        local areas = EqPlinths.areasFor(placeable.configFileName)
        local owner = placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() or nil
        if areas ~= nil and owner == farmId and type(placeable.rootNode) == "number" and placeable.rootNode ~= 0 then
            table.insert(plinths, placeable)
            for _, area in ipairs(areas) do table.insert(decks, { area = area, key = placeable }) end
        end
    end
    if #decks == 0 then return 0 end
    local vehicles = g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    local machines = {}
    for _, vehicle in ipairs(vehicles) do
        local owner = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
        if owner == farmId and not borrowed(vehicle) and brandOf(vehicle) == brand then
            local wx, wy, wz = EqPlinths.footprint(vehicle)
            if wx ~= nil then
                local machine = {}
                for _, placeable in ipairs(plinths) do
                    local x, y, z = worldToLocal(placeable.rootNode, wx, wy, wz)
                    machine[placeable] = { x, y, z }
                end
                table.insert(machines, machine)
            end
        end
    end
    return EqPlinths.best(decks, machines)
end


--- @param placeable table
--- @return boolean true when any machine stands on one of its decks: a drop wall bought
--- Disappearing must not hide (and drop its collision) under a parked machine (EqXcHide)
function EqPlinths.holdsMachine(placeable)
    local areas = EqPlinths.areasFor(placeable ~= nil and placeable.configFileName or nil)
    if areas == nil or type(placeable.rootNode) ~= "number" or placeable.rootNode == 0 or g_currentMission == nil then return false end
    local vehicles = g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        local wx, wy, wz = EqPlinths.footprint(vehicle)
        if wx ~= nil then
            local x, y, z = worldToLocal(placeable.rootNode, wx, wy, wz)
            for _, area in ipairs(areas) do
                if EqPlinths.inArea(area, x, y, z) then return true end
            end
        end
    end
    return false
end

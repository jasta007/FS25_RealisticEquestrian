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
    root, which sits on the ground in every FS25 vehicle, near the surface there), whichever way
    it faces. Each deck counts one machine and each machine one deck. Owned and leased machines
    count; ones borrowed for a contract don't (as with the sponsor's machine rule).

    The product ramps come in pairs the player sets facing each other (James, 2026-11-01): a
    machine on the ground between two facing ramps' faces, GAP apart at most, stands in the gap,
    a place of its own.

    Feedback (James): stopping a machine you're driving on a place says whether it's your
    sponsor's equipment. A machine of another brand on show when a hosted event's results come in
    costs RIVAL_PENALTY of the sponsor fee each, at most RIVAL_MAX.

    Pure checks (inArea, between, match) are tested; the scan is cheap, done when the branding is
    counted and every CHECK_MS for the feedback.

    Part of Realistic Equestrian by Jasta007.
]]

EqPlinths = {}

-- Branding a parked sponsor machine adds, in boards (James, 2026-10-31: plinths give extra).
EqPlinths.MACHINE = 2
-- How far a machine's root may be below and above the deck's surface and still stand on it.
EqPlinths.BELOW = 0.4
EqPlinths.ABOVE = 1.0
-- Two product ramps' faces at most this far apart make a gap between them (the ramps ship 4.8 m
-- apart in the shop's picture), and at least this, so two ramps back to back don't.
EqPlinths.GAP = { min = 2.5, max = 8.0, hx = 2.2 }
EqPlinths.RAMP = "placeables/sponsorplinths/plinthproductramp.xml"
EqPlinths.RIVAL_PENALTY = 0.10
EqPlinths.RIVAL_MAX = 0.50
EqPlinths.CHECK_MS = 500
EqPlinths.STILL_KMH = 1.0
-- The wrong-brand popup in plain red (James, 2026-11-01). The game's notification types are
-- colours (RGBA tables); if not, its critical type is used.
EqPlinths.RED = { 0.95, 0.08, 0.06, 1 }
-- When a plinth goes (sold, or a Lizard plinth collapsing), machines near it are woken for WAKE_MS
-- so they fall instead of floating on where it stood (James, 2026-11-01: a Volvo truck floated).
EqPlinths.WAKE_RANGE = 15
EqPlinths.WAKE_MS = 2000
EqPlinths.waking = {}

local function drop(depth)
    return { { x = 0, y = 0.05, z = -1 + depth / 2, hx = 2.0, hz = depth / 2, slope = 0 } }
end

-- Keep in step with art/source/plinths.py and xc_jumps.py (DROP_WALLS, drop_depth, DROP_LIP).
EqPlinths.AREAS = {
    ["placeables/sponsorplinths/plinthdrive.xml"] = { { x = 0, y = 0.75, z = 0, hx = 1.6, hz = 3.0, slope = 0 } },
    ["placeables/sponsorplinths/plinthramp.xml"] = { { x = 0, y = 0.6, z = 0, hx = 1.5, hz = 2.0, slope = -1.2 / 4.6 } },
    ["placeables/sponsorplinths/plinthramplarge.xml"] = { { x = 0, y = 0.8, z = 0, hx = 1.9, hz = 3.0, slope = -1.6 / 6.6 } },
    -- one bank: its 2 m face at z = 0 (facing -z), a 1.5 m flat top, then 7.5 m of ramp down to
    -- the ground; the machine stands mostly on the slope
    ["placeables/sponsorplinths/plinthproductramp.xml"] = { { x = 0, y = 2.0 - 3.5 * 2.0 / 7.5, z = 5.0, hx = 2.0, hz = 4.0, slope = -2.0 / 7.5 } },
    ["placeables/sponsorplinths/plinthturntable.xml"] = { { x = 0, y = 0.73, z = 0, r = 3.35, slope = 0, value = 3 } },
    -- the Lizard plinth's log deck (art/source/lizard_plinth.py DECK, DECK_TOP)
    ["placeables/sponsorplinths/lizardplinthstone.xml"] = { { x = 0, y = 1.15, z = 0, hx = 2.05, hz = 1.85, slope = 0 } },
    ["placeables/sponsorplinths/lizardplinthwoodchips.xml"] = { { x = 0, y = 1.15, z = 0, hx = 2.05, hz = 1.85, slope = 0 } },
    ["placeables/sponsorplinths/lizardplinthstraw.xml"] = { { x = 0, y = 1.15, z = 0, hx = 2.05, hz = 1.85, slope = 0 } },
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


--- @param a table a machine in one product ramp's space { x, y, z }
--- @param b table the same machine in the other's
--- @return boolean true when it stands on the ground in the gap between the two ramps' faces
function EqPlinths.between(a, b)
    local gap = EqPlinths.GAP
    if a[3] > 0 or b[3] > 0 then return false end
    if math.abs(a[1]) > gap.hx or math.abs(b[1]) > gap.hx then return false end
    local width = -(a[3] + b[3])
    if width < gap.min or width > gap.max then return false end
    return a[2] >= -EqPlinths.BELOW and a[2] <= EqPlinths.ABOVE
end


--- Pair machines with places, each place one machine and each machine one place, places in order.
--- @param places table list of places
--- @param machines table list of machines
--- @param on function(place, machine) true when the machine stands there
--- @return table list of { place, machine }
function EqPlinths.match(places, machines, on)
    local used, pairs_ = {}, {}
    for _, place in ipairs(places) do
        for i, machine in ipairs(machines) do
            if not used[i] and on(place, machine) then
                used[i] = true
                table.insert(pairs_, { place = place, machine = machine })
                break
            end
        end
    end
    return pairs_
end


--- @param vehicle table
--- @return boolean true for a machine borrowed for a contract
local function borrowed(vehicle)
    local states = VehiclePropertyState
    return states ~= nil and states.MISSION ~= nil and vehicle.propertyState == states.MISSION
end


--- @param vehicle table
--- @return string|nil its brand's name
function EqPlinths.brandOf(vehicle)
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
--- @return table places on the farm's plinths: { node, area } decks and { a, b } gaps
function EqPlinths.places(farmId)
    local places, ramps = {}, {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local areas = EqPlinths.areasFor(placeable.configFileName)
        local owner = placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() or nil
        local root = placeable.rootNode
        if areas ~= nil and (farmId == nil or owner == farmId) and type(root) == "number" and root ~= 0 then
            for _, area in ipairs(areas) do table.insert(places, { node = root, area = area, placeable = placeable }) end
            if string.sub(string.lower(string.gsub(placeable.configFileName, "\\", "/")), -#EqPlinths.RAMP) == EqPlinths.RAMP then
                table.insert(ramps, placeable)
            end
        end
    end
    for i = 1, #ramps do
        for j = i + 1, #ramps do
            table.insert(places, { a = ramps[i].rootNode, b = ramps[j].rootNode, value = EqPlinths.MACHINE })
        end
    end
    return places
end


--- @param place table
--- @param wx number a machine's footprint in the world
--- @return boolean true when it stands there
function EqPlinths.stands(place, wx, wy, wz)
    if place.area ~= nil then
        local x, y, z = worldToLocal(place.node, wx, wy, wz)
        return EqPlinths.inArea(place.area, x, y, z)
    end
    local ax, ay, az = worldToLocal(place.a, wx, wy, wz)
    local bx, by, bz = worldToLocal(place.b, wx, wy, wz)
    return EqPlinths.between({ ax, ay, az }, { bx, by, bz })
end


--- @param place table
--- @return number boards a sponsor machine there is worth
function EqPlinths.value(place)
    return place.value or (place.area ~= nil and place.area.value) or EqPlinths.MACHINE
end


--- @param farmId number
--- @return table pairs { place, machine = { vehicle, x, y, z, brand } } of the farm's machines on its plinths
function EqPlinths.onShow(farmId)
    local places = EqPlinths.places(farmId)
    if #places == 0 then return {} end
    local machines = {}
    local vehicles = g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        local owner = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
        if owner == farmId and not borrowed(vehicle) then
            local wx, wy, wz = EqPlinths.footprint(vehicle)
            if wx ~= nil then table.insert(machines, { vehicle = vehicle, x = wx, y = wy, z = wz }) end
        end
    end
    return EqPlinths.match(places, machines, function(place, machine)
        return EqPlinths.stands(place, machine.x, machine.y, machine.z)
    end)
end


--- @param brands table|string|nil
--- @return table set of brand names
local function brandSet(brands)
    if type(brands) == "string" then brands = { brands } end
    local set = {}
    for _, name in ipairs(type(brands) == "table" and brands or {}) do set[name] = true end
    return set
end


--- @param farmId number
--- @param brands table|string|nil the farm's sponsors (a list, or one brand)
--- @return number boards the sponsors' machines on the farm's plinths are worth
--- @return number rivals machines of other brands on show (only while the farm has a sponsor)
function EqPlinths.count(farmId, brands)
    local signed = brandSet(brands)
    if next(signed) == nil or g_currentMission == nil then return 0, 0 end
    local boards, rivals = 0, 0
    for _, pair in ipairs(EqPlinths.onShow(farmId)) do
        if signed[EqPlinths.brandOf(pair.machine.vehicle) or ""] then
            boards = boards + EqPlinths.value(pair.place)
        else
            rivals = rivals + 1
        end
    end
    return boards, rivals
end


--- @param rivals number
--- @return number share of the sponsor fee lost for rival machines on show
function EqPlinths.penalty(rivals)
    return math.min(EqPlinths.RIVAL_MAX, EqPlinths.RIVAL_PENALTY * (rivals or 0))
end


--- @param placeable table
--- @return string|nil the brand of a machine standing on one of its decks (the first found), so
--- the plinth can show that sponsor (James, 2026-11-01: a McCormick on the turntable, which went
--- over to a newly signed sponsor's colours)
function EqPlinths.parkedBrand(placeable)
    local areas = EqPlinths.areasFor(placeable ~= nil and placeable.configFileName or nil)
    if areas == nil or type(placeable.rootNode) ~= "number" or placeable.rootNode == 0 or g_currentMission == nil then return nil end
    local vehicles = g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        local wx, wy, wz = EqPlinths.footprint(vehicle)
        if wx ~= nil then
            local x, y, z = worldToLocal(placeable.rootNode, wx, wy, wz)
            for _, area in ipairs(areas) do
                if EqPlinths.inArea(area, x, y, z) then
                    local brand = EqPlinths.brandOf(vehicle)
                    if brand ~= nil then return brand end
                end
            end
        end
    end
    -- a product ramp with nothing on it takes the brand of a machine in a gap it makes with
    -- another (James, 2026-11-01: a McCormick between two ramps, both ramps say McCormick; with a
    -- machine on each ramp, each shows its own)
    if string.sub(string.lower(string.gsub(placeable.configFileName, "\\", "/")), -#EqPlinths.RAMP) ~= EqPlinths.RAMP then return nil end
    local system = g_currentMission.placeableSystem
    for _, other in ipairs(system ~= nil and system.placeables or {}) do
        if other ~= placeable and type(other.rootNode) == "number" and other.rootNode ~= 0 and type(other.configFileName) == "string"
            and string.sub(string.lower(string.gsub(other.configFileName, "\\", "/")), -#EqPlinths.RAMP) == EqPlinths.RAMP then
            local gap = { a = placeable.rootNode, b = other.rootNode }
            for _, vehicle in ipairs(vehicles) do
                local wx, wy, wz = EqPlinths.footprint(vehicle)
                if wx ~= nil and EqPlinths.stands(gap, wx, wy, wz) then
                    local brand = EqPlinths.brandOf(vehicle)
                    if brand ~= nil then return brand end
                end
            end
        end
    end
    return nil
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


--- @param vehicle table
local function wake(vehicle)
    if vehicle.isDeleted or vehicle.isDeleting then return end
    for _, component in ipairs(vehicle.components or {}) do
        local node = component.node
        if type(node) == "number" and node ~= 0 and (entityExists == nil or entityExists(node)) then
            if I3DUtil ~= nil and I3DUtil.wakeUpObject ~= nil then
                I3DUtil.wakeUpObject(node)
            elseif getLinearVelocity ~= nil and setLinearVelocity ~= nil then
                -- setting a body's velocity wakes it
                local vx, vy, vz = getLinearVelocity(node)
                setLinearVelocity(node, vx or 0, vy or 0, vz or 0)
            end
        end
    end
    if vehicle.raiseActive ~= nil then vehicle:raiseActive() end
end


--- A plinth is going: wake the machines near it over the next WAKE_MS.
--- @param placeable table
function EqPlinths.wakeNear(placeable)
    if g_currentMission == nil or g_currentMission.vehicleSystem == nil then return end
    if type(placeable.rootNode) ~= "number" or placeable.rootNode == 0 then return end
    local px, _, pz = getWorldTranslation(placeable.rootNode)
    local untilAt = (g_time or 0) + EqPlinths.WAKE_MS
    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles or {}) do
        if type(vehicle.rootNode) == "number" and vehicle.rootNode ~= 0 then
            local vx, _, vz = getWorldTranslation(vehicle.rootNode)
            if (vx - px) ^ 2 + (vz - pz) ^ 2 <= EqPlinths.WAKE_RANGE ^ 2 then EqPlinths.waking[vehicle] = untilAt end
        end
    end
end


--- Each frame: keep waking machines whose plinth went.
function EqPlinths.wakeUpdate()
    if next(EqPlinths.waking) == nil then return end
    local now = g_time or 0
    for vehicle, untilAt in pairs(EqPlinths.waking) do
        if now > untilAt or vehicle.isDeleted then
            EqPlinths.waking[vehicle] = nil
        else
            wake(vehicle)
        end
    end
end


--- @return table|nil the machine the player is driving
local function driven()
    for _, vehicle in ipairs(g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}) do
        if vehicle.getIsEntered ~= nil and vehicle:getIsEntered() then return vehicle end
    end
    return nil
end


--- Every CHECK_MS: when the player stops the machine they drive on a place of their own
--- plinths, say whether it's sponsor equipment (once per arrival).
function EqPlinths.update()
    if g_currentMission == nil or g_currentMission.getFarmId == nil then return end
    local now = g_time or 0
    if EqPlinths.checkedAt ~= nil and now - EqPlinths.checkedAt < EqPlinths.CHECK_MS and now >= EqPlinths.checkedAt then return end
    EqPlinths.checkedAt = now
    local vehicle = driven()
    if vehicle == nil then EqPlinths.shown = nil return end
    local speed = vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0
    if math.abs(speed) > EqPlinths.STILL_KMH then return end
    local farmId = g_currentMission:getFarmId()
    local wx, wy, wz = EqPlinths.footprint(vehicle)
    if wx == nil then return end
    local here = nil
    for _, place in ipairs(EqPlinths.places(farmId)) do
        if EqPlinths.stands(place, wx, wy, wz) then here = place break end
    end
    if here == nil then EqPlinths.shown = nil return end
    local key = tostring(vehicle) .. tostring(here.node or here.a) .. tostring(here.area or here.b)
    if EqPlinths.shown == key then return end
    EqPlinths.shown = key
    local signed = brandSet(EqSponsors ~= nil and EqSponsors.signedBrands ~= nil and EqSponsors.signedBrands(farmId) or {})
    local text, level
    if next(signed) == nil then
        text, level = g_i18n:getText("eq_plinth_noSponsor"), FSBaseMission.INGAME_NOTIFICATION_INFO
    elseif signed[EqPlinths.brandOf(vehicle) or ""] then
        text, level = g_i18n:getText("eq_plinth_inPlace"), FSBaseMission.INGAME_NOTIFICATION_OK
    else
        text, level = g_i18n:getText("eq_plinth_wrongBrand"), FSBaseMission.INGAME_NOTIFICATION_CRITICAL
        if type(level) == "table" then level = EqPlinths.RED end
    end
    g_currentMission:addIngameNotification(level, text)
end


--- After a hosted event's sponsor fees are paid: take RIVAL_PENALTY of them back for each machine
--- of another brand on show on the farm's plinths.
--- @param event table
--- @param report table
--- @param fee number what the sponsors paid
--- @return number fee after the penalty
function EqPlinths.afterEvent(event, report, fee)
    if (fee or 0) <= 0 or event == nil or event.hosted == nil then return fee end
    local farmId = event.hosted.farmId
    local signed = EqSponsors ~= nil and EqSponsors.signedBrands ~= nil and EqSponsors.signedBrands(farmId) or {}
    local _, rivals = EqPlinths.count(farmId, signed)
    local share = EqPlinths.penalty(rivals)
    if share <= 0 then return fee end
    local cut = math.floor(fee * share + 0.5)
    g_currentMission:addMoney(-cut, farmId, MoneyType.EQ_SPONSORSHIP or MoneyType.OTHER, true, true)
    if report ~= nil then
        report.sponsorFee = (report.sponsorFee or fee) - cut
        report.sponsorRivals = rivals
    end
    local text = string.format(g_i18n:getText("eq_plinth_penalty"), rivals, g_i18n:formatMoney(cut, 0, true, true))
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text)
    return fee - cut
end


--- @param guarded function main.lua's error guard
function EqPlinths.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("plinth feedback", EqPlinths.update)
        guarded("plinth wake", EqPlinths.wakeUpdate)
    end)
    if Placeable ~= nil and Placeable.delete ~= nil then
        Placeable.delete = Utils.prependedFunction(Placeable.delete, function(placeable)
            if EqMain.isActive and EqPlinths.areasFor(placeable.configFileName) ~= nil then
                EqLog.try("EqPlinths wake", EqPlinths.wakeNear, placeable)
            end
        end)
    end
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, function() EqPlinths.waking = {} end)
    if EqSponsorManager ~= nil and EqSponsorManager.afterEvent ~= nil then
        local paid = EqSponsorManager.afterEvent
        EqSponsorManager.afterEvent = function(event, report)
            local fee = paid(event, report)
            local ok, after = EqLog.try("EqPlinths penalty", EqPlinths.afterEvent, event, report, fee)
            if ok and after ~= nil then return after end
            return fee
        end
    end
end

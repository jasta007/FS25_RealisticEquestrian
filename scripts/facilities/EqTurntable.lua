--[[
    EqTurntable.lua
    The sponsor turntable (placeables/sponsorPlinths/plinthTurntable, James, 2026-10-31): its disc
    ("eqTurntableDisc") turns very slowly, and a machine left standing on it turns with it.

    Turning a machine with real physics would fight the wheels, so, like a ferry carrying a
    vehicle, the machine is held instead: once it has stood on the disc with nobody in it for
    HOLD_MS, it slides to the disc's middle, comes out of the physics and follows the disc (each
    of its parts copies a helper node linked under the disc). Getting in, hitching anything to it,
    selling it or the turntable, or leaving the game gives it back its physics where it is.

    A machine is held with everything hitched to it (James, 2026-11-01: a wheel loader, whose
    bucket is an implement of its own, wouldn't snap): the whole chain comes out of the physics
    and turns together; hitching or unhitching anything lets go.
    In multiplayer the disc turns but nothing is held: the server's held machine would not reach
    the other players the same way (not tried).

    Part of Realistic Equestrian by Jasta007.
]]

EqTurntable = {}

local Log = EqLog

EqTurntable.XML = "placeables/sponsorplinths/plinthturntable.xml"
EqTurntable.DISC = "eqTurntableDisc"
-- One turn in this long (James: "really slowly").
EqTurntable.TURN_MS = 120000
-- A machine is held after standing on the disc, empty and still, this long.
EqTurntable.HOLD_MS = 3000
-- Below this speed (km/h) a machine counts as standing still.
EqTurntable.STILL_KMH = 0.5
EqTurntable.SCAN_MS = 2000

EqTurntable.tables = {}     -- rootNode -> { placeable, disc, angle, held = { vehicle -> entry }, waiting = { vehicle -> ms } }
EqTurntable.scannedAt = nil


--- @param filename string|nil
--- @return boolean
function EqTurntable.isTurntable(filename)
    if type(filename) ~= "string" then return false end
    local path = string.lower(string.gsub(filename, "\\", "/"))
    return string.sub(path, -#EqTurntable.XML) == EqTurntable.XML
end


--- @param angle number the disc's turn now
--- @param dt number ms since the last frame
--- @return number the turn after dt, kept within one full turn
function EqTurntable.advance(angle, dt)
    local turn = 2 * math.pi
    return (angle + turn * (dt or 0) / EqTurntable.TURN_MS) % turn
end


--- @param vehicle table
--- @return boolean true when someone (or a helper) is driving it
local function inUse(vehicle)
    if vehicle.getIsControlled ~= nil and vehicle:getIsControlled() then return true end
    if vehicle.getIsEntered ~= nil and vehicle:getIsEntered() then return true end
    if vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then return true end
    return false
end


--- @param vehicle table
--- @return table the machines hitched together with it, its root first (just itself if alone)
local function chain(vehicle)
    local root = vehicle.rootVehicle or vehicle
    local list = { root }
    if root.getChildVehicles ~= nil then
        for _, child in pairs(root:getChildVehicles() or {}) do
            if child ~= root then table.insert(list, child) end
        end
    end
    return list
end


--- @param vehicle table
--- @return boolean true for the head of its chain (the one held for all of them)
local function isHead(vehicle)
    return vehicle.rootVehicle == nil or vehicle.rootVehicle == vehicle
end


--- @param vehicle table
--- @return boolean
local function still(vehicle)
    local speed = vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0
    return math.abs(speed) < EqTurntable.STILL_KMH
end


--- @param vehicle table
--- @return boolean true while it is in the game
local function exists(vehicle)
    if vehicle.isDeleted or vehicle.isDeleting then return false end
    return type(vehicle.rootNode) == "number" and (entityExists == nil or entityExists(vehicle.rootNode))
end


--- @param entry table a turntable
--- @param vehicle table
--- @return boolean true when the machine stands on the disc
local function onDisc(entry, vehicle)
    local areas = EqPlinths ~= nil and EqPlinths.areasFor(EqTurntable.XML) or nil
    if areas == nil then return false end
    local wx, wy, wz = EqPlinths.footprint(vehicle)
    if wx == nil then return false end
    local x, y, z = worldToLocal(entry.placeable.rootNode, wx, wy, wz)
    return EqPlinths.inArea(areas[1], x, y, z)
end


--- Take a machine onto the disc: to its middle, out of the physics, a helper per part.
--- @param entry table
--- @param vehicle table
local function hold(entry, vehicle)
    local machines = chain(vehicle)
    for _, machine in ipairs(machines) do
        if machine.removeFromPhysics == nil or #(machine.components or {}) == 0 then return end
    end
    local fx, _, fz = EqPlinths.footprint(vehicle)
    local cx, _, cz = getWorldTranslation(entry.disc)
    local dx, dz = cx - fx, cz - fz
    local components = {}
    for _, machine in ipairs(machines) do
        machine:removeFromPhysics()
        for _, component in ipairs(machine.components) do table.insert(components, component) end
    end
    local helpers = { machines = machines }
    for _, component in ipairs(components) do
        local node = component.node
        local x, y, z = getWorldTranslation(node)
        setWorldTranslation(node, x + dx, y, z + dz)
        local helper = createTransformGroup("eqTurntableHold")
        link(entry.disc, helper)
        setWorldTranslation(helper, x + dx, y, z + dz)
        setWorldQuaternion(helper, getWorldQuaternion(node))
        table.insert(helpers, { node = node, helper = helper })
    end
    entry.held[vehicle] = helpers
    Log:info("EqTurntable: %s held on the turntable", tostring(vehicle.configFileName))
end


--- Give a held machine its physics back where it stands.
--- @param entry table
--- @param vehicle table
local function release(entry, vehicle)
    local helpers = entry.held[vehicle]
    entry.held[vehicle] = nil
    if helpers == nil then return end
    for _, h in ipairs(helpers) do
        if entityExists == nil or entityExists(h.helper) then delete(h.helper) end
    end
    for _, machine in ipairs(helpers.machines or { vehicle }) do
        if exists(machine) and machine.addToPhysics ~= nil then machine:addToPhysics() end
    end
end


--- Move each held machine's parts to their helpers.
--- @param entry table
local function follow(entry)
    for vehicle, helpers in pairs(entry.held) do
        for _, h in ipairs(helpers) do
            if entityExists == nil or (entityExists(h.node) and entityExists(h.helper)) then
                setWorldTranslation(h.node, getWorldTranslation(h.helper))
                setWorldQuaternion(h.node, getWorldQuaternion(h.helper))
            end
        end
    end
end


local function isMultiplayer()
    local info = g_currentMission ~= nil and g_currentMission.missionDynamicInfo or nil
    return info ~= nil and info.isMultiplayer == true
end


--- Find placed turntables (every SCAN_MS); forget sold ones, giving their machines back.
local function scan(now)
    local seen = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local root = placeable.rootNode
        if EqTurntable.isTurntable(placeable.configFileName) and type(root) == "number" and root ~= 0 then
            seen[root] = true
            if EqTurntable.tables[root] == nil then
                local disc = EqTurntable.findDisc(root)
                if disc ~= nil then
                    EqTurntable.tables[root] = { placeable = placeable, disc = disc, angle = 0, held = {}, waiting = {} }
                end
            end
        end
    end
    for root, entry in pairs(EqTurntable.tables) do
        if not seen[root] then
            for vehicle in pairs(entry.held) do release(entry, vehicle) end
            EqTurntable.tables[root] = nil
        end
    end
    EqTurntable.scannedAt = now
end


--- @param node number
--- @return number|nil the disc under a turntable's root
function EqTurntable.findDisc(node)
    local stack = { node }
    while #stack > 0 do
        local current = table.remove(stack)
        if getName(current) == EqTurntable.DISC then return current end
        for i = 0, getNumOfChildren(current) - 1 do table.insert(stack, getChildAt(current, i)) end
    end
    return nil
end


--- Each frame: turn the discs, hold machines left on them, let go of ones got into.
--- @param dt number
function EqTurntable.update(dt)
    local now = g_time or 0
    if EqTurntable.scannedAt == nil or now - EqTurntable.scannedAt >= EqTurntable.SCAN_MS or now < EqTurntable.scannedAt then
        scan(now)
    end
    if next(EqTurntable.tables) == nil then return end
    local holding = not isMultiplayer() and g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil
    for _, entry in pairs(EqTurntable.tables) do
        entry.angle = EqTurntable.advance(entry.angle, dt)
        setRotation(entry.disc, 0, entry.angle, 0)
        if holding then
            for vehicle, helpers in pairs(entry.held) do
                local now_ = chain(vehicle)
                local changed = #now_ ~= #(helpers.machines or {})
                for _, machine in ipairs(now_) do
                    if not exists(machine) or inUse(machine) then changed = true end
                end
                if not exists(vehicle) or changed then release(entry, vehicle) end
            end
            follow(entry)
            if now - (entry.checkedAt or 0) >= 250 or now < (entry.checkedAt or 0) then
                local elapsed = now - (entry.checkedAt or now)
                entry.checkedAt = now
                local waiting = {}
                for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles or {}) do
                    local free = isHead(vehicle) and entry.held[vehicle] == nil and exists(vehicle) and onDisc(entry, vehicle)
                    if free then
                        for _, machine in ipairs(chain(vehicle)) do
                            if inUse(machine) or not still(machine) then free = false end
                        end
                    end
                    if free then
                        local waited = (entry.waiting[vehicle] or 0) + math.max(0, elapsed)
                        if waited >= EqTurntable.HOLD_MS then
                            EqLog.try("EqTurntable hold", hold, entry, vehicle)
                        else
                            waiting[vehicle] = waited
                        end
                    end
                end
                entry.waiting = waiting
            end
        end
    end
end


--- Give every held machine back (leaving the game, or before saving: saved where they stand).
function EqTurntable.releaseAll()
    for _, entry in pairs(EqTurntable.tables) do
        for vehicle in pairs(entry.held) do release(entry, vehicle) end
    end
end


--- @param guarded function main.lua's error guard
function EqTurntable.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(_, dt)
        if not EqMain.isActive then return end
        guarded("turntable", function() EqTurntable.update(dt) end)
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        EqLog.try("EqTurntable release", EqTurntable.releaseAll)
        EqTurntable.tables, EqTurntable.scannedAt = {}, nil
    end)
end

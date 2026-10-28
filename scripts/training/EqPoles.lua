--[[
    EqPoles.lua
    Our own show jumps (placeables/showJumps/, from art/source/show_jumps.py) have poles that fall
    when the horse hits them and go back up afterwards (James, 2026-10-28). The stands, wings and
    cups never move; each pole is a transform group "eqPole<n>" with its own static collision box.

    What knocks a pole: the jump tracker (EqTrainingHooks) already judges rails. When the horse's
    leg rays find its hooves below a pole's top in the air, that pole goes (onClip); any other rail
    over one of these jumps (hit it, landed on it) drops its highest pole still up (onRail).

    The fall is scripted, not physics, so a pole can never turn into a spinning beam of death
    (James): its collision comes off, one end leaves its cup a moment before the other, it drops
    under gravity and slides a little the way the horse was going, and lies on the ground. A pole
    goes back to where the i3d has it, with its collision, when a round's countdown starts, or
    once it has been down RESET_MS and no ridden horse is within RESET_CLEAR of the jump (not while
    a round is under way: the rails stay down to the finish).

    Single player for now: jumps are tracked on the server, and nothing is sent to clients.

    Part of Realistic Equestrian by Jasta007.
]]

EqPoles = {}

local Log = EqLog

-- Placeables whose xml path has this in it carry falling poles.
EqPoles.FOLDER = "placeables/showjumps/"
EqPoles.PREFIX = "eqpole"
-- From art/source/show_jumps.py: POLE_LENGTH and POLE_R.
EqPoles.LENGTH = 3.5
EqPoles.RADIUS = 0.05
EqPoles.GRAVITY = 9.81
-- The second end leaves its cup this long after the first (seconds).
EqPoles.LAG = 0.12
-- A falling pole slides the horse's way at this speed (m/s), slowing at PUSH_DRAG (m/s²).
EqPoles.PUSH = 1.1
EqPoles.PUSH_DRAG = 2.2
-- A rail with no pole clipped drops a pole of the nearest of our jumps this near the horse (m).
EqPoles.NEAR = 4.5
-- A dropped pole stays down at least this long, then goes up once no ridden horse is this near.
EqPoles.RESET_MS = 6000
EqPoles.RESET_CLEAR = 12
-- A rider counts as near for this long after they were last seen.
EqPoles.RIDER_MS = 1000
-- Jumps are listed again this often, to catch newly placed (or sold) ones.
EqPoles.SCAN_MS = 1000

EqPoles.UP, EqPoles.FALLING, EqPoles.DOWN = "up", "falling", "down"

EqPoles.jumps = {}
EqPoles.byNode = {}
EqPoles.riders = {}
EqPoles.scannedAt = nil
EqPoles.at = nil


function EqPoles.reset()
    EqPoles.jumps, EqPoles.byNode, EqPoles.riders = {}, {}, {}
    EqPoles.scannedAt, EqPoles.at = nil, nil
end


--- Where a falling pole is, t seconds after it was knocked. Pure, for the tests.
--- @param fall table { y0 = the pole's middle at rest in its cups, restA/restB = its middle's
---   height lying on the ground under its +x/-x end, lead = 1 when the +x end goes first else -1,
---   push = 1 to slide towards +z else -1, length }
--- @param t number seconds
--- @return number y of the middle, number z offset, number tilt (radians about z, +x end up),
---   boolean true once it lies still
function EqPoles.fallPose(fall, t)
    local function endAt(isLead, rest)
        local te = isLead and t or t - EqPoles.LAG
        if te <= 0 then return fall.y0, false end
        local y = fall.y0 - 0.5 * EqPoles.GRAVITY * te * te
        if y <= rest then return rest, true end
        return y, false
    end
    local a, aDown = endAt(fall.lead > 0, fall.restA)
    local b, bDown = endAt(fall.lead < 0, fall.restB)
    local stopAt = EqPoles.PUSH / EqPoles.PUSH_DRAG
    local ts = math.min(math.max(t, 0), stopAt)
    local dz = fall.push * (EqPoles.PUSH * ts - 0.5 * EqPoles.PUSH_DRAG * ts * ts)
    local length = fall.length or EqPoles.LENGTH
    local tilt = math.asin(math.max(-1, math.min(1, (a - b) / length)))
    return (a + b) / 2, dz, tilt, aDown and bDown and t >= stopAt
end


--- Whether a pole that is down may go back up now. Pure, for the tests.
--- @param pole table { state, downAt }
--- @param now number g_time
--- @param busy boolean a round is under way
--- @param riderNear boolean a ridden horse is within RESET_CLEAR of the jump
--- @return boolean
function EqPoles.mayReset(pole, now, busy, riderNear)
    if pole.state ~= EqPoles.DOWN or busy or riderNear then return false end
    return now - (pole.downAt or now) >= EqPoles.RESET_MS or now < (pole.downAt or 0)
end


local function noneType()
    return RigidBodyType ~= nil and RigidBodyType.NONE or "NoRigidBody"
end


local function staticType()
    return RigidBodyType ~= nil and RigidBodyType.STATIC or "Static"
end


--- @param configFileName string|nil
--- @return boolean true for our show jumps
function EqPoles.isOurs(configFileName)
    if type(configFileName) ~= "string" then return false end
    local path = string.lower(string.gsub(configFileName, "\\", "/"))
    return string.find(path, EqPoles.FOLDER, 1, true) ~= nil
end


--- The poles of one of our jumps, found once.
--- @param placeable table
--- @return table poles
local function polesOf(placeable)
    if placeable.eqPoles ~= nil then return placeable.eqPoles end
    local root, poles = placeable.rootNode, {}
    for i = 0, getNumOfChildren(root) - 1 do
        local node = getChildAt(root, i)
        if string.find(string.lower(getName(node)), EqPoles.PREFIX, 1, true) == 1 then
            local x, y, z = getTranslation(node)
            local rx, ry, rz = getRotation(node)
            local pole = { node = node, root = root, state = EqPoles.UP, home = { x, y, z, rx, ry, rz }, cols = {} }
            for k = 0, getNumOfChildren(node) - 1 do
                local child = getChildAt(node, k)
                local kind = getRigidBodyType ~= nil and getRigidBodyType(child) or nil
                if kind ~= nil and kind ~= noneType() and kind ~= "NoRigidBody" then
                    table.insert(pole.cols, { node = child, kind = kind })
                elseif string.find(string.lower(getName(child)), "col", 1, true) ~= nil then
                    -- Collision already off (the course editor took it): it was static in the i3d.
                    table.insert(pole.cols, { node = child, kind = staticType() })
                end
                EqPoles.byNode[child] = pole
            end
            EqPoles.byNode[node] = pole
            table.insert(poles, pole)
        end
    end
    -- Highest last: a rail with no pole named drops the highest one still up.
    table.sort(poles, function(p, q) return p.home[2] < q.home[2] end)
    placeable.eqPoles = poles
    Log:info("Poles: %d on %s", #poles, tostring(placeable.configFileName))
    return poles
end


--- List our jumps again.
function EqPoles.scan()
    EqPoles.scannedAt = g_time or 0
    local list = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then
        EqPoles.jumps = list
        return
    end
    for _, placeable in ipairs(system.placeables) do
        if placeable.rootNode ~= nil and EqPoles.isOurs(placeable.configFileName) then
            local ok, poles = EqLog.try("EqPoles.scan polesOf", polesOf, placeable)
            if ok and #poles > 0 then table.insert(list, { placeable = placeable, root = placeable.rootNode, poles = poles }) end
        end
    end
    EqPoles.jumps = list
end


local function exists(node)
    return node ~= nil and node ~= 0 and (entityExists == nil or entityExists(node))
end


--- Ground height under a point in the jump's space, in that space.
local function groundIn(root, x, z)
    local wx, wy, wz = localToWorld(root, x, 0, z)
    local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
    if terrain == nil or terrain == 0 or getTerrainHeightAtWorldPos == nil then return 0 end
    local ok, height = EqLog.try("EqPoles.groundIn getTerrainHeightAtWorldPos", getTerrainHeightAtWorldPos, terrain, wx, wy, wz)
    if not ok or height == nil then return 0 end
    local _, y, _ = worldToLocal(root, wx, height, wz)
    return y
end


--- Knock one pole off its cups.
--- @param pole table
--- @param dirX number|nil the horse's way, in the world
--- @param dirZ number|nil
--- @param hitX number|nil where along the pole it was hit, in the jump's space (that end goes first)
--- @return boolean true when it falls
function EqPoles.knock(pole, dirX, dirZ, hitX)
    if pole.state ~= EqPoles.UP or not exists(pole.node) then return false end
    local root = pole.root
    local push = 1
    if dirX ~= nil and dirZ ~= nil then
        local zx, _, zz = localDirectionToWorld(root, 0, 0, 1)
        if dirX * zx + dirZ * zz < 0 then push = -1 end
    end
    local lead = (hitX or 0) >= 0 and 1 or -1
    if hitX == nil then lead = math.random() < 0.5 and 1 or -1 end
    local home = pole.home
    local half = EqPoles.LENGTH / 2
    local slide = push * EqPoles.PUSH * EqPoles.PUSH / (2 * EqPoles.PUSH_DRAG)
    pole.fall = {
        y0 = home[2], lead = lead, push = push, length = EqPoles.LENGTH,
        restA = groundIn(root, home[1] + half, home[3] + slide) + EqPoles.RADIUS,
        restB = groundIn(root, home[1] - half, home[3] + slide) + EqPoles.RADIUS,
    }
    for _, col in ipairs(pole.cols) do
        if exists(col.node) then EqLog.try("EqPoles.knock setRigidBodyType", setRigidBodyType, col.node, noneType()) end
    end
    pole.state, pole.t = EqPoles.FALLING, 0
    Log:info("Poles: %s knocked down (%s end first)", getName(pole.node), lead > 0 and "+x" or "-x")
    return true
end


--- A pole back in its cups, with its collision.
--- @param pole table
function EqPoles.raise(pole)
    if pole.state == EqPoles.UP or not exists(pole.node) then return end
    local h = pole.home
    setTranslation(pole.node, h[1], h[2], h[3])
    setRotation(pole.node, h[4], h[5], h[6])
    -- While a course is edited the jump's collision is off (EqCourseHooks): hand the pole's to
    -- the editor, which gives it all back when editing ends.
    local taken = EqCourseHooks ~= nil and EqCourseHooks.bodies ~= nil and EqCourseHooks.bodies[pole.root] or nil
    for _, col in ipairs(pole.cols) do
        if exists(col.node) then
            if taken ~= nil then
                table.insert(taken, { node = col.node, kind = col.kind })
            else
                EqLog.try("EqPoles.raise setRigidBodyType", setRigidBodyType, col.node, col.kind)
            end
        end
    end
    pole.state, pole.fall, pole.t, pole.downAt = EqPoles.UP, nil, nil, nil
end


--- Every pole back up (a round's countdown).
function EqPoles.raiseAll()
    local count = 0
    for _, jump in ipairs(EqPoles.jumps) do
        for _, pole in ipairs(jump.poles) do
            if pole.state ~= EqPoles.UP then
                EqPoles.raise(pole)
                count = count + 1
            end
        end
    end
    if count > 0 then Log:info("Poles: %d put back up", count) end
end


--- The pole a collision node belongs to, if any.
--- @param node number|nil
--- @return table|nil pole
function EqPoles.poleFor(node)
    if node == nil then return nil end
    local pole = EqPoles.byNode[node]
    if pole == nil and EqPoles.scannedAt == nil then
        EqPoles.scan()
        pole = EqPoles.byNode[node]
    end
    return pole
end


--- @param vehicle table
--- @return number, number the horse's way in the world (x, z)
local function heading(vehicle)
    local dx, _, dz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
    return dx, dz
end


--- The horse's legs clipped something in the air: if it is one of our poles, it falls.
--- @param node number|nil the collision the leg rays hit
--- @param vehicle table
--- @param hitX number|nil world x of the hit
--- @param hitZ number|nil
--- @return boolean true when a pole fell
function EqPoles.onClip(node, vehicle, hitX, hitZ)
    local pole = EqPoles.poleFor(node)
    if pole == nil then return false end
    local dx, dz = heading(vehicle)
    local localX = nil
    if hitX ~= nil and hitZ ~= nil then localX = worldToLocal(pole.root, hitX, 0, hitZ) end
    return EqPoles.knock(pole, dx, dz, localX)
end


--- A rail was judged: when the horse is at one of our jumps and no pole fell yet, its highest
--- pole still up falls.
--- @param vehicle table
function EqPoles.onRail(vehicle)
    if EqPoles.scannedAt == nil then EqPoles.scan() end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local best, bestDistance = nil, EqPoles.NEAR
    for _, jump in ipairs(EqPoles.jumps) do
        if exists(jump.root) then
            -- distance to the jump's middle line (along x in its space, LENGTH wide)
            local lx, _, lz = worldToLocal(jump.root, x, 0, z)
            local along = math.max(0, math.abs(lx) - EqPoles.LENGTH / 2)
            local distance = math.sqrt(along * along + lz * lz)
            if distance <= bestDistance then best, bestDistance = jump, distance end
        end
    end
    if best == nil then return end
    for i = #best.poles, 1, -1 do
        local pole = best.poles[i]
        if pole.state == EqPoles.UP then
            local dx, dz = heading(vehicle)
            EqPoles.knock(pole, dx, dz, nil)
            return
        end
    end
end


--- Each frame, for every ridden horse (on the server): where riders are, for the reset.
--- @param vehicle table
function EqPoles.noteRider(vehicle)
    if vehicle.rootNode == nil then return end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    EqPoles.riders[vehicle] = { x = x, z = z, at = g_time or 0 }
end


--- @return boolean true while a round is under way (rails stay down to the finish)
local function roundBusy()
    local round = EqCourseHooks ~= nil and EqCourseHooks.round or nil
    local state = round ~= nil and round.sj ~= nil and round.sj.state or nil
    return state == "countdown" or state == "go" or state == "running"
end


local function riderNear(root, now)
    local x, _, z = getWorldTranslation(root)
    for vehicle, rider in pairs(EqPoles.riders) do
        if now - rider.at > EqPoles.RIDER_MS or now < rider.at then
            EqPoles.riders[vehicle] = nil
        elseif (rider.x - x) ^ 2 + (rider.z - z) ^ 2 <= EqPoles.RESET_CLEAR ^ 2 then
            return true
        end
    end
    return false
end


--- Each frame: falling poles fall, dropped ones go back up when they may.
function EqPoles.update()
    local now = g_time or 0
    local dt = EqPoles.at ~= nil and math.max(0, math.min(200, now - EqPoles.at)) or 0
    EqPoles.at = now
    if EqPoles.scannedAt == nil or now - EqPoles.scannedAt >= EqPoles.SCAN_MS or now < EqPoles.scannedAt then EqPoles.scan() end
    local busy = nil
    for _, jump in ipairs(EqPoles.jumps) do
        local near = nil
        for _, pole in ipairs(jump.poles) do
            if pole.state == EqPoles.FALLING and exists(pole.node) then
                pole.t = pole.t + dt / 1000
                local y, dz, tilt, still = EqPoles.fallPose(pole.fall, pole.t)
                local h = pole.home
                setTranslation(pole.node, h[1], y, h[3] + dz)
                setRotation(pole.node, h[4], h[5], h[6] + tilt)
                if still then pole.state, pole.downAt = EqPoles.DOWN, now end
            elseif pole.state == EqPoles.DOWN then
                if busy == nil then busy = roundBusy() end
                if near == nil then near = riderNear(jump.root, now) end
                if EqPoles.mayReset(pole, now, busy, near) then EqPoles.raise(pole) end
            end
        end
    end
end

--[[
    EqPoles.lua
    Our own show jumps (placeables/showJumps/, from art/source/show_jumps.py) have poles that fall
    when the horse hits them and go back up afterwards (James, 2026-10-28). The stands, wings and
    cups never move; each pole is a transform group "eqPole<n>" with its own static collision box.

    What knocks a pole: when the horse's leg rays (EqTrainingHooks) find its hooves below a pole's
    top in the air, that pole goes (onClip); running into the jump drops the pole in front
    (onCrash). In a show jumping round a pole falling is the rail (EqCourseHooks.onPoleDown):
    over these jumps nothing else counts as one (James, 2026-10-29).

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
EqPoles.END = "eqEnd"
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
-- A horse running into one of our jumps (James, 2026-10-29: "it probably should" fall) knocks a
-- pole off when a point this far in front of it is within CRASH_REACH of the jump's poles.
EqPoles.CRASH_AHEAD = 1.0
EqPoles.CRASH_REACH = 1.5
-- A dropped pole stays down at least this long, then goes up once no ridden horse is this near.
EqPoles.RESET_MS = 6000
EqPoles.RESET_CLEAR = 12
-- A rider counts as near for this long after they were last seen.
EqPoles.RIDER_MS = 1000
-- Jumps are listed again this often, to catch newly placed (or sold) ones.
EqPoles.SCAN_MS = 1000

-- The clonk as a pole comes off its cups (James's recordings, 2026-10-29): one of these, picked at
-- random, at a random pitch in PITCH so no two knocks sound the same. Heard up to SOUND_RANGE metres.
EqPoles.SOUNDS = { "sounds/poleKnock1.ogg", "sounds/poleKnock2.ogg" }
EqPoles.PITCH = { 0.88, 1.12 }
EqPoles.SOUND_RANGE = 60
EqPoles.SOUND_INNER = 8
EqPoles.SOUND_VOLUME = 1.0
EqPoles.modDirectory = g_currentModDirectory

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
--- @param fall table { a = { x, y, z } its +x end in its cups, b = { x, y, z } its -x end (in the
---   jump's space: a crossrail's ends are at different heights, a fan's at different z),
---   restA/restB = the height its middle lies at on the ground under each end, lead = 1 when the
---   +x end goes first else -1, push = 1 to slide towards +z else -1 }
--- @param t number seconds
--- @return table pose { x, y, z of its middle, ry = turn about y (radians, +x end towards -z),
---   rz = tilt about z (+x end up), still = true once it lies still }
function EqPoles.fallPose(fall, t)
    local function endAt(isLead, y0, rest)
        local te = isLead and t or t - EqPoles.LAG
        if te <= 0 then return y0, y0 <= rest end
        local y = y0 - 0.5 * EqPoles.GRAVITY * te * te
        if y <= rest then return rest, true end
        return y, false
    end
    local a, b = fall.a, fall.b
    local ya, aDown = endAt(fall.lead > 0, a[2], fall.restA)
    local yb, bDown = endAt(fall.lead < 0, b[2], fall.restB)
    local stopAt = EqPoles.PUSH / EqPoles.PUSH_DRAG
    local ts = math.min(math.max(t, 0), stopAt)
    local dz = fall.push * (EqPoles.PUSH * ts - 0.5 * EqPoles.PUSH_DRAG * ts * ts)
    local ax, az, bx, bz = a[1], a[3] + dz, b[1], b[3] + dz
    local horizontal = math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
    return {
        x = (ax + bx) / 2, y = (ya + yb) / 2, z = (az + bz) / 2,
        ry = math.atan2(-(az - bz), ax - bx), rz = math.atan2(ya - yb, horizontal),
        still = aDown and bDown and t >= stopAt,
    }
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


-- How deep under the placeable's root node poles are looked for: its rootNode is the i3d file's
-- root, so the jump's own transform group is one down and its poles two.
EqPoles.DEPTH = 4


--- The pole groups under a node.
--- @param root number
--- @return table nodes
local function findPoles(root)
    local found, stack = {}, { { root, 0 } }
    while #stack > 0 do
        local entry = table.remove(stack)
        local node, depth = entry[1], entry[2]
        if node ~= root and string.find(string.lower(getName(node)), EqPoles.PREFIX, 1, true) == 1 then
            table.insert(found, node)
        elseif depth < EqPoles.DEPTH then
            for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, { getChildAt(node, i), depth + 1 }) end
        end
    end
    return found
end


--- The poles of one of our jumps, found once.
--- @param placeable table
--- @return table poles
local function polesOf(placeable)
    if placeable.eqPoles ~= nil then return placeable.eqPoles end
    local root, poles = placeable.rootNode, {}
    for _, node in ipairs(findPoles(root)) do
        local x, y, z = getTranslation(node)
        local rx, ry, rz = getRotation(node)
        local jump = getParent(node)
        local pole = { node = node, root = jump, placeableRoot = root, state = EqPoles.UP, home = { x, y, z, rx, ry, rz }, cols = {},
            half = EqPoles.LENGTH / 2 }
        for k = 0, getNumOfChildren(node) - 1 do
            local child = getChildAt(node, k)
            -- A marker at the pole's +x end says how long it is (fans' poles are longer).
            if getName(child) == EqPoles.END then pole.half = math.abs(getTranslation(child)) end
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
            if EqJumpColours ~= nil then EqLog.try("EqPoles.scan colours", EqJumpColours.apply, placeable) end
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


--- The knock sound, played where the pole is: a 3D audio source on the pole, made the first time
--- it is knocked and used again after.
--- @param pole table
local function playKnock(pole)
    if createAudioSource == nil or getAudioSourceSample == nil or playSample == nil or EqPoles.modDirectory == nil then return end
    local index = math.random(#EqPoles.SOUNDS)
    pole.sounds = pole.sounds or {}
    local source = pole.sounds[index]
    if source == nil then
        source = createAudioSource("eqPoleKnock" .. index, EqPoles.modDirectory .. EqPoles.SOUNDS[index], EqPoles.SOUND_RANGE,
            EqPoles.SOUND_INNER, EqPoles.SOUND_VOLUME, 1)
        if source == nil or source == 0 then return end
        link(pole.node, source)
        if setAudioSourceAutoPlay ~= nil then setAudioSourceAutoPlay(source, false) end
        pole.sounds[index] = source
    end
    local sample = getAudioSourceSample(source)
    if setSampleGroup ~= nil and AudioGroup ~= nil and AudioGroup.ENVIRONMENT ~= nil then setSampleGroup(sample, AudioGroup.ENVIRONMENT) end
    if setSamplePitch ~= nil then setSamplePitch(sample, EqPoles.PITCH[1] + math.random() * (EqPoles.PITCH[2] - EqPoles.PITCH[1])) end
    playSample(sample, 1, EqPoles.SOUND_VOLUME, 0, 0, 0)
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
    -- Its ends where they are now, in the jump's space: the pole may be tilted (a crossrail) or
    -- turned (a fan).
    local half = pole.half or EqPoles.LENGTH / 2
    local ax, ay, az = localToLocal(pole.node, root, half, 0, 0)
    local bx, by, bz = localToLocal(pole.node, root, -half, 0, 0)
    local slide = push * EqPoles.PUSH * EqPoles.PUSH / (2 * EqPoles.PUSH_DRAG)
    pole.fall = {
        a = { ax, ay, az }, b = { bx, by, bz }, lead = lead, push = push,
        restA = groundIn(root, ax, az + slide) + EqPoles.RADIUS,
        restB = groundIn(root, bx, bz + slide) + EqPoles.RADIUS,
    }
    for _, col in ipairs(pole.cols) do
        if exists(col.node) then EqLog.try("EqPoles.knock setRigidBodyType", setRigidBodyType, col.node, noneType()) end
    end
    pole.state, pole.t = EqPoles.FALLING, 0
    EqLog.try("EqPoles.knock sound", playKnock, pole)
    Log:info("Poles: %s knocked down (%s end first)", getName(pole.node), lead > 0 and "+x" or "-x")
    -- A show jumping round counts a rail at the fence it falls from (EqCourseHooks): poles down,
    -- not the jump's landing, give the faults (James, 2026-10-29).
    if EqCourseHooks ~= nil and EqCourseHooks.onPoleDown ~= nil then
        local wx, _, wz = localToWorld(root, (ax + bx) / 2, 0, (az + bz) / 2)
        EqCourseHooks.onPoleDown(wx, wz)
    end
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
    local taken = EqCourseHooks ~= nil and EqCourseHooks.bodies ~= nil and EqCourseHooks.bodies[pole.placeableRoot] or nil
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


--- Which pole a horse running into a jump knocks off: the highest still up in the row of poles
--- nearest it (an oxer's front row from the front). Pure, for the tests.
--- @param poles table { state, home = { x, y, z } }
--- @param lz number the horse's front, along the jump's z
--- @return table|nil pole
function EqPoles.crashPole(poles, lz)
    local row = nil
    for _, pole in ipairs(poles) do
        if pole.state == EqPoles.UP and (row == nil or math.abs(pole.home[3] - lz) < math.abs(row - lz)) then row = pole.home[3] end
    end
    local best = nil
    for _, pole in ipairs(poles) do
        if pole.state == EqPoles.UP and pole.home[3] == row and (best == nil or pole.home[2] > best.home[2]) then best = pole end
    end
    return best
end


--- The horse ran into something: if it is one of our jumps, a pole falls.
--- @param vehicle table
--- @return boolean true when a pole fell
function EqPoles.onCrash(vehicle)
    if EqPoles.scannedAt == nil then EqPoles.scan() end
    local x, _, z = localToWorld(vehicle.rootNode, 0, 0, EqPoles.CRASH_AHEAD)
    local dx, dz = heading(vehicle)
    for _, jump in ipairs(EqPoles.jumps) do
        local first = jump.poles[1]
        if first ~= nil and exists(first.root) then
            local lx, _, lz = worldToLocal(first.root, x, 0, z)
            if math.abs(lx) <= EqPoles.LENGTH / 2 then
                local pole = EqPoles.crashPole(jump.poles, lz)
                if pole ~= nil and math.abs(pole.home[3] - lz) <= EqPoles.CRASH_REACH then
                    Log:info("Poles: ran into %s", getName(pole.node))
                    return EqPoles.knock(pole, dx, dz, nil)
                end
            end
        end
    end
    return false
end


--- The nearest of our jumps to a horse, within NEAR of its middle line.
--- @param vehicle table
--- @return table|nil jump, number|nil metres
function EqPoles.nearest(vehicle)
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
    return best, best ~= nil and bestDistance or nil
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
                local pose = EqPoles.fallPose(pole.fall, pole.t)
                setTranslation(pole.node, pose.x, pose.y, pose.z)
                setRotation(pole.node, 0, pose.ry, pose.rz)
                if pose.still then pole.state, pole.downAt = EqPoles.DOWN, now end
            elseif pole.state == EqPoles.DOWN then
                if busy == nil then busy = roundBusy() end
                if near == nil then near = riderNear(jump.root, now) end
                if EqPoles.mayReset(pole, now, busy, near) then EqPoles.raise(pole) end
            end
        end
    end
end

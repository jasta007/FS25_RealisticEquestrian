--[[
    EqTrainingHooks.lua
    Wires EqTraining into the game.

    - Rideable.updateRiding and Rideable.jump (base game) record the player's riding into a sheet
      per horse. Vehicle functions are copied into each vehicle type when types are registered,
      so these two are patched at source time, before that happens; the hook bodies stay idle
      until EqMain is active. Both run on the server only, which is where riding is counted.
    - Rideable.updateRiding also steps the exertion system (EqExertion), at a halt too, and keeps
      the base game's gait in line with it: a blown horse can't gallop, and slowing from a
      gallop to a canter takes what EqExertion.allowGait says. The forward and back keys
      (Rideable.actionEventAccelerate and actionEventBrake) pick the gallop's pace.
    - Rideable.onDraw shows the training panel while riding (EqTrainingHud): the exertion bar
      and a line per stat for today's training; the farm's facility the horse is
      inside (EqFacilityHooks) and the boost its feed gives (EqFeedHooks) in the help panel. The
      training view key (Y, Rideable.onRegisterActionEvents) switches to a focused view for one
      stat; H, and the first time each view opens, shows its help popups.
    - RLRM's AnimalHorse.processRidingUpdate is the daily horse tick. A prepend runs our day
      just before RLRM grades fitness and zeroes riding, so the day's riding value is still there
      to read.

    Sheets live in memory only: a save and reload mid-day drops that day's player riding (staff
    work is read from RLRM's saved riding value, so it survives).
]]

EqTrainingHooks = {}
EqTrainingHooks.sheets = {}

local Log = EqLog

local gaitNames = nil
local gaitTypes = nil


--- @param cluster table|nil RLRM Animal being ridden
--- @return boolean true once its riding bar is full: the horse is tired and trains no more today
local function isTired(cluster)
    return cluster ~= nil and (cluster.riding or 0) >= 100
end


--- Map Rideable.GAITTYPES values to EqTraining's gait names. Built on first use.
--- @return table
local function getGaitNames()
    if gaitNames == nil then
        local types = Rideable.GAITTYPES
        gaitNames = {
            [types.WALK] = "walk",
            [types.TROT] = "trot",
            [types.CANTER] = "canter",
            [types.GALLOP] = "gallop",
        }
        if types.BACKWARDS ~= nil then gaitNames[types.BACKWARDS] = "reverse" end
        gaitTypes = {}
        for value, name in pairs(gaitNames) do gaitTypes[name] = value end
    end
    return gaitNames
end


--- @param spec table spec_rideable
--- @return string|nil the gait the rider has asked for (not "halt" when it stands still)
local function inputGait(spec)
    return getGaitNames()[spec.inputValues.currentGait]
end


--- @param spec table spec_rideable
--- @param name string canter or gallop
local function setInputGait(spec, name)
    getGaitNames()
    if gaitTypes[name] ~= nil then spec.inputValues.currentGait = gaitTypes[name] end
end


--- @param id string
--- @return table sheet, created on first use
function EqTrainingHooks.getSheet(id)
    local sheet = EqTrainingHooks.sheets[id]
    if sheet == nil then
        sheet = EqTraining.newSheet()
        -- The month the riding happens in, for peak form (EqTraining.formFor).
        sheet.month = EqCompetitionManager.month or 0
        EqTrainingHooks.sheets[id] = sheet
    end
    return sheet
end


function EqTrainingHooks.reset()
    EqTrainingHooks.sheets = {}
    EqTrainingHooks.showJumpNodes = {}
    EqDressageHooks.reset()
    EqCourseHooks.reset()
    EqPoles.reset()
end


--- The RLRM identifier of the horse a rideable carries, cached until its cluster changes.
--- @param spec table spec_rideable
--- @return string|nil id
local function getRiddenId(spec)
    local cluster = spec.cluster
    if cluster == nil then return nil end
    if spec.eqCluster ~= cluster then
        spec.eqCluster = cluster
        spec.eqId = (cluster.isHorse ~= nil and cluster:isHorse()) and EqRegistry.getId(cluster) or nil
    end
    return spec.eqId
end


--- Backing up tires a horse faster than the base game counts, a fit horse's bar fills more
--- slowly, and riding that trains little costs less: add the difference to (or take it off) its
--- riding bar.
--- @param spec table spec_rideable
--- @param gait string
--- @param factor number EqTraining.ridingBarFactor over EqTraining.workStep's share
--- @param dt number milliseconds
local function adjustRiding(spec, gait, factor, dt)
    local cluster = spec.cluster
    if cluster.changeRiding == nil then return end
    local fullMs = cluster.getDailyRidingTime ~= nil and cluster:getDailyRidingTime() or EqConstants.RIDING_FULL_MS
    local points
    points, spec.eqReverseTimer = EqTraining.ridingAdjust(spec.eqReverseTimer, dt, gait, factor, fullMs)
    if points ~= 0 then cluster:changeRiding(points) end
end


-- Jumps: while the horse is in the air we look down from a row of points along its body (and
-- either side) for anything with a collision that is not the ground. A jump is judged
-- JUMP_SETTLE_MS after landing: it counts as cleared when something at least JUMP_MIN_HEIGHT
-- tall was under the horse in the air, it did not end up standing on it, and it did not hit
-- anything on the way (a crash, or losing most of its take-off speed). A clear over a proper
-- show jump (a "jumps" facility: Riding Hall 2k26's shop jumps, a map's jump course) trains
-- more agility than one over a fence, a bale or a parked tractor.
EqTrainingHooks.JUMP_MIN_HEIGHT = 0.25
EqTrainingHooks.JUMP_RAY_UP = 0.3
EqTrainingHooks.JUMP_RAY_LENGTH = 6
-- Ray offsets in metres: along the horse (forward is positive) and across it.
EqTrainingHooks.JUMP_RAYS_ALONG = { -1.2, -0.6, 0, 0.6, 1.2 }
EqTrainingHooks.JUMP_RAYS_ACROSS = { -0.4, 0.4 }
EqTrainingHooks.JUMP_TIMEOUT_MS = 3000
EqTrainingHooks.JUMP_SETTLE_MS = 600
-- A jump that ends with less than this share of the take-off speed hit something.
EqTrainingHooks.JUMP_KNOCK_SPEED_SHARE = 0.4
-- Clipping the jump (James, 2026-10-28: a show jump drops a pole when the horse just clips the
-- jump model): in the air, rays from CLIP_RAY_UP above the horse's hooves (its root) down
-- through where its legs are look for the jump's top. A top less than CLIP_CLEARANCE under the
-- hooves, on anything at least JUMP_MIN_HEIGHT tall, is a clip. Only rays this near the middle of
-- the horse count: past the legs its body is well above the hooves.
EqTrainingHooks.CLIP_RAY_UP = 1.0
EqTrainingHooks.CLIP_CLEARANCE = 0.0
EqTrainingHooks.CLIP_REACH = 0.6
-- Without a ground flag a jump is judged this long after take-off.
EqTrainingHooks.JUMP_FALLBACK_MS = 1500
-- The base game halts a horse that runs into something for 900 ms; we cut that to this.
EqTrainingHooks.CRASH_HALT_MS = 350
-- For this long after a crash the jump combo clock runs at the normal rate, not ten times
-- faster for the stop and the walk back up to speed.
EqTrainingHooks.CRASH_GRACE_MS = 2000

-- Turns for the routine come from the rider's steering key, not the horse's heading (which
-- is unclear when backing up). Steering is taken as negative for left.
EqTrainingHooks.STEER_MIN = 0.3

local probe = { vehicle = nil, height = nil, name = nil, showJump = false, node = nil, x = nil, z = nil }
-- How many parents up from the hit collision we look for a show jump's placeable or map node.
EqTrainingHooks.SHOW_JUMP_DEPTH = 12
-- Hit node -> true/false, so each collision is only looked up once (emptied with the mission).
EqTrainingHooks.showJumpNodes = {}


--- Whether a node the jump ray hit belongs to a show jump: a placeable or a map node of the
--- "jumps" facility kind, found by walking up from the collision.
--- @param node number
--- @return boolean
function EqTrainingHooks.isShowJump(node)
    local known = EqTrainingHooks.showJumpNodes[node]
    if known ~= nil then return known end
    local config = EqFacilityHooks.config
    if config == nil then return false end
    local roots = {}
    for _, entry in ipairs(EqFacilityHooks.listPlaceables()) do
        if entry.kind == "jumps" and entry.placeable.rootNode ~= nil then roots[entry.placeable.rootNode] = true end
    end
    local found, current = false, node
    for _ = 1, EqTrainingHooks.SHOW_JUMP_DEPTH do
        if current == nil or current == 0 then break end
        if roots[current] or EqFacility.kindForNode(config, getName(current)) == "jumps" then
            found = true
            break
        end
        current = getParent(current)
    end
    EqTrainingHooks.showJumpNodes[node] = found
    return found
end


--- raycastAll callback: skip the horse itself, keep the first thing below it.
function EqTrainingHooks:jumpRaycastCallback(hitObjectId, x, y, z, distance)
    if hitObjectId == nil or hitObjectId == 0 then return true end
    if g_currentMission.terrainRootNode ~= nil and hitObjectId == g_currentMission.terrainRootNode then return true end
    local object = g_currentMission.getNodeObject ~= nil and g_currentMission:getNodeObject(hitObjectId) or nil
    if object ~= nil and object == probe.vehicle then return true end
    probe.height, probe.node, probe.x, probe.z = y, hitObjectId, x, z
    probe.name = getName ~= nil and getName(hitObjectId) or tostring(hitObjectId)
    local ok, showJump = EqLog.try("EqTrainingHooks.jumpRaycastCallback isShowJump", EqTrainingHooks.isShowJump, hitObjectId)
    probe.showJump = ok and showJump or false
    return false
end


--- @return number collision mask for things a horse can jump: anything but the ground
local function jumpMask()
    local mask = 0
    for _, name in ipairs({ "DEFAULT", "STATIC_OBJECT", "BUILDING", "DYNAMIC_OBJECT", "TREE", "PLACEMENT_BLOCKING" }) do
        if CollisionFlag ~= nil and CollisionFlag[name] ~= nil then mask = mask + CollisionFlag[name] end
    end
    return mask
end


--- How tall the thing under one point is, if there is one.
--- @param up number|nil metres above y the ray starts (JUMP_RAY_UP)
--- @return number|nil height above the ground in metres, string|nil name, boolean show jump,
---   number|nil the top's world height, number|nil the collision hit
local function obstacleAt(vehicle, x, y, z, up)
    local ground = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, y, z)
    up = up or EqTrainingHooks.JUMP_RAY_UP
    probe.vehicle, probe.height, probe.name, probe.showJump, probe.node = vehicle, nil, nil, false, nil
    raycastAll(x, y + up, z, 0, -1, 0, EqTrainingHooks.JUMP_RAY_LENGTH + up - EqTrainingHooks.JUMP_RAY_UP,
        "jumpRaycastCallback", EqTrainingHooks, jumpMask())
    probe.vehicle = nil
    if probe.height == nil then return nil end
    return probe.height - ground, probe.name, probe.showJump, probe.height, probe.node
end


--- The tallest thing under the horse's body, if there is one.
--- @param vehicle table
--- @return number|nil height above the ground in metres, string|nil name, boolean show jump
---   (any ray over a show jump at least JUMP_MIN_HEIGHT tall)
local function obstacleBelow(vehicle)
    if raycastAll == nil or vehicle.rootNode == nil then return nil end
    local best, bestName, showJump = nil, nil, false
    local function look(along, across)
        local x, y, z = localToWorld(vehicle.rootNode, across, 0, along)
        local height, name, isShowJump = obstacleAt(vehicle, x, y, z)
        if height ~= nil and (best == nil or height > best) then best, bestName = height, name end
        if isShowJump and height ~= nil and height >= EqTrainingHooks.JUMP_MIN_HEIGHT then showJump = true end
    end
    for _, along in ipairs(EqTrainingHooks.JUMP_RAYS_ALONG) do look(along, 0) end
    for _, across in ipairs(EqTrainingHooks.JUMP_RAYS_ACROSS) do look(0, across) end
    return best, bestName, showJump
end


--- How far the horse's hooves are above the top of what is under its legs: negative when its
--- legs are down in it. Nil with nothing JUMP_MIN_HEIGHT tall under them.
--- @param vehicle table
--- @return number|nil metres, number|nil the collision it is over the least, number|nil world x
---   and number|nil z of that ray
local function legClearance(vehicle)
    if raycastAll == nil or vehicle.rootNode == nil then return nil end
    local _, hoof, _ = getWorldTranslation(vehicle.rootNode)
    local least, leastNode, leastX, leastZ = nil, nil, nil, nil
    local function look(along, across)
        local x, y, z = localToWorld(vehicle.rootNode, across, 0, along)
        local height, _, _, top, node = obstacleAt(vehicle, x, y, z, EqTrainingHooks.CLIP_RAY_UP)
        if height ~= nil and height >= EqTrainingHooks.JUMP_MIN_HEIGHT and (least == nil or hoof - top < least) then
            least, leastNode, leastX, leastZ = hoof - top, node, x, z
        end
    end
    for _, along in ipairs(EqTrainingHooks.JUMP_RAYS_ALONG) do
        if math.abs(along) <= EqTrainingHooks.CLIP_REACH then look(along, 0) end
    end
    for _, across in ipairs(EqTrainingHooks.JUMP_RAYS_ACROSS) do look(0, across) end
    return least, leastNode, leastX, leastZ
end


--- @param clearance number|nil from legClearance
--- @return boolean true when the legs clip the jump
function EqTrainingHooks.isClip(clearance)
    return clearance ~= nil and clearance < EqTrainingHooks.CLIP_CLEARANCE
end


--- @param result string|nil from EqTraining.knockCombo
local function popKnock(result)
    -- A knock only shows as the combo bar dropping: a "-3 s" popup read like losing stats.
    if result == "lost" then EqTrainingHud.pop("jumpLost") end
end


local judgeJump

--- Follow a jump through the air and judge it once the horse has landed and settled.
--- @param vehicle table
--- @param spec table spec_rideable
--- @param sheet table
--- @param worn boolean
local function trackJump(vehicle, spec, sheet, worn)
    local jump = spec.eqJump
    if jump == nil then return end
    local now = g_time or 0
    local age = now - jump.startedAt
    if (spec.haltTimer or 0) > 0 then jump.crashed = true end

    local height, name, showJump = obstacleBelow(vehicle)
    if jump.landedAt == nil then
        local inAir
        if spec.isOnGround ~= nil then
            inAir = not spec.isOnGround
        else
            inAir = age < EqTrainingHooks.JUMP_FALLBACK_MS
        end
        if inAir then
            jump.airborne = true
            -- Over (or by) one of our show jumps: only its poles falling make a rail (judgeJump).
            if jump.ours == nil then
                local ok, ours = EqLog.try("EqTrainingHooks.trackJump EqPoles.nearest", EqPoles.nearest, vehicle)
                if ok and ours ~= nil then jump.ours = ours end
            end
            if height ~= nil and height > jump.best then jump.best, jump.over = height, name end
            if showJump then jump.showJump = true end
            local clearance, node, hitX, hitZ = legClearance(vehicle)
            if clearance ~= nil and (jump.clearance == nil or clearance < jump.clearance) then jump.clearance = clearance end
            if EqTrainingHooks.isClip(clearance) then
                jump.clipped = true
                -- One of our show jumps' poles falls as it is hit (EqPoles).
                EqLog.try("EqTrainingHooks.trackJump EqPoles.onClip", EqPoles.onClip, node, vehicle, hitX, hitZ)
            end
            if age < EqTrainingHooks.JUMP_TIMEOUT_MS then return end
        elseif not jump.airborne and age < 500 then
            return
        end
        jump.landedAt = now
    end

    -- Settling: standing on the obstacle or stopping dead after landing spoils the jump. Only
    -- on the ground: in the air again, the horse is over the next obstacle, not on this one.
    if spec.isOnGround ~= false and height ~= nil and height >= EqTrainingHooks.JUMP_MIN_HEIGHT then jump.onTop = true end
    local speed = math.abs(spec.currentSpeed or 0)
    if jump.speed > 0 and speed < jump.speed * EqTrainingHooks.JUMP_KNOCK_SPEED_SHARE then jump.knocked = true end
    if now - jump.landedAt < EqTrainingHooks.JUMP_SETTLE_MS then return end

    judgeJump(spec, sheet, worn, jump, speed, now, vehicle)
end


--- Score a landed jump: cleared, cleared with a knock, landed on top, or nothing under it.
--- @param spec table
--- @param sheet table
--- @param worn boolean
--- @param jump table spec.eqJump
--- @param speed number current speed, m/s
--- @param now number g_time
--- @param vehicle table
judgeJump = function(spec, sheet, worn, jump, speed, now, vehicle)
    local age = now - jump.startedAt
    spec.eqJump = nil
    local high = jump.best >= EqTrainingHooks.JUMP_MIN_HEIGHT
    local cleared = high and not jump.onTop and not jump.crashed and not jump.knocked
    local why = ""
    if high and not cleared then
        why = jump.crashed and ", crashed" or jump.knocked and ", hit it (slowed from %.1f to %.1f m/s)" or ", landed on top of it"
        why = string.format(why, jump.speed, speed)
    end
    local legs = jump.clearance ~= nil and string.format(", hooves %.2f m over its top%s", jump.clearance, jump.clipped and ": clipped" or "") or ""
    Log:info("Jump: %s (tallest thing under the horse %.2f m '%s'%s%s%s, %d ms, ground flag %s, take-off at a %s)",
        cleared and "cleared" or (high and not jump.onTop) and "cleared with a knock" or "nothing cleared", jump.best, tostring(jump.over),
        jump.showJump and ", a show jump" or "", why, legs, age, tostring(spec.isOnGround ~= nil), tostring(jump.gait))
    -- A show jumping round (EqCourseHooks) hears how the fence went: the horse's legs clipping
    -- the jump, knocking it or landing on top of it is a rail, whatever the jump is (a show jump
    -- or anything flagged). A crash (into the arena wall, say) is no rail unless the legs
    -- clipped the jump on the way: running into things is penalty enough (James, 2026-10-27).
    -- Over one of our show jumps only a pole falling is a rail, as in a real round (James,
    -- 2026-10-29: poles knocked with no fault, faults with no pole down): the pole tells the
    -- round itself (EqPoles.knock), so the jump only says the fence is done.
    local rail = high and (jump.clipped or (not jump.crashed and (jump.knocked or jump.onTop)))
    if jump.ours ~= nil then rail = false end
    EqCourseHooks.onJumpJudged(cleared and "clear" or rail and "knock" or "nothing")
    if cleared then
        local mult = EqTraining.clearJump(sheet, worn, jump.showJump)
        if mult ~= nil then EqTrainingHud.pop("jump", mult) end
    elseif high and not jump.onTop then
        -- Hitting the obstacle on the way over costs combo time, but the jump still counts
        -- unless that ran the combo out (clearJump then refuses it).
        local knock = EqTraining.knockCombo(sheet)
        local mult = knock ~= "lost" and EqTraining.clearJump(sheet, worn, jump.showJump) or nil
        if mult ~= nil then EqTrainingHud.pop("jump", mult) else popKnock(knock) end
    elseif high then
        -- Landing on top of the obstacle doesn't count, and costs combo time.
        popKnock(EqTraining.knockCombo(sheet))
    else
        EqTraining.emptyJump(sheet, worn)
    end
end


--- The routine's name for what the horse is doing: a gait, a halt, or a turn at a walk or trot.
--- @param vehicle table
--- @param spec table
--- @return string|nil steer left or right while the rider holds a steering key
local function steerInput(spec)
    -- axisSteer is the local rider's key; on a server the remote rider's comes as axisSteerSend.
    -- The base game may clear both once it has used them, so fall back on the turn rate it set
    -- from them (currentTurnSpeed, positive turning left; it follows the key, not the heading).
    local values = spec.inputValues
    local axis, source = values.axisSteer or 0, "axisSteer"
    if axis == 0 then axis, source = values.axisSteerSend or 0, "axisSteerSend" end
    if axis == 0 and type(spec.currentTurnSpeed) == "number" and (spec.maxTurnSpeed or 0) > 0 then
        axis, source = -spec.currentTurnSpeed / spec.maxTurnSpeed, "currentTurnSpeed"
    end
    local steer = nil
    if axis <= -EqTrainingHooks.STEER_MIN then steer = "left" elseif axis >= EqTrainingHooks.STEER_MIN then steer = "right" end
    if steer ~= spec.eqSteer and steer ~= nil then
        Log:info("Steer: %s from %s (axisSteer %s, axisSteerSend %s, currentTurnSpeed %s)", steer, source,
            tostring(values.axisSteer), tostring(values.axisSteerSend), tostring(spec.currentTurnSpeed))
    end
    if not EqTrainingHooks.loggedInputs then
        EqTrainingHooks.loggedInputs = true
        for key, value in pairs(values) do Log:info("Rideable input %s = %s", tostring(key), tostring(value)) end
    end
    spec.eqSteer = steer
    return steer
end


--- @return boolean true when the routine runs: it only asks for moves where the rider sees them
local function routineShown()
    local view = EqTrainingHooks.getView()
    return view == "freestyle" or view == "temperament" or view == "condensed"
end


-- A jump (and the stumble after landing) can knock the gait or speed down for a moment. A
-- rider sometimes has to jump to keep the pace, so exertion (and the jump combo clock) carry on
-- at the gait from before take-off until this long after landing.
EqTrainingHooks.JUMP_PACE_HOLD_MS = 1500

local PACE_GAITS = { trot = true, canter = true, gallop = true }

--- @param spec table
--- @param gait string the gait this frame
--- @param now number g_time
--- @return string gait for exertion and the jump combo
local function paceGait(spec, gait, now)
    local held = spec.eqJumpGait
    if held == nil or not PACE_GAITS[held] then return gait end
    if spec.eqJump == nil and now > (spec.eqJumpHoldUntil or 0) then
        spec.eqJumpGait = nil
        return gait
    end
    return held
end


-- The base game's jump has the same lift (spec_rideable.jumpHeight, 2 m) at every gait, so a
-- canter (top speed 5 m/s against the gallop's 10) covers about half the distance and often
-- lands on the obstacle. A canter jumps CANTER_JUMP_SHARE higher, for longer in the air, and
-- the horse speeds up ACCELERATION_SHARE faster (maxAcceleration, 5 m/s2 in the base game) so
-- switching between canter and gallop is quicker. On top of that the horse's stats change how
-- it rides (EqTraining.handling): speed sets its top speeds, agility its jump and turn rate,
-- temperament its acceleration and how long it stands after a crash.
EqTrainingHooks.CANTER_JUMP_SHARE = 1.65
EqTrainingHooks.ACCELERATION_SHARE = 1.6
-- The base game launches a jump at sqrt(2 g jumpHeight) up (spec_rideable.currentSpeedY, 6.4 m/s
-- for 2.1 m) and lets it fall at 9.81 m/s2: 1.3 s in the air, 16 m long at 12 m/s, so a jump
-- floats. We pull a horse in the air down GRAVITY_SHARE times as hard, and raise jumpHeight by
-- the same share so it still reaches the same height: the jump takes 1/sqrt(GRAVITY_SHARE) as long.
-- James found 2 great but asked for a touch more float: 1.65 is 10% longer in the air.
EqTrainingHooks.GRAVITY = 9.81
EqTrainingHooks.GRAVITY_SHARE = 1.65
-- A real horse picks where to land: in the air it turns this many times as fast as on the ground.
EqTrainingHooks.AIR_TURN_SHARE = 1.6
-- The base game hardly turns a horse in the air however fast it may (James, 2026-10-27: still
-- super sluggish), so while A or D is held in the air we turn it ourselves as well, at this
-- share of its ground turn rate.
EqTrainingHooks.AIR_TURN_EXTRA = 1.2

--- Turn the horse in the air from the steering keys (A left, D right), on top of the base game.
--- @param spec table spec_rideable
--- @param dt number ms
function EqTrainingHooks.airTurn(spec, dt)
    if type(spec.currentTurnAngle) ~= "number" or spec.eqBaseTurnSpeed == nil then return end
    local axis = spec.inputValues ~= nil and (spec.inputValues.axisSteer or 0) or 0
    if axis == 0 and Input ~= nil and Input.isKeyPressed ~= nil and Input.KEY_a ~= nil and Input.KEY_d ~= nil then
        axis = (Input.isKeyPressed(Input.KEY_d) and 1 or 0) - (Input.isKeyPressed(Input.KEY_a) and 1 or 0)
    end
    if axis == 0 then return end
    -- currentTurnAngle grows turning left; a right axis is positive.
    spec.currentTurnAngle = spec.currentTurnAngle - axis * spec.eqBaseTurnSpeed * EqTrainingHooks.AIR_TURN_EXTRA * dt / 1000
    if not spec.eqAirTurnLogged then
        spec.eqAirTurnLogged = true
        Log:info("Air turn: steering %s in the air (axisSteer %s)", axis > 0 and "right" or "left", tostring(spec.inputValues.axisSteer))
    end
end

--- Set the base game's jump height, acceleration, top speeds and turn rate for the gait and
--- the horse, before it jumps. The base values are kept on the spec the first time.
--- @param spec table spec_rideable
--- @param gait string
--- @param record table|nil the ridden horse's EqHorseRecord
--- @param sheet table the horse's training sheet (its exertion sets the gallop's pace)
local function tuneRiding(spec, gait, record, sheet)
    local trained = record ~= nil and record.trained or {}
    local handling = EqTraining.handling(trained.speed, trained.agility, trained.temperament)
    if type(spec.jumpHeight) == "number" then
        spec.eqBaseJumpHeight = spec.eqBaseJumpHeight or spec.jumpHeight
        spec.jumpHeight = spec.eqBaseJumpHeight * handling.jump * (gait == "canter" and EqTrainingHooks.CANTER_JUMP_SHARE or 1)
            * EqTrainingHooks.GRAVITY_SHARE
    end
    if type(spec.maxAcceleration) == "number" then
        spec.eqBaseAcceleration = spec.eqBaseAcceleration or spec.maxAcceleration
        spec.maxAcceleration = spec.eqBaseAcceleration * EqTrainingHooks.ACCELERATION_SHARE * handling.acceleration
    end
    spec.eqCrashHaltMs = EqTrainingHooks.CRASH_HALT_MS * handling.crashHalt

    if type(spec.maxTurnSpeed) == "number" then
        spec.eqBaseTurnSpeed = spec.eqBaseTurnSpeed or spec.maxTurnSpeed
        spec.maxTurnSpeed = spec.eqBaseTurnSpeed * handling.turn
    end
    -- Above a walk the base game turns no tighter than each gait's minimum radius, so the turn
    -- rate alone hardly shows (James, 2026-10-27): the radii shrink by the same factor.
    if type(spec.minTurnRadius) == "table" then
        if spec.eqBaseTurnRadius == nil then
            spec.eqBaseTurnRadius, spec.minTurnRadius = spec.minTurnRadius, {}
            local listed = {}
            for key, value in pairs(spec.eqBaseTurnRadius) do
                spec.minTurnRadius[key] = value
                table.insert(listed, string.format("%s=%s", tostring(key), tostring(value)))
            end
            Log:info("Base turn radii: %s", table.concat(listed, ", "))
        end
        for key, value in pairs(spec.eqBaseTurnRadius) do
            if type(value) == "number" then spec.minTurnRadius[key] = value / handling.turn end
        end
    end
    if type(spec.topSpeeds) == "table" then
        if spec.eqBaseTopSpeeds == nil then
            -- Our own table, in case the base game shares one between horses.
            spec.eqBaseTopSpeeds, spec.topSpeeds = spec.topSpeeds, {}
            for key, value in pairs(spec.eqBaseTopSpeeds) do spec.topSpeeds[key] = value end
        end
        -- Forward gaits only: backing up stays at the base game's pace. The gallop's pace
        -- (Recovering, Pushing, Sprinting) sets its share of the gallop's speed.
        local pace = EqExertion.speedShare(sheet.exertion)
        local gallop = Rideable.GAITTYPES ~= nil and Rideable.GAITTYPES.GALLOP or nil
        for key, value in pairs(spec.eqBaseTopSpeeds) do
            if type(value) == "number" then
                local share = key == gallop and pace or 1
                spec.topSpeeds[key] = value > 0 and value * handling.speed * share or value
            end
        end
    end
    local shown = string.format("%s/%s/%s", tostring(trained.speed), tostring(trained.agility), tostring(trained.temperament))
    if spec.eqHandlingFor ~= shown then
        spec.eqHandlingFor = shown
        Log:info("Handling: speed %.0f (top speeds x%.2f), agility %.0f (jump x%.2f, turn rate x%.2f), "
            .. "temperament %.0f (acceleration x%.2f, crash stop %d ms)",
            trained.speed or 50, handling.speed, trained.agility or 50, handling.jump, handling.turn,
            trained.temperament or 50, handling.acceleration, math.floor(spec.eqCrashHaltMs))
    end
end


--- Appended to Rideable:updateRiding (server, every frame while ridden).
function EqTrainingHooks.onUpdateRiding(vehicle, dt)
    local spec = vehicle.spec_rideable
    if spec == nil then return end
    -- Dressage markers lose their collision while anyone rides.
    EqDressageHooks.ridingSeen = g_time

    local id = getRiddenId(spec)
    if id == nil then return end
    local record = EqRegistry.getById(id)
    local sheet = EqTrainingHooks.getSheet(id)
    -- Nobody in the saddle (the rider got off or switched to another horse or vehicle; the
    -- base game still updates a horse left out): a routine or test ends at once, the jump
    -- combo goes and nothing trains (James, 2026-10-27: a test ran on, faulting, while he was
    -- on another horse).
    if vehicle.getIsControlled ~= nil and not vehicle:getIsControlled() then
        local ended = EqTraining.breakRoutine(sheet)
        if EqTraining.loseCombo(sheet) or ended then Log:info("Rider left the horse: routine and jump combo ended") end
        return
    end
    -- First undo a gait change the exertion system doesn't allow (the base game may have made
    -- it this frame), so the gait below is the one the horse keeps.
    EqTrainingHooks.keepGait(spec, sheet.exertion)

    local gait = getGaitNames()[spec.inputValues.currentGait]
    if gait == nil or math.abs(spec.currentSpeed or 0) < 0.05 then gait = "halt" end
    -- Not while airborne, so the lift a jump started with stays put.
    if spec.eqJump == nil then tuneRiding(spec, gait, record, sheet) end
    -- In the air: an extra pull down (see GRAVITY_SHARE) and snappier turning (AIR_TURN_SHARE).
    local airborne = spec.isOnGround == false
    if airborne and type(spec.currentSpeedY) == "number" then
        spec.currentSpeedY = spec.currentSpeedY - EqTrainingHooks.GRAVITY * (EqTrainingHooks.GRAVITY_SHARE - 1) * dt / 1000
    end
    if spec.eqBaseTurnSpeed ~= nil and airborne ~= spec.eqAirborne then
        local handling = EqTraining.handling(record ~= nil and record.trained.speed or nil, record ~= nil and record.trained.agility or nil)
        spec.maxTurnSpeed = spec.eqBaseTurnSpeed * handling.turn * (airborne and EqTrainingHooks.AIR_TURN_SHARE or 1)
    end
    spec.eqAirborne = airborne
    EqExertion.setAir(sheet.exertion, airborne)
    if airborne then EqTrainingHooks.airTurn(spec, dt) end

    local now = g_time or 0
    local stamina = record ~= nil and record.trained.stamina or nil
    if sheet.clock ~= nil and now - sheet.clock > 1000 then EqTraining.rest(sheet, now - sheet.clock, stamina) end
    sheet.clock = now

    local worn = isTired(spec.cluster)
    local pace = paceGait(spec, gait, now)
    local ex = sheet.exertion
    local wasGalloping = EqExertion.isGalloping(ex)
    local event = EqExertion.step(ex, pace, dt, stamina, record ~= nil and record.trained.speed or nil)
    if event ~= nil then EqTrainingHooks.onExertionEvent(event, ex) end
    if not wasGalloping and EqExertion.isGalloping(ex) then Log:info("Exertion: galloping, pushing (exertion %.0f%%)", ex.value) end
    -- Stamina and speed train from how well the gallop is ridden.
    local speedMult, speedGain = EqTraining.speedStep(sheet, dt, worn)
    if speedMult ~= nil and ex.mode == "sprint" then
        Log:info("Speed: riding bar full mid-Sprint, banked at x%.1f (at %.0f%%), +%.3f effort", speedMult, ex.value, speedGain)
        EqTrainingHud.pop("speedBank", speedMult)
    elseif speedMult ~= nil then
        local last = ex.lastSprint or {}
        Log:info("Speed: Sprint banked at x%.1f (ended at %.0f%%%s), +%.3f effort", speedMult, last.value or 0,
            last.over and ", Fatigued" or "", speedGain)
        if not last.over then EqTrainingHud.pop("speedBank", speedMult) end
    end
    EqTraining.staminaStep(sheet, dt, worn)
    -- Blown or exhausted: down to a canter now, not next frame.
    EqTrainingHooks.keepGait(spec, ex)
    spec.eqLastGait = gait

    local wasJumping = spec.eqJump ~= nil
    EqPoles.noteRider(vehicle)
    trackJump(vehicle, spec, sheet, worn)
    if wasJumping and spec.eqJump == nil then spec.eqJumpHoldUntil = now + EqTrainingHooks.JUMP_PACE_HOLD_MS end

    -- The base game stops a horse that runs into something and counts its haltTimer down; we
    -- cut that stop short. A crash costs jump combo time and breaks a routine.
    local halted = (spec.haltTimer or 0) > 0
    if halted and not spec.eqHalted then
        local was = spec.haltTimer
        spec.haltTimer = math.min(spec.haltTimer, spec.eqCrashHaltMs or EqTrainingHooks.CRASH_HALT_MS)
        -- A jump still in the air or settling when the horse crashes did not clear.
        if spec.eqJump ~= nil then spec.eqJump.crashed = true end
        Log:info("Crash: the horse ran into something at a %s (haltTimer %s, cut to %s)", gait, tostring(was), tostring(spec.haltTimer))
        spec.eqCrashGraceUntil = now + EqTrainingHooks.CRASH_GRACE_MS
        -- Running into one of our show jumps knocks a pole off it (EqPoles): a rail, not a refusal.
        local ok, fell = EqLog.try("EqTrainingHooks crash EqPoles.onCrash", EqPoles.onCrash, vehicle)
        -- Running into the next fence of a show jumping round otherwise is a refusal (EqCourseHooks).
        if not (ok and fell) then EqCourseHooks.onCrash() end
        local knock = EqTraining.knockCombo(sheet)
        if EqTraining.breakRoutine(sheet) and knock == nil then EqTrainingHud.pop("routineLost") end
        popKnock(knock)
    end
    spec.eqHalted = halted
    -- Getting going again after a crash doesn't drain the combo at the slow-gait rate.
    local comboGait = now < (spec.eqCrashGraceUntil or 0) and "trot" or pace
    if EqTraining.comboTick(sheet, comboGait, dt, spec.eqJump ~= nil) then EqTrainingHud.pop("jumpLost") end
    local coursing = EqCourseHooks.isBusy()
    if routineShown() and not coursing then
        -- Near dressage markers the routine rides between them (EqDressage).
        local okCourse, course = EqLog.try("EqTrainingHooks.onUpdateRiding courseFor", EqDressageHooks.courseFor, vehicle, spec)
        local event = EqTraining.routineStep(sheet, gait, steerInput(spec), dt, worn, math.random, okCourse and course or nil)
        if event == "done" or event == "bonus" then EqTrainingHud.pop("routine", sheet.routine.mult)
        elseif event == "fault" then EqTrainingHud.pop("routineFault", sheet.routine.faults)
        elseif event == "test" then EqTrainingHud.pop("routineTest")
        elseif event == "lost" then EqTrainingHud.pop("routineLost") end
        if event ~= nil and sheet.routine.kind == "markers" then
            local task = sheet.routine.task
            Log:info("Dressage routine: %s x%d, now %s%s", event, sheet.routine.mult, tostring(sheet.routine.request),
                task ~= nil and task.marker ~= nil and string.format(" %s to %s", task.gait, task.marker.letter) or "")
        end
    elseif EqTraining.breakRoutine(sheet) and not coursing then
        EqTrainingHud.pop("routineLost")
    end

    local share = EqTraining.workStep(sheet, dt)
    if (share < 0.5) ~= (spec.eqCruising == true) then
        spec.eqCruising = share < 0.5
        Log:info("Riding bar: %s (%.0f%% of the usual rate)", spec.eqCruising and "easy riding" or "training", share * 100)
    end
    if worn or gait == "halt" then return end

    sheet.barFactor = EqTraining.ridingBarFactor(stamina)
    EqTraining.addRiding(sheet, gait, dt, share)
    adjustRiding(spec, gait, sheet.barFactor / share, dt)
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do EqTraining.addInside(sheet, kind, dt * share) end
end


--- Log, once a game, the base game's riding numbers that look like jump, speed or gait
--- settings, so canter jumps and gait changes can be tuned once we know their names.
local function logRideableFields(spec)
    if EqTrainingHooks.loggedRideable then return end
    EqTrainingHooks.loggedRideable = true
    local function dump(prefix, t, depth)
        local keys = {}
        for key in pairs(t) do if type(key) == "string" or type(key) == "number" then table.insert(keys, key) end end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do
            local value, name = t[key], prefix .. tostring(key)
            local lower = name:lower()
            -- Every number straight on the spec (looking for a gravity or fall speed for jumps),
            -- and the riding-looking ones in its tables.
            local wanted = depth == 0 or lower:find("jump") or lower:find("speed") or lower:find("gait") or lower:find("accel")
                or lower:find("decel") or lower:find("velocity") or lower:find("force") or lower:find("grav")
                or lower:find("fall") or lower:find("vertical")
            if (type(value) == "number" or type(value) == "boolean") and wanted then
                Log:info("Rideable field %s = %s", name, tostring(value))
            elseif type(value) == "table" and depth < 2 and key ~= "cluster" and key ~= "actionEvents" then
                dump(name .. ".", value, depth + 1)
            end
        end
    end
    dump("spec_rideable.", spec, 0)
end


--- The base game's gait, kept in line with the exertion system: down to a canter while the
--- horse is blown or exhausted, and back to the gait it had when a change isn't allowed (a gallop
--- that drops to a canter without a double tap, say). Called every frame and after every press.
--- @param spec table spec_rideable
--- @param ex table EqExertion state
function EqTrainingHooks.keepGait(spec, ex)
    local now = inputGait(spec)
    local last = spec.eqInputGait
    spec.eqInputGait = now
    if now == nil then return end
    local forced = EqExertion.forcedGait(ex)
    if forced ~= nil and now == "gallop" then
        setInputGait(spec, forced)
        spec.eqInputGait = forced
        return
    end
    if last ~= nil and last ~= now and not EqExertion.allowGait(ex, last, now) then
        setInputGait(spec, last)
        spec.eqInputGait = last
        Log:info("Gait: kept at %s (asked for %s, exertion %.0f%%, %s)", last, now, ex.value, tostring(ex.mode or ex.lock))
    end
end


--- Popups and log lines for what the exertion system did.
--- @param event string from EqExertion.step or EqExertion.press
--- @param ex table
function EqTrainingHooks.onExertionEvent(event, ex)
    Log:info("Exertion: %s (exertion %.0f%%)", event, ex.value)
    if event == "blown" or event == "spent" or event == "sprint" or event == "fresh" or event == "sprintOver" then
        EqTrainingHud.pop("ex_" .. event)
    end
end


-- The action and the key poll can both see one press, and an action may report a held key
-- every frame: a report of the same key this soon after the last one is the same press.
EqTrainingHooks.KEY_REPEAT_MS = 80
EqTrainingHooks.keyAt = {}

--- The base game ignores gait changes in the air, so a rider tapping to slow down after a jump
--- had to wait for the landing and then overshot (James, 2026-10-27). A forward or back press in
--- the air is queued instead, shown lit on the gait bar, and made the moment the horse lands
--- (applyQueuedGait). Not while galloping, where the keys set the pace, except in a jump from
--- the bottom third of the gallop (EqExertion.airQueue): then a slower gait is queued too, and
--- made on landing once exertion is down to the canter line.
--- @param spec table spec_rideable
--- @param key string "forward" or "back"
--- @param ex table|nil the horse's exertion
function EqTrainingHooks.queueGait(spec, key, ex)
    local types = Rideable.GAITTYPES
    local current = spec.inputValues.currentGait
    if types == nil or current == nil then return end
    if current == types.GALLOP and (ex == nil or not EqExertion.airQueue(ex)) then return end
    local queued = spec.eqQueuedGait
    if queued == nil then
        queued = { from = current, steps = 0 }
        spec.eqQueuedGait = queued
    end
    queued.steps = queued.steps + (key == "forward" and 1 or -1)
    local low = types.STILL or types.WALK
    queued.target = math.max(low, math.min(types.GALLOP, queued.from + queued.steps))
    Log:info("Gait: %s in the air, %s on landing", key, tostring(getGaitNames()[queued.target] or queued.target))
end


--- Make a queued gait change once the horse is on the ground. Called every frame while drawing.
--- @param spec table spec_rideable
function EqTrainingHooks.applyQueuedGait(spec, ex)
    local queued = spec.eqQueuedGait
    if queued == nil or spec.isOnGround == false then return end
    local types = Rideable.GAITTYPES
    if types ~= nil and queued.from == types.GALLOP and queued.target < types.GALLOP and ex ~= nil then
        -- Out of a gallop only once exertion is at the canter line; else the queue goes after
        -- AIR_CANTER_MS and the horse gallops on.
        local now = g_time or 0
        queued.landedAt = queued.landedAt or now
        if ex.value > 0 or ex.clock > ex.dropUntil then
            if now - queued.landedAt > EqExertion.AIR_CANTER_MS then
                spec.eqQueuedGait = nil
                Log:info("Gait: landed at exertion %.0f%%, still galloping", ex.value)
            end
            return
        end
    end
    spec.eqQueuedGait = nil
    if spec.inputValues.currentGait ~= queued.target then
        spec.inputValues.currentGait = queued.target
        Log:info("Gait: landed, now %s", tostring(getGaitNames()[queued.target] or queued.target))
    end
end


--- Forward (W) or back (S): the gallop's pace. Every other key is none of its business.
--- @param vehicle table
--- @param key string "forward" or "back"
--- @param source string what saw it, for the log
function EqTrainingHooks.onGaitKey(vehicle, key, source)
    local now = g_time or 0
    local last = EqTrainingHooks.keyAt[key]
    EqTrainingHooks.keyAt[key] = now
    if last ~= nil and now - last < EqTrainingHooks.KEY_REPEAT_MS then return end
    local spec = vehicle.spec_rideable
    local id = spec ~= nil and getRiddenId(spec) or nil
    local sheet = id ~= nil and EqTrainingHooks.getSheet(id) or nil
    if spec ~= nil and spec.inputValues ~= nil and spec.isOnGround == false then
        EqTrainingHooks.queueGait(spec, key, sheet ~= nil and sheet.exertion or nil)
    end
    if sheet == nil then return end
    local event = EqExertion.press(sheet.exertion, key)
    if event == "tap" then return end
    if event ~= nil then
        Log:info("Gallop key: %s from %s", key, source)
        EqTrainingHooks.onExertionEvent(event, sheet.exertion)
    end
end


-- Wrapped round the base game's forward and back key actions: the press picks the gallop's pace
-- first (beforeGaitAction), then the base game changes gait, and keepGait undoes a change that
-- isn't allowed (afterGaitAction).

--- @param vehicle table
--- @param key string "forward" or "back"
--- @param inputValue number|nil
function EqTrainingHooks.beforeGaitAction(vehicle, key, inputValue)
    local spec = vehicle.spec_rideable
    if spec == nil or spec.inputValues == nil then return end
    if (inputValue or 0) > 0 then EqTrainingHooks.onGaitKey(vehicle, key, key .. " action") end
    spec.eqInputGait = inputGait(spec)
end


--- @param vehicle table
function EqTrainingHooks.afterGaitAction(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil or spec.inputValues == nil then return end
    local id = getRiddenId(spec)
    local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
    if sheet ~= nil then EqTrainingHooks.keepGait(spec, sheet.exertion) end
end


--- The W and S keys themselves, polled while drawing, in case the actions don't reach us at
--- every gait. Only a fresh press counts.
--- @param vehicle table
local function pollGaitKeys(vehicle)
    local spec = vehicle.spec_rideable
    if spec ~= nil and spec.inputValues ~= nil then
        local id = getRiddenId(spec)
        local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
        EqTrainingHooks.applyQueuedGait(spec, sheet ~= nil and sheet.exertion or nil)
    end
    if Input == nil or Input.isKeyPressed == nil or Input.KEY_w == nil then return end
    local down = Input.isKeyPressed(Input.KEY_w) == true
    if down and not EqTrainingHooks.wWasDown then EqTrainingHooks.onGaitKey(vehicle, "forward", "W key") end
    EqTrainingHooks.wWasDown = down
    if Input.KEY_s == nil then return end
    down = Input.isKeyPressed(Input.KEY_s) == true
    if down and not EqTrainingHooks.sWasDown then EqTrainingHooks.onGaitKey(vehicle, "back", "S key") end
    EqTrainingHooks.sWasDown = down
end


--- Appended to Rideable:jump (the server branch: in multiplayer a client's JumpEvent calls it
--- on the server). The jump is judged in the air by trackJump; any jump ends a routine, but the
--- gallop keeps its pace through it (paceGait).
function EqTrainingHooks.onJump(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil then return end

    local id = getRiddenId(spec)
    if id == nil then return end

    local sheet = EqTrainingHooks.getSheet(id)
    -- Jumping again before the last jump has settled: judge that one now, so a quick double
    -- counts both.
    local last = spec.eqJump
    if last ~= nil and last.landedAt ~= nil then
        judgeJump(spec, sheet, isTired(spec.cluster), last, math.abs(spec.currentSpeed or 0), g_time or 0, vehicle)
    end
    EqTraining.addJump(sheet)
    if EqTraining.breakRoutine(sheet) then EqTrainingHud.pop("routineLost") end
    spec.eqJump = { startedAt = g_time or 0, best = 0, airborne = false, speed = math.abs(spec.currentSpeed or 0), gait = spec.eqLastGait }
    spec.eqJumpGait, spec.eqJumpHoldUntil = spec.eqLastGait, nil
    EqLog.try("EqTrainingHooks.onJump logRideableFields", logRideableFields, spec)
end


-- Riding HUD views, switched with the training view key (Y). Freestyle shows every stat; a
-- focused view shows only its own stat's training (Stamina and Speed the gallop's multipliers
-- and keys, Agility the jump combo, Temperament the routine); Condensed shows just the bar, with
-- news in a small line above it (James, 2026-10-27: the panel was too busy). Every view trains
-- everything. Help popups (H, and the first time a view opens) explain each view in HELP_PAGES pages.
EqTrainingHooks.VIEWS = { "freestyle", "stamina", "speed", "agility", "temperament", "condensed" }
-- "gallop" pops up the first time the horse gallops, and on H while it gallops.
EqTrainingHooks.HELP_PAGES = { freestyle = 4, stamina = 2, speed = 2, agility = 2, temperament = 2, gallop = 4, form = 2 }
-- Views that show the gallop's training rows and keys under the bar.
EqTrainingHooks.GALLOP_VIEWS = { freestyle = true, stamina = true, speed = true }
-- The stats the player's riding trains.
EqTrainingHooks.TRAINED_STATS = { "stamina", "speed", "agility", "temperament" }
EqTrainingHooks.viewIndex = 1


--- @return string view a VIEWS name
function EqTrainingHooks.getView()
    return EqTrainingHooks.VIEWS[EqTrainingHooks.viewIndex] or "freestyle"
end


--- @return string text for the action in the help panel
local function viewActionText()
    return string.format(g_i18n:getText("eq_train_viewAction"), g_i18n:getText("eq_train_view_" .. EqTrainingHooks.getView()))
end


--- Show a view's help popups.
--- @param view string
function EqTrainingHooks.showHelp(view)
    local pages = {}
    local title = g_i18n:getText("eq_help_" .. view .. "_title")
    for i = 1, EqTrainingHooks.HELP_PAGES[view] or 0 do
        table.insert(pages, { title = title, text = g_i18n:getText(string.format("eq_help_%s_%d", view, i)),
            color = EqTrainingHud.STAT_COLOR[view] or EqTrainingHud.COLOR.white })
    end
    EqTrainingHud.showHelp(pages, nil, view)
end


--- The help key was pressed: the gallop's help while galloping, else the view's.
--- @param vehicle table
function EqTrainingHooks.onHelpAction(vehicle)
    local spec = vehicle.spec_rideable
    local id = spec ~= nil and getRiddenId(spec) or nil
    local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
    local ex = sheet ~= nil and sheet.exertion or nil
    local galloping = ex ~= nil and (EqExertion.isGalloping(ex) or ex.lock ~= nil)
    EqTrainingHooks.showHelp(galloping and "gallop" or EqTrainingHooks.getView())
end


--- The training view key was pressed.
function EqTrainingHooks.onViewAction(vehicle)
    EqTrainingHooks.viewIndex = EqTrainingHooks.viewIndex % #EqTrainingHooks.VIEWS + 1
    local spec = vehicle.spec_rideable
    local event = spec ~= nil and spec.eqViewEventId or nil
    if event ~= nil then g_inputBinding:setActionEventText(event, viewActionText()) end
    EqTrainingHud.closeHelp()
end


--- Appended to Rideable:onRegisterActionEvents: the training view and help keys while riding.
function EqTrainingHooks.onRegisterActionEvents(vehicle, isActiveForInputIgnoreSelection)
    local spec = vehicle.spec_rideable
    if spec == nil or spec.actionEvents == nil or InputAction.EQ_TRAINING_VIEW == nil then return end
    spec.eqViewEventId = nil
    if not isActiveForInputIgnoreSelection then
        EqTrainingHud.closeHelp()
        return
    end
    local _, id = vehicle:addActionEvent(spec.actionEvents, InputAction.EQ_TRAINING_VIEW, vehicle,
        function() EqTrainingHooks.onViewAction(vehicle) end, false, true, false, true, nil)
    if id ~= nil then
        spec.eqViewEventId = id
        g_inputBinding:setActionEventText(id, viewActionText())
        g_inputBinding:setActionEventTextPriority(id, GS_PRIO_NORMAL)
    end
    -- Show jumping course keys (EqCourseHooks).
    EqCourseHooks.registerActions(vehicle, spec)
    if InputAction.EQ_TRAINING_HELP ~= nil then
        local _, helpId = vehicle:addActionEvent(spec.actionEvents, InputAction.EQ_TRAINING_HELP, vehicle,
            function() EqTrainingHooks.onHelpAction(vehicle) end, false, true, false, true, nil)
        if helpId ~= nil then
            g_inputBinding:setActionEventText(helpId, g_i18n:getText("input_EQ_TRAINING_HELP"))
            g_inputBinding:setActionEventTextPriority(helpId, GS_PRIO_LOW)
        end
    end
end


local COLOR = EqTrainingHud.COLOR
-- Status colours never borrow a stat's colour (EqTrainingHud.STAT_COLOR): white is good,
-- yellow a warning, red bad, grey idle.
local STAT_COLOR = EqTrainingHud.STAT_COLOR


--- A dressage command as text: "Trot: Marker B", "Stop!", "Turn left on the spot!".
--- @param task table
--- @return string
local function dressageText(task)
    if task.untimed then
        return string.format(g_i18n:getText("eq_dressage_begin"), task.marker.letter)
    end
    if task.kind == "go" then
        return string.format(g_i18n:getText("eq_dressage_go"), g_i18n:getText("eq_dressage_gait_" .. task.gait), task.marker.letter)
    end
    if task.kind == "reverse" then return g_i18n:getText("eq_dressage_reinBack") end
    if task.kind == "circle" then return g_i18n:getText("eq_dressage_circle_" .. task.side) end
    return g_i18n:getText("eq_move_" .. EqDressage.requestName(task))
end


--- The routine round dressage markers: its panel rows and the command in the middle.
--- @param rows table panel rows to add to
--- @param routine table
--- @param vehicle table the ridden horse
local function dressageRows(rows, routine, vehicle)
    local color = STAT_COLOR.temperament
    local task = routine.task
    local row = { left = string.format(g_i18n:getText("eq_train_routine"), routine.mult), leftColor = color }
    table.insert(rows, row)
    if task == nil then return end
    if task.kind == "hold" then
        row.right, row.rightColor = g_i18n:getText("eq_dressage_stand"), COLOR.grey
        return
    end
    local share = math.max(0, routine.deadline - routine.clock) / (routine.reactMs or EqDressage.REACT_MS)
    if task.kind == "reverse" and (task.backMs or 0) > 0 then share = 1 - task.backMs / EqDressage.REVERSE_MS end
    local text = dressageText(task)
    if task.kind == "go" then
        row.right, row.rightColor = task.marker.letter, color
        if vehicle.rootNode ~= nil then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            row.right = string.format("%s  %.0f m", task.marker.letter, math.sqrt((task.marker.x - x) ^ 2 + (task.marker.z - z) ^ 2))
        end
    end
    if task.kind == "reverse" then
        row.right, row.rightColor = g_i18n:getText("eq_dressage_backwards"), color
    elseif task.kind == "circle" then
        row.right, row.rightColor = string.format("%d°", math.floor(math.deg(task.turned or 0))), color
    end
    if task.untimed then share = nil end
    if share ~= nil then table.insert(rows, { bar = share, color = color }) end
    if routine.preview ~= nil then
        table.insert(rows, { left = string.format(g_i18n:getText("eq_dressage_next"), dressageText(routine.preview)), leftColor = color })
    end
    -- Out of the arena: getting back in comes first. Then a quick gait change on the way, while it lasts.
    if (routine.outMs or 0) > 0 then
        EqTrainingHud.drawPrompt(g_i18n:getText("eq_dressage_out"), 1 - routine.outMs / EqDressage.OUT_MS, COLOR.red or color)
    elseif routine.bonus ~= nil then
        EqTrainingHud.drawPrompt(string.format(g_i18n:getText(EqDressage.changeKey(routine.bonus)), g_i18n:getText("eq_dressage_gait_" .. routine.bonus.gait)),
            math.max(0, routine.bonus.deadline - routine.clock) / EqDressage.PASS_REACT_MS, color)
    elseif task.untimed then
        -- "Move to A to begin": not an alert, so beside the panel, not in the middle.
        EqTrainingHud.drawPanelNote(text, color, true)
    else
        EqTrainingHud.drawPrompt(text, share, color)
    end
end


-- The exertion bar's sections (James's drawing, 2026-10-27), each { from, to, colour when dim,
-- colour when lit }. A gait's section lights while the horse is in it; the gallop's lights in
-- every pace; Fatigued lights while the horse is blown or exhausted.
local BAR = EqExertion.BAR
EqTrainingHooks.BAR_SECTIONS = {
    halt = { BAR.reverse, BAR.halt, { 0.6, 0.8, 0.98 }, { 0.45, 0.75, 1 } },
    walk = { BAR.halt, BAR.walk, { 0.92, 0.98, 0.92 }, { 1, 1, 1 } },
    trot = { BAR.walk, BAR.trot, { 0.75, 1, 0.78 }, { 0.6, 1, 0.65 } },
    canter = { BAR.trot, BAR.canter, { 0.6, 0.98, 0.66 }, { 0, 1, 0 } },
    gallop = { BAR.canter, BAR.line, { 0.91, 0.95, 0.6 }, { 0.97, 0.97, 0.25 } },
    blown = { BAR.line, BAR.finish, { 0.8, 0.62, 0.62 }, { 0.85, 0.18, 0.18 } },
}
EqTrainingHooks.BAR_ORDER = { "halt", "walk", "trot", "canter", "gallop", "blown" }
EqTrainingHooks.BAR_DIM_ALPHA = 0.4
-- A Sprint lights the gallop amber.
EqTrainingHooks.BAR_SPRINT = { 1, 0.72, 0.2 }
-- Above this exertion while Pushing, the words turn yellow and the middle of the screen says to ease off.
EqTrainingHooks.EASE_OFF_FROM = 85
-- How quickly the marker slides to where it should be, in milliseconds.
EqTrainingHooks.MARKER_EASE_MS = 120

--- The exertion rows: what the horse is doing and how hard it's working, then the bar.
--- @param spec table spec_rideable
--- @param sheet table the horse's training sheet
--- @param view string
--- @return table rows
local function exertionRows(spec, sheet, view)
    local ex = sheet.exertion
    local gait = spec.eqLastGait or "halt"
    local state = EqExertion.state(ex, gait)
    -- Standing lights nothing; backing up lights the first section.
    local lit = { [gait == "reverse" and "halt" or gait] = gait ~= "halt" }
    if ex.mode ~= nil then lit.gallop = true end
    if ex.lock ~= nil or ex.value > EqExertion.LINE then lit.blown = true end
    -- A gait change asked for in the air lights the gait the horse will land into.
    local queued = spec.eqQueuedGait
    local queuedName = queued ~= nil and getGaitNames()[queued.target] or nil
    if queuedName ~= nil and EqTrainingHooks.BAR_SECTIONS[queuedName] ~= nil then lit[queuedName] = true end

    local color = COLOR.grey
    if ex.lock ~= nil or ex.value > EqExertion.LINE then
        color = COLOR.red
    elseif ex.mode == "push" and ex.value >= EqTrainingHooks.EASE_OFF_FROM then
        color = COLOR.yellow
    elseif ex.mode ~= nil then
        color = COLOR.white
    end
    local words = { left = g_i18n:getText("eq_ex_" .. state), leftColor = color,
        right = string.format("%s %d%%", g_i18n:getText("eq_train_tiredness"), math.floor(ex.value + 0.5)), rightColor = color }

    local sections = {}
    for _, name in ipairs(EqTrainingHooks.BAR_ORDER) do
        local section = EqTrainingHooks.BAR_SECTIONS[name]
        local rgb = lit[name] and section[4] or section[3]
        if lit[name] and name == "gallop" and ex.mode == "sprint" then rgb = EqTrainingHooks.BAR_SPRINT end
        table.insert(sections, { section[1], section[2], { rgb[1], rgb[2], rgb[3], lit[name] and 1 or EqTrainingHooks.BAR_DIM_ALPHA } })
    end

    -- The marker slides rather than jumps between the gait lines.
    local target = EqExertion.marker(ex, gait)
    local now = g_time or 0
    local step = math.min(1, math.max(0, now - (spec.eqMarkerAt or now)) / EqTrainingHooks.MARKER_EASE_MS)
    spec.eqMarker = spec.eqMarker == nil and target or spec.eqMarker + (target - spec.eqMarker) * step
    spec.eqMarkerAt = now

    local third = (BAR.line - BAR.canter) / 3
    local bar = { sections = sections, lines = { BAR.reverse, BAR.halt, BAR.walk, BAR.trot, BAR.canter, BAR.line, BAR.finish },
        ticks = { BAR.canter + third, BAR.canter + third * 2 }, marker = spec.eqMarker }
    if view == "condensed" then return { bar } end
    local rows = { words, bar }
    if EqTrainingHooks.GALLOP_VIEWS[view] then
        for _, row in ipairs(EqTrainingHooks.gallopTrainingRows(sheet, view)) do table.insert(rows, row) end
        local hint = EqTrainingHooks.exertionHints(ex)
        if hint ~= nil then table.insert(rows, hint) end
    end
    return rows
end


--- What the gallop is training, in one row: the stamina multiplier, and in a Sprint the speed
--- multiplier and what it will bank (EqTraining.staminaStep and speedStep). The Stamina and Speed
--- views always show their own, with the last Sprint's multiplier between Sprints.
--- @param sheet table
--- @param view string
--- @return table rows
function EqTrainingHooks.gallopTrainingRows(sheet, view)
    local ex, st = sheet.exertion, sheet.stamina
    local row = {}
    if view ~= "speed" and (view == "stamina" or ex.mode ~= nil or ex.lock ~= nil or st.mult > 1) then
        local training = ex.mode == "push" or ex.mode == "recover" or ex.mode == "sprint"
        row.left = ex.lock ~= nil and string.format("%s: %s", g_i18n:getText("eq_stat_stamina"), g_i18n:getText("eq_train_staminaStopped"))
            or string.format(g_i18n:getText("eq_train_staminaMult"), st.mult)
        row.leftColor = ex.lock ~= nil and COLOR.red or training and STAT_COLOR.stamina or COLOR.grey
    end
    -- Once a Sprint is paid out (the riding bar filled), its multiplier is no longer shown.
    if ex.mode == "sprint" and not sheet.sprint.cashed then
        local over = ex.value >= EqExertion.LINE
        local mult = EqTraining.sprintMultiplier(ex.value)
        local gain = EqTraining.SPEED_RATE * sheet.sprint.ms / 1000 * mult / EqTraining.EFFORT_CAP.speed * 100
        local color = over and COLOR.red or STAT_COLOR.speed
        local text = string.format(g_i18n:getText("eq_train_speedMult"), mult)
        if view == "speed" then
            row.left, row.leftColor = text, color
            row.right, row.rightColor = over and g_i18n:getText("eq_ex_fatigued") or string.format("+%d%%", math.floor(gain + 0.5)), color
        else
            row.right, row.rightColor = string.format("%s +%d%%", text, math.floor(gain + 0.5)), color
        end
    elseif view == "speed" then
        local last = sheet.sprint.last
        row.left = last ~= nil and string.format(g_i18n:getText("eq_train_lastSprint"), last) or g_i18n:getText("eq_train_sprintToTrain")
        row.leftColor = last ~= nil and STAT_COLOR.speed or COLOR.grey
    end
    if row.left == nil and row.right == nil then return {} end
    return { row }
end


--- What the rider can press now, in one row under the bar: Sprint on the left, canter on the right.
--- @param ex table
--- @return table|nil row
function EqTrainingHooks.exertionHints(ex)
    local left, leftColor, right = nil, COLOR.grey, nil
    if ex.mode == "push" or ex.mode == "recover" then
        if EqExertion.canSprint(ex) then
            left, leftColor = "eq_ex_hint_sprint", COLOR.white
        else
            left = "eq_ex_hint_sprintRest"
        end
    elseif ex.lock ~= nil then
        left = "eq_ex_hint_locked"
    end
    if ex.mode ~= nil then
        right = EqExertion.canterOnOneTap(ex) and "eq_ex_hint_canterOne" or "eq_ex_hint_canterDouble"
    end
    if left == nil and right == nil then return nil end
    return { left = left ~= nil and g_i18n:getText(left) or nil, leftColor = leftColor,
        right = right ~= nil and g_i18n:getText(right) or nil, rightColor = COLOR.grey }
end


--- The middle of the screen: keep tapping during a Sprint, ease off near the line.
--- @param ex table
-- For this long after a Sprint starts the middle says "Keep tapping W!"; then just its bar.
EqTrainingHooks.SPRINT_INTRO_MS = 1250
-- A Sprint climbs fast, so its warnings come early (James): a yellow "Tiring..." from
-- SPRINT_CAREFUL_FROM, a red flashing "Caution" from SPRINT_DANGER_FROM. Pushing warns from EASE_OFF_FROM.
EqTrainingHooks.SPRINT_CAREFUL_FROM = 50
EqTrainingHooks.SPRINT_DANGER_FROM = 75

--- @param small boolean the Condensed view: a smaller bar, no words
local function exertionPrompt(ex, small)
    local label, labelColor, pulse = nil, COLOR.yellow, false
    if ex.value > EqExertion.LINE then
        label, labelColor = g_i18n:getText("eq_ex_overExerted"), COLOR.red
    elseif ex.mode == "sprint" and ex.value >= EqTrainingHooks.SPRINT_DANGER_FROM then
        label, labelColor, pulse = g_i18n:getText("eq_ex_careful"), COLOR.red, true
    elseif ex.mode == "sprint" and ex.value >= EqTrainingHooks.SPRINT_CAREFUL_FROM then
        label = g_i18n:getText("eq_ex_tiring")
    elseif ex.mode ~= "sprint" and ex.value >= EqTrainingHooks.EASE_OFF_FROM then
        label, pulse = g_i18n:getText("eq_ex_tiring"), true
    end
    local warned = label ~= nil
    if small then label = nil end
    if ex.mode == "sprint" then
        local left = 1 - (ex.clock - ex.tapAt) / EqExertion.SPRINT_KEEP_MS
        local color = warned and labelColor or COLOR.white
        if ex.sprintMs < EqTrainingHooks.SPRINT_INTRO_MS and not small then
            EqTrainingHud.drawPrompt(g_i18n:getText("eq_ex_prompt_tap"), left, color)
        else
            EqTrainingHud.drawCentreBar(left, color, label, labelColor, pulse, small)
        end
    elseif ex.mode == "push" and warned then
        EqTrainingHud.drawCentreBar((EqExertion.LINE - ex.value) / (EqExertion.LINE - EqTrainingHooks.EASE_OFF_FROM),
            labelColor, label, labelColor, pulse, small)
    end
end


--- The top of the riding panel: the horse's skills, two to a line, "Stamina: 34 (+1)" with any
--- Peak form this month in brackets, so the rider remembers what this horse is being trained for
--- (its role is in the title). James (2026-10-27): no separate Peak form or effort lines.
--- @param cluster table|nil RLRM Animal being ridden
--- @return table rows
function EqTrainingHooks.horseRows(cluster)
    local rows = {}
    local record = cluster ~= nil and EqRegistry.getOrCreate(cluster) or nil
    if record == nil then return rows end
    -- Peak form comes with the Peak form feature (EqCompetitionManager.formFor), when it is there.
    local form = nil
    if EqCompetitionManager ~= nil and EqCompetitionManager.formFor ~= nil and EqTraining.hasForm ~= nil then
        form = EqCompetitionManager.formFor(record)
        if not EqTraining.hasForm(form) then
            form = nil
        elseif EqTrainingHooks.HELP_PAGES.form ~= nil and not EqTrainingHud.isHelpShowing() and not EqTrainingHud.hasSeen("form") then
            -- The first peak form explains itself, until its last page is clicked.
            EqTrainingHooks.showHelp("form")
        end
    end
    local segments
    for i, stat in ipairs(EqConstants.STAT_KEYS) do
        if i % 2 == 1 then
            segments = {}
            table.insert(rows, { segments = segments })
        end
        local boost = form ~= nil and math.floor((form[stat] or 0) + 0.5) or 0
        table.insert(segments, { g_i18n:getText("eq_stat_" .. stat) .. ":", STAT_COLOR[stat], at = i % 2 == 1 and 0 or 0.5, tight = true })
        table.insert(segments, { tostring(math.floor(record.trained[stat] or 0)), STAT_COLOR[stat], bold = true, tight = boost > 0 })
        if boost > 0 then table.insert(segments, { string.format("(+%d)", boost), STAT_COLOR[stat] }) end
    end
    return rows
end


--- Appended to Rideable:onDraw: the training panel, from the server's sheet, and the help popups.
function EqTrainingHooks.onDraw(vehicle, isActiveForInputIgnoreSelection)
    if not isActiveForInputIgnoreSelection then return end
    local spec = vehicle.spec_rideable
    if spec == nil then return end
    pollGaitKeys(vehicle)

    local view = EqTrainingHooks.getView()
    -- A first ride starts with the welcome; the view's help follows once it closes.
    if EqTrainingHooks.HELP_PAGES[view] ~= nil and not EqTrainingHud.isHelpShowing() and not EqWelcome.onRide()
        and not EqTrainingHud.hasSeen(view) then
        EqTrainingHooks.showHelp(view)
    end
    EqTrainingHud.drawHelp()
    -- Editing a show jumping course: recording, its line and the course keys (EqCourseHooks).
    EqCourseHooks.onDraw(vehicle)

    local id = getRiddenId(spec)
    local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
    if sheet == nil then return end

    local condensed = view == "condensed"
    local rows = condensed and {} or EqTrainingHooks.horseRows(spec.cluster)
    EqTrainingHud.view = view
    -- The exertion bar shows in every view: it says what gait the horse is in, too.
    local ex = sheet.exertion
    for _, row in ipairs(exertionRows(spec, sheet, view)) do table.insert(rows, row) end
    exertionPrompt(ex, condensed)
    if EqExertion.isGalloping(ex) and not EqTrainingHud.isHelpShowing() and not EqTrainingHud.hasSeen("gallop") then
        EqTrainingHud.markSeen("gallop")
        EqTrainingHooks.showHelp("gallop")
    end

    local combo = sheet.combo
    if combo.count > 0 and (view == "freestyle" or view == "agility") then
        local mult = math.min(combo.count, EqTraining.COMBO_MAX)
        local color = STAT_COLOR.agility
        table.insert(rows, { left = string.format(g_i18n:getText("eq_train_combo"), mult), leftColor = color,
            right = view == "agility" and string.format("%d s", math.ceil(combo.timer)) or nil })
        table.insert(rows, { bar = combo.timer / EqTraining.COMBO_SECONDS, color = color })
    elseif view == "agility" then
        table.insert(rows, { left = g_i18n:getText("eq_train_combo_none"), leftColor = COLOR.grey })
    end

    local routine = sheet.routine
    local onCourse = routineShown() and routine.active and routine.kind == "markers"
    -- The dressage test tags its next marker, else a show jumping round its next fence.
    if onCourse then
        EqDressageHooks.setTag(routine.task ~= nil and routine.task.marker or nil)
    else
        EqDressageHooks.setTag(EqCourseHooks.tagTarget())
    end
    -- A finished show jumping round pays agility training, unless the horse is worn out.
    local roundEffort = EqCourseHooks.takePayoff()
    if roundEffort > 0 and not isTired(spec.cluster) then sheet.focused.agility = sheet.focused.agility + roundEffort end
    EqCourseHooks.roundRows(rows)
    if onCourse then
        -- Condensed: no panel rows, but the rider still needs the commands.
        dressageRows(condensed and {} or rows, routine, vehicle)
    elseif routineShown() then
        if routine.active and condensed then
            if routine.request ~= nil then
                EqTrainingHud.drawPrompt(g_i18n:getText("eq_move_" .. routine.request),
                    math.max(0, routine.deadline - routine.clock) / (routine.reactMs or EqTraining.ROUTINE_REACT_MS), STAT_COLOR.temperament)
            end
        elseif routine.active then
            local color = STAT_COLOR.temperament
            local row = { left = string.format(g_i18n:getText("eq_train_routine"), routine.mult), leftColor = color }
            if routine.request ~= nil then
                local left = math.max(0, routine.deadline - routine.clock)
                row.right = g_i18n:getText("eq_move_" .. routine.request)
                row.rightColor = color
                table.insert(rows, row)
                table.insert(rows, { bar = left / (routine.reactMs or EqTraining.ROUTINE_REACT_MS), color = color })
                EqTrainingHud.drawPrompt(g_i18n:getText("eq_move_" .. routine.request), left / (routine.reactMs or EqTraining.ROUTINE_REACT_MS),
                    STAT_COLOR.temperament)
            else
                table.insert(rows, row)
                -- A command done at once still shows for a moment.
                if routine.shown ~= nil and routine.clock < (routine.shownUntil or 0) then
                    EqTrainingHud.drawPrompt(g_i18n:getText("eq_move_" .. routine.shown), 1, STAT_COLOR.temperament)
                end
            end
        elseif view == "temperament" then
            table.insert(rows, { left = g_i18n:getText("eq_train_routine_none"), leftColor = COLOR.grey })
        end
    end
    EqTrainingHud.drawPops()

    if isTired(spec.cluster) then table.insert(rows, { left = g_i18n:getText("eq_train_worn"), leftColor = COLOR.red }) end

    -- The ridden horse's name and role head the panel, the view on the right: Condensed has no title.
    local title, titleRight = nil, nil
    if not condensed then
        local cluster = spec.cluster
        local horseName = cluster ~= nil and cluster.getName ~= nil and cluster:getName() or nil
        title = (horseName ~= nil and horseName ~= "") and horseName or g_i18n:getText("eq_train_titlePlain")
        local record = cluster ~= nil and EqRegistry.getOrCreate(cluster) or nil
        if record ~= nil and EqRole.isShown(record) then
            title = string.format("%s (%s)", title, EqRole.text(EqRole.shown(record)))
        end
        titleRight = g_i18n:getText("eq_train_view_" .. view)
    end
    EqTrainingHud.drawPanel(title, rows, STAT_COLOR[view], titleRight)

    -- "Training in: Outdoor arena", then one line per bonus, in the base game's help panel.
    local inside = {}
    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do
        local facilityTitle, bonuses = EqFacilityHooks.insideText(kind, farmId)
        table.insert(inside, {title = facilityTitle, bonuses = bonuses})
    end
    table.sort(inside, function(x, y) return x.title < y.title end)
    for _, facility in ipairs(inside) do
        g_currentMission:addExtraPrintText(string.format(g_i18n:getText("eq_facility_inside"), facility.title))
        for _, bonus in ipairs(facility.bonuses) do g_currentMission:addExtraPrintText(bonus) end
    end
    local feedLine = EqFeedHooks.formatBoost(EqFeedHooks.getBoost(spec.cluster))
    if feedLine ~= nil then g_currentMission:addExtraPrintText(feedLine) end
end


--- Prepended to RLRM's AnimalHorse.processRidingUpdate: one day of training for one horse.
--- @param animal table RLRM Animal (a horse, not a sale animal)
function EqTrainingHooks.onHorseDay(animal)
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end

    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return end

    local sheet = EqTrainingHooks.sheets[record.id]
    EqTrainingHooks.sheets[record.id] = nil

    -- On box rest nothing trains: the day counts as idle, so the stats fade as they would.
    local resting = record.injury ~= nil
    local farmId = EqFacilityHooks.farmOfAnimal(animal)
    local owned, ridden = EqFacilityHooks.boostsFor(farmId, sheet)
    local day = {
        sheet = not resting and sheet or nil,
        riding = not resting and animal.riding or 0,
        dirt = animal.dirt,
        ageMonths = animal.age or 0,
        timeAdjustment = g_currentMission.environment.timeAdjustment or 1,
        facilityOwned = owned,
        facilityRidden = ridden,
        feedBoost = EqFeedHooks.getBoost(animal),
        rate = EqSettings.trainingRate(EqCompetitionManager.settings),
        staff = not resting and EqStaffManager.workFor(record, farmId) or nil,
    }
    local deltas, detail = EqTraining.applyDay(record, record:getCeilings(), day)
    if day.sheet ~= nil then
        record.form = EqTraining.mergeForm(record.form, day.sheet.month or 0, EqTraining.formFrom(day.sheet))
    end

    local notes = EqStatLog.explainDay(detail, day, { resting = resting, focus = record.focus, sheet = day.sheet,
        playerPoints = EqTraining.playerRidingPoints(day.sheet) })
    if record.form ~= nil and EqTraining.hasForm(record.form) then
        table.insert(notes, string.format("Peak form for month %d: sta +%.1f spd +%.1f agi +%.1f tem +%.1f", record.form.month or 0,
            record.form.stamina or 0, record.form.speed or 0, record.form.agility or 0, record.form.temperament or 0))
    end
    table.insert(notes, string.format("RLRM before its daily update: fitness %s health %s dirt %s riding %s",
        tostring(animal.fitness), tostring(animal.health), tostring(animal.dirt), tostring(animal.riding)))
    local today = g_currentMission.environment.currentMonotonicDay or 0
    EqStatLog.add(record.id, today, "daily training", deltas, notes, record.trained)
    record:addGains(today, deltas)

    Log:debug("EqTraining: %s riding=%s dirt=%s idle=%d -> sta %+.2f spd %+.2f agi %+.2f tem %+.2f",
        record.id, tostring(animal.riding), tostring(animal.dirt), record.idleDays,
        deltas.stamina, deltas.speed, deltas.agility, deltas.temperament)
end


--- Patch the base Rideable functions. Call at source time.
--- @param guarded function main.lua's error guard
function EqTrainingHooks.installRideable(guarded)
    Rideable.updateRiding = Utils.appendedFunction(Rideable.updateRiding, function(self, dt)
        if not EqMain.isActive or not self.isServer then return end
        guarded("riding tracker", function() EqTrainingHooks.onUpdateRiding(self, dt) end)
    end)

    Rideable.jump = Utils.appendedFunction(Rideable.jump, function(self)
        if not EqMain.isActive or not self.isServer then return end
        guarded("jump tracker", function() EqTrainingHooks.onJump(self) end)
    end)

    -- The forward and back keys pick the gallop's pace, and a change the exertion system doesn't
    -- allow is undone (EqTrainingHooks.gaitAction).
    for name, key in pairs({ actionEventAccelerate = "forward", actionEventBrake = "back" }) do
        if type(Rideable[name]) == "function" then
            Rideable[name] = Utils.overwrittenFunction(Rideable[name], function(self, superFunc, actionName, inputValue, ...)
                if not EqMain.isActive then return superFunc(self, actionName, inputValue, ...) end
                guarded("gallop key", function() EqTrainingHooks.beforeGaitAction(self, key, inputValue) end)
                local result = superFunc(self, actionName, inputValue, ...)
                guarded("gallop key", function() EqTrainingHooks.afterGaitAction(self) end)
                return result
            end)
            Log:info("Gallop keys: wrapped Rideable.%s", name)
        else
            Log:warning("EqTrainingHooks: Rideable.%s missing; the gallop keys only work through the key poll", name)
        end
    end

    if Rideable.onRegisterActionEvents ~= nil then
        Rideable.onRegisterActionEvents = Utils.appendedFunction(Rideable.onRegisterActionEvents,
            function(self, isActiveForInput, isActiveForInputIgnoreSelection)
                if not EqMain.isActive or not self.isClient then return end
                guarded("training view key", function() EqTrainingHooks.onRegisterActionEvents(self, isActiveForInputIgnoreSelection) end)
            end)
    else
        Log:warning("EqTrainingHooks: Rideable.onRegisterActionEvents missing; no training view key")
    end

    Rideable.onDraw = Utils.appendedFunction(Rideable.onDraw, function(self, isActiveForInput, isActiveForInputIgnoreSelection)
        if not EqMain.isActive then return end
        guarded("training overlay", function() EqTrainingHooks.onDraw(self, isActiveForInputIgnoreSelection) end)
    end)
    -- Dressage markers lose their collision as they are found; the tag comes down once nobody
    -- rides to it.
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("dressage markers", EqDressageHooks.update)
        guarded("course recording", EqCourseHooks.update)
        guarded("show jump poles", EqPoles.update)
    end)
end


--- Hook RLRM's daily horse tick. Call once, after EqRLRM.init succeeded.
--- @param guarded function main.lua's error guard
function EqTrainingHooks.installDaily(guarded)
    local animalHorse = EqRLRM.get("AnimalHorse")
    animalHorse.processRidingUpdate = Utils.prependedFunction(animalHorse.processRidingUpdate, function(animal)
        guarded("daily training", function() EqTrainingHooks.onHorseDay(animal) end)
    end)
    Log:debug("EqTrainingHooks: hooked AnimalHorse.processRidingUpdate")
end

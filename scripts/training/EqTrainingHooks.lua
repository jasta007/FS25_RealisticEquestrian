--[[
    EqTrainingHooks.lua
    Wires EqTraining into the game.

    - Rideable.updateRiding and Rideable.jump (base game) record the player's riding into a sheet
      per horse. Vehicle functions are copied into each vehicle type when types are registered,
      so these two are patched at source time, before that happens; the hook bodies stay idle
      until EqMain is active. Both run on the server only, which is where riding is counted.
    - Rideable.updateRiding also steps the tiredness meter and the focused stamina and speed work
      (EqTraining.step), at a halt too; a fitter horse tires more slowly.
    - Rideable.onDraw shows the training panel while riding (EqTrainingHud): the exertion meter
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
    end
    return gaitNames
end


--- @param id string
--- @return table sheet, created on first use
function EqTrainingHooks.getSheet(id)
    local sheet = EqTrainingHooks.sheets[id]
    if sheet == nil then
        sheet = EqTraining.newSheet()
        EqTrainingHooks.sheets[id] = sheet
    end
    return sheet
end


function EqTrainingHooks.reset()
    EqTrainingHooks.sheets = {}
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


--- Backing up tires a horse faster than the base game counts, and a fit horse's bar fills more
--- slowly: add the difference to (or take it off) its riding bar.
--- @param spec table spec_rideable
--- @param gait string
--- @param factor number EqTraining.ridingBarFactor
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
-- anything on the way (a crash, or losing most of its take-off speed).
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

local probe = { vehicle = nil, height = nil, name = nil }


--- raycastAll callback: skip the horse itself, keep the first thing below it.
function EqTrainingHooks:jumpRaycastCallback(hitObjectId, x, y, z, distance)
    if hitObjectId == nil or hitObjectId == 0 then return true end
    if g_currentMission.terrainRootNode ~= nil and hitObjectId == g_currentMission.terrainRootNode then return true end
    local object = g_currentMission.getNodeObject ~= nil and g_currentMission:getNodeObject(hitObjectId) or nil
    if object ~= nil and object == probe.vehicle then return true end
    probe.height = y
    probe.name = getName ~= nil and getName(hitObjectId) or tostring(hitObjectId)
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
--- @return number|nil height above the ground in metres, string|nil name
local function obstacleAt(vehicle, x, y, z)
    local ground = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, y, z)
    probe.vehicle, probe.height, probe.name = vehicle, nil, nil
    raycastAll(x, y + EqTrainingHooks.JUMP_RAY_UP, z, 0, -1, 0, EqTrainingHooks.JUMP_RAY_LENGTH,
        "jumpRaycastCallback", EqTrainingHooks, jumpMask())
    probe.vehicle = nil
    if probe.height == nil then return nil end
    return probe.height - ground, probe.name
end


--- The tallest thing under the horse's body, if there is one.
--- @param vehicle table
--- @return number|nil height above the ground in metres, string|nil name
local function obstacleBelow(vehicle)
    if raycastAll == nil or vehicle.rootNode == nil then return nil end
    local best, bestName = nil, nil
    local function look(along, across)
        local x, y, z = localToWorld(vehicle.rootNode, across, 0, along)
        local height, name = obstacleAt(vehicle, x, y, z)
        if height ~= nil and (best == nil or height > best) then best, bestName = height, name end
    end
    for _, along in ipairs(EqTrainingHooks.JUMP_RAYS_ALONG) do look(along, 0) end
    for _, across in ipairs(EqTrainingHooks.JUMP_RAYS_ACROSS) do look(0, across) end
    return best, bestName
end


--- @param result string|nil from EqTraining.knockCombo
local function popKnock(result)
    if result == "knocked" then EqTrainingHud.pop("knock")
    elseif result == "lost" then EqTrainingHud.pop("jumpLost") end
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

    local height, name = obstacleBelow(vehicle)
    if jump.landedAt == nil then
        local inAir
        if spec.isOnGround ~= nil then
            inAir = not spec.isOnGround
        else
            inAir = age < EqTrainingHooks.JUMP_FALLBACK_MS
        end
        if inAir then
            jump.airborne = true
            if height ~= nil and height > jump.best then jump.best, jump.over = height, name end
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

    judgeJump(spec, sheet, worn, jump, speed, now)
end


--- Score a landed jump: cleared, cleared with a knock, landed on top, or nothing under it.
--- @param spec table
--- @param sheet table
--- @param worn boolean
--- @param jump table spec.eqJump
--- @param speed number current speed, m/s
--- @param now number g_time
judgeJump = function(spec, sheet, worn, jump, speed, now)
    local age = now - jump.startedAt
    spec.eqJump = nil
    local high = jump.best >= EqTrainingHooks.JUMP_MIN_HEIGHT
    local cleared = high and not jump.onTop and not jump.crashed and not jump.knocked
    local why = ""
    if high and not cleared then
        why = jump.crashed and ", crashed" or jump.knocked and ", hit it (slowed from %.1f to %.1f m/s)" or ", landed on top of it"
        why = string.format(why, jump.speed, speed)
    end
    Log:info("Jump: %s (tallest thing under the horse %.2f m '%s'%s, %d ms, ground flag %s, take-off at a %s)",
        cleared and "cleared" or (high and not jump.onTop) and "cleared with a knock" or "nothing cleared", jump.best, tostring(jump.over), why,
        age, tostring(spec.isOnGround ~= nil), tostring(jump.gait))
    if cleared then
        local mult = EqTraining.clearJump(sheet, worn)
        if mult ~= nil then EqTrainingHud.pop("jump", mult) end
    elseif high and not jump.onTop then
        -- Hitting the obstacle on the way over costs combo time, but the jump still counts
        -- unless that ran the combo out (clearJump then refuses it).
        local knock = EqTraining.knockCombo(sheet)
        local mult = knock ~= "lost" and EqTraining.clearJump(sheet, worn) or nil
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
    return view == "freestyle" or view == "temperament"
end


-- A jump (and the stumble after landing) can knock the gait or speed down for a moment. A
-- rider sometimes has to jump to keep the pace, so stamina and speed training (and the jump
-- combo clock) carry on at the
-- gait from before take-off until this long after landing.
EqTrainingHooks.JUMP_PACE_HOLD_MS = 1500

local PACE_GAITS = { trot = true, canter = true, gallop = true }

--- @param spec table
--- @param gait string the gait this frame
--- @param now number g_time
--- @return string gait for stamina and speed training
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

-- A horse blowing hard (exertion over EqTraining.ZONE_HIGH) runs BLOWN_SPEED_SHARE as fast,
-- easing in over BLOWN_EASE_POINTS of exertion.
EqTrainingHooks.BLOWN_SPEED_SHARE = 0.75
EqTrainingHooks.BLOWN_EASE_POINTS = 5

--- @param tiredness number|nil exertion meter
--- @return number share of top speed
function EqTrainingHooks.blownSpeedShare(tiredness)
    local over = EqStats.clamp(((tiredness or 0) - EqTraining.ZONE_HIGH) / EqTrainingHooks.BLOWN_EASE_POINTS, 0, 1)
    return 1 - (1 - EqTrainingHooks.BLOWN_SPEED_SHARE) * over
end

--- Set the base game's jump height, acceleration, top speeds and turn rate for the gait and
--- the horse, before it jumps. The base values are kept on the spec the first time.
--- @param spec table spec_rideable
--- @param gait string
--- @param record table|nil the ridden horse's EqHorseRecord
--- @param sheet table the horse's training sheet (exertion and Sprint)
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
    if type(spec.topSpeeds) == "table" then
        if spec.eqBaseTopSpeeds == nil then
            -- Our own table, in case the base game shares one between horses.
            spec.eqBaseTopSpeeds, spec.topSpeeds = spec.topSpeeds, {}
            for key, value in pairs(spec.eqBaseTopSpeeds) do spec.topSpeeds[key] = value end
        end
        -- Forward gaits only: backing up stays at the base game's pace. A blowing horse slows.
        -- Sprint ignores being blown and runs the gallop SPRINT_SPEED_SHARE faster.
        local sprinting = EqTraining.isSprinting(sheet)
        local blown = sprinting and 1 or EqTrainingHooks.blownSpeedShare(sheet.tiredness)
        local gallop = Rideable.GAITTYPES ~= nil and Rideable.GAITTYPES.GALLOP or nil
        for key, value in pairs(spec.eqBaseTopSpeeds) do
            if type(value) == "number" then
                local sprint = sprinting and key == gallop and EqTraining.SPRINT_SPEED_SHARE or 1
                spec.topSpeeds[key] = value > 0 and value * handling.speed * blown * sprint or value
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

    local gait = getGaitNames()[spec.inputValues.currentGait]
    if gait == nil or math.abs(spec.currentSpeed or 0) < 0.05 then gait = "halt" end

    local id = getRiddenId(spec)
    if id == nil then return end
    local record = EqRegistry.getById(id)
    local sheet = EqTrainingHooks.getSheet(id)
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

    local now = g_time or 0
    if sheet.clock ~= nil and now - sheet.clock > 1000 then EqTraining.rest(sheet, now - sheet.clock) end
    sheet.clock = now

    local worn = isTired(spec.cluster)
    local stamina = record ~= nil and record.trained.stamina or nil
    local pace = paceGait(spec, gait, now)
    EqTraining.step(sheet, pace, dt, worn, stamina)
    spec.eqLastGait = gait
    local sprintEvent = EqTraining.sprintStep(sheet, pace, dt)
    if sprintEvent == "counted" then EqTrainingHud.pop("sprintCount", sheet.sprint.count)
    elseif sprintEvent ~= nil then EqTrainingHud.pop("sprint_" .. sprintEvent) end
    if sprintEvent == "ready" then spec.eqSprintKeyFresh = not spec.eqAccelHeld end
    -- Without a forward key hook, Sprint starts by itself after SPRINT_AUTO_MS ready.
    if sheet.sprint.ready and not EqTrainingHooks.sprintKeyHooked
        and sheet.sprint.readyMs >= EqTraining.SPRINT_READY_MS + EqTrainingHooks.SPRINT_AUTO_MS then
        EqTrainingHooks.startSprint(sheet)
    end

    local wasJumping = spec.eqJump ~= nil
    trackJump(vehicle, spec, sheet, worn)
    if wasJumping and spec.eqJump == nil then spec.eqJumpHoldUntil = now + EqTrainingHooks.JUMP_PACE_HOLD_MS end

    -- The base game stops a horse that runs into something and counts its haltTimer down; we
    -- cut that stop short. A crash costs jump combo time and breaks a routine, but not a
    -- stamina run.
    local halted = (spec.haltTimer or 0) > 0
    if halted and not spec.eqHalted then
        local was = spec.haltTimer
        spec.haltTimer = math.min(spec.haltTimer, spec.eqCrashHaltMs or EqTrainingHooks.CRASH_HALT_MS)
        -- A jump still in the air or settling when the horse crashes did not clear.
        if spec.eqJump ~= nil then spec.eqJump.crashed = true end
        Log:info("Crash: the horse ran into something at a %s (haltTimer %s, cut to %s)", gait, tostring(was), tostring(spec.haltTimer))
        spec.eqCrashGraceUntil = now + EqTrainingHooks.CRASH_GRACE_MS
        local knock = EqTraining.knockCombo(sheet)
        if EqTraining.breakRoutine(sheet) and knock == nil then EqTrainingHud.pop("routineLost") end
        popKnock(knock)
    end
    spec.eqHalted = halted
    -- Getting going again after a crash doesn't drain the combo at the slow-gait rate.
    local comboGait = now < (spec.eqCrashGraceUntil or 0) and "trot" or pace
    if EqTraining.comboTick(sheet, comboGait, dt) then EqTrainingHud.pop("jumpLost") end
    if routineShown() then
        local event = EqTraining.routineStep(sheet, (gait == "canter" or gait == "gallop") and "fast" or gait,
            steerInput(spec), dt, worn, math.random)
        if event == "done" then EqTrainingHud.pop("routine", sheet.routine.mult)
        elseif event == "lost" then EqTrainingHud.pop("routineLost")
        elseif event == "start" then EqTrainingHud.pop("routineStart") end
    elseif EqTraining.breakRoutine(sheet) then
        EqTrainingHud.pop("routineLost")
    end

    if worn or gait == "halt" then return end

    sheet.barFactor = EqTraining.ridingBarFactor(stamina)
    EqTraining.addRiding(sheet, gait, dt)
    adjustRiding(spec, gait, sheet.barFactor, dt)
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do EqTraining.addInside(sheet, kind, dt) end
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


-- Sprint starts with the forward key (W) once ready. If no forward key function could be
-- hooked, it starts by itself this long after it is ready.
EqTrainingHooks.SPRINT_AUTO_MS = 1500
EqTrainingHooks.sprintKeyHooked = false

--- @param sheet table
function EqTrainingHooks.startSprint(sheet)
    if EqTraining.startSprint(sheet) then
        EqTrainingHud.pop("sprint_go")
        Log:info("Sprint: started (exertion %.0f%%)", sheet.tiredness)
    end
end


--- Appended to the base game's forward key (accelerate) action: a fresh press of W while
--- Sprint is ready starts it. Holding W from before Sprint was ready needs a release first.
--- @param vehicle table
--- @param inputValue number
function EqTrainingHooks.onForwardInput(vehicle, inputValue)
    local spec = vehicle.spec_rideable
    if spec == nil then return end
    local held = (inputValue or 0) > 0
    if not held then spec.eqSprintKeyFresh = true end
    spec.eqAccelHeld = held
    if not held or not spec.eqSprintKeyFresh then return end
    local id = getRiddenId(spec)
    local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
    if sheet ~= nil and sheet.sprint.ready then EqTrainingHooks.startSprint(sheet) end
end


--- Appended to Rideable:jump (the server branch: in multiplayer a client's JumpEvent calls it
--- on the server). The jump is judged in the air by trackJump; any jump ends a routine, but a
--- stamina run or sprint keeps its pace through it (paceGait).
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
        judgeJump(spec, sheet, isTired(spec.cluster), last, math.abs(spec.currentSpeed or 0), g_time or 0)
    end
    EqTraining.addJump(sheet)
    if EqTraining.breakRoutine(sheet) then EqTrainingHud.pop("routineLost") end
    spec.eqJump = { startedAt = g_time or 0, best = 0, airborne = false, speed = math.abs(spec.currentSpeed or 0), gait = spec.eqLastGait }
    spec.eqJumpGait, spec.eqJumpHoldUntil = spec.eqLastGait, nil
    pcall(logRideableFields, spec)
end


-- Riding HUD views, switched with the training view key (Y). Freestyle shows every stat; a
-- focused view shows the one stat it trains. Help popups (H, and the first time a view
-- opens) explain each view in HELP_PAGES pages.
EqTrainingHooks.VIEWS = { "freestyle", "stamina", "speed", "agility", "temperament" }
EqTrainingHooks.HELP_PAGES = { freestyle = 2, stamina = 3, speed = 3, agility = 2, temperament = 2 }
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
        table.insert(pages, { title = title, text = g_i18n:getText(string.format("eq_help_%s_%d", view, i)) })
    end
    EqTrainingHud.showHelp(pages)
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
    if InputAction.EQ_TRAINING_HELP ~= nil then
        local _, helpId = vehicle:addActionEvent(spec.actionEvents, InputAction.EQ_TRAINING_HELP, vehicle,
            function() EqTrainingHooks.showHelp(EqTrainingHooks.getView()) end, false, true, false, true, nil)
        if helpId ~= nil then
            g_inputBinding:setActionEventText(helpId, g_i18n:getText("input_EQ_TRAINING_HELP"))
            g_inputBinding:setActionEventTextPriority(helpId, GS_PRIO_LOW)
        end
    end
end


local COLOR = EqTrainingHud.COLOR
local BAND_COLOR = {
    tired_fresh = COLOR.blue, tired_warm = COLOR.yellow, tired_zone = COLOR.green, tired_blown = COLOR.red,
    sprint_fresh = COLOR.green, sprint_tiring = COLOR.yellow, sprint_stale = COLOR.red,
}
local QUALITY_COLOR = { fast = COLOR.green, steady = COLOR.yellow, slow = COLOR.grey, full = COLOR.green }


--- A panel row for a stat: "Stamina 45%" and how it is training now, in that state's colour.
--- @param stat string
--- @param effort table from EqTraining.playerEffort
--- @param sheet table
--- @return table row
local function statRow(stat, effort, sheet)
    local cap = EqTraining.EFFORT_CAP[stat]
    local band
    if effort[stat] >= cap then
        band = "full"
    elseif sheet.quality[stat] ~= nil then
        band = EqTraining.qualityBand(sheet.quality[stat])
    end
    return {
        left = string.format("%s %d%%", g_i18n:getText("eq_stat_" .. stat), math.floor(effort[stat] / cap * 100 + 0.5)),
        right = band ~= nil and g_i18n:getText("eq_train_quality_" .. band) or nil,
        rightColor = band ~= nil and QUALITY_COLOR[band] or nil,
    }
end


--- Appended to Rideable:onDraw: the training panel, from the server's sheet, and the help popups.
function EqTrainingHooks.onDraw(vehicle, isActiveForInputIgnoreSelection)
    if not isActiveForInputIgnoreSelection then return end
    local spec = vehicle.spec_rideable
    if spec == nil then return end

    local view = EqTrainingHooks.getView()
    if not EqTrainingHud.isHelpShowing() and not EqTrainingHud.hasSeen(view) then
        EqTrainingHud.markSeen(view)
        EqTrainingHooks.showHelp(view)
    end
    EqTrainingHud.drawHelp()

    local id = getRiddenId(spec)
    local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
    if sheet == nil then return end

    local effort = EqTraining.playerEffort(sheet)
    local rows = {}
    if view == "freestyle" or view == "stamina" or view == "speed" then
        local band = view == "speed" and ("sprint_" .. EqTraining.sprintBand(sheet.tiredness))
            or ("tired_" .. EqTraining.tirednessBand(sheet.tiredness))
        local bandColor = BAND_COLOR[band]
        table.insert(rows, { left = string.format("%s %d%%", g_i18n:getText("eq_train_tiredness"), math.floor(sheet.tiredness + 0.5)),
            right = g_i18n:getText("eq_train_" .. band), rightColor = bandColor })
        local bar = { bar = sheet.tiredness / 100, color = bandColor }
        if view ~= "speed" then
            local low, high = EqTraining.zoneBounds(sheet.zoneHold)
            bar.marks = { low / 100, high / 100 }
        end
        table.insert(rows, bar)
    end
    if view == "freestyle" or view == "stamina" then
        local full = sheet.run >= EqTraining.RUN_FULL
        local row = { left = string.format(g_i18n:getText("eq_train_run"), math.floor(sheet.run)),
            leftColor = full and COLOR.green or COLOR.white }
        if (sheet.zoneHold or 0) > 0 then
            local _, _, t = EqTraining.zoneBounds(sheet.zoneHold)
            row.right = string.format(g_i18n:getText("eq_train_zoneHold"), 1 + EqTraining.ZONE_HOLD_BONUS * t)
            row.rightColor = COLOR.green
        end
        table.insert(rows, row)
    end
    if view == "freestyle" or view == "speed" then
        local sprint = sheet.sprint
        if EqTraining.isSprinting(sheet) then
            table.insert(rows, { left = g_i18n:getText("eq_train_sprint_on"), leftColor = COLOR.red,
                right = string.format("%d s", math.ceil(sprint.activeMs / 1000)) })
            table.insert(rows, { bar = sprint.activeMs / EqTraining.SPRINT_MS, color = COLOR.red })
        elseif sprint.ready then
            table.insert(rows, { left = g_i18n:getText("eq_train_sprint_ready"), leftColor = COLOR.orange })
            EqTrainingHud.drawPrompt(g_i18n:getText("eq_pop_sprint_ready"), 1, COLOR.orange)
        elseif sprint.warm then
            table.insert(rows, { left = g_i18n:getText("eq_train_sprint_warm"), leftColor = COLOR.yellow })
        elseif sprint.rest then
            table.insert(rows, { left = g_i18n:getText("eq_train_sprint_rest"), leftColor = COLOR.grey })
        else
            table.insert(rows, { left = string.format(g_i18n:getText("eq_train_sprint_count"), sprint.count, EqTraining.SPRINTS_TO_WARM),
                leftColor = view == "speed" and COLOR.white or COLOR.grey })
        end
    end

    local combo = sheet.combo
    if combo.count > 0 and (view == "freestyle" or view == "agility") then
        local mult = math.min(combo.count, EqTraining.COMBO_MAX)
        local color = EqTrainingHud.multColor(mult)
        table.insert(rows, { left = string.format(g_i18n:getText("eq_train_combo"), mult), leftColor = color,
            right = string.format("%d s", math.ceil(combo.timer)) })
        table.insert(rows, { bar = combo.timer / EqTraining.COMBO_SECONDS, color = color })
    elseif view == "agility" then
        table.insert(rows, { left = g_i18n:getText("eq_train_combo_none"), leftColor = COLOR.grey })
    end

    local routine = sheet.routine
    if routineShown() then
        if routine.active then
            local color = EqTrainingHud.multColor(routine.mult)
            local row = { left = string.format(g_i18n:getText("eq_train_routine"), routine.mult), leftColor = color }
            if routine.request ~= nil then
                local left = math.max(0, routine.deadline - routine.clock)
                row.right = g_i18n:getText("eq_move_" .. routine.request)
                row.rightColor = COLOR.yellow
                table.insert(rows, row)
                table.insert(rows, { bar = left / (routine.reactMs or EqTraining.ROUTINE_REACT_MS), color = COLOR.yellow })
                EqTrainingHud.drawPrompt(g_i18n:getText("eq_move_" .. routine.request), left / (routine.reactMs or EqTraining.ROUTINE_REACT_MS))
            else
                table.insert(rows, row)
            end
        elseif view == "temperament" then
            table.insert(rows, { left = g_i18n:getText("eq_train_routine_none"), leftColor = COLOR.grey })
        end
    end
    EqTrainingHud.drawPops()

    if view == "freestyle" then
        for _, stat in ipairs(EqConstants.STAT_KEYS) do table.insert(rows, statRow(stat, effort, sheet)) end
    else
        table.insert(rows, statRow(view, effort, sheet))
        local others = {}
        for _, stat in ipairs(EqConstants.STAT_KEYS) do
            if stat ~= view then
                table.insert(others, string.format("%s %d%%", g_i18n:getText("eq_stat_short_" .. stat),
                    math.floor(effort[stat] / EqTraining.EFFORT_CAP[stat] * 100 + 0.5)))
            end
        end
        table.insert(rows, { left = table.concat(others, "  "), leftColor = COLOR.grey })
    end
    if isTired(spec.cluster) then table.insert(rows, { left = g_i18n:getText("eq_train_worn"), leftColor = COLOR.orange }) end

    EqTrainingHud.drawPanel(string.format(g_i18n:getText("eq_train_title"), g_i18n:getText("eq_train_view_" .. view)), rows)

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
    local owned, ridden = EqFacilityHooks.boostsFor(EqFacilityHooks.farmOfAnimal(animal), sheet)
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
    }
    local deltas, detail = EqTraining.applyDay(record, record:getCeilings(), day)

    local notes = EqStatLog.explainDay(detail, day, { resting = resting, focus = record.focus, sheet = day.sheet,
        playerPoints = EqTraining.playerRidingPoints(day.sheet) })
    table.insert(notes, string.format("RLRM before its daily update: fitness %s health %s dirt %s riding %s",
        tostring(animal.fitness), tostring(animal.health), tostring(animal.dirt), tostring(animal.riding)))
    EqStatLog.add(record.id, g_currentMission.environment.currentMonotonicDay or 0, "daily training", deltas, notes, record.trained)

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

    -- The forward key: we don't know its function's name in FS25 yet, so log Rideable's action
    -- functions once and hook the ones that look like it.
    local names = {}
    for name, fn in pairs(Rideable) do
        if type(fn) == "function" and type(name) == "string" and name:find("^actionEvent") then table.insert(names, name) end
    end
    table.sort(names)
    Log:info("Rideable action functions: %s", table.concat(names, ", "))
    for _, name in ipairs(names) do
        local lower = name:lower()
        if lower:find("accel") or lower:find("forward") or lower:find("gaitup") then
            Rideable[name] = Utils.appendedFunction(Rideable[name], function(self, actionName, inputValue)
                if not EqMain.isActive then return end
                guarded("sprint key", function() EqTrainingHooks.onForwardInput(self, inputValue) end)
            end)
            EqTrainingHooks.sprintKeyHooked = true
            Log:info("Sprint key: hooked Rideable.%s", name)
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

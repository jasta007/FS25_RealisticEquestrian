--[[
    EqLateral.lua
    Lateral work while riding (James, 2026-10-30): hold Shift and press A or D at a walk, trot
    or canter and the horse drifts that way while still facing forwards, like strafing in a
    shooter, its head tilted the way it goes (a half pass, without new animations).

    The base game moves a ridden horse in Rideable:updateKinematic (server): it turns by
    maxTurnSpeed * axisSteer and moves the character controller (moveCCT) along its heading.
    While Shift is held the steer goes to zero for that frame, and the sideways move is added to
    that same moveCCT call (a second call replaced the first: the horse moved too little, the
    base game's stuck check halted it and it lurched, "almost like bucking", James 2026-10-30). Rideable:updateAnimation eases the tilt (smoothedLeftRightWeight) back towards
    the turn it sees; it is set each frame first, so the tilt holds.

    Holding the right mouse button and moving the mouse left or right bends the horse's head
    that way (James, 2026-10-30), with no turn and no camera move: the mouse's look input goes to
    the bend instead while the button is held, and the bend springs back on release. With the
    sideways drift it makes the lateral movements: shoulder-in (bend alone), half pass (drift
    with the head bent the way it goes), and so on (EqDressagePath scores them in a test).

    Holding Ctrl collects the horse to a stop while it keeps the gait's animation (James,
    2026-10-30): trotting on the spot is a piaffe, cantering on the spot turned with Ctrl + A/D a
    pirouette. The base game still works out the gait's speed; the move made is cut to nothing
    (and the stuck check's record of it with it, or it would halt the horse), and the animation is
    shown the gait's speed instead of the horse's real one.

    Keys are read on this machine, so it works for the local rider (single player for now).

    Part of Realistic Equestrian by Jasta007.
]]

EqLateral = {}

local Log = EqLog

-- Sideways speed as a share of the forward speed (about 27 degrees off straight ahead), eased in
-- and out over RAMP_MS, and the head's tilt (the animation's left-right weight, -1..1).
EqLateral.SHARE = 0.5
EqLateral.RAMP_MS = 400
EqLateral.TILT = 0.3
-- The head bend: mouse look input (radians the camera would have turned) to bend (-1..1, right
-- positive), and how fast it springs back once the button is let go.
EqLateral.BEND_SCALE = 2
EqLateral.BEND_BACK_MS = 300
-- Mouse steering (James, 2026-10-30): the right button held without Shift steers with the mouse,
-- left and right setting the turn (-1..1, left positive as the base game's axisSteer) like a
-- wheel, back to straight once the button is let go. Shift + right button bends the head.
-- (James: too little turn for the mouse moved, and hard to keep straight: x3, and a dead zone
-- in the middle the turn starts from, with the head eased to the turn so it doesn't jerk.)
EqLateral.STEER_SCALE = 4.5
EqLateral.DEAD_ZONE = 0.25
-- Past the dead zone the turn grows gently first (power STEER_CURVE), finer near straight.
EqLateral.STEER_CURVE = 1.5
-- Extra turn acceleration, rad/s², on top of the base game's 0.8 to 1.2.
EqLateral.TURN_ACCEL = 3
EqLateral.STEER_TILT = 0.9
EqLateral.HEAD_MS = 350
EqLateral.BEND_EASE_MS = 120
EqLateral.steer = 0
EqLateral.head = 0
-- While the bend is held the camera eases round to the way the horse is going (James,
-- 2026-10-30: bending took the mouse away from the camera, so he lost sight of where he went):
-- the share of the gap closed each SNAP_MS. Up and down stays on the mouse.
EqLateral.SNAP_MS = 250
-- The bend's share of the animation's left-right weight.
EqLateral.BEND_TILT = 0.8
-- The local rider's bend, and the horse it is on.
EqLateral.bend = 0
EqLateral.vehicle = nil
-- Collecting on the spot (Ctrl): how fast the forward move eases out and back in, and the turn
-- with Ctrl + A/D as a share of the base game's: piaffe (trot), pirouettes at a walk or canter
-- (James, 2026-10-30).
EqLateral.COLLECT_MS = 600
EqLateral.SPOT_TURN = { WALK = 1, TROT = 1, CANTER = 1 }
-- On the spot (James, 2026-10-30: the hooves slid): the animation is shown a slower speed, this
-- share of the way from the gait below's top speed to the gait's, and the horse still creeps
-- forward at this share of its speed, a little at a piaffe and a bit more at a canter. No lift:
-- off the ground the base game plays a jump or landing.
EqLateral.SPOT_SHOW = 0.6
EqLateral.SPOT_CREEP = { WALK = 0, TROT = 0.08, CANTER = 0.15 }
-- Ctrl + W (James, 2026-10-30): collected but going forward, a passage at a trot (the trot's
-- animation at the walk's top speed) and a collected canter (half way between the walk's and
-- the trot's), eased in and out over COLLECT_MS. W doesn't change gait while Ctrl is held.
EqLateral.PASSAGE = { TROT = 0, CANTER = 0.5 }
-- Gaits it works at (Rideable.GAITTYPES names).
EqLateral.GAITS = { WALK = true, TROT = true, CANTER = true }


--- The side the rider asks for (pure).
--- @param shift boolean Shift held
--- @param left boolean A held
--- @param right boolean D held
--- @param gaitOk boolean at a walk, trot or canter, on the ground
--- @return number -1 left, 1 right, 0 none
function EqLateral.side(shift, left, right, gaitOk)
    if not shift or not gaitOk or left == right then return 0 end
    return right and 1 or -1
end


--- Ease the lateral amount towards the side asked for (pure).
--- @param current number -1..1
--- @param side number -1, 0 or 1
--- @param dt number ms
--- @return number
function EqLateral.ease(current, side, dt)
    local step = dt / EqLateral.RAMP_MS
    if current < side then return math.min(side, current + step) end
    return math.max(side, current - step)
end


--- The sideways move for a frame (pure): world x, z for heading turnAngle (dir = sin, cos; the
--- rider's right is -cos, sin).
--- @param amount number -1..1 eased side
--- @param speed number forward speed, m/s
--- @param turnAngle number radians
--- @param dt number ms
--- @return number dx, number dz
function EqLateral.move(amount, speed, turnAngle, dt)
    local d = amount * EqLateral.SHARE * math.max(0, speed) * dt / 1000
    return -math.cos(turnAngle) * d, math.sin(turnAngle) * d
end


local function key(name)
    return Input ~= nil and Input[name] ~= nil and Input.isKeyPressed ~= nil and Input.isKeyPressed(Input[name]) == true
end


--- The bend after a frame (pure): eased back to straight when the button is up.
--- @param bend number -1..1
--- @param held boolean right mouse button held
--- @param dt number ms
--- @return number
function EqLateral.relax(bend, held, dt)
    if held then return bend end
    local step = dt / EqLateral.BEND_BACK_MS
    if bend > 0 then return math.max(0, bend - step) end
    return math.min(0, bend + step)
end


--- The left-right weight the animation shows (pure): the drift's tilt and the head bend
--- (left positive, as turning left is).
--- @param lateral number -1..1 eased drift, right positive
--- @param bend number -1..1 right positive
--- @return number
function EqLateral.weight(lateral, bend)
    return math.max(-1, math.min(1, -lateral * EqLateral.TILT - bend * EqLateral.BEND_TILT))
end


--- A heading turned towards another by at most rate rad/s (pure).
function EqLateral.turnToward(angle, want, rate, dt)
    local diff = (want - angle + math.pi) % (2 * math.pi) - math.pi
    local step = rate * dt / 1000
    return angle + math.max(-step, math.min(step, diff))
end


--- The turn on the spot asked for (pure): A turns left (the base game's axisSteer is positive
--- to the left).
--- @param gait string|nil gait name
--- @return number 1, -1 or 0, times the gait's SPOT_TURN
function EqLateral.spotSteer(left, right, gait)
    local turn = EqLateral.SPOT_TURN[gait or ""] or 0
    if left == right then return 0 end
    return (left and 1 or -1) * turn
end


--- The gait's name (WALK, TROT, CANTER) and the top speed of the gait below it (pure).
--- @return string|nil, number
function EqLateral.gaitName(spec)
    local types, tops = Rideable ~= nil and Rideable.GAITTYPES or nil, spec.topSpeeds
    local gait = spec.inputValues ~= nil and spec.inputValues.currentGait or nil
    if types == nil or tops == nil or gait == nil then return nil, 0 end
    local below = { TROT = "WALK", CANTER = "TROT" }
    for name in pairs(EqLateral.GAITS) do
        if types[name] == gait then
            local lower = below[name] ~= nil and tops[types[below[name]]] or 0
            return name, type(lower) == "number" and lower or 0
        end
    end
    return nil, 0
end


--- The base game's top speeds by gait name.
function EqLateral.tops(spec)
    local types, tops = Rideable ~= nil and Rideable.GAITTYPES or nil, spec.topSpeeds
    if types == nil or tops == nil then return nil end
    return { WALK = tops[types.WALK], TROT = tops[types.TROT], CANTER = tops[types.CANTER] }
end


--- The share of the forward move kept on the spot (pure).
--- @param collect number 0..1
--- @param gait string|nil gait name
function EqLateral.keep(collect, gait, creep)
    return 1 - collect * (1 - (creep or EqLateral.SPOT_CREEP[gait or ""] or 0))
end


--- The share of the gait's speed kept in a passage or collected canter (pure): the walk's top
--- speed, or PASSAGE of the way from it to the trot's.
--- @param gait string|nil gait name
--- @param tops table|nil topSpeeds by gait name { WALK, TROT, CANTER }
--- @return number|nil nil when there is none at this gait
function EqLateral.passageShare(gait, tops)
    local towards = EqLateral.PASSAGE[gait or ""]
    if towards == nil or tops == nil or tops.WALK == nil or tops.TROT == nil or (tops[gait] or 0) <= 0 then return nil end
    return math.min(1, (tops.WALK + (tops.TROT - tops.WALK) * towards) / tops[gait])
end


--- The speed the animation is shown on the spot (pure): eased from the real one to a slower
--- one that still reads as the gait.
--- @param speed number the gait's speed the base game worked out, m/s
--- @param lower number the gait below's top speed
--- @param collect number 0..1
function EqLateral.shownSpeed(speed, lower, collect)
    local slow = lower + (speed - lower) * EqLateral.SPOT_SHOW
    return speed + (math.min(speed, slow) - speed) * collect
end


--- How collected the horse is after a frame (pure): 0 moving on, 1 on the spot.
function EqLateral.collect(current, wanted, dt)
    local step = dt / EqLateral.COLLECT_MS
    if wanted then return math.min(1, current + step) end
    return math.max(0, current - step)
end


--- The turn from the mouse's steer (pure): nothing in the dead zone, then the rest of the way.
--- @param steer number -1..1
--- @return number -1..1
function EqLateral.deadZone(steer)
    local a = math.abs(steer)
    if a <= EqLateral.DEAD_ZONE then return 0 end
    return (steer > 0 and 1 or -1) * (a - EqLateral.DEAD_ZONE) / (1 - EqLateral.DEAD_ZONE)
end


--- The turn for a steer past the dead zone (pure): gentle near straight, full at the end.
function EqLateral.curve(steer)
    return (steer < 0 and -1 or 1) * math.abs(steer) ^ EqLateral.STEER_CURVE
end


--- The turn speed after a frame's extra easing towards what is asked (pure).
function EqLateral.turnSpeedToward(current, desired, dt)
    local step = EqLateral.TURN_ACCEL * dt / 1000
    return current + math.max(-step, math.min(step, desired - current))
end


--- A value eased towards a target over ms (pure).
function EqLateral.towards(value, target, dt, ms)
    return value + (target - value) * math.min(1, dt / ms)
end


--- @return boolean the right mouse button is held
local function rightHeld()
    return Input ~= nil and Input.isMouseButtonPressed ~= nil and Input.MOUSE_BUTTON_RIGHT ~= nil
        and Input.isMouseButtonPressed(Input.MOUSE_BUTTON_RIGHT) == true
end


--- @return boolean Shift is held
local function shiftHeld()
    return key("KEY_lshift") or key("KEY_rshift")
end


--- The camera's mouse look while riding with the right button held: it bends the head instead.
--- @return boolean true when the input was used for the bend
function EqLateral.onLook(inputValue, isMouse, horizontal)
    local vehicle = EqLateral.vehicle
    if not isMouse or vehicle == nil or not rightHeld() then return false end
    if vehicle.getIsEntered ~= nil and not vehicle:getIsEntered() then return false end
    if not horizontal then return false end
    local turn = inputValue * 0.001 * 16.666
    if shiftHeld() then
        EqLateral.bend = math.max(-1, math.min(1, EqLateral.bend + turn * EqLateral.BEND_SCALE))
    else
        EqLateral.steer = math.max(-1, math.min(1, EqLateral.steer - turn * EqLateral.STEER_SCALE))
    end
    return true
end


--- The camera's turn after a frame (pure). The horse's camera hangs off its head (James,
--- 2026-10-30: it lined up with the bent head), so its rotY is not measured from the heading:
--- it is turned by however far the view is off the way the horse goes, in the world, eased.
--- Angles are world headings (dir = sin, cos); a camera turn adds to the heading it faces.
--- @param rotY number the camera's turn now
--- @param viewAngle number the heading the camera looks along now
--- @param turnAngle number the horse's heading
--- @param lateral number -1..1 eased drift, right positive (the right is the lower heading)
--- @param dt number ms
--- @return number
function EqLateral.snap(rotY, viewAngle, turnAngle, lateral, dt)
    local want = turnAngle - math.atan(lateral * EqLateral.SHARE)
    local diff = (want - viewAngle + math.pi) % (2 * math.pi) - math.pi
    return rotY + diff * math.min(1, dt / EqLateral.SNAP_MS)
end


--- While the right button is held, the rider's camera eases round to the way the body faces.
local function snapCamera(vehicle, dt)
    if vehicle ~= EqLateral.vehicle or not rightHeld() then return end
    local enterable = vehicle.spec_enterable
    local camera = enterable ~= nil and enterable.activeCamera or nil
    local spec = vehicle.spec_rideable
    if camera == nil or not camera.isRotatable or type(camera.rotY) ~= "number" or camera.cameraNode == nil
        or spec == nil or type(spec.currentTurnAngle) ~= "number" then return end
    -- A camera looks along its -z.
    local vx, _, vz = localDirectionToWorld(camera.cameraNode, 0, 0, -1)
    if vx * vx + vz * vz < 1e-6 then return end
    local view = math.atan2(vx, vz)
    if not EqLateral.snapLogged then
        EqLateral.snapLogged = true
        Log:info("Lateral work: camera %.0f deg off the heading as it starts following",
            math.deg((view - spec.currentTurnAngle + math.pi) % (2 * math.pi) - math.pi))
    end
    -- The way the body faces, not the drift (James, 2026-10-30: following the strafe felt wrong,
    -- and a half pass looked odd).
    camera.rotY = EqLateral.snap(camera.rotY, view, spec.currentTurnAngle, 0, dt)
end


--- @return boolean the gait is one lateral work is ridden at
local function gaitOk(spec)
    local types = Rideable.GAITTYPES
    if types == nil or spec.isOnGround == false then return false end
    local gait = spec.inputValues ~= nil and spec.inputValues.currentGait or nil
    for name in pairs(EqLateral.GAITS) do
        if types[name] ~= nil and types[name] == gait then return true end
    end
    return false
end


--- Before the base game's move: what the rider asks for, and no turning while asking.
local function before(vehicle, dt)
    local spec = vehicle.spec_rideable
    if spec == nil or spec.inputValues == nil then return end
    local entered = vehicle.getIsEntered ~= nil and vehicle:getIsEntered()
    local side, spot = 0, false
    if entered then
        EqLateral.vehicle = vehicle
        local held, shift = rightHeld(), shiftHeld()
        EqLateral.bend = EqLateral.relax(EqLateral.bend, held and shift, dt)
        EqLateral.steer = EqLateral.relax(EqLateral.steer, held, dt)
        spot = (key("KEY_lctrl") or key("KEY_rctrl")) and gaitOk(spec)
        -- Mouse steering (James, 2026-10-30): A and D strafe without Shift, and Shift holds the
        -- heading (no turn) while the mouse bends the head. On the keyboard Shift + A/D strafes.
        if not spot then
            side = EqLateral.side(shift or held, key("KEY_a"), key("KEY_d"), gaitOk(spec))
        end
        EqLateral.steering = held and not shift and not spot
        if held and not spot then
            spec.inputValues.axisSteer = shift and 0 or EqLateral.curve(EqLateral.deadZone(EqLateral.steer))
        elseif side ~= 0 then
            spec.inputValues.axisSteer = 0
        end
    end
    spec.eqLateral = EqLateral.ease(spec.eqLateral or 0, side, dt)
    spec.eqCollect = EqLateral.collect(spec.eqCollect or 0, spot, dt)
    -- Ctrl + W: forward in a passage or collected canter; else creeping on the spot.
    local gait = EqLateral.gaitName(spec)
    local creep = EqLateral.SPOT_CREEP[gait or ""] or 0
    local passage = nil
    if spot and key("KEY_w") then passage = EqLateral.passageShare(gait, EqLateral.tops(spec)) end
    spec.eqCreep = EqLateral.towards(spec.eqCreep or creep, passage or creep, dt, EqLateral.COLLECT_MS)
    if (passage ~= nil) ~= (spec.eqPassage == true) then
        spec.eqPassage = passage ~= nil
        Log:info("Lateral work: %s", passage ~= nil and (gait == "TROT" and "passage" or "collected canter") or "collected")
    end
    if spot then spec.inputValues.axisSteer = EqLateral.spotSteer(key("KEY_a"), key("KEY_d"), (EqLateral.gaitName(spec))) end
    -- Quicker to swing from one lock to the other (James: "spongey", a canter serpentine was
    -- impossible): the turn speed is eased towards what is asked TURN_ACCEL rad/s² faster.
    if entered and spec.isOnGround ~= false and type(spec.currentTurnSpeed) == "number" and type(spec.maxTurnSpeed) == "number" then
        spec.currentTurnSpeed = EqLateral.turnSpeedToward(spec.currentTurnSpeed, spec.maxTurnSpeed * (spec.inputValues.axisSteer or 0), dt)
    end
    if spot ~= (spec.eqSpot == true) then
        spec.eqSpot = spot
        Log:info("Lateral work: %s", spot and "on the spot" or "moving on")
    end
    -- Temperament's stickiness in a dressage test (EqDressageHooks.assist): a pull onto the line,
    -- added to this frame's move, and the body eased towards the angle a lateral section asks for.
    spec.eqPullX, spec.eqPullZ = 0, 0
    local assist = EqDressageHooks ~= nil and EqDressageHooks.assist or nil
    if entered and not spot and assist ~= nil and math.abs(spec.currentSpeed or 0) > 0.2 then
        local pullX, pullZ, wantX, wantZ, rate = assist(vehicle, side ~= 0, dt)
        spec.eqPullX, spec.eqPullZ = pullX, pullZ
        if wantX ~= nil and rate > 0 and type(spec.currentTurnAngle) == "number" then
            spec.currentTurnAngle = EqLateral.turnToward(spec.currentTurnAngle, math.atan2(wantX, wantZ), rate, dt)
        end
    end
    if side ~= (spec.eqLateralSide or 0) then
        spec.eqLateralSide = side
        Log:info("Lateral work: %s", side == 0 and "straight on" or (side > 0 and "drifting right" or "drifting left"))
    end
end


--- The base game's moveCCT for this frame, with the sideways step added to its move.
--- @return function|nil
local function sidewaysMove(vehicle, dt)
    local spec = vehicle.spec_rideable
    local amount = spec ~= nil and spec.eqLateral or 0
    local pullX, pullZ = spec ~= nil and spec.eqPullX or 0, spec ~= nil and spec.eqPullZ or 0
    local keep = spec ~= nil and EqLateral.keep(spec.eqCollect or 0, (EqLateral.gaitName(spec)), spec.eqCreep) or 1
    if amount == 0 and pullX == 0 and pullZ == 0 and keep == 1 or type(spec.currentTurnAngle) ~= "number" then return nil end
    local base = vehicle.moveCCT
    if base == nil then
        if not EqLateral.warned then
            EqLateral.warned = true
            Log:warning("Lateral work: no moveCCT on the horse, sideways moves are off")
        end
        return nil
    end
    return function(self, moveX, moveY, moveZ, ...)
        -- The heading and speed the base game just worked out for this frame.
        local dx, dz = EqLateral.move(amount, spec.currentSpeed or 0, spec.currentTurnAngle, dt)
        spec.eqMoveKeep = keep
        return base(self, moveX * keep + dx + pullX, moveY, moveZ * keep + dz + pullZ, ...)
    end
end


--- Before the base game's animation update: tilt the head the way the horse drifts (left is
--- positive, as turning left is).
local function tilt(vehicle, dt)
    local spec = vehicle.spec_rideable
    local amount = spec ~= nil and spec.eqLateral or 0
    local bend = vehicle == EqLateral.vehicle and EqLateral.bend or 0
    -- Mouse steering: the head eased to the turn asked, not the base game's frame-to-frame turn
    -- (James: jerky, at times snapping from full left to full right).
    if vehicle == EqLateral.vehicle and EqLateral.steering and amount == 0 and bend == 0 and type(spec.smoothedLeftRightWeight) == "number" then
        -- Slower towards full lock, so the neck doesn't race ahead of the body.
        local target = EqLateral.curve(EqLateral.deadZone(EqLateral.steer)) * EqLateral.STEER_TILT
        EqLateral.head = EqLateral.towards(EqLateral.head, target, dt, EqLateral.HEAD_MS * (1 + math.abs(target)))
        spec.smoothedLeftRightWeight = EqLateral.head
        return
    end
    if type(spec.smoothedLeftRightWeight) ~= "number" then return end
    if amount == 0 and bend == 0 then
        if vehicle == EqLateral.vehicle then EqLateral.head = spec.smoothedLeftRightWeight end
        return
    end
    -- Eased a little too: the mouse's bend comes in bursts.
    EqLateral.head = EqLateral.towards(EqLateral.head, EqLateral.weight(amount, bend), dt, EqLateral.BEND_EASE_MS)
    spec.smoothedLeftRightWeight = EqLateral.head
end


--- @return boolean true while the horse is drifting sideways
function EqLateral.isActive(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    return spec ~= nil and (spec.eqLateralSide or 0) ~= 0
end


--- Patch Rideable's move and animation. Call at source time.
function EqLateral.install()
    if type(Rideable.updateKinematic) ~= "function" then
        Log:warning("EqLateral: Rideable.updateKinematic missing; no lateral work")
        return
    end
    Rideable.updateKinematic = Utils.overwrittenFunction(Rideable.updateKinematic, function(self, superFunc, dt)
        if not EqMain.isActive or EqLateral.failed then return superFunc(self, dt) end
        -- One failure turns it off for the game, not an error every frame.
        if not EqLog.try("EqLateral before", before, self, dt) then EqLateral.failed = true end
        local ok, move = EqLog.try("EqLateral move", sidewaysMove, self, dt)
        if not ok then EqLateral.failed = true end
        if move == nil then return superFunc(self, dt) end
        -- Only for this call: the move made inside it carries the sideways step.
        local own = rawget(self, "moveCCT")
        self.moveCCT = move
        local spec = self.spec_rideable
        spec.eqMoveKeep = nil
        local queued = spec.cctMoveQueue ~= nil and #spec.cctMoveQueue or nil
        local result = { pcall(superFunc, self, dt) }
        self.moveCCT = own
        if not result[1] then error(result[2], 0) end
        -- On the spot, the stuck check expects only the forward move actually made.
        local keep = spec.eqMoveKeep
        local entry = queued ~= nil and spec.cctMoveQueue[queued + 1] or nil
        if keep ~= nil and keep < 1 and entry ~= nil then
            entry.moveX, entry.moveZ = (entry.moveX or 0) * keep, (entry.moveZ or 0) * keep
        end
        return unpack(result, 2)
    end)
    if type(Rideable.updateAnimation) == "function" then
        Rideable.updateAnimation = Utils.overwrittenFunction(Rideable.updateAnimation, function(self, superFunc, dt)
            if EqMain.isActive and not EqLateral.failed and not EqLog.try("EqLateral tilt", tilt, self, dt) then EqLateral.failed = true end
            if EqMain.isActive and not EqLateral.failed and not EqLog.try("EqLateral camera", snapCamera, self, dt) then EqLateral.failed = true end
            -- On the spot the animation sees the gait's speed, not the horse's (near nothing).
            local spec = self.spec_rideable
            local collect = spec ~= nil and spec.eqCollect or 0
            if collect <= 0 or EqLateral.failed or type(spec.currentSpeed) ~= "number" or type(self.lastSignedSpeedReal) ~= "number" then
                return superFunc(self, dt)
            end
            local real, smooth = self.lastSignedSpeedReal, self.lastSignedSpeed
            local _, lower = EqLateral.gaitName(spec)
            local shown = EqLateral.shownSpeed(spec.currentSpeed, lower, collect) / 1000
            self.lastSignedSpeedReal = math.max(real, shown)
            if type(smooth) == "number" then self.lastSignedSpeed = math.max(smooth, shown) end
            local result = { pcall(superFunc, self, dt) }
            self.lastSignedSpeedReal, self.lastSignedSpeed = real, smooth
            if not result[1] then error(result[2], 0) end
            return unpack(result, 2)
        end)
    end
    -- W doesn't raise the gait while Ctrl is held: Ctrl + W is a passage or collected canter.
    if type(Rideable.actionEventAccelerate) == "function" then
        Rideable.actionEventAccelerate = Utils.overwrittenFunction(Rideable.actionEventAccelerate, function(self, superFunc, ...)
            if EqMain.isActive and not EqLateral.failed and (key("KEY_lctrl") or key("KEY_rctrl"))
                and self.getIsEntered ~= nil and self:getIsEntered() then
                return
            end
            return superFunc(self, ...)
        end)
    end
    -- The mouse look goes to the head bend while the right button is held on a horse.
    if VehicleCamera ~= nil then
        for name, horizontal in pairs({ actionEventLookLeftRight = true, actionEventLookUpDown = false }) do
            if type(VehicleCamera[name]) == "function" then
                VehicleCamera[name] = Utils.overwrittenFunction(VehicleCamera[name], function(self, superFunc, actionName, inputValue, callbackState, isAnalog, isMouse, ...)
                    if EqMain.isActive and not EqLateral.failed then
                        local ok, used = EqLog.try("EqLateral look", EqLateral.onLook, inputValue, isMouse, horizontal)
                        if not ok then EqLateral.failed = true elseif used then return end
                    end
                    return superFunc(self, actionName, inputValue, callbackState, isAnalog, isMouse, ...)
                end)
            end
        end
    end
    Log:info("Lateral work: Shift + A/D at a walk, trot or canter; right mouse drag bends the head; Ctrl on the spot")
end

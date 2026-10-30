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
-- with Ctrl + A/D as a share of the base game's.
EqLateral.COLLECT_MS = 600
EqLateral.SPOT_TURN = 0.5
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
--- @return number 1, -1 or 0, times SPOT_TURN
function EqLateral.spotSteer(left, right)
    if left == right then return 0 end
    return (left and 1 or -1) * EqLateral.SPOT_TURN
end


--- How collected the horse is after a frame (pure): 0 moving on, 1 on the spot.
function EqLateral.collect(current, wanted, dt)
    local step = dt / EqLateral.COLLECT_MS
    if wanted then return math.min(1, current + step) end
    return math.max(0, current - step)
end


--- @return boolean the right mouse button is held
local function rightHeld()
    return Input ~= nil and Input.isMouseButtonPressed ~= nil and Input.MOUSE_BUTTON_RIGHT ~= nil
        and Input.isMouseButtonPressed(Input.MOUSE_BUTTON_RIGHT) == true
end


--- The camera's mouse look while riding with the right button held: it bends the head instead.
--- @return boolean true when the input was used for the bend
function EqLateral.onLook(inputValue, isMouse, horizontal)
    local vehicle = EqLateral.vehicle
    if not isMouse or vehicle == nil or not rightHeld() then return false end
    if vehicle.getIsEntered ~= nil and not vehicle:getIsEntered() then return false end
    if not horizontal then return false end
    EqLateral.bend = math.max(-1, math.min(1, EqLateral.bend + inputValue * 0.001 * 16.666 * EqLateral.BEND_SCALE))
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


--- While the bend is held, the rider's camera eases round to the way the horse is going.
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
    camera.rotY = EqLateral.snap(camera.rotY, view, spec.currentTurnAngle, spec.eqLateral or 0, dt)
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
        EqLateral.bend = EqLateral.relax(EqLateral.bend, rightHeld(), dt)
        spot = (key("KEY_lctrl") or key("KEY_rctrl")) and gaitOk(spec)
        if not spot then
            side = EqLateral.side(key("KEY_lshift") or key("KEY_rshift"), key("KEY_a"), key("KEY_d"), gaitOk(spec))
        end
    end
    spec.eqLateral = EqLateral.ease(spec.eqLateral or 0, side, dt)
    spec.eqCollect = EqLateral.collect(spec.eqCollect or 0, spot, dt)
    if side ~= 0 then spec.inputValues.axisSteer = 0 end
    if spot then spec.inputValues.axisSteer = EqLateral.spotSteer(key("KEY_a"), key("KEY_d")) end
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
    local keep = 1 - (spec ~= nil and spec.eqCollect or 0)
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
local function tilt(vehicle)
    local spec = vehicle.spec_rideable
    local amount = spec ~= nil and spec.eqLateral or 0
    local bend = vehicle == EqLateral.vehicle and EqLateral.bend or 0
    if amount == 0 and bend == 0 or type(spec.smoothedLeftRightWeight) ~= "number" then return end
    spec.smoothedLeftRightWeight = EqLateral.weight(amount, bend)
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
            if EqMain.isActive and not EqLateral.failed and not EqLog.try("EqLateral tilt", tilt, self) then EqLateral.failed = true end
            if EqMain.isActive and not EqLateral.failed and not EqLog.try("EqLateral camera", snapCamera, self, dt) then EqLateral.failed = true end
            -- On the spot the animation sees the gait's speed, not the horse's (near nothing).
            local spec = self.spec_rideable
            local collect = spec ~= nil and spec.eqCollect or 0
            if collect <= 0 or EqLateral.failed or type(spec.currentSpeed) ~= "number" or type(self.lastSignedSpeedReal) ~= "number" then
                return superFunc(self, dt)
            end
            local real, smooth = self.lastSignedSpeedReal, self.lastSignedSpeed
            local shown = spec.currentSpeed / 1000
            self.lastSignedSpeedReal = math.max(real, shown)
            if type(smooth) == "number" then self.lastSignedSpeed = math.max(smooth, shown) end
            local result = { pcall(superFunc, self, dt) }
            self.lastSignedSpeedReal, self.lastSignedSpeed = real, smooth
            if not result[1] then error(result[2], 0) end
            return unpack(result, 2)
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

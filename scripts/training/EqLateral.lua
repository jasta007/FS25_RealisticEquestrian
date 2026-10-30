--[[
    EqLateral.lua
    Lateral work while riding (James, 2026-10-30): hold Shift and press A or D at a walk, trot
    or canter and the horse drifts that way while still facing forwards, like strafing in a
    shooter, its head tilted the way it goes (a half pass, without new animations).

    The base game moves a ridden horse in Rideable:updateKinematic (server): it turns by
    maxTurnSpeed * axisSteer and moves the character controller (moveCCT) along its heading.
    While Shift is held the steer goes to zero for that frame, and a sideways move is added
    after it. Rideable:updateAnimation eases the tilt (smoothedLeftRightWeight) back towards
    the turn it sees; it is set each frame first, so the tilt holds.

    Keys are read on this machine, so it works for the local rider (single player for now).

    Part of Realistic Equestrian by Jasta007.
]]

EqLateral = {}

local Log = EqLog

-- Sideways speed as a share of the forward speed (about 27 degrees off straight ahead), eased in
-- and out over RAMP_MS, and the head's tilt (the animation's left-right weight, -1..1).
EqLateral.SHARE = 0.5
EqLateral.RAMP_MS = 400
EqLateral.TILT = 0.6
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
    local side = 0
    if entered then
        side = EqLateral.side(key("KEY_lshift") or key("KEY_rshift"), key("KEY_a"), key("KEY_d"), gaitOk(spec))
    end
    spec.eqLateral = EqLateral.ease(spec.eqLateral or 0, side, dt)
    if side ~= 0 then spec.inputValues.axisSteer = 0 end
    if side ~= (spec.eqLateralSide or 0) then
        spec.eqLateralSide = side
        Log:info("Lateral work: %s", side == 0 and "straight on" or (side > 0 and "drifting right" or "drifting left"))
    end
end


--- After the base game's move: the sideways step.
local function after(vehicle, dt)
    local spec = vehicle.spec_rideable
    local amount = spec ~= nil and spec.eqLateral or 0
    if amount == 0 or type(spec.currentTurnAngle) ~= "number" then return end
    if vehicle.moveCCT == nil then
        if not EqLateral.warned then
            EqLateral.warned = true
            Log:warning("Lateral work: no moveCCT on the horse, sideways moves are off")
        end
        return
    end
    local dx, dz = EqLateral.move(amount, spec.currentSpeed or 0, spec.currentTurnAngle, dt)
    if math.abs(dx) + math.abs(dz) > 1e-5 then vehicle:moveCCT(dx, 0, dz, true) end
end


--- Before the base game's animation update: tilt the head the way the horse drifts (left is
--- positive, as turning left is).
local function tilt(vehicle)
    local spec = vehicle.spec_rideable
    local amount = spec ~= nil and spec.eqLateral or 0
    if amount == 0 or type(spec.smoothedLeftRightWeight) ~= "number" then return end
    spec.smoothedLeftRightWeight = -amount * EqLateral.TILT
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
        local result = superFunc(self, dt)
        if not EqLateral.failed and not EqLog.try("EqLateral after", after, self, dt) then EqLateral.failed = true end
        return result
    end)
    if type(Rideable.updateAnimation) == "function" then
        Rideable.updateAnimation = Utils.overwrittenFunction(Rideable.updateAnimation, function(self, superFunc, dt)
            if EqMain.isActive and not EqLateral.failed and not EqLog.try("EqLateral tilt", tilt, self) then EqLateral.failed = true end
            return superFunc(self, dt)
        end)
    end
    Log:info("Lateral work: Shift + A/D at a walk, trot or canter")
end

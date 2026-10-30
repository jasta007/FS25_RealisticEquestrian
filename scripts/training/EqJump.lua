--[[
    EqJump.lua
    How a ridden horse jumps: pure functions with no game calls, so they run headless.
    EqTrainingHooks applies them to the base game's Rideable each frame.

    - Gravity (James, 2026-10-30: jumps felt floaty). The base game pulls a horse down at
      spec_rideable.gravity, 9.81 m/s2, and launches a jump at sqrt(2 g jumpHeight). We set that
      field to RISE_SHARE times as hard on the ground and on the way up, so the launch still
      reaches jumpHeight but sooner, and FALL_SHARE times on the way down, so the horse doesn't
      hang at the top and comes down quickly. HEIGHT_SHARE lowers every jump a little.
    - Push-off (James: the horse rose before its push-off animation, which then played in the
      air). On the jump key the horse first lifts only a hand's breadth, at PUSH_SPEED for
      PUSH_MS, so the push-off plays near the ground, and then launches with what is left of the
      jump's lift.
    - Collected jump (James): press Ctrl just before the jump (held, or let go no more than
      COLLECT_WINDOW_MS before) for a short, steep jump. The horse gathers itself over
      COLLECT_PUSH_MS, slowing to about a trot (COLLECT_TROT_SHARE of the trot's top speed, or
      COLLECT_SPEED_SHARE of its speed when that is slower), and jumps
      COLLECT_HEIGHT_SHARE as high as a gallop jump, staying that slow until it lands.

    Take-off angles at agility 50 (James, 2026-10-30: gallop 30-40 degrees for distance, canter
    45-60, collected 65-80): gallop about 38, canter about 56, collected about 70.

    The numbers can be changed in game with the eqJump console command, until the game restarts.
]]

EqJump = {}

EqJump.GRAVITY = 9.81
EqJump.RISE_SHARE = 2.1
EqJump.FALL_SHARE = 2.7
EqJump.HEIGHT_SHARE = 0.88
EqJump.PUSH_MS = 180
EqJump.PUSH_SPEED = 0.5
EqJump.COLLECT_WINDOW_MS = 500
EqJump.COLLECT_PUSH_MS = 260
EqJump.COLLECT_SPEED_SHARE = 0.5
EqJump.COLLECT_TROT_SHARE = 0.9
EqJump.COLLECT_HEIGHT_SHARE = 1.05

-- What the eqJump console command may change: its short name, the field, and limits.
EqJump.TUNABLE = {
    { name = "rise", key = "RISE_SHARE", min = 1, max = 5 },
    { name = "fall", key = "FALL_SHARE", min = 1, max = 6 },
    { name = "height", key = "HEIGHT_SHARE", min = 0.4, max = 1.5 },
    { name = "push", key = "PUSH_MS", min = 0, max = 600 },
    { name = "lift", key = "PUSH_SPEED", min = 0, max = 3 },
    { name = "window", key = "COLLECT_WINDOW_MS", min = 0, max = 2000 },
    { name = "cpush", key = "COLLECT_PUSH_MS", min = 0, max = 800 },
    { name = "cspeed", key = "COLLECT_SPEED_SHARE", min = 0.1, max = 1 },
    { name = "ctrot", key = "COLLECT_TROT_SHARE", min = 0.2, max = 3 },
    { name = "cheight", key = "COLLECT_HEIGHT_SHARE", min = 0.4, max = 2 },
}


--- The pull down for this frame (pure), as the base game's signed spec.gravity.
--- @param speedY number the horse's vertical speed, m/s (up is positive)
--- @param onGround boolean
--- @return number gravity, negative
function EqJump.gravity(speedY, onGround)
    local share = (not onGround and speedY < 0) and EqJump.FALL_SHARE or EqJump.RISE_SHARE
    return -EqJump.GRAVITY * share
end


--- The vertical speed that reaches a height under a pull (pure).
--- @param height number metres
--- @param gravity number m/s2, either sign
--- @return number m/s
function EqJump.launchSpeed(height, gravity)
    return math.sqrt(2 * math.abs(gravity) * math.max(0, height))
end


--- Time in the air for a jump to a height and back down to the take-off level (pure).
--- @param height number metres
--- @return number seconds
function EqJump.airtime(height)
    local up = math.sqrt(2 * height / (EqJump.GRAVITY * EqJump.RISE_SHARE))
    local down = math.sqrt(2 * height / (EqJump.GRAVITY * EqJump.FALL_SHARE))
    return up + down
end


--- Whether Ctrl asks for a collected jump (pure).
--- @param ctrlDown boolean Ctrl held now
--- @param ctrlAt number|nil when Ctrl was last seen held, ms
--- @param now number ms
--- @return boolean
function EqJump.isCollected(ctrlDown, ctrlAt, now)
    if ctrlDown then return true end
    return ctrlAt ~= nil and now - ctrlAt <= EqJump.COLLECT_WINDOW_MS
end


--- A new take-off (pure): the lift the base game gave the jump becomes a push-off then a launch.
--- @param speedY number the base game's launch speed, m/s
--- @param speed number forward speed at take-off, m/s
--- @param collected boolean
--- @param collectedSpeedY number|nil launch speed for a collected jump
--- @param now number ms
--- @param trotSpeed number|nil the horse's trot top speed, m/s (a collected jump slows to about it)
--- @return table launch
function EqJump.newLaunch(speedY, speed, collected, collectedSpeedY, now, trotSpeed)
    local push = collected and EqJump.COLLECT_PUSH_MS or EqJump.PUSH_MS
    return {
        speedY = collected and collectedSpeedY or speedY,
        startSpeed = speed,
        targetSpeed = collected and EqJump.collectedSpeed(speed, trotSpeed) or nil,
        collected = collected,
        startedAt = now,
        pushMs = push,
        rise = 0,
        launched = push <= 0,
    }
end


--- The speed a collected jump slows to (pure): about a trot, never faster than the horse was going.
--- @param speed number forward speed at take-off, m/s
--- @param trotSpeed number|nil
--- @return number m/s
function EqJump.collectedSpeed(speed, trotSpeed)
    local target = speed * EqJump.COLLECT_SPEED_SHARE
    if trotSpeed ~= nil and trotSpeed > 0 then target = math.min(speed, trotSpeed * EqJump.COLLECT_TROT_SHARE) end
    return target
end


--- Take-off angle above the ground in degrees (pure).
function EqJump.angle(speedY, speed)
    return math.deg(math.atan2(speedY, math.max(0, speed)))
end


--- One frame of the take-off (pure).
--- @param launch table from newLaunch
--- @param now number ms
--- @param dt number ms
--- @param gravity number this frame's signed gravity (the base game adds it before moving)
--- @return number|nil vertical speed to set, nil once launched
--- @return number|nil the most forward speed the horse may have, nil for no limit
function EqJump.step(launch, now, dt, gravity)
    local elapsed = now - launch.startedAt
    local cap = nil
    if launch.targetSpeed ~= nil then
        local t = launch.pushMs > 0 and math.min(1, elapsed / launch.pushMs) or 1
        cap = launch.startSpeed + (launch.targetSpeed - launch.startSpeed) * t
    end
    if launch.launched then return nil, cap end
    if elapsed < launch.pushMs then
        launch.rise = launch.rise + EqJump.PUSH_SPEED * dt / 1000
        -- The base game adds this frame's gravity before it moves the horse: lift by that much more.
        return EqJump.PUSH_SPEED - gravity * dt / 1000, cap
    end
    launch.launched = true
    local left = launch.speedY * launch.speedY - 2 * math.abs(gravity) * launch.rise
    return math.sqrt(math.max(0, left)) - gravity * dt / 1000, cap
end


--- Change a tunable from the console (pure).
--- @param name string a TUNABLE name
--- @param value number
--- @return boolean ok, string message
function EqJump.set(name, value)
    for _, entry in ipairs(EqJump.TUNABLE) do
        if entry.name == name then
            if type(value) ~= "number" then return false, "needs a number" end
            local was = EqJump[entry.key]
            EqJump[entry.key] = math.max(entry.min, math.min(entry.max, value))
            return true, string.format("%s %s -> %s", name, tostring(was), tostring(EqJump[entry.key]))
        end
    end
    return false, "unknown setting " .. tostring(name)
end


--- @return string every tunable and its value
function EqJump.describe()
    local parts = {}
    for _, entry in ipairs(EqJump.TUNABLE) do
        table.insert(parts, string.format("%s %s", entry.name, tostring(EqJump[entry.key])))
    end
    return table.concat(parts, ", ")
end

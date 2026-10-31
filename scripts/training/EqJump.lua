--[[
    EqJump.lua
    How a ridden horse jumps: pure functions with no game calls, so they run headless.
    EqTrainingHooks applies them to the base game's Rideable each frame.

    - Gravity (James, 2026-10-30: jumps felt floaty). The base game pulls a horse down at
      spec_rideable.gravity, 9.81 m/s2, and launches a jump at sqrt(2 g jumpHeight). We set that
      field to RISE_SHARE times as hard on the ground and on the way up, so the launch still
      reaches jumpHeight but sooner, and FALL_SHARE times on the way down, so the horse doesn't
      hang at the top and comes down quickly. HEIGHT_SHARE lowers every jump a little. The pull
      changes smoothly over the top, and fades as the fall nears FALL_MAX m/s (the base game's jump
      lands at about 6.4 m/s): any sudden change in it showed as a stutter in the air (2026-10-31).
    - Push-off: a beat on the ground (PUSH_MS, GALLOP_PUSH_MS) before the launch. A lift during it
      (PUSH_SPEED) made the launch clip run out before the top and restart, so it is off.
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
EqJump.RISE_SHARE = 2.3
EqJump.FALL_SHARE = 2.6
EqJump.BLEND_SPEED = 3
EqJump.FALL_MAX = 7
-- The horse's animation changes pose by spec.isCloseToGround (the hooves under 1.25 m): our lower
-- jumps only just pop over that line, flashing the in-air pose between launch and landing
-- (James, 2026-10-31). CLOSE_MODE 0 leaves it to the base game, 1 keeps it on while rising (the
-- launch pose holds to the top), 2 keeps it on for the whole jump.
EqJump.CLOSE_MODE = 0
EqJump.HEIGHT_SHARE = 0.88
-- James, 2026-10-31: a lift during the push-off started the launch clip early, so it ran out
-- before the top and restarted (a mid-air stutter). The push-off is now a short beat on the
-- ground with no lift (PUSH_SPEED 0) before the launch, as long as each gait's clip allows:
-- James found 80 ms at a canter (PUSH_MS) and 140 ms at a gallop (GALLOP_PUSH_MS) smooth.
EqJump.PUSH_MS = 80
EqJump.GALLOP_PUSH_MS = 140
EqJump.PUSH_SPEED = 0
EqJump.COLLECT_WINDOW_MS = 500
EqJump.COLLECT_PUSH_MS = 260
-- A collected jump gathers on the ground: no lift while it slows, so its launch clip starts at the launch.
EqJump.COLLECT_LIFT = 0
EqJump.COLLECT_SPEED_SHARE = 0.5
EqJump.COLLECT_TROT_SHARE = 0.9
EqJump.COLLECT_HEIGHT_SHARE = 1.05

-- What the eqJump console command may change: its short name, the field, and limits.
EqJump.TUNABLE = {
    { name = "rise", key = "RISE_SHARE", min = 1, max = 5 },
    { name = "fall", key = "FALL_SHARE", min = 1, max = 6 },
    { name = "fallmax", key = "FALL_MAX", min = 2, max = 30 },
    { name = "blend", key = "BLEND_SPEED", min = 0.1, max = 10 },
    { name = "close", key = "CLOSE_MODE", min = 0, max = 2 },
    { name = "height", key = "HEIGHT_SHARE", min = 0.4, max = 1.5 },
    { name = "push", key = "PUSH_MS", min = 0, max = 600 },
    { name = "gpush", key = "GALLOP_PUSH_MS", min = 0, max = 600 },
    { name = "lift", key = "PUSH_SPEED", min = 0, max = 3 },
    { name = "clift", key = "COLLECT_LIFT", min = 0, max = 3 },
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
    if onGround then return -EqJump.GRAVITY * EqJump.RISE_SHARE end
    -- From RISE_SHARE to FALL_SHARE smoothly across the top of the jump (James, 2026-10-31: a
    -- one-frame switch at the top was a mid-air stutter), between BLEND_SPEED up and down.
    local t = math.max(0, math.min(1, (EqJump.BLEND_SPEED - speedY) / (2 * EqJump.BLEND_SPEED)))
    t = t * t * (3 - 2 * t)
    local share = EqJump.RISE_SHARE + (EqJump.FALL_SHARE - EqJump.RISE_SHARE) * t
    -- Easing into FALL_MAX rather than stopping at it: the pull fades as the fall nears it.
    if speedY < 0 then
        local k = math.min(1, -speedY / EqJump.FALL_MAX)
        share = share * (1 - k * k)
    end
    return -EqJump.GRAVITY * share
end


--- The vertical speed to set so the fall stays at FALL_MAX after the base game adds this frame's
--- gravity (pure).
--- @param speedY number m/s
--- @param onGround boolean
--- @param gravity number signed m/s2
--- @param dt number ms
--- @return number|nil speed to set, nil when no change is needed
function EqJump.fallCap(speedY, onGround, gravity, dt)
    if onGround then return nil end
    local next = speedY + gravity * dt / 1000
    if next >= -EqJump.FALL_MAX then return nil end
    return -EqJump.FALL_MAX - gravity * dt / 1000
end


--- What the animation is told about being close to the ground in a jump (pure).
--- @param baseClose boolean the base game's own answer
--- @param speedY number m/s
--- @return boolean
function EqJump.closeToGround(baseClose, speedY)
    local mode = math.floor(EqJump.CLOSE_MODE + 0.5)
    if mode == 2 or (mode == 1 and speedY > 0) then return true end
    return baseClose
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
    -- Stepped through in 5 ms frames, as the game would.
    local dt, y, t = 0.005, 0, 0
    local v = EqJump.launchSpeed(height, EqJump.gravity(0, true))
    repeat
        local capped = EqJump.fallCap(v, false, EqJump.gravity(v, false), dt * 1000)
        if capped ~= nil then v = capped end
        v = v + EqJump.gravity(v, false) * dt
        y, t = y + v * dt, t + dt
    until y <= 0 or t > 10
    return t
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
--- @param gait string|nil the gait it took off from ("gallop" takes GALLOP_PUSH_MS)
--- @return table launch
function EqJump.newLaunch(speedY, speed, collected, collectedSpeedY, now, trotSpeed, gait)
    local push = collected and EqJump.COLLECT_PUSH_MS or (gait == "gallop" and EqJump.GALLOP_PUSH_MS or EqJump.PUSH_MS)
    return {
        speedY = collected and collectedSpeedY or speedY,
        startSpeed = speed,
        targetSpeed = collected and EqJump.collectedSpeed(speed, trotSpeed) or nil,
        collected = collected,
        startedAt = now,
        pushMs = push,
        lift = collected and EqJump.COLLECT_LIFT or EqJump.PUSH_SPEED,
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
        launch.rise = launch.rise + launch.lift * dt / 1000
        -- The base game adds this frame's gravity before it moves the horse: lift by that much more.
        return launch.lift - gravity * dt / 1000, cap
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

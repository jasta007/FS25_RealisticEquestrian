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
-- James, 2026-10-31, after testing: rise 3.5 and fall 3 at a canter, so the climb ends before
-- the launch clip does (with the push-off's lift below).
EqJump.RISE_SHARE = 3.5
EqJump.FALL_SHARE = 3
EqJump.BLEND_SPEED = 3
EqJump.FALL_MAX = 7
-- The horse's animation changes pose by spec.isCloseToGround (the hooves under 1.25 m): our lower
-- jumps only just pop over that line, flashing the in-air pose between launch and landing
-- (James, 2026-10-31). CLOSE_MODE 0 leaves it to the base game, 1 keeps it on while rising (the
-- launch pose holds to the top), 2 keeps it on for the whole jump, 3 turns it on once the fall
-- passes CLOSE_FALL_SPEED (James: the landing clip played a bit late).
EqJump.CLOSE_MODE = 3
EqJump.CLOSE_FALL_SPEED = 1
-- ...but higher than CLOSE_DROP_M off the ground, no sooner than CLOSE_LEAD_S seconds from it at
-- the speed it falls: off a high wall the landing clip played out mid-air and began again on
-- touching down (James, 2026-10-31). An ordinary jump stays lower and is unchanged.
EqJump.CLOSE_DROP_M = 1.6
EqJump.CLOSE_LEAD_S = 0.3
-- The quicker jump covered too little ground to clear things (James): a jump carries a share of
-- its take-off speed through the air, eased in over CARRY_EASE_MS. Not at a gallop (James: 1.25
-- there snapped the horse forwards into "hyper speed"), nor once the rider asks for a slower gait
-- (it ran on at a gallop for steps after landing), nor in a Ctrl jump.
EqJump.AIR_CARRY = 1.45
EqJump.GALLOP_CARRY = 1
EqJump.TROT_CARRY = 1.8
EqJump.CARRY_EASE_MS = 250
EqJump.HEIGHT_SHARE = 0.88
-- James, 2026-10-31: the push-off's small lift starts the launch clip while the hind legs are
-- still on the ground, but the clip must last until the top of the climb or it restarts (a
-- mid-air stutter), so the climb is quick (RISE_SHARE). James found 80 ms at 0.5 m/s smooth at a
-- canter and 120 ms at a gallop (140 hinted at a stutter).
EqJump.PUSH_MS = 80
EqJump.GALLOP_PUSH_MS = 120
EqJump.PUSH_SPEED = 0.5
EqJump.COLLECT_WINDOW_MS = 500
EqJump.COLLECT_PUSH_MS = 260
-- A jump from a trot (James, 2026-10-31: simpler than hiding the high jump behind Ctrl; the base
-- game allows jumps only from a canter) is a collected jump. It is slow already, so its gather
-- on the ground is only TROT_PUSH_MS.
EqJump.TROT_PUSH_MS = 80
-- ...and lower than the Ctrl jump, but longer (James): TROT_HEIGHT_SHARE of a gallop jump.
EqJump.TROT_HEIGHT_SHARE = 0.8
-- A collected jump gathers on the ground: no lift while it slows, so its launch clip starts at the launch.
EqJump.COLLECT_LIFT = 0
EqJump.COLLECT_SPEED_SHARE = 0.5
EqJump.COLLECT_TROT_SHARE = 1.15
EqJump.COLLECT_HEIGHT_SHARE = 1.05

-- Temperament aims a horse at the middle of the jump ahead (James, 2026-10-31: near the
-- middle it goes where it is pointed; off centre a steady horse tries to jump where it scores
-- rather than run out or shave the end). Only show jumps and cross country fences, never dressage.
-- Ends of the jump count as -1 and +1: inside AIM_CENTRE nothing happens, the pull is full to
-- AIM_FULL and fades out by AIM_WIDE (pointing well past the end means the rider is going round).
EqJump.AIM_CENTRE = 0.45
EqJump.AIM_FULL = 1.3
EqJump.AIM_WIDE = 2
-- Looked for between these distances ahead, approached no more than AIM_ANGLE degrees off square.
EqJump.AIM_NEAR = 2
EqJump.AIM_REACH = 18
EqJump.AIM_ANGLE = 60
-- From this temperament up, full at 100; turn rate = heading error x AIM_GAIN, at most AIM_RATE rad/s.
EqJump.AIM_FROM = 50
EqJump.AIM_GAIN = 2
EqJump.AIM_RATE = 0.35

-- What the eqJump console command may change: its short name, the field, and limits.
EqJump.TUNABLE = {
    { name = "rise", key = "RISE_SHARE", min = 1, max = 5 },
    { name = "fall", key = "FALL_SHARE", min = 1, max = 6 },
    { name = "fallmax", key = "FALL_MAX", min = 2, max = 30 },
    { name = "blend", key = "BLEND_SPEED", min = 0.1, max = 10 },
    { name = "close", key = "CLOSE_MODE", min = 0, max = 3 },
    { name = "closefall", key = "CLOSE_FALL_SPEED", min = 0, max = 10 },
    { name = "closedrop", key = "CLOSE_DROP_M", min = 0, max = 10 },
    { name = "closelead", key = "CLOSE_LEAD_S", min = 0, max = 2 },
    { name = "carry", key = "AIR_CARRY", min = 0.5, max = 2.5 },
    { name = "gcarry", key = "GALLOP_CARRY", min = 0.5, max = 2.5 },
    { name = "tcarry", key = "TROT_CARRY", min = 0.5, max = 3 },
    { name = "theight", key = "TROT_HEIGHT_SHARE", min = 0.3, max = 2 },
    { name = "height", key = "HEIGHT_SHARE", min = 0.4, max = 1.5 },
    { name = "push", key = "PUSH_MS", min = 0, max = 600 },
    { name = "gpush", key = "GALLOP_PUSH_MS", min = 0, max = 600 },
    { name = "tpush", key = "TROT_PUSH_MS", min = 0, max = 600 },
    { name = "lift", key = "PUSH_SPEED", min = 0, max = 3 },
    { name = "clift", key = "COLLECT_LIFT", min = 0, max = 3 },
    { name = "window", key = "COLLECT_WINDOW_MS", min = 0, max = 2000 },
    { name = "cpush", key = "COLLECT_PUSH_MS", min = 0, max = 800 },
    { name = "cspeed", key = "COLLECT_SPEED_SHARE", min = 0.1, max = 1 },
    { name = "ctrot", key = "COLLECT_TROT_SHARE", min = 0.2, max = 3 },
    { name = "cheight", key = "COLLECT_HEIGHT_SHARE", min = 0.4, max = 2 },
    { name = "aimcentre", key = "AIM_CENTRE", min = 0, max = 1 },
    { name = "aimwide", key = "AIM_WIDE", min = 1, max = 4 },
    { name = "aimreach", key = "AIM_REACH", min = 4, max = 40 },
    { name = "aimfrom", key = "AIM_FROM", min = 0, max = 100 },
    { name = "aimrate", key = "AIM_RATE", min = 0, max = 2 },
    { name = "aimgain", key = "AIM_GAIN", min = 0, max = 10 },
}


--- How hard temperament aims (pure): 0 below AIM_FROM, 1 at 100.
--- @param temperament number|nil
--- @return number 0..1
function EqJump.aimStrength(temperament)
    local from = EqJump.AIM_FROM
    if from >= 100 then return (temperament or 0) >= 100 and 1 or 0 end
    return math.max(0, math.min(1, ((temperament or 50) - from) / (100 - from)))
end


--- The jump the horse is heading for (pure), in the horse's own space: it stands at 0,0 facing
--- +z, +x on its left. Each jump is { ax, az, bx, bz }, its two ends.
--- @param jumps table
--- @return table|nil jump, number|nil offset (-1 at a, +1 at b), number|nil distance ahead
function EqJump.jumpAhead(jumps)
    local best, bestOffset, bestDistance = nil, nil, nil
    local square = math.cos(math.rad(EqJump.AIM_ANGLE))
    for _, jump in ipairs(jumps) do
        local dx, dz = jump.bx - jump.ax, jump.bz - jump.az
        local length = math.sqrt(dx * dx + dz * dz)
        -- across the horse's path, near enough square on
        if length > 0.1 and math.abs(dx) / length >= square then
            local p = -jump.ax / dx
            local distance = jump.az + p * dz
            local offset = (p - 0.5) * 2
            if distance >= EqJump.AIM_NEAR and distance <= EqJump.AIM_REACH and math.abs(offset) <= EqJump.AIM_WIDE
                and (bestDistance == nil or distance < bestDistance) then
                best, bestOffset, bestDistance = jump, offset, distance
            end
        end
    end
    return best, bestOffset, bestDistance
end


--- Temperament's turn toward the middle of the jump ahead (pure), in rad/s, positive to the
--- left. Nothing near the middle, below AIM_FROM, or while the rider steers the other way.
--- @param jumps table in the horse's space (see jumpAhead)
--- @param temperament number|nil
--- @param axis number|nil the rider's steering, right positive
--- @return number rate, table|nil jump, number|nil offset
function EqJump.aim(jumps, temperament, axis)
    local strength = EqJump.aimStrength(temperament)
    if strength <= 0 then return 0 end
    local jump, offset = EqJump.jumpAhead(jumps)
    if jump == nil or math.abs(offset) <= EqJump.AIM_CENTRE then return 0, jump, offset end
    local wide = math.abs(offset)
    local fade = 1
    if wide > EqJump.AIM_FULL then
        fade = math.max(0, (EqJump.AIM_WIDE - wide) / math.max(0.01, EqJump.AIM_WIDE - EqJump.AIM_FULL))
    end
    -- aim just inside the middle band, on the same side
    local side = offset > 0 and 1 or -1
    local p = 0.5 + side * EqJump.AIM_CENTRE * 0.25
    local tx = jump.ax + p * (jump.bx - jump.ax)
    local tz = jump.az + p * (jump.bz - jump.az)
    local err = math.atan2(tx, tz)
    local rate = math.max(-EqJump.AIM_RATE, math.min(EqJump.AIM_RATE, err * EqJump.AIM_GAIN)) * strength * fade
    -- The rider steering away wins: a rider going round the jump is let go.
    if axis ~= nil and axis ~= 0 and ((rate > 0 and axis > 0) or (rate < 0 and axis < 0)) then return 0, jump, offset end
    return rate, jump, offset
end


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
--- @param groundDistance number|nil metres down to the ground, nil when not known
--- @return boolean
function EqJump.closeToGround(baseClose, speedY, groundDistance)
    local mode = math.floor(EqJump.CLOSE_MODE + 0.5)
    if mode == 2 or (mode == 1 and speedY > 0) then return true end
    if mode == 3 and speedY < -EqJump.CLOSE_FALL_SPEED
        and (groundDistance == nil or groundDistance <= EqJump.CLOSE_DROP_M
            or groundDistance / -speedY <= EqJump.CLOSE_LEAD_S) then return true end
    return baseClose
end


--- The least forward speed a jump in the air keeps (pure), nil for no floor.
--- @param launch table from newLaunch
--- @param now number ms
--- @param gaitTop number|nil top speed of the gait the rider now asks for, m/s
--- @return number|nil m/s
function EqJump.carrySpeed(launch, now, gaitTop)
    if not launch.launched or (launch.collected and not launch.trot) then return nil end
    if gaitTop ~= nil and gaitTop < launch.startSpeed * 0.95 then return nil end
    local carry = EqJump.AIR_CARRY
    if launch.trot then carry = EqJump.TROT_CARRY elseif launch.gait == "gallop" then carry = EqJump.GALLOP_CARRY end
    local t = EqJump.CARRY_EASE_MS > 0 and math.min(1, math.max(0, (now - (launch.launchedAt or now)) / EqJump.CARRY_EASE_MS)) or 1
    return launch.startSpeed * (1 + (carry - 1) * t)
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


--- Whether a jump is collected (pure): from a trot, or with Ctrl.
--- @param ctrlDown boolean Ctrl held now
--- @param ctrlAt number|nil when Ctrl was last seen held, ms
--- @param now number ms
--- @param gait string|nil the gait it took off from
--- @return boolean
function EqJump.isCollected(ctrlDown, ctrlAt, now, gait)
    if ctrlDown or gait == "trot" then return true end
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
    local push = EqJump.PUSH_MS
    if collected then
        push = gait == "trot" and EqJump.TROT_PUSH_MS or EqJump.COLLECT_PUSH_MS
    elseif gait == "gallop" then
        push = EqJump.GALLOP_PUSH_MS
    end
    return {
        speedY = collected and collectedSpeedY or speedY,
        startSpeed = speed,
        -- A trot jump keeps its pace (it carries, see carrySpeed); a Ctrl jump slows to about a trot.
        targetSpeed = (collected and gait ~= "trot") and EqJump.collectedSpeed(speed, trotSpeed) or nil,
        collected = collected,
        trot = collected and gait == "trot",
        gait = gait,
        startedAt = now,
        pushMs = push,
        lift = collected and EqJump.COLLECT_LIFT or EqJump.PUSH_SPEED,
        rise = 0,
        launched = push <= 0,
        launchedAt = push <= 0 and now or nil,
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
    launch.launched, launch.launchedAt = true, now
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

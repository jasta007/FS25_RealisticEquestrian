--[[
    EqExertion.lua
    The exertion system: pure functions with no game calls, so they run headless.

    Exertion only works at a gallop, which has three paces (James, 2026-10-27: a racehorse gallops
    the whole way, and dropping to a canter is like going from 6th gear to 3rd):
    - Pushing: the gallop the horse starts in (W from a canter). Its top speed comes from the Speed
      stat. Exertion rises, faster the higher it is, more slowly for a horse with more Stamina.
    - Recovering: S from Pushing. A slower gallop that brings exertion back down to empty, and
      stays a gallop until the rider asks for a canter.
    - Sprinting: tap W quickly SPRINT_TAPS times while galloping, and keep tapping. Much faster;
      exertion rises slowly at first and ever faster, so taking it as high as possible without
      crossing the line is the skill. Quick taps slow the rise for a while. Ending a Sprint goes to
      Recovering. Only a Sprint may go past the Blowing Hard line, into a last gasp that ends at
      EXERTION_MAX. After a Sprint the horse can Push but not Sprint again until exertion is empty.

    Pushing up to the Blowing Hard line (LINE) blows the horse: it drops to a canter and can't
    gallop again until exertion is empty. A Sprint that ends past the line leaves it exhausted:
    the same, but while exertion is still past the line it falls only SPENT_SHARE as fast. At a
    canter or slower exertion falls fast, faster the slower the gait.

    Slowing from a gallop to a canter takes one press of S while Recovering with exertion empty,
    or else a quick double tap. EqTrainingHooks keeps the base game's gait in line with this.

    Training doesn't steer any of this: it only changes the stats this reads.
]]

EqExertion = {}

-- Exertion 0-100 is the gallop; LINE is Blowing Hard; a Sprint's last gasp runs on to EXERTION_MAX.
EqExertion.LINE = 100
EqExertion.EXERTION_MAX = 130

-- Pushing: PUSH_RISE per second when empty, PUSH_CLIMB times more at the line.
EqExertion.PUSH_RISE = 2.2
EqExertion.PUSH_CLIMB = 1
-- Recovering: exertion falls this much per second in each third of the gallop (EqExertion.band):
-- fast from the top third, slowly through the middle "zone", fast again in the bottom third
-- (James, 2026-10-27: the stamina multiplier follows the same pattern, see EqTraining).
EqExertion.RECOVER_DROP = { high = 5, zone = 1.8, low = 5 }
-- Sprinting: SPRINT_RISE per second at the start, SPRINT_RAMP more for every second it lasts, up
-- to SPRINT_RISE_MAX; the same on both sides of the line. (James, 2026-10-27: start slowly and get
-- faster pretty rapidly, especially when the taps are slow, so stopping just short of the line
-- is a challenge.)
EqExertion.SPRINT_RISE = 3
EqExertion.SPRINT_RAMP = 2.2
EqExertion.SPRINT_SLOW_RAMP = 1.8
EqExertion.SPRINT_RISE_MAX = 20
-- Canter and slower: exertion falls this much per second.
EqExertion.FALL = { canter = 9, trot = 12, reverse = 12, walk = 14, halt = 16 }
-- Exhausted (a Sprint ended past the line): while still past the line it falls at this share of
-- the rate (slower gaits still help).
EqExertion.SPENT_SHARE = 0.2

-- Stats change the rates: how fast Pushing tires the horse, by Stamina (stat 0 to 100), how fast
-- it gets its breath back (Recovering, cantering or slower), by Stamina, and how fast a Sprint
-- tires it, by Speed.
EqExertion.PUSH_STAMINA = { 1.4, 0.65 }
EqExertion.RECOVER_STAMINA = { 0.75, 1.3 }
EqExertion.SPRINT_SPEED = { 1.3, 0.75 }

-- Gallop top speed by pace, on top of the Speed stat's handling (EqTraining.handling).
EqExertion.GALLOP_SHARE = { recover = 0.8, push = 1, sprint = 1.25 }

-- Sprint: SPRINT_TAPS presses of W, each within SPRINT_TAP_GAP_MS of the last, start it. It
-- ends when no tap comes for SPRINT_KEEP_MS. Taps ease the rise by up to SPRINT_TAP_EASE: fully
-- at a tap every SPRINT_FAST_TAP_MS, not at all from SPRINT_SLOW_TAP_MS, and less as the Sprint
-- goes on, to nothing after SPRINT_EASE_MS.
EqExertion.SPRINT_TAPS = 3
EqExertion.SPRINT_TAP_GAP_MS = 400
EqExertion.SPRINT_KEEP_MS = 600
EqExertion.SPRINT_TAP_EASE = 0.4
EqExertion.SPRINT_FAST_TAP_MS = 130
EqExertion.SPRINT_SLOW_TAP_MS = 450
EqExertion.SPRINT_EASE_MS = 10000

-- Two presses of S this close together are a double tap. A press that allows a canter allows it
-- for DROP_GRACE_MS, in case the base game changes gait a frame later.
EqExertion.DOUBLE_TAP_MS = 400
EqExertion.DROP_GRACE_MS = 300

-- The bar, as shares of its width: a line per slow gait, then the gallop from the canter line to
-- the Blowing Hard line, then the last gasp. James's drawing (2026-10-27).
EqExertion.BAR = { reverse = 0, halt = 0.033, walk = 0.065, trot = 0.13, canter = 0.26, line = 0.83, finish = 1 }


--- @return table ex a rested horse
function EqExertion.new()
    return { value = 0, mode = nil, lock = nil, clock = 0, taps = 0, tapAt = -math.huge, backAt = -math.huge,
        dropUntil = -math.huge, sprintMs = 0, tapGap = nil, sprinted = false }
end


--- @param limits table { at stat 0, at stat 100 }
--- @param stat number|nil nil reads as 50
--- @return number
local function byStat(limits, stat)
    local t = math.min(math.max((stat or 50) / 100, 0), 1)
    return limits[1] + (limits[2] - limits[1]) * t
end


--- @param value number exertion
--- @return string band "low", "zone" or "high": the third of the gallop it is in
function EqExertion.band(value)
    if value < EqExertion.LINE / 3 then return "low" end
    if value < EqExertion.LINE * 2 / 3 then return "zone" end
    return "high"
end


--- @param ex table
--- @return boolean true while the horse is galloping in one of the three paces
function EqExertion.isGalloping(ex)
    return ex.mode ~= nil
end


--- @param ex table
--- @param kind string "blown" or "spent"
local function lockOut(ex, kind)
    ex.lock, ex.mode, ex.taps = kind, nil, 0
end


--- Note how a Sprint ended, for speed training: ex.lastSprint = { value, over }, over when it
--- ended at or past the Blowing Hard line.
--- @param ex table
local function recordSprint(ex)
    ex.lastSprint = { value = ex.value, over = ex.value >= EqExertion.LINE }
    ex.sprintMs, ex.tapGap, ex.sprinted = 0, nil, true
end


--- End a Sprint: on to Recovering, or exhausted when it ended past the line. No new Sprint
--- until exertion is empty.
--- @param ex table
--- @return string event "sprintOver" or "spent"
local function endSprint(ex)
    recordSprint(ex)
    if ex.value >= EqExertion.LINE then
        lockOut(ex, "spent")
        return "spent"
    end
    ex.mode, ex.taps = "recover", 0
    return "sprintOver"
end


--- @param ex table
--- @return boolean true when taps of W would start a Sprint
function EqExertion.canSprint(ex)
    return (ex.mode == "push" or ex.mode == "recover") and not ex.sprinted
end


--- @param ex table
--- @return boolean true when one press of S slows to a canter (else it takes a double tap)
function EqExertion.canterOnOneTap(ex)
    return ex.mode == "recover" and ex.value <= 0
end


--- Exertion change per second.
--- @param ex table
--- @param gait string reverse, halt, walk, trot, canter or gallop
--- @param stamina number|nil trained stamina
--- @param speed number|nil trained speed
--- @return number per second
function EqExertion.rate(ex, gait, stamina, speed)
    local v = ex.value
    if ex.mode == "push" then
        return EqExertion.PUSH_RISE * (1 + EqExertion.PUSH_CLIMB * math.min(v, EqExertion.LINE) / EqExertion.LINE)
            * byStat(EqExertion.PUSH_STAMINA, stamina)
    elseif ex.mode == "recover" then
        return -EqExertion.RECOVER_DROP[EqExertion.band(v)] * byStat(EqExertion.RECOVER_STAMINA, stamina)
    elseif ex.mode == "sprint" then
        -- Tapping pace, 1 for quick taps (and the quick taps that started the Sprint) to 0 for slow.
        local pace = 1
        if ex.tapGap ~= nil then
            pace = (EqExertion.SPRINT_SLOW_TAP_MS - ex.tapGap) / (EqExertion.SPRINT_SLOW_TAP_MS - EqExertion.SPRINT_FAST_TAP_MS)
            pace = math.min(math.max(pace, 0), 1)
        end
        local fade = math.min(math.max(1 - ex.sprintMs / EqExertion.SPRINT_EASE_MS, 0), 1)
        local ease = EqExertion.SPRINT_TAP_EASE * pace * fade
        -- Slow tapping also steepens the ramp, up to SPRINT_SLOW_RAMP times.
        local ramp = EqExertion.SPRINT_RAMP * (1 + (EqExertion.SPRINT_SLOW_RAMP - 1) * (1 - pace))
        local rise = math.min(EqExertion.SPRINT_RISE + ramp * ex.sprintMs / 1000, EqExertion.SPRINT_RISE_MAX)
        return rise * byStat(EqExertion.SPRINT_SPEED, speed) * (1 - ease)
    end
    local fall = EqExertion.FALL[gait] or EqExertion.FALL.canter
    local spent = ex.lock == "spent" and v > EqExertion.LINE
    return -fall * byStat(EqExertion.RECOVER_STAMINA, stamina) * (spent and EqExertion.SPENT_SHARE or 1)
end


--- One frame.
--- @param ex table
--- @param gait string the horse's gait this frame (reverse, halt, walk, trot, canter or gallop)
--- @param dt number milliseconds
--- @param stamina number|nil trained stamina
--- @param speed number|nil trained speed
--- @return string|nil event "blown", "spent", "sprintOver" or "fresh" (gallop allowed again)
function EqExertion.step(ex, gait, dt, stamina, speed)
    if dt <= 0 then return nil end
    ex.clock = ex.clock + dt
    local event = nil
    if gait == "gallop" and ex.lock == nil then
        if ex.mode == nil then ex.mode, ex.taps = "push", 0 end
    elseif ex.mode ~= nil then
        -- Out of the gallop: a Sprint that ends past the line leaves the horse exhausted.
        if ex.mode == "sprint" then
            recordSprint(ex)
            if ex.value >= EqExertion.LINE then
                lockOut(ex, "spent")
                event = "spent"
            else
                event = "sprintOver"
            end
        end
        ex.mode, ex.sprintMs, ex.tapGap = nil, 0, nil
    end
    if ex.mode == "sprint" then
        ex.sprintMs = ex.sprintMs + dt
        if ex.clock - ex.tapAt > EqExertion.SPRINT_KEEP_MS then event = endSprint(ex) end
    end

    local value = ex.value + EqExertion.rate(ex, gait, stamina, speed) * dt / 1000
    ex.value = math.min(math.max(value, 0), EqExertion.EXERTION_MAX)
    if ex.mode == "push" and ex.value >= EqExertion.LINE then
        ex.value = EqExertion.LINE
        lockOut(ex, "blown")
        event = "blown"
    elseif ex.mode == "sprint" and ex.value >= EqExertion.EXERTION_MAX then
        endSprint(ex)
        event = "spent"
    end
    if ex.value <= 0 then
        ex.sprinted = false
        if ex.lock ~= nil then
            ex.lock = nil
            event = "fresh"
        end
    end
    return event
end


--- The rider pressed W (forward) or S (back). Call before the base game acts on the key.
--- @param ex table
--- @param key string "forward" or "back"
--- @return string|nil event "push", "recover", "sprint", "tap" (during a Sprint), "spent" or
---     "canter" (a canter is allowed now)
function EqExertion.press(ex, key)
    local now = ex.clock
    if key == "forward" then
        if ex.mode == nil then return nil end
        if ex.mode == "sprint" then
            ex.tapGap, ex.tapAt = now - ex.tapAt, now
            return "tap"
        end
        ex.taps = now - ex.tapAt <= EqExertion.SPRINT_TAP_GAP_MS and ex.taps + 1 or 1
        ex.tapAt = now
        if ex.taps >= EqExertion.SPRINT_TAPS and not ex.sprinted then
            ex.mode, ex.sprintMs, ex.tapGap, ex.taps = "sprint", 0, nil, 0
            return "sprint"
        end
        if ex.mode == "recover" then
            ex.mode = "push"
            return "push"
        end
        return nil
    end

    local double = now - ex.backAt <= EqExertion.DOUBLE_TAP_MS
    ex.backAt = now
    if ex.mode == nil then return nil end
    if double or (ex.mode == "recover" and ex.value <= 0) then
        ex.dropUntil = now + EqExertion.DROP_GRACE_MS
        return "canter"
    end
    if ex.mode == "sprint" then
        if endSprint(ex) == "spent" then return "spent" end
    end
    ex.mode = "recover"
    return "recover"
end


--- Whether the horse may change gait from one to the other now.
--- @param ex table
--- @param from string
--- @param to string
--- @return boolean
function EqExertion.allowGait(ex, from, to)
    if to == "gallop" and from ~= "gallop" then return ex.lock == nil end
    if from == "gallop" and to == "canter" then
        return ex.mode == nil or ex.clock <= ex.dropUntil
    end
    return true
end


--- @param ex table
--- @return string|nil gait the horse has to drop to: "canter" while blown or exhausted
function EqExertion.forcedGait(ex)
    return ex.lock ~= nil and "canter" or nil
end


--- @param ex table
--- @return number share of the gallop's top speed for the pace
function EqExertion.speedShare(ex)
    return EqExertion.GALLOP_SHARE[ex.mode] or 1
end


--- Where the marker sits on the bar: on the gait's line while exertion is empty, else along
--- the gallop (and past the Blowing Hard line in a last gasp).
--- @param ex table
--- @param gait string
--- @return number share 0..1 of the bar
function EqExertion.marker(ex, gait)
    local bar = EqExertion.BAR
    if ex.value <= 0 then
        if gait == "gallop" then return bar.canter end
        return bar[gait] or bar.canter
    end
    if ex.value <= EqExertion.LINE then
        return bar.canter + (bar.line - bar.canter) * ex.value / EqExertion.LINE
    end
    return bar.line + (bar.finish - bar.line) * (ex.value - EqExertion.LINE) / (EqExertion.EXERTION_MAX - EqExertion.LINE)
end


--- What the horse is doing, for the words above the bar.
--- @param ex table
--- @param gait string
--- @return string state push, recover, sprint, blown, spent, or the gait
function EqExertion.state(ex, gait)
    return ex.mode or ex.lock or gait
end


--- Time out of the saddle rests the horse like standing still.
--- @param ex table
--- @param ms number
--- @param stamina number|nil
function EqExertion.rest(ex, ms, stamina)
    if ms <= 0 then return end
    ex.mode, ex.taps, ex.sprintMs, ex.tapGap = nil, 0, 0, nil
    EqExertion.step(ex, "halt", ms, stamina)
end

--[[
    EqTraining.lua
    The training maths: pure functions with no game or RLRM calls, so they run headless.

    A day's work comes from two places:
    - The player's own riding. EqTrainingHooks records milliseconds spent in each gait and
      jumps taken into a "sheet" per horse. Each gait trains a different mix of stats.
    - Staff. Whatever share of RLRM's riding value the player's sheet does not explain was put
      there by someone else: the base game's animal worker, or RLRM's herdsman horse-care rule.
      Staff train to the horse's focus profile and stop at STAFF_CAP of each ceiling.

    Stamina and speed are focused work. Most of what they learn comes from how the horse is
    worked, not how long: an exertion meter (a short-term one, separate from the riding bar, which
    is the day's energy) rises in canter and gallop and falls at slower gaits and at a halt.
    Stamina comes from runs (full after RUN_FULL seconds) that hold the meter high but not too high; speed comes from
    galloping while the meter is low, so the best speed work is sprints with rests between. Just
    riding the gaits trains them at UNFOCUSED_SHARE of the gait weights below.

    Each stat closes a share of the gap to its cap every month (scaled to the day with the
    game's timeAdjustment), so gains slow as a horse nears its ceiling. Idle horses fade.
    The farm's horse facilities (EqFacility.boosts) and what the horse is fed (EqFeed.dietBoost)
    speed that up per stat, adding together; riding inside a facility speeds the player's own work
    up more. They never add work.
]]

EqTraining = {}

-- Effort each gait gives per full day of training (TRAINING_FULL_MS in that gait), by stat.
EqTraining.GAIT_WEIGHTS = {
    walk = { temperament = 1.0, stamina = 0.3 },
    trot = { temperament = 0.6, stamina = 0.6, agility = 0.3 },
    canter = { stamina = 0.8, agility = 0.8, temperament = 0.3 },
    gallop = { speed = 1.0, stamina = 0.8 },
    -- Backing up is slow, fiddly schooling: a little of it does a lot for balance and manners.
    reverse = { agility = 2.0, temperament = 2.0 },
}

-- Stats trained by focused work (see step); their gait weights count at UNFOCUSED_SHARE.
EqTraining.UNFOCUSED_SHARE = { stamina = 0.1, speed = 0.1, agility = 0.15, temperament = 0.08 }

-- The most effort a day can give each stat. Good focused work goes past the old full day (1).
EqTraining.EFFORT_CAP = { stamina = 2, speed = 2, agility = 2, temperament = 2 }

-- AGILITY: jumps that clear something (EqTrainingHooks checks under the horse in the air).
-- Each clear in a row raises the combo, worth up to COMBO_MAX times AGILITY_PER_JUMP. The
-- combo is lost COMBO_SECONDS after the last clear, a clock that runs COMBO_SLOW_DRAIN times as
-- fast at a halt, a walk or backing up, so slowing to a trot for a tight fence is fine.
EqTraining.AGILITY_PER_JUMP = 0.015
-- A jump over nothing still trains a little, without touching the combo.
EqTraining.AGILITY_PER_EMPTY_JUMP = 0.004
EqTraining.COMBO_MAX = 5
EqTraining.COMBO_SECONDS = 10
EqTraining.COMBO_SLOW_DRAIN = 10
-- After a combo is lost, jumps start no new one for this long (so a late 'Clear!' can't follow).
EqTraining.COMBO_LOCK_MS = 2500
-- Hitting something (a crash, or a jump that hits or lands on the obstacle) takes this much
-- off the combo clock rather than ending the combo, at most once every COMBO_KNOCK_GAP_MS.
EqTraining.COMBO_KNOCK_SECONDS = 3
EqTraining.COMBO_KNOCK_GAP_MS = 3000

-- TEMPERAMENT: a routine. Walk for ROUTINE_START_MS to start one; then every ROUTINE_GAP_MS
-- (a random time in the range) the rider is asked for a new movement and has ROUTINE_REACT_MS
-- to start it. Each one done raises the multiplier, up to COMBO_MAX; a miss, a canter, a gallop
-- or a jump ends the routine. Temperament builds at TEMPERAMENT_RATE per second for each step
-- of multiplier above x1. Gaits and turns are judged apart: a rider must steer round things
-- whatever the routine asks, so a gait request ignores steering and a turn request (holding
-- the left or right key for ROUTINE_STEER_MS) takes any gait short of a canter.
EqTraining.ROUTINE_START_MS = 2000
EqTraining.ROUTINE_STEER_MS = 300
EqTraining.ROUTINE_GAP_MS = { 5000, 8000 }
EqTraining.ROUTINE_TURN_GAP_MS = { 3000, 4000 }
EqTraining.ROUTINE_REACT_MS = 3000
-- After a full stop the next request comes sooner (James: waiting at a halt was boring).
EqTraining.ROUTINE_HALT_GAP_MS = { 2500, 4000 }
-- The routine gets more stressful as its multiplier climbs: for each step above x1, gaps
-- between requests shrink by ROUTINE_GAP_PRESSURE and the time to react by ROUTINE_REACT_PRESSURE
-- (at x5: gaps 70%, 2.4 s to react).
EqTraining.ROUTINE_GAP_PRESSURE = 0.075
EqTraining.ROUTINE_REACT_PRESSURE = 0.05
EqTraining.ROUTINE_MOVES = { "walk", "trot", "halt", "reverse", "left", "right" }
EqTraining.TEMPERAMENT_RATE = 0.0022

-- Exertion meter (0-100) change per second, by gait. "halt" is standing still. Canter is
-- worked out in exertionRate: it levels off rather than climbing for ever.
-- A trot drops exertion fast, so a short one brings a run back down into the stamina zone.
EqTraining.TIREDNESS_RATE = { halt = -3, walk = -3, reverse = -1, trot = -3, canter = 0, gallop = 3 }

-- Below RECOVER_BELOW exertion, standing or walking recovers faster: RECOVER_UNFIT_SHARE times
-- as fast for an unfit horse, up to RECOVER_FIT_SHARE for a fit one, so the wait between sprints
-- stays short.
EqTraining.RECOVER_BELOW = 30
EqTraining.RECOVER_UNFIT_SHARE = 2
EqTraining.RECOVER_FIT_SHARE = 4
-- That fast recovery also starts at any exertion once the horse has stood still SETTLE_HALT_MS,
-- or walked (or stood) SETTLE_WALK_MS, a walk at SETTLE_WALK_SHARE of the rate.
EqTraining.SETTLE_HALT_MS = 4000
EqTraining.SETTLE_WALK_MS = 5000
EqTraining.SETTLE_WALK_SHARE = 0.75

-- A fit horse's riding bar fills more slowly: up to BAR_FIT_SHARE times longer at stamina 100,
-- from no change at BAR_FROM_STAMINA and below.
EqTraining.BAR_FROM_STAMINA = 50
EqTraining.BAR_FIT_SHARE = 1.4

-- A canter raises exertion at CANTER_RISE per second up to a level inside the zone (72, plus
-- CANTER_LEVEL_PER_STAMINA per stamina point), then keeps creeping up for as long as it goes on,
-- at CANTER_CREEP_MIN + CANTER_CREEP_UNFIT x (1 - stamina/100)^1.5 per second. So every horse
-- blows in the end, a fit one only after a long canter (an unfit horse after about a minute,
-- an average one after a minute and a half, a stamina-80 one after more than two).
EqTraining.CANTER_RISE = 2
EqTraining.CANTER_LEVEL_BASE = 72
EqTraining.CANTER_LEVEL_PER_STAMINA = 0.08
EqTraining.CANTER_CREEP_MIN = 0.03
EqTraining.CANTER_CREEP_UNFIT = 0.45

-- A gallop tires a fit horse more slowly: GALLOP_FIT_SHARE of the rate at stamina 100,
-- GALLOP_UNFIT_SHARE at 0.
EqTraining.GALLOP_UNFIT_SHARE = 1.25
EqTraining.GALLOP_FIT_SHARE = 0.75

-- A run is time spent at canter or gallop. Trotting holds it; walking, backing up or being
-- knocked to a halt wear it down slowly rather than ending it, since FS horses stop easily.
EqTraining.RUN_RATE = { halt = -3, walk = -3, reverse = -3, trot = 0, canter = 1, gallop = 1 }
EqTraining.RUN_START = 0
EqTraining.RUN_FULL = 15

-- Stamina effort per second in each gait at the best tiredness and a long run.
EqTraining.STAMINA_RATE = { trot = 0.0065, canter = 0.0165, gallop = 0.021 }
-- Stamina zone: no stamina work below ZONE_FROM, building to full at ZONE_LOW, full up to
-- ZONE_HIGH, then falling to ZONE_BLOWN_SHARE at 100.
EqTraining.ZONE_FROM = 55
EqTraining.ZONE_LOW = 68
EqTraining.ZONE_HIGH = 85
EqTraining.ZONE_BLOWN_SHARE = 0.2

-- Speed effort per second at a gallop while fresh: full up to FRESH_UNTIL, falling to
-- STALE_SHARE at STALE_FROM and above.
EqTraining.SPEED_RATE = 0.02
EqTraining.FRESH_UNTIL = 25
EqTraining.STALE_FROM = 55
EqTraining.STALE_SHARE = 0

-- Tempo: stamina rewards riding the beat. Only beats raise it: every TEMPO_HITS beat points
-- (a hit is 1, a perfect hit 2) raise the tempo by one, x1 to TEMPO_MAX, and stamina trains
-- 1 + TEMPO_BONUS x (tempo - 1) times as fast. A missed or wasted beat loses the points
-- towards the next step. Blowing hard (over ZONE_HIGH) for longer than TEMPO_BLOWN_MS breaks
-- the streak back to x1; so does more than TEMPO_SLOW_MS below a canter.
EqTraining.TEMPO_HITS = 3

-- Training modes keep stamina, agility and speed from talking over each other: one at a time
-- owns the beats and the popups (temperament's routine is separate and always runs).
--   stamina: canter STAMINA_ENTRY_MS without a jump or a gallop; ends when the tempo breaks.
--   agility: clear a jump outside stamina mode; ends when the combo is lost.
--   speed: count a warm-up gallop outside the other two; ends when the Sprint is over.
EqTraining.STAMINA_ENTRY_MS = 8000
-- Outside stamina mode a run only trickles stamina in, at this share: real stamina gains need
-- stamina mode and its tempo.
EqTraining.STAMINA_OUTSIDE_SHARE = 0.2
EqTraining.TEMPO_MAX = 5
EqTraining.TEMPO_BONUS = 0.375
EqTraining.TEMPO_BLOWN_MS = 5000
EqTraining.TEMPO_SLOW_MS = 3500

-- Beats: during a run a marker sweeps along the exertion meter, from 0 to 100 in BEAT_SWEEP_MS,
-- every BEAT_GAP_MS (a random time in the range). Pressing the key for the other fast gait
-- (forward for gallop, back for canter) while it is within BEAT_WINDOW of the horse's exertion
-- is a hit (within BEAT_PERFECT, a perfect one); pressing it up to BEAT_NEAR points early wastes
-- the beat, and any other key, or a press further off, is ignored. A hit:
-- the horse gets its breath back (exertion drops BEAT_RELIEF, BEAT_PERFECT_RELIEF for a
-- perfect hit) and the tempo climbs (see TEMPO_HITS). That is how a rider holds a high tempo
-- without blowing.
EqTraining.BEAT_SWEEP_MS = 2500
EqTraining.BEAT_GAP_MS = { 4000, 7000 }
EqTraining.BEAT_WINDOW = 7
EqTraining.BEAT_PERFECT = 2.5
EqTraining.BEAT_RELIEF = 6
EqTraining.BEAT_PERFECT_RELIEF = 10
EqTraining.BEAT_NEAR = 15
-- It gets harder as the tempo climbs, so no horse gallops for ever: for each tempo step above
-- x1 the window shrinks BEAT_WINDOW_PRESSURE, the breather BEAT_RELIEF_PRESSURE and the sweep
-- time BEAT_SWEEP_PRESSURE (at x5: window 52%, breather 40%, sweep 60%).
EqTraining.BEAT_WINDOW_PRESSURE = 0.12
EqTraining.BEAT_RELIEF_PRESSURE = 0.15
EqTraining.BEAT_SWEEP_PRESSURE = 0.1

-- SPEED: sprints. A gallop held SPRINT_COUNT_MS while speed is training at SPRINT_MIN_QUALITY
-- or better is a warm-up sprint; after SPRINTS_TO_WARM of them the horse is warmed up. Gallop
-- for SPRINT_READY_MS more and Sprint is ready: press forward (W) and for SPRINT_MS (more with taps, below) the horse
-- runs SPRINT_SPEED_SHARE faster (EqTrainingHooks), ignores being blown, tires
-- SPRINT_EXERTION_SHARE as fast and trains speed SPRINT_TRAIN_SHARE as fast as a fresh gallop.
-- Dropping below a gallop for SPRINT_DROP_MS ends it. Then it must rest below
-- SPRINT_REST_BELOW exertion before warm-up sprints count again.
EqTraining.SPRINT_COUNT_MS = 4000
EqTraining.SPRINT_MIN_QUALITY = 0.5
EqTraining.SPRINTS_TO_WARM = 2
EqTraining.SPRINT_READY_MS = 2000
EqTraining.SPRINT_MS = 6000
-- Tapping forward (W) during Sprint spurs the horse on: each tap at least SPRINT_TAP_GAP_MS
-- after the last adds SPRINT_TAP_MS, less the longer the Sprint has gone, up to SPRINT_MAX_MS
-- left. However well the rider taps, the horse conks out after SPRINT_LIMIT_MS.
EqTraining.SPRINT_TAP_MS = 300
EqTraining.SPRINT_TAP_GAP_MS = 120
-- The Sprint meter runs down SPRINT_DRAIN times as fast as the clock, so only quick tapping
-- keeps it up, and less so as the Sprint goes on.
EqTraining.SPRINT_DRAIN = 1.5
EqTraining.SPRINT_MAX_MS = 8000
EqTraining.SPRINT_LIMIT_MS = 14000
EqTraining.SPRINT_SPEED_SHARE = 1.25
EqTraining.SPRINT_EXERTION_SHARE = 1.5
EqTraining.SPRINT_TRAIN_SHARE = 3
-- Outside Sprint (warm-up gallops, any other gallop) speed only trickles in, at this share.
EqTraining.SPEED_OUTSIDE_SHARE = 0.2
EqTraining.SPRINT_DROP_MS = 1000
EqTraining.SPRINT_REST_BELOW = 10
-- Sprint holds the horse on the limit: exertion stops SPRINT_EXERTION_GAP short of blowing hard.
EqTraining.SPRINT_EXERTION_GAP = 1
-- A slower horse's Sprint runs out faster: at speed 0 the clock runs SPRINT_SLOW_DRAIN times
-- as fast, easing to normal at speed 100.
EqTraining.SPRINT_SLOW_DRAIN = 1.6

-- How fast each gait fills the riding bar. The base game's factors (Rideable:updateRiding),
-- except backing up: the base game counts it like a walk, and EqTrainingHooks tops it up to
-- this, because it is hard mental work: it tires a horse nearly as fast as a gallop.
EqTraining.GAIT_SPEED_FACTOR = { reverse = 2.5, walk = 1, trot = 1, canter = 2, gallop = 3 }

-- What the base game already credits for backing up; the rest of reverse's factor is ours.
EqTraining.BASE_REVERSE_FACTOR = 1

-- What staff work on, per focus. Set with the eqFocus console command for now.
EqTraining.FOCUS = {
    balanced = { stamina = 0.6, speed = 0.6, agility = 0.6, temperament = 0.6 },
    showJumping = { stamina = 0.3, speed = 0.4, agility = 1.0, temperament = 0.7 },
    dressage = { stamina = 0.2, speed = 0.2, agility = 0.7, temperament = 1.0 },
    crossCountry = { stamina = 1.0, speed = 0.6, agility = 0.6, temperament = 0.5 },
    racing = { stamina = 0.9, speed = 1.0, agility = 0.1, temperament = 0.1 },
}

-- Staff ride at this share of their focus profile, so a rider's own focused work (up to
-- EFFORT_CAP) is well ahead of what staff give: staff keep horses ticking over.
EqTraining.STAFF_EFFORT_SHARE = 0.5

EqTraining.FOCUS_ORDER = { "balanced", "showJumping", "dressage", "crossCountry", "racing" }


--- @return table sheet One horse's riding since its last daily tick
function EqTraining.newSheet()
    return { ms = { reverse = 0, walk = 0, trot = 0, canter = 0, gallop = 0 }, jumps = 0, inside = {},
        tiredness = 0, run = 0, tempo = EqTraining.newTempo(), beat = EqTraining.newBeat(), mode = nil, entryMs = 0,
        sprint = { count = 0, holdMs = 0, counted = false, warm = false, readyMs = 0, ready = false, activeMs = 0, dropMs = 0, rest = false },
        focused = { stamina = 0, speed = 0, agility = 0, temperament = 0 },
        quality = { stamina = 0, speed = 0, agility = 0, temperament = 0 },
        combo = { count = 0, timer = 0, best = 0 },
        routine = { active = false, mult = 0, clock = 0, walkMs = 0, current = nil, request = nil, deadline = 0, nextAt = 0 } }
end


--- @return table tempo a fresh tempo streak
function EqTraining.newTempo()
    return { ms = 0, mult = 1, hits = 0, slowMs = 0, blownMs = 0 }
end


--- One frame of the tempo streak.
--- @param tempo table
--- @param gait string the pace gait
--- @param tiredness number
--- @param dt number milliseconds
--- @return string|nil event "lost"
function EqTraining.tempoStep(tempo, gait, tiredness, dt)
    local had = tempo.ms > 0
    local function lose()
        local gained = tempo.mult > 1 or tempo.hits > 0
        tempo.ms, tempo.mult, tempo.hits, tempo.slowMs, tempo.blownMs = 0, 1, 0, 0, 0
        return had and gained and "lost" or nil
    end
    if gait ~= "canter" and gait ~= "gallop" then
        if not had then return nil end
        tempo.slowMs = tempo.slowMs + dt
        if tempo.slowMs > EqTraining.TEMPO_SLOW_MS then return lose() end
        return nil
    end
    tempo.slowMs = 0
    if tiredness > EqTraining.ZONE_HIGH then
        tempo.blownMs = tempo.blownMs + dt
        if tempo.blownMs > EqTraining.TEMPO_BLOWN_MS then return lose() end
        return nil
    end
    tempo.blownMs = 0
    -- The streak's running time: it shows the tempo row, but only beats raise the tempo.
    tempo.ms = tempo.ms + dt
    return nil
end


--- A beat hit (or miss) for the tempo.
--- @param tempo table
--- @param points number 1 for a hit, 2 for a perfect one, 0 for a miss or wasted beat
--- @return string|nil event "up" (a new tempo)
function EqTraining.tempoBeat(tempo, points)
    if points <= 0 then
        tempo.hits = 0
        return nil
    end
    if tempo.mult >= EqTraining.TEMPO_MAX then return nil end
    tempo.hits = tempo.hits + points
    if tempo.hits < EqTraining.TEMPO_HITS then return nil end
    tempo.mult, tempo.hits = tempo.mult + 1, 0
    return "up"
end


--- @return table beat a fresh beat state
function EqTraining.newBeat()
    return { clock = 0, nextAt = 0, pos = nil, target = nil }
end


--- @param range table { min, max } milliseconds
--- @param rng function (n) -> 1..n
local function beatGap(range, rng)
    return range[1] + (rng(range[2] - range[1] + 1) - 1)
end


--- The beat's window, breather and sweep time at the current tempo.
--- @param sheet table
--- @return number window exertion points, number relief share 0..1, number sweep milliseconds
function EqTraining.beatPressure(sheet)
    local steps = (sheet.tempo ~= nil and sheet.tempo.mult or 1) - 1
    return EqTraining.BEAT_WINDOW * (1 - EqTraining.BEAT_WINDOW_PRESSURE * steps),
        1 - EqTraining.BEAT_RELIEF_PRESSURE * steps,
        EqTraining.BEAT_SWEEP_MS * (1 - EqTraining.BEAT_SWEEP_PRESSURE * steps)
end


--- One frame of the beat. Beats only come during a run at a canter or gallop; the rider's key
--- presses are judged by EqTraining.beatPress.
--- @param sheet table
--- @param gait string
--- @param dt number milliseconds
--- @param rng function (n) -> 1..n
--- @return string|nil event "start" or "miss"
function EqTraining.beatStep(sheet, gait, dt, rng)
    local beat = sheet.beat
    beat.clock = beat.clock + dt
    local fast = gait == "canter" or gait == "gallop"
    -- Sprint owns W and a routine command owns the middle of the screen: no new beats meanwhile.
    local busy = sheet.mode ~= "stamina" or sheet.sprint.ready or EqTraining.isSprinting(sheet) or sheet.routine.request ~= nil
    local window, _, sweep = EqTraining.beatPressure(sheet)
    if beat.pos ~= nil then
        if busy then
            beat.pos = nil
            beat.nextAt = math.max(beat.nextAt, beat.clock + EqTraining.BEAT_GAP_MS[1])
            return nil
        end
        beat.pos = beat.pos + 100 * dt / sweep
        -- Until the cue is near, it follows the gait the horse is in.
        if fast and beat.pos - sheet.tiredness < -(window + EqTraining.BEAT_NEAR) then
            beat.target = gait == "gallop" and "canter" or "gallop"
        end
        if beat.pos - sheet.tiredness > window or not fast then
            beat.pos, beat.nextAt = nil, beat.clock + beatGap(EqTraining.BEAT_GAP_MS, rng)
            EqTraining.tempoBeat(sheet.tempo, 0)
            return "miss"
        end
        return nil
    end
    if busy or not fast or sheet.run <= 0 then
        beat.nextAt = math.max(beat.nextAt, beat.clock + EqTraining.BEAT_GAP_MS[1])
        return nil
    end
    if beat.clock >= beat.nextAt then
        beat.pos, beat.target = 0, gait == "gallop" and "canter" or "gallop"
        return "start"
    end
    return nil
end


--- The rider pressed forward or back during a beat.
--- @param sheet table
--- @param key string "forward" or "back"
--- @param rng function (n) -> 1..n
--- @return string|nil event "hit", "perfect", "off" (too early: the beat is wasted) or nil (ignored)
--- @return string|nil tempo "up" when the hit raised the tempo
function EqTraining.beatPress(sheet, key, rng)
    local beat = sheet.beat
    if beat.pos == nil or key ~= (beat.target == "gallop" and "forward" or "back") then return nil end
    local window, relief = EqTraining.beatPressure(sheet)
    local gap = beat.pos - sheet.tiredness
    if math.abs(gap) <= window then
        local perfect = math.abs(gap) <= EqTraining.BEAT_PERFECT
        sheet.tiredness = math.max(0, sheet.tiredness
            - (perfect and EqTraining.BEAT_PERFECT_RELIEF or EqTraining.BEAT_RELIEF) * relief)
        beat.pos, beat.nextAt = nil, beat.clock + beatGap(EqTraining.BEAT_GAP_MS, rng)
        return perfect and "perfect" or "hit", EqTraining.tempoBeat(sheet.tempo, perfect and 2 or 1)
    end
    if gap < -window and gap >= -(window + EqTraining.BEAT_NEAR) then
        beat.pos, beat.nextAt = nil, beat.clock + beatGap(EqTraining.BEAT_GAP_MS, rng)
        EqTraining.tempoBeat(sheet.tempo, 0)
        return "off"
    end
    return nil
end


--- @param tempo table|nil
--- @return number stamina gains multiplier
function EqTraining.tempoBonus(tempo)
    return 1 + EqTraining.TEMPO_BONUS * ((tempo ~= nil and tempo.mult or 1) - 1)
end


--- How well stamina is training at this tiredness and run length.
--- @param tiredness number 0-100
--- @param run number seconds
--- @return number share 0..1 of STAMINA_RATE, before the tempo bonus
function EqTraining.staminaQuality(tiredness, run)
    local zone
    if tiredness < EqTraining.ZONE_LOW then
        zone = EqStats.clamp((tiredness - EqTraining.ZONE_FROM) / (EqTraining.ZONE_LOW - EqTraining.ZONE_FROM), 0, 1)
    elseif tiredness <= EqTraining.ZONE_HIGH then
        zone = 1
    else
        local over = (tiredness - EqTraining.ZONE_HIGH) / (100 - EqTraining.ZONE_HIGH)
        zone = 1 - over * (1 - EqTraining.ZONE_BLOWN_SHARE)
    end
    local length = EqStats.clamp((run - EqTraining.RUN_START) / (EqTraining.RUN_FULL - EqTraining.RUN_START), 0, 1)
    return zone * length
end


--- How well a gallop trains speed at this tiredness.
--- @param tiredness number 0-100
--- @return number share 0..1 of SPEED_RATE
function EqTraining.speedQuality(tiredness)
    if tiredness <= EqTraining.FRESH_UNTIL then return 1 end
    local stale = EqStats.clamp((tiredness - EqTraining.FRESH_UNTIL) / (EqTraining.STALE_FROM - EqTraining.FRESH_UNTIL), 0, 1)
    return 1 - stale * (1 - EqTraining.STALE_SHARE)
end


--- How fast exertion changes in a gait.
--- @param gait string
--- @param tiredness number 0-100
--- @param stamina number|nil the horse's trained stamina (50 when nil)
--- @return number|nil per second; nil for an unknown gait
function EqTraining.exertionRate(gait, tiredness, stamina, settled)
    local rate = EqTraining.TIREDNESS_RATE[gait]
    if rate == nil then return nil end
    local fitness = EqStats.clamp((stamina or 50) / 100, 0, 1)
    if gait == "canter" then
        local level = EqTraining.CANTER_LEVEL_BASE + EqTraining.CANTER_LEVEL_PER_STAMINA * fitness * 100
        local creep = EqTraining.CANTER_CREEP_MIN + EqTraining.CANTER_CREEP_UNFIT * (1 - fitness) ^ 1.5
        return tiredness < level and EqTraining.CANTER_RISE or creep
    elseif (gait == "halt" or gait == "walk") and (tiredness < EqTraining.RECOVER_BELOW or settled) then
        local fast = rate * (EqTraining.RECOVER_UNFIT_SHARE + (EqTraining.RECOVER_FIT_SHARE - EqTraining.RECOVER_UNFIT_SHARE) * fitness)
        -- Settled at a walk (rather than a halt) above RECOVER_BELOW: a little slower.
        if tiredness >= EqTraining.RECOVER_BELOW and settled == "walk" then fast = fast * EqTraining.SETTLE_WALK_SHARE end
        return fast
    elseif gait == "gallop" then
        return rate * (EqTraining.GALLOP_UNFIT_SHARE + (EqTraining.GALLOP_FIT_SHARE - EqTraining.GALLOP_UNFIT_SHARE) * fitness)
    end
    return rate
end


--- One frame of riding for the meters and focused work.
--- @param sheet table
--- @param gait string halt, reverse, walk, trot, canter or gallop
--- @param dt number milliseconds
--- @param worn boolean true when the riding bar is full: the meters move, nothing trains
--- @param stamina number|nil the horse's trained stamina, which slows how fast it tires
function EqTraining.step(sheet, gait, dt, worn, stamina)
    -- How long the horse has stood still, and walked or stood, without a break.
    sheet.haltMs = gait == "halt" and (sheet.haltMs or 0) + dt or 0
    sheet.easyMs = (gait == "halt" or gait == "walk") and (sheet.easyMs or 0) + dt or 0
    local settled = (sheet.haltMs >= EqTraining.SETTLE_HALT_MS and "halt")
        or (sheet.easyMs >= EqTraining.SETTLE_WALK_MS and "walk") or nil
    local rate = EqTraining.exertionRate(gait, sheet.tiredness, stamina, settled)
    if rate == nil or dt <= 0 then return end
    local seconds = dt / 1000
    local sprinting = EqTraining.isSprinting(sheet) and gait == "gallop"
    if sprinting then rate = rate * EqTraining.SPRINT_EXERTION_SHARE end
    sheet.tiredness = EqStats.clamp(sheet.tiredness + rate * seconds, 0, 100)
    if sprinting then
        sheet.tiredness = math.min(sheet.tiredness, EqTraining.ZONE_HIGH - EqTraining.SPRINT_EXERTION_GAP)
    end
    sheet.run = math.max(0, sheet.run + EqTraining.RUN_RATE[gait] * seconds)

    sheet.tempoEvent = sheet.mode == "stamina" and EqTraining.tempoStep(sheet.tempo, gait, sheet.tiredness, dt) or nil

    local stamina = EqTraining.STAMINA_RATE[gait] ~= nil
        and EqTraining.staminaQuality(sheet.tiredness, sheet.run) * EqTraining.tempoBonus(sheet.tempo)
            * (sheet.mode == "stamina" and 1 or EqTraining.STAMINA_OUTSIDE_SHARE) or 0
    local speed = gait == "gallop" and EqTraining.speedQuality(sheet.tiredness) * EqTraining.SPEED_OUTSIDE_SHARE or 0
    if sprinting then speed = EqTraining.SPRINT_TRAIN_SHARE end
    sheet.quality.stamina, sheet.quality.speed = stamina, speed
    if worn then
        sheet.quality.stamina, sheet.quality.speed = 0, 0
        return
    end
    sheet.focused.stamina = sheet.focused.stamina + (EqTraining.STAMINA_RATE[gait] or 0) * stamina * seconds
    sheet.focused.speed = sheet.focused.speed + EqTraining.SPEED_RATE * speed * seconds
end


--- @param sheet table
--- @return boolean true while Sprint is on
function EqTraining.isSprinting(sheet)
    return sheet.sprint ~= nil and sheet.sprint.activeMs > 0
end


--- @param sheet table
--- @return boolean true while warm-up gallops or Sprint are under way
local function speedBusy(sheet)
    local sprint = sheet.sprint
    return sprint.warm or sprint.ready or sprint.activeMs > 0
end


--- One frame of the training mode, after step, sprintStep and comboTick.
--- @param sheet table
--- @param gait string the pace gait
--- @param dt number milliseconds
--- @return string|nil event "stamina" when stamina mode starts
function EqTraining.modeStep(sheet, gait, dt)
    local mode = sheet.mode
    if mode == "stamina" and sheet.tempo.ms <= 0 then mode = nil end
    if mode == "agility" and sheet.combo.count == 0 then mode = nil end
    if mode == "speed" and sheet.sprint.count == 0 and not speedBusy(sheet) then mode = nil end
    sheet.mode = mode
    -- A steady canter starts stamina mode, unless agility or a warmed-up horse has the floor.
    if mode == "stamina" or mode == "agility" or (mode == "speed" and speedBusy(sheet)) or gait ~= "canter" then
        sheet.entryMs = 0
        return nil
    end
    sheet.entryMs = sheet.entryMs + dt
    if sheet.entryMs < EqTraining.STAMINA_ENTRY_MS then return nil end
    sheet.mode, sheet.entryMs = "stamina", 0
    sheet.sprint.count, sheet.sprint.holdMs, sheet.sprint.counted = 0, 0, false
    sheet.tempo = EqTraining.newTempo()
    -- The streak starts now (tempo.ms > 0 is what keeps stamina mode on).
    sheet.tempo.ms = 1
    sheet.beat.nextAt = sheet.beat.clock + EqTraining.BEAT_GAP_MS[1]
    return "stamina"
end


--- A jump outside stamina mode: the canter towards stamina mode starts again.
--- @param sheet table
function EqTraining.modeJump(sheet)
    if sheet.mode ~= "stamina" then sheet.entryMs = 0 end
end


--- Start a Sprint, if one is ready.
--- @param sheet table
--- @return boolean true when it started
function EqTraining.startSprint(sheet)
    local sprint = sheet.sprint
    if not sprint.ready or sprint.activeMs > 0 then return false end
    sprint.activeMs, sprint.dropMs, sprint.ready, sprint.readyMs = EqTraining.SPRINT_MS, 0, false, 0
    -- The press that started it (seen by both the action and the key poll) is not a tap.
    sprint.elapsedMs, sprint.tapAt = 0, 0
    return true
end


--- A tap of the forward key during Sprint: more time, less as the Sprint goes on.
--- @param sheet table
--- @return boolean true when it added time
function EqTraining.spurSprint(sheet)
    local sprint = sheet.sprint
    if sprint.activeMs <= 0 or sprint.elapsedMs - (sprint.tapAt or 0) < EqTraining.SPRINT_TAP_GAP_MS then return false end
    sprint.tapAt = sprint.elapsedMs
    local left = 1 - EqStats.clamp(sprint.elapsedMs / EqTraining.SPRINT_LIMIT_MS, 0, 1)
    sprint.activeMs = math.min(EqTraining.SPRINT_MAX_MS, sprint.activeMs + EqTraining.SPRINT_TAP_MS * left)
    return left > 0
end


--- One frame of warm-up sprints and Sprint, after EqTraining.step.
--- @param sheet table
--- @param gait string the pace gait
--- @param dt number milliseconds
--- @param speed number|nil the horse's trained speed: a slower horse's Sprint runs out faster
--- @return string|nil event "counted" (a warm-up gallop), "warm", "ready", "over"
function EqTraining.sprintStep(sheet, gait, dt, speed)
    local sprint = sheet.sprint
    if sprint.activeMs > 0 then
        local drain = 1 + (EqTraining.SPRINT_SLOW_DRAIN - 1) * (1 - EqStats.clamp((speed or 100) / 100, 0, 1))
        sprint.activeMs = math.max(0, sprint.activeMs - dt * drain * EqTraining.SPRINT_DRAIN)
        sprint.elapsedMs = (sprint.elapsedMs or 0) + dt
        if sprint.elapsedMs >= EqTraining.SPRINT_LIMIT_MS then sprint.activeMs = 0 end
        sprint.dropMs = gait == "gallop" and 0 or sprint.dropMs + dt
        if sprint.activeMs > 0 and sprint.dropMs < EqTraining.SPRINT_DROP_MS then return nil end
        sprint.activeMs, sprint.count, sprint.warm, sprint.rest = 0, 0, false, true
        sprint.holdMs, sprint.counted, sprint.readyMs, sprint.ready = 0, false, 0, false
        return "over"
    end
    if sprint.rest and sheet.tiredness < EqTraining.SPRINT_REST_BELOW then sprint.rest = false end

    if gait ~= "gallop" then
        sprint.holdMs, sprint.counted, sprint.readyMs, sprint.ready = 0, false, 0, false
        return nil
    end
    if sprint.warm then
        sprint.readyMs = sprint.readyMs + dt
        if not sprint.ready and sprint.readyMs >= EqTraining.SPRINT_READY_MS then
            sprint.ready = true
            return "ready"
        end
        return nil
    end
    if sprint.rest or EqTraining.speedQuality(sheet.tiredness) < EqTraining.SPRINT_MIN_QUALITY
        or sheet.mode == "stamina" or sheet.mode == "agility" then
        sprint.holdMs = 0
        return nil
    end
    sprint.holdMs = sprint.holdMs + dt
    if sprint.counted or sprint.holdMs < EqTraining.SPRINT_COUNT_MS then return nil end
    sprint.counted = true
    sprint.count = sprint.count + 1
    sheet.mode = "speed"
    if sprint.count < EqTraining.SPRINTS_TO_WARM then return "counted" end
    sprint.warm = true
    -- Keep galloping from here: the time already held counts towards Sprint being ready.
    sprint.readyMs = 0
    return "warm"
end


--- Word for the tiredness meter, for the riding HUD.
--- @param tiredness number 0-100
--- @return string band fresh, warm, zone or blown
function EqTraining.tirednessBand(tiredness)
    if tiredness < EqTraining.ZONE_FROM then return "fresh" end
    if tiredness < EqTraining.ZONE_LOW then return "warm" end
    if tiredness <= EqTraining.ZONE_HIGH then return "zone" end
    return "blown"
end


--- Word for the tiredness meter in the Speed view.
--- @param tiredness number 0-100
--- @return string band fresh, tiring or stale
function EqTraining.sprintBand(tiredness)
    if tiredness <= EqTraining.FRESH_UNTIL then return "fresh" end
    if tiredness < EqTraining.STALE_FROM then return "tiring" end
    return "stale"
end


--- Word for how fast a stat is training this moment.
--- @param quality number 0..1
--- @return string|nil band fast, steady or slow; nil when it is not training
function EqTraining.qualityBand(quality)
    if quality >= 0.75 then return "fast" end
    if quality >= 0.35 then return "steady" end
    if quality > 0 then return "slow" end
    return nil
end


--- A jump that cleared something: raise the combo and train agility.
--- @param sheet table
--- @param worn boolean true when the riding bar is full: the combo counts, nothing trains
--- @return number|nil multiplier this jump was worth, nil just after a combo was lost
function EqTraining.clearJump(sheet, worn)
    local combo = sheet.combo
    if (combo.lock or 0) > 0 then
        EqTraining.emptyJump(sheet, worn)
        return nil
    end
    combo.count = combo.count + 1
    combo.timer = EqTraining.COMBO_SECONDS
    if sheet.mode == nil then sheet.mode = "agility" end
    combo.best = math.max(combo.best, combo.count)
    local mult = math.min(combo.count, EqTraining.COMBO_MAX)
    if not worn then sheet.focused.agility = sheet.focused.agility + EqTraining.AGILITY_PER_JUMP * mult end
    return mult
end


--- A jump that cleared nothing: a little agility, no combo.
--- @param sheet table
--- @param worn boolean
function EqTraining.emptyJump(sheet, worn)
    if not worn then sheet.focused.agility = sheet.focused.agility + EqTraining.AGILITY_PER_EMPTY_JUMP end
end


--- End the jump combo, and start no new one for COMBO_LOCK_MS.
--- @param sheet table
--- @return boolean true when there was a combo to lose
function EqTraining.loseCombo(sheet)
    local combo = sheet.combo
    local had = combo.count > 0
    combo.count, combo.timer = 0, 0
    if had then combo.lock = EqTraining.COMBO_LOCK_MS end
    return had
end


--- The horse hit something: take time off the combo clock.
--- @param sheet table
--- @return string|nil "knocked", "lost" when that ran the clock out, nil when there was no
--- combo or it was knocked moments ago
function EqTraining.knockCombo(sheet)
    local combo = sheet.combo
    if combo.count == 0 or (combo.knockLock or 0) > 0 then return nil end
    combo.knockLock = EqTraining.COMBO_KNOCK_GAP_MS
    combo.timer = combo.timer - EqTraining.COMBO_KNOCK_SECONDS
    if combo.timer > 0 then return "knocked" end
    EqTraining.loseCombo(sheet)
    return "lost"
end


--- Run the jump combo's clock.
--- @param sheet table
--- @param gait string
--- @param dt number milliseconds
--- @param jumping boolean|nil true while a jump is in the air or not yet judged: the combo
---     can't run out until it lands and is judged
--- @return boolean true when the combo was lost this frame
function EqTraining.comboTick(sheet, gait, dt, jumping)
    local combo = sheet.combo
    combo.lock = math.max(0, (combo.lock or 0) - dt)
    combo.knockLock = math.max(0, (combo.knockLock or 0) - dt)
    sheet.quality.agility = combo.count > 0 and math.min(combo.count, EqTraining.COMBO_MAX) / EqTraining.COMBO_MAX or 0
    if combo.count == 0 then return false end
    local slow = gait == "halt" or gait == "walk" or gait == "reverse"
    combo.timer = combo.timer - dt / 1000 * (slow and EqTraining.COMBO_SLOW_DRAIN or 1)
    if combo.timer > 0 then return false end
    if jumping then
        combo.timer = 0
        return false
    end
    return EqTraining.loseCombo(sheet)
end


--- @param range table { min, max } milliseconds
--- @param rng function (n) -> 1..n
local function randomGap(range, rng)
    local steps = math.floor((range[2] - range[1]) / 500)
    return range[1] + (rng(steps + 1) - 1) * 500
end


--- Movements the routine may ask for next: never the one being done, and never straight from
--- a trot to backing up or back (the horse has to stop or walk in between).
--- @param current string|nil
--- @return table moves
function EqTraining.routineChoices(current)
    local moves = {}
    for _, move in ipairs(EqTraining.ROUTINE_MOVES) do
        local blocked = move == current or (current == "trot" and move == "reverse") or (current == "reverse" and move == "trot")
        if not blocked then table.insert(moves, move) end
    end
    return moves
end


--- End the temperament routine.
--- @param sheet table
--- @return boolean true when one was running
function EqTraining.breakRoutine(sheet)
    local routine = sheet.routine
    local was = routine.active
    routine.active, routine.mult, routine.request, routine.walkMs, routine.current = false, 0, nil, 0, nil
    routine.steerMs = 0
    return was
end


--- One frame of the temperament routine.
--- @param sheet table
--- @param move string walk, trot, halt, reverse, or fast (canter or gallop)
--- @param steer string|nil left or right while the rider holds that steering key
--- @param dt number milliseconds
--- @param worn boolean true when the riding bar is full: the routine runs, nothing trains
--- @param rng function (n) -> 1..n
--- @return string|nil event "start", "request", "done", "lost", or nil
function EqTraining.routineStep(sheet, move, steer, dt, worn, rng)
    local routine = sheet.routine
    routine.clock = routine.clock + dt
    routine.steerMs = steer ~= nil and steer == routine.steerSide and (routine.steerMs or 0) + dt or 0
    routine.steerSide = steer
    sheet.quality.temperament = routine.active and (routine.mult - 1) / (EqTraining.COMBO_MAX - 1) or 0
    if move == "fast" then
        return EqTraining.breakRoutine(sheet) and "lost" or nil
    end

    if not routine.active then
        routine.walkMs = move == "walk" and routine.walkMs + dt or 0
        if routine.walkMs < EqTraining.ROUTINE_START_MS then return nil end
        routine.active, routine.mult, routine.current = true, 1, "walk"
        routine.nextAt = routine.clock + randomGap(EqTraining.ROUTINE_GAP_MS, rng)
        return "start"
    end

    local event = nil
    if routine.request ~= nil then
        local turned = routine.request == "left" or routine.request == "right"
        local done = move == routine.request
        if turned then done = steer == routine.request and routine.steerMs >= EqTraining.ROUTINE_STEER_MS end
        if done then
            routine.mult = math.min(routine.mult + 1, EqTraining.COMBO_MAX)
            if not turned then routine.current = move end
            routine.request = nil
            local range = turned and EqTraining.ROUTINE_TURN_GAP_MS or move == "halt" and EqTraining.ROUTINE_HALT_GAP_MS
                or EqTraining.ROUTINE_GAP_MS
            routine.nextAt = routine.clock + randomGap(range, rng) * (1 - EqTraining.ROUTINE_GAP_PRESSURE * (routine.mult - 1))
            event = "done"
        elseif routine.clock > routine.deadline then
            EqTraining.breakRoutine(sheet)
            return "lost"
        end
    -- A beat on its way waits for nothing: the next command comes after it.
    elseif routine.clock >= routine.nextAt and (sheet.beat == nil or sheet.beat.pos == nil) then
        local choices = EqTraining.routineChoices(routine.current)
        routine.request = choices[rng(#choices)]
        routine.reactMs = EqTraining.ROUTINE_REACT_MS * (1 - EqTraining.ROUTINE_REACT_PRESSURE * (routine.mult - 1))
        routine.deadline = routine.clock + routine.reactMs
        -- A turn counts once its key has been held this long after the request shows.
        routine.steerMs = 0
        event = "request"
    end

    if not worn and routine.mult > 1 then
        sheet.focused.temperament = sheet.focused.temperament + EqTraining.TEMPERAMENT_RATE * (routine.mult - 1) * dt / 1000
    end
    return event
end


--- Time out of the saddle rests the horse like standing still.
--- @param sheet table
--- @param ms number milliseconds since the sheet was last ridden
function EqTraining.rest(sheet, ms)
    if ms <= 0 then return end
    local seconds = ms / 1000
    sheet.tiredness = EqStats.clamp(sheet.tiredness + EqTraining.TIREDNESS_RATE.halt * seconds, 0, 100)
    sheet.run = math.max(0, sheet.run + EqTraining.RUN_RATE.halt * seconds)
    sheet.quality.stamina, sheet.quality.speed, sheet.quality.agility, sheet.quality.temperament = 0, 0, 0, 0
    sheet.combo.count, sheet.combo.timer = 0, 0
    sheet.tempo = EqTraining.newTempo()
    sheet.beat = EqTraining.newBeat()
    sheet.mode, sheet.entryMs = nil, 0
    local sprint = sheet.sprint
    sprint.activeMs, sprint.ready, sprint.readyMs, sprint.holdMs, sprint.counted = 0, false, 0, 0, false
    if sheet.tiredness < EqTraining.SPRINT_REST_BELOW then sprint.rest = false end
    EqTraining.breakRoutine(sheet)
end


--- @param sheet table
--- @param kind string an EqFacility kind name the horse is being ridden inside
--- @param dt number milliseconds
function EqTraining.addInside(sheet, kind, dt)
    if dt <= 0 then return end
    sheet.inside[kind] = (sheet.inside[kind] or 0) + dt
end


--- @param sheet table
--- @param gait string reverse, walk, trot, canter or gallop; anything else is ignored
--- @param dt number milliseconds
function EqTraining.addRiding(sheet, gait, dt)
    if sheet.ms[gait] == nil or dt <= 0 then return end
    sheet.ms[gait] = sheet.ms[gait] + dt
end


--- How many times longer than the base game a horse's riding bar takes to fill.
--- @param stamina number|nil trained stamina
--- @return number factor 1 or more
function EqTraining.ridingBarFactor(stamina)
    local above = EqStats.clamp(((stamina or 0) - EqTraining.BAR_FROM_STAMINA) / (100 - EqTraining.BAR_FROM_STAMINA), 0, 1)
    return 1 + (EqTraining.BAR_FIT_SHARE - 1) * above
end


-- Handling: a horse's trained stats change how it rides. Each is a multiplier on the base
-- game's value, linear in the stat between the two limits (stat 0 to stat 100), so a horse
-- never gets too slow or too wild to steer.
EqTraining.HANDLING = {
    -- Top speed of every forward gait. James, after riding: speed 10 about 10% slower, 100 about 20% faster.
    speed = { 0.87, 1.2 },
    -- Jump height (and so time in the air and length), by agility. Lowered after James found
    -- jumps too high and too long at agility 10 and 100.
    jump = { 0.8, 1.05 },
    turn = { 1, 1.65 },      -- turn rate, by agility
    -- By temperament, kept subtle: how quickly the horse picks up speed between gaits, and how
    -- long it stands after running into something (a share of EqTrainingHooks.CRASH_HALT_MS).
    acceleration = { 0.85, 1.15 },
    crashHalt = { 1.3, 0.7 },
}

--- @param limits table { at 0, at 100 }
--- @param stat number|nil trained stat; nil reads as 50
--- @return number
local function handlingShare(limits, stat)
    local t = EqStats.clamp((stat or 50) / 100, 0, 1)
    return limits[1] + (limits[2] - limits[1]) * t
end


--- How a horse's stats change its riding.
--- @param speed number|nil trained speed
--- @param agility number|nil trained agility
--- @param temperament number|nil trained temperament
--- @return table { speed, jump, turn, acceleration, crashHalt } multipliers on the base game's top
---   speeds, jump height, turn rate and acceleration, and on our crash halt
function EqTraining.handling(speed, agility, temperament)
    local limits = EqTraining.HANDLING
    return {
        speed = handlingShare(limits.speed, speed),
        jump = handlingShare(limits.jump, agility),
        turn = handlingShare(limits.turn, agility),
        acceleration = handlingShare(limits.acceleration, temperament),
        crashHalt = handlingShare(limits.crashHalt, temperament),
    }
end


--- Riding points to add to (or, when negative, take off) what the base game credits this frame:
--- backing up counts extra, and a fit horse's bar fills more slowly.
--- @param timer number weighted milliseconds carried over from earlier frames
--- @param dt number milliseconds ridden this frame
--- @param gait string
--- @param factor number from ridingBarFactor
--- @param fullMs number weighted milliseconds that fill riding from 0 to 100
--- @return number points whole points, number timer what is carried to the next frame
function EqTraining.ridingAdjust(timer, dt, gait, factor, fullMs)
    local base = gait == "reverse" and EqTraining.BASE_REVERSE_FACTOR or (EqTraining.GAIT_SPEED_FACTOR[gait] or 0)
    local wanted = (EqTraining.GAIT_SPEED_FACTOR[gait] or 0) / (factor or 1)
    timer = (timer or 0) + math.max(dt, 0) * (wanted - base)
    local perPoint = fullMs / 100
    local points = timer >= 0 and math.floor(timer / perPoint) or -math.floor(-timer / perPoint)
    return points, timer - points * perPoint
end


--- Extra riding points for backing up, on top of what the base game credits.
--- @param timer number weighted milliseconds carried over from earlier frames
--- @param dt number milliseconds spent backing up this frame
--- @param fullMs number weighted milliseconds that fill riding from 0 to 100
--- @return number points whole points to add, number timer what is carried to the next frame
function EqTraining.reverseExtraRiding(timer, dt, fullMs)
    return EqTraining.ridingAdjust(timer, dt, "reverse", 1, fullMs)
end


--- @param sheet table
function EqTraining.addJump(sheet)
    sheet.jumps = sheet.jumps + 1
end


--- Riding points (0-100) the base game credited for this sheet, so the rest of RLRM's riding
--- value can be put down to staff.
--- @param sheet table|nil
--- @return number points
function EqTraining.playerRidingPoints(sheet)
    if sheet == nil then return 0 end
    local weighted = 0
    for gait, ms in pairs(sheet.ms) do
        weighted = weighted + ms * EqTraining.GAIT_SPEED_FACTOR[gait]
    end
    return math.min(100, weighted / (sheet.barFactor or 1) / EqConstants.RIDING_FULL_MS * 100)
end


--- @param sheet table|nil
--- @return table effort stat -> 0..EFFORT_CAP
function EqTraining.playerEffort(sheet)
    local effort = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do effort[stat] = 0 end
    if sheet == nil then return effort end

    for gait, ms in pairs(sheet.ms) do
        local share = ms / EqConstants.TRAINING_FULL_MS
        for stat, weight in pairs(EqTraining.GAIT_WEIGHTS[gait]) do
            effort[stat] = effort[stat] + share * weight * (EqTraining.UNFOCUSED_SHARE[stat] or 1)
        end
    end
    for stat, value in pairs(sheet.focused or {}) do effort[stat] = effort[stat] + value end

    for _, stat in ipairs(EqConstants.STAT_KEYS) do effort[stat] = EqStats.clamp(effort[stat], 0, EqTraining.EFFORT_CAP[stat]) end
    return effort
end


--- @param riding number RLRM's riding value (0-100) at the day's end
--- @param playerPoints number from playerRidingPoints
--- @param focus string a key of EqTraining.FOCUS
--- @param groomed boolean
--- @return table effort stat -> 0..1
function EqTraining.staffEffort(riding, playerPoints, focus, groomed)
    local share = EqStats.clamp(((riding or 0) - playerPoints) / 100, 0, 1)
    local profile = EqTraining.FOCUS[focus] or EqTraining.FOCUS.balanced

    local effort = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do effort[stat] = share * profile[stat] * EqTraining.STAFF_EFFORT_SHARE end
    if groomed then
        effort.temperament = math.min(1, effort.temperament + EqConstants.GROOMED_TEMPERAMENT)
    end
    return effort
end


--- Points gained toward a cap in one day.
--- @param level number
--- @param cap number
--- @param monthly number percent of the gap closed per month at full effort
--- @param effort number 0..1
--- @param ageFactor number
--- @param timeAdjustment number share of a month this day is
--- @return number gain
function EqTraining.gain(level, cap, monthly, effort, ageFactor, timeAdjustment)
    if effort <= 0 or level >= cap then return 0 end
    local share = math.min(1, monthly / 100 * effort * ageFactor * timeAdjustment)
    return (cap - level) * share
end


--- Lower a level by loss, but never below floor, and never raise it to meet the floor.
local function fadeToward(level, loss, floor)
    if level <= floor then return level end
    return math.max(floor, level - loss)
end


--- Apply one day of training to a record.
--- @param record table EqHorseRecord (uses trained, focus, idleDays)
--- @param ceilings table stat -> ceiling
--- @param day table { sheet, riding, dirt, ageMonths, timeAdjustment, facilityOwned, facilityRidden,
---     feedBoost, rate }; each boost table is stat -> share (EqFacility.boosts, EqFeed.dietBoost), or nil;
---     rate is the Training rate setting (1 when nil)
--- @return table deltas stat -> change, for logging
--- @return table detail why: { player, staff (effort stat -> 0..1), groomed, ageFactor, idleDays,
---     fading, old, stats = stat -> { fromPlayer, fromStaff, faded, aged } } for EqStatLog
function EqTraining.applyDay(record, ceilings, day)
    local timeAdjustment = day.timeAdjustment or 1
    local rate = day.rate or 1
    local ageFactor = EqStats.ageTrainingFactor(day.ageMonths or 0)
    local groomed = day.dirt ~= nil and day.dirt <= EqConstants.GROOMED_DIRT

    local player = EqTraining.playerEffort(day.sheet)
    local staff = EqTraining.staffEffort(day.riding, EqTraining.playerRidingPoints(day.sheet), record.focus, groomed)

    local worked = false
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if player[stat] > 0 or staff[stat] > 0 then worked = true end
    end
    record.idleDays = worked and 0 or (record.idleDays or 0) + 1
    local fading = record.idleDays >= EqConstants.FADE_GRACE_DAYS
        and record.idleDays * timeAdjustment >= EqConstants.FADE_GRACE_MONTHS
    local old = (day.ageMonths or 0) > EqConstants.AGE_DECLINE

    local deltas = {}
    local detail = { player = player, staff = staff, groomed = groomed, ageFactor = ageFactor,
        idleDays = record.idleDays, fading = fading, old = old, stats = {} }
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local ceiling = ceilings[stat]
        local before = record.trained[stat] or 0
        local level = before
        local owned = day.facilityOwned ~= nil and day.facilityOwned[stat] or 0
        local ridden = day.facilityRidden ~= nil and day.facilityRidden[stat] or 0
        local fed = day.feedBoost ~= nil and day.feedBoost[stat] or 0
        local monthly = EqConstants.TRAIN_MONTHLY[stat] * (1 + owned + fed) * rate
        local monthlyRidden = EqConstants.TRAIN_MONTHLY[stat] * (1 + owned + fed + ridden) * rate

        local fromPlayer = EqTraining.gain(level, ceiling, monthlyRidden, player[stat], ageFactor, timeAdjustment)
        local fromStaff = EqTraining.gain(level, ceiling * EqConstants.STAFF_CAP, monthly, staff[stat], ageFactor, timeAdjustment)
        level = level + math.max(fromPlayer, fromStaff)

        local trainedTo = level
        if fading then
            level = fadeToward(level, EqConstants.FADE_MONTHLY[stat] * timeAdjustment, ceiling * EqConstants.FADE_FLOOR)
        end
        local fadedTo = level
        if old then
            level = fadeToward(level, EqConstants.OLD_DECLINE_MONTHLY * timeAdjustment, ceiling * EqConstants.OLD_FLOOR)
        end

        record.trained[stat] = EqStats.clamp(level, 0, ceiling)
        deltas[stat] = record.trained[stat] - before
        detail.stats[stat] = { fromPlayer = fromPlayer, fromStaff = fromStaff, faded = fadedTo - trainedTo,
            aged = level - fadedTo }
    end

    return deltas, detail
end


-- Words for how much an event would teach a horse, best first.
EqTraining.BENEFIT_BANDS = {
    { from = 0.5, name = "high" },
    { from = 0.25, name = "medium" },
    { from = 0.08, name = "low" },
    { from = -math.huge, name = "none" },
}


--- How much an event would teach a horse, for the Events tab: the room left below staff level in
--- the discipline's stats, weighted like the boost, times the age factor and the tier's boost.
--- @param trained table
--- @param ceilings table stat -> ceiling (the shown ones, so this tells nothing the words don't)
--- @param weights table stat -> discipline weight
--- @param ageMonths number
--- @param boost number|nil the tier's share of a full day (1 for a young horse class)
--- @return number benefit 0..1
--- @return string band a BENEFIT_BANDS name
function EqTraining.boostBenefit(trained, ceilings, weights, ageMonths, boost)
    local room, total = 0, 0
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local weight = weights[stat] or 0
        local cap = ceilings[stat] * EqConstants.STAFF_CAP
        if weight > 0 and cap > 0 then
            room = room + weight * EqStats.clamp((cap - (trained[stat] or 0)) / cap, 0, 1)
            total = total + weight
        end
    end
    local benefit = total > 0 and room / total * EqStats.ageTrainingFactor(ageMonths) * (boost or 1) or 0
    for _, band in ipairs(EqTraining.BENEFIT_BANDS) do
        if benefit >= band.from then return benefit, band.name end
    end
end


--- An event's training boost: a share of a full day's work spread over the discipline's stats,
--- counted at staff level (it is not the player's own riding).
--- @param record table EqHorseRecord
--- @param ceilings table stat -> ceiling
--- @param weights table stat -> discipline weight
--- @param boost number share of a full day
--- @param ageMonths number
--- @param timeAdjustment number
--- @param rate number|nil the Training rate setting (1 when nil)
--- @return table deltas stat -> change
function EqTraining.applyBoost(record, ceilings, weights, boost, ageMonths, timeAdjustment, rate)
    local maxWeight = 0
    for _, stat in ipairs(EqConstants.STAT_KEYS) do maxWeight = math.max(maxWeight, weights[stat] or 0) end

    local ageFactor = EqStats.ageTrainingFactor(ageMonths)
    local deltas = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local effort = maxWeight > 0 and boost * (weights[stat] or 0) / maxWeight or 0
        local before = record.trained[stat] or 0
        local gained = EqTraining.gain(before, ceilings[stat] * EqConstants.STAFF_CAP, EqConstants.TRAIN_MONTHLY[stat] * (rate or 1),
            effort, ageFactor, timeAdjustment)
        record.trained[stat] = EqStats.clamp(before + gained, 0, ceilings[stat])
        deltas[stat] = record.trained[stat] - before
    end
    return deltas
end

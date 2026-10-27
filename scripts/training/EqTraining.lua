--[[
    EqTraining.lua
    The training maths: pure functions with no game or RLRM calls, so they run headless.

    A day's work comes from two places:
    - The player's own riding. EqTrainingHooks records milliseconds spent in each gait and
      jumps taken into a "sheet" per horse. Each gait trains a different mix of stats.
    - Staff. Whatever share of RLRM's riding value the player's sheet does not explain was put
      there by someone else: the base game's animal worker, or RLRM's herdsman horse-care rule.
      Staff train to the horse's focus profile and stop at STAFF_CAP of each ceiling.

    Agility and temperament are focused work (jump combos and routines); just riding the gaits
    trains them at UNFOCUSED_SHARE of the gait weights below. Stamina and speed come only from
    riding the gallop well (EqExertion's Pushing, Recovering and Sprinting): a live stamina
    multiplier and a speed multiplier banked when a Sprint ends (James, 2026-10-27).

    Each stat closes a share of the gap to its cap every month (scaled to the day with the
    game's timeAdjustment), so gains slow as a horse nears its ceiling. Idle horses fade.
    The farm's horse facilities (EqFacility.boosts) and what the horse is fed (EqFeed.dietBoost)
    speed that up per stat, adding together; riding inside a facility speeds the player's own work
    up more. They never add work.
]]

EqTraining = {}

-- SPEED: every second of a Sprint banks SPEED_RATE, times a multiplier from how high the Sprint
-- took exertion when it ended: 1 + (SPRINT_MULT_MAX - 1) * share ^ SPRINT_MULT_POWER, so 2x
-- half way to the Blowing Hard line and 10x just short of it. A Sprint that ends at or past the
-- line banks only 1x. (James, 2026-10-27: get the Sprint as high as you dare.)
EqTraining.SPEED_RATE = 0.0065
EqTraining.SPRINT_MULT_MAX = 10
EqTraining.SPRINT_MULT_POWER = math.log(9) / math.log(2)

-- STAMINA: Pushing and Recovering earn STAMINA_RATE per second times a live multiplier, x1 to
-- STAMINA_MULT_MAX (James, 2026-10-27). The multiplier isn't tied to the bar:
-- - Pushing raises it, faster the higher exertion is (STAMINA_PUSH_GAIN per second, empty to the
--   line, with the square of exertion). Every point of exertion Pushing adds uses STAMINA_BREATH_USE of the horse's breath,
--   hidden from the rider: with less breath the multiplier rises more slowly (down to STAMINA_LOW_BREATH_GAIN of
--   the rate) and falls faster (up to STAMINA_LOW_BREATH_LOSS times), but never stops either way
--   (James). So bouncing between Push and Recover near the top earns little.
-- - Recovering gets breath back and loses multiplier, by the bar's third (EqExertion.band): fast
--   from the top third, slowly in the middle "zone" (where breath comes back best), fast again in
--   the bottom third. A canter or slower loses it fast.
-- - A Sprint holds both. Blowing Hard (or a Sprint that ends past the line) drops it to x1 and
--   stops stamina training until exertion is empty again, with no breath left to start on.
EqTraining.STAMINA_RATE = 0.0045
EqTraining.STAMINA_MULT_MAX = 5
EqTraining.STAMINA_PUSH_GAIN = { 0.15, 2.0 }
EqTraining.STAMINA_BREATH_USE = 0.01
EqTraining.STAMINA_LOW_BREATH_GAIN = 0.1
EqTraining.STAMINA_LOW_BREATH_LOSS = 2
EqTraining.STAMINA_LOSS = { high = 0.25, zone = 0.03, low = 0.8, slow = 0.6 }
EqTraining.STAMINA_BREATH_GAIN = { high = 0, zone = 0.07, low = 0.07, slow = 0.05 }

-- Effort each gait gives per full day of training (TRAINING_FULL_MS in that gait), by stat.
EqTraining.GAIT_WEIGHTS = {
    walk = { temperament = 1.0 },
    trot = { temperament = 0.6, agility = 0.3 },
    canter = { agility = 0.8, temperament = 0.3 },
    gallop = {},
    -- Backing up is slow, fiddly schooling: a little of it does a lot for balance and manners.
    reverse = { agility = 2.0, temperament = 2.0 },
}

-- Stats trained by focused work; their gait weights count at UNFOCUSED_SHARE.
EqTraining.UNFOCUSED_SHARE = { agility = 0.15, temperament = 0.08 }

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
-- to start it. Each one done raises the multiplier, up to ROUTINE_MAX; a miss, a canter, a gallop
-- or a jump ends the routine. Temperament builds at TEMPERAMENT_RATE per second for each step
-- of multiplier above x1. Gaits and turns are judged apart: a rider must steer round things
-- whatever the routine asks, so a gait request ignores steering and a turn request (holding
-- the left or right key for ROUTINE_STEER_MS) takes any gait short of a canter.
EqTraining.ROUTINE_START_MS = 2000
EqTraining.ROUTINE_STEER_MS = 300
EqTraining.ROUTINE_GAP_MS = { 5000, 8000 }
EqTraining.ROUTINE_TURN_GAP_MS = { 3000, 4000 }
EqTraining.ROUTINE_REACT_MS = 3000
EqTraining.ROUTINE_SHOW_MS = 1500
-- After a full stop the next request comes sooner (James: waiting at a halt was boring).
EqTraining.ROUTINE_HALT_GAP_MS = { 2500, 4000 }
-- The routine gets more stressful as its multiplier climbs: for each step above x1, gaps
-- between requests shrink by ROUTINE_GAP_PRESSURE and the time to react by ROUTINE_REACT_PRESSURE
-- (at x5: gaps 72%, 2.2 s to react; at x8: gaps 51%, 1.5 s).
-- James (2026-10-26): it felt too easy and a chore, so it goes to x8, not the jump combo's x5.
EqTraining.ROUTINE_MAX = 8
EqTraining.ROUTINE_GAP_PRESSURE = 0.07
EqTraining.ROUTINE_REACT_PRESSURE = 0.07
-- From ROUTINE_STEADY_FROM the horse must also hold its pace between requests: changing gait
-- unasked for ROUTINE_DRIFT_MS breaks the routine. On the way to a requested gait the ones in
-- between (a trot passes through a walk to stop) are fine, and so is any gait during a turn.
EqTraining.ROUTINE_STEADY_FROM = 4
EqTraining.ROUTINE_DRIFT_MS = 600
-- The routine's gaits, slowest first: a change between two passes through those in between.
EqTraining.ROUTINE_PACE = { reverse = 1, halt = 2, walk = 3, trot = 4 }
EqTraining.ROUTINE_MOVES = { "walk", "trot", "halt", "reverse", "left", "right" }
EqTraining.TEMPERAMENT_RATE = 0.0022

-- A fit horse's riding bar fills more slowly: up to BAR_FIT_SHARE times longer at stamina 100,
-- from no change at BAR_FROM_STAMINA and below.
EqTraining.BAR_FROM_STAMINA = 50
EqTraining.BAR_FIT_SHARE = 1.4

-- How fast each gait fills the riding bar. The base game's factors (Rideable:updateRiding),
-- except backing up: the base game counts it like a walk, and EqTrainingHooks tops it up to
-- this, because it is hard mental work: it tires a horse nearly as fast as a gallop.
EqTraining.GAIT_SPEED_FACTOR = { reverse = 2.5, walk = 1, trot = 1, canter = 2, gallop = 3 }

-- What the base game already credits for backing up; the rest of reverse's factor is ours.
EqTraining.BASE_REVERSE_FACTOR = 1

-- What staff work on, per focus: the horse's role (EqRole), set with the Set role button in
-- RLRM's Info tab or the eqFocus console command. Breeding and sale horses are kept ticking over.
EqTraining.FOCUS = {
    balanced = { stamina = 0.6, speed = 0.6, agility = 0.6, temperament = 0.6 },
    showJumping = { stamina = 0.3, speed = 0.4, agility = 1.0, temperament = 0.7 },
    dressage = { stamina = 0.2, speed = 0.2, agility = 0.7, temperament = 1.0 },
    crossCountry = { stamina = 1.0, speed = 0.6, agility = 0.6, temperament = 0.5 },
    racing = { stamina = 0.9, speed = 1.0, agility = 0.1, temperament = 0.1 },
    eventing = { stamina = 0.8, speed = 0.6, agility = 0.8, temperament = 0.8 },
    breeding = { stamina = 0.6, speed = 0.6, agility = 0.6, temperament = 0.6 },
    sale = { stamina = 0.6, speed = 0.6, agility = 0.6, temperament = 0.6 },
}

-- Staff ride at this share of their focus profile, so a rider's own focused work (up to
-- EFFORT_CAP) is well ahead of what staff give: staff keep horses ticking over.
EqTraining.STAFF_EFFORT_SHARE = 0.5

-- Staff don't manage a role's work equally well every day: each day the stats a role is about
-- (FOCUS_STAT_MIN or more in its profile) get a share between these of their effort, 1 on
-- average. A horse without a role (balanced) gets the same steady work every day.
EqTraining.STAFF_LUCK = { low = 0.5, high = 1.5 }
EqTraining.FOCUS_STAT_MIN = 0.7

EqTraining.FOCUS_ORDER = { "balanced", "showJumping", "dressage", "crossCountry", "eventing", "racing", "breeding", "sale" }


--- @return table sheet One horse's riding since its last daily tick
function EqTraining.newSheet()
    return { ms = { reverse = 0, walk = 0, trot = 0, canter = 0, gallop = 0 }, jumps = 0, inside = {},
        exertion = EqExertion.new(),
        focused = { stamina = 0, speed = 0, agility = 0, temperament = 0 },
        quality = { stamina = 0, speed = 0, agility = 0, temperament = 0 },
        stamina = { mult = 1, breath = 1 }, sprint = { ms = 0 },
        combo = { count = 0, timer = 0, best = 0 },
        routine = { active = false, mult = 0, clock = 0, walkMs = 0, current = nil, request = nil, deadline = 0, nextAt = 0 } }
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
    routine.shown = nil
    routine.steerMs, routine.driftMs = 0, 0
    return was
end


--- Whether a gait is one the routine allows right now, at a multiplier that asks for a steady pace.
--- @param routine table
--- @param move string
--- @return boolean
local function steadyPace(routine, move)
    local request = routine.request
    if request == "left" or request == "right" then return true end
    local pace, from = EqTraining.ROUTINE_PACE[move], EqTraining.ROUTINE_PACE[routine.current]
    if pace == nil or from == nil then return true end
    local to = from
    if request ~= nil and EqTraining.ROUTINE_PACE[request] ~= nil then to = EqTraining.ROUTINE_PACE[request] end
    return pace >= math.min(from, to) and pace <= math.max(from, to)
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
    sheet.quality.temperament = routine.active and (routine.mult - 1) / (EqTraining.ROUTINE_MAX - 1) or 0
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
            routine.mult = math.min(routine.mult + 1, EqTraining.ROUTINE_MAX)
            if not turned then routine.current = move end
            routine.driftMs = 0
            routine.request = nil
            local range = turned and EqTraining.ROUTINE_TURN_GAP_MS or move == "halt" and EqTraining.ROUTINE_HALT_GAP_MS
                or EqTraining.ROUTINE_GAP_MS
            routine.nextAt = routine.clock + randomGap(range, rng) * (1 - EqTraining.ROUTINE_GAP_PRESSURE * (routine.mult - 1))
            event = "done"
        elseif routine.clock > routine.deadline then
            EqTraining.breakRoutine(sheet)
            return "lost"
        end
    elseif routine.clock >= routine.nextAt then
        local choices = EqTraining.routineChoices(routine.current)
        routine.request = choices[rng(#choices)]
        routine.reactMs = EqTraining.ROUTINE_REACT_MS * (1 - EqTraining.ROUTINE_REACT_PRESSURE * (routine.mult - 1))
        routine.deadline = routine.clock + routine.reactMs
        -- The command stays on screen a moment even if the horse is already doing it.
        routine.shown, routine.shownUntil = routine.request, routine.clock + EqTraining.ROUTINE_SHOW_MS
        -- A turn counts once its key has been held this long after the request shows.
        routine.steerMs = 0
        event = "request"
    end

    if routine.active and (routine.request == "left" or routine.request == "right") and EqTraining.ROUTINE_PACE[move] ~= nil then
        -- Any pace will do for a turn, and the one it ends at is the pace to hold.
        routine.current = move
    end
    if routine.active and routine.mult >= EqTraining.ROUTINE_STEADY_FROM and not steadyPace(routine, move) then
        routine.driftMs = (routine.driftMs or 0) + dt
        if routine.driftMs >= EqTraining.ROUTINE_DRIFT_MS then
            EqTraining.breakRoutine(sheet)
            return "lost"
        end
    else
        routine.driftMs = 0
    end

    if not worn and routine.mult > 1 then
        sheet.focused.temperament = sheet.focused.temperament + EqTraining.TEMPERAMENT_RATE * (routine.mult - 1) * dt / 1000
    end
    return event
end


--- @param value number exertion when the Sprint ended
--- @param over boolean|nil true when it ended at or past the Blowing Hard line
--- @return number speed multiplier, 1..SPRINT_MULT_MAX
function EqTraining.sprintMultiplier(value, over)
    if over or value >= EqExertion.LINE then return 1 end
    local share = math.min(math.max(value / EqExertion.LINE, 0), 1)
    return 1 + (EqTraining.SPRINT_MULT_MAX - 1) * share ^ EqTraining.SPRINT_MULT_POWER
end


--- One frame of speed training, after EqExertion.step: Sprint time earns 1x as it goes, and the
--- rest of the multiplier is banked once the Sprint is over.
--- @param sheet table
--- @param dt number milliseconds
--- @param worn boolean true when the riding bar is full: nothing trains
--- @return number|nil mult, number gain when a Sprint was banked this frame
function EqTraining.speedStep(sheet, dt, worn)
    local ex, sprint = sheet.exertion, sheet.sprint
    if ex.mode == "sprint" then
        -- The 1x part counts as it is earned (so the riding bar sees steady work), the rest of
        -- the multiplier when the Sprint ends.
        if not worn then
            sprint.ms = sprint.ms + dt
            sheet.focused.speed = sheet.focused.speed + EqTraining.SPEED_RATE * dt / 1000
        end
        sheet.quality.speed = (EqTraining.sprintMultiplier(ex.value) - 1) / (EqTraining.SPRINT_MULT_MAX - 1)
        return nil
    end
    sheet.quality.speed = 0
    if sprint.ms <= 0 then return nil end
    local last = ex.lastSprint or { value = ex.value }
    local mult = EqTraining.sprintMultiplier(last.value, last.over)
    local gain = EqTraining.SPEED_RATE * sprint.ms / 1000 * mult
    sheet.focused.speed = sheet.focused.speed + gain - EqTraining.SPEED_RATE * sprint.ms / 1000
    sprint.ms, sprint.last = 0, mult
    return mult, gain
end


--- One frame of the stamina multiplier and stamina training, after EqExertion.step.
--- @param sheet table
--- @param dt number milliseconds
--- @param worn boolean true when the riding bar is full: the multiplier runs, nothing trains
function EqTraining.staminaStep(sheet, dt, worn)
    local ex, st = sheet.exertion, sheet.stamina
    local climbed = math.max(0, ex.value - (st.lastValue or ex.value))
    st.lastValue = ex.value
    local seconds = dt / 1000
    if ex.lock ~= nil then
        st.mult, st.breath = 1, 0
    elseif ex.mode == "sprint" then
        -- A Sprint holds the multiplier and the breath.
    elseif ex.mode == "push" then
        local share = math.min(ex.value / EqExertion.LINE, 1)
        local gain = EqTraining.STAMINA_PUSH_GAIN[1] + (EqTraining.STAMINA_PUSH_GAIN[2] - EqTraining.STAMINA_PUSH_GAIN[1]) * share * share
        local low = EqTraining.STAMINA_LOW_BREATH_GAIN
        st.mult = st.mult + gain * (low + (1 - low) * st.breath) * seconds
        st.breath = st.breath - EqTraining.STAMINA_BREATH_USE * climbed
    else
        local band = ex.mode == "recover" and EqExertion.band(ex.value) or "slow"
        local winded = 1 + (EqTraining.STAMINA_LOW_BREATH_LOSS - 1) * (1 - st.breath)
        st.mult = st.mult - EqTraining.STAMINA_LOSS[band] * winded * seconds
        st.breath = st.breath + EqTraining.STAMINA_BREATH_GAIN[band] * seconds
    end
    st.mult = math.min(math.max(st.mult, 1), EqTraining.STAMINA_MULT_MAX)
    st.breath = math.min(math.max(st.breath, 0), 1)
    sheet.quality.stamina = (ex.mode == "push" or ex.mode == "recover") and (st.mult - 1) / (EqTraining.STAMINA_MULT_MAX - 1) or 0
    if not worn and (ex.mode == "push" or ex.mode == "recover") then
        sheet.focused.stamina = sheet.focused.stamina + EqTraining.STAMINA_RATE * st.mult * seconds
    end
end


--- Time out of the saddle rests the horse like standing still.
--- @param sheet table
--- @param ms number milliseconds since the sheet was last ridden
--- @param stamina number|nil the horse's trained stamina
function EqTraining.rest(sheet, ms, stamina)
    if ms <= 0 then return end
    EqExertion.rest(sheet.exertion, ms, stamina)
    sheet.stamina.mult, sheet.stamina.breath = 1, 1
    sheet.sprint.ms = 0
    for stat in pairs(sheet.quality) do sheet.quality[stat] = 0 end
    sheet.combo.count, sheet.combo.timer = 0, 0
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
--- @param luck number|nil how well staff managed the role's own stats today (STAFF_LUCK), 1 when nil
--- @return table effort stat -> 0..1
function EqTraining.staffEffort(riding, playerPoints, focus, groomed, luck)
    local share = EqStats.clamp(((riding or 0) - playerPoints) / 100, 0, 1)
    local profile = EqTraining.FOCUS[focus] or EqTraining.FOCUS.balanced

    local effort = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local success = (focus ~= "balanced" and profile[stat] >= EqTraining.FOCUS_STAT_MIN) and (luck or 1) or 1
        effort[stat] = math.min(1, share * profile[stat] * EqTraining.STAFF_EFFORT_SHARE * success)
    end
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
    local share = math.min(1, monthly / 100 * effort * ageFactor * timeAdjustment * EqTraining.lowSkillFactor(level))
    return (cap - level) * share
end


-- A green horse learns the basics fast (James, 2026-10-26): below LOW_SKILL_UNTIL a stat trains
-- faster, up to LOW_SKILL_MAX times at 0, easing back to normal at LOW_SKILL_UNTIL.
EqTraining.LOW_SKILL_MAX = 3
EqTraining.LOW_SKILL_UNTIL = 40

--- @param level number trained stat
--- @return number factor 1..LOW_SKILL_MAX
function EqTraining.lowSkillFactor(level)
    local low = EqStats.clamp((EqTraining.LOW_SKILL_UNTIL - (level or 0)) / EqTraining.LOW_SKILL_UNTIL, 0, 1)
    return 1 + (EqTraining.LOW_SKILL_MAX - 1) * low
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
---     feedBoost, rate, staffLuck }; each boost table is stat -> share (EqFacility.boosts, EqFeed.dietBoost), or nil;
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
    local staff = EqTraining.staffEffort(day.riding, EqTraining.playerRidingPoints(day.sheet), record.focus, groomed,
        day.staffLuck)

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


-- Peak form (James, 2026-10-26): the player's own riding is mostly pre-contest prep. A month's
-- best minigame session in each stat lifts that stat by up to FORM_MAX points for the month's
-- events, at FORM_FULL focused effort. Plain gait riding gives none. Sessions on several days of
-- a month never add up: each stat keeps its best. It clears when the month's events have run.
EqTraining.FORM_MAX = 8
EqTraining.FORM_FULL = 1.5

--- @param sheet table|nil
--- @return table points stat -> 0..FORM_MAX from this sheet's minigame work
function EqTraining.formFrom(sheet)
    local points = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local focused = sheet ~= nil and sheet.focused ~= nil and sheet.focused[stat] or 0
        points[stat] = EqTraining.FORM_MAX * EqStats.clamp(focused / EqTraining.FORM_FULL, 0, 1)
    end
    return points
end


--- Fold one session into a horse's form: a new month starts afresh, the same month keeps the best.
--- @param form table|nil { month, stat -> points }
--- @param month number the month the session was ridden in
--- @param points table from formFrom
--- @return table form
function EqTraining.mergeForm(form, month, points)
    if form ~= nil and (form.month or 0) > month then return form end
    local merged = { month = month }
    local same = form ~= nil and form.month == month
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        merged[stat] = math.max(same and form[stat] or 0, points[stat] or 0)
    end
    return merged
end


--- A horse's form for a month's events: what it kept from earlier days, and today's riding if
--- the day has not been counted yet.
--- @param form table|nil record.form
--- @param month number
--- @param sheet table|nil today's sheet, not yet applied; sheet.month says when it was ridden
--- @return table points stat -> points (all 0 when out of form)
function EqTraining.formFor(form, month, sheet)
    local points = EqTraining.mergeForm(form ~= nil and form.month == month and form or nil, month, {})
    if sheet ~= nil and (sheet.month or 0) == month then
        points = EqTraining.mergeForm(points, month, EqTraining.formFrom(sheet))
    end
    points.month = nil
    return points
end


--- @param form table stat -> points
--- @return boolean true when any stat has at least half a point of form
function EqTraining.hasForm(form)
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if (form[stat] or 0) >= 0.5 then return true end
    end
    return false
end


--- Stats as the horse competes: trained levels plus form, at most 100. Form may pass the
--- ceiling: it is sharpness on the day, not training.
--- @param trained table stat -> level
--- @param form table|nil stat -> points
--- @return table stats
function EqTraining.withForm(trained, form)
    local stats = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        stats[stat] = math.min(100, (trained[stat] or 0) + (form ~= nil and form[stat] or 0))
    end
    return stats
end

--[[
    EqTemperament.lua
    The temperament combo (James, 2026-11-03): like the agility jump combo, but built from
    variety rather than jumps. Nothing gives orders: the rider strings together moves they
    choose, and each one that is new raises the combo and refills its bar.

    A move is something the horse settles into or finishes:
    - a gait change that isn't to a gallop (walk, trot, canter, backing up), held GAIT_HOLD_MS;
    - standing still, held HALT_HOLD_MS;
    - lateral and collected work (EqLateral.movementName: half pass, shoulder-in, piaffe,
      passage, collected walk or canter, a pirouette...), held LATERAL_HOLD_MS;
    - a big turn: TURN_ANGLE turned one way at one gait without letting the steering go for
      long. Each gait and direction is its own move (a big left turn at a trot is not the
      same as one at a canter).

    A move done among the last RECENT moves is no new thing: it is fine to do (keep riding,
    turn round things), but it neither raises the combo nor refills the bar. Galloping or
    crashing into something (being knocked to a stand) loses the combo, and so does letting
    the bar run out. Jumps neither count nor break it, and the bar can't run out mid-air.

    While a combo runs temperament builds at RATE a second for each step of the multiplier.

    Pure functions with no game calls, so they run headless; EqTrainingHooks feeds them.

    Part of Realistic Equestrian by Jasta007.
]]

EqTemperament = {}

-- The combo: up to COMBO_MAX, the bar lasting COMBO_SECONDS from the last new move.
EqTemperament.COMBO_MAX = 5
EqTemperament.COMBO_SECONDS = 12
-- After a combo is lost no new one starts for this long (so coming down from a gallop to a
-- canter doesn't start a new combo the moment the old one went).
EqTemperament.LOCK_MS = 2500
-- A move is "done recently" while it is one of the last RECENT new moves.
EqTemperament.RECENT = 3
-- How long each kind of move must be held before it counts.
EqTemperament.GAIT_HOLD_MS = 1000
EqTemperament.HALT_HOLD_MS = 2000
EqTemperament.LATERAL_HOLD_MS = 1000
-- A big turn: this much heading (radians, a half circle) turned one way at one gait. Letting the
-- steering go for TURN_GAP_MS or more starts the count again.
EqTemperament.TURN_ANGLE = math.pi
EqTemperament.TURN_GAP_MS = 1000
-- Temperament effort a second for each step of the multiplier (x5 = 0.01 a second, against a
-- dressage test's 0.031 at x8: an arena still trains far more).
EqTemperament.RATE = 0.002

local TURN_GAITS = { walk = true, trot = true, canter = true }


--- @return table state a fresh combo
function EqTemperament.new()
    return { count = 0, timer = 0, lock = 0, recent = {}, current = nil, candidate = nil, candidateMs = 0,
        turn = nil, last = nil, stale = nil, staleAt = nil, best = 0 }
end


--- The multiplier now: 0 without a combo, else 1..COMBO_MAX.
--- @param state table
--- @return number
function EqTemperament.mult(state)
    if state.count <= 0 then return 0 end
    return math.min(state.count, EqTemperament.COMBO_MAX)
end


--- The key of what the horse is settled into this frame: "lateral:<name>", "halt" or "gait:<gait>".
--- @param gait string halt, walk, trot, canter, gallop or reverse
--- @param lateral string|nil EqLateral.movementName key
--- @return string
function EqTemperament.poseKey(gait, lateral)
    if lateral ~= nil then return "lateral:" .. lateral end
    if gait == "halt" then return "halt" end
    return "gait:" .. gait
end


--- How long a pose must be held to count.
--- @param key string from poseKey
--- @return number milliseconds
function EqTemperament.holdMs(key)
    if key == "halt" then return EqTemperament.HALT_HOLD_MS end
    if key:sub(1, 8) == "lateral:" then return EqTemperament.LATERAL_HOLD_MS end
    return EqTemperament.GAIT_HOLD_MS
end


--- @param state table
--- @param key string
--- @return boolean true when the move is one of the last RECENT new moves
function EqTemperament.isRecent(state, key)
    for _, done in ipairs(state.recent) do
        if done == key then return true end
    end
    return false
end


--- Lose the combo.
--- @param state table
--- @return boolean true when there was a combo to lose
function EqTemperament.lose(state)
    local had = state.count > 0
    state.count, state.timer = 0, 0
    state.recent = {}
    state.stale, state.staleAt = nil, nil
    if had then state.lock = EqTemperament.LOCK_MS end
    return had
end


--- Forget everything (off the horse, a dressage test taking over), without the lock.
--- @param state table
--- @return boolean true when there was a combo to lose
function EqTemperament.reset(state)
    local had = state.count > 0
    state.count, state.timer, state.lock = 0, 0, 0
    state.recent = {}
    state.current, state.candidate, state.candidateMs, state.turn = nil, nil, 0, nil
    state.last, state.stale, state.staleAt = nil, nil, nil
    return had
end


--- A move done: raise the combo when it is new.
--- @param state table
--- @param key string
--- @param now number|nil ms clock, for how long "done recently" shows
--- @return string|nil "move" (new), "stale" (done recently), nil while locked after a loss
function EqTemperament.award(state, key, now)
    if state.lock > 0 then return nil end
    if EqTemperament.isRecent(state, key) then
        state.stale, state.staleAt = key, now
        return "stale"
    end
    state.count = state.count + 1
    state.best = math.max(state.best, state.count)
    state.timer = EqTemperament.COMBO_SECONDS
    state.last, state.stale, state.staleAt = key, nil, nil
    table.insert(state.recent, 1, key)
    while #state.recent > EqTemperament.RECENT do table.remove(state.recent) end
    return "move"
end


--- One frame of riding.
--- @param state table
--- @param input table { gait, lateral = key|nil, steer = "left"|"right"|nil, turned = radians the
---     heading changed this frame (any sign), crashed = true the frame the horse ran into
---     something, jumping = true while in the air or not yet judged, now = ms clock }
--- @param dt number milliseconds
--- @return string|nil event "move", "stale" or "lost"
--- @return string|nil key the move, for "move" and "stale"
function EqTemperament.step(state, input, dt)
    state.lock = math.max(0, state.lock - dt)
    local gait = input.gait

    -- Galloping or crashing loses the combo at once.
    if gait == "gallop" or input.crashed then
        state.current, state.candidate, state.candidateMs, state.turn = gait == "gallop" and "gait:gallop" or state.current, nil, 0, nil
        if EqTemperament.lose(state) then return "lost" end
        return nil
    end

    local event, key = nil, nil
    -- A jump's take-off and landing knock the gait about: nothing settles until it is judged.
    if not input.jumping then
        local pose = EqTemperament.poseKey(gait, input.lateral)
        if state.current == nil then
            -- Getting on: whatever the horse is doing is where it starts, not a move.
            state.current = pose
        elseif pose == state.current then
            state.candidate, state.candidateMs = nil, 0
        else
            if pose ~= state.candidate then state.candidate, state.candidateMs = pose, 0 end
            state.candidateMs = state.candidateMs + dt
            if state.candidateMs >= EqTemperament.holdMs(pose) then
                state.current, state.candidate, state.candidateMs = pose, nil, 0
                event, key = EqTemperament.award(state, pose, input.now), pose
            end
        end

        -- Big turns: steering one way at a walk, trot or canter, outside lateral work.
        local steer = input.steer
        if TURN_GAITS[gait] and input.lateral == nil and steer ~= nil then
            local turn = state.turn
            if turn == nil or turn.dir ~= steer or turn.gait ~= gait then
                turn = { dir = steer, gait = gait, angle = 0, gapMs = 0 }
                state.turn = turn
            end
            turn.gapMs = 0
            turn.angle = turn.angle + math.abs(input.turned or 0)
            if turn.angle >= EqTemperament.TURN_ANGLE then
                turn.angle = 0
                local turnKey = string.format("turn:%s:%s", gait, steer)
                local turnEvent = EqTemperament.award(state, turnKey, input.now)
                if event ~= "move" and turnEvent ~= nil then event, key = turnEvent, turnKey end
            end
        elseif state.turn ~= nil then
            state.turn.gapMs = state.turn.gapMs + dt
            if not TURN_GAITS[gait] or input.lateral ~= nil or state.turn.gapMs >= EqTemperament.TURN_GAP_MS then state.turn = nil end
        end
    end

    if event == "move" then return event, key end
    if state.count > 0 then
        state.timer = state.timer - dt / 1000
        if state.timer <= 0 then
            if input.jumping then
                state.timer = 0
            else
                EqTemperament.lose(state)
                return "lost"
            end
        end
    end
    return event, key
end


--- Temperament effort from the combo this frame.
--- @param state table
--- @param sheet table EqTraining sheet: focused.temperament and quality.temperament
--- @param worn boolean riding bar full: the combo counts, nothing trains
--- @param dt number milliseconds
function EqTemperament.train(state, sheet, worn, dt)
    local mult = EqTemperament.mult(state)
    sheet.quality.temperament = mult / EqTemperament.COMBO_MAX
    if worn or mult == 0 then return end
    sheet.focused.temperament = sheet.focused.temperament + EqTemperament.RATE * mult * dt / 1000
end


--- The translation key and argument for a move's name: "eq_temper_gait_trot", "eq_now_piaffe",
--- "eq_temper_turn_left" with the gait's name key.
--- @param key string
--- @return string textKey
--- @return string|nil gaitKey for a turn, the gait's eq_dressage_gait_ key
function EqTemperament.nameKeys(key)
    if key == "halt" then return "eq_temper_halt" end
    local lateral = key:match("^lateral:(.+)$")
    if lateral ~= nil then return "eq_now_" .. lateral end
    local gait, dir = key:match("^turn:(%a+):(%a+)$")
    if gait ~= nil then return "eq_temper_turn_" .. dir, "eq_dressage_gait_" .. gait end
    return "eq_temper_gait_" .. (key:match("^gait:(%a+)$") or "walk")
end

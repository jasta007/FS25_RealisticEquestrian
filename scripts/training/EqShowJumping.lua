--[[
    EqShowJumping.lua
    A timed show jumping round over a recorded course (EqCourse): pure functions with no game
    calls, so they run headless. EqCourseHooks feeds the horse's position each frame, the jump
    judgements (cleared, or a rail down) and crashes, and shows what the round says.

    Like the dressage test (James, 2026-10-27): near a course the rider is asked to "Move to the
    start line to begin Show Jumping". Behind the start line and close to it, a 3, 2, 1 countdown
    runs; crossing the line before it ends is too early and starts over. After "Go!" the clock
    starts as the horse crosses the start line, then the fences are jumped in order and the
    clock stops at the finish line (or, with none, at the last fence).

    Faults as in a real round: a rail down is 4, a refusal (running into the next fence) 4,
    a second refusal or jumping a fence out of order eliminates, and each second (or part) over
    the time allowed is 1. The time allowed comes from the course length at TIME_SPEED; twice
    that is the time limit. A finished round pays agility training (payoff), most for a clear.

    A line (start, finish) is { ax, az, bx, bz, x, z }: its red end a, white end b, crossed the
    right way from crossSide's -1 side, as with the start and finish line placeables (red flag on
    the right as the horse rides through).

    Part of Realistic Equestrian by Jasta007.
]]

EqShowJumping = {}

-- The countdown starts within this many metres behind the start line, and stops if the horse
-- wanders off beyond READY_RADIUS * READY_LEAVE.
EqShowJumping.READY_RADIUS = 12
EqShowJumping.READY_LEAVE = 1.5
EqShowJumping.COUNT_MS = 3000
-- After "Go!" the horse has this long to cross the start line.
EqShowJumping.GO_MS = 45000
-- A fence crossed waits this long for its jump to be judged before it counts as clear.
EqShowJumping.PENDING_MS = 3000
EqShowJumping.RAIL_FAULTS = 4
EqShowJumping.REFUSAL_FAULTS = 4
EqShowJumping.REFUSALS_OUT = 2
-- In a round a fence only counts when the horse goes over it between its flags (not the 0.75 m
-- spare recording allows), so going over a wing is no clear, while any off-centre jump between
-- the flags still is (James, 2026-10-27). Going through within RUNOUT_MARGIN outside
-- the flags without that is a run-out: a refusal.
EqShowJumping.INSIDE_MARGIN = 0
EqShowJumping.RUNOUT_MARGIN = 2.5
-- A crash this close to the next fence's line (between its flags) is a refusal; running into
-- anything else, like the arena wall, is not.
EqShowJumping.REFUSAL_RADIUS = 3
-- Time allowed: the course at 350 m a minute (a usual show jumping speed), at least MIN_TIME s.
EqShowJumping.TIME_SPEED = 350 / 60
EqShowJumping.MIN_TIME = 20
EqShowJumping.TIME_LIMIT_FACTOR = 2
-- A line made from the course's path stands this far before fence 1 and after the last fence.
EqShowJumping.LINE_OFFSET = 12
EqShowJumping.LINE_WIDTH = 8
-- The result shows this long before the next round can start.
EqShowJumping.REST_MS = 8000
-- A finished round pays this many top-combo show jumps' worth of agility training, less for
-- faults (none at FAULTS_NO_PAY), and none when eliminated.
EqShowJumping.ROUND_BONUS_JUMPS = 12
EqShowJumping.FAULTS_NO_PAY = 20


--- @param points table
--- @param from number index
--- @param to number index
--- @return number metres along the points between the two
local function pathBetween(points, from, to)
    local length = 0
    for i = math.max(2, from + 1), math.min(#points, to) do
        local dx, dz = points[i].x - points[i - 1].x, points[i].z - points[i - 1].z
        length = length + math.sqrt(dx * dx + dz * dz)
    end
    return length
end


--- The point LINE_OFFSET metres along the path from an index, going back (-1) or on (1), with
--- the path's direction there.
--- @return number x, number z, number tx, number tz (unit direction of travel), number index
local function alongPath(points, index, way, distance)
    index = math.max(1, math.min(#points, index))
    local left = distance
    local i = index
    while left > 0 do
        local j = i + way
        if j < 1 or j > #points then break end
        local dx, dz = points[j].x - points[i].x, points[j].z - points[i].z
        local d = math.sqrt(dx * dx + dz * dz)
        if d >= left then
            local share = left / d
            local x, z = points[i].x + dx * share, points[i].z + dz * share
            local tx, tz = dx / d * way, dz / d * way
            return x, z, tx, tz, i
        end
        left = left - d
        i = j
    end
    -- The path ran out: the end it reached, facing along its last step.
    local k = math.max(1, math.min(#points, i - way))
    local dx, dz = (points[i].x - points[k].x) * way, (points[i].z - points[k].z) * way
    local d = math.sqrt(dx * dx + dz * dz)
    if d < 1e-6 then dx, dz, d = 0, 1, 1 end
    return points[i].x, points[i].z, dx / d, dz / d, i
end


--- A line across the path at x, z for a horse travelling along tx, tz: red end on its right.
local function lineAt(x, z, tx, tz)
    local half = EqShowJumping.LINE_WIDTH / 2
    -- Facing +z the right hand is -x: right = (-tz, tx).
    local rx, rz = -tz, tx
    return { ax = x + rx * half, az = z + rz * half, bx = x - rx * half, bz = z - rz * half, x = x, z = z }
end


--- The start line made from the path: LINE_OFFSET before fence 1.
--- @param course table
--- @return table line, number the path index it stands at
function EqShowJumping.startFromPath(course)
    local first = course.jumps[1]
    local x, z, tx, tz, index = alongPath(course.points, first.pointIndex or 1, -1, EqShowJumping.LINE_OFFSET)
    return lineAt(x, z, tx, tz), index
end


--- The finish line made from the path: LINE_OFFSET after the last fence.
--- @param course table
--- @return table line, number the path index it stands at
function EqShowJumping.finishFromPath(course)
    local last = course.jumps[#course.jumps]
    local x, z, tx, tz, index = alongPath(course.points, last.pointIndex or #course.points, 1, EqShowJumping.LINE_OFFSET)
    return lineAt(x, z, tx, tz), index
end


--- @param course table
--- @return number seconds allowed: the path from the start line to the finish line at TIME_SPEED
function EqShowJumping.timeAllowed(course)
    local _, from = EqShowJumping.startFromPath(course)
    local _, to = EqShowJumping.finishFromPath(course)
    local metres = pathBetween(course.points, from, to) + 2 * EqShowJumping.LINE_OFFSET
    return math.max(EqShowJumping.MIN_TIME, math.ceil(metres / EqShowJumping.TIME_SPEED))
end


--- @param line table
--- @param x number
--- @param z number
--- @return number which side of the line the point is: -1 the approach side, 1 past it
function EqShowJumping.sideOf(line, x, z)
    local dx, dz = line.bx - line.ax, line.bz - line.az
    local s = dx * (z - line.az) - dz * (x - line.ax)
    return s > 0 and 1 or -1
end


--- @param line table { ax, az, bx, bz }
--- @param x number
--- @param z number
--- @return number metres from the point to the nearest part of the line
function EqShowJumping.distanceToLine(line, x, z)
    local dx, dz = line.bx - line.ax, line.bz - line.az
    local length2 = dx * dx + dz * dz
    local share = length2 > 1e-9 and math.max(0, math.min(1, ((x - line.ax) * dx + (z - line.az) * dz) / length2)) or 0
    local px, pz = line.ax + dx * share - x, line.az + dz * share - z
    return math.sqrt(px * px + pz * pz)
end


--- @param course table
--- @param start table|nil a placed start line, else one from the path
--- @param finish table|nil a placed finish line, else one from the path; false for none
--- @return table round
function EqShowJumping.newRound(course, start, finish)
    if finish == nil then finish = EqShowJumping.finishFromPath(course) end
    return {
        course = course, start = start or EqShowJumping.startFromPath(course), finish = finish or nil,
        state = "approach", allowed = EqShowJumping.timeAllowed(course), clock = 0,
        next = 1, faults = 0, refusals = 0, count = nil,
    }
end


local function restart(round)
    round.state, round.clock, round.next, round.faults, round.refusals = "approach", 0, 1, 0, 0
    round.pending, round.count, round.result, round.why = nil, nil, nil, nil
end


local function eliminate(round, why)
    round.state, round.restMs = "done", EqShowJumping.REST_MS
    round.result = { eliminated = why, seconds = round.clock / 1000 }
    round.pending = nil
    return "eliminated"
end


local function finish(round)
    local seconds = round.clock / 1000
    local timeFaults = math.max(0, math.ceil(seconds - round.allowed - 1e-9))
    round.state, round.restMs = "done", EqShowJumping.REST_MS
    round.result = { seconds = seconds, faults = round.faults, timeFaults = timeFaults,
        total = round.faults + timeFaults, clear = round.faults + timeFaults == 0 }
    return "finished"
end


--- @param round table
--- @param line table
--- @param input table
--- @return number|nil crossSide of this frame's step over the line
local function crossed(line, input, margin)
    return EqCourse.crossSide(line.ax, line.az, line.bx, line.bz, input.px, input.pz, input.x, input.z, margin)
end


--- One frame of the round.
--- @param round table
--- @param input table { px, pz (last frame), x, z, dt ms, judged = nil|"clear"|"knock"|"nothing", crashed = bool }
--- @return string|nil event: "count", "early", "go", "started", "fence", "rail", "refusal", "runout",
---   "eliminated", "finished", "reset", "ready" (the next round can start)
function EqShowJumping.step(round, input)
    local dt = input.dt or 0
    local state = round.state
    local start = round.start

    if state == "approach" then
        local dx, dz = input.x - start.x, input.z - start.z
        if dx * dx + dz * dz <= EqShowJumping.READY_RADIUS ^ 2 and EqShowJumping.sideOf(start, input.x, input.z) == -1 then
            round.state, round.countMs, round.count = "countdown", EqShowJumping.COUNT_MS, 3
            return "count"
        end
        return nil
    end

    if state == "countdown" then
        if crossed(start, input) ~= nil then
            restart(round)
            round.why = "early"
            return "early"
        end
        local dx, dz = input.x - start.x, input.z - start.z
        if dx * dx + dz * dz > (EqShowJumping.READY_RADIUS * EqShowJumping.READY_LEAVE) ^ 2 then
            restart(round)
            return "reset"
        end
        round.countMs = round.countMs - dt
        if round.countMs <= 0 then
            round.state, round.goMs, round.count = "go", EqShowJumping.GO_MS, nil
            return "go"
        end
        local count = math.ceil(round.countMs / 1000)
        if count ~= round.count then
            round.count = count
            return "count"
        end
        return nil
    end

    if state == "go" then
        round.goMs = round.goMs - dt
        if crossed(start, input) == -1 then
            round.state, round.clock, round.next = "running", 0, 1
            return "started"
        end
        if round.goMs <= 0 then return eliminate(round, "late") end
        return nil
    end

    if state == "done" then
        round.restMs = round.restMs - dt
        if round.restMs <= 0 then
            restart(round)
            return "ready"
        end
        return nil
    end

    -- Running.
    round.clock = round.clock + dt
    local jumps = round.course.jumps
    local event = nil

    -- A fence crossed waits for its jump's judgement.
    local pending = round.pending
    if pending ~= nil then
        if input.judged == "knock" then
            round.faults = round.faults + EqShowJumping.RAIL_FAULTS
            round.pending, event = nil, "rail"
        elseif input.judged ~= nil or round.clock - pending.at >= EqShowJumping.PENDING_MS then
            round.pending, event = nil, "fence"
        end
    end

    -- The next fence, jumped either way (a course recorded with the side the wrong way round
    -- would otherwise never let it count). A fence before it still waiting for its judgement (a
    -- double, close together) counts as clear: a jump is judged by the next take-off.
    local nextJump = jumps[round.next]
    if nextJump ~= nil and nextJump.ax ~= nil and crossed(nextJump, input, EqShowJumping.RUNOUT_MARGIN) ~= nil
        and crossed(nextJump, input, EqShowJumping.INSIDE_MARGIN) == nil then
        -- Past the end of the fence, over a wing or round a flag: a run-out.
        round.refusals = round.refusals + 1
        round.faults = round.faults + EqShowJumping.REFUSAL_FAULTS
        if round.refusals >= EqShowJumping.REFUSALS_OUT then return eliminate(round, "refusals") end
        event = "runout"
    elseif nextJump ~= nil and nextJump.ax ~= nil and crossed(nextJump, input, EqShowJumping.INSIDE_MARGIN) ~= nil then
        if round.pending ~= nil then event = "fence" end
        round.pending = { index = round.next, at = round.clock }
        round.next = round.next + 1
        if input.judged == "knock" then
            round.faults = round.faults + EqShowJumping.RAIL_FAULTS
            round.pending, event = nil, "rail"
        end
    end

    -- Any other fence of the course jumped the right way is the wrong course.
    for i, jump in ipairs(jumps) do
        local current = jumps[round.next]
        local same = (current ~= nil and EqCourse.sameJump(jump, current))
            or (round.pending ~= nil and EqCourse.sameJump(jump, jumps[round.pending.index]))
        if i ~= round.next and not same and jump.ax ~= nil and crossed(jump, input, EqShowJumping.INSIDE_MARGIN) == jump.side then
            -- Only one that is not the fence just jumped (the same jump twice in a course).
            local just = jumps[round.next - 1]
            if just == nil or not EqCourse.sameJump(jump, just) then
                round.why = i
                return eliminate(round, "wrongCourse")
            end
        end
    end

    -- Running into the next fence is a refusal.
    if input.crashed and round.pending == nil and nextJump ~= nil then
        if EqShowJumping.distanceToLine(nextJump.ax ~= nil and nextJump or { ax = nextJump.x, az = nextJump.z,
            bx = nextJump.x, bz = nextJump.z }, input.x, input.z) <= EqShowJumping.REFUSAL_RADIUS then
            round.refusals = round.refusals + 1
            round.faults = round.faults + EqShowJumping.REFUSAL_FAULTS
            if round.refusals >= EqShowJumping.REFUSALS_OUT then return eliminate(round, "refusals") end
            event = "refusal"
        end
    end

    if round.clock / 1000 > round.allowed * EqShowJumping.TIME_LIMIT_FACTOR then return eliminate(round, "timeLimit") end

    -- Every fence jumped: the finish line (the last fence counts as clear if its judgement has
    -- not come by then), or with none the last fence's judgement.
    if round.next > #jumps then
        if (round.finish == nil and round.pending == nil) or (round.finish ~= nil and crossed(round.finish, input) == -1) then
            round.pending = nil
            return finish(round)
        end
    end
    return event
end


--- Agility training for a finished round, as focused effort (EqTraining's sheet.focused.agility).
--- @param result table round.result
--- @return number effort
function EqShowJumping.payoff(result)
    if result == nil or result.eliminated ~= nil then return 0 end
    local share = math.max(0, 1 - (result.total or 0) / EqShowJumping.FAULTS_NO_PAY)
    return EqTraining.AGILITY_PER_JUMP * EqTraining.COMBO_MAX * EqTraining.SHOW_JUMP_FACTOR
        * EqShowJumping.ROUND_BONUS_JUMPS * share
end

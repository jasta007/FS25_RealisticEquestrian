--[[
    EqDressage.lua
    The temperament routine ridden round dressage markers: pure functions with no game calls, so
    they run headless. EqTrainingHooks finds the markers (Riding Hall 2k26's letter boards, and
    the letters of our own arenas) and passes them in as a course. A routine starts only when the
    rider comes to the markers (ARENA_NEAR); with none near, there is no routine (James, 2026-10-29).

    In one of our arenas the routine is a dressage test of figures drawn on the ground
    (EqDressagePath, James 2026-10-29). Round Riding Hall's boards, which a player can put
    anywhere, it is the routine of legs below.

    A course is every marker linked to the one nearest the horse: the nearest within
    SEARCH_RADIUS, then any within LINK_RADIUS of a marker already in. It needs at least three
    markers that are not all in a line. A standard 20 x 40 m arena reads A K E H C M B F round
    the edge with D X G on the centre line, but a player can put them anywhere.

    Most commands are legs: "Trot: Marker B", ride there at that gait. Each leg's time comes from
    its length (GO_SPEED, with slack that shrinks as the multiplier climbs). Near the marker the
    next command shows early (PREVIEW_SECONDS out), and reaching the marker (ARRIVE_RADIUS) raises
    the multiplier and starts it. Passing close to another marker on the way may ask for a quick
    gait change (PASS_CHANCE, PASS_REACT_MS) worth an extra step; missing that costs nothing.
    At a marker the next command can also be a halt (then maybe a turn on the spot, the only
    turns asked for) or, rarely, backing up for a moment, a halt, and a new leg.

    Part of Realistic Equestrian by Jasta007.
]]

EqDressage = {}

-- Riding Hall 2k26's markers: placeable xml filenames, lowercased, matched at the end.
EqDressage.MARKER_XML = { "fs25_ridinghall/objekt.xml" }
-- Our own arenas (placeables/dressageArena): every letter is a node named eqMarker_<letter>.
EqDressage.ARENA_XML = "placeables/dressagearena/dressagearena"
EqDressage.ARENA_NODE = "^eqMarker_(%u)$"
EqDressage.SEARCH_RADIUS = 100
EqDressage.LINK_RADIUS = 60
EqDressage.MAX_MARKERS = 40
-- The markers must spread at least this far either side of a line through the two furthest apart.
EqDressage.MIN_SPREAD = 2

-- Assumed metres per second at each gait, on the slow side; a leg gets GO_SLACK times that long
-- plus GO_EXTRA_MS to change gait and turn, and GO_PRESSURE less slack for each step above x1.
EqDressage.GO_SPEED = { walk = 1.4, trot = 2.8, canter = 4.5 }
EqDressage.GO_SLACK = 1.6
EqDressage.GO_PRESSURE = 0.06
EqDressage.GO_EXTRA_MS = 4000
-- Every command gets this much longer than the above (James, 2026-10-27: 20% more time).
EqDressage.TIME_FACTOR = 1.2
-- A gait is only asked for on a leg at least this long, and picked by these weights.
EqDressage.GO_MIN_DISTANCE = { walk = 0, trot = 10, canter = 18 }
-- ...and at most this long: long walks are dull (James), so a walk is only to a nearby marker.
EqDressage.GO_MAX_DISTANCE = { walk = 12 }
-- Trot is the usual gait (James, 2026-10-27).
EqDressage.GO_WEIGHTS = { walk = 1, trot = 6, canter = 3 }
EqDressage.GO_GAITS = { "walk", "trot", "canter" }
-- Targets nearer than this are only picked when there is nothing further.
EqDressage.MIN_TARGET_DISTANCE = 8
-- How close counts as at a marker, by gait.
-- Wider at speed, so there is room to slow down (James, 2026-10-27).
EqDressage.ARRIVE_RADIUS = { walk = 3, trot = 4.5, canter = 7 }
-- The next command shows when the marker is this many seconds out at the leg's gait (and never
-- closer than PREVIEW_MIN metres), so there is time to plan the turn.
EqDressage.PREVIEW_SECONDS = 3
EqDressage.PREVIEW_MIN = 6
-- Time to settle into the leg's gait; after it, the wrong gait for DRIFT_MS breaks the routine.
EqDressage.REACT_MS = 3000
EqDressage.DRIFT_MS = 1500
-- Passing within PASS_RADIUS of another marker: PASS_CHANCE in 100 of a quick gait change.
EqDressage.PASS_RADIUS = 3
EqDressage.PASS_CHANCE = 35
EqDressage.PASS_REACT_MS = 2000
-- What comes after reaching a marker, and after a halt there (weights). Backing up is rare.
EqDressage.AT_MARKER = { { "go", 70 }, { "halt", 12 }, { "circle", 10 }, { "reverse", 8 } }
-- Halts only at the middle and end letters, and not too often (James, 2026-10-27).
EqDressage.HALT_LETTERS = { A = true, C = true, E = true, B = true, X = true }
-- No turns on the spot: the base game's animation for them looks wrong (James). Circles instead.
EqDressage.AFTER_HALT = { { "go", 1 } }
-- Stand this long after a halt is done before the next command (a random time in the range).
EqDressage.HOLD_MS = { 1500, 3000 }
-- Back up for this long, then halt.
EqDressage.REVERSE_MS = 2500
-- A turn on the spot counts once its steering key is held this long.
EqDressage.TURN_MS = 600
-- Our arenas (markers with arena set) ride a test (EqDressagePath): coming within ARENA_NEAR
-- metres of one's rail (not of any letter: from a long arena's far end, "Move to A" showed 84 m
-- off) starts it. Finishing pays up to TEST_BONUS_SECONDS of temperament training at the top
-- multiplier at once, by its score; after that no new test starts for TEST_REST_MS.
EqDressage.ARENA_NEAR = 12
EqDressage.TEST_BONUS_SECONDS = 60
EqDressage.TEST_REST_MS = 20000
-- A test broken by faults waits this long before the markers start a new one.
EqDressage.BREAK_REST_MS = 5000
-- A leg that starts with a turn gets more time: TURN_ALLOW_MS at its gait for a full about-turn,
-- in proportion for less (James: turning round at M to ride to K eats a third of the time).
EqDressage.TURN_ALLOW_MS = { walk = 4000, trot = 6000, canter = 8000 }
-- A mistake (the wrong gait, running out of time) is a fault, not the end (James): the
-- multiplier drops FAULT_DROP steps and a fresh leg starts from here; FAULTS faults end it.
EqDressage.FAULTS = 3
EqDressage.FAULT_DROP = 2
-- A circle (volte) at a walk or trot, steering one way: done once the horse has come this far
-- round (radians), within CIRCLE_MS.
EqDressage.CIRCLE_TURN = math.pi * 2 * 0.9
EqDressage.CIRCLE_MS = 20000
-- An arena's bounds reach OUT_MARGIN metres past its letters.
EqDressage.OUT_MARGIN = 1


--- @return number metres between two points on the ground
local function distance(ax, az, bx, bz)
    return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end


--- @param filename string|nil a placeable's xml filename
--- @return boolean true for a dressage marker
function EqDressage.isMarkerXml(filename)
    if type(filename) ~= "string" then return false end
    local lower = filename:lower():gsub("\\", "/")
    for _, suffix in ipairs(EqDressage.MARKER_XML) do
        if lower:sub(-#suffix) == suffix then return true end
    end
    return false
end


--- @param filename string|nil a placeable's xml filename
--- @return boolean true for one of our dressage arenas
function EqDressage.isArenaXml(filename)
    if type(filename) ~= "string" then return false end
    local lower = filename:lower():gsub("\\", "/")
    return lower:find(EqDressage.ARENA_XML, 1, true) ~= nil and lower:sub(-4) == ".xml"
end


--- @param name string|nil a node's name in an arena
--- @return string|nil the letter when the node is a marker
function EqDressage.arenaLetter(name)
    if type(name) ~= "string" then return nil end
    return name:match(EqDressage.ARENA_NODE)
end


--- The letter on a marker: from its configuration's name when that is one letter ("A",
--- "Letter A"), else from the configuration's place in the list (1 = A ... 26 = Z).
--- @param index number|nil
--- @param name string|nil
--- @return string letter
function EqDressage.letterFor(index, name)
    if type(name) == "string" then
        local letter = name:match("^%s*(%a)%s*$") or name:match("[%s_](%a)%s*$")
        if letter ~= nil then return letter:upper() end
    end
    if type(index) == "number" and index >= 1 and index <= 26 then return string.char(64 + index) end
    return "?"
end


--- The markers that make a course around a point, or nil when there are too few to ride.
--- @param markers table { { letter, x, z }, ... } every marker on the map
--- @param x number
--- @param z number
--- @return table|nil course markers, nearest first
function EqDressage.findCourse(markers, x, z)
    local nearest, best = nil, EqDressage.SEARCH_RADIUS
    for _, marker in ipairs(markers) do
        local d = distance(x, z, marker.x, marker.z)
        if d <= best then nearest, best = marker, d end
    end
    if nearest == nil then return nil end
    local course, taken, i = { nearest }, { [nearest] = true }, 1
    while i <= #course and #course < EqDressage.MAX_MARKERS do
        local from = course[i]
        for _, marker in ipairs(markers) do
            if not taken[marker] and distance(from.x, from.z, marker.x, marker.z) <= EqDressage.LINK_RADIUS then
                taken[marker] = true
                table.insert(course, marker)
            end
        end
        i = i + 1
    end
    if #course < 3 then return nil end
    -- A polygon, not a line: the furthest any marker sits off the line through the furthest pair.
    local a, b, far = nil, nil, -1
    for p = 1, #course do
        for q = p + 1, #course do
            local d = distance(course[p].x, course[p].z, course[q].x, course[q].z)
            if d > far then a, b, far = course[p], course[q], d end
        end
    end
    if far <= 0 then return nil end
    local spread = 0
    for _, marker in ipairs(course) do
        local cross = math.abs((b.x - a.x) * (marker.z - a.z) - (b.z - a.z) * (marker.x - a.x)) / far
        spread = math.max(spread, cross)
    end
    if spread < EqDressage.MIN_SPREAD then return nil end
    return course
end


--- @param list table { { name, weight }, ... }
--- @param rng function (n) -> 1..n
--- @return string name
local function pick(list, rng)
    local total = 0
    for _, entry in ipairs(list) do total = total + entry[2] end
    local roll = rng(total)
    for _, entry in ipairs(list) do
        roll = roll - entry[2]
        if roll <= 0 then return entry[1] end
    end
    return list[#list][1]
end


--- @return boolean true when two markers stand in the same place
local function same(a, b)
    return a ~= nil and b ~= nil and math.abs(a.x - b.x) < 0.5 and math.abs(a.z - b.z) < 0.5
end


--- @param routine table
--- @param gait string
--- @param metres number
--- @return number milliseconds a leg of that length gets
function EqDressage.legMs(routine, gait, metres)
    local slack = EqDressage.GO_SLACK * (1 - EqDressage.GO_PRESSURE * (math.max(1, routine.mult or 1) - 1))
    return (EqDressage.GO_EXTRA_MS + metres / EqDressage.GO_SPEED[gait] * slack * 1000) * EqDressage.TIME_FACTOR
end


--- Plan a leg from where the horse is: a marker, further ones likelier, and a gait it has room for.
--- @param routine table
--- @param course table { x, z, markers }
--- @param rng function
--- @return table task
function EqDressage.planLeg(routine, course, rng)
    local candidates, fallback = {}, {}
    for _, marker in ipairs(course.markers) do
        if not same(marker, routine.from) then
            local d = distance(course.x, course.z, marker.x, marker.z)
            table.insert(fallback, { marker, d })
            if d >= EqDressage.MIN_TARGET_DISTANCE then table.insert(candidates, { marker, d }) end
        end
    end
    if #candidates == 0 then candidates = fallback end
    if #candidates == 0 then candidates = { { course.markers[1], 0 } } end
    local weighted = {}
    for i, entry in ipairs(candidates) do weighted[i] = { i, math.max(1, math.floor(entry[2])) ^ 2 } end
    local chosen = candidates[pick(weighted, rng)]
    local gaits = {}
    for _, gait in ipairs(EqDressage.GO_GAITS) do
        local most = EqDressage.GO_MAX_DISTANCE[gait]
        if chosen[2] >= EqDressage.GO_MIN_DISTANCE[gait] and (most == nil or chosen[2] <= most) then table.insert(gaits, { gait, EqDressage.GO_WEIGHTS[gait] }) end
    end
    local marker = chosen[1]
    return { kind = "go", gait = pick(gaits, rng), marker = { letter = marker.letter, x = marker.x, z = marker.z } }
end


--- @param course table { x, z, markers }
--- How far the horse is from where a test starts: the nearest of our arenas' letter rectangles,
--- or the nearest other marker (Riding Hall's letter boards).
--- @param course table { x, z, markers }
--- @return number metres, 0 inside an arena, math.huge with no markers
function EqDressage.startDistance(course)
    local best = math.huge
    for _, marker in ipairs(course.markers) do
        if not marker.arena then
            best = math.min(best, distance(course.x, course.z, marker.x, marker.z))
        elseif marker.letter == "X" then
            local bounds = EqDressage.arenaBounds(course, marker)
            if bounds ~= nil then
                local dx, dz = course.x - bounds.mx, course.z - bounds.mz
                local along = math.max(math.abs(dx * bounds.ux + dz * bounds.uz) - bounds.halfLength, 0)
                local across = math.max(math.abs(dx * bounds.uz - dz * bounds.ux) - bounds.halfWidth, 0)
                best = math.min(best, math.sqrt(along * along + across * across))
            end
        end
    end
    return best
end


--- @param course table { x, z, markers }
--- @return boolean true within ARENA_NEAR of one of our arenas (its letters' rectangle)
function EqDressage.nearArena(course)
    for _, marker in ipairs(course.markers) do
        if marker.arena and marker.letter == "X" then
            local bounds = EqDressage.arenaBounds(course, marker)
            if bounds ~= nil then
                local dx, dz = course.x - bounds.mx, course.z - bounds.mz
                local along = math.max(math.abs(dx * bounds.ux + dz * bounds.uz) - bounds.halfLength, 0)
                local across = math.max(math.abs(dx * bounds.uz - dz * bounds.ux) - bounds.halfWidth, 0)
                if math.sqrt(along * along + across * across) <= EqDressage.ARENA_NEAR then return true end
            end
        end
    end
    return false
end


--- @param course table { x, z, markers }
--- @return boolean true close enough to the markers for a test to start (ARENA_NEAR)
function EqDressage.atMarkers(course)
    return EqDressage.startDistance(course) <= EqDressage.ARENA_NEAR
end


--- @param course table { x, z, markers }
--- @return boolean true when every marker is one of our arenas' (no other markers to ride round)
function EqDressage.arenaOnly(course)
    for _, marker in ipairs(course.markers) do
        if not marker.arena then return false end
    end
    return true
end


--- The rectangle of the arena an X belongs to, from its A and C and how far its letters stand
--- from the centre line, OUT_MARGIN wider all round.
--- @param course table
--- @param x table the arena's X marker
--- @return table|nil { mx, mz, ux, uz, halfLength, halfWidth }
function EqDressage.arenaBounds(course, x)
    local a, c
    for _, marker in ipairs(course.markers) do
        if marker.arena and marker.arenaId == x.arenaId then
            if marker.letter == "A" and (a == nil or distance(x.x, x.z, marker.x, marker.z) < distance(x.x, x.z, a.x, a.z)) then a = marker end
            if marker.letter == "C" and (c == nil or distance(x.x, x.z, marker.x, marker.z) < distance(x.x, x.z, c.x, c.z)) then c = marker end
        end
    end
    if a == nil or c == nil then return nil end
    local length = distance(a.x, a.z, c.x, c.z)
    if length < 1 then return nil end
    local bounds = { mx = (a.x + c.x) / 2, mz = (a.z + c.z) / 2, ux = (c.x - a.x) / length, uz = (c.z - a.z) / length,
        halfLength = length / 2 + EqDressage.OUT_MARGIN, halfWidth = 0 }
    for _, marker in ipairs(course.markers) do
        if marker.arena and marker.arenaId == x.arenaId then
            local across = math.abs((marker.x - bounds.mx) * bounds.uz - (marker.z - bounds.mz) * bounds.ux)
            if across <= length then bounds.halfWidth = math.max(bounds.halfWidth, across) end
        end
    end
    bounds.halfWidth = bounds.halfWidth + EqDressage.OUT_MARGIN
    return bounds
end


--- @param bounds table from arenaBounds
--- @return boolean true when a point is inside the arena
function EqDressage.inArena(bounds, px, pz)
    local dx, dz = px - bounds.mx, pz - bounds.mz
    return math.abs(dx * bounds.ux + dz * bounds.uz) <= bounds.halfLength
        and math.abs(dx * bounds.uz - dz * bounds.ux) <= bounds.halfWidth
end


--- The command after one is done.
--- @param routine table
--- @param course table
--- @param done string|nil the kind just done: go (at a marker), halt, turn or reverse
--- @param rng function
--- @return table task
function EqDressage.plan(routine, course, done, rng)
    local kind = "go"
    if done == "go" then
        local at = routine.from ~= nil and routine.from.letter or nil
        local choices = EqDressage.AT_MARKER
        if not EqDressage.HALT_LETTERS[at] then
            choices = {}
            for _, entry in ipairs(EqDressage.AT_MARKER) do
                if entry[1] ~= "halt" then table.insert(choices, entry) end
            end
        end
        kind = pick(choices, rng)
    elseif done == "halt" and not routine.afterReverse then
        kind = pick(EqDressage.AFTER_HALT, rng)
    elseif done == "reverse" then
        kind = "halt"
    end
    if kind == "go" then return EqDressage.planLeg(routine, course, rng) end
    if kind == "turn" then return { kind = "turn", side = rng(2) == 1 and "left" or "right" } end
    if kind == "circle" then return { kind = "circle", side = rng(2) == 1 and "left" or "right", turned = 0 } end
    return { kind = kind }
end


--- How a quick change on the way reads: a flying change from a walk up to a canter, else a change.
--- @param bonus table { gait, from }
--- @return string text key, eq_dressage_flying or eq_dressage_change
function EqDressage.changeKey(bonus)
    if bonus.gait == "canter" and bonus.from == "walk" then return "eq_dressage_flying" end
    return "eq_dressage_change"
end


--- The name a task shows by: go, halt, reverse, spinLeft or spinRight (eq_move_<name>).
--- @param task table|nil
--- @return string|nil
function EqDressage.requestName(task)
    if task == nil then return nil end
    if task.kind == "turn" then return task.side == "left" and "spinLeft" or "spinRight" end
    if task.kind == "circle" then return task.side == "left" and "circleLeft" or "circleRight" end
    return task.kind
end


--- Make a task the one being asked for.
--- @param routine table
--- @param task table
--- @param course table
local function begin(routine, task, course)
    routine.task, routine.preview, routine.bonus, routine.passed = task, nil, nil, {}
    routine.request = EqDressage.requestName(task)
    routine.taskMs, routine.driftMs, routine.steerMs = 0, 0, 0
    routine.afterReverse = task.kind == "halt" and routine.lastDone == "reverse"
    if task.kind == "go" then
        task.gaitMs = 0
        local dx, dz = task.marker.x - course.x, task.marker.z - course.z
        local length = math.sqrt(dx * dx + dz * dz)
        routine.reactMs = EqDressage.legMs(routine, task.gait, length)
        task.startX, task.startZ = course.x, course.z
        local heading = routine.heading
        if heading ~= nil and length > 0.5 then
            -- 0 straight on, 1 a full about-turn from the way the last leg rode.
            local turn = math.acos(math.max(-1, math.min(1, (dx * heading.x + dz * heading.z) / length))) / math.pi
            routine.reactMs = routine.reactMs + EqDressage.TURN_ALLOW_MS[task.gait] * turn * EqDressage.TIME_FACTOR
        end
    elseif task.kind == "circle" then
        routine.reactMs = EqDressage.CIRCLE_MS * EqDressage.TIME_FACTOR
    else
        routine.reactMs = EqDressage.REACT_MS * EqDressage.TIME_FACTOR
    end
    routine.deadline = routine.clock + routine.reactMs
    routine.shown, routine.shownUntil = routine.request, routine.clock + 1500
end


--- The X of our arena nearest the horse, or nil.
--- @param course table { x, z, markers }
--- @return table|nil marker
function EqDressage.arenaX(course)
    local best, bestD = nil, nil
    for _, marker in ipairs(course.markers) do
        if marker.arena and marker.letter == "X" then
            local d = distance(course.x, course.z, marker.x, marker.z)
            if bestD == nil or d < bestD then best, bestD = marker, d end
        end
    end
    return best
end


--- @param seed number|string
--- @return function rng (n) -> 1..n, the same rolls every time for the same seed
local function seeded(seed)
    local random = EqRandom.new(seed)
    return function(n) return math.min(n, 1 + math.floor(random:next() * n)) end
end


--- Start the routine on a course. Near one of our arenas it is a test of figures
--- (EqDressagePath): the arena's own test when the player made one, else a hosted event's fixed
--- test when course.test says so, else a new one.
--- Elsewhere the first leg is asked for at once.
--- @param routine table
--- @param course table { x, z, markers, test = { seed, moves, counts }|nil, temperament }
--- @param rng function
function EqDressage.start(routine, course, rng)
    routine.kind, routine.from, routine.lastDone = "markers", nil, nil
    routine.faults, routine.heading, routine.path, routine.competing = 0, nil, nil, nil
    local x = EqDressage.nearArena(course) and EqDressage.arenaX(course) or nil
    local frame = x ~= nil and EqDressagePath.frameFor(course.markers, x) or nil
    if frame ~= nil then
        local fixed = course.test
        -- The player's own test for this arena (EqDressageTests) rides instead of a random one,
        -- in training and in your own events.
        local plan = EqDressageTests ~= nil and EqDressageTests.planFor(frame) or nil
        local test
        if plan ~= nil then
            test = EqDressagePath.build(frame, nil, nil, plan)
        else
            test = EqDressagePath.build(frame, EqDressagePath.figuresFor(fixed ~= nil and fixed.moves or nil),
                fixed ~= nil and seeded(fixed.seed) or rng)
        end
        routine.kind, routine.path = "path", EqDressagePath.newRun(test, course.temperament)
        routine.competing = fixed ~= nil and fixed.counts or nil
        routine.task, routine.request, routine.preview, routine.bonus = { kind = "path" }, nil, nil, nil
        return
    end
    begin(routine, EqDressage.planLeg(routine, course, rng), course)
end


--- One frame of a test of figures.
--- @return string|nil event as EqDressage.step's, "test" once it is over
local function pathStep(sheet, move, dt, course)
    local routine = sheet.routine
    local run = routine.path
    -- The course carries the horse's facing and head bend for lateral work.
    local event = EqDressagePath.step(run, move, course.x, course.z, dt, course.dirX ~= nil and course or nil)
    if event == "done" then
        if run.lastMark >= EqDressagePath.MULT_UP then
            routine.mult = math.min(routine.mult + 1, EqTraining.ROUTINE_MAX)
        elseif run.lastMark < EqDressagePath.MULT_DOWN then
            routine.mult = math.max(1, routine.mult - 1)
        end
    elseif event == "fault" then
        routine.faults = run.errors
        routine.mult = math.max(1, routine.mult - EqDressage.FAULT_DROP)
    elseif event == "lost" then
        routine.faults = run.errors
        EqTraining.breakRoutine(sheet)
    end
    return event
end


--- One step done: raise the multiplier and move on.
--- @return string event "done", or "test" when the arena test's final halt is done
local function finish(routine, course, rng)
    local task = routine.task
    routine.mult = math.min(routine.mult + 1, EqTraining.ROUTINE_MAX)
    routine.lastDone = task.kind
    if task.kind == "go" then
        routine.from = task.marker
        local hx, hz = task.marker.x - (task.startX or task.marker.x), task.marker.z - (task.startZ or task.marker.z)
        local length = math.sqrt(hx * hx + hz * hz)
        if length > 0.5 then routine.heading = { x = hx / length, z = hz / length } end
    end
    local nextTask = routine.preview or EqDressage.plan(routine, course, task.kind, rng)
    if task.kind == "halt" or task.kind == "turn" then
        -- Stand a moment before the next command.
        routine.task, routine.request, routine.pending, routine.driftMs = { kind = "hold" }, nil, nextTask, 0
        local hold = EqDressage.HOLD_MS
        routine.holdUntil = routine.clock + hold[1] + (rng(math.floor((hold[2] - hold[1]) / 500) + 1) - 1) * 500
        routine.preview = nil
    else
        begin(routine, nextTask, course)
    end
    return "done"
end


--- A mistake: a fault, the multiplier down FAULT_DROP steps and a fresh leg from here; the
--- FAULTS-th ends the routine.
--- @return string event "fault" or "lost"
local function fault(sheet, course, rng)
    local routine = sheet.routine
    routine.faults = (routine.faults or 0) + 1
    if routine.faults >= EqDressage.FAULTS then
        EqTraining.breakRoutine(sheet)
        return "lost"
    end
    routine.mult = math.max(1, routine.mult - EqDressage.FAULT_DROP)
    routine.from = nil
    local nextTask = EqDressage.planLeg(routine, course, rng)
    routine.pending = nil
    begin(routine, nextTask, course)
    return "fault"
end


--- One frame of the routine on a course.
--- @param sheet table
--- @param move string walk, trot, canter, gallop, halt or reverse
--- @param steer string|nil left or right while a steering key is held
--- @param dt number milliseconds
--- @param rng function
--- @param course table { x, z, markers } the horse's position and the course
--- @return string|nil event "request", "done", "bonus", "fault", "lost", "test" (a test of figures
---     ridden to the end) or nil
function EqDressage.step(sheet, move, steer, dt, rng, course)
    local routine = sheet.routine
    if routine.kind == "path" and routine.path ~= nil then return pathStep(sheet, move, dt, course) end
    local task = routine.task
    if task == nil then
        return EqTraining.breakRoutine(sheet) and "lost" or nil
    end
    routine.taskMs = (routine.taskMs or 0) + dt

    if task.kind == "hold" then
        if move ~= "halt" then
            routine.driftMs = routine.driftMs + dt
            if routine.driftMs >= EqDressage.DRIFT_MS then return fault(sheet, course, rng) end
        else
            routine.driftMs = 0
        end
        if routine.clock >= routine.holdUntil then
            begin(routine, routine.pending, course)
            routine.pending = nil
            return "request"
        end
        return nil
    end

    if task.kind == "go" then
        local d = distance(course.x, course.z, task.marker.x, task.marker.z)
        local gait = routine.bonus ~= nil and routine.bonus.gait or task.gait
        if d <= EqDressage.ARRIVE_RADIUS[task.gait] then return finish(routine, course, rng) end
        if routine.preview == nil and d <= math.max(EqDressage.PREVIEW_MIN, EqDressage.GO_SPEED[task.gait] * EqDressage.PREVIEW_SECONDS) then
            -- Plan the next command from the marker, not from here.
            local at = { x = task.marker.x, z = task.marker.z, markers = course.markers }
            local was = routine.from
            routine.from = task.marker
            routine.preview = EqDressage.plan(routine, at, "go", rng)
            routine.from = was
        end

        local event = nil
        if routine.bonus ~= nil then
            if move == routine.bonus.gait then
                -- The rest of the leg is at the new gait, with the time that needs.
                task.gait = routine.bonus.gait
                routine.bonus = nil
                routine.mult = math.min(routine.mult + 1, EqTraining.ROUTINE_MAX)
                local need = EqDressage.legMs(routine, task.gait, d)
                if routine.clock + need > routine.deadline then
                    routine.reactMs = routine.reactMs + (routine.clock + need - routine.deadline)
                    routine.deadline = routine.clock + need
                end
                routine.driftMs = 0
                event = "bonus"
            elseif routine.clock > routine.bonus.deadline then
                routine.bonus = nil
            end
        elseif routine.preview == nil then
            for _, marker in ipairs(course.markers) do
                if not same(marker, task.marker) and not same(marker, routine.from)
                    and distance(course.x, course.z, marker.x, marker.z) <= EqDressage.PASS_RADIUS then
                    local key = string.format("%.1f:%.1f", marker.x, marker.z)
                    if not routine.passed[key] then
                        routine.passed[key] = true
                        -- A change only to a gait the rest of the leg has room for: no long walks.
                        local options = {}
                        for _, other in ipairs(EqDressage.GO_GAITS) do
                            local most = EqDressage.GO_MAX_DISTANCE[other]
                            if other ~= task.gait and d >= EqDressage.GO_MIN_DISTANCE[other] and (most == nil or d <= most) then
                                table.insert(options, { other, EqDressage.GO_WEIGHTS[other] })
                            end
                        end
                        if #options > 0 and rng(100) <= EqDressage.PASS_CHANCE then
                            routine.bonus = { gait = pick(options, rng), from = task.gait, deadline = routine.clock + EqDressage.PASS_REACT_MS,
                                letter = marker.letter }
                            event = "request"
                        end
                    end
                end
            end
        end

        -- Settling in, a quick change on the way, or the last stretch to the marker: any gait
        -- short of a gallop. Otherwise the leg's gait.
        local free = routine.taskMs < EqDressage.REACT_MS or routine.bonus ~= nil or routine.preview ~= nil
        -- A gallop is never asked for.
        local galloping = move == "gallop" or (move == "fast" and gait ~= "canter")
        if move == gait or (free and not galloping) or (move == "fast" and gait == "canter") then
            routine.driftMs = 0
        else
            routine.driftMs = routine.driftMs + dt
            if routine.driftMs >= EqDressage.DRIFT_MS then return fault(sheet, course, rng) end
        end
        if routine.clock > routine.deadline then return fault(sheet, course, rng) end
        return event
    end

    local done = false
    if task.kind == "halt" then
        done = move == "halt"
    elseif task.kind == "turn" then
        routine.steerMs = steer == task.side and (move == "halt" or move == "walk") and routine.steerMs + dt or 0
        done = routine.steerMs >= EqDressage.TURN_MS
    elseif task.kind == "circle" then
        -- How far round the horse has come, from where it goes, while steering that way.
        if move == "canter" or move == "gallop" or move == "fast" then
            routine.driftMs = routine.driftMs + dt
            if routine.driftMs >= EqDressage.DRIFT_MS then return fault(sheet, course, rng) end
        else
            routine.driftMs = 0
        end
        if task.lastX == nil then
            task.lastX, task.lastZ = course.x, course.z
        else
            local dx, dz = course.x - task.lastX, course.z - task.lastZ
            if dx * dx + dz * dz >= 0.04 then
                local dir = math.atan2(dx, dz)
                if task.lastDir ~= nil and steer == task.side then
                    local delta = (dir - task.lastDir + math.pi) % (2 * math.pi) - math.pi
                    task.turned = (task.turned or 0) + math.abs(delta)
                end
                task.lastDir, task.lastX, task.lastZ = dir, course.x, course.z
            end
        end
        done = (task.turned or 0) >= EqDressage.CIRCLE_TURN
    elseif task.kind == "reverse" then
        if move == "reverse" then
            task.backMs = (task.backMs or 0) + dt
            -- Started in time: the clock now runs for the backing up itself.
            routine.deadline = math.max(routine.deadline, routine.clock + 1000)
        end
        done = (task.backMs or 0) >= EqDressage.REVERSE_MS
    end
    if done then return finish(routine, course, rng) end
    if routine.clock > routine.deadline then return fault(sheet, course, rng) end
    return nil
end

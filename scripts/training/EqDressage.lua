--[[
    EqDressage.lua
    The temperament routine ridden round dressage markers: pure functions with no game calls, so
    they run headless. EqTrainingHooks finds the markers (Riding Hall 2k26's letter boards) and
    passes them in as a course; without one the routine falls back to EqTraining's free routine,
    which trains less (EqTraining.FREE_ROUTINE_SHARE).

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
-- A gait is only asked for on a leg at least this long, and picked by these weights.
EqDressage.GO_MIN_DISTANCE = { walk = 0, trot = 10, canter = 18 }
EqDressage.GO_WEIGHTS = { walk = 3, trot = 4, canter = 3 }
EqDressage.GO_GAITS = { "walk", "trot", "canter" }
-- Targets nearer than this are only picked when there is nothing further.
EqDressage.MIN_TARGET_DISTANCE = 8
-- How close counts as at a marker, by gait.
EqDressage.ARRIVE_RADIUS = { walk = 3, trot = 3.5, canter = 4.5 }
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
EqDressage.AT_MARKER = { { "go", 70 }, { "halt", 22 }, { "reverse", 8 } }
EqDressage.AFTER_HALT = { { "go", 60 }, { "turn", 40 } }
-- Stand this long after a halt is done before the next command (a random time in the range).
EqDressage.HOLD_MS = { 1500, 3000 }
-- Back up for this long, then halt.
EqDressage.REVERSE_MS = 2500
-- A turn on the spot counts once its steering key is held this long.
EqDressage.TURN_MS = 600


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
    return EqDressage.GO_EXTRA_MS + metres / EqDressage.GO_SPEED[gait] * slack * 1000
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
        if chosen[2] >= EqDressage.GO_MIN_DISTANCE[gait] then table.insert(gaits, { gait, EqDressage.GO_WEIGHTS[gait] }) end
    end
    local marker = chosen[1]
    return { kind = "go", gait = pick(gaits, rng), marker = { letter = marker.letter, x = marker.x, z = marker.z } }
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
        kind = pick(EqDressage.AT_MARKER, rng)
    elseif done == "halt" and not routine.afterReverse then
        kind = pick(EqDressage.AFTER_HALT, rng)
    elseif done == "reverse" then
        kind = "halt"
    end
    if kind == "go" then return EqDressage.planLeg(routine, course, rng) end
    if kind == "turn" then return { kind = "turn", side = rng(2) == 1 and "left" or "right" } end
    return { kind = kind }
end


--- The name a task shows by: go, halt, reverse, spinLeft or spinRight (eq_move_<name>).
--- @param task table|nil
--- @return string|nil
function EqDressage.requestName(task)
    if task == nil then return nil end
    if task.kind == "turn" then return task.side == "left" and "spinLeft" or "spinRight" end
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
        routine.reactMs = EqDressage.legMs(routine, task.gait, distance(course.x, course.z, task.marker.x, task.marker.z))
    else
        routine.reactMs = EqDressage.REACT_MS
    end
    routine.deadline = routine.clock + routine.reactMs
    routine.shown, routine.shownUntil = routine.request, routine.clock + 1500
end


--- Start the routine on a course: the first leg is asked for at once.
--- @param routine table
--- @param course table
--- @param rng function
function EqDressage.start(routine, course, rng)
    routine.kind, routine.from, routine.lastDone = "markers", nil, nil
    begin(routine, EqDressage.planLeg(routine, course, rng), course)
end


--- One step done: raise the multiplier and move on.
--- @return string event "done"
local function finish(routine, course, rng)
    local task = routine.task
    routine.mult = math.min(routine.mult + 1, EqTraining.ROUTINE_MAX)
    routine.lastDone = task.kind
    if task.kind == "go" then routine.from = task.marker end
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


--- One frame of the routine on a course.
--- @param sheet table
--- @param move string walk, trot, canter, gallop, halt or reverse
--- @param steer string|nil left or right while a steering key is held
--- @param dt number milliseconds
--- @param rng function
--- @param course table { x, z, markers } the horse's position and the course
--- @return string|nil event "request", "done", "bonus", "lost" or nil
function EqDressage.step(sheet, move, steer, dt, rng, course)
    local routine = sheet.routine
    local task = routine.task
    if move == "gallop" or move == "fast" or task == nil then
        return EqTraining.breakRoutine(sheet) and "lost" or nil
    end
    routine.taskMs = (routine.taskMs or 0) + dt

    if task.kind == "hold" then
        if move ~= "halt" then
            routine.driftMs = routine.driftMs + dt
            if routine.driftMs >= EqDressage.DRIFT_MS then
                EqTraining.breakRoutine(sheet)
                return "lost"
            end
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
                        if rng(100) <= EqDressage.PASS_CHANCE then
                            local options = {}
                            for _, other in ipairs(EqDressage.GO_GAITS) do
                                if other ~= task.gait then table.insert(options, other) end
                            end
                            routine.bonus = { gait = options[rng(#options)], deadline = routine.clock + EqDressage.PASS_REACT_MS,
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
        if free or move == gait then
            routine.driftMs = 0
        else
            routine.driftMs = routine.driftMs + dt
            if routine.driftMs >= EqDressage.DRIFT_MS then
                EqTraining.breakRoutine(sheet)
                return "lost"
            end
        end
        if routine.clock > routine.deadline then
            EqTraining.breakRoutine(sheet)
            return "lost"
        end
        return event
    end

    local done = false
    if task.kind == "halt" then
        done = move == "halt"
    elseif task.kind == "turn" then
        routine.steerMs = steer == task.side and (move == "halt" or move == "walk") and routine.steerMs + dt or 0
        done = routine.steerMs >= EqDressage.TURN_MS
    elseif task.kind == "reverse" then
        if move == "reverse" then
            task.backMs = (task.backMs or 0) + dt
            -- Started in time: the clock now runs for the backing up itself.
            routine.deadline = math.max(routine.deadline, routine.clock + 1000)
        end
        done = (task.backMs or 0) >= EqDressage.REVERSE_MS
    end
    if done then return finish(routine, course, rng) end
    if routine.clock > routine.deadline then
        EqTraining.breakRoutine(sheet)
        return "lost"
    end
    return nil
end

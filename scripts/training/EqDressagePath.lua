--[[
    EqDressagePath.lua
    The dressage test in our arenas (James, 2026-10-29): a chain of figures drawn on the ground,
    scored on how closely the horse follows the line and how well it times its gait changes and
    halts. Pure functions with no game calls, so they run headless.

    The arena: local metres with X at 0, 0, y up the centre line from A (negative) to C, and x to
    the rider's right while riding from A to C, so a positive turn is a left turn. The track runs
    TRACK_INSET inside the rail with rounded corners.

    Figures (a 20 m circle at A, a 10 m volte at B, change rein F-X-H, a serpentine...) are
    built once for one end and one side and mirrored four ways. Each starts and ends on the
    track, so they chain: the next figure must start on the rein the last one ended on, and the
    track between ("go large") joins them. A test opens down the centre line from A with a halt
    at X, rides its figures, and ends down the centre line from A to a halt at X.

    Gait changes and halts sit at letters and at set points in a figure (X on a diagonal, half
    way round a circle). They show only a few metres before they come: more for a horse with
    better temperament, which also sees more of the line ahead and gets a wider timing window.

    Each movement (a figure with the track before it) is marked 0 to 10 like a real test: how far
    off the line the horse rode, time at the wrong gait, late or early changes and halts, and
    errors of course (lost the line, out of the arena or stopped). The test's mark is the sum as
    a percentage. Three errors eliminate.

    Part of Realistic Equestrian by Jasta007.
]]

EqDressagePath = {}

-- Metres between the points of a path.
EqDressagePath.STEP = 0.5
-- The track: this far inside the rail, corners of this radius (CORNER_SMALL in the 15 m arena).
EqDressagePath.TRACK_INSET = 1.5
EqDressagePath.CORNER = 4
EqDressagePath.CORNER_SMALL = 3.5
-- Letters stand this far outside the rail (art/source/dressage_arenas.py MARKER_GAP).
EqDressagePath.MARKER_GAP = 0.6
-- Turns down the centre line (radius), and how wide a "20 m" circle may be (radius).
EqDressagePath.CENTRE_TURN = 4
EqDressagePath.BIG_CIRCLE = 10
EqDressagePath.VOLTE = 5
-- The base game turns a ridden horse on about 3.5 m (log, 2026-10-27): nothing tighter.
EqDressagePath.MIN_RADIUS = 3.5
-- The test starts this far outside A, and the rider begins within START_RADIUS of it.
EqDressagePath.START_OUT = 2.5
EqDressagePath.START_RADIUS = 3.5
-- Figures in a test: training, and a hosted event's (EqDressagePath.figuresFor).
EqDressagePath.TRAINING_FIGURES = 5
-- The track between figures: at least this long, and preferably no longer than CONNECT_GOOD.
EqDressagePath.CONNECT_MIN = 3
EqDressagePath.CONNECT_GOOD = 30
-- Gaits each figure may be ridden at (weights).
EqDressagePath.GAITS = { "walk", "trot", "canter" }
-- Chances in 100: a change on the track before a figure, one inside it, a halt at X on a
-- centre line.
EqDressagePath.CHANGE_TRACK = 35
EqDressagePath.CHANGE_INSIDE = 45
EqDressagePath.HALT_CHANCE = 30
-- Changes this far apart at least; a walk no longer than WALK_MAX (long walks are dull, James).
EqDressagePath.CHANGE_GAP = 8
EqDressagePath.WALK_MAX = 30
-- After a halt: stand this long, then go on at this gait.
EqDressagePath.HOLD_MS = 2500
EqDressagePath.PROCEED = "trot"

-- What the horse's temperament (0..100) buys: metres of line shown ahead, metres of warning
-- before a change or halt, and metres either side of it that count as on time.
EqDressagePath.LOOK = { 8, 30 }
EqDressagePath.WARN = { 3, 12 }
EqDressagePath.TOLERANCE = { 1.5, 3.5 }

-- Following the line: searched this far back, and ahead by what the horse moved plus this.
EqDressagePath.SEARCH_BACK = 2
EqDressagePath.SEARCH_AHEAD = 2
-- Back on the line further ahead after cutting a corner: within REJOIN_DIST of a point up to
-- REJOIN_AHEAD on, once more than REJOIN_FROM off; the cut counts as SKIP_DEV off the line.
EqDressagePath.REJOIN_FROM = 2.5
EqDressagePath.REJOIN_DIST = 1
EqDressagePath.REJOIN_AHEAD = 15
EqDressagePath.SKIP_DEV = 3

-- Marks. Off the line: nothing for the first DEV_FREE metres on average, then DEV_PER_M a metre.
EqDressagePath.DEV_FREE = 0.3
EqDressagePath.DEV_PER_M = 3
-- At the wrong gait: this much a second, at most WRONG_MAX a movement.
EqDressagePath.WRONG_PER_S = 0.5
EqDressagePath.WRONG_MAX = 5
-- A change out of its window: this much a metre beyond it, at most CHANGE_MAX (also a missed one).
EqDressagePath.CHANGE_PER_M = 0.6
EqDressagePath.CHANGE_MAX = 3
-- A change counts within WARN metres before its point; missed MISS metres after it.
EqDressagePath.MISS = 10
-- A halt: free within HALT_FREE metres of its point, then HALT_PER_M a metre, at most HALT_MAX;
-- moving off before the hold is over costs HALT_MOVED; riding through it HALT_MISSED.
EqDressagePath.HALT_FREE = 1
EqDressagePath.HALT_PER_M = 1
EqDressagePath.HALT_MAX = 3
EqDressagePath.HALT_MOVED = 1
EqDressagePath.HALT_MISSED = 4
EqDressagePath.HALT_PASS = 5
-- Errors of course: further than LOST_DEV off the line for LOST_MS, out of the arena for OUT_MS
-- (OUT_MARGIN past the rail), or no headway for STALL_MS. Each costs ERROR_PEN on the movement;
-- ERRORS eliminate. The line then picks up at the nearest point up to SNAP_AHEAD on.
EqDressagePath.LOST_DEV = 6
EqDressagePath.LOST_MS = 4000
EqDressagePath.OUT_MARGIN = 0.5
EqDressagePath.OUT_MS = 3000
EqDressagePath.STALL_MS = 10000
EqDressagePath.ERROR_PEN = 3
EqDressagePath.ERRORS = 3
EqDressagePath.SNAP_AHEAD = 40
-- The training multiplier after a movement: up at MULT_UP or better, down below MULT_DOWN.
EqDressagePath.MULT_UP = 6.5
EqDressagePath.MULT_DOWN = 4
-- The test's payoff share: full at PAYOFF_FULL percent, PAYOFF_MIN of it at PAYOFF_ZERO or less.
EqDressagePath.PAYOFF_ZERO = 40
EqDressagePath.PAYOFF_FULL = 70
EqDressagePath.PAYOFF_MIN = 0.2


-- GEOMETRY --------------------------------------------------------------------------------

--- A pen that draws a path as it moves: a point every STEP metres.
local function newPen(x, y, hx, hy)
    return { x = x, y = y, hx = hx, hy = hy, pts = { { x = x, y = y } } }
end


local function put(pen, x, y)
    pen.x, pen.y = x, y
    table.insert(pen.pts, { x = x, y = y })
end


--- Straight on for d metres.
local function forward(pen, d)
    if d <= 0.001 then return end
    local n = math.max(1, math.ceil(d / EqDressagePath.STEP))
    local x0, y0 = pen.x, pen.y
    for i = 1, n do put(pen, x0 + pen.hx * d * i / n, y0 + pen.hy * d * i / n) end
end


--- Straight to a point, facing it.
local function lineTo(pen, x, y)
    local dx, dy = x - pen.x, y - pen.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= 0.001 then return end
    pen.hx, pen.hy = dx / d, dy / d
    forward(pen, d)
end


--- Round an arc of radius r through angle (radians, positive turns left).
local function arc(pen, r, angle)
    if math.abs(angle) < 0.0001 then return end
    local side = angle > 0 and 1 or -1
    local cx, cy = pen.x - pen.hy * r * side, pen.y + pen.hx * r * side
    local sx, sy = pen.x - cx, pen.y - cy
    local n = math.max(1, math.ceil(r * math.abs(angle) / EqDressagePath.STEP))
    for i = 1, n do
        local a = angle * i / n
        local c, s = math.cos(a), math.sin(a)
        put(pen, cx + sx * c - sy * s, cy + sx * s + sy * c)
    end
    local c, s = math.cos(angle), math.sin(angle)
    pen.hx, pen.hy = pen.hx * c - pen.hy * s, pen.hx * s + pen.hy * c
end


--- Round an arc until done(pen) says stop, at least minAngle and at most 2 pi.
--- @param side number 1 left, -1 right
local function arcUntil(pen, r, side, minAngle, done)
    local step = EqDressagePath.STEP / 4 / r
    local turned = 0
    while turned < math.pi * 2 do
        arc(pen, r, step * side)
        turned = turned + step
        if turned >= minAngle and done(pen) then return true end
    end
    return false
end


--- @return function done when the pen faces the point (within half a step's turn)
local function facing(tx, ty)
    return function(pen)
        local dx, dy = tx - pen.x, ty - pen.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 0.001 then return true end
        local cross = pen.hx * dy / d - pen.hy * dx / d
        local dot = pen.hx * dx / d + pen.hy * dy / d
        return dot > 0 and math.abs(cross) < 0.02
    end
end


--- @return function done when the pen heads (hx, hy)
local function heading(hx, hy)
    return function(pen)
        return pen.hx * hx + pen.hy * hy > 0 and math.abs(pen.hx * hy - pen.hy * hx) < 0.02
    end
end


--- Through the corners of a line of points, each rounded with radius r (less where the legs
--- are too short for it). The pen should already face the first point.
local function rounded(pen, points, r)
    local all = { { x = pen.x, y = pen.y } }
    for _, p in ipairs(points) do table.insert(all, p) end
    -- The first leg is all the pen's; inner legs are shared by two corners.
    for i = 2, #all - 1 do
        local a, b, c = all[i - 1], all[i], all[i + 1]
        local ax, ay = b.x - a.x, b.y - a.y
        local bx, by = c.x - b.x, c.y - b.y
        local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
        ax, ay, bx, by = ax / la, ay / la, bx / lb, by / lb
        local turn = math.atan2(ax * by - ay * bx, ax * bx + ay * by)
        local half = math.tan(math.abs(turn) / 2)
        local roomIn = i == 2 and la or la / 2
        local roomOut = i == #all - 1 and lb or lb / 2
        local radius = half > 0.0001 and math.min(r, roomIn / half, roomOut / half) or r
        local t = radius * half
        lineTo(pen, b.x - ax * t, b.y - ay * t)
        pen.hx, pen.hy = ax, ay
        arc(pen, radius, turn)
    end
    local last = all[#all]
    lineTo(pen, last.x, last.y)
end


--- The track: a rounded rectangle, from A anticlockwise (to the right first, then up to C).
--- @param g table geometry { wt, lt, rc }
--- @return table points { x, y, s }, and the loop's length
local function trackPoints(g)
    local pen = newPen(0, -g.lt, 1, 0)
    forward(pen, g.wt - g.rc)
    arc(pen, g.rc, math.pi / 2)
    forward(pen, 2 * g.lt - 2 * g.rc)
    arc(pen, g.rc, math.pi / 2)
    forward(pen, 2 * g.wt - 2 * g.rc)
    arc(pen, g.rc, math.pi / 2)
    forward(pen, 2 * g.lt - 2 * g.rc)
    arc(pen, g.rc, math.pi / 2)
    forward(pen, g.wt - g.rc)
    local pts = pen.pts
    table.remove(pts)
    local s = 0
    for i, p in ipairs(pts) do
        if i > 1 then s = s + math.sqrt((p.x - pts[i - 1].x) ^ 2 + (p.y - pts[i - 1].y) ^ 2) end
        p.s = s
    end
    local length = s + math.sqrt((pts[1].x - pts[#pts].x) ^ 2 + (pts[1].y - pts[#pts].y) ^ 2)
    return pts, length
end


--- @return number index of the nearest track point, and how far it is
local function onTrack(track, x, y)
    local best, bestD = 1, math.huge
    for i, p in ipairs(track) do
        local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
        if d < bestD then best, bestD = i, d end
    end
    return best, math.sqrt(bestD)
end


--- @return number 1 when heading (hx, hy) at track point i runs anticlockwise, -1 clockwise
local function reinAt(track, i, hx, hy)
    local n = #track
    local a, b = track[(i - 2) % n + 1], track[i % n + 1]
    return (b.x - a.x) * hx + (b.y - a.y) * hy >= 0 and 1 or -1
end


-- THE ARENA --------------------------------------------------------------------------------

--- The arena an X marker belongs to, in local metres.
--- @param markers table the course's markers { letter, x, z, arena, arenaId }
--- @param x table the arena's X marker
--- @return table|nil frame { cx, cz, ux, uz, vx, vz, halfL, halfW, letters = { { letter, x, y } } }
function EqDressagePath.frameFor(markers, x)
    local a, c
    local function near(m, best) return best == nil or (m.x - x.x) ^ 2 + (m.z - x.z) ^ 2 < (best.x - x.x) ^ 2 + (best.z - x.z) ^ 2 end
    for _, marker in ipairs(markers) do
        if marker.arena and marker.arenaId == x.arenaId then
            if marker.letter == "A" and near(marker, a) then a = marker end
            if marker.letter == "C" and near(marker, c) then c = marker end
        end
    end
    if a == nil or c == nil then return nil end
    local length = math.sqrt((c.x - a.x) ^ 2 + (c.z - a.z) ^ 2)
    if length < 10 then return nil end
    local ux, uz = (c.x - a.x) / length, (c.z - a.z) / length
    -- The rider's right facing (ux, uz) in the game's world (y up): (-uz, ux).
    local frame = { cx = (a.x + c.x) / 2, cz = (a.z + c.z) / 2, ux = ux, uz = uz, vx = -uz, vz = ux,
        halfL = length / 2 - EqDressagePath.MARKER_GAP, halfW = 0, letters = {}, arenaId = x.arenaId }
    for _, marker in ipairs(markers) do
        if marker.arena and marker.arenaId == x.arenaId then
            local lx, ly = EqDressagePath.toLocal(frame, marker.x, marker.z)
            table.insert(frame.letters, { letter = marker.letter, x = lx, y = ly })
            if math.abs(lx) <= length then frame.halfW = math.max(frame.halfW, math.abs(lx)) end
        end
    end
    frame.halfW = frame.halfW - EqDressagePath.MARKER_GAP
    if frame.halfW < 5 then return nil end
    return frame
end


--- @return number x, number y local metres of a world point
function EqDressagePath.toLocal(frame, wx, wz)
    local dx, dz = wx - frame.cx, wz - frame.cz
    return dx * frame.vx + dz * frame.vz, dx * frame.ux + dz * frame.uz
end


--- @return number wx, number wz the world point of local metres
function EqDressagePath.toWorld(frame, x, y)
    return frame.cx + x * frame.vx + y * frame.ux, frame.cz + x * frame.vz + y * frame.uz
end


--- @return string the letter nearest a local point
local function letterAt(frame, x, y)
    local best, bestD = "?", math.huge
    for _, l in ipairs(frame.letters) do
        local d = (l.x - x) ^ 2 + (l.y - y) ^ 2
        if d < bestD then best, bestD = l.letter, d end
    end
    return best
end


--- The geometry figures are built from.
local function geometry(frame)
    local g = { wt = frame.halfW - EqDressagePath.TRACK_INSET, lt = frame.halfL - EqDressagePath.TRACK_INSET }
    g.rc = frame.halfW >= 9 and EqDressagePath.CORNER or EqDressagePath.CORNER_SMALL
    -- The side letters on the right, from A up (K/F first).
    g.sides = {}
    for _, l in ipairs(frame.letters) do
        if l.x > frame.halfW * 0.5 then table.insert(g.sides, l.y) end
    end
    table.sort(g.sides)
    g.straight = g.lt - g.rc
    return g
end


-- FIGURES ------------------------------------------------------------------------------------
-- Each builder returns figures for the right side, A end: { key, pts, labels = { local points
-- named by their letters }, marks = { point indices where a change may come }, gaits, turn =
-- 1 or -1 when the name says left or right }.

local FIGURES = {}


--- A big circle's name: as wide as the arena when it touches the track on both sides (a "20 m
--- circle" rides on the track, inside the rail), else its own size.
local function bigSize(g, r)
    return r >= g.wt - 0.01 and 2 * (r + EqDressagePath.TRACK_INSET) or 2 * r
end


--- A circle from A, as big as the arena allows (up to 20 m).
FIGURES.circleEnd = function(g)
    local r = math.min(EqDressagePath.BIG_CIRCLE, g.wt)
    local pen = newPen(0, -g.lt, 1, 0)
    arc(pen, r, math.pi * 2)
    return { { key = "circle", size = bigSize(g, r), pts = pen.pts, labels = { { 0, -g.lt } },
        marks = { 1, math.floor(#pen.pts / 2) }, gaits = { trot = 6, canter = 4 } } }
end


--- A circle from the middle letter (E or B), as wide as the arena.
FIGURES.circleMid = function(g)
    local r = math.min(EqDressagePath.BIG_CIRCLE, g.wt)
    if r > g.straight then return {} end
    local pen = newPen(g.wt, 0, 0, 1)
    arc(pen, r, math.pi * 2)
    return { { key = "circle", size = bigSize(g, r), pts = pen.pts, labels = { { g.wt, 0 } },
        marks = { 1, math.floor(#pen.pts / 2) }, gaits = { trot = 6, canter = 4 } } }
end


--- A 10 m volte at any side letter it fits at.
FIGURES.volte = function(g)
    local r, list = EqDressagePath.VOLTE, {}
    if 2 * r > 2 * g.wt then return list end
    for _, y in ipairs(g.sides) do
        if math.abs(y) <= g.straight then
            local pen = newPen(g.wt, y, 0, 1)
            arc(pen, r, math.pi * 2)
            table.insert(list, { key = "circle", size = r * 2, pts = pen.pts, labels = { { g.wt, y } }, marks = { 1 },
                gaits = { walk = 2, trot = 6 } })
        end
    end
    return list
end


--- Change rein on the long diagonal, F-X-H, or the short one, F-E.
FIGURES.diagonals = function(g)
    local first, last = g.sides[1], g.sides[#g.sides]
    if first == nil then return {} end
    local fromY = math.max(first, -g.straight + 1.5)
    local list = {}
    local function diagonal(toY, key, gaits)
        local pen = newPen(g.wt, -g.straight, 0, 1)
        local endY = math.min(toY + 5, g.straight)
        rounded(pen, { { x = g.wt, y = fromY }, { x = -g.wt, y = math.min(toY, endY - 1.5) }, { x = -g.wt, y = endY } }, g.rc)
        -- The middle of the diagonal (X on the long one) is a natural place for a change.
        local mid, bestD = 1, math.huge
        local midY = (fromY + toY) / 2
        for i, p in ipairs(pen.pts) do
            local d = math.abs(p.x) + math.abs(p.y - midY)
            if d < bestD then mid, bestD = i, d end
        end
        table.insert(list, { key = key, pts = pen.pts, labels = { { g.wt, first }, { -g.wt, toY } }, marks = { 1, mid }, gaits = gaits })
    end
    diagonal(last, "longDiagonal", { walk = 3, trot = 5, canter = 3 })
    diagonal(0, "shortDiagonal", { trot = 5, canter = 3 })
    return list
end


--- A half volte: half a 10 m circle in from a side letter, back to the track on a slant.
FIGURES.halfVolte = function(g)
    local r, list = EqDressagePath.VOLTE, {}
    if 2 * r > 2 * g.wt then return list end
    for _, y in ipairs(g.sides) do
        local back = y - 2 * r
        if y + r <= g.lt and y <= g.straight and back - 4 >= -g.straight then
            local pen = newPen(g.wt, y, 0, 1)
            arcUntil(pen, r, 1, math.pi * 0.75, facing(g.wt, back))
            rounded(pen, { { x = g.wt, y = back }, { x = g.wt, y = back - 4 } }, g.rc)
            table.insert(list, { key = "halfVolte", pts = pen.pts, labels = { { g.wt, y } }, marks = { 1 },
                gaits = { walk = 2, trot = 5 } })
        end
    end
    return list
end


--- Across the arena from a side letter: turning back the same way (half school) or changing rein.
FIGURES.across = function(g)
    local list = {}
    for _, y in ipairs(g.sides) do
        if y - 4 >= -g.straight and y + 4 <= g.straight then
            for _, turn in ipairs({ 1, -1 }) do
                local pen = newPen(g.wt, y - 4, 0, 1)
                rounded(pen, { { x = g.wt, y = y }, { x = -g.wt, y = y }, { x = -g.wt, y = y - 4 * turn } }, g.rc)
                table.insert(list, { key = turn == 1 and "across" or "acrossChange", pts = pen.pts, labels = { { g.wt, y }, { -g.wt, y } },
                    marks = { 1 }, gaits = { walk = 2, trot = 5, canter = 2 } })
            end
        end
    end
    return list
end


--- Down the centre line from A, to track left or right at C.
--- @param opening boolean the test's opening: from outside A (its halt at X is the build's)
local function centreLine(g, frame, turn, opening)
    local a = math.max(math.min(EqDressagePath.CENTRE_TURN, g.wt - g.rc), 2.5)
    local pen
    if opening then
        pen = newPen(0, -frame.halfL - EqDressagePath.START_OUT, 0, 1)
    else
        pen = newPen(-a, -g.lt, 1, 0)
        arc(pen, a, math.pi / 2)
    end
    lineTo(pen, 0, 0)
    local x = #pen.pts
    lineTo(pen, 0, g.lt - a)
    arc(pen, a, math.pi / 2 * turn)
    return pen.pts, x
end


FIGURES.centre = function(g, frame)
    local list = {}
    for _, turn in ipairs({ 1, -1 }) do
        local pts, x = centreLine(g, frame, turn, false)
        table.insert(list, { key = "centre", turn = turn, pts = pts, labels = { { 0, -g.lt }, { 0, g.lt } }, marks = { x },
            haltAt = x, gaits = { walk = 1, trot = 5, canter = 2 } })
    end
    return list
end


--- A serpentine of n loops from A to C, each loop touching a long side.
FIGURES.serpentine = function(g)
    local list = {}
    for _, n in ipairs({ 3, 4, 5 }) do
        local h = 2 * g.lt / n
        local r = math.min(h / 2, g.wt, 6) - 0.01
        if r >= EqDressagePath.MIN_RADIUS then
            local points, side = {}, 1
            table.insert(points, { x = g.wt, y = -g.lt })
            for k = 1, n - 1 do
                local y = -g.lt + k * h
                table.insert(points, { x = g.wt * side, y = y })
                table.insert(points, { x = -g.wt * side, y = y })
                side = -side
            end
            table.insert(points, { x = g.wt * side, y = g.lt })
            table.insert(points, { x = 0, y = g.lt })
            local pen = newPen(0, -g.lt, 1, 0)
            rounded(pen, points, r)
            -- Changes where the loops cross the centre line.
            local marks = { 1 }
            for i = 2, #pen.pts do
                if (pen.pts[i - 1].x < 0) ~= (pen.pts[i].x < 0) and math.abs(pen.pts[i].y) < g.lt - 1 then table.insert(marks, i) end
            end
            table.insert(list, { key = "serpentine", loops = n, pts = pen.pts, labels = { { 0, -g.lt }, { 0, g.lt } }, marks = marks,
                gaits = { trot = 6, canter = 1 } })
        end
    end
    return list
end


--- A shallow loop in off the long side: K-E-H in by 5 m (3 m in a 15 m arena).
FIGURES.shallowLoop = function(g)
    local first, last = g.sides[1], g.sides[#g.sides]
    if first == nil or #g.sides < 3 then return {} end
    local depth = g.wt >= 8 and 5 or 3
    local fromY, toY = math.max(first, -g.straight + 1), math.min(last, g.straight - 1)
    local pen = newPen(g.wt, -g.straight, 0, 1)
    rounded(pen, { { x = g.wt, y = fromY }, { x = g.wt - depth, y = 0 }, { x = g.wt, y = toY }, { x = g.wt, y = g.straight } }, 10)
    local mid, bestD = 1, math.huge
    for i, p in ipairs(pen.pts) do
        if math.abs(p.y) < bestD then mid, bestD = i, math.abs(p.y) end
    end
    return { { key = "shallowLoop", size = depth, pts = pen.pts, labels = { { g.wt, first }, { g.wt, 0 }, { g.wt, last } }, marks = { 1, mid },
        gaits = { walk = 2, trot = 5, canter = 2 } } }
end


--- Change rein through the circle at A: half the circle, then an S through its middle.
FIGURES.throughCircle = function(g)
    local r = math.min(EqDressagePath.BIG_CIRCLE, g.wt)
    if r / 2 < EqDressagePath.MIN_RADIUS then return {} end
    local pen = newPen(0, -g.lt, 1, 0)
    arc(pen, r, math.pi)
    local s = #pen.pts
    arc(pen, r / 2, math.pi)
    local middle = #pen.pts
    arc(pen, r / 2, -math.pi)
    return { { key = "throughCircle", pts = pen.pts, labels = { { 0, -g.lt } }, marks = { 1, s, middle }, gaits = { trot = 6 } } }
end


--- A figure of eight: circles at both ends, crossing at X.
FIGURES.eight = function(g)
    local r = math.min(EqDressagePath.BIG_CIRCLE, g.wt)
    local c = g.lt - r
    if c < r then return {} end
    local pen = newPen(0, -g.lt, 1, 0)
    if not arcUntil(pen, r, 1, math.pi / 6, facing(0, 0)) then return {} end
    local x1 = #pen.pts
    local tx, ty = -pen.x, -pen.y
    lineTo(pen, 0, 0)
    local cross1 = #pen.pts
    lineTo(pen, tx, ty)
    if not arcUntil(pen, r, -1, math.pi / 2, facing(0, 0)) then return {} end
    tx, ty = -pen.x, -pen.y
    lineTo(pen, 0, 0)
    local cross2 = #pen.pts
    lineTo(pen, tx, ty)
    if not arcUntil(pen, r, 1, math.pi / 6, heading(1, 0)) then return {} end
    -- Back at A: square it up on the track.
    lineTo(pen, pen.x + 1, -g.lt)
    return { { key = "eight", pts = pen.pts, labels = { { 0, -g.lt } }, marks = { 1, x1, cross1, cross2 }, gaits = { trot = 6, canter = 2 } } }
end


EqDressagePath.FIGURE_ORDER = { "circleEnd", "circleMid", "volte", "diagonals", "halfVolte", "across", "centre", "serpentine",
    "shallowLoop", "throughCircle", "eight" }


--- Every figure for an arena, mirrored four ways, each with where it joins the track.
--- @param frame table from frameFor
--- @return table figures, table track, number trackLength, table g
function EqDressagePath.library(frame)
    local g = geometry(frame)
    local track, trackLength = trackPoints(g)
    local list = {}
    for _, name in ipairs(EqDressagePath.FIGURE_ORDER) do
        for _, figure in ipairs(FIGURES[name](g, frame)) do
            for _, mirror in ipairs({ { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
                local sx, sy = mirror[1], mirror[2]
                local pts = {}
                for i, p in ipairs(figure.pts) do pts[i] = { x = p.x * sx, y = p.y * sy } end
                local n = #pts
                local entry, entryD = onTrack(track, pts[1].x, pts[1].y)
                local exit, exitD = onTrack(track, pts[n].x, pts[n].y)
                if n >= 3 and entryD < 0.5 and exitD < 0.5 then
                    local labels = {}
                    for i, l in ipairs(figure.labels) do labels[i] = letterAt(frame, l[1] * sx, l[2] * sy) end
                    table.insert(list, {
                        key = figure.key, size = figure.size, loops = figure.loops, labels = labels,
                        turn = figure.turn ~= nil and figure.turn * sx * sy or nil,
                        pts = pts, marks = figure.marks, haltAt = figure.haltAt, gaits = figure.gaits,
                        entry = entry, entryRein = reinAt(track, entry, pts[2].x - pts[1].x, pts[2].y - pts[1].y),
                        exit = exit, exitRein = reinAt(track, exit, pts[n].x - pts[n - 1].x, pts[n].y - pts[n - 1].y),
                        fromA = pts[1].y < 0,
                    })
                end
            end
        end
    end
    return list, track, trackLength, g
end


-- BUILDING A TEST ----------------------------------------------------------------------------

--- @param list table { { name, weight }, ... }
--- @param rng function (n) -> 1..n
local function pick(list, rng)
    local total = 0
    for _, entry in ipairs(list) do total = total + entry[2] end
    if total <= 0 then return nil end
    local roll = rng(math.max(1, math.floor(total + 0.5)))
    for _, entry in ipairs(list) do
        roll = roll - entry[2]
        if roll <= 0 then return entry[1] end
    end
    return list[#list][1]
end


--- @param gaits table gait -> weight
--- @param except string|nil
local function pickGait(gaits, rng, except)
    local list = {}
    for _, gait in ipairs(EqDressagePath.GAITS) do
        if gaits[gait] ~= nil and gait ~= except then table.insert(list, { gait, gaits[gait] }) end
    end
    return pick(list, rng)
end


--- Add points to a test's path, all in movement m.
local function append(test, pts, m)
    local path = test.pts
    for _, p in ipairs(pts) do
        local last = path[#path]
        local d = last ~= nil and math.sqrt((p.x - last.x) ^ 2 + (p.y - last.y) ^ 2) or 0
        if last == nil or d > 0.05 then
            table.insert(path, { x = p.x, y = p.y, s = (last ~= nil and last.s or 0) + d, m = m })
        end
    end
end


--- The track from point i to point j going round in rein's direction (j itself left out).
local function trackRun(track, i, j, rein)
    local n, pts = #track, {}
    local k = i
    while k ~= j and #pts <= n do
        table.insert(pts, track[k])
        k = (k - 1 + rein) % n + 1
    end
    return pts
end


--- @return number metres from point i to point j round the track in rein's direction
local function trackDistance(track, length, i, j, rein)
    local d = (track[j].s - track[i].s) * rein
    if d < 0 then d = d + length end
    return d
end


--- The letters the track passes between two points: change points { index into pts, letter }.
local function trackLetters(frame, pts)
    local found = {}
    for _, l in ipairs(frame.letters) do
        -- Round the edge: the long sides' letters, and A and C (outside the rail's ends).
        local onSide = math.abs(l.x) > frame.halfW * 0.5 or math.abs(l.y) > frame.halfL
        if onSide then
            local best, bestD = nil, 2.5
            for i, p in ipairs(pts) do
                local d = math.sqrt((p.x - l.x) ^ 2 + (p.y - l.y) ^ 2) - EqDressagePath.TRACK_INSET - EqDressagePath.MARKER_GAP
                if d < bestD then best, bestD = i, d end
            end
            if best ~= nil then table.insert(found, { i = best, letter = l.letter }) end
        end
    end
    table.sort(found, function(a, b) return a.i < b.i end)
    return found
end


--- How many figures a test of a hosted event's length has (data/hosting.xml dressageMoves:
--- 15, 20, 25 make 6, 8, 10).
--- @param moves number|nil
--- @return number figures
function EqDressagePath.figuresFor(moves)
    if moves == nil then return EqDressagePath.TRAINING_FIGURES end
    return math.max(3, math.floor(moves * 0.4 + 0.5))
end


--- Build a test for an arena.
--- @param frame table from frameFor
--- @param figures number how many figures between the opening and the final centre line
--- @param rng function (n) -> 1..n; a seeded one rides the same test every time
--- @return table test { pts = { x, y, s, m }, moves = { s0, s1, key, ... }, events = { s, kind, gait, letter, m }, length, frame }
function EqDressagePath.build(frame, figures, rng)
    local library, track, trackLength, g = EqDressagePath.library(frame)
    local test = { pts = {}, moves = {}, events = {}, frame = frame, g = g }
    local events = test.events

    -- Changes: never closer than CHANGE_GAP to the last one, and walks kept short.
    local gait, lastChange, walkFrom = EqDressagePath.PROCEED, 0, nil
    local function change(s, newGait, letter, m)
        if newGait == gait or s < lastChange + EqDressagePath.CHANGE_GAP then return false end
        table.insert(events, { s = s, kind = "change", gait = newGait, letter = letter, m = m })
        gait, lastChange = newGait, s
        walkFrom = newGait == "walk" and s or nil
        return true
    end
    -- A walk longer than WALK_MAX before sLimit trots on where it reaches that.
    local function capWalk(sLimit, m)
        if walkFrom ~= nil and sLimit - walkFrom > EqDressagePath.WALK_MAX then
            change(walkFrom + EqDressagePath.WALK_MAX, "trot", nil, m)
        end
    end
    local function halt(s, letter, m, final)
        table.insert(events, { s = s, kind = "halt", gait = final and "halt" or EqDressagePath.PROCEED, letter = letter, m = m, final = final })
        gait, lastChange, walkFrom = EqDressagePath.PROCEED, s, nil
    end

    -- The opening: from outside A down the centre line, halt at X, track left or right at C.
    local turn = rng(2) == 1 and 1 or -1
    local opening, xIndex = centreLine(g, frame, turn, true)
    local enter = { s0 = 0, key = "enter", labels = { "A", "X" } }
    table.insert(test.moves, enter)
    for i = 1, xIndex do append(test, { opening[i] }, 1) end
    enter.s1 = test.pts[#test.pts].s
    halt(enter.s1, "X", 1, false)
    local proceed = { s0 = enter.s1, key = "proceed", turn = turn, labels = { "C" } }
    table.insert(test.moves, proceed)
    for i = xIndex + 1, #opening do append(test, { opening[i] }, 2) end
    proceed.s1 = test.pts[#test.pts].s
    local last = opening[#opening]
    local at = onTrack(track, last.x, last.y)
    local rein = reinAt(track, at, last.x - opening[#opening - 1].x, last.y - opening[#opening - 1].y)
    local lastKey = "centre"

    local function ride(figure, m)
        local move = test.moves[m]
        local run = trackRun(track, at, figure.entry, rein)
        local runStart = #test.pts
        append(test, run, m)
        local s0 = test.pts[runStart] ~= nil and test.pts[runStart].s or 0
        capWalk(test.pts[#test.pts].s, m)
        -- A change on the track first: at a letter it passes, or one it needs for the figure.
        local letters = trackLetters(frame, run)
        local need = figure.gaits[gait] == nil or (walkFrom ~= nil and s0 - walkFrom > EqDressagePath.WALK_MAX / 2)
        if (need or rng(100) <= EqDressagePath.CHANGE_TRACK) and #letters > 0 then
            local chosen = letters[need and #letters or rng(#letters)]
            local runPts = test.pts
            local idx = math.min(runStart + chosen.i, #runPts)
            local newGait = pickGait(figure.gaits, rng, gait)
            if newGait ~= nil then change(runPts[idx].s, newGait, chosen.letter, m) end
        end
        local figStart = #test.pts
        append(test, figure.pts, m)
        local function sAt(i) return test.pts[math.min(figStart + i - 1, #test.pts)].s end
        if figure.gaits[gait] == nil then
            -- Still at a gait the figure doesn't allow: change at its start, gap or not.
            lastChange = -math.huge
            change(sAt(1), pickGait(figure.gaits, rng), figure.labels[1], m)
        end
        if figure.haltAt ~= nil and gait ~= "canter" and rng(100) <= EqDressagePath.HALT_CHANCE then
            capWalk(sAt(figure.haltAt), m)
            halt(sAt(figure.haltAt), "X", m, false)
        elseif #figure.marks > 1 and rng(100) <= EqDressagePath.CHANGE_INSIDE then
            local mark = figure.marks[1 + rng(#figure.marks - 1)]
            capWalk(sAt(mark), m)
            local newGait = pickGait(figure.gaits, rng, gait)
            if newGait ~= nil then change(sAt(mark), newGait, nil, m) end
        end
        capWalk(sAt(#figure.pts), m)
        move.s1 = test.pts[#test.pts].s
        at, rein = figure.exit, figure.exitRein
    end

    for _ = 1, figures do
        local choices = {}
        for _, figure in ipairs(library) do
            if figure.entryRein == rein and figure.key ~= lastKey then
                local d = trackDistance(track, trackLength, at, figure.entry, rein)
                if d >= EqDressagePath.CONNECT_MIN and d <= trackLength * 0.6 then
                    table.insert(choices, { figure, d <= EqDressagePath.CONNECT_GOOD and 3 or 1 })
                end
            end
        end
        local figure = pick(choices, rng)
        if figure == nil then break end
        local m = #test.moves + 1
        table.insert(test.moves, { s0 = test.pts[#test.pts].s, key = figure.key, size = figure.size, loops = figure.loops,
            turn = figure.turn, labels = figure.labels })
        ride(figure, m)
        lastKey = figure.key
    end

    -- The finish: down the centre line from A, halt at X (the path goes on a little past it).
    local final
    for _, figure in ipairs(library) do
        if figure.key == "centre" and figure.fromA and figure.entryRein == rein then
            final = figure
            break
        end
    end
    local m = #test.moves + 1
    table.insert(test.moves, { s0 = test.pts[#test.pts].s, key = "final", labels = { "A", "X" } })
    local run = trackRun(track, at, final.entry, rein)
    capWalk(test.pts[#test.pts].s + trackDistance(track, trackLength, at, final.entry, rein), m)
    if #run > 0 and gait == "canter" then
        local letters = trackLetters(frame, run)
        local before = #test.pts
        append(test, run, m)
        if #letters > 0 then change(test.pts[math.min(before + letters[#letters].i, #test.pts)].s, "trot", letters[#letters].letter, m) end
    else
        append(test, run, m)
    end
    local figStart = #test.pts
    for i = 1, math.min(final.haltAt + 16, #final.pts) do append(test, { final.pts[i] }, m) end
    local xs = test.pts[math.min(figStart + final.haltAt - 1, #test.pts)].s
    if gait ~= EqDressagePath.PROCEED then
        lastChange = -math.huge
        change(math.max(test.pts[figStart].s, xs - 15), EqDressagePath.PROCEED, "A", m)
    end
    halt(xs, "X", m, true)
    test.moves[m].s1 = xs
    test.length = test.pts[#test.pts].s
    table.sort(events, function(a, b) return a.s < b.s end)
    return test
end


-- RIDING IT -----------------------------------------------------------------------------------

local function lerp(range, t)
    return range[1] + (range[2] - range[1]) * math.max(0, math.min(1, t))
end


--- @param test table from build
--- @param temperament number|nil the horse's trained temperament, 0..100
--- @return table run
function EqDressagePath.newRun(test, temperament)
    local t = (temperament or 50) / 100
    local run = { test = test, frame = test.frame, i = 1, s = 0, ev = 1, gait = EqDressagePath.PROCEED, started = false,
        look = lerp(EqDressagePath.LOOK, t), warn = lerp(EqDressagePath.WARN, t), tolerance = lerp(EqDressagePath.TOLERANCE, t),
        cur = 1, marks = {}, acc = {}, errors = 0, lostMs = 0, outMs = 0, stallMs = 0, dev = 0, clock = 0 }
    for m = 1, #test.moves do run.acc[m] = { devSum = 0, len = 0, wrongMs = 0, pen = 0 } end
    -- Out of the arena counts once the path is inside the rail.
    run.inFrom = 0
    for _, p in ipairs(test.pts) do
        if p.y > -test.frame.halfL + 1 then
            run.inFrom = p.s
            break
        end
    end
    return run
end


--- @return boolean true when the horse's move is that gait
function EqDressagePath.matches(move, gait)
    if gait == "canter" then return move == "canter" or move == "fast" end
    return move == gait
end


--- The mark for a movement from what it gathered.
--- @param acc table { devSum, len, wrongMs, pen }
--- @return number 0..10 in halves
function EqDressagePath.markOf(acc)
    local mean = acc.len > 0 and acc.devSum / acc.len or 0
    local mark = 10 - math.max(0, mean - EqDressagePath.DEV_FREE) * EqDressagePath.DEV_PER_M
        - math.min(EqDressagePath.WRONG_MAX, acc.wrongMs / 1000 * EqDressagePath.WRONG_PER_S) - acc.pen
    return math.max(0, math.min(10, math.floor(mark * 2 + 0.5) / 2))
end


--- @return number percent, one decimal, of the marks so far (all movements once it is over)
function EqDressagePath.percent(run, all)
    local sum, n = 0, 0
    for m = 1, #run.test.moves do
        if run.marks[m] ~= nil then sum, n = sum + run.marks[m], n + 1 end
    end
    if all then n = #run.test.moves end
    if n == 0 then return 0 end
    return math.floor(sum / (10 * n) * 1000 + 0.5) / 10
end


--- @param percent number|nil
--- @return number share of the test's training payoff
function EqDressagePath.payoffShare(percent)
    if percent == nil then return 1 end
    local t = (percent - EqDressagePath.PAYOFF_ZERO) / (EqDressagePath.PAYOFF_FULL - EqDressagePath.PAYOFF_ZERO)
    return EqDressagePath.PAYOFF_MIN + (1 - EqDressagePath.PAYOFF_MIN) * math.max(0, math.min(1, t))
end


--- Close movements up to m (its mark from what it gathered).
local function closeTo(run, m)
    local event = nil
    while run.cur <= math.min(m, #run.test.moves) do
        if run.marks[run.cur] == nil then
            run.marks[run.cur] = EqDressagePath.markOf(run.acc[run.cur])
            run.lastMark, run.lastMove = run.marks[run.cur], run.cur
            event = "done"
        end
        run.cur = run.cur + 1
    end
    return event
end


--- The nearest path point to (x, y) from index a to b.
local function nearest(pts, a, b, x, y)
    local best, bestD = a, math.huge
    for i = math.max(1, a), math.min(#pts, b) do
        local d = (pts[i].x - x) ^ 2 + (pts[i].y - y) ^ 2
        if d < bestD then best, bestD = i, d end
    end
    return best, math.sqrt(bestD)
end


local function addPen(run, m, amount)
    local acc = run.acc[math.max(1, math.min(m, #run.test.moves))]
    acc.pen = acc.pen + amount
end


--- An error of course: a penalty, and the line picks up at the nearest point ahead.
--- @return string "fault" or "lost"
local function errorOfCourse(run, x, y)
    run.errors = run.errors + 1
    addPen(run, run.cur, EqDressagePath.ERROR_PEN)
    run.lostMs, run.outMs, run.stallMs = 0, 0, 0
    if run.errors >= EqDressagePath.ERRORS then
        run.eliminated = true
        return "lost"
    end
    local pts = run.test.pts
    local ahead = run.i
    while ahead < #pts and pts[ahead].s < run.s + EqDressagePath.SNAP_AHEAD do ahead = ahead + 1 end
    local j = nearest(pts, run.i, ahead, x, y)
    run.i, run.s = j, pts[j].s
    -- What it skipped is gone: changes and halts there count as done, without marks off.
    local events = run.test.events
    while run.ev <= #events and events[run.ev].s <= run.s and not events[run.ev].final do
        run.gait = events[run.ev].gait
        run.ev = run.ev + 1
    end
    run.hold = nil
    return "fault"
end


--- One frame of the test.
--- @param run table from newRun
--- @param move string walk, trot, canter, fast, gallop, halt or reverse
--- @param wx number the horse's world position
--- @param wz number
--- @param dt number milliseconds
--- @return string|nil event "begin", "request" (a change or halt is near), "done" (a movement
---     marked: run.lastMark), "fault" (an error of course), "test" (finished: run.percent) or "lost"
function EqDressagePath.step(run, move, wx, wz, dt)
    local test, pts = run.test, run.test.pts
    local x, y = EqDressagePath.toLocal(run.frame, wx, wz)
    run.clock = run.clock + dt

    if not run.started then
        local d = math.sqrt((pts[1].x - x) ^ 2 + (pts[1].y - y) ^ 2)
        if d > EqDressagePath.START_RADIUS then return nil end
        run.started, run.lastX, run.lastY = true, x, y
        return "begin"
    end

    -- Along the line: ahead by about what the horse moved, so cutting across doesn't skip it.
    local moved = math.sqrt((x - run.lastX) ^ 2 + (y - run.lastY) ^ 2)
    run.lastX, run.lastY = x, y
    local i0 = run.i
    local back = math.ceil(EqDressagePath.SEARCH_BACK / EqDressagePath.STEP)
    local ahead = math.ceil((moved * 1.5 + EqDressagePath.SEARCH_AHEAD) / EqDressagePath.STEP)
    local j, dev = nearest(pts, i0 - back, i0 + ahead, x, y)
    local skipped = 0
    if dev > EqDressagePath.REJOIN_FROM then
        local far = i0 + math.ceil(EqDressagePath.REJOIN_AHEAD / EqDressagePath.STEP)
        local k, kd = nearest(pts, i0 + ahead + 1, far, x, y)
        if kd <= EqDressagePath.REJOIN_DIST then
            skipped = pts[k].s - pts[math.min(i0 + ahead, #pts)].s
            j, dev = k, kd
        end
    end
    run.dev = dev
    if j > i0 then
        local ds = pts[j].s - pts[i0].s
        for k = i0 + 1, j do
            local acc = run.acc[pts[k].m]
            local step = pts[k].s - pts[k - 1].s
            acc.devSum = acc.devSum + step * (skipped > 0 and EqDressagePath.SKIP_DEV or dev)
            acc.len = acc.len + step
        end
        run.i, run.s = j, pts[j].s
        if ds > 0.05 then run.stallMs = 0 end
    end

    local m = pts[run.i].m
    local event = closeTo(run, m - 1)
    local events = test.events
    local next = events[run.ev]

    -- A halt held: stand still for HOLD_MS, then go on (or the test is over).
    if run.hold ~= nil then
        run.stallMs = 0
        if move ~= "halt" and not run.hold.moved then
            run.hold.moved = true
            addPen(run, run.hold.event.m, EqDressagePath.HALT_MOVED)
        end
        if run.clock >= run.hold.untilMs or run.hold.moved then
            local done = run.hold.event
            run.hold, run.ev = nil, run.ev + 1
            run.gait = done.gait
            if done.final then
                closeTo(run, #test.moves)
                run.percent = EqDressagePath.percent(run, true)
                return "test"
            end
            run.proceedMs = run.clock
            return "request"
        end
        return event
    end

    -- Changes and halts as they come.
    local free = false
    if next ~= nil then
        local dist = next.s - run.s
        if dist <= run.warn then
            free = true
            if not next.shown then
                next.shown = true
                event = event or "request"
            end
            if next.kind == "halt" then
                if move == "halt" then
                    local hx, hy = pts[run.i].x, pts[run.i].y
                    for k = run.i, #pts do
                        if pts[k].s >= next.s then
                            hx, hy = pts[k].x, pts[k].y
                            break
                        end
                    end
                    local err = math.sqrt((hx - x) ^ 2 + (hy - y) ^ 2)
                    addPen(run, next.m, math.min(EqDressagePath.HALT_MAX, math.max(0, err - EqDressagePath.HALT_FREE) * EqDressagePath.HALT_PER_M))
                    run.hold = { event = next, untilMs = run.clock + EqDressagePath.HOLD_MS }
                    return event
                elseif -dist >= EqDressagePath.HALT_PASS then
                    addPen(run, next.m, EqDressagePath.HALT_MISSED)
                    run.ev, run.gait = run.ev + 1, next.gait
                    if next.final then
                        closeTo(run, #test.moves)
                        run.percent = EqDressagePath.percent(run, true)
                        return "test"
                    end
                end
            elseif EqDressagePath.matches(move, next.gait) then
                local err = math.abs(dist)
                addPen(run, next.m, math.min(EqDressagePath.CHANGE_MAX, math.max(0, err - run.tolerance) * EqDressagePath.CHANGE_PER_M))
                run.ev, run.gait = run.ev + 1, next.gait
            elseif -dist >= EqDressagePath.MISS then
                addPen(run, next.m, EqDressagePath.CHANGE_MAX)
                run.ev, run.gait = run.ev + 1, next.gait
            end
        end
    end

    -- At the wrong gait, once settled after the last change or halt.
    local settling = run.proceedMs ~= nil and run.clock - run.proceedMs < 3000
    if not free and not settling and not EqDressagePath.matches(move, run.gait) then
        local acc = run.acc[math.min(m, #test.moves)]
        acc.wrongMs = acc.wrongMs + dt
    end

    -- Errors of course.
    run.lostMs = dev > EqDressagePath.LOST_DEV and run.lostMs + dt or 0
    local frame = run.frame
    local out = run.s > run.inFrom and (math.abs(x) > frame.halfW + EqDressagePath.OUT_MARGIN or math.abs(y) > frame.halfL + EqDressagePath.OUT_MARGIN)
    run.outMs = out and run.outMs + dt or 0
    run.stallMs = run.stallMs + dt
    if run.lostMs >= EqDressagePath.LOST_MS or run.outMs >= EqDressagePath.OUT_MS or run.stallMs >= EqDressagePath.STALL_MS then
        return errorOfCourse(run, x, y)
    end
    return event
end


--- What to show next: the change or halt coming up, once it is within warning.
--- @return table|nil event { s, kind, gait, letter }, number metres to it
function EqDressagePath.upcoming(run)
    local next = run.test.events[run.ev]
    if next == nil or run.hold ~= nil then return nil end
    local dist = next.s - run.s
    if dist > run.warn then return nil end
    return next, dist
end

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
-- The track: this far inside the rail, its corners by gait (CORNER_SMALL in the 15 m arena,
-- where a canter's short sides are half circles).
EqDressagePath.TRACK_INSET = 1.5
EqDressagePath.CORNER = { walk = 3.5, trot = 4.5, canter = 7 }
EqDressagePath.CORNER_SMALL = { walk = 3.5, trot = 3.5, canter = 7 }
-- Letters stand this far outside the rail (art/source/dressage_arenas.py MARKER_GAP).
EqDressagePath.MARKER_GAP = 0.6
-- Turns down the centre line (radius), and how wide a "20 m" circle may be (radius).
EqDressagePath.CENTRE_TURN = 4
EqDressagePath.BIG_CIRCLE = 10
-- Circles at the side letters by gait (radius): 8 m at a walk, 10 or 15 m at a trot, 15 m at a canter.
EqDressagePath.VOLTES = { walk = { 4 }, trot = { 5, 7.5 }, canter = { 7.5 } }
-- The tightest turn a figure may ask for at each gait (radius; at most half the track's width).
-- The base game turns a ridden horse on about 3.5 m (log, 2026-10-27), but a canter needs room.
EqDressagePath.MIN_RADIUS = { walk = 3.5, trot = 4, canter = 7 }
EqDressagePath.MIN_RADIUS_SMALL = { walk = 3, trot = 3, canter = 6 }
-- Turns are measured over this many points either side.
EqDressagePath.RADIUS_SPAN = 3
-- The test starts this far outside A, and the rider begins within START_RADIUS of it.
EqDressagePath.START_OUT = 2.5
EqDressagePath.START_RADIUS = 3.5
-- Figures in a test: training, and a hosted event's (EqDressagePath.figuresFor).
EqDressagePath.TRAINING_FIGURES = 7
-- The track between figures: at least this long, and preferably no longer than CONNECT_GOOD.
EqDressagePath.CONNECT_MIN = 3
EqDressagePath.CONNECT_GOOD = 15
-- Every figure is ridden at one gait, built for it (James 2026-10-29: trot circles, walk
-- circles and canter circles, never one in another gait). How often each gait and figure comes.
EqDressagePath.GAITS = { "walk", "trot", "canter" }
EqDressagePath.GAIT_WEIGHTS = { walk = 2, trot = 5, canter = 3 }
-- Short figures come more often than long ones (James 2026-10-30: long figures felt like one
-- big line, nothing new for a while).
EqDressagePath.FIGURE_WEIGHTS = { circle = 1.5, longDiagonal = 1.5, shortDiagonal = 1.5, halfVolte = 2, across = 1.5, acrossChange = 1.5,
    centre = 1.5, serpentine = 0.8, shallowLoop = 1.2, throughCircle = 1.2, eight = 0.8 }
-- Chances in 100: on the track before a figure, a stretch at another gait between two letters
-- (INTERLUDES: which gait, by the gait the horse is in), else a halt at a letter; a change down
-- inside a figure (DOWN); a halt at X on a centre line.
EqDressagePath.INTERLUDE = 55
EqDressagePath.INTERLUDES = { walk = { { "trot", 1 } }, trot = { { "canter", 3 }, { "walk", 1 } }, canter = { { "trot", 1 } } }
EqDressagePath.HALT_TRACK = 30
-- Else this % of the time on the track, movement on the spot at a letter (James, 2026-10-30):
-- a piaffe at a trot, a pirouette at a walk or canter; and this % of canters and walks between
-- two letters have a pirouette at a letter between them.
EqDressagePath.SPOT_TRACK = 15
EqDressagePath.SPOT_INTERLUDE = 40
EqDressagePath.CHANGE_INSIDE = 55
EqDressagePath.DOWN = { canter = "trot", trot = "walk" }
EqDressagePath.HALT_CHANCE = 60
-- Changes this far apart at least; a walk no longer than WALK_MAX (long walks are dull, James).
EqDressagePath.CHANGE_GAP = 15
EqDressagePath.CHANGE_LEAD = 8
EqDressagePath.CANTER_SPAN = 15
EqDressagePath.WALK_MAX = 30
-- After a halt: stand this long, then go on at this gait.
EqDressagePath.HOLD_MS = 2500
-- Some halts (not the last) go on into a rein back: back up for REIN_BACK_MS, told only once the
-- halt is held. Moving off before it is done costs up to REIN_BACK_SHORT; not starting it within
-- REIN_BACK_WAIT_MS costs REIN_BACK_MISSED.
EqDressagePath.REIN_BACK_CHANCE = 40
EqDressagePath.REIN_BACK_MS = 2000
EqDressagePath.REIN_BACK_SHORT = 2
EqDressagePath.REIN_BACK_WAIT_MS = 5000
EqDressagePath.REIN_BACK_MISSED = 3
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

-- Lateral work (EqLateral, James 2026-10-30): the sideways drift is DRIFT of the forward speed
-- (EqLateral.SHARE). In a lateral section the horse's body must face within ANGLE_FREE (radians)
-- of the way asked, else ANGLE_PER_S a second (at most ANGLE_MAX); a bend asked for must be at
-- least BEND_MIN that way, else BEND_PER_S a second (at most BEND_MAX). The first SECTION_GRACE
-- metres of a section are not judged (setting up).
EqDressagePath.DRIFT = 0.5
EqDressagePath.LATERAL_IN = { [true] = 4, [false] = 3 }
EqDressagePath.ANGLE_FREE = math.rad(12)
EqDressagePath.ANGLE_PER_S = 0.6
EqDressagePath.ANGLE_MAX = 3
EqDressagePath.BEND_MIN = 0.3
EqDressagePath.BEND_PER_S = 0.5
EqDressagePath.BEND_MAX = 2
EqDressagePath.SECTION_GRACE = 1
-- Temperament's stickiness (James 2026-10-30): a pull back onto the line, a share of how far off
-- the horse is each second (0 at temperament 0 up to STICK_PULL at 100; STICK_FREE of it outside
-- lateral work), and a turn towards the body angle a section asks for, up to STICK_TURN rad/s.
EqDressagePath.STICK_PULL = 0.8
-- A bend sharper than this (radians) where pieces of line join is smoothed out of the line.
EqDressagePath.KINK = math.rad(50)
-- Metres over which the line eases from one gait's track to another's in a corner.
EqDressagePath.BLEND = 5
EqDressagePath.STICK_FREE = 0.3
EqDressagePath.STICK_TURN = 0.5

-- Marks. Off the line: nothing for the first DEV_FREE metres on average, then DEV_PER_M a metre
-- (James 2026-10-30: 0.3 to 0.4 m off on average scored 8s and 9s for a test worth about 60%).
EqDressagePath.DEV_FREE = 0.05
EqDressagePath.DEV_PER_M = 12
-- At the wrong gait: this much a second, at most WRONG_MAX a movement.
EqDressagePath.WRONG_PER_S = 0.5
EqDressagePath.WRONG_MAX = 5
-- A change out of its window: this much a metre beyond it, at most CHANGE_MAX (also a missed one).
EqDressagePath.CHANGE_PER_M = 0.8
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
-- On the spot (Ctrl, EqLateral): started near its point like a halt (the same marks off), a
-- piaffe held SPOT_MS, a pirouette turned a full circle the way asked (SPOT_TURN radians short
-- of it will do); let go early costs up to SPOT_SHORT, riding past SPOT_MISSED.
EqDressagePath.SPOT_MS = 4000
EqDressagePath.SPOT_TURN = math.rad(20)
EqDressagePath.SPOT_SHORT = 3
EqDressagePath.SPOT_MISSED = 3
-- Off the spot this long before it counts as let go (James, 2026-10-30: a pirouette ended a third
-- of the way round).
EqDressagePath.SPOT_GRACE_MS = 700
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


--- The geometry figures are built from: the track's corners and the tightest turn allowed at
--- each gait (a canter needs room, James 2026-10-29: a canter asked for just before a tight turn
--- had no chance of following it).
local function geometry(frame)
    local g = { wt = frame.halfW - EqDressagePath.TRACK_INSET, lt = frame.halfL - EqDressagePath.TRACK_INSET }
    local small = frame.halfW < 9
    g.rc, g.minR = {}, {}
    for gait, r in pairs(small and EqDressagePath.CORNER_SMALL or EqDressagePath.CORNER) do
        -- A canter in the small arena: its short sides are half circles, as wide as it is.
        g.rc[gait] = math.min(r, g.wt)
        g.minR[gait] = math.min((small and EqDressagePath.MIN_RADIUS_SMALL or EqDressagePath.MIN_RADIUS)[gait], g.wt)
    end
    -- The side letters on the right, from A up (K/F first).
    g.sides = {}
    for _, l in ipairs(frame.letters) do
        if l.x > frame.halfW * 0.5 then table.insert(g.sides, l.y) end
    end
    table.sort(g.sides)
    g.straight = {}
    for gait, r in pairs(g.rc) do g.straight[gait] = g.lt - r end
    return g
end


-- FIGURES ------------------------------------------------------------------------------------
-- Each builder(g, frame, gait) returns figures for the right side, A end, ridden at that gait
-- (nil when the figure is not ridden at it): { key, pts, labels = { local points named by
-- their letters }, marks = { point indices where a change down may come }, turn = 1 or -1 when
-- the name says left or right }. Gaits: weights for how often each is picked.

local FIGURES = {}


--- A big circle's name: as wide as the arena when it touches the track on both sides (a "20 m
--- circle" rides on the track, inside the rail), else its own size.
local function bigSize(g, r)
    return r >= g.wt - 0.01 and 2 * (r + EqDressagePath.TRACK_INSET) or 2 * r
end


--- A circle from A, as big as the arena allows (up to 20 m): trot or canter.
FIGURES.circleEnd = function(g, frame, gait)
    if gait == "walk" then return {} end
    local r = math.min(EqDressagePath.BIG_CIRCLE, g.wt)
    local pen = newPen(0, -g.lt, 1, 0)
    arc(pen, r, math.pi * 2)
    return { { key = "circle", size = bigSize(g, r), pts = pen.pts, labels = { { 0, -g.lt } }, marks = { math.floor(#pen.pts / 2) } } }
end


--- A circle from the middle letter (E or B), as wide as the arena: trot or canter.
FIGURES.circleMid = function(g, frame, gait)
    if gait == "walk" then return {} end
    local r = math.min(EqDressagePath.BIG_CIRCLE, g.wt)
    if r > g.straight[gait] then return {} end
    local pen = newPen(g.wt, 0, 0, 1)
    arc(pen, r, math.pi * 2)
    return { { key = "circle", size = bigSize(g, r), pts = pen.pts, labels = { { g.wt, 0 } }, marks = { math.floor(#pen.pts / 2) } } }
end


--- Circles at the side letters, sized for the gait: 8 m at a walk, 10 m at a trot, 15 m at a
--- trot or canter where the arena is wide enough.
FIGURES.volte = function(g, frame, gait)
    local list = {}
    for _, r in ipairs(EqDressagePath.VOLTES[gait]) do
        if 2 * r <= 2 * g.wt and r < g.wt then
            for _, y in ipairs(g.sides) do
                if math.abs(y) <= g.straight[gait] and math.abs(y) + r <= g.lt then
                    local pen = newPen(g.wt, y, 0, 1)
                    arc(pen, r, math.pi * 2)
                    table.insert(list, { key = "circle", size = r * 2, pts = pen.pts, labels = { { g.wt, y } }, marks = {} })
                end
            end
        end
    end
    return list
end


--- Change rein on the long diagonal, F-X-H (a free walk, a trot or a canter), or the short one,
--- F-E (trot or canter).
FIGURES.diagonals = function(g, frame, gait)
    local first, last = g.sides[1], g.sides[#g.sides]
    if first == nil then return {} end
    local straight, rc = g.straight[gait], g.rc[gait]
    local list = {}
    local function diagonal(toY, key)
        -- Room on the track before and after the diagonal for corners of the gait's size.
        local fromY, cornerY = math.max(first, -straight + 1), math.min(toY, straight - 1)
        for _ = 1, 3 do
            local lead = rc * math.tan(math.atan2(2 * g.wt, cornerY - fromY) / 2) + 0.3
            fromY = math.max(first, -straight + lead)
            cornerY = math.min(toY, straight - lead)
        end
        local pen = newPen(g.wt, -straight, 0, 1)
        rounded(pen, { { x = g.wt, y = fromY }, { x = -g.wt, y = cornerY }, { x = -g.wt, y = straight } }, rc)
        -- The middle of the diagonal (X on the long one) is a natural place for a change down.
        local mid, bestD = 1, math.huge
        local midY = (fromY + cornerY) / 2
        for i, p in ipairs(pen.pts) do
            local d = math.abs(p.x) + math.abs(p.y - midY)
            if d < bestD then mid, bestD = i, d end
        end
        table.insert(list, { key = key, pts = pen.pts, labels = { { g.wt, first }, { -g.wt, toY } }, marks = { mid } })
    end
    diagonal(last, "longDiagonal")
    if gait ~= "walk" then diagonal(0, "shortDiagonal") end
    return list
end


--- A half volte: half a small circle in from a side letter, back to the track on a slant. Walk or trot.
FIGURES.halfVolte = function(g, frame, gait)
    if gait == "canter" then return {} end
    local r, list = EqDressagePath.VOLTES[gait][1], {}
    for _, y in ipairs(g.sides) do
        local back = y - 2 * r
        if 2 * r < 2 * g.wt and y + r <= g.lt and y <= g.straight[gait] + 1 and back - 2 >= -g.straight[gait] - 0.5 then
            local pen = newPen(g.wt, y, 0, 1)
            arcUntil(pen, r, 1, math.pi * 0.75, facing(g.wt, back))
            rounded(pen, { { x = g.wt, y = back }, { x = g.wt, y = back - 2 } }, g.rc[gait])
            table.insert(list, { key = "halfVolte", pts = pen.pts, labels = { { g.wt, y } }, marks = {} })
        end
    end
    return list
end


--- Across the arena from a side letter: turning back the same way (half school) or changing
--- rein. Walk or trot.
FIGURES.across = function(g, frame, gait)
    if gait == "canter" then return {} end
    local list, rc, straight = {}, g.rc[gait], g.straight[gait]
    for _, y in ipairs(g.sides) do
        if y - rc >= -straight and y + rc <= straight then
            for _, turn in ipairs({ 1, -1 }) do
                local pen = newPen(g.wt, y - rc, 0, 1)
                rounded(pen, { { x = g.wt, y = y }, { x = -g.wt, y = y }, { x = -g.wt, y = y - rc * turn } }, rc)
                table.insert(list, { key = turn == 1 and "across" or "acrossChange", pts = pen.pts, labels = { { g.wt, y }, { -g.wt, y } },
                    marks = {} })
            end
        end
    end
    return list
end


--- Down the centre line from A, to track left or right at C.
--- @param opening boolean the test's opening: from outside A (its halt at X is the build's)
local function centreLine(g, frame, turn, opening, gait)
    -- Both turns at each end share the half width: from the long side through the corner onto
    -- the centre line (no room for them on the short side alone).
    local a = math.min(EqDressagePath.CENTRE_TURN, g.wt / 2)
    local pen, points
    if opening then
        pen = newPen(0, -frame.halfL - EqDressagePath.START_OUT, 0, 1)
        points = {}
    else
        pen = newPen(-g.wt, -g.lt + a + 1, 0, -1)
        points = { { x = -g.wt, y = -g.lt }, { x = 0, y = -g.lt } }
    end
    for _, p in ipairs({ { x = 0, y = g.lt }, { x = -turn * g.wt, y = g.lt }, { x = -turn * g.wt, y = g.lt - a - 1 } }) do
        table.insert(points, p)
    end
    rounded(pen, points, a)
    local x, best = 1, math.huge
    for i, p in ipairs(pen.pts) do
        local d = p.x * p.x + p.y * p.y
        if d < best then x, best = i, d end
    end
    return pen.pts, x
end


--- A centre line: walk or trot, often with a halt at X.
FIGURES.centre = function(g, frame, gait)
    if gait == "canter" then return {} end
    local list = {}
    for _, turn in ipairs({ 1, -1 }) do
        local pts, x = centreLine(g, frame, turn, false, gait)
        table.insert(list, { key = "centre", turn = turn, pts = pts, labels = { { 0, -g.lt }, { 0, g.lt } }, marks = { x }, haltAt = x })
    end
    return list
end


--- A serpentine of n loops from A to C, each loop touching a long side. Trot only.
FIGURES.serpentine = function(g, frame, gait)
    if gait ~= "trot" then return {} end
    local list = {}
    for _, n in ipairs({ 3, 4, 5 }) do
        local h = 2 * g.lt / n
        local r = math.min(h / 2, g.wt, 6) - 0.01
        if r >= g.minR.trot then
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
            table.insert(list, { key = "serpentine", loops = n, pts = pen.pts, labels = { { 0, -g.lt }, { 0, g.lt } }, marks = {} })
        end
    end
    return list
end


--- A shallow loop in off the long side: K-E-H in by 5 m (3 m in a 15 m arena). Any gait.
FIGURES.shallowLoop = function(g, frame, gait)
    local first, last = g.sides[1], g.sides[#g.sides]
    if first == nil or #g.sides < 3 then return {} end
    local straight = g.straight[gait]
    local depth = gait == "canter" and (g.wt >= 8 and 3 or 2) or (g.wt >= 8 and 5 or 3)
    local lead = gait == "canter" and 2 or 1
    local fromY, toY = math.max(first, -straight + lead), math.min(last, straight - lead)
    local pen = newPen(g.wt, -straight, 0, 1)
    rounded(pen, { { x = g.wt, y = fromY }, { x = g.wt - depth, y = 0 }, { x = g.wt, y = toY }, { x = g.wt, y = straight } }, 12)
    local mid, bestD = 1, math.huge
    for i, p in ipairs(pen.pts) do
        if math.abs(p.y) < bestD then mid, bestD = i, math.abs(p.y) end
    end
    return { { key = "shallowLoop", size = depth, pts = pen.pts, labels = { { g.wt, first }, { g.wt, 0 }, { g.wt, last } }, marks = { mid } } }
end


--- Change rein through the circle at A: half the circle, then an S through its middle. Trot only.
FIGURES.throughCircle = function(g, frame, gait)
    if gait ~= "trot" then return {} end
    local r = math.min(EqDressagePath.BIG_CIRCLE, g.wt)
    local pen = newPen(0, -g.lt, 1, 0)
    arc(pen, r, math.pi)
    arc(pen, r / 2, math.pi)
    arc(pen, r / 2, -math.pi)
    return { { key = "throughCircle", pts = pen.pts, labels = { { 0, -g.lt } }, marks = {} } }
end


--- A figure of eight: circles at both ends, crossing at X. Trot or canter.
FIGURES.eight = function(g, frame, gait)
    if gait == "walk" then return {} end
    local r = math.min(EqDressagePath.BIG_CIRCLE, g.wt)
    local c = g.lt - r
    if c < r then return {} end
    local pen = newPen(0, -g.lt, 1, 0)
    if not arcUntil(pen, r, 1, math.pi / 6, facing(0, 0)) then return {} end
    local tx, ty = -pen.x, -pen.y
    lineTo(pen, 0, 0)
    local cross1 = #pen.pts
    lineTo(pen, tx, ty)
    if not arcUntil(pen, r, -1, math.pi / 2, facing(0, 0)) then return {} end
    tx, ty = -pen.x, -pen.y
    lineTo(pen, 0, 0)
    lineTo(pen, tx, ty)
    if not arcUntil(pen, r, 1, math.pi / 6, heading(1, 0)) then return {} end
    -- Back at A: square it up on the track.
    forward(pen, 1)
    return { { key = "eight", pts = pen.pts, labels = { { 0, -g.lt } }, marks = { cross1 } } }
end


-- LATERAL WORK (James 2026-10-30): with Shift + A/D the horse drifts sideways facing forwards
-- (EqLateral), and a right mouse drag bends its head. Each builds a figure whose sections ask for a
-- body angle (hx, hy: the way the horse faces, local) and a bend (1 right, -1 left, nil any).


--- In off the track and back, drifting with the body straight up the arena: leg yield (bend away
--- from the drift) or half pass (bend into it).
local function inAndBack(g, gait, key, bendIn)
    local d = EqDressagePath.LATERAL_IN[g.wt >= 8]
    local run = d / EqDressagePath.DRIFT
    local straight = g.straight[gait]
    local total = 2 + run + 3 + run + 2
    local list = {}
    for _, y in ipairs(g.sides) do
        -- A letter just into the corner is still on the track (within half a metre).
        if y >= -straight - 1 and y + total <= straight + 1 then
            local pen = newPen(g.wt, y, 0, 1)
            forward(pen, 2)
            local a = #pen.pts
            lineTo(pen, g.wt - d, pen.y + run)
            local b = #pen.pts
            lineTo(pen, g.wt - d, pen.y + 3)
            local c = #pen.pts
            lineTo(pen, g.wt, pen.y + run)
            local e = #pen.pts
            lineTo(pen, g.wt, pen.y + 2)
            -- In is to the rider's left here (facing +y on the right side).
            table.insert(list, { key = key, pts = pen.pts, labels = { { g.wt, y } }, marks = {}, lateral = true,
                sections = { { from = a, to = b, hx = 0, hy = 1, bend = bendIn, drift = -1 },
                    { from = c, to = e, hx = 0, hy = 1, bend = -bendIn, drift = 1 } } })
        end
    end
    return list
end


--- Leg yield off the track and back: walk or trot, bent away from the drift.
FIGURES.legYield = function(g, frame, gait)
    if gait == "canter" then return {} end
    return inAndBack(g, gait, "legYield", 1)
end


--- Half pass off the track and back: trot, or canter in a 20 m wide arena; bent into the drift.
FIGURES.halfPass = function(g, frame, gait)
    if gait == "walk" or gait == "canter" and g.wt < 8 then return {} end
    return inAndBack(g, gait, "halfPass", -1)
end


--- Along the rail between two side letters: shoulder-in (straight, head bent in) or leg yield
--- along the rail (the body turned in by the drift's angle, drifting to the rail). Walk or trot.
local function alongRail(g, gait, key)
    if gait == "canter" then return {} end
    local straight, list = g.straight[gait], {}
    local angle = math.atan(EqDressagePath.DRIFT)
    for k = 1, #g.sides - 1 do
        local y0, y1 = g.sides[k], g.sides[k + 1]
        if y0 >= -straight - 1 and y1 <= straight + 1 and y1 - y0 >= 10 then
            local pen = newPen(g.wt, y0, 0, 1)
            lineTo(pen, g.wt, y1)
            local section = key == "shoulderIn" and { from = 1, to = #pen.pts, hx = 0, hy = 1, bend = -1, drift = 0 }
                or { from = 1, to = #pen.pts, hx = -math.sin(angle), hy = math.cos(angle), drift = 1 }
            table.insert(list, { key = key, pts = pen.pts, labels = { { g.wt, y0 }, { g.wt, y1 } }, marks = {}, lateral = true,
                sections = { section } })
        end
    end
    return list
end


FIGURES.shoulderIn = function(g, frame, gait) return alongRail(g, gait, "shoulderIn") end
FIGURES.legYieldRail = function(g, frame, gait) return alongRail(g, gait, "legYieldRail") end


-- For the tests.
EqDressagePath.FIGURES = FIGURES


EqDressagePath.FIGURE_ORDER = { "legYield", "halfPass", "shoulderIn", "legYieldRail",
    "circleEnd", "circleMid", "volte", "diagonals", "halfVolte", "across", "centre", "serpentine",
    "shallowLoop", "throughCircle", "eight" }


--- The tightest turn along a line of points (metres of radius), from each point and the ones
--- RADIUS_SPAN either side.
--- @return number radius
function EqDressagePath.tightest(pts)
    local k, best = EqDressagePath.RADIUS_SPAN, math.huge
    for i = 1 + k, #pts - k do
        local a, b, c = pts[i - k], pts[i], pts[i + k]
        local ab = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        local bc = math.sqrt((c.x - b.x) ^ 2 + (c.y - b.y) ^ 2)
        local ca = math.sqrt((a.x - c.x) ^ 2 + (a.y - c.y) ^ 2)
        local cross = math.abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
        if cross > 1e-9 then best = math.min(best, ab * bc * ca / (2 * cross)) end
    end
    return best
end


--- The track for each gait: its points and length.
local function tracks(g)
    local list = {}
    for gait, r in pairs(g.rc) do
        local pts, length = trackPoints({ wt = g.wt, lt = g.lt, rc = r })
        list[gait] = { pts = pts, length = length }
    end
    return list
end


--- Every figure for an arena at every gait it is ridden at, mirrored four ways, each with where
--- it joins its gait's track. Figures with a turn tighter than the gait allows are left out.
--- @param frame table from frameFor
--- @return table figures, table tracks gait -> { pts, length }, table g
function EqDressagePath.library(frame)
    local g = geometry(frame)
    local byGait = tracks(g)
    local list = {}
    for _, name in ipairs(EqDressagePath.FIGURE_ORDER) do
        for _, gait in ipairs(EqDressagePath.GAITS) do
            local track = byGait[gait].pts
            for _, figure in ipairs(FIGURES[name](g, frame, gait)) do
                local weight = EqDressagePath.FIGURE_WEIGHTS[figure.key] or 1
                -- Lateral work drifts without turning: its kinks are not turns.
                if figure.lateral or EqDressagePath.tightest(figure.pts) >= g.minR[gait] * 0.9 then
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
                            -- A mirror swaps left and right once (twice is none).
                            local sections = nil
                            for _, sec in ipairs(figure.sections or {}) do
                                sections = sections or {}
                                table.insert(sections, { from = sec.from, to = sec.to, hx = sec.hx * sx, hy = sec.hy * sy,
                                    bend = sec.bend ~= nil and sec.bend * sx * sy or nil, drift = sec.drift * sx * sy })
                            end
                            table.insert(list, {
                                key = figure.key, gait = gait, weight = weight * EqDressagePath.GAIT_WEIGHTS[gait],
                                size = figure.size, loops = figure.loops, labels = labels,
                                turn = figure.turn ~= nil and figure.turn * sx * sy or nil,
                                pts = pts, marks = figure.marks, haltAt = figure.haltAt, sections = sections,
                                entry = entry, entryRein = reinAt(track, entry, pts[2].x - pts[1].x, pts[2].y - pts[1].y),
                                exitRein = reinAt(track, exit, pts[n].x - pts[n - 1].x, pts[n].y - pts[n - 1].y),
                                fromA = pts[1].y < 0,
                            })
                        end
                    end
                end
            end
        end
    end
    return list, byGait, g
end


--- For the tests: an arena's geometry, and the nearest point of a track.
EqDressagePath.geometry = geometry
EqDressagePath.onTrack = onTrack


-- BUILDING A TEST ----------------------------------------------------------------------------

--- @param list table { { name, weight }, ... }
--- @param rng function (n) -> 1..n
local function pick(list, rng)
    local total = 0
    for _, entry in ipairs(list) do total = total + entry[2] end
    if total <= 0 then return nil end
    local scale = 100 / total
    local roll = rng(100)
    for _, entry in ipairs(list) do
        roll = roll - entry[2] * scale
        if roll <= 0 then return entry[1] end
    end
    return list[#list][1]
end


--- Add points to a test's path, all in movement m.
local function append(test, pts, m)
    local path = test.pts
    local popped = 0
    for _, p in ipairs(pts) do
        -- Where two pieces of line join (the track and a figure, two gaits' tracks), the
        -- nearest point can sit a little behind or beside the horse: a sudden bend or step back
        -- (James's screenshot, 2026-10-30). Drop the points that make one.
        while #path >= 2 and popped < 4 do
            local a, b = path[#path - 1], path[#path]
            local ux, uy, vx, vy = b.x - a.x, b.y - a.y, p.x - b.x, p.y - b.y
            local turn = math.abs(math.atan2(ux * vy - uy * vx, ux * vx + uy * vy))
            local gap = math.sqrt((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2)
            if turn <= EqDressagePath.KINK or gap > 1.2 then break end
            table.remove(path)
            popped = popped + 1
        end
        local last = path[#path]
        local d = last ~= nil and math.sqrt((p.x - last.x) ^ 2 + (p.y - last.y) ^ 2) or 0
        if last == nil or d > 0.05 then
            table.insert(path, { x = p.x, y = p.y, s = (last ~= nil and last.s or 0) + d, m = m })
        end
    end
    return popped
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


--- The letters round the edge a run of track passes: { i = index into pts, letter, x, y }, in order.
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
            if best ~= nil then table.insert(found, { i = best, letter = l.letter, x = pts[best].x, y = pts[best].y }) end
        end
    end
    table.sort(found, function(a, b) return a.i < b.i end)
    return found
end


--- How many figures a test of a hosted event's length has (data/hosting.xml dressageMoves:
--- 15, 20, 25 make 8, 10, 13).
--- @param moves number|nil
--- @return number figures
function EqDressagePath.figuresFor(moves)
    if moves == nil then return EqDressagePath.TRAINING_FIGURES end
    return math.max(3, math.floor(moves * 0.5 + 0.5))
end


--- Build a test for an arena.
--- @param frame table from frameFor
--- @param figures number how many figures between the opening and the final centre line
--- @param rng function (n) -> 1..n; a seeded one rides the same test every time
--- @return table test { pts = { x, y, s, m }, moves = { s0, s1, key, ... }, events = { s, kind, gait, letter, m }, length, frame }
function EqDressagePath.build(frame, figures, rng)
    local library, byGait, g = EqDressagePath.library(frame)
    local test = { pts = {}, moves = {}, events = {}, sections = {}, frame = frame, g = g }
    local events = test.events

    -- Changes: never closer than CHANGE_GAP to the last one (unless forced), and walks kept short.
    local gait, lastChange, walkFrom = EqDressagePath.PROCEED, 0, nil
    local function change(s, newGait, letter, m, forced)
        if newGait == gait or (not forced and s < lastChange + EqDressagePath.CHANGE_GAP) then return false end
        table.insert(events, { s = s, kind = "change", gait = newGait, letter = letter, m = m })
        gait, lastChange = newGait, s
        walkFrom = newGait == "walk" and s or nil
        return true
    end
    local function halt(s, letter, m, final, after)
        local back = not final and rng(100) <= EqDressagePath.REIN_BACK_CHANCE or nil
        table.insert(events, { s = s, kind = "halt", gait = final and "halt" or after, letter = letter, m = m, final = final, reinBack = back })
        gait, lastChange = after, s
        walkFrom = after == "walk" and s or nil
    end
    --- A piaffe (trot) or pirouette (walk, canter) at a letter, turning into the arena.
    local function spot(s, letter, m, turn)
        if s < lastChange + EqDressagePath.CHANGE_GAP then return end
        local style = gait == "trot" and "piaffe" or "pirouette"
        table.insert(events, { s = s, kind = "spot", style = style, gait = gait, letter = letter, m = m, turn = turn })
        lastChange = s
    end

    -- The opening: from outside A down the centre line, halt at X, track left or right at C.
    local turn = rng(2) == 1 and 1 or -1
    local opening, xIndex = centreLine(g, frame, turn, true, "trot")
    local enter = { s0 = 0, key = "enter", labels = { "A", "X" } }
    table.insert(test.moves, enter)
    for i = 1, xIndex do append(test, { opening[i] }, 1) end
    enter.s1 = test.pts[#test.pts].s
    halt(enter.s1, "X", 1, false, "trot")
    local proceed = { s0 = enter.s1, key = "proceed", turn = turn, labels = { "C" } }
    table.insert(test.moves, proceed)
    for i = xIndex + 1, #opening do append(test, { opening[i] }, 2) end
    proceed.s1 = test.pts[#test.pts].s
    local last = opening[#opening]
    local rein = reinAt(byGait.trot.pts, onTrack(byGait.trot.pts, last.x, last.y), last.x - opening[#opening - 1].x, last.y - opening[#opening - 1].y)
    local lastKey = "centre"

    --- Ride the track from where the horse is to (x, y) at the gait it is in, and add it.
    local function track(x, y, m)
        local t = byGait[gait].pts
        local here = test.pts[#test.pts]
        local run = trackRun(t, onTrack(t, here.x, here.y), onTrack(t, x, y), rein)
        -- Just after a change in a corner the horse is on the last gait's track, whose corner is
        -- sized differently: ease across to this one over BLEND metres, not a sudden step.
        local _, off = onTrack(t, here.x, here.y)
        if off > 0.1 then
            local from, fromOff = nil, off
            for _, other in pairs(byGait) do
                local _, d = onTrack(other.pts, here.x, here.y)
                if d < fromOff then from, fromOff = other.pts, d end
            end
            if from ~= nil then
                local d = 0
                for k, p in ipairs(run) do
                    if k > 1 then d = d + math.sqrt((p.x - run[k - 1].x) ^ 2 + (p.y - run[k - 1].y) ^ 2) end
                    if d >= EqDressagePath.BLEND then break end
                    local q = from[onTrack(from, p.x, p.y)]
                    local w = 1 - d / EqDressagePath.BLEND
                    w = w * w * (3 - 2 * w)
                    run[k] = { x = p.x + (q.x - p.x) * w, y = p.y + (q.y - p.y) * w }
                end
            end
        end
        append(test, run, m)
    end

    --- The way round to (x, y): the letters on it and how far each is.
    local function letterRun(x, y)
        local t = byGait[gait]
        local here = test.pts[#test.pts]
        local run = trackRun(t.pts, onTrack(t.pts, here.x, here.y), onTrack(t.pts, x, y), rein)
        local letters = trackLetters(frame, run)
        local d, s = 0, {}
        for i = 2, #run do
            d = d + math.sqrt((run[i].x - run[i - 1].x) ^ 2 + (run[i].y - run[i - 1].y) ^ 2)
            s[i] = d
        end
        s[1] = 0
        for _, l in ipairs(letters) do l.d = s[l.i] end
        return letters, d
    end

    --- The track to a figure's start, with what happens on the way: the change the figure
    --- needs at the last letter before it, else maybe a canter or walk on a long side, or a
    --- halt at a letter (James 2026-10-29: more to do between the figures).
    local function connect(entry, figGait, m)
        local letters, length = letterRun(entry.x, entry.y)
        local usable = {}
        for _, l in ipairs(letters) do
            if l.d >= 2 and length - l.d >= 4 then table.insert(usable, l) end
        end
        if figGait ~= gait then
            -- Up from a walk at the first letter (walks are kept short), else at the last.
            local at = gait == "walk" and usable[1] or usable[#usable]
            if at ~= nil then
                track(at.x, at.y, m)
                change(test.pts[#test.pts].s, figGait, at.letter, m, true)
            end
            if gait ~= figGait then
                -- No letter before it: change a few metres before the figure starts.
                local t = byGait[gait].pts
                local here = test.pts[#test.pts]
                local run = trackRun(t, onTrack(t, here.x, here.y), onTrack(t, entry.x, entry.y), rein)
                local k = math.max(1, #run - math.floor(EqDressagePath.CHANGE_LEAD / 2 / EqDressagePath.STEP))
                for i = 1, k do append(test, { run[i] }, m) end
                change(test.pts[#test.pts].s, figGait, nil, m, true)
            end
            track(entry.x, entry.y, m)
            return
        end
        local roll = rng(100)
        if #usable >= 2 and length >= 20 and roll <= EqDressagePath.INTERLUDE then
            -- A stretch at another gait between two letters, then back: a canter only along
            -- one long side (the track's corners are sized for the gait it is ridden at).
            local options = EqDressagePath.INTERLUDES[gait]
            local other = pick(options, rng)
            local from = usable[1]
            local to = nil
            local function side(l) return math.abs(l.x) > frame.halfW * 0.5 and (l.x > 0 and 1 or -1) or 0 end
            for k = #usable, 2, -1 do
                local span = usable[k].d - from.d
                if other == "canter" then
                    if side(from) ~= 0 and side(usable[k]) == side(from) and span >= EqDressagePath.CANTER_SPAN then
                        to = usable[k]
                        break
                    end
                elseif span >= 10 and (other ~= "walk" or span <= EqDressagePath.WALK_MAX) then
                    to = usable[k]
                    break
                end
            end
            if other ~= nil and to ~= nil then
                local back = gait
                track(from.x, from.y, m)
                change(test.pts[#test.pts].s, other, from.letter, m)
                -- A pirouette at a letter on the way, now and then.
                local between = {}
                for _, l in ipairs(usable) do
                    if l.d > from.d + 5 and l.d < to.d - 5 then table.insert(between, l) end
                end
                if other ~= "trot" and #between > 0 and rng(100) <= EqDressagePath.SPOT_INTERLUDE then
                    local at = between[rng(#between)]
                    track(at.x, at.y, m)
                    lastChange = lastChange - EqDressagePath.CHANGE_GAP
                    spot(test.pts[#test.pts].s, at.letter, m, rein)
                end
                track(to.x, to.y, m)
                change(test.pts[#test.pts].s, back, to.letter, m, true)
            end
        elseif #usable >= 1 and gait ~= "canter" and roll <= EqDressagePath.INTERLUDE + EqDressagePath.HALT_TRACK then
            local at = usable[rng(#usable)]
            track(at.x, at.y, m)
            if test.pts[#test.pts].s >= lastChange + EqDressagePath.CHANGE_GAP then
                halt(test.pts[#test.pts].s, at.letter, m, false, gait)
            end
        elseif #usable >= 1 and roll <= EqDressagePath.INTERLUDE + EqDressagePath.HALT_TRACK + EqDressagePath.SPOT_TRACK then
            local at = usable[rng(#usable)]
            track(at.x, at.y, m)
            spot(test.pts[#test.pts].s, at.letter, m, rein)
        end
        track(entry.x, entry.y, m)
    end

    local function ride(figure, m)
        local move = test.moves[m]
        connect(figure.pts[1], figure.gait, m)
        local figStart = #test.pts
        figStart = figStart - append(test, figure.pts, m)
        local function sAt(i) return test.pts[math.min(figStart + i - 1, #test.pts)].s end
        for _, sec in ipairs(figure.sections or {}) do
            table.insert(test.sections, { s0 = sAt(sec.from), s1 = sAt(sec.to), m = m, kind = figure.key, hx = sec.hx, hy = sec.hy,
                bend = sec.bend, drift = sec.drift })
        end
        -- A walk down the centre line trots on from X: halt, proceed at a trot.
        local after = figure.gait == "walk" and "trot" or figure.gait
        if figure.haltAt ~= nil and rng(100) <= EqDressagePath.HALT_CHANCE then
            halt(sAt(figure.haltAt), "X", m, false, after)
        elseif figure.haltAt ~= nil and after ~= figure.gait then
            change(sAt(figure.haltAt), after, "X", m, true)
        elseif #figure.marks > 0 and rng(100) <= EqDressagePath.CHANGE_INSIDE then
            -- Only a change down inside a figure: its turns suit the faster gait.
            local down = EqDressagePath.DOWN[gait]
            local at = sAt(figure.marks[rng(#figure.marks)])
            if down ~= nil and (down ~= "walk" or sAt(#figure.pts) - at <= EqDressagePath.WALK_MAX) then change(at, down, nil, m) end
        end
        -- A walk has gone on long enough: trot on as the figure ends.
        if walkFrom ~= nil and sAt(#figure.pts) - walkFrom > EqDressagePath.WALK_MAX then
            change(sAt(#figure.pts), "trot", nil, m, true)
        end
        move.s1 = test.pts[#test.pts].s
        rein = figure.exitRein
    end

    for _ = 1, figures do
        local choices = {}
        local here = test.pts[#test.pts]
        local t = byGait[gait]
        local from = onTrack(t.pts, here.x, here.y)
        for _, figure in ipairs(library) do
            -- One gait at a time (no walk to canter), room on the track for a change, and one
            -- walking figure at a time.
            local step = figure.gait == gait or (figure.gait == "trot" or gait == "trot")
            if figure.gait == "walk" and gait == "walk" then step = false end
            if figure.entryRein == rein and figure.key ~= lastKey and step then
                local d = trackDistance(t.pts, t.length, from, onTrack(t.pts, figure.pts[1].x, figure.pts[1].y), rein)
                local least = figure.gait == gait and EqDressagePath.CONNECT_MIN or EqDressagePath.CHANGE_LEAD
                if d >= least and d <= t.length * 0.6 then
                    local near = d <= EqDressagePath.CONNECT_GOOD and 4 or (d <= 2 * EqDressagePath.CONNECT_GOOD and 2 or 1)
                    table.insert(choices, { figure, figure.weight * near })
                end
            end
        end
        local figure = pick(choices, rng)
        if figure == nil then break end
        local m = #test.moves + 1
        table.insert(test.moves, { s0 = test.pts[#test.pts].s, key = figure.key, size = figure.size, loops = figure.loops,
            turn = figure.turn, labels = figure.labels, gait = figure.gait })
        ride(figure, m)
        lastKey = figure.key
    end

    -- The finish: down the centre line from A at a trot, halt at X (the path goes on a little past it).
    local final
    for _, figure in ipairs(library) do
        if figure.key == "centre" and figure.gait == "trot" and figure.fromA and figure.entryRein == rein then
            final = figure
            break
        end
    end
    local m = #test.moves + 1
    table.insert(test.moves, { s0 = test.pts[#test.pts].s, key = "final", labels = { "A", "X" } })
    connect(final.pts[1], "trot", m)
    local figStart = #test.pts
    for i = 1, math.min(final.haltAt + 16, #final.pts) do append(test, { final.pts[i] }, m) end
    local xs = test.pts[math.min(figStart + final.haltAt - 1, #test.pts)].s
    halt(xs, "X", m, true, "halt")
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
        cur = 1, marks = {}, acc = {}, devAt = {}, errors = 0, lostMs = 0, outMs = 0, stallMs = 0, dev = 0, clock = 0,
        temper = t, sec = 1 }
    for m = 1, #test.moves do run.acc[m] = { devSum = 0, len = 0, wrongMs = 0, pen = 0, angleMs = 0, bendMs = 0 } end
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
        - math.min(EqDressagePath.ANGLE_MAX, (acc.angleMs or 0) / 1000 * EqDressagePath.ANGLE_PER_S)
        - math.min(EqDressagePath.BEND_MAX, (acc.bendMs or 0) / 1000 * EqDressagePath.BEND_PER_S)
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


-- The line's colour by how far off it the horse is (James, 2026-10-29: green to yellow to red),
-- metres: { up to, colour }; past the last, red.
EqDressagePath.COLOUR_BANDS = { { 0.5, "green" }, { 1, "lime" }, { 1.6, "yellow" }, { 2.4, "orange" } }


--- @param dev number|nil metres off the line
--- @return string colour one of EqCourseGlow.COLOURS
function EqDressagePath.colourFor(dev)
    for _, band in ipairs(EqDressagePath.COLOUR_BANDS) do
        if (dev or 0) <= band[1] then return band[2] end
    end
    return "red"
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
            local acc = run.acc[run.cur]
            run.marks[run.cur] = EqDressagePath.markOf(acc)
            run.lastMark, run.lastMove = run.marks[run.cur], run.cur
            -- Why: for the log.
            local move = run.test.moves[run.cur]
            run.lastDetail = string.format("%s, off the line %.2f m on average, wrong gait %.1f s, timing and halts -%.1f, body angle off %.1f s, bend off %.1f s",
                move.key, acc.len > 0 and acc.devSum / acc.len or 0, acc.wrongMs / 1000, acc.pen, (acc.angleMs or 0) / 1000, (acc.bendMs or 0) / 1000)
            event = "done"
        end
        run.cur = run.cur + 1
    end
    return event
end


--- The nearest path point to (x, y) from index a to b.
local function nearest(pts, a, b, x, y)
    local best, bestD = a, math.huge
    local from, to = math.max(1, a), math.min(#pts, b)
    for i = from, to do
        local d = (pts[i].x - x) ^ 2 + (pts[i].y - y) ^ 2
        if d < bestD then best, bestD = i, d end
    end
    -- How far off: to the line itself either side of the nearest point, not to the point (the
    -- points are STEP apart, so on the line was up to a quarter metre "off").
    local p = pts[best]
    for _, q in ipairs({ pts[best - 1], pts[best + 1] }) do
        if q ~= nil then
            local dx, dy = q.x - p.x, q.y - p.y
            local len2 = dx * dx + dy * dy
            if len2 > 1e-9 then
                local t = math.max(0, math.min(1, ((x - p.x) * dx + (y - p.y) * dy) / len2))
                local d = (p.x + dx * t - x) ^ 2 + (p.y + dy * t - y) ^ 2
                if d < bestD then bestD = d end
            end
        end
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
    run.hold, run.spot = nil, nil
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
--- @param look table|nil { dirX, dirZ = the horse's facing in the world, bend = -1..1 right
--- positive } for lateral work; nil leaves sections unjudged
function EqDressagePath.step(run, move, wx, wz, dt, look)
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
            local d = skipped > 0 and EqDressagePath.SKIP_DEV or dev
            acc.devSum = acc.devSum + step * d
            -- How far off each point was ridden: the line behind the horse is coloured by it.
            run.devAt[k] = d
            acc.len = acc.len + step
        end
        run.i, run.s = j, pts[j].s
        if ds > 0.05 then run.stallMs = 0 end
    end

    local m = pts[run.i].m
    local event = closeTo(run, m - 1)
    local events = test.events
    local next = events[run.ev]

    -- A rein back after a halt: back up for REIN_BACK_MS, then go on.
    if run.back ~= nil then
        run.stallMs = 0
        local back = run.back
        if move == "reverse" then
            back.ms = back.ms + dt
        elseif back.ms > 0 and move ~= "halt" or back.ms == 0 and run.clock - back.from > EqDressagePath.REIN_BACK_WAIT_MS then
            -- Moved off too soon, or never backed up.
            local short = back.ms == 0 and EqDressagePath.REIN_BACK_MISSED
                or EqDressagePath.REIN_BACK_SHORT * (1 - back.ms / EqDressagePath.REIN_BACK_MS)
            addPen(run, back.event.m, short)
            back.ms = EqDressagePath.REIN_BACK_MS
        end
        if back.ms >= EqDressagePath.REIN_BACK_MS then
            run.back, run.ev = nil, run.ev + 1
            run.gait = back.event.gait
            run.proceedMs = run.clock
            -- Wherever the horse backed to, carry on from the nearest point.
            run.lastX, run.lastY = x, y
            return "request"
        end
        return event
    end

    -- On the spot: a piaffe held, or a pirouette turned round, then go on.
    if run.spot ~= nil then
        run.stallMs = 0
        local spot, done = run.spot, false
        local on = look ~= nil and look.spot and EqDressagePath.matches(move, spot.event.gait)
        if on then
            spot.offMs = 0
            spot.ms = spot.ms + dt
            if spot.event.style == "pirouette" then
                local a = math.atan2(look.dirX, look.dirZ)
                local d = (a - spot.lastA + math.pi) % (2 * math.pi) - math.pi
                spot.lastA = a
                spot.turned = spot.turned + d * spot.event.turn
                done = spot.turned >= 2 * math.pi - EqDressagePath.SPOT_TURN
            else
                done = spot.ms >= EqDressagePath.SPOT_MS
            end
        else
            spot.offMs = (spot.offMs or 0) + dt
            if look ~= nil then spot.lastA = math.atan2(look.dirX, look.dirZ) end
            if spot.offMs >= EqDressagePath.SPOT_GRACE_MS then
                -- Let go early: marks off by how much was left.
                addPen(run, spot.event.m, EqDressagePath.SPOT_SHORT * (1 - EqDressagePath.spotShare(spot)))
                done = true
            end
        end
        if done then
            run.spot, run.ev = nil, run.ev + 1
            run.proceedMs = run.clock
            run.lastX, run.lastY = x, y
            return "request"
        end
        return event
    end

    -- A halt held: stand still for HOLD_MS, then go on (or the test is over).
    if run.hold ~= nil then
        run.stallMs = 0
        if move ~= "halt" and not run.hold.moved then
            run.hold.moved = true
            addPen(run, run.hold.event.m, EqDressagePath.HALT_MOVED)
        end
        if run.clock >= run.hold.untilMs or run.hold.moved then
            local done = run.hold.event
            if done.reinBack and not run.hold.moved then
                run.hold = nil
                run.back = { event = done, ms = 0, from = run.clock }
                return "request"
            end
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
            elseif next.kind == "spot" then
                if look ~= nil and look.spot and EqDressagePath.matches(move, next.gait) then
                    local hx, hy = pts[run.i].x, pts[run.i].y
                    for k = run.i, #pts do
                        if pts[k].s >= next.s then
                            hx, hy = pts[k].x, pts[k].y
                            break
                        end
                    end
                    local err = math.sqrt((hx - x) ^ 2 + (hy - y) ^ 2)
                    addPen(run, next.m, math.min(EqDressagePath.HALT_MAX, math.max(0, err - EqDressagePath.HALT_FREE) * EqDressagePath.HALT_PER_M))
                    run.spot = { event = next, ms = 0, turned = 0, lastA = math.atan2(look.dirX, look.dirZ) }
                    return event
                elseif -dist >= EqDressagePath.HALT_PASS then
                    addPen(run, next.m, EqDressagePath.SPOT_MISSED)
                    run.ev = run.ev + 1
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

    -- Lateral work: the body's angle and the bend in a section.
    -- run.angleWrong / run.bendWrong say what is off this frame, for the prompt's colour.
    local sec = EqDressagePath.section(run)
    run.angleWrong, run.bendWrong = false, false
    if sec ~= nil and look ~= nil and run.s >= sec.s0 + EqDressagePath.SECTION_GRACE then
        local acc = run.acc[math.min(sec.m, #test.moves)]
        if EqDressagePath.angleOff(run.frame, sec, look.dirX, look.dirZ) > EqDressagePath.ANGLE_FREE then
            acc.angleMs = acc.angleMs + dt
            run.angleWrong = true
        end
        if sec.bend ~= nil and (look.bend or 0) * sec.bend < EqDressagePath.BEND_MIN then
            acc.bendMs = acc.bendMs + dt
            run.bendWrong = true
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
-- The line's dashes by gait (James, 2026-10-30: show where a change is due; lengths alone were
-- hard to tell apart and a canter should look wider apart): DASH metres long, DASH_STEP apart,
-- like the stride. Each gait's dashes start right at its change (EqCourseGlow.pieces breaks).
EqDressagePath.DASH = { walk = 0.2, trot = 0.45, canter = 0.9, halt = 0.2 }
EqDressagePath.DASH_STEP = { walk = 0.6, trot = 1.1, canter = 1.9, halt = 0.6 }


--- The gait asked for at metres s along a test (pure): from the last change or halt before it.
--- @return string walk, trot, canter or halt
function EqDressagePath.gaitAt(test, s)
    local gait = EqDressagePath.PROCEED
    for _, e in ipairs(test.events) do
        if e.s > s then break end
        gait = e.gait or gait
    end
    return gait
end


--- Where the line's dashes start afresh (pure): every change and halt, in order.
function EqDressagePath.breaks(test)
    if test.breaks == nil then
        test.breaks = {}
        for _, e in ipairs(test.events) do table.insert(test.breaks, e.s) end
    end
    return test.breaks
end


--- How much of a movement on the spot is done (pure): 0..1.
function EqDressagePath.spotShare(spot)
    if spot.event.style == "pirouette" then
        return math.max(0, math.min(1, spot.turned / (2 * math.pi - EqDressagePath.SPOT_TURN)))
    end
    return math.min(1, spot.ms / EqDressagePath.SPOT_MS)
end


--- The lateral section the horse is in, or the next one within warning (pure).
--- @return table|nil section { s0, s1, m, kind, hx, hy, bend, drift }, boolean true once in it
function EqDressagePath.section(run)
    local sections = run.test.sections or {}
    while sections[run.sec] ~= nil and sections[run.sec].s1 < run.s do run.sec = run.sec + 1 end
    local sec = sections[run.sec]
    if sec == nil or sec.s0 - run.s > run.warn then return nil, false end
    return sec, run.s >= sec.s0
end


--- How far the horse's body faces off what a section asks (radians, pure).
--- @param dirX number the horse's facing in the world
--- @param dirZ number
function EqDressagePath.angleOff(frame, sec, dirX, dirZ)
    local hx, hy = dirX * frame.vx + dirZ * frame.vz, dirX * frame.ux + dirZ * frame.uz
    local cross = hx * sec.hy - hy * sec.hx
    local dot = hx * sec.hx + hy * sec.hy
    return math.abs(math.atan2(cross, dot))
end


--- Temperament's stickiness (pure): a pull back onto the line this frame (world metres) and,
--- in a lateral section, the world heading (dirX, dirZ) to ease the body towards and how fast.
--- @param run table
--- @param wx number the horse's position
--- @param wz number
--- @param lateral boolean drifting sideways now
--- @param dt number ms
--- @return number dx, number dz, number|nil wantX, number|nil wantZ, number turnRate rad/s
function EqDressagePath.assist(run, wx, wz, lateral, dt)
    if not run.started or run.hold ~= nil or run.back ~= nil or run.spot ~= nil then return 0, 0, nil, nil, 0 end
    local pts, frame = run.test.pts, run.frame
    local x, y = EqDressagePath.toLocal(frame, wx, wz)
    local i = run.i
    local a, b = pts[math.max(1, i - 1)], pts[math.min(#pts, i + 1)]
    -- The nearest point of the line by the horse.
    local px, py = pts[i].x, pts[i].y
    local dx, dy = b.x - a.x, b.y - a.y
    local len2 = dx * dx + dy * dy
    if len2 > 1e-9 then
        local t = math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2))
        px, py = a.x + dx * t, a.y + dy * t
    end
    local sec, inside = EqDressagePath.section(run)
    if not inside then sec = nil end
    local share = EqDressagePath.STICK_PULL * run.temper * ((lateral or sec ~= nil) and 1 or EqDressagePath.STICK_FREE)
    local k = math.min(1, share * dt / 1000)
    local ox, oy = (px - x) * k, (py - y) * k
    local pullX, pullZ = ox * frame.vx + oy * frame.ux, ox * frame.vz + oy * frame.uz
    if sec == nil then return pullX, pullZ, nil, nil, 0 end
    local wantX, wantZ = sec.hx * frame.vx + sec.hy * frame.ux, sec.hx * frame.vz + sec.hy * frame.uz
    return pullX, pullZ, wantX, wantZ, EqDressagePath.STICK_TURN * run.temper
end


function EqDressagePath.upcoming(run)
    local next = run.test.events[run.ev]
    if next == nil or run.hold ~= nil or run.spot ~= nil then return nil end
    local dist = next.s - run.s
    if dist > run.warn then return nil end
    return next, dist
end

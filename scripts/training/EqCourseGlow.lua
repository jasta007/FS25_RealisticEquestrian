--[[
    EqCourseGlow.lua
    The glowing marks over a round's next fence: a soft gold pole at each flag (James,
    2026-10-27: the debug lines poked above the flags and looked one pixel thin), and a
    see-through gold bar between the start and finish lines' poles. Fences get no bar since
    they are judged by the jump itself (James, 2026-10-28). The shapes come from
    placeables/courseGlow/courseGlow.i3d (art/source/course_glow.py), loaded once and cloned
    into pools as needed.

    Each frame of drawing: EqCourseGlow.begin(), then pole() and bar() for what to show, then
    finish(), which hides what this frame did not use. If the file will not load, draw() calls
    return false and EqCourseHooks falls back on debug lines.

    Part of Realistic Equestrian by Jasta007.
]]

EqCourseGlow = {}

local Log = EqLog

EqCourseGlow.FILE = "placeables/courseGlow/courseGlow.i3d"
-- A pole just wider than a flag pole (3.6 cm), and a thin bar (James, 2026-10-27).
EqCourseGlow.POLE_WIDTH = 0.06
EqCourseGlow.BAR_WIDTH = 0.06
-- Nothing drawn for this long (the rider got off): everything hides.
EqCourseGlow.STALE_MS = 300

EqCourseGlow.modDirectory = g_currentModDirectory
EqCourseGlow.templates = nil
EqCourseGlow.failed = false
-- The bar in other colours (glowBar_<colour>), for path guides; gold is the plain bar.
EqCourseGlow.COLOURS = { "green", "lime", "yellow", "orange", "red", "cyan", "white" }
-- A path guide (James, 2026-10-29): pieces SEGMENT metres apart along the path, each GAP short
-- of the next so they don't overlap at the bends (a dashed look).
EqCourseGlow.SEGMENT = 1
EqCourseGlow.GAP = 0.3
EqCourseGlow.PATH_WIDTH = 0.25
EqCourseGlow.PATH_THICK = 0.03
EqCourseGlow.PATH_LIFT = 0.05
-- At most this many pieces a frame for all the paths together.
EqCourseGlow.MAX_PIECES = 600
EqCourseGlow.pools = {}
EqCourseGlow.used = {}
EqCourseGlow.drawnAt = nil


--- @param node number
--- @param name string
--- @return number|nil
local function findNode(node, name)
    if getName(node) == name then return node end
    for i = 0, getNumOfChildren(node) - 1 do
        local found = findNode(getChildAt(node, i), name)
        if found ~= nil then return found end
    end
    return nil
end


--- @return boolean true when the shapes are ready
local function ensureLoaded()
    if EqCourseGlow.templates ~= nil then return true end
    if EqCourseGlow.failed then return false end
    local ok, err = EqLog.try("EqCourseGlow.ensureLoaded", function()
        local root = g_i3DManager:loadI3DFile((EqCourseGlow.modDirectory or "") .. EqCourseGlow.FILE, false, false)
        if root == nil or root == 0 then error("no node") end
        local bar, pole = findNode(root, "glowBar"), findNode(root, "glowPole")
        if bar == nil or pole == nil then error("glowBar or glowPole missing") end
        EqCourseGlow.root = root
        EqCourseGlow.templates = { bar = bar, pole = pole }
        -- Coloured bars from an older file may be missing: those paths stay gold.
        for _, colour in ipairs(EqCourseGlow.COLOURS) do
            EqCourseGlow.templates["bar_" .. colour] = findNode(root, "glowBar_" .. colour) or bar
        end
    end)
    if not ok then
        EqCourseGlow.failed = true
        Log:warning("Course glow unavailable, using lines: %s", tostring(err))
        return false
    end
    Log:info("Course glow loaded")
    return true
end


--- @param kind string "bar", "pole" or "bar_<colour>"
--- @return number node, shown
local function take(kind)
    local used = (EqCourseGlow.used[kind] or 0) + 1
    EqCourseGlow.used[kind] = used
    local pool = EqCourseGlow.pools[kind]
    if pool == nil then
        pool = {}
        EqCourseGlow.pools[kind] = pool
    end
    local node = pool[used]
    if node == nil then
        node = clone(EqCourseGlow.templates[kind], false, false, false)
        link(getRootNode(), node)
        pool[used] = node
    end
    setVisibility(node, true)
    return node
end


function EqCourseGlow.begin()
    for kind in pairs(EqCourseGlow.used) do EqCourseGlow.used[kind] = 0 end
    EqCourseGlow.pieceCount = 0
end


--- A glowing pole standing at x, y, z.
--- @return boolean false when the glow can't be drawn
function EqCourseGlow.pole(x, y, z, height)
    if not ensureLoaded() then return false end
    local node = take("pole")
    setTranslation(node, x, y, z)
    setRotation(node, 0, 0, 0)
    setScale(node, EqCourseGlow.POLE_WIDTH, height, EqCourseGlow.POLE_WIDTH)
    EqCourseGlow.drawnAt = g_time or 0
    return true
end


--- A glowing bar from a to b.
--- @return boolean false when the glow can't be drawn
function EqCourseGlow.bar(ax, ay, az, bx, by, bz)
    if not ensureLoaded() then return false end
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 0.01 then return true end
    local node = take("bar")
    setTranslation(node, ax, ay, az)
    setDirection(node, dx / length, dy / length, dz / length, 0, 1, 0)
    setScale(node, EqCourseGlow.BAR_WIDTH, EqCourseGlow.BAR_WIDTH, length)
    EqCourseGlow.drawnAt = g_time or 0
    return true
end


--- A flat strip from a to b, width across and thick high.
--- @param colour string|nil one of COLOURS, gold when nil
--- @return boolean false when the glow can't be drawn
function EqCourseGlow.strip(ax, ay, az, bx, by, bz, width, thick, colour)
    if not ensureLoaded() then return false end
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 0.01 then return true end
    local node = take(colour ~= nil and EqCourseGlow.templates["bar_" .. colour] ~= nil and "bar_" .. colour or "bar")
    setTranslation(node, ax, ay, az)
    setDirection(node, dx / length, dy / length, dz / length, 0, 1, 0)
    setScale(node, width, thick, length)
    EqCourseGlow.drawnAt = g_time or 0
    return true
end


--- The pieces of a path guide (pure): along points { x, y, z }, a piece every SEGMENT metres,
--- GAP short of the next. Points further than radius from (nearX, nearZ) are left out.
--- @param points table
--- @param from number|nil metres along the path where the first piece starts (keeps pieces
--- still on the ground as the path is cut shorter in front of the horse)
--- @param breaks table|nil sorted metres along the path (same count as from) where the pieces
--- start afresh: a dressage test's changes, so a gait's dashes begin right at its change
--- @param stepAt function|nil function(s) giving the spacing from a break at s on (the
--- dressage line's dashes by gait), SEGMENT when nil
--- @return table pieces { ax, ay, az, bx, by, bz, s = metres along the path where it starts }
function EqCourseGlow.pieces(points, from, nearX, nearZ, radius, breaks, stepAt)
    local list = {}
    local step, gap = EqCourseGlow.SEGMENT, EqCourseGlow.GAP
    local radius2 = radius ~= nil and radius * radius or nil
    local base = from or 0
    breaks = breaks or {}
    -- The cut after metre c: whole steps from the last break (or the start), or the next break.
    local function nextAfter(c)
        local anchor = 0
        for _, b in ipairs(breaks) do
            if b <= c + 1e-9 then anchor = b else break end
        end
        local st = stepAt ~= nil and stepAt(anchor) or step
        local n = anchor + (math.floor((c - anchor) / st + 1e-9) + 1) * st
        for _, b in ipairs(breaks) do
            if b > c + 1e-9 and b < n - 1e-9 then return b end
        end
        return n
    end
    -- Metres along the points, and a point at any of them.
    local at = { 0 }
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        at[i] = at[i - 1] + math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
    end
    local total = at[#points] or 0
    local k = 2
    local function point(d)
        while k < #points and at[k] < d do k = k + 1 end
        while k > 2 and at[k - 1] > d do k = k - 1 end
        local a, b = points[k - 1], points[k]
        local t = at[k] - at[k - 1] > 1e-9 and (d - at[k - 1]) / (at[k] - at[k - 1]) or 0
        t = math.max(0, math.min(1, t))
        return a.x + (b.x - a.x) * t, (a.y or 0) + ((b.y or 0) - (a.y or 0)) * t, a.z + (b.z - a.z) * t
    end
    if #points < 2 then return list end
    local c = nextAfter(base - 1e-6)
    while c - base <= total do
        local n = nextAfter(c)
        local stop = math.min(n, base + total) - gap
        if stop > c + 1e-6 then
            local ax, ay, az = point(c - base)
            local bx, by, bz = point(stop - base)
            if radius2 == nil or (bx - nearX) ^ 2 + (bz - nearZ) ^ 2 <= radius2 then
                table.insert(list, { ax, ay, az, bx, by, bz, s = c })
            end
        end
        c = n
    end
    return list
end


--- A path guide on the ground: flat strips with gaps between them (pieces).
--- @param points table { x, y, z } on the ground
--- @param colour string|function|nil one of COLOURS, gold when nil, or a function(s) giving
--- each piece's colour from the metres along the path where it starts
--- @param from number|nil see pieces
--- @param style table|nil { breaks = see pieces, step = see pieces' stepAt, length = function(s) giving a piece's length
--- (the dressage line's dashes by gait), shape = function(s) giving a world heading (dirX,
--- dirZ) and a bend (-1..1, right positive) for a piece drawn as a horse's body instead }
--- @return boolean false when the glow can't be drawn
function EqCourseGlow.path(points, colour, from, nearX, nearZ, radius, style)
    if not ensureLoaded() then return false end
    style = style or {}
    local lift = EqCourseGlow.PATH_LIFT
    for _, p in ipairs(EqCourseGlow.pieces(points, from, nearX, nearZ, radius, style.breaks, style.step)) do
        if (EqCourseGlow.pieceCount or 0) >= EqCourseGlow.MAX_PIECES then break end
        EqCourseGlow.pieceCount = (EqCourseGlow.pieceCount or 0) + 1
        local c = colour
        if type(colour) == "function" then c = colour(p.s) end
        if style.length ~= nil then p = EqCourseGlow.shorten(p, style.length(p.s)) end
        local dirX, dirZ, bend = nil, nil, 0
        if style.shape ~= nil then dirX, dirZ, bend = style.shape(p.s) end
        local strips = dirX ~= nil and EqCourseGlow.body(p, dirX, dirZ, bend or 0) or { p }
        for _, b in ipairs(strips) do
            EqCourseGlow.strip(b[1], b[2] + lift, b[3], b[4], b[5] + lift, b[6], EqCourseGlow.PATH_WIDTH, EqCourseGlow.PATH_THICK, c)
        end
    end
    return true
end


--- A piece cut to at most length metres from its start (pure).
function EqCourseGlow.shorten(piece, length)
    local dx, dy, dz = piece[4] - piece[1], piece[5] - piece[2], piece[6] - piece[3]
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length == nil or d <= length or d < 1e-9 then return piece end
    local f = length / d
    return { piece[1], piece[2], piece[3], piece[1] + dx * f, piece[2] + dy * f, piece[3] + dz * f, s = piece.s }
end


-- A piece showing a horse's body (James, 2026-10-30: the lateral words were unreadable in the
-- heat of the moment, and a separate head piece too busy): one dash as long as the piece, facing
-- the way the horse should face and centred on it, its front HEAD share turned HEAD_TURN radians
-- to the bend side at full bend, so it reads as one bent dash.
EqCourseGlow.HEAD = 0.35
EqCourseGlow.HEAD_TURN = math.rad(35)


--- The strips for a piece drawn as a horse's body (pure): { ax, ay, az, bx, by, bz } each.
--- @param piece table { ax, ay, az, bx, by, bz }
--- @param dirX number world heading
--- @param dirZ number
--- @param bend number -1..1, right positive (the right of a heading (x, z) is (-z, x))
--- @return table
function EqCourseGlow.body(piece, dirX, dirZ, bend)
    local len = math.sqrt(dirX * dirX + dirZ * dirZ)
    if len < 1e-6 then return { piece } end
    dirX, dirZ = dirX / len, dirZ / len
    local size = math.sqrt((piece[4] - piece[1]) ^ 2 + (piece[6] - piece[3]) ^ 2)
    local mx, my, mz = (piece[1] + piece[4]) / 2, (piece[2] + piece[5]) / 2, (piece[3] + piece[6]) / 2
    local half = size / 2
    local ax, az = mx - dirX * half, mz - dirZ * half
    if bend == 0 then return { { ax, my, az, mx + dirX * half, my, mz + dirZ * half } } end
    local back = size * (1 - EqCourseGlow.HEAD)
    local bx, bz = ax + dirX * back, az + dirZ * back
    local turn = EqCourseGlow.HEAD_TURN * math.max(-1, math.min(1, bend))
    local hx = dirX * math.cos(turn) - dirZ * math.sin(turn)
    local hz = dirZ * math.cos(turn) + dirX * math.sin(turn)
    local head = size * EqCourseGlow.HEAD
    return { { ax, my, az, bx, my, bz }, { bx, my, bz, bx + hx * head, my, bz + hz * head } }
end


-- Symbols on a dressage line (James, 2026-10-30: halts and movements on the spot gave no idea
-- what was coming): a bar across the line for a halt, two for a piaffe, and for a pirouette a
-- ring round the point with an arrowhead the way to turn.
EqCourseGlow.SYMBOL = { bar = 1.4, piaffeBar = 1.0, piaffeGap = 0.35, ring = 1.1, ringPieces = 12, arrow = 0.45 }


--- The strips for a symbol at a point on the line (pure): { ax, ay, az, bx, by, bz } each.
--- @param kind string halt, piaffe or pirouette
--- @param dirX number the line's heading there (world, dir = sin, cos of a heading)
--- @param dirZ number
--- @param turn number|nil pirouette: 1 left (the heading growing), -1 right
--- @return table
function EqCourseGlow.symbol(kind, x, y, z, dirX, dirZ, turn)
    local len = math.sqrt(dirX * dirX + dirZ * dirZ)
    if len < 1e-6 then return {} end
    dirX, dirZ = dirX / len, dirZ / len
    -- The line's right: (-z, x).
    local rx, rz = -dirZ, dirX
    local S = EqCourseGlow.SYMBOL
    local function across(cx, cz, width)
        return { cx - rx * width / 2, y, cz - rz * width / 2, cx + rx * width / 2, y, cz + rz * width / 2 }
    end
    if kind == "halt" then return { across(x, z, S.bar) } end
    if kind == "piaffe" then
        return { across(x - dirX * S.piaffeGap / 2, z - dirZ * S.piaffeGap / 2, S.piaffeBar),
            across(x + dirX * S.piaffeGap / 2, z + dirZ * S.piaffeGap / 2, S.piaffeBar) }
    end
    if kind ~= "pirouette" then return {} end
    turn = turn or 1
    local list = {}
    local a0 = math.atan2(dirX, dirZ)
    local step = 2 * math.pi / S.ringPieces
    local function at(a) return x + math.sin(a) * S.ring, z + math.cos(a) * S.ring end
    -- Round from in front of the horse the way it turns, leaving a gap for the arrowhead.
    for k = 0, S.ringPieces - 2 do
        local ax, az = at(a0 + turn * (k + 0.15) * step)
        local bx, bz = at(a0 + turn * (k + 0.85) * step)
        table.insert(list, { ax, y, az, bx, y, bz })
    end
    local endA = a0 + turn * (S.ringPieces - 1.15) * step
    local tx, tz = at(endA)
    -- The ring's way round there, and the arrowhead's two barbs pointing along it.
    local gx, gz = math.cos(endA) * turn, -math.sin(endA) * turn
    for _, side in ipairs({ 1, -1 }) do
        local c, sn = math.cos(math.rad(150) * side), math.sin(math.rad(150) * side)
        local bx, bz = gx * c - gz * sn, gz * c + gx * sn
        table.insert(list, { tx, y, tz, tx + bx * S.arrow, y, tz + bz * S.arrow })
    end
    return list
end


--- Hide what this frame did not use.
function EqCourseGlow.finish()
    for kind, pool in pairs(EqCourseGlow.pools) do
        for i = (EqCourseGlow.used[kind] or 0) + 1, #pool do setVisibility(pool[i], false) end
    end
end


--- Each frame (from EqCourseHooks.update): hide everything once nothing has been drawn for a while.
function EqCourseGlow.update()
    if EqCourseGlow.drawnAt == nil then return end
    local now = g_time or 0
    if now - EqCourseGlow.drawnAt > EqCourseGlow.STALE_MS or now < EqCourseGlow.drawnAt then
        EqCourseGlow.drawnAt = nil
        EqCourseGlow.begin()
        EqCourseGlow.finish()
    end
end


--- Delete the clones and the loaded file (mission end).
function EqCourseGlow.delete()
    for _, pool in pairs(EqCourseGlow.pools) do
        for _, node in ipairs(pool) do EqLog.try("EqCourseGlow.delete", delete, node) end
    end
    if EqCourseGlow.root ~= nil then EqLog.try("EqCourseGlow.delete", delete, EqCourseGlow.root) end
    EqCourseGlow.pools, EqCourseGlow.used = {}, {}
    EqCourseGlow.templates, EqCourseGlow.root, EqCourseGlow.failed, EqCourseGlow.drawnAt = nil, nil, false, nil
end

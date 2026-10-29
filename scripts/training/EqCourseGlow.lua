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
--- @return table pieces { ax, ay, az, bx, by, bz }
function EqCourseGlow.pieces(points, from, nearX, nearZ, radius)
    local list = {}
    local step, gap = EqCourseGlow.SEGMENT, EqCourseGlow.GAP
    local radius2 = radius ~= nil and radius * radius or nil
    -- Walk the line, cutting it at whole steps from its start.
    local s = 0
    local nextCut = from ~= nil and (math.ceil(from / step - 1e-9) * step - from) or 0
    local cut = nil
    local function at(a, b, t)
        return a.x + (b.x - a.x) * t, (a.y or 0) + ((b.y or 0) - (a.y or 0)) * t, a.z + (b.z - a.z) * t
    end
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
        while d > 1e-6 and nextCut <= s + d do
            local x, y, z = at(a, b, (nextCut - s) / d)
            if cut ~= nil and nextCut - cut.s >= step - 1e-6 then
                -- The piece from the last cut, ending GAP short of this one.
                local f = (step - gap) / step
                local bx, by, bz = cut.x + (x - cut.x) * f, cut.y + (y - cut.y) * f, cut.z + (z - cut.z) * f
                if radius2 == nil or (bx - nearX) ^ 2 + (bz - nearZ) ^ 2 <= radius2 then
                    table.insert(list, { cut.x, cut.y, cut.z, bx, by, bz })
                end
            end
            cut = { x = x, y = y, z = z, s = nextCut }
            nextCut = nextCut + step
        end
        s = s + d
    end
    -- What is left past the last cut, if it is more than a gap.
    local last = points[#points]
    if cut ~= nil and last ~= nil and s - cut.s > gap then
        local f = (s - cut.s - gap) / (s - cut.s)
        local ly = last.y or 0
        table.insert(list, { cut.x, cut.y, cut.z, cut.x + (last.x - cut.x) * f, cut.y + (ly - cut.y) * f, cut.z + (last.z - cut.z) * f })
    end
    return list
end


--- A path guide on the ground: flat strips with gaps between them (pieces).
--- @param points table { x, y, z } on the ground
--- @param colour string|nil one of COLOURS, gold when nil
--- @param from number|nil see pieces
--- @return boolean false when the glow can't be drawn
function EqCourseGlow.path(points, colour, from, nearX, nearZ, radius)
    if not ensureLoaded() then return false end
    local lift = EqCourseGlow.PATH_LIFT
    for _, p in ipairs(EqCourseGlow.pieces(points, from, nearX, nearZ, radius)) do
        if (EqCourseGlow.pieceCount or 0) >= EqCourseGlow.MAX_PIECES then break end
        EqCourseGlow.pieceCount = (EqCourseGlow.pieceCount or 0) + 1
        EqCourseGlow.strip(p[1], p[2] + lift, p[3], p[4], p[5] + lift, p[6], EqCourseGlow.PATH_WIDTH, EqCourseGlow.PATH_THICK, colour)
    end
    return true
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

--[[
    EqCourseGlow.lua
    The glowing marks over a round's next fence: a soft gold pole at each flag and a thicker,
    see-through gold bar between them at the fence height (James, 2026-10-27: the debug lines
    poked above the flags and looked one pixel thin). The shapes come from
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
EqCourseGlow.pools = { bar = {}, pole = {} }
EqCourseGlow.used = { bar = 0, pole = 0 }
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
    end)
    if not ok then
        EqCourseGlow.failed = true
        Log:warning("Course glow unavailable, using lines: %s", tostring(err))
        return false
    end
    Log:info("Course glow loaded")
    return true
end


--- @param kind string "bar" or "pole"
--- @return number node, shown
local function take(kind)
    local used = EqCourseGlow.used[kind] + 1
    EqCourseGlow.used[kind] = used
    local pool = EqCourseGlow.pools[kind]
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
    EqCourseGlow.used.bar, EqCourseGlow.used.pole = 0, 0
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


--- Hide what this frame did not use.
function EqCourseGlow.finish()
    for kind, pool in pairs(EqCourseGlow.pools) do
        for i = EqCourseGlow.used[kind] + 1, #pool do setVisibility(pool[i], false) end
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
    EqCourseGlow.pools, EqCourseGlow.used = { bar = {}, pole = {} }, { bar = 0, pole = 0 }
    EqCourseGlow.templates, EqCourseGlow.root, EqCourseGlow.failed, EqCourseGlow.drawnAt = nil, nil, false, nil
end

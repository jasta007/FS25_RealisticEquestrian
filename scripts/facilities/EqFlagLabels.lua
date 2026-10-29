--[[
    EqFlagLabels.lua
    "L" over every white flag and "R" over every red one, in construction mode and while a course
    is edited, so jumps are placed the right way round: facing a jump, the white flag is on the
    rider's left and the red flag on their right (James, 2026-10-29).

    Drawn as screen text at each flag, never baked into the models, so no i3d changes. Flags are
    the flag fence's posts (EqXcFlags) and any placeable node named "...flagsWhite"/"...flagsRed":
    our show jumps and log piles (eqFlags*), Riding Hall and Equestrian Pack jumps (modernFlags*).

    Part of Realistic Equestrian by Jasta007.
]]

EqFlagLabels = {}

local Log = EqLog

-- Metres over a flag's foot (show jump poles stand 1.7 m, flag fence poles 1.5 m).
EqFlagLabels.LIFT = 2.1
-- Labels further than this from the camera (straight line, height counts) are left out, and
-- they shrink from FULL_SIZE_RANGE out to MIN_SCALE of their size at RANGE: screen text keeps
-- its size however far away, so zoomed out they were giant (James, 2026-10-29).
EqFlagLabels.RANGE = 45
EqFlagLabels.FULL_SIZE_RANGE = 15
EqFlagLabels.MIN_SCALE = 0.5
-- Flags are found again this often while labels show (placed pieces; the piece in the
-- construction brush is found every frame).
EqFlagLabels.SCAN_MS = 500
-- How deep and how many nodes are searched under one placeable for flag nodes.
EqFlagLabels.DEPTH = 6
EqFlagLabels.MAX_NODES = 3000
EqFlagLabels.TEXT_SIZE = 0.03
EqFlagLabels.COLOURS = { white = { 1, 1, 1, 1 }, red = { 0.95, 0.15, 0.12, 1 } }
EqFlagLabels.KEYS = { white = "eq_flagLeft", red = "eq_flagRight" }
EqFlagLabels.FALLBACK = { white = "L", red = "R" }

EqFlagLabels.labels = {}
EqFlagLabels.scannedAt = nil
EqFlagLabels.drawnAt = nil
EqFlagLabels.failed = false
-- Brush kinds whose fields have been logged (to learn where previews keep their nodes).
EqFlagLabels.brushLogged = {}
-- Flag nodes found under each (non fence) placeable, found once: placeables don't change.
EqFlagLabels.cache = setmetatable({}, { __mode = "k" })


--- @param name string|nil a node name
--- @return string|nil "white" or "red" for a jump's flag node
function EqFlagLabels.classify(name)
    if type(name) ~= "string" then return nil end
    local lower = name:lower()
    if string.find(lower, "flagswhite", 1, true) then return "white" end
    if string.find(lower, "flagsred", 1, true) then return "red" end
    return EqXcFlags.classify(name)
end


--- @param colour string "white" or "red"
--- @param getText function|nil key -> text
--- @return string the letter over that flag: the side of the jump it marks
function EqFlagLabels.letter(colour, getText)
    local key = EqFlagLabels.KEYS[colour]
    if key ~= nil and getText ~= nil then
        local ok, text = pcall(getText, key)
        if ok and type(text) == "string" and text ~= "" and not text:find("Missing", 1, true) then return text end
    end
    return EqFlagLabels.FALLBACK[colour] or "?"
end


--- @param flags table list of { colour, x, y, z }
--- @param cx number camera position
--- @param cy number
--- @param cz number
--- @param range number
--- @return table list of { flag, distance } for the flags within range of the camera
function EqFlagLabels.near(flags, cx, cy, cz, range)
    local out = {}
    for _, flag in ipairs(flags) do
        local dx, dy, dz = flag.x - cx, flag.y + EqFlagLabels.LIFT - cy, flag.z - cz
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        if distance <= range then table.insert(out, { flag = flag, distance = distance }) end
    end
    return out
end


--- @param distance number metres from the camera
--- @return number the label's size as a share of TEXT_SIZE: whole up close, smaller further away
function EqFlagLabels.scale(distance)
    if distance <= EqFlagLabels.FULL_SIZE_RANGE then return 1 end
    local t = math.min(1, (distance - EqFlagLabels.FULL_SIZE_RANGE) / (EqFlagLabels.RANGE - EqFlagLabels.FULL_SIZE_RANGE))
    return 1 - t * (1 - EqFlagLabels.MIN_SCALE)
end


--- @return boolean true while the labels should be seen
function EqFlagLabels.wanted()
    return EqXcFlags.wantGuides(EqXcFlags.inConstruction(), EqXcFlags.editing)
end


--- Flag nodes under one placeable's root, depth and count limited.
--- @param root number
--- @param maxDepth number|nil DEPTH when nil
--- @param maxNodes number|nil MAX_NODES when nil
--- @return table list of { node, colour }
local function findFlagNodes(root, maxDepth, maxNodes)
    maxDepth, maxNodes = maxDepth or EqFlagLabels.DEPTH, maxNodes or EqFlagLabels.MAX_NODES
    local found, stack, seen = {}, { { root, 0 } }, 0
    while #stack > 0 and seen < maxNodes do
        local entry = table.remove(stack)
        local node, depth = entry[1], entry[2]
        seen = seen + 1
        local colour = EqFlagLabels.classify(getName(node))
        if colour ~= nil then
            table.insert(found, { node = node, colour = colour })
        elseif depth < maxDepth then
            for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, { getChildAt(node, i), depth + 1 }) end
        end
    end
    return found
end


--- Every flag node on the map. Positions are read each frame, so moved pieces keep their letters.
--- @return table list of { node, colour, offset } (offset: along the node's z to the flag)
function EqFlagLabels.scan()
    local flags = {}
    for _, flag in ipairs((EqXcFlags.scan())) do
        table.insert(flags, { node = flag.node, colour = flag.colour, offset = EqXcFlags.POST / 2 })
    end
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return flags end
    for _, placeable in ipairs(system.placeables) do
        if placeable.rootNode ~= nil and not EqXcFlags.isFlagFence(placeable.configFileName) then
            local nodes = EqFlagLabels.cache[placeable]
            if nodes == nil then
                nodes = findFlagNodes(placeable.rootNode)
                EqFlagLabels.cache[placeable] = nodes
            end
            for _, entry in ipairs(nodes) do table.insert(flags, entry) end
        end
    end
    return flags
end


--- The construction screen's brush, if one is in hand.
--- @return table|nil
function EqFlagLabels.brush()
    local gui = g_gui ~= nil and g_gui.currentGui or nil
    local target = gui ~= nil and gui.target or nil
    return target ~= nil and type(target.brush) == "table" and target.brush or nil
end


--- Flags on the piece being dragged before it is placed: the brush's preview placeable.
--- Searched every frame (a preview is a few nodes) and logs the brush's fields once.
--- @return table list as scan()
function EqFlagLabels.previewFlags()
    local brush = EqFlagLabels.brush()
    if brush == nil then return {} end
    local kind = getmetatable(brush) or brush
    if not EqFlagLabels.brushLogged[kind] then
        EqFlagLabels.brushLogged[kind] = true
        local keys = {}
        for key, value in pairs(brush) do table.insert(keys, tostring(key) .. ":" .. type(value)) end
        table.sort(keys)
        Log:info("EqFlagLabels: brush fields %s", table.concat(keys, " "))
    end
    local flags = {}
    local preview = type(brush.placeable) == "table" and brush.placeable.rootNode or nil
    if preview ~= nil and preview ~= 0 then
        for _, entry in ipairs(findFlagNodes(preview)) do table.insert(flags, entry) end
    end
    return flags
end


--- The flag fence the construction brush is drawing, whose segments may not be in the
--- placeable list yet. Searched like EqXcFlags.scan: fences can hold thousands of nodes.
--- @return table list as scan()
function EqFlagLabels.brushFenceFlags()
    local brush = EqFlagLabels.brush()
    local fence = brush ~= nil and type(brush.fencePlaceable) == "table" and brush.fencePlaceable or nil
    if fence == nil or fence.rootNode == nil or not EqXcFlags.isFlagFence(fence.configFileName) then return {} end
    local flags = {}
    for _, entry in ipairs(findFlagNodes(fence.rootNode, math.huge, EqXcFlags.MAX_NODES)) do
        table.insert(flags, { node = entry.node, colour = entry.colour, offset = EqXcFlags.POST / 2 })
    end
    return flags
end


--- @param entries table list as scan()
--- @return table list of { colour, x, y, z }, each node once
function EqFlagLabels.positions(entries)
    local out, seen = {}, {}
    for _, entry in ipairs(entries) do
        if not seen[entry.node] and (entityExists == nil or entityExists(entry.node)) then
            seen[entry.node] = true
            local x, y, z = localToWorld(entry.node, 0, 0, entry.offset or 0)
            table.insert(out, { colour = entry.colour, x = x, y = y, z = z })
        end
    end
    return out
end


--- @return number|nil, number|nil, number|nil the active camera's position
local function cameraPosition()
    local camera = getCamera ~= nil and getCamera() or nil
    if camera == nil or camera == 0 then return nil, nil, nil end
    return getWorldTranslation(camera)
end


-- GUI elements whose area hides a letter under them (the game draws all text after the menus,
-- whatever order it is drawn in: James, 2026-10-29). Elements nearly the whole screen are
-- backdrops, not panels, and are left out.
EqFlagLabels.COVER_TYPES = { Bitmap = true, Button = true, ThreePartBitmap = true, SmoothList = true, List = true,
    MultiTextOption = true, Slider = true, TextInput = true }
EqFlagLabels.BACKDROP = 0.9
EqFlagLabels.MAX_COVER_NODES = 2000


--- Whether a screen point is inside any of the rectangles. Pure, for the tests.
--- @param rects table { { x, y, w, h } }
--- @return boolean
function EqFlagLabels.covered(rects, x, y)
    for _, r in ipairs(rects) do
        if x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] then return true end
    end
    return false
end


--- The visible menu panels of the open screen (the construction menu), as screen rectangles.
--- @return table rects
function EqFlagLabels.menuRects()
    local rects = {}
    local gui = g_gui ~= nil and g_gui.currentGui or nil
    local root = gui ~= nil and (gui.target or gui) or nil
    if type(root) ~= "table" or type(root.elements) ~= "table" then return rects end
    local stack, count = { root }, 0
    while #stack > 0 and count < EqFlagLabels.MAX_COVER_NODES do
        local element = table.remove(stack)
        count = count + 1
        local visible = element.visible ~= false
        if visible and element.getIsVisible ~= nil then
            local ok, shown = pcall(element.getIsVisible, element)
            visible = not ok or shown ~= false
        end
        if visible then
            local pos, size = element.absPosition, element.absSize
            if element ~= root and EqFlagLabels.COVER_TYPES[element.typeName] and type(pos) == "table" and type(size) == "table"
                and size[1] ~= nil and size[2] ~= nil and size[1] > 0 and size[2] > 0
                and not (size[1] >= EqFlagLabels.BACKDROP and size[2] >= EqFlagLabels.BACKDROP) then
                table.insert(rects, { pos[1], pos[2], size[1], size[2] })
            end
            if type(element.elements) == "table" then
                for _, child in ipairs(element.elements) do table.insert(stack, child) end
            end
        end
    end
    return rects
end


--- Draw the letters. Once per frame however many draws call it.
function EqFlagLabels.draw()
    if EqFlagLabels.failed or not EqFlagLabels.wanted() then
        EqFlagLabels.scannedAt = nil
        return
    end
    local now = g_time or 0
    if EqFlagLabels.drawnAt == now then return end
    EqFlagLabels.drawnAt = now
    local ok, err = EqLog.try("EqFlagLabels.draw", function()
        local due = EqFlagLabels.scannedAt == nil or now - EqFlagLabels.scannedAt >= EqFlagLabels.SCAN_MS or now < EqFlagLabels.scannedAt
        if due then
            EqFlagLabels.labels = EqFlagLabels.scan()
            if EqXcFlags.inConstruction() then
                for _, entry in ipairs(EqFlagLabels.brushFenceFlags()) do table.insert(EqFlagLabels.labels, entry) end
            end
            EqFlagLabels.scannedAt = now
        end
        local cx, cy, cz = cameraPosition()
        if cx == nil then return end
        local entries = {}
        for _, entry in ipairs(EqFlagLabels.labels) do table.insert(entries, entry) end
        if EqXcFlags.inConstruction() then
            for _, entry in ipairs(EqFlagLabels.previewFlags()) do table.insert(entries, entry) end
        end
        local getText = g_i18n ~= nil and function(key) return g_i18n:getText(key) end or nil
        local size = getCorrectTextSize ~= nil and getCorrectTextSize(EqFlagLabels.TEXT_SIZE) or EqFlagLabels.TEXT_SIZE
        local okRects, rects = EqLog.try("EqFlagLabels.menuRects", EqFlagLabels.menuRects)
        if not okRects then rects = {} end
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        for _, entry in ipairs(EqFlagLabels.near(EqFlagLabels.positions(entries), cx, cy, cz, EqFlagLabels.RANGE)) do
            local flag, textSize = entry.flag, size * EqFlagLabels.scale(entry.distance)
            local sx, sy, sz = project(flag.x, flag.y + EqFlagLabels.LIFT, flag.z)
            if sx ~= nil and sx > -0.1 and sx < 1.1 and sy > -0.1 and sy < 1.1 and sz <= 1
                and not EqFlagLabels.covered(rects, sx, sy + textSize * 0.5) then
                local text = EqFlagLabels.letter(flag.colour, getText)
                setTextColor(0, 0, 0, 0.8)
                renderText(sx + 0.0012, sy - 0.0018, textSize, text)
                local c = EqFlagLabels.COLOURS[flag.colour]
                setTextColor(c[1], c[2], c[3], c[4])
                renderText(sx, sy, textSize, text)
            end
        end
        setTextColor(1, 1, 1, 1)
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
    end)
    if not ok then
        EqFlagLabels.failed = true
        Log:warning("Flag L/R labels unavailable: %s", tostring(err))
    end
end


--- Draw from the mission and, in case the world's draw is skipped under it, the construction screen.
--- Before each one's own drawing. The game still draws text after the menus, so letters over a
--- menu panel are left out (EqFlagLabels.menuRects).
--- @param guarded function main.lua's error guard
function EqFlagLabels.install(guarded)
    local function hook(class, label)
        if class == nil or class.draw == nil then return false end
        class.draw = Utils.prependedFunction(class.draw, function()
            if not EqMain.isActive then return end
            guarded(label, EqFlagLabels.draw)
        end)
        return true
    end
    local missionClass = FSBaseMission ~= nil and FSBaseMission.draw ~= nil and FSBaseMission or BaseMission
    local mission = hook(missionClass, "flag labels")
    local construction = hook(ConstructionScreen, "flag labels (construction)")
    Log:info("EqFlagLabels: L/R over jump flags in construction and course editing (mission draw %s, construction draw %s)",
        tostring(mission), tostring(construction))
end

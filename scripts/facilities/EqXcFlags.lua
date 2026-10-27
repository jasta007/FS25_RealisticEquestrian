--[[
    EqXcFlags.lua
    Cross country flags (placeables/xcJumps/courseFlags.xml): one spline fence, placed like the
    base game's pillar fences, whose segment types (N/M) are a white flag, a gold height bar for
    a 0.6, 0.9 or 1.2 m fence, and a red flag (James, 2026-10-27). The player sets white flag, bar,
    red flag across anything they want ridden as a cross country fence, such as a map's logs or a
    table or hedge from any mod. Each red flag pairs with the nearest white flag within MAX_WIDTH,
    the line between them is the fence, and the bar nearest its middle gives its height.

    The bars (nodes "eqXcGuide") show only in construction mode or while a course is edited
    (EqXcFlags.editing); the flags always show. The game keeps every segment of one fence type in
    one placeable, so the flags and bars are found by node name under it.

    Part of Realistic Equestrian by Jasta007.
]]

EqXcFlags = {}

local Log = EqLog

EqXcFlags.XML = "placeables/xcjumps/courseflags%.xml$"
EqXcFlags.GUIDE = "eqXcGuide"
EqXcFlags.FLAG_NODES = { eqXcFlagWhite = "white", eqXcFlagRed = "red" }
EqXcFlags.BAR_NODE = "^eqXcBar(%d+)$"
-- A flag post's length along the fence line (art/source/xc_jumps.py FLAG_POST); the flag stands in its middle.
EqXcFlags.POST = 0.3
-- A pair's flags stand at least this far apart and at most this far (metres).
EqXcFlags.MIN_WIDTH = 1
EqXcFlags.MAX_WIDTH = 15
-- A fence's height comes from a bar this near its middle (metres, past half its width).
EqXcFlags.BAR_REACH = 1.5
-- Flags are checked again this often, to set newly placed bars' visibility.
EqXcFlags.SCAN_MS = 1000
-- Most nodes searched under one fence placeable.
EqXcFlags.MAX_NODES = 20000

-- Set by the course editor: the height bars show while a course is edited.
EqXcFlags.editing = false
EqXcFlags.shown = nil
EqXcFlags.scannedAt = nil


--- @param filename string|nil a placeable's xml filename
--- @return boolean true for the cross country flag fence
function EqXcFlags.isFlagFence(filename)
    if type(filename) ~= "string" then return false end
    return filename:lower():gsub("\\", "/"):match(EqXcFlags.XML) ~= nil
end


--- @param name string|nil a node name
--- @return string|nil "white" or "red" for a flag post
--- @return number|nil the fence height in metres, for a bar panel
function EqXcFlags.classify(name)
    if type(name) ~= "string" then return nil end
    local colour = EqXcFlags.FLAG_NODES[name]
    if colour ~= nil then return colour end
    local cm = name:match(EqXcFlags.BAR_NODE)
    if cm ~= nil then return nil, tonumber(cm) / 100 end
    return nil
end


--- Pair red flags with white ones: nearest pairs first, each flag used once. A fence's height is
--- that of the bar nearest its middle, if one is within BAR_REACH past half its width.
--- @param flags table list of { colour, x, z, ... }
--- @param bars table|nil list of { height, x, z }
--- @return table fences list of { red, white, width, height|nil }, nearest first
function EqXcFlags.pair(flags, bars)
    local candidates = {}
    for _, red in ipairs(flags) do
        if red.colour == "red" then
            for _, white in ipairs(flags) do
                if white.colour == "white" then
                    local width = math.sqrt((red.x - white.x) ^ 2 + (red.z - white.z) ^ 2)
                    if width >= EqXcFlags.MIN_WIDTH and width <= EqXcFlags.MAX_WIDTH then
                        table.insert(candidates, { red = red, white = white, width = width })
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.width < b.width end)
    local used, fences = {}, {}
    for _, fence in ipairs(candidates) do
        if not used[fence.red] and not used[fence.white] then
            used[fence.red], used[fence.white] = true, true
            local mx, mz = (fence.red.x + fence.white.x) / 2, (fence.red.z + fence.white.z) / 2
            local best = fence.width / 2 + EqXcFlags.BAR_REACH
            for _, bar in ipairs(bars or {}) do
                local d = math.sqrt((bar.x - mx) ^ 2 + (bar.z - mz) ^ 2)
                if d <= best then
                    best = d
                    fence.height = bar.height
                end
            end
            table.insert(fences, fence)
        end
    end
    return fences
end


--- @param inConstruction boolean
--- @param editing boolean
--- @return boolean true when the height bars should be seen
function EqXcFlags.wantGuides(inConstruction, editing)
    return inConstruction == true or editing == true
end


--- @return boolean true while the construction screen is open
function EqXcFlags.inConstruction()
    if g_gui == nil then return false end
    if g_gui.currentGuiName == "ConstructionScreen" then return true end
    local gui = g_gui.currentGui
    local target = gui ~= nil and gui.target or nil
    if target == nil or ConstructionScreen == nil or target.isa == nil then return false end
    local ok, isConstruction = pcall(target.isa, target, ConstructionScreen)
    return ok and isConstruction == true
end


--- Every flag, bar and bar guide under the flag fence placeables.
--- @return table flags list of { colour, x, z, node }
--- @return table bars list of { height, x, z, node }
--- @return table guides list of guide nodes
function EqXcFlags.scan()
    local flags, bars, guides = {}, {}, {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return flags, bars, guides end
    for _, placeable in ipairs(system.placeables) do
        if EqXcFlags.isFlagFence(placeable.configFileName) and placeable.rootNode ~= nil then
            local stack, seen = { placeable.rootNode }, 0
            while #stack > 0 and seen < EqXcFlags.MAX_NODES do
                local node = table.remove(stack)
                seen = seen + 1
                local name = getName(node)
                local colour, height = EqXcFlags.classify(name)
                if colour ~= nil then
                    local x, _, z = localToWorld(node, 0, 0, EqXcFlags.POST / 2)
                    table.insert(flags, { colour = colour, x = x, z = z, node = node })
                elseif height ~= nil then
                    -- a bar panel runs along its +z, stretched with the panel: its middle is at z 0.5
                    local x, _, z = localToWorld(node, 0, 0, 0.5)
                    table.insert(bars, { height = height, x = x, z = z, node = node })
                end
                if name == EqXcFlags.GUIDE then
                    table.insert(guides, node)
                else
                    for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
                end
            end
        end
    end
    return flags, bars, guides
end


--- The fences the flags on the map make.
--- @return table see EqXcFlags.pair
function EqXcFlags.fences()
    local flags, bars = EqXcFlags.scan()
    return EqXcFlags.pair(flags, bars)
end


--- Show or hide every height bar.
--- @param shown boolean
--- @return number how many bars
function EqXcFlags.applyGuides(shown)
    local _, _, guides = EqXcFlags.scan()
    for _, node in ipairs(guides) do setVisibility(node, shown) end
    return #guides
end


--- Each frame: follow construction mode and course editing at once, and catch newly placed
--- bars every SCAN_MS.
function EqXcFlags.update()
    local now = g_time or 0
    local shown = EqXcFlags.wantGuides(EqXcFlags.inConstruction(), EqXcFlags.editing)
    local due = EqXcFlags.scannedAt == nil or now - EqXcFlags.scannedAt >= EqXcFlags.SCAN_MS or now < EqXcFlags.scannedAt
    if shown ~= EqXcFlags.shown or due then
        local count = EqXcFlags.applyGuides(shown)
        if shown ~= EqXcFlags.shown and count > 0 then
            Log:debug("EqXcFlags: %d height bar(s) %s", count, shown and "shown" or "hidden")
        end
        EqXcFlags.shown = shown
        EqXcFlags.scannedAt = now
    end
end


--- eqXcFences: the fences the flags make, for testing.
--- @return string
function EqXcFlags.describe()
    local flags, bars = EqXcFlags.scan()
    local fences = EqXcFlags.pair(flags, bars)
    for i, fence in ipairs(fences) do
        print(string.format("  %d: %s fence, %.1f m wide, white at %.0f %.0f, red at %.0f %.0f", i,
            fence.height ~= nil and string.format("%.1f m", fence.height) or "no bar,", fence.width,
            fence.white.x, fence.white.z, fence.red.x, fence.red.z))
    end
    return string.format("%d flag(s) and %d bar panel(s) make %d cross country fence(s); unpaired flags need one of the other colour within %d m.",
        #flags, #bars, #fences, EqXcFlags.MAX_WIDTH)
end


--- @param guarded function main.lua's error guard
function EqXcFlags.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("course flags", EqXcFlags.update)
    end)
end

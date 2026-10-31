--[[
    EqXcFlags.lua
    Cross country flags (placeables/xcJumps/courseFlags.xml): one spline fence, placed like the
    base game's pillar fences, whose segment types (N/M) are a white flag, a gold guide line on the
    ground, and a red flag (James, 2026-10-27). The player sets white flag, line, red flag along
    anything they want ridden as a fence, such as a map's logs or a table or hedge from any mod.
    Each red flag pairs with the nearest white flag within MAX_WIDTH and the line between them is
    where the fence is crossed. The fence is judged by the obstacle itself, never by the guide
    (James, 2026-10-28: a raised bar with collision looked bad and gave false faults).

    The guide lines (nodes "eqXcGuide") show only in construction mode or while a course is
    edited (EqXcFlags.editing); the flags hide outside construction, editing and rounds, and are
    ridden through in rounds (EqXcHide). The game keeps every segment of one fence type in one
    placeable, so the flags and lines are found by node name under it.

    Part of Realistic Equestrian by Jasta007.
]]

EqXcFlags = {}

local Log = EqLog

EqXcFlags.XML = "placeables/xcjumps/courseflags%.xml$"
EqXcFlags.GUIDE = "eqXcGuide"
EqXcFlags.FLAG_NODES = { eqXcFlagWhite = "white", eqXcFlagRed = "red" }
-- A flag post's length along the fence line (art/source/xc_jumps.py FLAG_POST); the flag stands in its middle.
EqXcFlags.POST = 0.3
-- Every flag pole's top above the ground (xc_jumps.py POLE_HEIGHT); the pennant hangs from just
-- under it, PENNANT_TOP down to PENNANT_BOTTOM.
EqXcFlags.POLE_HEIGHT = 1.5
EqXcFlags.PENNANT_TOP = 1.47
EqXcFlags.PENNANT_BOTTOM = 1.17
-- A pair's flags stand at least this far apart and at most this far (metres).
EqXcFlags.MIN_WIDTH = 1
EqXcFlags.MAX_WIDTH = 15
-- Flags are checked again this often, to set newly placed guide lines' visibility.
EqXcFlags.SCAN_MS = 1000
-- Most nodes searched under one fence placeable.
EqXcFlags.MAX_NODES = 20000

-- Set by the course editor: the guide lines show while a course is edited.
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
function EqXcFlags.classify(name)
    if type(name) ~= "string" then return nil end
    return EqXcFlags.FLAG_NODES[name]
end


--- Pair red flags with white ones: nearest pairs first, each flag used once.
--- @param flags table list of { colour, x, z, ... }
--- @return table fences list of { red, white, width, poleHeight }, nearest first
function EqXcFlags.pair(flags)
    local candidates = {}
    for _, red in ipairs(flags) do
        if red.colour == "red" then
            for _, white in ipairs(flags) do
                if white.colour == "white" then
                    local width = math.sqrt((red.x - white.x) ^ 2 + (red.z - white.z) ^ 2)
                    if width >= EqXcFlags.MIN_WIDTH and width <= EqXcFlags.MAX_WIDTH then
                        table.insert(candidates, { red = red, white = white, width = width, poleHeight = EqXcFlags.POLE_HEIGHT })
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
            table.insert(fences, fence)
        end
    end
    return fences
end


--- @param inConstruction boolean
--- @param editing boolean
--- @return boolean true when the guide lines should be seen
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
    local ok, isConstruction = EqLog.try("EqXcFlags.inConstruction isa", target.isa, target, ConstructionScreen)
    return ok and isConstruction == true
end


--- Every flag and guide line under the flag fence placeables.
--- @return table flags list of { colour, x, z, node }
--- @return table guides list of guide nodes
function EqXcFlags.scan()
    local flags, guides = {}, {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return flags, guides end
    for _, placeable in ipairs(system.placeables) do
        if EqXcFlags.isFlagFence(placeable.configFileName) and placeable.rootNode ~= nil then
            local stack, seen = { placeable.rootNode }, 0
            while #stack > 0 and seen < EqXcFlags.MAX_NODES do
                local node = table.remove(stack)
                seen = seen + 1
                local name = getName(node)
                local colour = EqXcFlags.classify(name)
                if colour ~= nil then
                    local x, _, z = localToWorld(node, 0, 0, EqXcFlags.POST / 2)
                    table.insert(flags, { colour = colour, x = x, z = z, node = node })
                end
                if name == EqXcFlags.GUIDE then
                    table.insert(guides, node)
                else
                    for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
                end
            end
        end
    end
    return flags, guides
end


--- The fences the flags on the map make.
--- @return table see EqXcFlags.pair
function EqXcFlags.fences()
    return EqXcFlags.pair((EqXcFlags.scan()))
end


--- Show or hide every guide line.
--- @param shown boolean
--- @return number how many lines
function EqXcFlags.applyGuides(shown)
    local _, guides = EqXcFlags.scan()
    for _, node in ipairs(guides) do setVisibility(node, shown) end
    return #guides
end


--- Each frame: follow construction mode and course editing at once, and catch newly placed
--- guide lines every SCAN_MS.
function EqXcFlags.update()
    local now = g_time or 0
    -- Riding with the HUD hidden (filming): the guide lines go too. Construction keeps them.
    local editing = EqXcFlags.editing and not EqTrainingHud.gameHudHidden()
    local shown = EqXcFlags.wantGuides(EqXcFlags.inConstruction(), editing)
    local due = EqXcFlags.scannedAt == nil or now - EqXcFlags.scannedAt >= EqXcFlags.SCAN_MS or now < EqXcFlags.scannedAt
    if shown ~= EqXcFlags.shown or due then
        local count = EqXcFlags.applyGuides(shown)
        if shown ~= EqXcFlags.shown and count > 0 then
            Log:debug("EqXcFlags: %d guide line(s) %s", count, shown and "shown" or "hidden")
        end
        EqXcFlags.shown = shown
        EqXcFlags.scannedAt = now
    end
end


--- eqXcFences: the fences the flags make, for testing.
--- @return string
function EqXcFlags.describe()
    local flags = EqXcFlags.scan()
    local fences = EqXcFlags.pair(flags)
    for i, fence in ipairs(fences) do
        print(string.format("  %d: fence %.1f m wide, white at %.0f %.0f, red at %.0f %.0f", i, fence.width,
            fence.white.x, fence.white.z, fence.red.x, fence.red.z))
    end
    return string.format("%d flag(s) make %d cross country fence(s); unpaired flags need one of the other colour within %d m.",
        #flags, #fences, EqXcFlags.MAX_WIDTH)
end


--- @param guarded function main.lua's error guard
function EqXcFlags.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("course flags", EqXcFlags.update)
    end)
end

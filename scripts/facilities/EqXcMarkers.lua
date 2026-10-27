--[[
    EqXcMarkers.lua
    Cross country fence markers (placeables/xcJumps/xcFenceMarker*): a fence face with no fence,
    put across anything the player wants ridden as a cross country fence, such as a map's logs, a
    bank they landscaped or another mod's prop (James, 2026-10-27). They are "xcFence" facilities,
    and their "eqFlagsRed" and "eqFlagsWhite" nodes mark the jump's two ends, like a real fence's.

    The gold rails and flags (the node "eqXcMarkerVisual") show in construction mode, so markers
    can be placed, moved and sold, and while a course is being edited (EqXcMarkers.editing), and
    are hidden the rest of the time. They have no collision.

    Part of Realistic Equestrian by Jasta007.
]]

EqXcMarkers = {}

local Log = EqLog

EqXcMarkers.XML = "placeables/xcjumps/xcfencemarker"
EqXcMarkers.VISUAL = "eqXcMarkerVisual"
-- Markers are checked again this often, to hide newly loaded ones.
EqXcMarkers.SCAN_MS = 1000
-- How deep under a marker's root node we look for its visual node.
EqXcMarkers.VISUAL_DEPTH = 3

-- Set by the course editor: markers show while a course is edited.
EqXcMarkers.editing = false
EqXcMarkers.shown = nil
EqXcMarkers.scannedAt = nil


--- @param filename string|nil a placeable's xml filename
--- @return boolean true for one of our fence markers
function EqXcMarkers.isMarkerXml(filename)
    if type(filename) ~= "string" then return false end
    local lower = filename:lower():gsub("\\", "/")
    return lower:find(EqXcMarkers.XML, 1, true) ~= nil and lower:sub(-4) == ".xml"
end


--- @param inConstruction boolean
--- @param editing boolean
--- @return boolean true when markers should be seen
function EqXcMarkers.wantShown(inConstruction, editing)
    return inConstruction == true or editing == true
end


--- @return boolean true while the construction screen is open
function EqXcMarkers.inConstruction()
    if g_gui == nil then return false end
    if g_gui.currentGuiName == "ConstructionScreen" then return true end
    local gui = g_gui.currentGui
    local target = gui ~= nil and gui.target or nil
    if target == nil or ConstructionScreen == nil or target.isa == nil then return false end
    local ok, isConstruction = pcall(target.isa, target, ConstructionScreen)
    return ok and isConstruction == true
end


--- @param node number
--- @return number|nil the marker's visual node
local function findVisual(node)
    local stack = { { node, 0 } }
    while #stack > 0 do
        local entry = table.remove(stack)
        local current, depth = entry[1], entry[2]
        if getName(current) == EqXcMarkers.VISUAL then return current end
        if depth < EqXcMarkers.VISUAL_DEPTH then
            for i = 0, getNumOfChildren(current) - 1 do table.insert(stack, { getChildAt(current, i), depth + 1 }) end
        end
    end
    return nil
end


--- Show or hide every marker that isn't already that way.
--- @param shown boolean
--- @return number how many changed
function EqXcMarkers.apply(shown)
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return 0 end
    local changed = 0
    for _, placeable in ipairs(system.placeables) do
        if placeable.rootNode ~= nil and EqXcMarkers.isMarkerXml(placeable.configFileName) then
            if placeable.eqXcVisual == nil then placeable.eqXcVisual = findVisual(placeable.rootNode) or false end
            if placeable.eqXcVisual and placeable.eqXcShown ~= shown then
                setVisibility(placeable.eqXcVisual, shown)
                placeable.eqXcShown = shown
                changed = changed + 1
            end
        end
    end
    return changed
end


--- Each frame: follow construction mode and course editing at once, and catch newly loaded
--- markers every SCAN_MS.
function EqXcMarkers.update()
    local now = g_time or 0
    local shown = EqXcMarkers.wantShown(EqXcMarkers.inConstruction(), EqXcMarkers.editing)
    local due = EqXcMarkers.scannedAt == nil or now - EqXcMarkers.scannedAt >= EqXcMarkers.SCAN_MS or now < EqXcMarkers.scannedAt
    if shown ~= EqXcMarkers.shown or due then
        local changed = EqXcMarkers.apply(shown)
        if shown ~= EqXcMarkers.shown and changed > 0 then
            Log:debug("EqXcMarkers: %d fence marker(s) %s", changed, shown and "shown" or "hidden")
        end
        EqXcMarkers.shown = shown
        EqXcMarkers.scannedAt = now
    end
end


--- @param guarded function main.lua's error guard
function EqXcMarkers.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("fence markers", EqXcMarkers.update)
    end)
end

--[[
    EqXcFlags.lua
    Cross country flags (placeables/xcJumps/courseFlag<Red|White><cm>): the player sets a red and a
    white flag either side of anything they want ridden as a cross country fence, such as a map's
    logs or a table or hedge from any mod (James, 2026-10-27). Each red flag pairs with the nearest
    white flag of the same height within MAX_WIDTH, and the line between them is the fence.

    Each flag is made for a fence height (60, 90 or 120 cm, in its name) and carries a gold bar at
    that height, to line it up with the fence top. The bar (node "eqXcGuide") shows only in
    construction mode or while a course is edited (EqXcFlags.editing); the flags always show. They
    have no collision.

    Part of Realistic Equestrian by Jasta007.
]]

EqXcFlags = {}

local Log = EqLog

EqXcFlags.XML = "placeables/xcjumps/courseflag(%a+)(%d+)%.xml$"
EqXcFlags.GUIDE = "eqXcGuide"
-- A pair's flags stand at least this far apart and at most this far (metres).
EqXcFlags.MIN_WIDTH = 1
EqXcFlags.MAX_WIDTH = 15
-- Flags are checked again this often, to set newly placed ones' guide.
EqXcFlags.SCAN_MS = 1000
EqXcFlags.GUIDE_DEPTH = 3

-- Set by the course editor: the height guides show while a course is edited.
EqXcFlags.editing = false
EqXcFlags.shown = nil
EqXcFlags.scannedAt = nil


--- @param filename string|nil a placeable's xml filename
--- @return string|nil colour "red" or "white"
--- @return number|nil the fence height it is made for, in metres
function EqXcFlags.parseXml(filename)
    if type(filename) ~= "string" then return nil end
    local colour, cm = filename:lower():gsub("\\", "/"):match(EqXcFlags.XML)
    if (colour ~= "red" and colour ~= "white") or cm == nil then return nil end
    return colour, tonumber(cm) / 100
end


--- Pair red flags with white ones: nearest pairs first, each flag used once, same height only.
--- @param flags table list of { colour, height, x, z, ... }
--- @return table fences list of { red, white, width, height }, nearest first
function EqXcFlags.pair(flags)
    local candidates = {}
    for _, red in ipairs(flags) do
        if red.colour == "red" then
            for _, white in ipairs(flags) do
                if white.colour == "white" and math.abs((white.height or 0) - (red.height or 0)) < 0.01 then
                    local width = math.sqrt((red.x - white.x) ^ 2 + (red.z - white.z) ^ 2)
                    if width >= EqXcFlags.MIN_WIDTH and width <= EqXcFlags.MAX_WIDTH then
                        table.insert(candidates, { red = red, white = white, width = width, height = red.height })
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
--- @return boolean true when the height guides should be seen
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


--- @param node number
--- @return number|nil the flag's guide node
local function findGuide(node)
    local stack = { { node, 0 } }
    while #stack > 0 do
        local entry = table.remove(stack)
        local current, depth = entry[1], entry[2]
        if getName(current) == EqXcFlags.GUIDE then return current end
        if depth < EqXcFlags.GUIDE_DEPTH then
            for i = 0, getNumOfChildren(current) - 1 do table.insert(stack, { getChildAt(current, i), depth + 1 }) end
        end
    end
    return nil
end


--- Every flag on the map.
--- @return table list of { colour, height, x, z, node, placeable }
function EqXcFlags.list()
    local list = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return list end
    for _, placeable in ipairs(system.placeables) do
        local colour, height = EqXcFlags.parseXml(placeable.configFileName)
        if colour ~= nil and placeable.rootNode ~= nil then
            local x, _, z = getWorldTranslation(placeable.rootNode)
            table.insert(list, { colour = colour, height = height, x = x, z = z, node = placeable.rootNode, placeable = placeable })
        end
    end
    return list
end


--- The fences the flags on the map make.
--- @return table see EqXcFlags.pair
function EqXcFlags.fences()
    return EqXcFlags.pair(EqXcFlags.list())
end


--- Show or hide every flag's height guide that isn't already that way.
--- @param shown boolean
--- @return number how many changed
function EqXcFlags.applyGuides(shown)
    local changed = 0
    for _, flag in ipairs(EqXcFlags.list()) do
        local placeable = flag.placeable
        if placeable.eqXcGuide == nil then placeable.eqXcGuide = findGuide(placeable.rootNode) or false end
        if placeable.eqXcGuide and placeable.eqXcGuideShown ~= shown then
            setVisibility(placeable.eqXcGuide, shown)
            placeable.eqXcGuideShown = shown
            changed = changed + 1
        end
    end
    return changed
end


--- Each frame: follow construction mode and course editing at once, and catch newly loaded
--- flags every SCAN_MS.
function EqXcFlags.update()
    local now = g_time or 0
    local shown = EqXcFlags.wantGuides(EqXcFlags.inConstruction(), EqXcFlags.editing)
    local due = EqXcFlags.scannedAt == nil or now - EqXcFlags.scannedAt >= EqXcFlags.SCAN_MS or now < EqXcFlags.scannedAt
    if shown ~= EqXcFlags.shown or due then
        local changed = EqXcFlags.applyGuides(shown)
        if shown ~= EqXcFlags.shown and changed > 0 then
            Log:debug("EqXcFlags: %d height guide(s) %s", changed, shown and "shown" or "hidden")
        end
        EqXcFlags.shown = shown
        EqXcFlags.scannedAt = now
    end
end


--- eqXcFences: the fences the flags make, for testing.
--- @return string
function EqXcFlags.describe()
    local flags = EqXcFlags.list()
    local fences = EqXcFlags.pair(flags)
    for i, fence in ipairs(fences) do
        print(string.format("  %d: %.1f m fence, %.1f m wide, red at %.0f %.0f, white at %.0f %.0f", i, fence.height,
            fence.width, fence.red.x, fence.red.z, fence.white.x, fence.white.z))
    end
    return string.format("%d flag(s) make %d cross country fence(s); unpaired flags need a flag of the other colour and the same height within %d m.",
        #flags, #fences, EqXcFlags.MAX_WIDTH)
end


--- @param guarded function main.lua's error guard
function EqXcFlags.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("course flags", EqXcFlags.update)
    end)
end

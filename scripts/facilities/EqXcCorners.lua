--[[
    EqXcCorners.lua
    Our two cross country corners (placeables/xcJumps/xcCorner*.xml) have a Corner choice in the
    shop (James, 2026-10-29: "a customisation option to make them left or right, just switch the
    white and red flags"): Point right keeps the red flag at the point, Point left swaps the two
    flags so the corner is ridden the other way round.

    The flags are the transform groups "eqFlagsRed" and "eqFlagsWhite" (each holding its flag's
    shape) at +x and -x. Swapping moves each to the other's place, turned round so its pennant
    still flies outwards. The course recorder and the flag letters read the groups, so nothing
    else changes. The game never called PlaceableConfigurationItem.onPostLoad for this choice
    (James, 2026-10-29: Point left did nothing), so the placed corners and the construction
    brush's preview are looked over every second instead, and again before the course lists its
    fences.

    Part of Realistic Equestrian by Jasta007.
]]

EqXcCorners = {}

local Log = EqLog

EqXcCorners.CONFIG = "eqCornerSide"
EqXcCorners.RIGHT = 1
EqXcCorners.LEFT = 2


--- Whether a placeable xml is one of our corners. Pure.
--- @param configFileName string|nil
--- @return boolean
function EqXcCorners.isCorner(configFileName)
    if type(configFileName) ~= "string" then return false end
    local path = string.lower(string.gsub(configFileName, "\\", "/"))
    return string.find(path, "fs25_realisticequestrian/placeables/xcjumps/xccorner", 1, true) ~= nil
end


--- Where the flags go for a Corner choice: the red flag's x and turn, the white flag's. Pure.
--- @param side number|nil the configuration's index (nil: Point right)
--- @param half number distance of either flag from the middle
--- @return number redX, number redRy, number whiteX, number whiteRy
function EqXcCorners.flagPlaces(side, half)
    half = math.abs(half)
    if side == EqXcCorners.LEFT then
        return -half, math.pi, half, math.pi
    end
    return half, 0, -half, 0
end


--- Register the Corner choice before the store items load.
function EqXcCorners.registerConfiguration()
    local manager = g_placeableConfigurationManager
    if manager == nil or manager.addConfigurationType == nil or PlaceableConfigurationItem == nil then
        Log:warning("EqXcCorners: no placeable configurations, corners keep the red flag at the point")
        return
    end
    if manager.configurations == nil or manager.configurations[EqXcCorners.CONFIG] == nil then
        local title = "Corner"
        if g_i18n ~= nil and g_i18n:hasText("eq_config_corner") then title = g_i18n:getText("eq_config_corner") end
        manager:addConfigurationType(EqXcCorners.CONFIG, title, EqXcCorners.CONFIG, PlaceableConfigurationItem)
    end
end


--- The flag groups right under a placeable's root.
local function flagGroups(root)
    local red, white
    for i = 0, getNumOfChildren(root) - 1 do
        local child = getChildAt(root, i)
        local name = getName(child)
        if name == "eqFlagsRed" then red = child elseif name == "eqFlagsWhite" then white = child end
    end
    return red, white
end


--- Put a corner's flags where its Corner choice wants them.
--- @param placeable table
--- @return boolean true when the flags moved
function EqXcCorners.apply(placeable)
    if placeable == nil or placeable.rootNode == nil or not EqXcCorners.isCorner(placeable.configFileName) then return false end
    local side = placeable.configurations ~= nil and placeable.configurations[EqXcCorners.CONFIG] or nil
    if placeable.eqCornerSide == side then return false end
    local red, white = flagGroups(placeable.rootNode)
    if red == nil or white == nil then return false end
    placeable.eqCornerSide = side
    local rx, ry, rz = getTranslation(red)
    local redX, redRy, whiteX, whiteRy = EqXcCorners.flagPlaces(side, rx)
    local _, wy, wz = getTranslation(white)
    setTranslation(red, redX, ry, rz)
    setRotation(red, 0, redRy, 0)
    setTranslation(white, whiteX, wy, wz)
    setRotation(white, 0, whiteRy, 0)
    return true
end


EqXcCorners.SCAN_MS = 1000


--- Put every placed corner's flags, and the one on the construction brush, where they belong.
function EqXcCorners.update()
    local now = g_time or 0
    if EqXcCorners.scannedAt ~= nil and now - EqXcCorners.scannedAt < EqXcCorners.SCAN_MS then return end
    EqXcCorners.scannedAt = now
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system ~= nil and system.placeables ~= nil then
        for _, placeable in ipairs(system.placeables) do EqXcCorners.apply(placeable) end
    end
    local gui = g_gui ~= nil and g_gui.currentGui or nil
    local target = gui ~= nil and gui.target or nil
    local brush = type(target) == "table" and target.brush or nil
    if type(brush) == "table" and type(brush.placeable) == "table" then EqXcCorners.apply(brush.placeable) end
end


--- @param guarded function main.lua's error guard
function EqXcCorners.install(guarded)
    guarded("corner configuration", EqXcCorners.registerConfiguration)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("corner flags", EqXcCorners.update)
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        EqXcCorners.scannedAt = nil
    end)
end

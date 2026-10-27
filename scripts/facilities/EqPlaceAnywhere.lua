--[[
    EqPlaceAnywhere.lua
    The cross country pieces (placeables/xcJumps/: flags, log piles, drop walls) can be placed on
    land the farm doesn't own, so a course can cross the whole map (James, 2026-10-27). Everything
    else keeps the base game's land rule.

    The construction brushes ask ConstructionBrush.verifyAccess before placing; for our pieces a
    land ownership error is let through, as FS25_paintAndTerraformAnywhere does for landscaping.
    Other errors (store and spawn places, restricted zones, blocked placement) still stop it.
    The error names aren't documented, so any ConstructionBrush.ERROR whose name mentions
    farmland or owned land counts; they are logged once.

    Part of Realistic Equestrian by Jasta007.
]]

EqPlaceAnywhere = {}

local Log = EqLog

EqPlaceAnywhere.XML = "placeables/xcjumps/[^/]+%.xml$"
EqPlaceAnywhere.ERROR_WORDS = { "FARMLAND", "OWNED" }


--- @param filename string|nil a store item's xml filename
--- @return boolean true for one of our cross country pieces
function EqPlaceAnywhere.isOurs(filename)
    if type(filename) ~= "string" then return false end
    local path = filename:lower():gsub("\\", "/")
    return path:find("fs25_realisticequestrian", 1, true) ~= nil and path:match(EqPlaceAnywhere.XML) ~= nil
end


--- @param errors table|nil ConstructionBrush.ERROR (name -> code)
--- @return table code -> name for the land ownership errors
function EqPlaceAnywhere.landErrors(errors)
    local codes = {}
    for name, code in pairs(errors or {}) do
        if type(name) == "string" then
            for _, word in ipairs(EqPlaceAnywhere.ERROR_WORDS) do
                if name:upper():find(word, 1, true) then
                    codes[code] = name
                    break
                end
            end
        end
    end
    return codes
end


--- @param brush table a construction brush
--- @return string|nil the xml filename of what it places
function EqPlaceAnywhere.brushXml(brush)
    local item = brush ~= nil and (brush.storeItem or (brush.placeable ~= nil and brush.placeable.storeItem)) or nil
    if item ~= nil then return item.xmlFilename end
    local fence = brush ~= nil and brush.fencePlaceable or nil
    return fence ~= nil and fence.configFileName or nil
end


--- @param guarded function main.lua's error guard
function EqPlaceAnywhere.install(guarded)
    if ConstructionBrush == nil or ConstructionBrush.verifyAccess == nil then
        Log:info("EqPlaceAnywhere: no ConstructionBrush.verifyAccess, cross country pieces keep the land rule")
        return
    end
    local land = EqPlaceAnywhere.landErrors(ConstructionBrush.ERROR)
    local names = {}
    for _, name in pairs(land) do table.insert(names, name) end
    Log:info("EqPlaceAnywhere: cross country pieces skip %s", #names > 0 and table.concat(names, ", ") or "nothing (no land errors found)")
    ConstructionBrush.verifyAccess = Utils.overwrittenFunction(ConstructionBrush.verifyAccess, function(self, superFunc, ...)
        local result = superFunc(self, ...)
        if result ~= nil and land[result] ~= nil then
            local ours = false
            guarded("place anywhere", function() ours = EqPlaceAnywhere.isOurs(EqPlaceAnywhere.brushXml(self)) end)
            if ours then return nil end
        end
        return result
    end)
end

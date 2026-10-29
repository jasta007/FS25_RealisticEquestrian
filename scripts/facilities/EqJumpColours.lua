--[[
    EqJumpColours.lua
    Our show jumps (placeables/showJumps/) offer two colour options in the shop (James,
    2026-10-29: "a colour picker as part of the customization panel"): the pole colour, which
    also paints the stand tops and trim, and the wing colour. Their painted shapes use the base
    game's vehicle shader; this sets its colorScale on the shapes named "eqPaint" and
    "eqWingPaint" from the option bought.

    The options are plain named configurations (a colour configuration's picker took no input in
    the build menu). Their xml lists COLOURS from art/source/show_jumps.py, in the same order as LIST here: the
    option's index is all that is read back. A jump placed before these options existed has none
    and keeps the colours its i3d gives it.

    Part of Realistic Equestrian by Jasta007.
]]

EqJumpColours = {}

local Log = EqLog

-- Same order as COLOURS in art/source/show_jumps.py (linear colours, as the shader takes them).
EqJumpColours.LIST = {
    { "white", 0.80, 0.80, 0.78 },
    { "cream", 0.72, 0.62, 0.42 },
    { "red", 0.55, 0.02, 0.02 },
    { "burgundy", 0.22, 0.01, 0.02 },
    { "orange", 0.80, 0.22, 0.02 },
    { "yellow", 0.85, 0.60, 0.03 },
    { "lime", 0.30, 0.55, 0.04 },
    { "green", 0.04, 0.30, 0.06 },
    { "darkGreen", 0.01, 0.09, 0.03 },
    { "skyBlue", 0.15, 0.42, 0.75 },
    { "blue", 0.02, 0.10, 0.50 },
    { "navy", 0.005, 0.02, 0.10 },
    { "purple", 0.18, 0.04, 0.42 },
    { "pink", 0.80, 0.22, 0.38 },
    { "grey", 0.20, 0.20, 0.20 },
    { "black", 0.015, 0.015, 0.015 },
}

-- configuration name -> the shapes it paints, and its title's text
EqJumpColours.CONFIGS = {
    { name = "eqPoleColour", node = "eqPaint", title = "eq_config_poleColour", fallback = "Colour" },
    { name = "eqWingColour", node = "eqWingPaint", title = "eq_config_wingColour", fallback = "Wing colour" },
}
EqJumpColours.PARAMETER = "colorScale"
-- How deep under a placeable's root the painted shapes are looked for (poles' are three down).
EqJumpColours.DEPTH = 4


--- The colour of an option. Pure, for the tests.
--- @param index number|nil the configuration's index
--- @return table|nil { r, g, b }
function EqJumpColours.colour(index)
    local entry = type(index) == "number" and EqJumpColours.LIST[index] or nil
    if entry == nil then return nil end
    return { entry[2], entry[3], entry[4] }
end


--- What a jump's options paint, as "name=index" pairs: the same key means nothing changed. Pure.
--- @param configurations table|nil
--- @return string
function EqJumpColours.key(configurations)
    local parts = {}
    for _, config in ipairs(EqJumpColours.CONFIGS) do
        local index = type(configurations) == "table" and configurations[config.name] or nil
        table.insert(parts, config.name .. "=" .. tostring(index))
    end
    return table.concat(parts, ",")
end


--- Register the options before the store items load.
function EqJumpColours.registerConfiguration()
    local manager = g_placeableConfigurationManager
    if manager == nil or manager.addConfigurationType == nil then
        Log:warning("EqJumpColours: no placeable configurations, show jumps keep their colours")
        return
    end
    -- Plain named options, not colour swatches: as colour configurations the build menu opened a
    -- colour picker that took no clicks or keys (James, 2026-10-29), so the colours are listed by name.
    local itemClass = PlaceableConfigurationItem
    if itemClass == nil then return end
    for _, config in ipairs(EqJumpColours.CONFIGS) do
        if manager.configurations == nil or manager.configurations[config.name] == nil then
            local title = config.fallback
            if g_i18n ~= nil and g_i18n:hasText(config.title) then title = g_i18n:getText(config.title) end
            manager:addConfigurationType(config.name, title, config.name, itemClass)
        end
    end
end


--- The shapes under a node with a name.
local function shapesNamed(root, name)
    local found, stack = {}, { { root, 0 } }
    while #stack > 0 do
        local entry = table.remove(stack)
        local node, depth = entry[1], entry[2]
        if getName(node) == name then table.insert(found, node) end
        if depth < EqJumpColours.DEPTH then
            for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, { getChildAt(node, i), depth + 1 }) end
        end
    end
    return found
end


--- Paint one of our jumps in the colours bought (once per change).
--- @param placeable table
function EqJumpColours.apply(placeable)
    if placeable == nil or placeable.rootNode == nil or not EqPoles.isOurs(placeable.configFileName) then return end
    local key = EqJumpColours.key(placeable.configurations)
    if placeable.eqColourKey == key then return end
    placeable.eqColourKey = key
    if setShaderParameter == nil then return end
    for _, config in ipairs(EqJumpColours.CONFIGS) do
        local colour = EqJumpColours.colour(placeable.configurations ~= nil and placeable.configurations[config.name] or nil)
        if colour ~= nil then
            for _, node in ipairs(shapesNamed(placeable.rootNode, config.node)) do
                if getHasShaderParameter == nil or getHasShaderParameter(node, EqJumpColours.PARAMETER) then
                    local w = 0
                    if getShaderParameter ~= nil then
                        local _, _, _, current = getShaderParameter(node, EqJumpColours.PARAMETER)
                        w = current or 0
                    end
                    setShaderParameter(node, EqJumpColours.PARAMETER, colour[1], colour[2], colour[3], w, false)
                end
            end
        end
    end
end


--- @param guarded function main.lua's error guard
function EqJumpColours.install(guarded)
    guarded("show jump colour configuration", EqJumpColours.registerConfiguration)
    -- Paint a jump as its colour option loads: in the shop's preview as well as placed ones.
    -- EqPoles.scan paints placed jumps too, in case this event never comes.
    if PlaceableConfigurationItem ~= nil and PlaceableConfigurationItem.onPostLoad ~= nil then
        PlaceableConfigurationItem.onPostLoad = Utils.appendedFunction(PlaceableConfigurationItem.onPostLoad,
            function(item, placeable)
                if not EqMain.isActive or type(placeable) ~= "table" or type(item) ~= "table" then return end
                if item.configName ~= "eqPoleColour" and item.configName ~= "eqWingColour" then return end
                guarded("show jump colours", function() EqJumpColours.apply(placeable) end)
            end)
    end
end

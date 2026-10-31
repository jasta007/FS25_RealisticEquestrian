--[[
    EqAttire.lua
    A dressage outfit in the player's wardrobe (James, 2026-10-31): white breeches, black riding
    gloves, a plain dark jacket with a white shirt and black boots.

    FS25 has no modDesc entry for wardrobe items, so this adds them the way wardrobe mods do:
    data/attire.xml lists base-game items with our own colours, read with the game's own
    PlayerStyleItem and added to the female and male player styles' configs. The items reuse the
    game's meshes ($dataS paths), so nothing of the game's is shipped.

    Two items need more than colours. The tweed jacket has its check painted into its diffuse
    map, and the Chelsea boots have their brown baked in with no colour mask. An item's eqDiffuse
    names one of our flat textures (art/source/attire_textures.py), swapped onto its shapes'
    materials each time a player model is dressed from its style.

    Part of Realistic Equestrian by Jasta007.
]]

EqAttire = {}

local Log = EqLog

EqAttire.XML = "data/attire.xml"
-- player style xml file name -> the attire.xml section for that body
EqAttire.BODIES = { playerf = "female", playerm = "male" }
-- wardrobe config -> the HumanModel field holding the item's live node
EqAttire.SLOTS = {
    { config = "headgear", node = "headgearNode" },
    { config = "top", node = "topNode" },
    { config = "bottom", node = "bottomNode" },
    { config = "gloves", node = "glovesNode" },
    { config = "footwear", node = "footwearNode" },
}
-- The game sends at most this many items per config in multiplayer.
EqAttire.MAX_ITEMS = 255
-- Materials looked at per shape (a shape has as many as its mesh's material slots).
EqAttire.MAX_MATERIALS = 8

EqAttire.modDirectory = nil
EqAttire.schema = nil
-- item name -> absolute path of the diffuse map swapped onto it
EqAttire.diffuseByItem = {}
-- original material id .. "|" .. path -> the material made from it
EqAttire.materials = {}


--- The attire.xml section for a player style's xml file, or nil for styles we leave alone
--- (other mods' extra player models). Pure.
--- @param filename string|nil
--- @return string|nil "female" or "male"
function EqAttire.bodyOf(filename)
    if type(filename) ~= "string" then return nil end
    local name = string.match(string.lower(filename:gsub("\\", "/")), "([^/]+)%.xml$")
    return name ~= nil and EqAttire.BODIES[name] or nil
end


--- An item path as the game loads it: "$dataS/x" and "$data/x" are the game's own files, other
--- relative paths are ours (so attire.xml always writes the game's with the $). Pure.
--- @param path string|nil
--- @param modDirectory string
--- @return string|nil
function EqAttire.resolve(path, modDirectory)
    if type(path) ~= "string" or path == "" then return nil end
    path = path:gsub("\\", "/")
    local lower = string.lower(path)
    if string.sub(lower, 1, 7) == "$datas/" or string.sub(lower, 1, 6) == "$data/" then
        return string.sub(path, 2)
    end
    -- Already resolved by the item's own loading (filename values drop the $).
    if string.sub(lower, 1, 6) == "datas/" then return path end
    if string.sub(path, 1, 1) == "/" or string.find(path, "^%a:/") ~= nil then return path end
    return (modDirectory or "") .. path
end


--- @return table|nil the schema for attire.xml
function EqAttire.getSchema()
    if EqAttire.schema == nil then
        local schema = XMLSchema.new("eqAttire")
        for _, body in pairs(EqAttire.BODIES) do
            for _, slot in ipairs(EqAttire.SLOTS) do
                local base = "attire." .. body
                PlayerStyleItem.registerXMLPaths(schema, base, slot.config)
                schema:register(XMLValueType.STRING, base .. "." .. slot.config .. "(?)#eqDiffuse",
                    "Our diffuse map swapped onto the item")
            end
        end
        EqAttire.schema = schema
    end
    return EqAttire.schema
end


--- Add our items to one player style. Safe to repeat: items it already has are skipped.
--- @param style table PlayerStyle
function EqAttire.register(style)
    if style == nil or style.configs == nil or EqAttire.modDirectory == nil then return end
    local body = EqAttire.bodyOf(style.xmlFilename)
    if body == nil then return end
    local xmlFile = XMLFile.loadIfExists("eqAttire", EqAttire.modDirectory .. EqAttire.XML, EqAttire.getSchema())
    if xmlFile == nil then return end
    for _, slot in ipairs(EqAttire.SLOTS) do
        local config = style.configs[slot.config]
        if config ~= nil then
            for _, key in xmlFile:iterator("attire." .. body .. "." .. slot.config) do
                local item = PlayerStyleItem.new()
                item:loadFromConfigurationXMLFile(xmlFile, key, style.defaultClothingColors, style.attachPoints, false)
                item.filename = EqAttire.resolve(item.filename, EqAttire.modDirectory)
                item.iconFilename = EqAttire.resolve(item.iconFilename, EqAttire.modDirectory)
                local diffuse = xmlFile:getString(key .. "#eqDiffuse")
                if item.name ~= nil and diffuse ~= nil then
                    EqAttire.diffuseByItem[item.name] = EqAttire.resolve(diffuse, EqAttire.modDirectory)
                end
                if item.name ~= nil and item.filename ~= nil and config.itemsByName[item.name] == nil
                    and #config.items < EqAttire.MAX_ITEMS then
                    config:addItem(item)
                end
            end
        end
    end
    xmlFile:delete()
end


--- Add our items to every player style loaded so far.
function EqAttire.registerAll()
    for _, entry in pairs(PlayerSystem.PLAYER_STYLES_BY_FILENAME or {}) do
        if entry ~= nil and entry.style ~= nil then EqAttire.register(entry.style) end
    end
end


--- The material made from a material with our diffuse map (one per pair, reused).
local function swappedMaterial(material, path)
    local key = tostring(material) .. "|" .. path
    local made = EqAttire.materials[key]
    if made == nil then
        made = setMaterialDiffuseMapFromFile(material, path, true, true, false)
        if made == nil or made == 0 then return nil end
        EqAttire.materials[key] = made
        -- A made material is also its own: swapping it again keeps it.
        EqAttire.materials[tostring(made) .. "|" .. path] = made
    end
    return made
end


--- Put a diffuse map on every shape under a node.
local function swapDiffuse(node, path)
    if node == nil or node == 0 or not entityExists(node) then return end
    if getHasClassId(node, ClassIds.SHAPE) then
        for index = 0, EqAttire.MAX_MATERIALS - 1 do
            local ok, material = pcall(getMaterial, node, index)
            if not ok or material == nil or material == 0 then break end
            local made = swappedMaterial(material, path)
            if made ~= nil and made ~= material then setMaterial(node, made, index) end
        end
    end
    for i = 0, getNumOfChildren(node) - 1 do swapDiffuse(getChildAt(node, i), path) end
end


--- Swap our diffuse maps onto a model's items that name one.
--- @param model table HumanModel
--- @param style table PlayerStyle
function EqAttire.dress(model, style)
    if model == nil or style == nil or style.configs == nil or next(EqAttire.diffuseByItem) == nil then return end
    if setMaterialDiffuseMapFromFile == nil then return end
    for _, slot in ipairs(EqAttire.SLOTS) do
        local config = style.configs[slot.config]
        local item = config ~= nil and config:getSelectedItem() or nil
        local path = item ~= nil and EqAttire.diffuseByItem[item.name] or nil
        if path ~= nil then swapDiffuse(model[slot.node], path) end
    end
end


--- @param guarded function main.lua's error guard
--- @param modDirectory string
function EqAttire.install(guarded, modDirectory)
    if PlayerStyle == nil or PlayerStyleItem == nil or PlayerSystem == nil then
        Log:warning("EqAttire: no player styles, the dressage outfit is left out")
        return
    end
    EqAttire.modDirectory = modDirectory

    -- A style loaded again (wardrobe, other players) gets our items back after the game resets it.
    PlayerStyle.loadConfigurationXML = Utils.appendedFunction(PlayerStyle.loadConfigurationXML, function(style)
        guarded("attire items", function() EqAttire.register(style) end)
    end)
    if HumanModel ~= nil and HumanModel.applyFromStyle ~= nil then
        HumanModel.applyFromStyle = Utils.appendedFunction(HumanModel.applyFromStyle, function(model, style)
            guarded("attire textures", function() EqAttire.dress(model, style) end)
        end)
    end
    -- The base styles load before mods do; add ours now and again once the map has loaded.
    guarded("attire items", EqAttire.registerAll)
    addModEventListener({ loadMap = function() guarded("attire items", EqAttire.registerAll) end })
end

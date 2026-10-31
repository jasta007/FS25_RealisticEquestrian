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

    The top hat is our own model (art/source/top_hat.py). It hangs off the head's attach point,
    whose axes are the rig's, so once dressed its "eqHatFit" group is turned upright and to the
    front from the character's root and placed by EqAttire.HAT (eqHatFit tunes it in game).

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

-- The top hat's place on the head, along the character's own axes: metres up and forward from
-- the head joint, its tilt back in degrees and a size factor. Set with the eqHatFit command.
EqAttire.HAT = { up = 0.10, forward = 0.01, tilt = 0, scale = 1 }
EqAttire.HAT_NODE = "eqHatFit"

EqAttire.modDirectory = nil
EqAttire.schema = nil
-- item name -> absolute path of the diffuse map swapped onto it
EqAttire.diffuseByItem = {}
-- original material id .. "|" .. path -> the material made from it
EqAttire.materials = {}
-- fitted hat node -> its model, to refit after eqHatFit (weak, models come and go)
EqAttire.hats = setmetatable({}, { __mode = "k" })


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


--- The hat's direction and up, along the character's axes, for a tilt back in degrees. Pure.
--- @param tilt number
--- @return number, number, number, number, number, number forward xyz, up xyz
function EqAttire.hatAxes(tilt)
    local t = math.rad(tilt or 0)
    return 0, math.sin(t), math.cos(t), 0, math.cos(t), -math.sin(t)
end


--- A node under another by name.
local function findNamed(node, name)
    if node == nil or node == 0 or not entityExists(node) then return nil end
    if getName(node) == name then return node end
    for i = 0, getNumOfChildren(node) - 1 do
        local found = findNamed(getChildAt(node, i), name)
        if found ~= nil then return found end
    end
    return nil
end


--- Sit the top hat upright on the head, facing the way the character faces.
--- @param model table HumanModel
--- @param fit number the hat's eqHatFit node
function EqAttire.fitHat(model, fit)
    local reference = model.rootNode
    local parent = getParent(fit)
    if reference == nil or reference == 0 or parent == nil or parent == 0 then return end
    local hat = EqAttire.HAT
    local fx, fy, fz, ux, uy, uz = EqAttire.hatAxes(hat.tilt)
    fx, fy, fz = localDirectionToLocal(reference, parent, fx, fy, fz)
    ux, uy, uz = localDirectionToLocal(reference, parent, ux, uy, uz)
    setDirection(fit, fx, fy, fz, ux, uy, uz)
    setTranslation(fit, localDirectionToLocal(reference, parent, 0, hat.up, hat.forward))
    setScale(fit, hat.scale, hat.scale, hat.scale)
    EqAttire.hats[fit] = model
end


--- Swap our diffuse maps onto a model's items that name one.
--- @param model table HumanModel
--- @param style table PlayerStyle
function EqAttire.dress(model, style)
    if model == nil or style == nil or style.configs == nil then return end
    local hat = findNamed(model.headgearNode, EqAttire.HAT_NODE)
    if hat ~= nil then EqAttire.fitHat(model, hat) end
    if setMaterialDiffuseMapFromFile == nil then return end
    for _, slot in ipairs(EqAttire.SLOTS) do
        local config = style.configs[slot.config]
        local item = config ~= nil and config:getSelectedItem() or nil
        local path = item ~= nil and EqAttire.diffuseByItem[item.name] or nil
        if path ~= nil then swapDiffuse(model[slot.node], path) end
    end
end


--- eqHatFit [up] [forward] [tilt] [scale]: move the top hat on every dressed character.
function EqAttire:consoleHatFit(up, forward, tilt, scale)
    local hat = EqAttire.HAT
    hat.up = tonumber(up) or hat.up
    hat.forward = tonumber(forward) or hat.forward
    hat.tilt = tonumber(tilt) or hat.tilt
    hat.scale = math.max(0.5, math.min(2, tonumber(scale) or hat.scale))
    for fit, model in pairs(EqAttire.hats) do
        if entityExists(fit) then EqAttire.fitHat(model, fit) else EqAttire.hats[fit] = nil end
    end
    return string.format("Top hat: up %.3f m, forward %.3f m, tilt %.1f deg, scale %.2f (eqHatFit up forward tilt scale)",
        hat.up, hat.forward, hat.tilt, hat.scale)
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
    addConsoleCommand("eqHatFit", "Moves the dressage top hat: eqHatFit [up] [forward] [tilt] [scale]", "consoleHatFit", EqAttire)
    -- The base styles load before mods do; add ours now and again once the map has loaded.
    guarded("attire items", EqAttire.registerAll)
    addModEventListener({ loadMap = function() guarded("attire items", EqAttire.registerAll) end })
end

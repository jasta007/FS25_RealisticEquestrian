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

    The tall boots are our own model too (art/source/riding_boots.py), cut at the ankle. Clothes
    bend with the body through skinning to the game's rig, which we can't ship, so each piece is
    moved off the item onto a bone instead: shafts onto the shin bones, feet onto the foot bones
    (as the skeleton mod does with its bones). They are deleted when the character is dressed
    again.

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
-- The character shader's primary and secondary colours. A swapped material loses the ones the
-- wardrobe set, so ours are set again from the item's own colour list.
EqAttire.PRIMARY, EqAttire.SECONDARY = "colorScaleR", "colorScaleG"

-- The top hat's place on each body's head, along the character's own axes: metres up, forward
-- and to the right of the head joint, its tilt back in degrees and a size factor. Set with the
-- eqHatFit command.
EqAttire.HAT = {
    female = { up = 0.10, forward = -0.005, side = 0, tilt = 0, scale = 1 },
    male = { up = 0.10, forward = -0.005, side = 0, tilt = 0, scale = 1 },
}
EqAttire.HAT_NODE = "eqHatFit"
-- eqUvGrid's test texture (art/source/uv_grid.py) and the slot it is on, if any.
EqAttire.UV_GRID = "data/attire/uvGrid_diffuse.dds"
EqAttire.uvGridSlot = nil

-- The boots' pieces and the bones they go on. A shaft stands from the ankle (the foot bone's
-- origin) towards the knee (the shin bone's), each foot keeps the shaft's turn at dressing time.
EqAttire.BOOTS = {
    { side = "L", shin = "LeftLeg", foot = "LeftFoot", toe = "LeftToeBase", out = 1 },
    { side = "R", shin = "RightLeg", foot = "RightFoot", toe = "RightToeBase", out = -1 },
}
-- The boot model's shaft from the ankle to its top, and how far below the knee it should end.
EqAttire.BOOT_SHAFT = 0.43
EqAttire.BOOT_KNEE_GAP = 0.04
EqAttire.BOOT_SCALE_MIN, EqAttire.BOOT_SCALE_MAX = 0.85, 1.15
-- The shafts' girth on top of that (the model already widens up the calf), and how far the
-- whole boot sits above the ankle bone (the model's ankle is higher than the rig's). eqBootFit
-- tunes both.
EqAttire.BOOT_WIDTH = 1.15
EqAttire.BOOT_RAISE = 0.03
-- How far the foot bone's line to the toe bone points down from the boot's sole, degrees.
EqAttire.BOOT_TOE_DROP = 14
-- The shaft leans back from the ankle (degrees) and moves back (metres), for the calf.
EqAttire.BOOT_LEAN = 7
EqAttire.BOOT_BACK = -0.01
-- The shaft tops lean outwards, away from each other, seen from the front (degrees).
EqAttire.BOOT_SPLAY = 3
-- Which of the shaft's calf shapes (eqCalf1..n, art/source/riding_boots.py CALF_SHAPES) shows.
EqAttire.BOOT_CALF = 5
-- dressed models wearing our boots (weak, models come and go), for eqBootFit
EqAttire.booted = setmetatable({}, { __mode = "k" })

EqAttire.modDirectory = nil
EqAttire.schema = nil
-- item name -> { diffuse = path|nil, normal = path|nil, key } the maps swapped onto it
EqAttire.swapsByItem = {}
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


--- "r g b [a]" as { r, g, b, a }, or nil. Pure.
--- @param text string|nil
--- @return table|nil
function EqAttire.parseColour(text)
    if type(text) ~= "string" then return nil end
    local values = {}
    for number in string.gmatch(text, "[^%s]+") do table.insert(values, tonumber(number)) end
    if #values < 3 or values[1] == nil or values[2] == nil or values[3] == nil then return nil end
    return { values[1], values[2], values[3], values[4] or 1 }
end


--- The colour picked for an item from its own list (1-based index, first if out of range). Pure.
--- @param colours table|nil
--- @param index number|nil
--- @return table|nil { primary, secondary }
function EqAttire.pickColour(colours, index)
    if colours == nil or #colours == 0 then return nil end
    return colours[index] or colours[1]
end


--- Set the character shader's colours on every shape under a node that has them.
local function setColours(node, colour)
    if node == nil or node == 0 or not entityExists(node) then return end
    if getHasClassId(node, ClassIds.SHAPE) and getHasShaderParameter(node, EqAttire.PRIMARY) then
        local p, q = colour.primary, colour.secondary
        pcall(setShaderParameter, node, EqAttire.PRIMARY, p[1], p[2], p[3], p[4], false)
        if getHasShaderParameter(node, EqAttire.SECONDARY) then
            pcall(setShaderParameter, node, EqAttire.SECONDARY, q[1], q[2], q[3], q[4], false)
        end
    end
    for i = 0, getNumOfChildren(node) - 1 do setColours(getChildAt(node, i), colour) end
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
                schema:register(XMLValueType.STRING, base .. "." .. slot.config .. "(?)#eqNormal",
                    "Our normal map swapped onto the item")
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
                local normal = xmlFile:getString(key .. "#eqNormal")
                if item.name ~= nil and (diffuse ~= nil or normal ~= nil) then
                    local colours = {}
                    for i = 0, EqAttire.MAX_ITEMS - 1 do
                        local primary = EqAttire.parseColour(xmlFile:getString(string.format("%s.colors.color(%d)#primary", key, i)))
                        if primary == nil then break end
                        local secondary = EqAttire.parseColour(xmlFile:getString(string.format("%s.colors.color(%d)#secondary", key, i)))
                        table.insert(colours, { primary = primary, secondary = secondary or primary })
                    end
                    EqAttire.swapsByItem[item.name] = {
                        diffuse = EqAttire.resolve(diffuse, EqAttire.modDirectory),
                        normal = EqAttire.resolve(normal, EqAttire.modDirectory),
                        key = tostring(diffuse) .. "|" .. tostring(normal),
                        colours = colours,
                    }
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


--- The material made from a material with our maps, reused while it exists. The game deletes
--- materials when it reloads an item's i3d (the wardrobe does on every try-on), so a cached one
--- may be gone and is then made again.
local function swappedMaterial(material, swap)
    local key = tostring(material) .. "|" .. swap.key
    local made = EqAttire.materials[key]
    if made ~= nil and entityExists(made) then return made end
    made = material
    if swap.diffuse ~= nil then made = setMaterialDiffuseMapFromFile(made, swap.diffuse, true, true, false) end
    if made ~= nil and made ~= 0 and swap.normal ~= nil and setMaterialNormalMapFromFile ~= nil then
        made = setMaterialNormalMapFromFile(made, swap.normal, true, false, false)
    end
    if made == nil or made == 0 then return nil end
    EqAttire.materials[key] = made
    -- A made material is also its own: swapping it again keeps it.
    EqAttire.materials[tostring(made) .. "|" .. swap.key] = made
    return made
end


--- Put our maps on every shape under a node.
local function swapMaps(node, swap)
    if node == nil or node == 0 or not entityExists(node) then return end
    if getHasClassId(node, ClassIds.SHAPE) then
        for index = 0, EqAttire.MAX_MATERIALS - 1 do
            local ok, material = pcall(getMaterial, node, index)
            if not ok or material == nil or material == 0 then break end
            local made = swappedMaterial(material, swap)
            if made ~= nil and made ~= material then pcall(setMaterial, node, made, index) end
        end
    end
    for i = 0, getNumOfChildren(node) - 1 do swapMaps(getChildAt(node, i), swap) end
end


--- The hat's direction and up, along the character's axes, for a tilt back in degrees. Pure.
--- @param tilt number
--- @return number, number, number, number, number, number forward xyz, up xyz
function EqAttire.hatAxes(tilt)
    local t = math.rad(tilt or 0)
    return 0, math.sin(t), math.cos(t), 0, math.cos(t), -math.sin(t)
end


--- The nearest of the six axes to a direction, as a unit vector. Pure.
local function nearestAxis(x, y, z, skip)
    local best, bx, by, bz = -1, 0, 1, 0
    for _, axis in ipairs({ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }) do
        local dot = x * axis[1] + y * axis[2] + z * axis[3]
        local sign = dot < 0 and -1 or 1
        local ax, ay, az = axis[1] * sign, axis[2] * sign, axis[3] * sign
        local skipped = skip ~= nil and math.abs(ax * skip[1] + ay * skip[2] + az * skip[3]) > 0.5
        if not skipped and math.abs(dot) > best then best, bx, by, bz = math.abs(dot), ax, ay, az end
    end
    return bx, by, bz
end


--- The head joint's own up, forward and left axes, from the character's up and forward seen
--- from it. The rig's joints sit square to the body, so the nearest axes are the ones it has
--- at rest, whichever way the head happens to be turned at dressing time. Pure.
--- @return number, number, number, number, number, number, number, number, number up, forward, left
function EqAttire.headAxes(ux, uy, uz, fx, fy, fz)
    ux, uy, uz = nearestAxis(ux, uy, uz)
    fx, fy, fz = nearestAxis(fx, fy, fz, { ux, uy, uz })
    -- x = y cross z
    return ux, uy, uz, fx, fy, fz, uy * fz - uz * fy, uz * fx - ux * fz, ux * fy - uy * fx
end


--- The boot foot's forward and up on the foot bone: the line to the toe bone, turned up by
--- the drop about the side axis. Pure.
--- @param tx number toe direction, any length
--- @param sx number the character's left, any length
--- @param drop number degrees
--- @return number|nil, number, number, number, number, number forward xyz, up xyz (nil if no toe line)
function EqAttire.footAxes(tx, ty, tz, sx, sy, sz, drop)
    local length = math.sqrt(tx * tx + ty * ty + tz * tz)
    if length < 1e-6 then return nil end
    tx, ty, tz = tx / length, ty / length, tz / length
    -- up = forward cross left (z cross x = y)
    local ux, uy, uz = ty * sz - tz * sy, tz * sx - tx * sz, tx * sy - ty * sx
    length = math.sqrt(ux * ux + uy * uy + uz * uz)
    if length < 1e-6 then return nil end
    ux, uy, uz = ux / length, uy / length, uz / length
    local c, s = math.cos(math.rad(drop or 0)), math.sin(math.rad(drop or 0))
    return c * tx + s * ux, c * ty + s * uy, c * tz + s * uz, c * ux - s * tx, c * uy - s * ty, c * uz - s * tz
end


--- Forward and up tilted back by an angle (the top goes back), both unit. Pure.
--- @return number, number, number, number, number, number forward xyz, up xyz
function EqAttire.lean(fx, fy, fz, ux, uy, uz, degrees)
    local c, s = math.cos(math.rad(degrees or 0)), math.sin(math.rad(degrees or 0))
    return c * fx + s * ux, c * fy + s * uy, c * fz + s * uz, c * ux - s * fx, c * uy - s * fy, c * uz - s * fz
end


--- Up tilted towards the character's left (x = up cross forward) about forward, by degrees;
--- negative tilts right. Pure.
--- @return number, number, number up xyz
function EqAttire.splay(fx, fy, fz, ux, uy, uz, degrees)
    local lx, ly, lz = uy * fz - uz * fy, uz * fx - ux * fz, ux * fy - uy * fx
    local c, s = math.cos(math.rad(degrees or 0)), math.sin(math.rad(degrees or 0))
    return c * ux + s * lx, c * uy + s * ly, c * uz + s * lz
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


--- Sit the top hat upright on the head, facing the way the character faces. The offsets are
--- along the head joint's own axes, so the hat stays put wherever the head turns.
--- @param model table HumanModel
--- @param fit number the hat's eqHatFit node
--- @param body string "female" or "male"
function EqAttire.fitHat(model, fit, body)
    local reference = model.rootNode
    local parent = getParent(fit)
    if reference == nil or reference == 0 or parent == nil or parent == 0 then return end
    local hat = EqAttire.HAT[body] or EqAttire.HAT.female
    local ux, uy, uz = localDirectionToLocal(reference, parent, 0, 1, 0)
    local fx, fy, fz = localDirectionToLocal(reference, parent, 0, 0, 1)
    local lx, ly, lz
    ux, uy, uz, fx, fy, fz, lx, ly, lz = EqAttire.headAxes(ux, uy, uz, fx, fy, fz)
    -- The hat's own axes along the head's: (left, up, forward) per component.
    local function along(x, y, z) return x * lx + y * ux + z * fx, x * ly + y * uy + z * fy, x * lz + y * uz + z * fz end
    local hfx, hfy, hfz, hux, huy, huz = EqAttire.hatAxes(hat.tilt)
    local dx, dy, dz = along(hfx, hfy, hfz)
    local vx, vy, vz = along(hux, huy, huz)
    setDirection(fit, dx, dy, dz, vx, vy, vz)
    -- The character's right is its -x (it faces +z).
    setTranslation(fit, along(-hat.side, hat.up, hat.forward))
    setScale(fit, hat.scale, hat.scale, hat.scale)
    EqAttire.hats[fit] = { model = model, body = body }
end


--- The boots' size for a shin (knee to ankle, metres): the shaft ends a little below the knee. Pure.
--- @param shin number|nil
--- @return number
function EqAttire.bootScale(shin)
    if type(shin) ~= "number" or shin <= 0 then return 1 end
    local scale = (shin - EqAttire.BOOT_KNEE_GAP) / EqAttire.BOOT_SHAFT
    return math.max(EqAttire.BOOT_SCALE_MIN, math.min(EqAttire.BOOT_SCALE_MAX, scale))
end


--- Whether a footwear item is one of our riding boots (any colour). Pure.
--- @param name string|nil
--- @return boolean
function EqAttire.isRidingBoots(name)
    return type(name) == "string" and string.sub(name, 1, 13) == "eqRidingBoots"
end


--- Show one calf shape of a shaft, hide the others (a shaft with none named eqCalf is left alone).
local function showCalf(shaft)
    for i = 0, getNumOfChildren(shaft) - 1 do
        local child = getChildAt(shaft, i)
        local n = tonumber(string.match(getName(child), "^eqCalf(%d+)$"))
        if n ~= nil then setVisibility(child, n == EqAttire.BOOT_CALF) end
    end
end


--- Delete the boot pieces a model wore before.
local function removeBoots(model)
    for _, node in ipairs(model.eqBootNodes or {}) do
        if entityExists(node) then delete(node) end
    end
    model.eqBootNodes = nil
end


--- Move the boots' pieces from the item onto the leg bones.
--- @param model table HumanModel
--- @param item number the boots item's root node
function EqAttire.fitBoots(model, item)
    local reference = model.rootNode
    local skeleton = model.skeleton or model.rootNode
    if reference == nil or reference == 0 or skeleton == nil or skeleton == 0 then return end
    local nodes = {}
    for _, boot in ipairs(EqAttire.BOOTS) do
        local shaft = findNamed(item, "eqBootShaft" .. boot.side)
        local foot = findNamed(item, "eqBootFoot" .. boot.side)
        local shin = findNamed(skeleton, boot.shin)
        local ankle = findNamed(skeleton, boot.foot)
        local toe = findNamed(skeleton, boot.toe)
        if shaft ~= nil and foot ~= nil and shin ~= nil and ankle ~= nil then
            -- The shaft: up from the ankle towards the knee, its toe the way the character faces.
            local ax, ay, az = localToLocal(ankle, shin, 0, 0, 0)
            local length = math.sqrt(ax * ax + ay * ay + az * az)
            if length > 0.05 then
                local ux, uy, uz = -ax / length, -ay / length, -az / length
                local fx, fy, fz = localDirectionToLocal(reference, shin, 0, 0, 1)
                local along = fx * ux + fy * uy + fz * uz
                fx, fy, fz = fx - along * ux, fy - along * uy, fz - along * uz
                local flength = math.sqrt(fx * fx + fy * fy + fz * fz)
                if flength < 1e-6 then fx, fy, fz, flength = 0, 0, 1, 1 end
                fx, fy, fz = fx / flength, fy / flength, fz / flength
                fx, fy, fz, ux, uy, uz = EqAttire.lean(fx, fy, fz, ux, uy, uz, EqAttire.BOOT_LEAN)
                ux, uy, uz = EqAttire.splay(fx, fy, fz, ux, uy, uz, EqAttire.BOOT_SPLAY * boot.out)
                local scale = EqAttire.bootScale(length)
                local raise, back = EqAttire.BOOT_RAISE, EqAttire.BOOT_BACK
                link(shin, shaft)
                setDirection(shaft, fx, fy, fz, ux, uy, uz)
                setTranslation(shaft, ax + ux * raise - fx * back, ay + uy * raise - fy * back, az + uz * raise - fz * back)
                setScale(shaft, scale * EqAttire.BOOT_WIDTH, scale, scale * EqAttire.BOOT_WIDTH)
                showCalf(shaft)
                -- The foot: along the foot bone towards the toe bone, so it lies on the foot
                -- however the ankle is bent at dressing time (in the saddle the toes point down).
                -- Its own size, the shaft's girth is only for calves.
                local dx, dy, dz, vx, vy, vz
                if toe ~= nil then
                    local tx, ty, tz = localToLocal(toe, ankle, 0, 0, 0)
                    local sx, sy, sz = localDirectionToLocal(reference, ankle, 1, 0, 0)
                    dx, dy, dz, vx, vy, vz = EqAttire.footAxes(tx, ty, tz, sx, sy, sz, EqAttire.BOOT_TOE_DROP)
                end
                if dx == nil then
                    dx, dy, dz = localDirectionToLocal(shaft, ankle, 0, 0, 1)
                    vx, vy, vz = localDirectionToLocal(shaft, ankle, 0, 1, 0)
                end
                link(ankle, foot)
                setDirection(foot, dx, dy, dz, vx, vy, vz)
                setTranslation(foot, vx * raise, vy * raise, vz * raise)
                setScale(foot, scale, scale, scale)
                table.insert(nodes, shaft)
                table.insert(nodes, foot)
            end
        end
    end
    if #nodes > 0 then
        removeBoots(model)
        model.eqBootNodes = nodes
        EqAttire.booted[model] = true
    end
end


--- Swap our diffuse maps onto a model's items that name one.
--- @param model table HumanModel
--- @param style table PlayerStyle
function EqAttire.dress(model, style)
    if model == nil or style == nil or style.configs == nil then return end
    local hat = findNamed(model.headgearNode, EqAttire.HAT_NODE)
    if hat ~= nil then EqAttire.fitHat(model, hat, EqAttire.bodyOf(style.xmlFilename)) end
    local boots = findNamed(model.footwearNode, "eqRidingBoots")
    if boots ~= nil then
        EqAttire.fitBoots(model, boots)
    elseif model.eqBootNodes ~= nil then
        -- Still ours if the game kept the item's node; anything else and the old pair goes.
        local footwear = style.configs.footwear ~= nil and style.configs.footwear:getSelectedItem() or nil
        if footwear == nil or not EqAttire.isRidingBoots(footwear.name) then removeBoots(model) end
    end
    if setMaterialDiffuseMapFromFile == nil then return end
    for _, slot in ipairs(EqAttire.SLOTS) do
        local config = style.configs[slot.config]
        local item = config ~= nil and config:getSelectedItem() or nil
        local swap = item ~= nil and EqAttire.swapsByItem[item.name] or nil
        if swap ~= nil then
            swapMaps(model[slot.node], swap)
            -- The riding boots' pieces live on the leg bones now.
            if slot.config == "footwear" then
                for _, node in ipairs(model.eqBootNodes or {}) do swapMaps(node, swap) end
            end
            local index = config.getSelectedColorIndex ~= nil and config:getSelectedColorIndex() or config.selectedColorIndex
            local colour = EqAttire.pickColour(swap.colours, index)
            if colour ~= nil then setColours(model[slot.node], colour) end
        end
        if EqAttire.uvGridSlot == slot.config then
            -- eqUvGrid: the labelled grid in white light, to see where the texture lands.
            swapMaps(model[slot.node], { diffuse = EqAttire.resolve(EqAttire.UV_GRID, EqAttire.modDirectory), key = "uvGrid" })
            setColours(model[slot.node], { primary = { 1, 1, 1, 1 }, secondary = { 1, 1, 1, 1 } })
        end
    end
end


--- eqHatFit [female|male] [up] [forward] [side] [tilt] [scale]: move the top hat on every
--- dressed character (of one body, or both).
function EqAttire:consoleHatFit(...)
    local args = { ... }
    local bodies = { "female", "male" }
    if args[1] == "female" or args[1] == "male" then bodies = { table.remove(args, 1) } end
    local lines = {}
    for _, body in ipairs(bodies) do
        local hat = EqAttire.HAT[body]
        hat.up = tonumber(args[1]) or hat.up
        hat.forward = tonumber(args[2]) or hat.forward
        hat.side = tonumber(args[3]) or hat.side
        hat.tilt = tonumber(args[4]) or hat.tilt
        hat.scale = math.max(0.5, math.min(2, tonumber(args[5]) or hat.scale))
        table.insert(lines, string.format("Top hat (%s): up %.3f m, forward %.3f m, side %.3f m, tilt %.1f deg, scale %.2f",
            body, hat.up, hat.forward, hat.side, hat.tilt, hat.scale))
    end
    for fit, entry in pairs(EqAttire.hats) do
        if entityExists(fit) then EqAttire.fitHat(entry.model, fit, entry.body) else EqAttire.hats[fit] = nil end
    end
    table.insert(lines, "eqHatFit [female|male] up forward side tilt scale")
    return table.concat(lines, "\n")
end


--- eqBootFit [width] [raise] [toeDrop]: the tall boots' shaft girth, height above the ankle and
--- foot angle; applies the next time a character is dressed (open the wardrobe, or remount).
function EqAttire:consoleBootFit(width, raise, drop, lean, back, splay)
    EqAttire.BOOT_WIDTH = math.max(0.8, math.min(2, tonumber(width) or EqAttire.BOOT_WIDTH))
    EqAttire.BOOT_RAISE = math.max(-0.1, math.min(0.15, tonumber(raise) or EqAttire.BOOT_RAISE))
    EqAttire.BOOT_TOE_DROP = math.max(-30, math.min(60, tonumber(drop) or EqAttire.BOOT_TOE_DROP))
    EqAttire.BOOT_LEAN = math.max(-20, math.min(20, tonumber(lean) or EqAttire.BOOT_LEAN))
    EqAttire.BOOT_BACK = math.max(-0.1, math.min(0.1, tonumber(back) or EqAttire.BOOT_BACK))
    EqAttire.BOOT_SPLAY = math.max(-15, math.min(15, tonumber(splay) or EqAttire.BOOT_SPLAY))
    for model in pairs(EqAttire.booted) do
        for _, node in ipairs(model.eqBootNodes or {}) do
            if entityExists(node) and string.find(getName(node), "Shaft") ~= nil then
                local _, scale = getScale(node)
                setScale(node, scale * EqAttire.BOOT_WIDTH, scale, scale * EqAttire.BOOT_WIDTH)
            end
        end
    end
    return string.format("Riding boots: width %.2f (now), raise %.3f m, toe drop %.0f deg, lean %.1f deg, back %.3f m, "
        .. "splay %.1f deg (next dressing)\neqBootFit width raise toeDrop lean back splay", EqAttire.BOOT_WIDTH,
        EqAttire.BOOT_RAISE, EqAttire.BOOT_TOE_DROP, EqAttire.BOOT_LEAN, EqAttire.BOOT_BACK, EqAttire.BOOT_SPLAY)
end


--- eqBootCalf [1-8]: which calf shape the tall boots' shafts show, live on every dressed character.
function EqAttire:consoleBootCalf(n)
    EqAttire.BOOT_CALF = math.max(1, math.min(8, math.floor(tonumber(n) or EqAttire.BOOT_CALF)))
    for model in pairs(EqAttire.booted) do
        for _, node in ipairs(model.eqBootNodes or {}) do
            if entityExists(node) and string.find(getName(node), "Shaft") ~= nil then showCalf(node) end
        end
    end
    local shapes = { "1.40 wide 1.30 deep", "1.55 wide 1.30 deep", "1.40 wide 1.45 deep, even taper, full higher",
        "1.30 wide 1.55 deep", "1.40 wide 1.45 deep", "1.55 wide 1.45 deep", "1.40 wide 1.45 deep, full lower",
        "1.30 wide 1.45 deep" }
    return string.format("Riding boots: calf shape %d (%s at the top)", EqAttire.BOOT_CALF, shapes[EqAttire.BOOT_CALF])
end


--- eqUvGrid [bottom|top|gloves|footwear|headgear|off]: put a labelled grid on one slot's item as
--- its texture, from the next dressing (re-pick the item in the wardrobe), to map its layout.
function EqAttire:consoleUvGrid(slot)
    local slots = { bottom = true, top = true, gloves = true, footwear = true, headgear = true }
    EqAttire.uvGridSlot = slots[slot] and slot or nil
    if EqAttire.uvGridSlot == nil then return "UV grid off (re-pick the item to put its texture back)" end
    return string.format("UV grid on the %s item: open the wardrobe and pick it again", EqAttire.uvGridSlot)
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
    addConsoleCommand("eqBootFit", "Fits the tall riding boots: eqBootFit [width] [raise] [toeDrop] [lean] [back] [splay]", "consoleBootFit", EqAttire)
    addConsoleCommand("eqBootCalf", "Picks the tall riding boots' calf shape: eqBootCalf [1-8]", "consoleBootCalf", EqAttire)
    addConsoleCommand("eqUvGrid", "Shows a labelled test grid on a worn item: eqUvGrid [bottom|top|gloves|footwear|headgear|off]", "consoleUvGrid", EqAttire)
    addConsoleCommand("eqHatFit", "Moves the dressage top hat: eqHatFit [female|male] [up] [forward] [side] [tilt] [scale]", "consoleHatFit", EqAttire)
    -- The base styles load before mods do; add ours now and again once the map has loaded.
    guarded("attire items", EqAttire.registerAll)
    addModEventListener({ loadMap = function() guarded("attire items", EqAttire.registerAll) end })
end

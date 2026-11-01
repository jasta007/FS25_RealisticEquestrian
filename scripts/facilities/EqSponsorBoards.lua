--[[
    EqSponsorBoards.lua
    The Sponsor boards choice on six of our show jumps (the wall, a showpiece, always has its boards) (James, 2026-10-31): bought with Yes, the
    jump's sponsor parts show (the transform group "eqSponsorOn": a sign on each pillar, a board
    in place of a fan, an oval on a picket wing, the logo in a liverpool's water) and the parts
    they replace hide ("eqSponsorOff"). Their faces, "eqSponsor_<n>", are boards like any other
    (EqSponsors puts the logo on and counts them); bought with No they are neither shown nor
    counted. Like the corners' choice, placed jumps and the construction brush's are looked over
    every second rather than trusting PlaceableConfigurationItem.onPostLoad.

    Sponsor colours (James, 2026-10-31): a jump with boards paints its poles and trim in the
    signed sponsor's colour. The colour is the game's own for that brand when it has one (the
    paint it gives the brand's machines, read at run time, so brands added later by DLC or mods
    work too), else one from COLOURS below, else the pole colour bought in the shop.
    eqSponsorColours lists where each brand's colour comes from.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsorBoards = {}

local Log = EqLog

EqSponsorBoards.CONFIG = "eqSponsorBoards"
EqSponsorBoards.YES = 2
EqSponsorBoards.ON = "eqSponsorOn"
EqSponsorBoards.OFF = "eqSponsorOff"
EqSponsorBoards.DEPTH = 3
EqSponsorBoards.SCAN_MS = 1000
-- Our show jumps with the choice (lower case, as the xml paths are compared).
EqSponsorBoards.JUMPS = {
    "placeables/showjumps/showjumpupright.xml", "placeables/showjumps/showjumpoxer.xml",
    "placeables/showjumps/showjumptriplebar.xml", "placeables/showjumps/showjumphogsback.xml",
    "placeables/showjumps/showjumpfan3.xml", "placeables/showjumps/showjumpliverpool.xml",
}

-- Brands' colours when the game gives none: sRGB 0-255, made linear for the shader. Only the
-- best known; anything else keeps the shop's colour.
EqSponsorBoards.COLOURS = {
    FENDT = { 62, 122, 39 },
    MASSEYFERGUSON = { 190, 22, 34 },
    JOHNDEERE = { 54, 124, 43 },
    CASEIH = { 181, 18, 27 },
    NEWHOLLAND = { 13, 77, 161 },
    CLAAS = { 180, 198, 24 },
    DEUTZFAHR = { 108, 179, 63 },
    VALTRA = { 200, 16, 46 },
    KUBOTA = { 243, 115, 33 },
    KRONE = { 46, 125, 50 },
    LEMKEN = { 0, 92, 169 },
    POETTINGER = { 0, 150, 64 },
    KUHN = { 226, 0, 26 },
    JCB = { 252, 179, 21 },
    MANITOU = { 227, 6, 19 },
    CHALLENGER = { 246, 184, 0 },
    STEYR = { 200, 16, 46 },
}


-- Pieces whose sponsor boards are always there (no choice): the wall and the two gates, whose
-- banners or board take the sponsor's colour.
EqSponsorBoards.ALWAYS = { "placeables/showjumps/showjumpwall.xml", "placeables/xcjumps/xcgatearch.xml",
    "placeables/xcjumps/xcgatesimple.xml", "placeables/sponsorplinths/plinthdrive.xml",
    "placeables/sponsorplinths/plinthramp.xml", "placeables/sponsorplinths/plinthramplarge.xml",
    "placeables/sponsorplinths/plinthproductramp.xml", "placeables/sponsorplinths/plinthturntable.xml" }

-- Brands whose colour is ours whatever the game's paints say, faces included (James, 2026-11-01:
-- the game's Lizard paint is red; Lizard is green, as on its logo).
EqSponsorBoards.OWN_COLOURS = {
    LIZARD = { 132, 189, 41 },
}

-- Brands whose logo is white or very pale (James, 2026-11-01: white on a white board vanishes).
-- Measured on the game's own 261 logos (light share of the opaque pixels 0.5 or more, or a mean
-- luminance of 0.75 or more); brands from DLCs and mods aren't known and keep the white board.
EqSponsorBoards.LIGHT_LOGOS = {}
for _, name in ipairs({
    "AGRIFAC", "APV", "APE", "CONVEYALL", "DALBO", "ELHO", "SKODA", "FARMTECH", "FENDT", "GEA", "GOLDHOFER",
    "HUSQVARNA", "INTERNATIONAL", "KOMATSU", "KOTTE", "KRAMPE", "LACOTEC", "LEMKEN", "LODEKING", "MACDON", "MACK",
    "MERCEDESBENZTRUCKS", "MERIDIAN", "MITAS", "NEWHOLLAND", "PORSCHEDIESEL", "QUICKE", "RANDON", "ROSTSELMASH",
    "ROTTNE", "SALFORD", "SCHAEFFER", "SENNEBOGEN", "TAJFUN", "TROUTRIVER", "VALTRA", "VOLVO", "VREDESTEIN", "WELGER",
    "MZURI", "NARDI", "FLEXICOIL", "DAMMANN", "JUNGHEINRICH", "KESLA", "NEXAT", "OLOFSFORS", "HOLMER", "MERLO", "DFM",
    "HEIZOMAT", "SUMMERSMFG", "BOMECH", "BRANDT", "LIZARD", "UNVERFERTH", "SCHWARZMUELLER", "FARMAX", "GORENC",
    "ARMATRAC", "RIGITRAC", "BRIELMAIER", "TMCCANCELA", "AGIWESTFIELD", "AGCO", "ARCUSIN", "MICHELIN", "WEBERMT",
    "FARMET", "PROVITIS", "AGISENTINEL", "HELM", "JMMANUFACTURING", "ABI", "AGIWESTEEL", "WILSON", "DUEVELSDORF",
    "WARZEE", "ANDERSONGROUP", "REITER", "KRAMER", "AGISTORM", "PALADIN", "RIEDLER", "AGIBATCO", "GIANTS",
    "ANNABURGER", "STEPA", "TRELLEBORG", "AGINECO", "AGRISPREAD", "MCCULLOCH", "NEUERO", "KAERCHER",
    "KRONE", "CHALLENGER", "AGRISEM", "RAU", "ZIEGLER",
}) do EqSponsorBoards.LIGHT_LOGOS[name] = true end
-- A board face's colours, linear: plain white, and the dark grey behind a light logo whose brand
-- colour is too pale to show it.
EqSponsorBoards.FACE_WHITE = { 0.80, 0.80, 0.78 }
EqSponsorBoards.FACE_DARK = { 0.025, 0.027, 0.032 }
-- A brand colour darker than this (linear luminance) carries a light logo.
EqSponsorBoards.DARK_ENOUGH = 0.18


--- @param brand string|nil the brand a piece shows
--- @return table colour of the boards' faces behind its logo: white, or for a light logo the
--- brand's own colour when it's dark enough, else dark grey
function EqSponsorBoards.faceColour(brand)
    if brand ~= nil and EqSponsorBoards.OWN_COLOURS[string.upper(brand)] ~= nil then
        return EqSponsorBoards.linear(EqSponsorBoards.OWN_COLOURS[string.upper(brand)])
    end
    if brand == nil or not EqSponsorBoards.LIGHT_LOGOS[string.upper(brand)] then return EqSponsorBoards.FACE_WHITE end
    local colour = EqSponsorBoards.brandColour(brand)
    if colour ~= nil and 0.2126 * colour[1] + 0.7152 * colour[2] + 0.0722 * colour[3] < EqSponsorBoards.DARK_ENOUGH then
        return colour
    end
    return EqSponsorBoards.FACE_DARK
end


local function endsWith(filename, list)
    if type(filename) ~= "string" then return false end
    local path = string.lower(string.gsub(filename, "\\", "/"))
    for _, suffix in ipairs(list) do
        if string.sub(path, -#suffix) == suffix then return true end
    end
    return false
end


--- @param filename string|nil
--- @return boolean true for one of our jumps with sponsor boards, by choice or always. Pure.
function EqSponsorBoards.isJump(filename)
    return endsWith(filename, EqSponsorBoards.JUMPS) or endsWith(filename, EqSponsorBoards.ALWAYS)
end


--- @param placeable table|nil
--- @return boolean true when the placeable's sponsor parts are bought: Yes on a jump with the
--- choice. Pieces whose boards are always there have no choice, and nil means not a jump of ours.
function EqSponsorBoards.isOn(placeable)
    if type(placeable) ~= "table" then return false end
    if endsWith(placeable.configFileName, EqSponsorBoards.ALWAYS) then return true end
    local configurations = placeable.configurations
    return type(configurations) == "table" and configurations[EqSponsorBoards.CONFIG] == EqSponsorBoards.YES
end


--- Register the choice before the store items load.
function EqSponsorBoards.registerConfiguration()
    local manager = g_placeableConfigurationManager
    if manager == nil or manager.addConfigurationType == nil or PlaceableConfigurationItem == nil then
        Log:warning("EqSponsorBoards: no placeable configurations, show jumps have no sponsor boards")
        return
    end
    if manager.configurations == nil or manager.configurations[EqSponsorBoards.CONFIG] == nil then
        local title = "Sponsor boards"
        if g_i18n ~= nil and g_i18n:hasText("eq_config_sponsorBoards") then title = g_i18n:getText("eq_config_sponsorBoards") end
        manager:addConfigurationType(EqSponsorBoards.CONFIG, title, EqSponsorBoards.CONFIG, PlaceableConfigurationItem)
    end
end


--- The "eqSponsorOn" and "eqSponsorOff" groups under a placeable's root.
local function groups(root)
    local on, off = {}, {}
    local stack = { { root, 0 } }
    while #stack > 0 do
        local node, depth = stack[#stack][1], stack[#stack][2]
        stack[#stack] = nil
        local name = getName(node)
        if name == EqSponsorBoards.ON then table.insert(on, node)
        elseif name == EqSponsorBoards.OFF then table.insert(off, node)
        elseif depth < EqSponsorBoards.DEPTH then
            for i = 0, getNumOfChildren(node) - 1 do stack[#stack + 1] = { getChildAt(node, i), depth + 1 } end
        end
    end
    return on, off
end


--- Show a jump's sponsor parts or the parts they replace, as its choice says.
--- @param placeable table
function EqSponsorBoards.apply(placeable)
    if placeable == nil or type(placeable.rootNode) ~= "number" or placeable.rootNode == 0 then return end
    if not EqSponsorBoards.isJump(placeable.configFileName) then return end
    local on = EqSponsorBoards.isOn(placeable)
    if placeable.eqSponsorBoardsOn ~= on then
        placeable.eqSponsorBoardsOn = on
        local onNodes, offNodes = groups(placeable.rootNode)
        for _, node in ipairs(onNodes) do setVisibility(node, on) end
        for _, node in ipairs(offNodes) do setVisibility(node, not on) end
        -- its boards are new: let EqSponsors put the logos on
        placeable.eqSponsored = nil
        if EqSponsors ~= nil then EqSponsors.scannedAt = nil end
    end
    if EqJumpColours ~= nil then EqJumpColours.apply(placeable) end
end


--- Every placed jump with the choice, and the one on the construction brush.
function EqSponsorBoards.update()
    local now = g_time or 0
    if EqSponsorBoards.scannedAt ~= nil and now - EqSponsorBoards.scannedAt < EqSponsorBoards.SCAN_MS and now >= EqSponsorBoards.scannedAt then return end
    EqSponsorBoards.scannedAt = now
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do EqSponsorBoards.apply(placeable) end
    local gui = g_gui ~= nil and g_gui.currentGui or nil
    local target = gui ~= nil and gui.target or nil
    local brush = type(target) == "table" and target.brush or nil
    if type(brush) == "table" and type(brush.placeable) == "table" then EqSponsorBoards.apply(brush.placeable) end
end


-- ---------------------------------------------------------------------------------------------
-- Sponsor colours

--- sRGB 0-255 to the shader's linear 0-1. Pure.
function EqSponsorBoards.linear(rgb)
    local out = {}
    for i = 1, 3 do
        local c = (rgb[i] or 0) / 255
        out[i] = c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    end
    return out
end


--- A colour from a value the game might hold it in: { r, g, b } (or {r=, g=, b=}), or "r g b". Pure.
--- @return table|nil { r, g, b } linear, as the game's paint keeps them
function EqSponsorBoards.readColour(value)
    if type(value) == "string" then
        local r, g, b = string.match(value, "^%s*([%d%.%-]+)[%s,]+([%d%.%-]+)[%s,]+([%d%.%-]+)")
        if r ~= nil then return { tonumber(r), tonumber(g), tonumber(b) } end
    elseif type(value) == "table" then
        local r, g, b = value[1] or value.r, value[2] or value.g, value[3] or value.b
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return { r, g, b } end
    end
    return nil
end


--- How colourful a linear colour is: 0 for white, grey and black. Pure.
function EqSponsorBoards.saturation(c)
    local hi, lo = math.max(c[1], c[2], c[3]), math.min(c[1], c[2], c[3])
    if hi <= 0.002 then return 0 end
    return (hi - lo) / hi
end


--- The brand's own colour from named paints: the most colourful one whose name starts with the
--- brand's ("fendtNatureGreen" for FENDT; case, spaces and punctuation ignored). Pure.
--- @param brand string the brand's name, as the brand manager has it
--- @param paints table name -> { r, g, b } linear
--- @return table|nil colour, string|nil the paint's name
function EqSponsorBoards.pickPaint(brand, paints)
    local key = string.lower(string.gsub(brand or "", "[^%w]", ""))
    if key == "" then return nil end
    local best, bestName, bestSat = nil, nil, 0.25
    for name, colour in pairs(paints) do
        local plain = string.lower(string.gsub(name, "[^%w]", ""))
        if string.sub(plain, 1, #key) == key then
            local sat = EqSponsorBoards.saturation(colour)
            if sat > bestSat or (sat == bestSat and bestName ~= nil and name < bestName) then
                best, bestName, bestSat = colour, name, sat
            end
        end
    end
    return best, bestName
end


-- Where the game keeps named paints: managers and their tables (the first that has any wins).
EqSponsorBoards.PAINT_SOURCES = {
    { manager = "g_vehicleMaterialManager", tables = { "materialTemplates", "templates", "nameToTemplate", "materialTemplateByName" } },
    { manager = "g_materialManager", tables = { "materialTemplates", "templates", "nameToTemplate" } },
    { manager = "g_brandColorManager", tables = { "brandColors", "colors", "nameToColor" } },
}
EqSponsorBoards.COLOUR_FIELDS = { "colorScale", "colourScale", "color", "colour", "baseColor", "diffuseColor" }


--- A paint's colour, wherever in it the game keeps it.
local function colourOf(entry)
    local direct = EqSponsorBoards.readColour(entry)
    if direct ~= nil then return direct end
    if type(entry) ~= "table" then return nil end
    for _, field in ipairs(EqSponsorBoards.COLOUR_FIELDS) do
        local c = EqSponsorBoards.readColour(entry[field])
        if c ~= nil then return c end
    end
    local params = entry.parameters or entry.customParameters or entry.shaderParameters
    if type(params) == "table" then
        for _, field in ipairs(EqSponsorBoards.COLOUR_FIELDS) do
            local p = params[field]
            local c = EqSponsorBoards.readColour(type(p) == "table" and (p.value or p) or p)
            if c ~= nil then return c end
        end
    end
    return nil
end


--- The game's named paints, read once: name -> colour, and where they came from.
function EqSponsorBoards.gamePaints()
    if EqSponsorBoards.paints ~= nil then return EqSponsorBoards.paints, EqSponsorBoards.paintSource end
    local paints, source = {}, nil
    for _, src in ipairs(EqSponsorBoards.PAINT_SOURCES) do
        local manager = _G[src.manager]
        if type(manager) == "table" then
            for _, field in ipairs(src.tables) do
                local list = manager[field]
                if type(list) == "table" then
                    local count = 0
                    for key, entry in pairs(list) do
                        local name = type(key) == "string" and key or (type(entry) == "table" and entry.name) or nil
                        local colour = type(name) == "string" and colourOf(entry) or nil
                        if colour ~= nil then
                            paints[name] = colour
                            count = count + 1
                        end
                    end
                    if count > 0 then
                        source = string.format("%s.%s (%d)", src.manager, field, count)
                        break
                    end
                end
            end
        end
        if source ~= nil then break end
    end
    EqSponsorBoards.paints, EqSponsorBoards.paintSource = paints, source
    if source ~= nil then
        Log:info("EqSponsorBoards: brand paints from %s", source)
    else
        Log:info("EqSponsorBoards: the game's brand paints not found; using our own list")
    end
    return paints, source
end


--- A brand's colour for a jump, and where it came from ("game <paint>", "list" or nil).
--- @param brand string|nil
--- @return table|nil colour linear, string|nil source
function EqSponsorBoards.brandColour(brand)
    if type(brand) ~= "string" or brand == "" then return nil, nil end
    EqSponsorBoards.cache = EqSponsorBoards.cache or {}
    local cached = EqSponsorBoards.cache[brand]
    if cached ~= nil then return cached.colour, cached.source end
    local colour, source = nil, nil
    local own = EqSponsorBoards.OWN_COLOURS[string.upper(brand)]
    if own ~= nil then
        colour, source = EqSponsorBoards.linear(own), "own"
        EqSponsorBoards.cache[brand] = { colour = colour, source = source }
        return colour, source
    end
    local ok, paints = EqLog.try("EqSponsorBoards paints", EqSponsorBoards.gamePaints)
    if ok and type(paints) == "table" then
        local found, name = EqSponsorBoards.pickPaint(brand, paints)
        if found ~= nil then colour, source = found, "game " .. tostring(name) end
    end
    if colour == nil and EqSponsorBoards.COLOURS[string.upper(brand)] ~= nil then
        colour, source = EqSponsorBoards.linear(EqSponsorBoards.COLOURS[string.upper(brand)]), "list"
    end
    EqSponsorBoards.cache[brand] = { colour = colour, source = source }
    return colour, source
end


--- The pole colour a jump takes from its farm's sponsor, if it has boards and a sponsor.
--- @param placeable table
--- @return table|nil colour, string|nil brand
function EqSponsorBoards.colourFor(placeable)
    if not EqSponsorBoards.isJump(placeable and placeable.configFileName) or not EqSponsorBoards.isOn(placeable) then return nil, nil end
    local farmId = placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() or nil
    if farmId == nil and g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then farmId = g_currentMission:getFarmId() end
    -- the brand whose logos the piece shows (EqSponsors: one per piece), else the lead sponsor's
    local brand = placeable.eqBrand
    local signed = EqSponsors ~= nil and EqSponsors.signedBrands ~= nil and farmId ~= nil and EqSponsors.signedBrands(farmId) or {}
    local isSigned = false
    for _, name in ipairs(signed) do if name == brand then isSigned = true end end
    if not isSigned then brand = signed[1] end
    local colour = EqSponsorBoards.brandColour(brand)
    return colour, colour ~= nil and brand or nil
end


--- eqSponsorColours: each brand of the shop and its jump colour, with where it came from.
function EqSponsorBoards.report()
    local lines = {}
    local _, source = EqSponsorBoards.gamePaints()
    table.insert(lines, "Game paints: " .. tostring(source or "not found"))
    local names = {}
    local manager = g_brandManager
    for _, brand in pairs(manager ~= nil and (manager.indexToBrand or manager.nameToBrand) or {}) do
        if type(brand) == "table" and type(brand.name) == "string" then names[brand.name] = true end
    end
    local sorted = {}
    for name in pairs(names) do table.insert(sorted, name) end
    table.sort(sorted)
    local missing = 0
    for _, name in ipairs(sorted) do
        local colour, from = EqSponsorBoards.brandColour(name)
        if colour ~= nil then
            table.insert(lines, string.format("%-20s %.3f %.3f %.3f  %s", name, colour[1], colour[2], colour[3], from))
        else
            missing = missing + 1
            table.insert(lines, string.format("%-20s none (shop colour)", name))
        end
    end
    table.insert(lines, string.format("%d brands, %d with no colour", #sorted, missing))
    return lines
end


--- @param guarded function main.lua's error guard
function EqSponsorBoards.install(guarded)
    guarded("sponsor boards configuration", EqSponsorBoards.registerConfiguration)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("show jump sponsor boards", EqSponsorBoards.update)
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        EqSponsorBoards.scannedAt, EqSponsorBoards.paints, EqSponsorBoards.paintSource, EqSponsorBoards.cache = nil, nil, nil, nil
    end)
end

--[[
    EqFacility.lua
    Horse facilities: which buildings count, and what they give. Pure functions over xml
    filenames, node names and counts, so they run headless; EqFacilityHooks finds the buildings
    in the game. See data/facilities.xml for what each attribute means.

    - A farm's facilities are counted per kind. Each kind gives its owned shares in full once the
      farm has fullAt of it, and its part below that.
    - Riding inside a facility adds the kind's ridden shares, weighted by the share of the day's
      riding done inside.
    - Owned and ridden shares are summed over kinds and capped; they speed up the monthly
      training rate, like feed does, and never add work.
]]

EqFacility = {}

local Log = EqLog


--- @param xmlFile table XMLFile handle
--- @param key string
--- @param prefix string "owned" or "ridden"
--- @return table shares stat -> share
local function readShares(xmlFile, key, prefix)
    local shares = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local attribute = prefix .. string.upper(string.sub(stat, 1, 1)) .. string.sub(stat, 2)
        shares[stat] = xmlFile:getFloat(key .. "#" .. attribute, 0)
    end
    return shares
end


--- @param text string|nil "dressage:0.03 showJumping:0.02"
--- @return table events discipline -> bonus
local function readEvents(text)
    local events = {}
    for name, value in string.gmatch(text or "", "([%w_]+):([%d%.]+)") do events[name] = tonumber(value) end
    return events
end


--- @param path string|nil
--- @return string path lowercased, with forward slashes
local function normalise(path)
    return string.lower(string.gsub(path or "", "\\", "/"))
end


--- @param xmlFile table An open XMLFile on facilities.xml
--- @return table config { kinds, kindByName, matches, keywords, nodes, ownedCap, riddenCap, eventCap }
function EqFacility.read(xmlFile)
    local config = {
        kinds = {}, kindByName = {}, matches = {}, keywords = {}, nodes = {},
        ownedCap = xmlFile:getFloat("facilities#ownedCap", 0.25),
        riddenCap = xmlFile:getFloat("facilities#riddenCap", 0.6),
        eventCap = xmlFile:getFloat("facilities#eventCap", 0.05),
    }

    local i = 0
    while true do
        local key = string.format("facilities.kind(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local kind = {
            name = xmlFile:getString(key .. "#name"),
            radius = xmlFile:getFloat(key .. "#radius", 25),
            fullAt = math.max(1, xmlFile:getInt(key .. "#fullAt", 1)),
            owned = readShares(xmlFile, key, "owned"),
            ridden = readShares(xmlFile, key, "ridden"),
            events = readEvents(xmlFile:getString(key .. "#events")),
        }
        table.insert(config.kinds, kind)
        config.kindByName[kind.name] = kind
        i = i + 1
    end

    local function readList(element, list, valueAttribute, transform)
        local j = 0
        while true do
            local key = string.format("facilities.%s(%d)", element, j)
            if not xmlFile:hasProperty(key) then break end
            local kind = xmlFile:getString(key .. "#kind")
            local value = xmlFile:getString(key .. "#" .. valueAttribute)
            if config.kindByName[kind] == nil or value == nil then
                Log:warning("EqFacility: %s %d names unknown kind '%s' or has no %s", element, j, tostring(kind), valueAttribute)
            else
                table.insert(list, { kind = kind, value = transform(value) })
            end
            j = j + 1
        end
    end

    readList("match", config.matches, "xml", normalise)
    readList("keyword", config.keywords, "pattern", string.lower)
    readList("node", config.nodes, "pattern", function(value) return value end)

    return config
end


--- @param path string
--- @return table|nil config
function EqFacility.load(path)
    local xmlFile = XMLFile.load("eqFacilities", path)
    if xmlFile == nil then
        Log:error("EqFacility: could not open %s", path)
        return nil
    end
    local config = EqFacility.read(xmlFile)
    xmlFile:delete()
    Log:info("EqFacility: %d kinds, %d buildings, %d keywords, %d map patterns", #config.kinds, #config.matches,
        #config.keywords, #config.nodes)
    return config
end


--- The kind of a placeable, from its xml filename.
--- @param config table
--- @param xmlFilename string|nil full path of the placeable's xml
--- @param isHusbandry boolean keywords are skipped for animal pens, which are not training places
--- @return string|nil kind
function EqFacility.kindForXml(config, xmlFilename, isHusbandry)
    if xmlFilename == nil then return nil end
    local path = normalise(xmlFilename)
    -- The game reports its own files as "data/placeables/...", with or without the "$".
    local gamePath = string.gsub(path, "^%$", "")

    for _, match in ipairs(config.matches) do
        local value = match.value
        if string.sub(value, 1, 6) == "$data/" then
            -- A base game file: the whole path must be the game's, not a mod folder that ends alike.
            if gamePath == string.sub(value, 2) then return match.kind end
        elseif string.sub(value, -4) == ".xml" then
            if string.sub(path, -#value) == value then return match.kind end
        else
            -- A prefix: ".../FS25_RidingHall/props" matches props01.xml, props11.xml.
            local start = string.find(path, value, 1, true)
            if start ~= nil and string.find(string.sub(path, start + #value), "/", 1, true) == nil then
                return match.kind
            end
        end
    end

    if isHusbandry then return nil end
    local filename = string.match(path, "[^/]+$") or path
    for _, keyword in ipairs(config.keywords) do
        -- The filename only: a mod's folder name also covers its decorations and letters.
        if string.find(filename, keyword.value) ~= nil then return keyword.kind end
    end
    return nil
end


--- @param config table
--- @param nodeName string|nil
--- @return string|nil kind
function EqFacility.kindForNode(config, nodeName)
    if nodeName == nil then return nil end
    for _, node in ipairs(config.nodes) do
        if string.find(nodeName, node.value) ~= nil then return node.kind end
    end
    return nil
end


--- Merge map scenery matches that stand within minDistance of an earlier one, so a prefab and
--- the model inside it count as one fence.
--- @param points table list of { kind, x, z }
--- @param minDistance number
--- @return table points
function EqFacility.dedupe(points, minDistance)
    local kept = {}
    local minSq = minDistance * minDistance
    for _, point in ipairs(points) do
        local duplicate = false
        for _, other in ipairs(kept) do
            local dx, dz = point.x - other.x, point.z - other.z
            if other.kind == point.kind and dx * dx + dz * dz < minSq then duplicate = true break end
        end
        if not duplicate then table.insert(kept, point) end
    end
    return kept
end


--- How much of a kind's bonus a farm has.
--- @param kind table
--- @param count number
--- @return number scale 0..1
function EqFacility.scale(kind, count)
    return math.min(1, (count or 0) / kind.fullAt)
end


--- Training rate shares for a horse.
--- @param config table
--- @param counts table kind name -> number the farm owns
--- @param insideShares table|nil kind name -> share (0..1) of the day's riding done inside
--- @return table owned stat -> share, for staff and player alike
--- @return table ridden stat -> share, on top of owned for the player's own riding
function EqFacility.boosts(config, counts, insideShares)
    local owned, ridden = {}, {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do owned[stat], ridden[stat] = 0, 0 end

    for _, kind in ipairs(config.kinds) do
        local scale = EqFacility.scale(kind, counts[kind.name])
        local inside = (insideShares ~= nil and insideShares[kind.name]) or 0
        for _, stat in ipairs(EqConstants.STAT_KEYS) do
            owned[stat] = owned[stat] + kind.owned[stat] * scale
            if scale > 0 then ridden[stat] = ridden[stat] + kind.ridden[stat] * math.min(1, inside) end
        end
    end

    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        owned[stat] = math.min(owned[stat], config.ownedCap)
        ridden[stat] = math.min(ridden[stat], config.riddenCap)
    end
    return owned, ridden
end


--- @param config table
--- @param counts table kind name -> number the farm owns
--- @param discipline string
--- @return number bonus share added to a horse's condition on the day
function EqFacility.eventBonus(config, counts, discipline)
    local bonus = 0
    for _, kind in ipairs(config.kinds) do
        bonus = bonus + (kind.events[discipline] or 0) * EqFacility.scale(kind, counts[kind.name])
    end
    return math.min(bonus, config.eventCap)
end


--- Share of the day's riding done inside each kind.
--- @param sheet table|nil EqTraining sheet
--- @return table kind name -> share 0..1
function EqFacility.insideShares(sheet)
    local shares = {}
    if sheet == nil or sheet.inside == nil then return shares end
    local total = 0
    for _, ms in pairs(sheet.ms) do total = total + ms end
    if total <= 0 then return shares end
    for kind, ms in pairs(sheet.inside) do shares[kind] = math.min(1, ms / total) end
    return shares
end


--- The stats a kind trains, strongest first, for "Improves Agility and Temperament training".
--- @param kind table
--- @return table stats list of stat keys
function EqFacility.improvedStats(kind)
    local stats = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if kind.owned[stat] > 0 or kind.ridden[stat] > 0 then table.insert(stats, stat) end
    end
    table.sort(stats, function(a, b)
        local sa, sb = kind.owned[a] + kind.ridden[a], kind.owned[b] + kind.ridden[b]
        if sa ~= sb then return sa > sb end
        return a < b
    end)
    return stats
end

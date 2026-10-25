--[[
    EqFacilityHooks.lua
    Finds horse facilities in the game for EqFacility.

    - Placeables are matched by xml filename (data/facilities.xml) and belong to their owner farm.
      They are read from the placeable system on demand, so buying and selling needs no hook.
    - Map scenery (Elmcreek 25's show jumping course is loose map nodes, not a placeable) is
      found once when the map has loaded, by node name, and belongs to whoever owns the farmland
      under it.
    - Riding inside a facility is a position test: inside the placeable's own placement test
      areas when it has them, else within the kind's radius of its origin.
    - Shop entries of matched buildings get an "Improves ... training" line.
]]

EqFacilityHooks = {}
EqFacilityHooks.config = nil
EqFacilityHooks.mapPoints = {}
EqFacilityHooks.areas = setmetatable({}, { __mode = "k" })
EqFacilityHooks.countCache = {}

-- Margin around a placeable's test areas that still counts as inside, in metres.
local AREA_MARGIN = 2
-- Map scenery matches closer than this count as one.
local DEDUPE_DISTANCE = 2
-- How long a position or count result is reused, in milliseconds.
local INSIDE_CACHE_MS = 1000
local COUNT_CACHE_MS = 5000

local Log = EqLog


--- @param modDirectory string
function EqFacilityHooks.loadConfig(modDirectory)
    EqFacilityHooks.config = EqFacility.load(modDirectory .. "data/facilities.xml")
end


function EqFacilityHooks.reset()
    EqFacilityHooks.mapPoints = {}
    EqFacilityHooks.areas = setmetatable({}, { __mode = "k" })
    EqFacilityHooks.countCache = {}
end


--- @return number ms game time, 0 before the mission runs
local function now()
    return g_time or 0
end


--- @param placeable table
--- @return string|nil kind
function EqFacilityHooks.kindOfPlaceable(placeable)
    local config = EqFacilityHooks.config
    if config == nil or placeable == nil then return nil end
    if placeable.eqFacilityKind == nil then
        local kind = EqFacility.kindForXml(config, placeable.configFileName, placeable.spec_husbandryAnimals ~= nil)
        placeable.eqFacilityKind = kind or false
    end
    return placeable.eqFacilityKind or nil
end


--- @param placeable table
--- @return number|nil farmId
local function ownerOf(placeable)
    if placeable.getOwnerFarmId == nil then return nil end
    return placeable:getOwnerFarmId()
end


--- @param x number
--- @param z number
--- @return number|nil farmId owner of the farmland at the position
function EqFacilityHooks.farmlandOwnerAt(x, z)
    local manager = g_farmlandManager
    if manager == nil or manager.getFarmlandIdAtWorldPosition == nil then return nil end
    local farmlandId = manager:getFarmlandIdAtWorldPosition(x, z)
    if farmlandId == nil or farmlandId == 0 then return nil end
    return manager:getFarmlandOwner(farmlandId)
end


--- Every facility placeable, with its kind.
--- @return table list of { placeable, kind }
function EqFacilityHooks.listPlaceables()
    local list = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return list end
    for _, placeable in ipairs(system.placeables) do
        local kind = EqFacilityHooks.kindOfPlaceable(placeable)
        if kind ~= nil then table.insert(list, { placeable = placeable, kind = kind }) end
    end
    return list
end


--- How many of each kind a farm has. Cached for a few seconds: the Events tab asks per event.
--- @param farmId number|nil
--- @return table kind name -> count
function EqFacilityHooks.countsForFarm(farmId)
    if farmId == nil or EqFacilityHooks.config == nil then return {} end
    local cached = EqFacilityHooks.countCache[farmId]
    if cached ~= nil and now() - cached.time < COUNT_CACHE_MS and now() >= cached.time then return cached.counts end

    local counts = {}
    for _, entry in ipairs(EqFacilityHooks.listPlaceables()) do
        if ownerOf(entry.placeable) == farmId then counts[entry.kind] = (counts[entry.kind] or 0) + 1 end
    end
    for _, point in ipairs(EqFacilityHooks.mapPoints) do
        if EqFacilityHooks.farmlandOwnerAt(point.x, point.z) == farmId then counts[point.kind] = (counts[point.kind] or 0) + 1 end
    end

    EqFacilityHooks.countCache[farmId] = { time = now(), counts = counts }
    return counts
end


--- A placeable's placement test areas as boxes in its own space, measured once.
--- @param placeable table
--- @return table boxes list of { minX, maxX, minZ, maxZ }, empty when it has none
local function areasOf(placeable)
    local boxes = EqFacilityHooks.areas[placeable]
    if boxes ~= nil then return boxes end

    boxes = {}
    local spec = placeable.spec_placement
    local rootNode = placeable.rootNode
    if spec ~= nil and type(spec.testAreas) == "table" and rootNode ~= nil then
        for _, area in ipairs(spec.testAreas) do
            local startNode, endNode = area.startNode, area.endNode
            if startNode ~= nil and endNode ~= nil then
                local x1, _, z1 = localToLocal(startNode, rootNode, 0, 0, 0)
                local x2, _, z2 = localToLocal(endNode, rootNode, 0, 0, 0)
                table.insert(boxes, {
                    minX = math.min(x1, x2) - AREA_MARGIN, maxX = math.max(x1, x2) + AREA_MARGIN,
                    minZ = math.min(z1, z2) - AREA_MARGIN, maxZ = math.max(z1, z2) + AREA_MARGIN,
                })
            end
        end
    end
    EqFacilityHooks.areas[placeable] = boxes
    return boxes
end


--- @param placeable table
--- @param kind table EqFacility kind
--- @param x number
--- @param y number
--- @param z number
--- @return boolean inside
local function isInsidePlaceable(placeable, kind, x, y, z)
    local rootNode = placeable.rootNode
    if rootNode == nil then return false end

    local boxes = areasOf(placeable)
    if #boxes > 0 then
        local lx, _, lz = worldToLocal(rootNode, x, y, z)
        for _, box in ipairs(boxes) do
            if lx >= box.minX and lx <= box.maxX and lz >= box.minZ and lz <= box.maxZ then return true end
        end
        return false
    end

    local px, _, pz = getWorldTranslation(rootNode)
    local dx, dz = x - px, z - pz
    return dx * dx + dz * dz <= kind.radius * kind.radius
end


--- The facility kinds a farm owns at a position.
--- @param farmId number|nil
--- @param x number
--- @param y number
--- @param z number
--- @return table kind name -> true
function EqFacilityHooks.kindsAt(farmId, x, y, z)
    local kinds = {}
    local config = EqFacilityHooks.config
    if config == nil or farmId == nil then return kinds end

    for _, entry in ipairs(EqFacilityHooks.listPlaceables()) do
        if not kinds[entry.kind] and ownerOf(entry.placeable) == farmId
            and isInsidePlaceable(entry.placeable, config.kindByName[entry.kind], x, y, z) then
            kinds[entry.kind] = true
        end
    end

    for _, point in ipairs(EqFacilityHooks.mapPoints) do
        if not kinds[point.kind] then
            local radius = config.kindByName[point.kind].radius
            local dx, dz = x - point.x, z - point.z
            if dx * dx + dz * dz <= radius * radius and EqFacilityHooks.farmlandOwnerAt(point.x, point.z) == farmId then
                kinds[point.kind] = true
            end
        end
    end
    return kinds
end


--- The kinds a ridden horse is inside, rechecked once a second.
--- @param vehicle table a rideable
--- @return table kind name -> true
function EqFacilityHooks.insideKinds(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil or EqFacilityHooks.config == nil or vehicle.rootNode == nil then return {} end
    local time = now()
    if spec.eqInsideKinds == nil or time - (spec.eqInsideCheckedAt or 0) >= INSIDE_CACHE_MS or time < (spec.eqInsideCheckedAt or 0) then
        local x, y, z = getWorldTranslation(vehicle.rootNode)
        local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
        spec.eqInsideKinds = EqFacilityHooks.kindsAt(farmId, x, y, z)
        spec.eqInsideCheckedAt = time
    end
    return spec.eqInsideKinds
end


--- @param animal table RLRM Animal
--- @return number|nil farmId the farm of the husbandry the horse lives in
function EqFacilityHooks.farmOfAnimal(animal)
    local system = animal ~= nil and animal.clusterSystem or nil
    local owner = system ~= nil and system.owner or nil
    if owner == nil or owner.getOwnerFarmId == nil then return nil end
    return owner:getOwnerFarmId()
end


--- Training shares for one horse's day.
--- @param farmId number|nil
--- @param sheet table|nil the day's EqTraining sheet
--- @return table|nil owned, table|nil ridden stat -> share; nil without the config
function EqFacilityHooks.boostsFor(farmId, sheet)
    local config = EqFacilityHooks.config
    if config == nil or farmId == nil then return nil, nil end
    return EqFacility.boosts(config, EqFacilityHooks.countsForFarm(farmId), EqFacility.insideShares(sheet))
end


--- @param farmId number|nil
--- @param discipline string
--- @return number factor to multiply a horse's condition with (1 without facilities)
function EqFacilityHooks.conditionFactor(farmId, discipline)
    local config = EqFacilityHooks.config
    if config == nil or farmId == nil then return 1 end
    return 1 + EqFacility.eventBonus(config, EqFacilityHooks.countsForFarm(farmId), discipline)
end


--- Walk the map once for scenery facilities. Call when the map has loaded.
function EqFacilityHooks.scanMap()
    local config = EqFacilityHooks.config
    EqFacilityHooks.mapPoints = {}
    if config == nil or #config.nodes == 0 then return end

    local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
    local mapRoot = (terrain ~= nil and terrain ~= 0) and getParent(terrain) or getRootNode()

    local found, visited = {}, 0
    local stack = { mapRoot }
    while #stack > 0 do
        local node = table.remove(stack)
        visited = visited + 1
        local kind = EqFacility.kindForNode(config, getName(node))
        if kind ~= nil then
            local x, _, z = getWorldTranslation(node)
            table.insert(found, { kind = kind, x = x, z = z, name = getName(node) })
        end
        for i = getNumOfChildren(node) - 1, 0, -1 do table.insert(stack, getChildAt(node, i)) end
    end

    EqFacilityHooks.mapPoints = EqFacility.dedupe(found, DEDUPE_DISTANCE)
    Log:info("EqFacility: %d map scenery facilities (from %d matching nodes, %d nodes walked)",
        #EqFacilityHooks.mapPoints, #found, visited)
end


--- "Improves Agility and Temperament training" on matched shop entries.
function EqFacilityHooks.addStoreText()
    local config = EqFacilityHooks.config
    if config == nil or g_storeManager == nil then return end

    local added = 0
    for _, item in ipairs(g_storeManager:getItems()) do
        -- Keywords stay out of the shop: they are a fallback for buildings we have not checked.
        local kind = EqFacility.kindForXml(config, item.xmlFilename, true)
        if kind ~= nil and not item.eqFacilityText and type(item.functions) == "table" then
            local names = {}
            for _, stat in ipairs(EqFacility.improvedStats(config.kindByName[kind])) do
                table.insert(names, g_i18n:getText("eq_stat_" .. stat))
            end
            if #names > 0 then
                local list = #names == 1 and names[1]
                    or table.concat(names, ", ", 1, #names - 1) .. " " .. g_i18n:getText("eq_and") .. " " .. names[#names]
                table.insert(item.functions, string.format(g_i18n:getText("eq_facility_improves"), list))
                item.eqFacilityText = true
                added = added + 1
            end
        end
    end
    Log:debug("EqFacility: training line added to %d shop entries", added)
end


--- @param kind string
--- @return string title
function EqFacilityHooks.kindTitle(kind)
    return g_i18n:getText("eq_facility_" .. kind)
end


--- "Riding hall" and {"Agility +35%", "Temperament +35%", "Stamina +15%"}: what riding inside a
--- kind adds to the player's own training, biggest first, scaled by how much of it the farm has (a
--- jump course needs six fences for the full bonus). Before the ridden cap, which only bites when
--- several kinds add up. Separate lines because the help panel cuts long lines off.
--- @param kindName string
--- @param farmId number|nil
--- @return string title
--- @return table bonuses one "Stat +N%" string per stat, maybe empty
function EqFacilityHooks.insideText(kindName, farmId)
    local title = EqFacilityHooks.kindTitle(kindName)
    local config = EqFacilityHooks.config
    local kind = config ~= nil and config.kindByName[kindName] or nil
    if kind == nil then return title, {} end

    local scale = EqFacility.scale(kind, EqFacilityHooks.countsForFarm(farmId)[kindName])
    local stats = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if kind.ridden[stat] * scale > 0 then table.insert(stats, stat) end
    end
    table.sort(stats, function(a, b) return kind.ridden[a] > kind.ridden[b] end)

    local parts = {}
    for _, stat in ipairs(stats) do
        table.insert(parts, string.format("%s +%d%%", g_i18n:getText("eq_stat_" .. stat),
            math.floor(kind.ridden[stat] * scale * 100 + 0.5)))
    end
    return title, parts
end

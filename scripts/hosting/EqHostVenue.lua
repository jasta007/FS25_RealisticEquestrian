--[[
    EqHostVenue.lua
    Reads a farm into the venue table EqHosting checks: its recorded courses and dressage arenas,
    the bleachers near each, whether each is indoors, free places in its horse pens, and the
    horse feed in its troughs and storage.

    - Courses are the ones recorded by riding (EqCourse.list); every saved course counts.
    - Arenas are our dressage arena placeables and Riding Hall letter boards (EqDressageHooks).
    - Bleachers are placeables data/hosting.xml names, owned by the farm.
    - Indoors means inside an indoor arena or riding centre (EqFacilityHooks).
    - Feed is every horse feed fill type, in the farm's horse troughs and its silos.
    - Shops are farm shops (by name) and productions making goods visitors buy; goods are those
      in the farm's productions and silos (data/hosting.xml <shops>).

    Part of Realistic Equestrian by Jasta007.
]]

EqHostVenue = {}
EqHostVenue.config = nil

-- Facility kinds that put a course or arena indoors, and the ones that count as horse
-- facilities for popularity.
EqHostVenue.INDOOR_KINDS = { indoorArena = true, ridingCentre = true }
EqHostVenue.TRAINING_KINDS = { "indoorArena", "ridingCentre", "outdoorArena", "roundPen", "jumps", "xcFence" }
-- A visiting horse eats like an adult horse of this age (months).
EqHostVenue.VISITOR_AGE = 96

local Log = EqLog


--- @param modDirectory string
function EqHostVenue.loadConfig(modDirectory)
    EqHostVenue.config = EqHosting.load(modDirectory .. "data/hosting.xml")
end


--- @param placeable table
--- @return number|nil farmId
local function ownerOf(placeable)
    if placeable.getOwnerFarmId == nil then return nil end
    return placeable:getOwnerFarmId()
end


--- @return table list of placeables, empty before the mission runs
local function placeables()
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    return system ~= nil and system.placeables or {}
end


--- @param placeable table
--- @return number|nil x, number|nil z
local function positionOf(placeable)
    local node = placeable.rootNode
    if type(node) ~= "number" or node == 0 then return nil end
    local x, _, z = getWorldTranslation(node)
    return x, z
end


--- @param farmId number
--- @return table list of { x, z } for every bleacher the farm owns
function EqHostVenue.bleachers(farmId)
    local list = {}
    local config = EqHostVenue.config
    if config == nil then return list end
    for _, placeable in ipairs(placeables()) do
        if ownerOf(placeable) == farmId and EqHosting.isSeatingXml(config, placeable.configFileName) then
            local x, z = positionOf(placeable)
            if x ~= nil then table.insert(list, { x = x, z = z }) end
        end
    end
    return list
end


--- @param farmId number
--- @param x number
--- @param z number
--- @return boolean true when the point is inside one of the farm's indoor arenas
local function isIndoor(farmId, x, z)
    local y = 0
    if g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
        y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    end
    for kind in pairs(EqFacilityHooks.kindsAt(farmId, x, y, z)) do
        if EqHostVenue.INDOOR_KINDS[kind] then return true end
    end
    return false
end


--- @param list table points { x, z }
--- @return number|nil x, number|nil z their middle
local function middleOf(list)
    if #list == 0 then return nil end
    local sx, sz = 0, 0
    for _, point in ipairs(list) do sx, sz = sx + point.x, sz + point.z end
    return sx / #list, sz / #list
end


--- @param farmId number
--- @param seats table from bleachers
--- @return table courses
function EqHostVenue.courses(farmId, seats)
    local radius = EqHostVenue.config.seatingRadius
    local list = {}
    for _, course in ipairs(EqCourse.list) do
        local seating = 0
        for _, seat in ipairs(seats) do
            if EqCourse.distanceTo(course, seat.x, seat.z) <= radius then seating = seating + 1 end
        end
        local mx, mz = middleOf(#course.jumps > 0 and course.jumps or course.points)
        table.insert(list, { name = course.name, kind = course.kind or EqCourse.SHOW_JUMPING, jumps = #course.jumps,
            length = course.length or EqCourse.pathLength(course.points), seating = seating,
            indoor = mx ~= nil and isIndoor(farmId, mx, mz) or false, quality = EqHostVenue.quality(course), source = course })
    end
    return list
end


--- How well built a recorded course is (EqHosting.courseQuality): its jumps matched to the
--- jumps on the map for their type. Kept on the course until it changes, so the Host tab and
--- the daily checks don't search the map again.
--- @param course table EqCourse course
--- @return number quality 0..1
function EqHostVenue.quality(course)
    local key = string.format("%d %.1f", #course.jumps, course.length or 0)
    if course.eqQualityKey == key then return course.eqQuality end
    local onMap = {}
    if EqCourseHooks ~= nil and EqCourseHooks.listJumps ~= nil then
        local ok, list = EqLog.try("EqHostVenue.quality listJumps", EqCourseHooks.listJumps, course.kind)
        if ok and type(list) == "table" then onMap = list end
    end
    local jumps = {}
    for _, jump in ipairs(course.jumps) do
        local kind
        for _, other in ipairs(onMap) do
            if math.abs(other.x - jump.x) < 1.5 and math.abs(other.z - jump.z) < 1.5 then
                kind = other.type
                break
            end
        end
        table.insert(jumps, { x = jump.x, z = jump.z, type = kind })
    end
    course.eqQuality = EqHosting.courseQuality(EqHostVenue.config, jumps)
    course.eqQualityKey = key
    return course.eqQuality
end


--- The share of a cross country course's jumps that are outdoors. Asked once, when a hosted
--- event opens (James, 2026-11-01: keep it light).
--- @param farmId number
--- @param pick table|nil a course from EqHostVenue.courses
--- @return number|nil share 0..1, nil without jumps
function EqHostVenue.outdoorShareOf(farmId, pick)
    local course = pick ~= nil and pick.source or nil
    if course == nil or #course.jumps == 0 then return nil end
    local outside = 0
    for _, jump in ipairs(course.jumps) do
        if not isIndoor(farmId, jump.x, jump.z) then outside = outside + 1 end
    end
    return outside / #course.jumps
end


--- @param farmId number
--- @param seats table from bleachers
--- @return table arenas
function EqHostVenue.arenas(farmId, seats)
    local radius = EqHostVenue.config.seatingRadius
    local list = EqHosting.arenasFromMarkers(EqDressageHooks.scan())
    for i, arena in ipairs(list) do
        arena.name = string.format("%dx%d", arena.length == 30 and 15 or 20, arena.length)
        arena.seating = 0
        for _, seat in ipairs(seats) do
            if math.sqrt((seat.x - arena.x) ^ 2 + (seat.z - arena.z) ^ 2) <= radius + arena.halfLength then
                arena.seating = arena.seating + 1
            end
        end
        arena.indoor = isIndoor(farmId, arena.x, arena.z)
        arena.index = i
    end
    return list
end


--- @param placeable table
--- @return boolean true for a pen that keeps horses
local function isHorsePen(placeable)
    local spec = placeable.spec_husbandryAnimals
    return spec ~= nil and AnimalType ~= nil and spec.animalTypeIndex == AnimalType.HORSE
end


--- @return number|nil subTypeIndex a horse subtype, to ask pens for room
local function horseSubType()
    local system = g_currentMission ~= nil and g_currentMission.animalSystem or nil
    for index, subType in ipairs(system ~= nil and system.subTypes or {}) do
        if subType.typeIndex == AnimalType.HORSE then return subType.subTypeIndex or index end
    end
    return nil
end


--- @param farmId number
--- @return number free places for horses in the farm's horse pens
function EqHostVenue.freePlaces(farmId)
    local subTypeIndex = horseSubType()
    local free = 0
    for _, placeable in ipairs(placeables()) do
        if ownerOf(placeable) == farmId and isHorsePen(placeable) and placeable.getNumOfFreeAnimalSlots ~= nil then
            local ok, count = EqLog.try("EqHostVenue.freePlaces", placeable.getNumOfFreeAnimalSlots, placeable, subTypeIndex)
            if ok and type(count) == "number" then free = free + math.max(0, count) end
        end
    end
    return free
end


--- @return table fillTypeIndex -> true for every fill type horses eat
function EqHostVenue.feedTypes()
    local types = {}
    local foodSystem = g_currentMission ~= nil and g_currentMission.animalFoodSystem or nil
    local animalFood = foodSystem ~= nil and foodSystem.getAnimalFood ~= nil and foodSystem:getAnimalFood(AnimalType.HORSE) or nil
    for _, group in ipairs(animalFood ~= nil and animalFood.groups or {}) do
        for key, value in pairs(group.fillTypes or {}) do
            -- The groups hold either a list of indices or a set of them.
            if value == true then types[key] = true elseif type(value) == "number" then types[value] = true end
        end
    end
    return types
end


--- @param placeable table
--- @return table list of the placeable's Storage objects
local function storagesOf(placeable)
    local list = {}
    local silo = placeable.spec_silo
    for _, storage in ipairs(silo ~= nil and silo.storages or {}) do table.insert(list, storage) end
    local extension = placeable.spec_siloExtension
    if extension ~= nil and extension.storage ~= nil then table.insert(list, extension.storage) end
    return list
end


--- The farm's horse feed, in litres: what its horse pens' troughs hold and what is in its silos.
--- @param farmId number
--- @return number litres
--- @return table sources list of { name, litres }, for the console
function EqHostVenue.feed(farmId)
    local types = EqHostVenue.feedTypes()
    local total, sources, seen = 0, {}, {}
    for _, placeable in ipairs(placeables()) do
        if ownerOf(placeable) == farmId then
            local litres = 0
            local food = placeable.spec_husbandryFood
            if isHorsePen(placeable) and food ~= nil and food.fillLevels ~= nil then
                for index, level in pairs(food.fillLevels) do
                    if types[index] and type(level) == "number" then litres = litres + level end
                end
            end
            for _, storage in ipairs(storagesOf(placeable)) do
                if not seen[storage] and storage.getFillLevel ~= nil then
                    seen[storage] = true
                    for index in pairs(types) do
                        local ok, level = EqLog.try("EqHostVenue.feed getFillLevel", storage.getFillLevel, storage, index)
                        if ok and type(level) == "number" then litres = litres + level end
                    end
                end
            end
            if litres > 0 then
                total = total + litres
                table.insert(sources, { name = placeable.getName ~= nil and placeable:getName() or "?", litres = litres })
            end
        end
    end
    return total, sources
end


--- Take horse feed from the farm: its silos first, then its horse troughs.
--- @param farmId number
--- @param litres number
--- @return number taken litres actually taken
function EqHostVenue.takeFeed(farmId, litres)
    local types = EqHostVenue.feedTypes()
    local indices = {}
    for index in pairs(types) do table.insert(indices, index) end
    table.sort(indices)
    local left, seen = litres, {}
    local pens = {}
    for _, placeable in ipairs(placeables()) do
        if ownerOf(placeable) == farmId then
            if isHorsePen(placeable) and placeable.spec_husbandryFood ~= nil then table.insert(pens, placeable) end
            for _, storage in ipairs(storagesOf(placeable)) do
                if left > 0 and not seen[storage] and storage.getFillLevel ~= nil and storage.setFillLevel ~= nil then
                    seen[storage] = true
                    for _, index in ipairs(indices) do
                        local ok, level = EqLog.try("EqHostVenue.takeFeed getFillLevel", storage.getFillLevel, storage, index)
                        if left > 0 and ok and type(level) == "number" and level > 0 then
                            local take = math.min(level, left)
                            if EqLog.try("EqHostVenue.takeFeed setFillLevel", storage.setFillLevel, storage, level - take, index) then
                                left = left - take
                            end
                        end
                    end
                end
            end
        end
    end
    -- Troughs: the base game's addFood takes a negative amount and stops at empty.
    for _, pen in ipairs(pens) do
        local spec = pen.spec_husbandryFood
        for _, index in ipairs(indices) do
            local level = spec.fillLevels ~= nil and spec.fillLevels[index] or nil
            if left > 0 and type(level) == "number" and level > 0 and pen.addFood ~= nil then
                EqLog.try("EqHostVenue.takeFeed addFood", pen.addFood, pen, farmId, -math.min(level, left), index, nil, nil, nil)
                local after = spec.fillLevels[index] or level
                left = left - math.max(0, level - after)
            end
        end
    end
    return litres - left
end


--- @return number litres a visiting horse eats in a month (RLRM's food curve is a month's ration)
function EqHostVenue.feedPerHorse()
    local system = g_currentMission ~= nil and g_currentMission.animalSystem or nil
    for _, subType in ipairs(system ~= nil and system.subTypes or {}) do
        if subType.typeIndex == AnimalType.HORSE and subType.input ~= nil and subType.input.food ~= nil then
            local food = subType.input.food:get(EqHostVenue.VISITOR_AGE) or 0
            local scale = EqRLRM.get("RealisticLivestock_PlaceableHusbandryFood")
            return food * (scale ~= nil and scale.foodScale or 1)
        end
    end
    return 0
end


--- @param farmId number
--- @return number kinds of horse facility the farm owns
function EqHostVenue.facilityKinds(farmId)
    local counts = EqFacilityHooks.countsForFarm(farmId)
    local kinds = 0
    for _, kind in ipairs(EqHostVenue.TRAINING_KINDS) do
        if (counts[kind] or 0) > 0 then kinds = kinds + 1 end
    end
    return kinds
end


-- GOODS VISITORS BUY (James, 2026-11-01): a shop or a production making goods visitors buy draws
-- a crowd, and more goods in stock more so; at the event visitors can buy a few hundred litres.

--- @return table fillTypeIndex -> name for the goods data/hosting.xml lists that this game knows
function EqHostVenue.goodsTypes()
    local types = {}
    local config = EqHostVenue.config
    if config == nil or config.shops == nil or g_fillTypeManager == nil then return types end
    for _, name in ipairs(config.shops.goods) do
        local index = g_fillTypeManager:getFillTypeIndexByName(name)
        if index ~= nil then types[index] = name end
    end
    return types
end


--- @param placeable table
--- @return boolean true for a farm shop and the like (data/hosting.xml shop keywords)
local function isShop(placeable)
    local file = string.lower(tostring(placeable.configFileName or ""))
    for _, keyword in ipairs(EqHostVenue.config.shops.keywords) do
        if string.find(file, keyword) then return true end
    end
    return false
end


--- @param farmId number
--- @return table list of the farm's production points
local function productionsOf(farmId)
    local manager = g_currentMission ~= nil and g_currentMission.productionChainManager or nil
    if manager == nil or manager.getProductionPointsForFarmId == nil then return {} end
    local ok, list = EqLog.try("EqHostVenue productions", manager.getProductionPointsForFarmId, manager, farmId)
    return ok and type(list) == "table" and list or {}
end


--- The goods the farm can sell to visitors: what its productions and silos hold.
--- @param farmId number
--- @return table shops { sources, goods (kinds with at least minStock), stock = list of { index, name, litres } }
function EqHostVenue.goods(farmId)
    local shops = { sources = 0, goods = 0, stock = {} }
    local config = EqHostVenue.config
    if config == nil or config.shops == nil then return shops end
    local types = EqHostVenue.goodsTypes()
    if next(types) == nil then return shops end
    local litres, seen = {}, {}
    local function count(storage)
        if storage == nil or seen[storage] or storage.getFillLevel == nil then return end
        seen[storage] = true
        for index in pairs(types) do
            local ok, level = EqLog.try("EqHostVenue.goods getFillLevel", storage.getFillLevel, storage, index)
            if ok and type(level) == "number" and level > 0 then litres[index] = (litres[index] or 0) + level end
        end
    end
    for _, production in ipairs(productionsOf(farmId)) do
        local makesGoods = false
        for index in pairs(production.outputFillTypeIds or {}) do
            if types[index] ~= nil then makesGoods = true end
        end
        if makesGoods then shops.sources = shops.sources + 1 end
        count(production.storage)
    end
    for _, placeable in ipairs(placeables()) do
        if ownerOf(placeable) == farmId then
            if isShop(placeable) then shops.sources = shops.sources + 1 end
            for _, storage in ipairs(storagesOf(placeable)) do count(storage) end
        end
    end
    for index, amount in pairs(litres) do
        table.insert(shops.stock, { index = index, name = types[index], litres = amount })
        if amount >= config.shops.minStock then shops.goods = shops.goods + 1 end
    end
    table.sort(shops.stock, function(a, b) return a.name < b.name end)
    return shops
end


--- The best price a selling point pays for a fill type, per litre.
--- @param index number fill type index
--- @return number price
function EqHostVenue.bestPrice(index)
    local best = 0
    local system = g_currentMission ~= nil and g_currentMission.storageSystem or nil
    if system ~= nil and system.getUnloadingStations ~= nil then
        for _, station in pairs(system:getUnloadingStations() or {}) do
            local accepts = station.acceptedFillTypes ~= nil and station.acceptedFillTypes[index]
                or station.supportedFillTypes ~= nil and station.supportedFillTypes[index]
            if station.isSellingPoint and accepts and station.getEffectiveFillTypePrice ~= nil then
                local ok, price = EqLog.try("EqHostVenue.bestPrice", station.getEffectiveFillTypePrice, station, index)
                if ok and type(price) == "number" and price > best then best = price end
            end
        end
    end
    if best <= 0 and g_fillTypeManager ~= nil then
        local fillType = g_fillTypeManager:getFillTypeByIndex(index)
        best = fillType ~= nil and fillType.pricePerLiter or 0
    end
    return best
end


--- Take goods from the farm: its productions first, then its silos.
--- @param farmId number
--- @param index number fill type index
--- @param litres number
--- @return number taken
function EqHostVenue.takeGoods(farmId, index, litres)
    local left, seen = litres, {}
    local function take(storage)
        if left <= 0 or storage == nil or seen[storage] or storage.getFillLevel == nil or storage.setFillLevel == nil then return end
        seen[storage] = true
        local ok, level = EqLog.try("EqHostVenue.takeGoods getFillLevel", storage.getFillLevel, storage, index)
        if ok and type(level) == "number" and level > 0 then
            local amount = math.min(level, left)
            if EqLog.try("EqHostVenue.takeGoods setFillLevel", storage.setFillLevel, storage, level - amount, index) then
                left = left - amount
            end
        end
    end
    for _, production in ipairs(productionsOf(farmId)) do take(production.storage) end
    for _, placeable in ipairs(placeables()) do
        if ownerOf(placeable) == farmId then
            for _, storage in ipairs(storagesOf(placeable)) do take(storage) end
        end
    end
    return litres - left
end


--- Everything EqHosting.check needs about a farm.
--- @param farmId number
--- @return table venue
function EqHostVenue.read(farmId)
    local seats = EqHostVenue.bleachers(farmId)
    local feed, sources = EqHostVenue.feed(farmId)
    return {
        bleachers = seats,
        courses = EqHostVenue.courses(farmId, seats),
        arenas = EqHostVenue.arenas(farmId, seats),
        freePlaces = EqHostVenue.freePlaces(farmId),
        feed = feed,
        feedSources = sources,
        feedPerHorse = EqHostVenue.feedPerHorse(),
        facilityKinds = EqHostVenue.facilityKinds(farmId),
        shops = EqHostVenue.goods(farmId),
    }
end

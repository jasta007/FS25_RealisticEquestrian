--[[
    EqDealerStock.lua
    Fewer horses at the animal dealer. RLRM keeps a pool of 10 to 50 horses spread over every
    colour and gender and refills it every hour, so there were always plenty to pick from.

    Each colour and gender (an RLRM subtype, such as HORSE_BAY or STALLION_BAY) gets a shelf
    size from 0 to DEALER_SHELF_MAX each in-game month, topped up so the whole stock is at least
    DEALER_SHELF_MIN_TOTAL. The rolls are seeded from the month, so a reload gives the same shelves.

    Every horse the dealer adds goes through RLRM's AnimalSystem:createNewSaleAnimal (the new
    game fill, the hourly refill, Reset dealer, a dealer quality change). The hook hides the full
    kinds from RLRM's pick for that one call, so a new horse is always one of a kind with room,
    and adds nothing when every kind is full. Listings over a shelf size (an older save, or a
    smaller shelf next month) are taken off once an hour. Other animals are left alone. No RLRM
    files change. Without RLRM the base game dealer has no individual horses, so there is
    nothing to limit.
]]

EqDealerStock = {}

local Log = EqLog

-- Kept per month so the shelves only roll once: { key = "year:period", shelves = { name = n } }
EqDealerStock.cache = nil


--- Shelf sizes for one month. Pure.
--- @param kinds table subtype names, in any order
--- @param seedText string the same text gives the same shelves
--- @param maxEach number|nil default DEALER_SHELF_MAX
--- @param minTotal number|nil default DEALER_SHELF_MIN_TOTAL
--- @return table shelves name -> horses
function EqDealerStock.rollShelves(kinds, seedText, maxEach, minTotal)
    maxEach = maxEach or EqConstants.DEALER_SHELF_MAX
    minTotal = minTotal or EqConstants.DEALER_SHELF_MIN_TOTAL

    local names = {}
    for _, name in ipairs(kinds) do table.insert(names, name) end
    table.sort(names)

    local rng = EqRandom.new("dealer shelves " .. seedText)
    local shelves, total = {}, 0
    for _, name in ipairs(names) do
        local size = math.min(math.floor(rng:next() * (maxEach + 1)), maxEach)
        shelves[name] = size
        total = total + size
    end

    minTotal = math.min(minTotal, #names * maxEach)
    while total < minTotal do
        local open = {}
        for _, name in ipairs(names) do
            if shelves[name] < maxEach then table.insert(open, name) end
        end
        local name = open[math.min(math.floor(rng:next() * #open) + 1, #open)]
        shelves[name] = shelves[name] + 1
        total = total + 1
    end

    return shelves
end


--- How many listings each kind has. Pure.
--- @param animals table RLRM sale animals of one type
--- @param kindOf function animal -> subtype name or nil
--- @return table counts name -> listings
function EqDealerStock.countKinds(animals, kindOf)
    local counts = {}
    for _, animal in ipairs(animals or {}) do
        local name = animal.sale ~= nil and kindOf(animal) or nil
        if name ~= nil then counts[name] = (counts[name] or 0) + 1 end
    end
    return counts
end


--- Positions of the listings over their kind's shelf, the newest of each kind first to go. Pure.
--- Kinds with no shelf (another mod's horse added mid-month) are left alone.
--- @param animals table RLRM sale animals of one type, oldest first as RLRM appends them
--- @param shelves table name -> horses
--- @param kindOf function animal -> subtype name or nil
--- @return table indexes ascending
function EqDealerStock.excess(animals, shelves, kindOf)
    local kept, indexes = {}, {}
    for i, animal in ipairs(animals or {}) do
        local name = animal.sale ~= nil and kindOf(animal) or nil
        local shelf = name ~= nil and shelves[name] or nil
        if shelf ~= nil then
            kept[name] = (kept[name] or 0) + 1
            if kept[name] > shelf then table.insert(indexes, i) end
        end
    end
    return indexes
end


--- @param animalSystem table
--- @param animal table RLRM Animal
--- @return string|nil name its subtype's name
local function kindOf(animalSystem, animal)
    local subType = animal.subTypeIndex ~= nil and animalSystem:getSubTypeByIndex(animal.subTypeIndex) or nil
    return subType ~= nil and subType.name or nil
end


--- @param subType table
--- @return boolean buyable any of its visuals can be bought, as RLRM's pick checks
local function isBuyable(subType)
    for _, visual in ipairs(subType.visuals or {}) do
        if visual.store ~= nil and visual.store.canBeBought then return true end
    end
    return false
end


--- The horse type's subtypes the dealer may sell.
--- @param animalSystem table
--- @return table subTypes
function EqDealerStock.horseSubTypes(animalSystem)
    local horseType = animalSystem:getTypeByIndex(AnimalType.HORSE)
    local subTypes = {}
    for _, index in ipairs(horseType ~= nil and horseType.subTypes or {}) do
        local subType = animalSystem:getSubTypeByIndex(index)
        if subType ~= nil and subType.name ~= nil and isBuyable(subType) then table.insert(subTypes, subType) end
    end
    return subTypes
end


--- This month's shelves, rolled the first time they are asked for.
--- @param animalSystem table
--- @return table shelves name -> horses
function EqDealerStock.shelves(animalSystem)
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    local key = string.format("%s:%s", tostring(environment ~= nil and environment.currentYear or 1),
        tostring(environment ~= nil and environment.currentPeriod or 1))
    local cache = EqDealerStock.cache
    if cache ~= nil and cache.key == key then return cache.shelves end

    local names = {}
    for _, subType in ipairs(EqDealerStock.horseSubTypes(animalSystem)) do table.insert(names, subType.name) end
    local shelves = EqDealerStock.rollShelves(names, key)
    EqDealerStock.cache = { key = key, shelves = shelves }

    local parts, total = {}, 0
    for _, name in ipairs(names) do
        table.insert(parts, string.format("%s %d", name, shelves[name]))
        total = total + shelves[name]
    end
    Log:debug("EqDealerStock: dealer horses for %s, %d in all: %s", key, total, table.concat(parts, ", "))
    return shelves
end


--- RLRM's createNewSaleAnimal for horses, with the full kinds hidden from its pick.
--- @param original function
--- @param animalSystem table
--- @param animalTypeIndex number
--- @return table|nil animal
function EqDealerStock.createHorse(original, animalSystem, animalTypeIndex, ...)
    local shelves = EqDealerStock.shelves(animalSystem)
    local counts = EqDealerStock.countKinds(animalSystem.animals[animalTypeIndex],
        function(animal) return kindOf(animalSystem, animal) end)

    local full, room = {}, false
    for _, subType in ipairs(EqDealerStock.horseSubTypes(animalSystem)) do
        local shelf = shelves[subType.name]
        if shelf ~= nil and (counts[subType.name] or 0) >= shelf then
            table.insert(full, subType)
        else
            room = true
        end
    end

    if not room then return nil end

    local hidden = {}
    for _, subType in ipairs(full) do
        for _, visual in ipairs(subType.visuals or {}) do
            if visual.store ~= nil and visual.store.canBeBought then
                visual.store.canBeBought = false
                table.insert(hidden, visual.store)
            end
        end
    end

    return EqLog.finally(function()
        for _, store in ipairs(hidden) do store.canBeBought = true end
    end, original, animalSystem, animalTypeIndex, ...)
end


--- Take listings over their shelf off the dealer. Server only.
--- @return number removed
function EqDealerStock.trim()
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() or mission.animalSystem == nil then return 0 end
    local animalSystem = mission.animalSystem
    local animals = animalSystem.animals ~= nil and animalSystem.animals[AnimalType.HORSE] or nil
    if animals == nil then return 0 end

    local indexes = EqDealerStock.excess(animals, EqDealerStock.shelves(animalSystem),
        function(animal) return kindOf(animalSystem, animal) end)
    for i = #indexes, 1, -1 do table.remove(animals, indexes[i]) end

    if #indexes > 0 then
        Log:debug("EqDealerStock: took %d horses off the dealer to fit this month's shelves", #indexes)
        local stateEvent = EqRLRM.get("AnimalSystemStateEvent")
        if g_server ~= nil and stateEvent ~= nil then
            g_server:broadcastEvent(stateEvent.new(animalSystem.countries, animalSystem.animals, animalSystem.aiAnimals))
        end
    end
    return #indexes
end


--- @param guarded function main.lua's error guard
function EqDealerStock.install(guarded)
    local original = AnimalSystem.createNewSaleAnimal
    AnimalSystem.createNewSaleAnimal = function(animalSystem, animalTypeIndex, ...)
        if animalTypeIndex ~= AnimalType.HORSE then return original(animalSystem, animalTypeIndex, ...) end
        local ok, animal = EqLog.guard("dealer horse stock", EqDealerStock.createHorse, original, animalSystem,
            animalTypeIndex, ...)
        if ok then return animal end
        return original(animalSystem, animalTypeIndex, ...)
    end
    Log:debug("EqDealerStock: hooked AnimalSystem.createNewSaleAnimal")
end


--- Trim now (an older save's full shelf) and once an hour after RLRM's own rotation.
--- @param guarded function main.lua's error guard
function EqDealerStock.start(guarded)
    EqDealerStock.cache = nil
    guarded("dealer horse stock trim", EqDealerStock.trim)
    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, function()
        guarded("dealer horse stock trim", EqDealerStock.trim)
    end, EqDealerStock)
end


function EqDealerStock.stop()
    if g_messageCenter ~= nil then g_messageCenter:unsubscribeAll(EqDealerStock) end
    EqDealerStock.cache = nil
end

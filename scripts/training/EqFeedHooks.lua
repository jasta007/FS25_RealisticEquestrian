--[[
    EqFeedHooks.lua
    Wires EqFeed into the game.

    - AnimalFoodSystem.loadMapData (base game) reads the map's animalFood.xml. Right after it,
      the HORSE food groups are rewritten from data/feeds.xml. That is before any placeable
      loads, so every horse pen's trough is built with the new list (and stops taking sorghum).
      It runs on server and clients alike, so both agree on what a trough accepts.
    - getBoost reads the trough of the pen a horse lives in. EqTrainingHooks passes it to the
      day's training and shows it while riding. A horse in a trailer, away at an event or in a
      pen without a trough gets no boost.

    A save made before this change may have sorghum in a horse trough: the game drops fill
    types a trough no longer accepts when it loads.
]]

EqFeedHooks = {}
EqFeedHooks.config = nil
EqFeedHooks.applied = false

local Log = EqLog


--- @param fillTypes table a food group's fill types: a list of indices, or a set index -> true
--- @return table names, boolean isSet
local function readFillTypes(fillTypes)
    local names, isSet = {}, false
    for key, value in pairs(fillTypes) do
        local index = value
        if value == true then index, isSet = key, true end
        local name = g_fillTypeManager:getFillTypeNameByIndex(index)
        if name ~= nil then table.insert(names, name) end
    end
    table.sort(names)
    return names, isSet
end


--- @param names table fill type names
--- @param isSet boolean
--- @return table fillTypes in the shape the group had
local function writeFillTypes(names, isSet)
    local fillTypes = {}
    for _, name in ipairs(names) do
        local index = g_fillTypeManager:getFillTypeIndexByName(name)
        if index ~= nil then
            if isSet then fillTypes[index] = true else table.insert(fillTypes, index) end
        end
    end
    return fillTypes
end


--- @param key string|nil l10n key
--- @return string
local function groupTitle(key)
    if key ~= nil and g_i18n ~= nil and g_i18n:hasText(key) then return g_i18n:getText(key) end
    return key or ""
end


--- Rewrite the horse food groups of a loaded AnimalFoodSystem.
--- @param foodSystem table
function EqFeedHooks.applyToFoodSystem(foodSystem)
    local config = EqFeedHooks.config
    if config == nil then return end

    local animalFood = foodSystem.getAnimalFood ~= nil and foodSystem:getAnimalFood(AnimalType.HORSE) or nil
    if animalFood == nil or animalFood.groups == nil then
        Log:warning("EqFeed: the map defines no horse food, feeds left as they are")
        return
    end

    local isSet = false
    local plan = {}
    for _, foodGroup in ipairs(animalFood.groups) do
        local names, groupIsSet = readFillTypes(foodGroup.fillTypes or {})
        isSet = isSet or groupIsSet
        table.insert(plan, { names = names, foodGroup = foodGroup })
    end

    plan = EqFeed.planGroups(plan, config, function(name)
        return g_fillTypeManager:getFillTypeIndexByName(name) ~= nil
    end)

    local groups = {}
    for _, entry in ipairs(plan) do
        local foodGroup = entry.foodGroup
        if entry.isNew then
            foodGroup = {
                title = groupTitle(entry.group.title),
                productionWeight = entry.group.productionWeight,
                eatWeight = entry.group.eatWeight,
            }
        end
        foodGroup.fillTypes = writeFillTypes(entry.names, isSet)
        table.insert(groups, foodGroup)
        Log:info("EqFeed: horse food group '%s' (production %.2f, eat %.2f): %s", tostring(foodGroup.title),
            foodGroup.productionWeight or 0, foodGroup.eatWeight or 0, table.concat(entry.names, " "))
    end
    animalFood.groups = groups
    EqFeedHooks.applied = true
end


--- What the trough of a horse's pen holds.
--- @param animal table RLRM Animal
--- @return table|nil levels fill type name -> litres, nil when the horse has no trough
function EqFeedHooks.getTroughLevels(animal)
    local clusterSystem = animal ~= nil and animal.clusterSystem or nil
    local owner = clusterSystem ~= nil and clusterSystem.owner or nil
    local spec = owner ~= nil and owner.spec_husbandryFood or nil
    if spec == nil or spec.fillLevels == nil then return nil end

    local levels = {}
    for index, level in pairs(spec.fillLevels) do
        local name = g_fillTypeManager:getFillTypeNameByIndex(index)
        if name ~= nil and type(level) == "number" then levels[name] = level end
    end
    return levels
end


--- @param animal table RLRM Animal
--- @return table boost stat -> share
function EqFeedHooks.getBoost(animal)
    return EqFeed.dietBoost(EqFeedHooks.getTroughLevels(animal), EqFeedHooks.config)
end


--- "Feed: Spd +35% Tem +35%", or nil when the feed gives nothing.
--- @param boost table stat -> share
--- @return string|nil
function EqFeedHooks.formatBoost(boost)
    local parts = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local percent = math.floor((boost[stat] or 0) * 100 + 0.5)
        if percent > 0 then
            table.insert(parts, string.format("%s +%d%%", g_i18n:getText("eq_stat_short_" .. stat), percent))
        end
    end
    if #parts == 0 then return nil end
    return g_i18n:getText("eq_feed_boost") .. ": " .. table.concat(parts, " ")
end


--- eqFeed: what horses eat on this map, and what each of your horses' troughs gives.
function EqFeedHooks:consoleFeed()
    local lines = {}
    local animalFood = g_currentMission.animalFoodSystem ~= nil
        and g_currentMission.animalFoodSystem:getAnimalFood(AnimalType.HORSE) or nil
    if animalFood ~= nil then
        for _, foodGroup in ipairs(animalFood.groups or {}) do
            local names = readFillTypes(foodGroup.fillTypes or {})
            table.insert(lines, string.format("%s: %s", tostring(foodGroup.title), table.concat(names, " ")))
        end
    end
    if not EqFeedHooks.applied then table.insert(lines, "(Realistic Equestrian's feed list was not applied; see the log)") end

    for _, animal in ipairs(EqRLRM.listHorsesForFarm(g_currentMission:getFarmId())) do
        local boost = EqFeedHooks.formatBoost(EqFeedHooks.getBoost(animal)) or "no feed boost"
        table.insert(lines, string.format("%s (%s): %s", tostring(animal.name or animal.uniqueId),
            tostring(EqRegistry.getId(animal)), boost))
    end
    return table.concat(lines, "\n")
end


function EqFeedHooks.register()
    addConsoleCommand("eqFeed", "Shows what horses eat and each horse's feed training boost", "consoleFeed", EqFeedHooks)
end


function EqFeedHooks.unregister()
    removeConsoleCommand("eqFeed")
end


--- Load feeds.xml and hook the food system. Call at source time, before the map loads.
--- @param guarded function main.lua's error guard
--- @param modDirectory string
function EqFeedHooks.install(guarded, modDirectory)
    EqFeedHooks.config = EqFeed.load(modDirectory .. "data/feeds.xml")
    if EqFeedHooks.config == nil then return end

    AnimalFoodSystem.loadMapData = Utils.overwrittenFunction(AnimalFoodSystem.loadMapData, function(self, superFunc, ...)
        local result = superFunc(self, ...)
        guarded("horse feeds", function() EqFeedHooks.applyToFoodSystem(self) end)
        return result
    end)
end

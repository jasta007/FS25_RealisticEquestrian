--[[
    EqFeedHooks.lua
    Wires EqFeed into the game.

    - AnimalFoodSystem.loadMapData (base game) reads the map's animalFood.xml. Right after it,
      the HORSE food groups are rewritten from data/feeds.xml. That is before any placeable
      loads, so every horse pen's trough is built with the new list (and stops taking sorghum).
      It runs on server and clients alike, so both agree on what a trough accepts.
    - PlaceableHusbandryFood.getFoodInfos gives a horse pen's food rows our names, a row each for
      oats, barley and corn, and in place of the base game's production share ("Root crops (5%)")
      the stats each row's feed boosts, in full words with its strength: "Corn (Speed+++)",
      "Oats (Stamina+, Temperament+)", "Hay (no boost)".
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
                productionWeight = entry.group.productionWeight,
                eatWeight = entry.group.eatWeight,
            }
        end
        foodGroup.fillTypes = writeFillTypes(entry.names, isSet)
        foodGroup.eqNames = entry.names
        foodGroup.eqKind = EqFeed.groupKind(entry.names, config)
        local kind = config.groupByName[foodGroup.eqKind]
        if kind ~= nil then foodGroup.title = groupTitle(kind.title) end
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


--- @param boost table stat -> share
--- @return string "Stamina+, Temperament+", "" when nothing is boosted
local function fullStats(boost)
    local parts = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if boost[stat] > 0 then
            table.insert(parts, g_i18n:getText("eq_stat_" .. stat) .. EqFeed.strengthMarks(boost[stat]))
        end
    end
    return table.concat(parts, ", ")
end


--- A pen food row's title: its name and, in full words with their strength, the stats its feed
--- boosts now, or, while the row is empty, the stats it could.
--- @param name string
--- @param names table the row's fill type names
--- @param levels table fill type name -> litres
--- @return string
local function rowTitle(name, names, levels)
    local config = EqFeedHooks.config
    local rowLevels = {}
    for _, fillType in ipairs(names) do rowLevels[fillType] = levels[fillType] or 0 end

    local detail = fullStats(EqFeed.dietBoost(rowLevels, config))
    if detail == "" then detail = fullStats(EqFeed.bestBoost(names, config)) end
    if detail == "" then detail = g_i18n:getText("eq_feed_noBoost") end
    return string.format("%s (%s)", name, detail)
end


--- A horse pen's food rows, built from the base game's one row per food group (in group
--- order): our group names, the stats each boosts in place of the production share, and
--- separate rows for feeds with a row of their own (oats, barley, corn). Display only; the
--- groups still feed as before. A group's leftover row ("Other grain") goes to the end, so the
--- rows that are always there come first in RLRM's five-row pane.
--- @return table|nil rows a new list, nil to keep the base game's
function EqFeedHooks.buildFoodRows(placeable, infos)
    local spec = placeable.spec_husbandryFood
    if type(infos) ~= "table" or spec == nil or spec.fillLevels == nil or spec.animalTypeIndex ~= AnimalType.HORSE then return nil end
    local animalFood = g_currentMission.animalFoodSystem:getAnimalFood(AnimalType.HORSE)
    if animalFood == nil or animalFood.groups == nil or #animalFood.groups ~= #infos then return nil end

    local config = EqFeedHooks.config
    local levels = {}
    for index, level in pairs(spec.fillLevels) do
        local name = g_fillTypeManager:getFillTypeNameByIndex(index)
        if name ~= nil and type(level) == "number" then levels[name] = level end
    end

    local rows, tail = {}, {}
    for i, info in ipairs(infos) do
        local foodGroup = animalFood.groups[i]
        if foodGroup.eqNames == nil then
            table.insert(rows, info)
        else
            local kind = config.groupByName[foodGroup.eqKind]
            local groupName = kind ~= nil and groupTitle(kind.title) or tostring(foodGroup.title)
            local split = EqFeed.splitRows(foodGroup.eqNames, levels, config)
            for _, part in ipairs(split) do
                local row = {}
                for key, value in pairs(info) do row[key] = value end
                local name = groupName
                if part.row ~= nil then
                    name = groupTitle(part.row)
                elseif #split > 1 and kind ~= nil and kind.otherTitle ~= nil then
                    name = groupTitle(kind.otherTitle)
                end
                row.title = rowTitle(name, part.names, levels)
                if #split > 1 then
                    row.value = part.value
                    local capacity = info.capacity or 0
                    row.ratio = capacity > 0 and part.value / capacity or 0
                end
                table.insert((part.row == nil and #split > 1) and tail or rows, row)
            end
        end
    end
    for _, row in ipairs(tail) do table.insert(rows, row) end
    return rows
end


--- "Feed: Speed +35%, Temperament +35%", or nil when the feed gives nothing.
--- @param boost table stat -> share
--- @return string|nil
function EqFeedHooks.formatBoost(boost)
    local parts = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local percent = math.floor((boost[stat] or 0) * 100 + 0.5)
        if percent > 0 then
            table.insert(parts, string.format("%s +%d%%", g_i18n:getText("eq_stat_" .. stat), percent))
        end
    end
    if #parts == 0 then return nil end
    return g_i18n:getText("eq_feed_boost") .. ": " .. table.concat(parts, ", ")
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

    -- A placeable specialization's functions are copied into placeable types when types are
    -- validated, so this is patched now, at source time.
    PlaceableHusbandryFood.getFoodInfos = Utils.overwrittenFunction(PlaceableHusbandryFood.getFoodInfos, function(self, superFunc, ...)
        local infos = superFunc(self, ...)
        local rows = nil
        if EqFeedHooks.applied then
            guarded("horse food rows", function() rows = EqFeedHooks.buildFoodRows(self, infos) end)
        end
        return rows or infos
    end)
end

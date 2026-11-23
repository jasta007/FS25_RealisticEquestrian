--[[
    EqRLRM.lua
    The one place Realistic Equestrian reaches into Realistic Livestock (RLRM).

    FS25 runs each mod in its own environment, and a mod's top-level globals live at
    realGlobal[modName]; RLRM's Animal, AnimalHorse, BreedingMath and the rest are therefore
    read through _G.FS25_RealisticLivestockRM. Every RLRM function this mod calls or hooks is
    listed below and checked once at load, so an RLRM update that renames one turns into a
    clear log line and a disabled feature instead of a crash mid-game.
]]

EqRLRM = {}

EqRLRM.MOD_NAME = "FS25_RealisticLivestockRM"
-- The oldest RLRM release this mod is tested with. An older one gets a startup popup.
-- Pre-release builds of the same number ("1.4.2.0-dev.4") count as that release.
EqRLRM.MIN_VERSION = "1.4.2.0"

local Log = EqLog

-- Functions the mod cannot run without. A missing one disables the whole mod.
EqRLRM.REQUIRED = {
    { "Animal", "getIdentifiers" },
    { "Animal", "isHorse" },
    { "AnimalHorse", "processRidingUpdate" },
    { "BreedingMath", "breedOffspring" },
    { "BreedingMath", "randn" },
    { "RLGenetics", "perTrait" },
    { "RLAnimalQuery", "listHusbandriesForFarm" },
}

-- Functions that only one feature needs. A missing one switches that feature off.
EqRLRM.OPTIONAL = {
    infoDisplay = { { "AnimalHorse", "addHorseInfos" } },
    menuLayout = { { "RLAnimalInfoService", "getAnimalDisplay" }, { "Animal", "showGeneticsInfo" } },
    eventsTab = { { "RLMenu", "setupMenuPages" } },
    menuPaging = { { "RLMenu", "updatePages" } },
    messageLink = { { "RLMessageService", "formatMessage" }, { "RLMenuMessagesFrame", "updateButtonVisibility" } },
    settingsTab = { { "RLMenuSettingsFrame", "onFrameOpen" }, { "RLMenuSettingsFrame", "initializeSubCategoryPages" },
        { "RLMenuSettingsFrame", "updateSubCategoryPages" } },
    rideButton = { { "RLMenuInfoFrame", "updateButtonVisibility" }, { "RLMenuInfoFrame", "getSelectedAnimal" } },
    animalsPageButton = { { "RLMenu", "openFromBridge" } },
    menuGenetics = { { "RLDetailPaneHelper", "updateAnimalDisplay" }, { "RLAnimalInfoService", "getAnimalDisplay" } },
    horsePricing = { { "AnimalHorse", "getHorseSellPrice" } },
    dealerStock = { { "AnimalSystem", "createNewSaleAnimal" }, { "AnimalSystemStateEvent", "new" } },
    awayVisuals = { { "RealisticLivestock_AnimalClusterHusbandry", "updateVisuals" } },
    metabolismFitness = { { "AnimalHorse", "changeFitness" } },
    listBadge = { { "RLAnimalQuery", "formatAnimalRow" } },
    roleMenu = { { "RLAnimalQuery", "buildSections" }, { "RLMenuInfoFrame", "updateButtonVisibility" },
        { "RLMenuInfoFrame", "getSelectedAnimal" } },
    injuries = { { "DiseaseManager", "loadDiseases" }, { "DiseaseManager", "contractDisease" }, { "Disease", "onDayChanged" },
        { "RLDiseaseDefinition", "parse" } },
    dealerDelivery = { { "RLAnimalMoveService", "moveAnimals" }, { "RLAnimalMoveService", "getValidDestinations" },
        { "RLAnimalMoveService", "getErrorText" } },
    looseHorses = { { "Animal", "applyExercise" }, { "Animal", "applyGrooming" } },
    staffPicker = { { "RLHusbandryTargetKey", "keyFor" }, { "RLHerdsmanHusbandryPickerDialog", "show" } },
}

EqRLRM.env = nil
EqRLRM.version = nil
EqRLRM.isAvailable = false
EqRLRM.features = {}
-- Why RLRM needs updating, for the startup popup: nil, "missing", "incompatible" (switched off)
-- or "old" (older than MIN_VERSION, or a feature is off; the mod still runs).
EqRLRM.problem = nil


--- @param version string|nil Such as "1.4.2.0" or "1.4.2.0-dev.4"
--- @return table numbers The leading dotted numbers, { 1, 4, 2, 0 }
local function versionNumbers(version)
    local numbers = {}
    local base = string.match(tostring(version or ""), "^[%d%.]+") or ""
    for part in string.gmatch(base, "%d+") do table.insert(numbers, tonumber(part)) end
    return numbers
end


--- @return boolean older true when version is older than minimum; false for an unreadable version
function EqRLRM.isOlder(version, minimum)
    local have, need = versionNumbers(version), versionNumbers(minimum)
    if #have == 0 then return false end
    for i = 1, math.max(#have, #need) do
        local a, b = have[i] or 0, need[i] or 0
        if a ~= b then return a < b end
    end
    return false
end


--- @param path table { tableName, functionName }
--- @return boolean present
local function hasFunction(env, path)
    local owner = env[path[1]]
    return type(owner) == "table" and type(owner[path[2]]) == "function"
end


--- Find RLRM and check every function this mod relies on. Call once, at source time.
--- @return boolean ok false when RLRM is missing or a required function is gone
function EqRLRM.init()
    local env = _G[EqRLRM.MOD_NAME]
    EqRLRM.env, EqRLRM.isAvailable = nil, false

    -- An RLRM that is in the mods folder but not active on this savegame can still leave its
    -- environment table behind (from an earlier savegame this session), so ask the game which
    -- mods this savegame loaded.
    local active = g_modIsLoaded == nil or g_modIsLoaded[EqRLRM.MOD_NAME] ~= nil
    if type(env) ~= "table" or not active then
        Log:info("Realistic Livestock (%s) is not loaded; Realistic Equestrian runs on the base game's horses.", EqRLRM.MOD_NAME)
        EqRLRM.problem = "missing"
        return false
    end

    EqRLRM.env = env

    local mod = g_modManager ~= nil and g_modManager:getModByName(EqRLRM.MOD_NAME) or nil
    EqRLRM.version = mod ~= nil and mod.version or "unknown"

    local missing = {}
    for _, path in ipairs(EqRLRM.REQUIRED) do
        if not hasFunction(env, path) then table.insert(missing, path[1] .. "." .. path[2]) end
    end

    if #missing > 0 then
        Log:error("Realistic Livestock %s is missing %s. Realistic Equestrian stays disabled; it needs a newer or older RLRM build.",
            EqRLRM.version, table.concat(missing, ", "))
        EqRLRM.problem = "incompatible"
        return false
    end

    for feature, paths in pairs(EqRLRM.OPTIONAL) do
        local ok = true
        for _, path in ipairs(paths) do
            if not hasFunction(env, path) then ok = false end
        end
        EqRLRM.features[feature] = ok
        if not ok then
            Log:warning("Realistic Livestock %s lacks what '%s' needs; that feature is off.", EqRLRM.version, feature)
            EqRLRM.problem = "old"
        end
    end

    if EqRLRM.isOlder(EqRLRM.version, EqRLRM.MIN_VERSION) then
        Log:warning("Realistic Livestock %s is older than %s, the oldest version Realistic Equestrian is tested with.",
            EqRLRM.version, EqRLRM.MIN_VERSION)
        EqRLRM.problem = "old"
    end

    EqRLRM.isAvailable = true
    Log:info("Found Realistic Livestock %s", EqRLRM.version)
    return true
end


--- @param name string A global table RLRM defines, such as "AnimalHorse"
--- @return table|nil
function EqRLRM.get(name)
    return EqRLRM.env ~= nil and EqRLRM.env[name] or nil
end


--- RLRM's inheritance function and its within-family spread.
--- @return function breedOffspring
--- @return number sd
function EqRLRM.getBreeding()
    local breedingMath = EqRLRM.get("BreedingMath")
    return breedingMath.breedOffspring, breedingMath.SD_CONST
end


--- RLRM's breedOffspring, drawing its random spread from our seeded generator instead of
--- math.random. BreedingMath samples through BreedingMath.randn, so that one function is swapped
--- for the length of the call and always put back, even on error. With the foal's identifier as
--- the seed, every machine breeds the same genes from the same parents.
--- @param breedingMath table RLRM's BreedingMath
--- @param rng table EqRandom generator
--- @return function breedOffspring(p1, p2, opts)
function EqRLRM.makeSeededBreeder(breedingMath, rng)
    return function(parent1, parent2, opts)
        local randn = breedingMath.randn
        breedingMath.randn = function() return rng:normal(0, 1) end
        return EqLog.finally(function() breedingMath.randn = randn end,
            breedingMath.breedOffspring, parent1, parent2, opts)
    end
end


--- Band a gene with RLRM's per-trait ladder and translations ("Very high", "Low").
--- @param gene number
--- @return string text
function EqRLRM.geneBandText(gene)
    local genetics = EqRLRM.get("RLGenetics")
    if genetics == nil then return string.format("%.2f", gene or 0) end
    return g_i18n:getText(genetics.perTrait(gene), EqRLRM.MOD_NAME)
end


--- Without RLRM, the mod runs on the base game's horses (EqBase).
--- @return boolean
function EqRLRM.isMissing()
    return not EqRLRM.isAvailable and EqRLRM.problem == "missing"
end


--- Every husbandry a farm owns: RLRM's query with RLRM, the husbandry system without.
--- @param farmId number
--- @return table placeables
function EqRLRM.listHusbandriesForFarm(farmId)
    local query = EqRLRM.get("RLAnimalQuery")
    if query ~= nil and query.listHusbandriesForFarm ~= nil then return query.listHusbandriesForFarm(farmId) end
    return EqBase.listHusbandriesForFarm(farmId)
end


--- A husbandry's lasting key, as RLRM's Herdsman keys it (the placeable's unique id).
--- @param placeable table|nil
--- @return string|nil
function EqRLRM.husbandryKey(placeable)
    local keys = EqRLRM.get("RLHusbandryTargetKey")
    if keys ~= nil and keys.keyFor ~= nil then return keys.keyFor(placeable) end
    return EqBase.husbandryKey(placeable)
end


--- Every horse on a farm's husbandries, using RLRM's own query helpers, and any being ridden.
--- @param farmId number
--- @return table animals RLRM Animal objects (base horse clusters without RLRM)
function EqRLRM.listHorsesForFarm(farmId)
    local horses = {}

    for _, husbandry in ipairs(EqRLRM.listHusbandriesForFarm(farmId)) do
        local spec = husbandry.spec_husbandryAnimals
        if EqBase.installed then
            -- Base clusters don't say where they live, so each is told here (EqBase.farmOf).
            for _, animal in pairs(EqBase.clustersOf(husbandry)) do
                if animal.isHorse ~= nil and animal:isHorse() then
                    EqBase.place(animal, farmId, husbandry)
                    table.insert(horses, animal)
                end
            end
        elseif spec ~= nil and spec.getClusters ~= nil then
            for _, animal in pairs(spec:getClusters() or {}) do
                if animal.isHorse ~= nil and animal:isHorse() then table.insert(horses, animal) end
            end
        end
    end

    -- A horse being ridden has left its pen until it is put back: it lives on the rideable.
    local vehicleSystem = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, vehicle in ipairs(vehicleSystem ~= nil and vehicleSystem.vehicles or {}) do
        local animal = vehicle.spec_rideable ~= nil and vehicle.spec_rideable.cluster or nil
        if animal ~= nil and animal.isHorse ~= nil and animal:isHorse() and vehicle:getOwnerFarmId() == farmId then
            local listed = false
            for _, horse in ipairs(horses) do
                if horse == animal then listed = true end
            end
            if not listed then table.insert(horses, animal) end
            if EqBase.installed then EqBase.place(animal, farmId, nil) end
        end
    end

    return horses
end


--- A farm's horses standing in its livestock trailers. They have left their pens, so
--- listHorsesForFarm doesn't see them, but they are still the farm's: a horse driven somewhere
--- and left in its trailer must still run in its event (or be told it was never delivered).
--- @param farmId number
--- @return table animals RLRM Animal objects
function EqRLRM.listHorsesInTrailers(farmId)
    local horses = {}
    local vehicleSystem = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, vehicle in ipairs(vehicleSystem ~= nil and vehicleSystem.vehicles or {}) do
        if vehicle.spec_livestockTrailer ~= nil and vehicle.getClusters ~= nil
            and vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farmId then
            for _, animal in pairs(vehicle:getClusters() or {}) do
                if animal.isHorse ~= nil and animal:isHorse() then
                    if EqBase.installed then EqBase.place(animal, farmId, nil) end
                    table.insert(horses, animal)
                end
            end
        end
    end
    return horses
end

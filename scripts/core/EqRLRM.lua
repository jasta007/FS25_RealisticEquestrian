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
    infoDisplay = { { "AnimalHorse", "addHorseInfos" }, { "AnimalHorse", "showHorseHudInfo" } },
    menuLayout = { { "RLAnimalInfoService", "getAnimalDisplay" }, { "Animal", "showGeneticsInfo" } },
    menuGenetics = { { "RLDetailPaneHelper", "updateAnimalDisplay" }, { "RLAnimalInfoService", "getAnimalDisplay" } },
}

EqRLRM.env = nil
EqRLRM.version = nil
EqRLRM.isAvailable = false
EqRLRM.features = {}


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

    if type(env) ~= "table" then
        Log:error("Realistic Livestock (%s) is not loaded. Realistic Equestrian stays disabled.", EqRLRM.MOD_NAME)
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
        end
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
        local ok, child = pcall(breedingMath.breedOffspring, parent1, parent2, opts)
        breedingMath.randn = randn
        if not ok then error(child, 0) end
        return child
    end
end


--- Band a gene with RLRM's per-trait ladder and translations ("Very high", "Low").
--- @param gene number
--- @return string text
function EqRLRM.geneBandText(gene)
    local key = EqRLRM.get("RLGenetics").perTrait(gene)
    return g_i18n:getText(key, EqRLRM.MOD_NAME)
end


--- Every horse on a farm's husbandries, using RLRM's own query helpers.
--- @param farmId number
--- @return table animals RLRM Animal objects
function EqRLRM.listHorsesForFarm(farmId)
    local horses = {}
    local query = EqRLRM.get("RLAnimalQuery")

    for _, husbandry in ipairs(query.listHusbandriesForFarm(farmId)) do
        local spec = husbandry.spec_husbandryAnimals
        if spec ~= nil and spec.getClusters ~= nil then
            for _, animal in pairs(spec:getClusters() or {}) do
                if animal.isHorse ~= nil and animal:isHorse() then table.insert(horses, animal) end
            end
        end
    end

    return horses
end

--[[
    EqRegistry.lua
    Every horse record, keyed by RLRM identifier, plus the save file that holds them.

    Records are created lazily the first time a horse is looked at. A horse whose mother RLRM
    knows (a foal born on a farm) is bred from its parents' genes; any other - one from the
    dealer, or from a save made before this mod - is rolled from a seed of its identifier. Both
    are seeded by the identifier, so they give the same genes on every machine with no
    migration step. Training is server authoritative: clients will get trained levels through a
    sync event (milestone 7).
]]

EqRegistry = {}
EqRegistry.records = {}

local Log = EqLog


--- Drop every record. Called when a mission loads so nothing leaks between savegames.
function EqRegistry.reset()
    EqRegistry.records = {}
end


--- @param animal table An RLRM Animal
--- @return string|nil id RLRM's identifier, or nil when the animal cannot give one yet
function EqRegistry.getId(animal)
    if animal == nil or animal.getIdentifiers == nil or animal.birthday == nil then return nil end

    local ok, id = pcall(animal.getIdentifiers, animal)
    if not ok then
        Log:debug("EqRegistry.getId: getIdentifiers raised for uniqueId=%s: %s",
            tostring(animal.uniqueId), tostring(id))
        return nil
    end

    return id
end


--- @return number day The game's monotonic day, or 0 before the environment exists
local function currentDay()
    local mission = g_currentMission
    if mission == nil or mission.environment == nil then return 0 end
    return mission.environment.currentMonotonicDay or 0
end


--- @param id string
--- @return table|nil record
function EqRegistry.getById(id)
    return EqRegistry.records[id]
end


--- Get a horse's record, rolling one from its identifier on first sight.
--- @param animal table An RLRM Animal
--- @return table|nil record nil for a non-horse or an animal without an identifier
function EqRegistry.getOrCreate(animal)
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return nil end

    local id = EqRegistry.getId(animal)
    if id == nil then return nil end

    local record = EqRegistry.records[id]
    if record == nil then
        if EqRegistry.hasKnownParent(animal.motherId) then
            record = EqRegistry.breedRecord(id, animal.age or 0, animal.motherId, animal.fatherId)
            Log:debug("EqRegistry: bred record for %s from dam %s and sire %s", id,
                tostring(animal.motherId), tostring(animal.fatherId))
        else
            record = EqRegistry.rollRecord(id, animal.age or 0)
            Log:debug("EqRegistry: rolled record for %s (age %s)", id, tostring(animal.age))
        end
        EqRegistry.records[id] = record
    end

    record.lastSeenDay = currentDay()
    return record
end


--- Build a record from a seed of the identifier. Same id and age -> same record, everywhere.
--- @param id string
--- @param ageMonths number
--- @return table record
function EqRegistry.rollRecord(id, ageMonths)
    local rng = EqRandom.new(id)
    local record = EqHorseRecord.new(id)

    record.genes, record.budgetGene = EqStats.rollGenes(rng)
    record.trained = EqStats.initialTrained(record:getCeilings(), ageMonths, rng)
    record.origin = EqHorseRecord.ORIGIN_ROLLED

    return record
end


--- @param parentId string|nil RLRM's motherId or fatherId ("-1" when unknown)
--- @return boolean
function EqRegistry.hasKnownParent(parentId)
    return parentId ~= nil and parentId ~= "" and parentId ~= "-1"
end


--- A parent's genes: its record when we have one, otherwise the genes its identifier rolls to.
--- A dealer stallion whose straw is used, or a mare sold before her foal was first seen, so
--- still breeds true to the stats it showed. The rolled record is not stored.
--- @param parentId string|nil
--- @return table record-like { genes, budgetGene }
function EqRegistry.getParentGenes(parentId)
    if not EqRegistry.hasKnownParent(parentId) then
        local average = {}
        for _, stat in ipairs(EqConstants.STAT_KEYS) do average[stat] = EqConstants.GENE_MEAN end
        return { genes = average, budgetGene = EqConstants.GENE_MEAN }
    end
    return EqRegistry.records[parentId] or EqRegistry.rollRecord(parentId, 0)
end


--- Build a record by breeding the parents' genes through RLRM's BreedingMath, seeded by the
--- foal's identifier so the result is the same on every machine.
--- @param id string
--- @param ageMonths number
--- @param motherId string
--- @param fatherId string|nil
--- @return table record
function EqRegistry.breedRecord(id, ageMonths, motherId, fatherId)
    local rng = EqRandom.new(id)
    local record = EqHorseRecord.new(id)
    local breedingMath = EqRLRM.get("BreedingMath")
    local breed = EqRLRM.makeSeededBreeder(breedingMath, rng)

    record.genes, record.budgetGene = EqStats.breedGenes(EqRegistry.getParentGenes(motherId),
        EqRegistry.getParentGenes(fatherId), breed, breedingMath.SD_CONST)
    for _, stat in ipairs(EqConstants.STAT_KEYS) do record.genes[stat] = EqStats.clampGene(record.genes[stat]) end
    record.budgetGene = EqStats.clampGene(record.budgetGene)

    record.trained = EqStats.initialTrained(record:getCeilings(), ageMonths, rng)
    record.origin = EqHorseRecord.ORIGIN_BRED

    return record
end


--- @return number count
function EqRegistry.count()
    local count = 0
    for _ in pairs(EqRegistry.records) do count = count + 1 end
    return count
end


--- @param directory string Savegame directory
function EqRegistry.saveToDirectory(directory)
    local path = directory .. "/" .. EqConstants.SAVE_FILENAME
    local xmlFile = XMLFile.create("rlEquestrian", path, "rlEquestrian")
    if xmlFile == nil then
        Log:error("EqRegistry: could not create %s", path)
        return
    end

    xmlFile:setInt("rlEquestrian#version", EqConstants.SAVE_VERSION)

    -- Sorted so the file diffs cleanly between saves.
    local ids = {}
    for id in pairs(EqRegistry.records) do table.insert(ids, id) end
    table.sort(ids)

    for i, id in ipairs(ids) do
        EqRegistry.records[id]:saveToXMLFile(xmlFile, string.format("rlEquestrian.horses.horse(%d)", i - 1))
    end

    xmlFile:save()
    xmlFile:delete()
    Log:info("EqRegistry: saved %d horse record(s)", #ids)
end


--- @param directory string|nil Savegame directory; nil for a new game
function EqRegistry.loadFromDirectory(directory)
    EqRegistry.reset()
    if directory == nil then return end

    local xmlFile = XMLFile.loadIfExists("rlEquestrian", directory .. "/" .. EqConstants.SAVE_FILENAME)
    if xmlFile == nil then
        Log:info("EqRegistry: no %s yet, horses will be rolled on first sight", EqConstants.SAVE_FILENAME)
        return
    end

    local index = 0
    while true do
        local key = string.format("rlEquestrian.horses.horse(%d)", index)
        if not xmlFile:hasProperty(key) then break end

        local record = EqHorseRecord.loadFromXMLFile(xmlFile, key)
        if record ~= nil then EqRegistry.records[record.id] = record end
        index = index + 1
    end

    xmlFile:delete()
    Log:info("EqRegistry: loaded %d horse record(s)", EqRegistry.count())
end

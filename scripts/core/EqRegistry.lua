--[[
    EqRegistry.lua
    Every horse record, keyed by RLRM identifier, plus the save file that holds them.

    Records are created lazily the first time a horse is looked at. A horse whose mother RLRM
    knows (a foal born on a farm) is bred from its parents' genes; any other - one from the
    dealer, or from a save made before this mod - is rolled from a seed of its identifier. Both
    are seeded by the identifier, so they give the same genes on every machine with no
    migration step.

    A horse still at the dealer gets a dealer record (green, with the dealer's view of its
    potential) that is kept aside, not saved, since most dealer horses are never bought. When the
    horse turns up on a farm its dealer record becomes its real one. Training is server authoritative: clients will get trained levels through a
    sync event (milestone 7).
]]

EqRegistry = {}
EqRegistry.records = {}
EqRegistry.dealer = {}           -- id -> { record, animal } for horses still at the dealer

local Log = EqLog


--- Drop every record. Called when a mission loads so nothing leaks between savegames.
function EqRegistry.reset()
    EqRegistry.records = {}
    EqRegistry.dealer = {}
end


--- @param animal table An RLRM Animal
--- @return string|nil id RLRM's identifier, or nil when the animal cannot give one yet
function EqRegistry.getId(animal)
    if animal == nil or animal.getIdentifiers == nil or animal.birthday == nil then return nil end

    local ok, id = EqLog.try("EqRegistry.getId getIdentifiers", animal.getIdentifiers, animal)
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
    if record == nil and EqRegistry.isAtDealer(animal) then
        local held = EqRegistry.dealer[id]
        if held == nil then
            held = { record = EqRegistry.rollRecord(id, animal.age or 0, EqRegistry.rlrmQuality(animal), true), animal = animal }
            EqRegistry.dealer[id] = held
        end
        return held.record
    end

    local isNew = record == nil
    if record == nil and EqRegistry.dealer[id] ~= nil then
        record = EqRegistry.promote(id)
    elseif record == nil then
        if EqRegistry.hasKnownParent(animal.motherId) then
            record = EqRegistry.breedRecord(id, animal.age or 0, animal.motherId, animal.fatherId)
            Log:debug("EqRegistry: bred record for %s from dam %s and sire %s", id,
                tostring(animal.motherId), tostring(animal.fatherId))
        else
            record = EqRegistry.rollRecord(id, animal.age or 0, EqRegistry.rlrmQuality(animal), false)
            Log:debug("EqRegistry: rolled record for %s (age %s)", id, tostring(animal.age))
        end
        EqRegistry.records[id] = record
    end

    if record.redrawStart then
        record.trained = EqStats.initialTrained(record:getCeilings(), animal.age or 0, EqRandom.new("start " .. id))
        record.redrawStart = nil
    end
    if isNew then record:markStart(currentDay()) end

    record.lastSeenDay = currentDay()
    return record
end


--- Saves before starting stats were drawn put every stat at OLD_START_LEVEL. A horse still
--- there in every stat, with no starts, has never been worked, so it can draw its stats now.
--- @param record table
--- @return boolean
function EqRegistry.hasOldStart(record)
    if record.career.starts > 0 then return false end
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if math.abs((record.trained[stat] or 0) - EqConstants.OLD_START_LEVEL) > 0.01 then return false end
    end
    return true
end


--- @param animal table An RLRM Animal
--- @return boolean true while the horse is in the dealer's stock (RLRM clears `sale` when it
---     joins a pen or trailer)
function EqRegistry.isAtDealer(animal)
    return animal.sale ~= nil and animal.clusterSystem == nil
end


--- @param animal table An RLRM Animal
--- @return number|nil quality the average of its RLRM genetics, nil when it has none
function EqRegistry.rlrmQuality(animal)
    local genetics = animal.genetics
    if type(genetics) ~= "table" then return nil end
    local sum, count = 0, 0
    for _, trait in ipairs({ "metabolism", "quality", "fertility", "health" }) do
        if type(genetics[trait]) == "number" then
            sum, count = sum + genetics[trait], count + 1
        end
    end
    if count == 0 then return nil end
    return sum / count
end


--- Build a record from a seed of the identifier. Same id, age and RLRM genetics -> same record,
--- everywhere.
--- @param id string
--- @param ageMonths number
--- @param rlrmQuality number|nil from rlrmQuality
--- @param atDealer boolean a dealer horse: green, with the dealer's view of its potential
--- @return table record
function EqRegistry.rollRecord(id, ageMonths, rlrmQuality, atDealer)
    local rng = EqRandom.new(id)
    local record = EqHorseRecord.new(id)

    record.genes, record.budgetGene = EqStats.rollGenes(rng)
    record.budgetGene = EqDealer.leanOnRlrm(record.genes, record.budgetGene, rlrmQuality)
    record.budgetGene = EqDealer.maybeProspect(record.genes, record.budgetGene, rng)

    local ceilings = record:getCeilings()
    if atDealer then
        record.trained = EqDealer.greenTrained(ceilings, ageMonths, rng)
        record.advertised = EqDealer.advertise(ceilings, rng)
        record.revealed = false
        record.origin = EqHorseRecord.ORIGIN_DEALER
    else
        record.trained = EqStats.initialTrained(ceilings, ageMonths, rng)
        record.origin = EqHorseRecord.ORIGIN_ROLLED
    end

    return record
end


--- A dealer horse has been bought: its dealer record becomes its real one, and its months on
--- the farm start counting.
--- @param id string
--- @return table record
function EqRegistry.promote(id)
    local record = EqRegistry.dealer[id].record
    EqRegistry.dealer[id] = nil
    record.ownedMonths = 0
    record:markStart(currentDay())
    EqRegistry.records[id] = record
    Log:debug("EqRegistry: %s bought from the dealer", id)
    return record
end


--- Promote every held dealer horse that has left the dealer's stock since it was last looked at.
--- Called before a save, so a horse bought and saved before anything looked at it again keeps
--- its dealer record.
function EqRegistry.promoteBought()
    local bought = {}
    for id, held in pairs(EqRegistry.dealer) do
        if not EqRegistry.isAtDealer(held.animal) and held.animal.clusterSystem ~= nil then
            table.insert(bought, id)
        end
    end
    table.sort(bought)
    for _, id in ipairs(bought) do EqRegistry.promote(id) end
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
    return EqRegistry.records[parentId] or (EqRegistry.dealer[parentId] ~= nil and EqRegistry.dealer[parentId].record)
        or EqRegistry.rollRecord(parentId, 0, nil, false)
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
    EqRegistry.promoteBought()

    local xmlFile = XMLFile.create("rlEquestrian", path, "rlEquestrian")
    if xmlFile == nil then
        Log:error("EqRegistry: could not create %s", path)
        return
    end

    xmlFile:setInt("rlEquestrian#version", EqConstants.SAVE_VERSION)
    xmlFile:setString("rlEquestrian#madeBy", EqRandom.mark())

    -- Sorted so the file diffs cleanly between saves.
    local ids = {}
    for id in pairs(EqRegistry.records) do table.insert(ids, id) end
    table.sort(ids)

    for i, id in ipairs(ids) do
        EqRegistry.records[id]:saveToXMLFile(xmlFile, string.format("rlEquestrian.horses.horse(%d)", i - 1))
    end

    EqCompetitionManager.saveToXMLFile(xmlFile, "rlEquestrian.competition")
    EqCourse.saveToXMLFile(xmlFile, "rlEquestrian.courses")
    EqStaffManager.saveToXMLFile(xmlFile, "rlEquestrian.staff")

    xmlFile:save()
    xmlFile:delete()
    Log:info("EqRegistry: saved %d horse record(s)", #ids)
end


--- @param directory string|nil Savegame directory; nil for a new game
function EqRegistry.loadFromDirectory(directory)
    EqRegistry.reset()
    if directory == nil then
        EqCompetitionManager.loadFromXMLFile(nil, "rlEquestrian.competition")
        EqCourse.loadFromXMLFile(nil, "rlEquestrian.courses")
        EqStaffManager.loadFromXMLFile(nil, "rlEquestrian.staff")
        return
    end

    local xmlFile = XMLFile.loadIfExists("rlEquestrian", directory .. "/" .. EqConstants.SAVE_FILENAME)
    if xmlFile == nil then
        Log:info("EqRegistry: no %s yet, horses will be rolled on first sight", EqConstants.SAVE_FILENAME)
        EqCompetitionManager.loadFromXMLFile(nil, "rlEquestrian.competition")
        EqCourse.loadFromXMLFile(nil, "rlEquestrian.courses")
        EqStaffManager.loadFromXMLFile(nil, "rlEquestrian.staff")
        return
    end

    local version = xmlFile:getInt("rlEquestrian#version", 1)
    local index, redraw = 0, 0
    while true do
        local key = string.format("rlEquestrian.horses.horse(%d)", index)
        if not xmlFile:hasProperty(key) then break end

        local record = EqHorseRecord.loadFromXMLFile(xmlFile, key)
        if record ~= nil then
            EqRegistry.records[record.id] = record
            if version < 2 and EqRegistry.hasOldStart(record) then
                record.redrawStart = true
                redraw = redraw + 1
            end
        end
        index = index + 1
    end
    if redraw > 0 then Log:info("EqRegistry: %d horse(s) from an older save get new starting stats", redraw) end

    EqCompetitionManager.loadFromXMLFile(xmlFile, "rlEquestrian.competition")
    EqCourse.loadFromXMLFile(xmlFile, "rlEquestrian.courses")
    EqStaffManager.loadFromXMLFile(xmlFile, "rlEquestrian.staff")
    if #EqCourse.list > 0 then Log:info("EqRegistry: loaded %d show jumping course(s)", #EqCourse.list) end

    xmlFile:delete()
    Log:info("EqRegistry: loaded %d horse record(s)", EqRegistry.count())
end

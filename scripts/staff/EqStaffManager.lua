--[[
    EqStaffManager.lua
    The farm's hired staff and the candidates on offer (EqStaff does the maths). Server only.

    - Candidates: up to EqStaff.CANDIDATES on offer, shared by every farm; each stays some hours,
      and new ones arrive a few hours apart (EqStaff.refreshCandidates, every game hour).
    - Wages are per day, paid every day.
    - A horse's day of training asks workFor for everyone's work on it (EqTrainingHooks.onHorseDay).
    - In the last hour of the day grooms clean horses (EqStaff.toClean) and, like the base game's
      workers, bring the farm's loose horses home (EqLooseHorses).
    - Saved in the mod's own save file, beside the horse records (EqRegistry).
]]

EqStaffManager = {}

-- Grooms do their round in this hour, with the base game's workers (EqLooseHorses.ROUND_FROM_HOUR).
EqStaffManager.ROUND_HOUR = 23

local Log = EqLog


--- Forget everything. Called when a mission loads or ends.
function EqStaffManager.reset()
    EqStaffManager.hired = {}       -- members, each with farmId
    EqStaffManager.candidates = {}
    EqStaffManager.nextId = 1
    EqStaffManager.dayCache = {}    -- farmId -> { day, members, counts } for the daily training
end
EqStaffManager.reset()


--- @return number the game hour now
function EqStaffManager.hourNow()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment == nil then return 0 end
    return EqStaff.gameHour(environment.currentMonotonicDay, environment.currentHour)
end


--- @return table rng a generator for new candidates
local function newRng()
    return EqRandom.new(string.format("staff %d %d %s", EqStaffManager.hourNow(), EqStaffManager.nextId, tostring(g_time or 0)))
end


--- Fill the candidate list. Safe to call any time.
function EqStaffManager.ensureCandidates()
    EqStaffManager.nextId = EqStaff.refreshCandidates(EqStaffManager.candidates, EqStaffManager.hourNow(), newRng(),
        EqStaffManager.nextId, true)
end


--- @param farmId number
--- @return table members the farm's hired staff
function EqStaffManager.membersOf(farmId)
    local members = {}
    for _, member in ipairs(EqStaffManager.hired) do
        if member.farmId == farmId then table.insert(members, member) end
    end
    return members
end


--- @param list table
--- @param id number
--- @return table|nil member, number|nil index
local function find(list, id)
    for i, member in ipairs(list) do
        if member.id == id then return member, i end
    end
    return nil, nil
end


--- Hire a candidate for a farm.
--- @param id number candidate id
--- @param farmId number
--- @return boolean ok
--- @return string|nil why "gone" or "unique" when not
function EqStaffManager.hire(id, farmId)
    local candidate, index = find(EqStaffManager.candidates, id)
    if candidate == nil then return false, "gone" end
    if not EqStaff.canHire(EqStaffManager.membersOf(farmId), candidate) then return false, "unique" end
    table.remove(EqStaffManager.candidates, index)
    candidate.farmId = farmId
    candidate.leavesAt = nil
    candidate.enabled = true
    table.insert(EqStaffManager.hired, candidate)
    EqStaffManager.dayCache = {}
    Log:info("EqStaff: farm %d hired %s (%s, %s, %d a day)", farmId, candidate.name, candidate.job,
        EqStaff.GRADES[candidate.grade].name, candidate.wage)
    return true
end


--- Let a member go.
--- @param id number member id
--- @param farmId number
--- @return boolean ok
function EqStaffManager.fire(id, farmId)
    local member, index = find(EqStaffManager.hired, id)
    if member == nil or member.farmId ~= farmId then return false end
    table.remove(EqStaffManager.hired, index)
    EqStaffManager.dayCache = {}
    Log:info("EqStaff: farm %d let %s go", farmId, member.name)
    return true
end


--- @param id number member id
--- @param farmId number
--- @param works table { mode, stables, roles, horses } (EqStaff.WORKS_*)
--- @return boolean ok
function EqStaffManager.setWorksOn(id, farmId, works)
    local member = find(EqStaffManager.hired, id)
    if member == nil or member.farmId ~= farmId or not EqStaff.trains(member.job) then return false end
    member.worksOn = EqStaff.normalizeWorks(works)
    EqStaffManager.dayCache = {}
    return true
end


--- Switch a member on or off from the next morning (EqStaff.ENABLE_HOUR).
--- @param id number member id
--- @param farmId number
--- @param enabled boolean
--- @return boolean ok
function EqStaffManager.setEnabled(id, farmId, enabled)
    local member = find(EqStaffManager.hired, id)
    if member == nil or member.farmId ~= farmId then return false end
    if enabled == (member.enabled ~= false) then
        member.nextEnabled = nil
    else
        member.nextEnabled = enabled
    end
    return true
end


--- @param member table
--- @return boolean enabled what the member will be from the next morning
function EqStaffManager.willBeEnabled(member)
    if member.nextEnabled ~= nil then return member.nextEnabled end
    return member.enabled ~= false
end


--- @param animal table|nil RLRM Animal
--- @return string|nil key of the stable it lives in (RLRM's husbandry key), nil while ridden
function EqStaffManager.stableOf(animal)
    local system = animal ~= nil and animal.clusterSystem or nil
    local owner = system ~= nil and system.owner or nil
    if owner == nil or owner.spec_husbandryAnimals == nil then return nil end
    local keys = EqRLRM.get("RLHusbandryTargetKey")
    return keys ~= nil and keys.keyFor(owner) or nil
end


--- @param record table EqHorseRecord
--- @param animal table|nil RLRM Animal, for its stable
--- @return table horse what EqStaff needs to know about it
function EqStaffManager.horseInfo(record, animal)
    return { id = record.id, role = EqRole.get(record), retired = record.retired == true,
        stable = EqStaffManager.stableOf(animal) }
end


--- @param farmId number
--- @return table list of { horse, animal } for the farm's horses
local function farmHorses(farmId)
    local out = {}
    for _, animal in ipairs(EqRLRM.listHorsesForFarm(farmId)) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil then table.insert(out, { horse = EqStaffManager.horseInfo(record, animal), animal = animal }) end
    end
    return out
end
EqStaffManager.farmHorses = farmHorses


--- The farm's horse stables, for the stable picker.
--- @param farmId number
--- @return table list of { uniqueId, name }
function EqStaffManager.stablesOf(farmId)
    local out, seen = {}, {}
    local query = EqRLRM.get("RLAnimalQuery")
    local keys = EqRLRM.get("RLHusbandryTargetKey")
    if query == nil or keys == nil then return out end
    for i, placeable in ipairs(query.listHusbandriesForFarm(farmId)) do
        local holdsHorses = false
        local spec = placeable.spec_husbandryAnimals
        if spec ~= nil and spec.getClusters ~= nil then
            for _, animal in pairs(spec:getClusters() or {}) do
                if animal.isHorse ~= nil and animal:isHorse() then holdsHorses = true end
            end
        end
        local typeIndex = placeable.getAnimalTypeIndex ~= nil and placeable:getAnimalTypeIndex() or nil
        local horseType = AnimalType ~= nil and AnimalType.HORSE or nil
        local key = keys.keyFor(placeable)
        if key ~= nil and not seen[key] and (holdsHorses or (horseType ~= nil and typeIndex == horseType)) then
            seen[key] = true
            local name = query.formatHusbandryLabel ~= nil and query.formatHusbandryLabel(placeable, i)
                or (placeable.getName ~= nil and placeable:getName()) or key
            table.insert(out, { uniqueId = key, name = name })
        end
    end
    table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return out
end


--- The farm's staff and how many horses each works on, worked out once a day.
--- @param farmId number
--- @return table cache { day, members, counts }
local function cacheFor(farmId)
    local today = g_currentMission ~= nil and g_currentMission.environment.currentMonotonicDay or 0
    local cache = EqStaffManager.dayCache[farmId]
    if cache == nil or cache.day ~= today then
        local members = EqStaff.working(EqStaffManager.membersOf(farmId))
        local horses, byId = {}, {}
        if #members > 0 then
            for _, entry in ipairs(farmHorses(farmId)) do
                table.insert(horses, entry.horse)
                byId[entry.horse.id] = entry.horse
            end
        end
        cache = { day = today, members = members, counts = EqStaff.targetCounts(members, horses), byId = byId }
        EqStaffManager.dayCache[farmId] = cache
    end
    return cache
end


--- Everyone's work on one horse today, for EqTraining.applyDay.
--- @param record table EqHorseRecord
--- @param farmId number|nil
--- @return table|nil work stat -> list, nil with no staff
function EqStaffManager.workFor(record, farmId)
    if farmId == nil then return nil end
    local cache = cacheFor(farmId)
    if #cache.members == 0 then return nil end
    return EqStaff.workOn(cache.members, cache.byId[record.id] or EqStaffManager.horseInfo(record), cache.counts)
end


--- Staff's bonus to a horse's stats in an event of this discipline.
--- @param record table EqHorseRecord
--- @param farmId number|nil
--- @param discipline table events.xml discipline
--- @return table|nil bonus stat -> points, nil with no staff
function EqStaffManager.eventBonusFor(record, farmId, discipline)
    if farmId == nil or discipline == nil then return nil end
    local cache = cacheFor(farmId)
    if #cache.members == 0 then return nil end
    return EqStaff.eventBonus(cache.members, cache.byId[record.id] or EqStaffManager.horseInfo(record), cache.counts,
        EqStaff.eventSkills(discipline), discipline.weights or {})
end


--- @param farmId number|nil
--- @param skill string "veterinary" or "broker"
--- @return number strength 0..1, 0 with no farm
function EqStaffManager.strength(farmId, skill)
    if farmId == nil then return 0 end
    return EqStaff.strength(EqStaffManager.membersOf(farmId), skill)
end


--- The local player's farm's Broker, for the dealer's view (EqHorseRecord:getShownCeilings).
--- @return number strength 0..1
function EqStaffManager.localBroker()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return 0 end
    return EqStaffManager.strength(g_currentMission:getFarmId(), "broker")
end
EqHorseRecord.brokerStrength = EqStaffManager.localBroker


--- @return table farmIds farms with any staff
local function staffedFarms()
    local seen, out = {}, {}
    for _, member in ipairs(EqStaffManager.hired) do
        if not seen[member.farmId] then
            seen[member.farmId] = true
            table.insert(out, member.farmId)
        end
    end
    table.sort(out)
    return out
end


--- Pay the day's wages.
function EqStaffManager.onDayChanged()
    for _, farmId in ipairs(staffedFarms()) do
        local wages = EqStaff.dailyWages(EqStaffManager.membersOf(farmId))
        if wages > 0 then
            g_currentMission:addMoney(-wages, farmId, MoneyType.EQ_STAFF_WAGES or MoneyType.OTHER, true, true)
        end
    end
end


--- Each hour candidates come and go; in the last hour of the day the grooms' round: clean, and
--- bring loose horses home.
function EqStaffManager.onHourChanged()
    EqStaffManager.nextId = EqStaff.refreshCandidates(EqStaffManager.candidates, EqStaffManager.hourNow(), newRng(),
        EqStaffManager.nextId, false)
    local environment = g_currentMission.environment
    if environment == nil then return end
    if environment.currentHour == EqStaff.ENABLE_HOUR then
        -- Switching on or off takes effect each morning, for a whole day.
        for _, member in ipairs(EqStaffManager.hired) do
            if member.nextEnabled ~= nil then
                member.enabled = member.nextEnabled
                member.nextEnabled = nil
            end
        end
        EqStaffManager.dayCache = {}
    end
    if environment.currentHour ~= EqStaffManager.ROUND_HOUR then return end

    for _, farmId in ipairs(staffedFarms()) do
        local members = EqStaff.working(EqStaffManager.membersOf(farmId))
        local hasGroom = false
        for _, member in ipairs(members) do
            if member.job == "groom" then hasGroom = true end
        end
        if hasGroom then
            local entries, byId = farmHorses(farmId), {}
            local horses = {}
            for _, entry in ipairs(entries) do
                table.insert(horses, entry.horse)
                byId[entry.horse.id] = entry.animal
            end
            local cleaned = 0
            for _, horse in ipairs(EqStaff.toClean(members, horses)) do
                local animal = byId[horse.id]
                if animal ~= nil and (animal.dirt or 0) > 0 and animal.changeDirt ~= nil then
                    if animal.setDirty ~= nil then animal:setDirty() end
                    animal:changeDirt(-100)
                    cleaned = cleaned + 1
                end
            end
            -- Every pen with a horse in it counts as staffed, so loose horses come home.
            for _, entry in ipairs(entries) do
                local system = entry.animal.clusterSystem
                local pen = system ~= nil and system.owner or nil
                if pen ~= nil and pen.spec_husbandryAnimals ~= nil then EqLooseHorses.noteStaffed(pen) end
            end
            Log:debug("EqStaff: farm %d grooms cleaned %d horse(s)", farmId, cleaned)
        end
    end
end


local function saveMember(xmlFile, key, member)
    xmlFile:setInt(key .. "#id", member.id)
    xmlFile:setString(key .. "#name", member.name)
    xmlFile:setString(key .. "#job", member.job)
    xmlFile:setInt(key .. "#grade", member.grade)
    xmlFile:setInt(key .. "#dailyWage", member.wage)
    xmlFile:setInt(key .. "#talents", member.talents or 0)
    xmlFile:setInt(key .. "#face", EqStaff.faceOf(member))
    if member.farmId ~= nil then xmlFile:setInt(key .. "#farmId", member.farmId) end
    if member.leavesAt ~= nil then xmlFile:setInt(key .. "#leavesAt", member.leavesAt) end
    for _, skill in ipairs(EqStaff.SKILLS) do
        xmlFile:setInt(key .. ".skills#" .. skill, member.skills[skill] or 0)
    end
    if member.enabled == false then xmlFile:setBool(key .. "#enabled", false) end
    if member.nextEnabled ~= nil then xmlFile:setBool(key .. "#nextEnabled", member.nextEnabled) end
    local works = EqStaff.normalizeWorks(member.worksOn)
    xmlFile:setString(key .. ".worksOn#mode", works.mode)
    for listName, values in pairs({ stable = works.stables, role = works.roles, horse = works.horses }) do
        for i, value in ipairs(values or {}) do
            xmlFile:setString(string.format("%s.worksOn.%s(%d)#id", key, listName, i - 1), value)
        end
    end
    -- An empty stable or role list means none chosen; a missing one means all.
    if works.stables ~= nil then xmlFile:setBool(key .. ".worksOn#someStables", true) end
    if works.roles ~= nil then xmlFile:setBool(key .. ".worksOn#someRoles", true) end
end


--- @return table|nil list of the ids saved under key.listName(i)#id
local function loadList(xmlFile, key, listName)
    local out, i = {}, 0
    while true do
        local value = xmlFile:getString(string.format("%s.%s(%d)#id", key, listName, i))
        if value == nil then break end
        table.insert(out, value)
        i = i + 1
    end
    return out
end


--- @return table worksOn
local function loadWorks(xmlFile, key)
    local mode = xmlFile:getString(key .. "#mode")
    if mode == nil then
        -- Before stables and checklists: one role or one horse.
        return EqStaff.normalizeWorks({ kind = xmlFile:getString(key .. "#kind", EqStaff.WORKS_GENERAL),
            role = xmlFile:getString(key .. "#role"), id = xmlFile:getString(key .. "#horse") })
    end
    return {
        mode = mode,
        stables = xmlFile:getBool(key .. "#someStables", false) and loadList(xmlFile, key, "stable") or nil,
        roles = xmlFile:getBool(key .. "#someRoles", false) and loadList(xmlFile, key, "role") or nil,
        horses = loadList(xmlFile, key, "horse"),
    }
end


local function loadMember(xmlFile, key)
    local job = xmlFile:getString(key .. "#job")
    if EqStaff.JOBS[job] == nil then return nil end
    local member = {
        id = xmlFile:getInt(key .. "#id", 0),
        name = xmlFile:getString(key .. "#name", "?"),
        job = job,
        grade = math.max(1, math.min(#EqStaff.GRADES, xmlFile:getInt(key .. "#grade", 1))),
        wage = xmlFile:getInt(key .. "#dailyWage"),
        talents = xmlFile:getInt(key .. "#talents", 0),
        face = xmlFile:getInt(key .. "#face"),
        farmId = xmlFile:getInt(key .. "#farmId"),
        leavesAt = xmlFile:getInt(key .. "#leavesAt"),
        skills = {},
        enabled = xmlFile:getBool(key .. "#enabled", true),
        nextEnabled = xmlFile:getBool(key .. "#nextEnabled"),
        worksOn = loadWorks(xmlFile, key .. ".worksOn"),
    }
    for _, skill in ipairs(EqStaff.SKILLS) do
        member.skills[skill] = xmlFile:getInt(key .. ".skills#" .. skill, 0)
    end
    -- Saves from before daily wages held a monthly one: work out the daily wage again.
    if member.wage == nil then
        member.wage = EqStaff.wageFor(job, member.grade, member.skills, member.talents, 0)
    end
    return member
end


--- @param xmlFile table XMLFile
--- @param key string
function EqStaffManager.saveToXMLFile(xmlFile, key)
    xmlFile:setInt(key .. "#nextId", EqStaffManager.nextId)
    for i, member in ipairs(EqStaffManager.hired) do
        saveMember(xmlFile, string.format("%s.hired.member(%d)", key, i - 1), member)
    end
    for i, member in ipairs(EqStaffManager.candidates) do
        saveMember(xmlFile, string.format("%s.candidates.member(%d)", key, i - 1), member)
    end
end


--- @param xmlFile table|nil XMLFile; nil for a new game
--- @param key string
function EqStaffManager.loadFromXMLFile(xmlFile, key)
    EqStaffManager.reset()
    if xmlFile ~= nil then
        EqStaffManager.nextId = xmlFile:getInt(key .. "#nextId", 1)
        for _, list in ipairs({ { "hired", EqStaffManager.hired }, { "candidates", EqStaffManager.candidates } }) do
            local i = 0
            while true do
                local memberKey = string.format("%s.%s.member(%d)", key, list[1], i)
                if not xmlFile:hasProperty(memberKey) then break end
                local member = loadMember(xmlFile, memberKey)
                if member ~= nil then
                    table.insert(list[2], member)
                    EqStaffManager.nextId = math.max(EqStaffManager.nextId, member.id + 1)
                end
                i = i + 1
            end
        end
        if #EqStaffManager.hired > 0 then Log:info("EqStaff: loaded %d staff member(s)", #EqStaffManager.hired) end
    end
    EqStaffManager.ensureCandidates()
end


--- Start the daily wages, the hourly candidates and the grooms' round. Server only.
--- @param guarded function main.lua's error guard
function EqStaffManager.start(guarded)
    g_messageCenter:subscribe(MessageType.DAY_CHANGED, function()
        guarded("staff wages", EqStaffManager.onDayChanged)
    end, EqStaffManager)
    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, function()
        guarded("staff candidates and round", EqStaffManager.onHourChanged)
    end, EqStaffManager)
end


function EqStaffManager.stop()
    g_messageCenter:unsubscribeAll(EqStaffManager)
    EqStaffManager.reset()
end

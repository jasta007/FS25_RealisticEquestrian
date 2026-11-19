--[[
    EqBase.lua
    The base game's stand-ins for what Realistic Livestock (RLRM) gives this mod, used only when
    RLRM is not installed. With RLRM, none of this is installed and nothing here runs.

    - Horse identity. RLRM gives each animal a permanent id; the base game's horse clusters only
      have a number that is handed out again every load. So each horse gets our own id
      ("EQ-<n>"), saved as an extra attribute on its entry in the savegame and copied when the
      game clones the cluster (it does when a horse is taken out to ride). A horse that turns up
      without one (moved some way that doesn't clone) is matched back to its record by name.
    - Husbandry lists and keys, from the husbandry system and each placeable's unique id.
    - The daily horse tick, from the base horse's own day change (or the day change message,
      with the riding read from an hourly snapshot, when the game has no such function).
    - The genetics band words and colours RLRM's screens give our skill and potential words.
    - A message log of our own: the lines RLRM's Messages tab would hold, also shown as the
      game's notifications.

    Every base function used here is checked when it is hooked, and the log says which were
    found, so a game update that renames one shows up as a line in log.txt.
]]

EqBase = {}

local Log = EqLog

EqBase.ID_PREFIX = "EQ-"
EqBase.ID_ATTRIBUTE = "#eqId"

EqBase.installed = false
--- Ids carried by horses loaded from the savegame or handed out this session: id -> true
EqBase.known = {}
--- Highest number in an id seen so far
EqBase.highest = 0
--- true when the daily tick hooks the base horse's onDayChanged, false when it runs off the
--- day change message
EqBase.dailyFromCluster = false
--- id -> the riding level at the last hour change, for the message-driven daily tick
EqBase.ridingAtHour = {}
--- id -> the day it was last ticked, so a horse is never ticked twice in one day
EqBase.tickedDay = {}


-- SECTION: ids

--- @param id string|nil
--- @return number|nil n the number in an "EQ-<n>" id
function EqBase.idNumber(id)
    if type(id) ~= "string" then return nil end
    local digits = string.match(id, "^" .. EqBase.ID_PREFIX:gsub("%p", "%%%0") .. "(%d+)$")
    return digits ~= nil and tonumber(digits) or nil
end


--- Note an id as taken, so a new horse never gets it.
--- @param id string|nil
function EqBase.remember(id)
    if id == nil or id == "" then return end
    EqBase.known[id] = true
    local n = EqBase.idNumber(id)
    if n ~= nil and n > EqBase.highest then EqBase.highest = n end
end


--- @param records table|nil id -> record, also counted as taken (a horse sold or ridden away
---     keeps its record)
--- @return string id a new, unused id
function EqBase.newId(records)
    for id in pairs(records or {}) do EqBase.remember(id) end
    local id
    repeat
        EqBase.highest = EqBase.highest + 1
        id = EqBase.ID_PREFIX .. EqBase.highest
    until not EqBase.known[id] and (records == nil or records[id] == nil)
    EqBase.remember(id)
    return id
end


--- @param animal table a base horse cluster
--- @return string|nil name
local function nameOf(animal)
    local name = animal.getName ~= nil and animal:getName() or animal.name
    return type(name) == "string" and name ~= "" and name or nil
end


--- A horse that lost its id: the one record with its name that no other horse now carries.
--- @param name string|nil
--- @param records table id -> record
--- @param carried table id -> true for the ids live horses carry
--- @return string|nil id
function EqBase.matchByName(name, records, carried)
    if name == nil then return nil end
    local found = nil
    for id, record in pairs(records or {}) do
        if record.name == name and not carried[id] then
            if found ~= nil then return nil end   -- two candidates: don't guess
            found = id
        end
    end
    return found
end


--- The ids every horse the farms own carries right now.
--- @return table id -> true
local function carriedIds()
    local carried = {}
    if g_currentMission == nil or g_farmManager == nil or g_farmManager.getFarms == nil then return carried end
    for _, farm in pairs(g_farmManager:getFarms() or {}) do
        local farmId = farm.farmId
        if farmId ~= nil and farmId ~= 0 then
            for _, animal in ipairs(EqRLRM.listHorsesForFarm(farmId)) do
                if animal.eqId ~= nil then carried[animal.eqId] = true end
            end
            for _, animal in ipairs(EqRLRM.listHorsesInTrailers(farmId)) do
                if animal.eqId ~= nil then carried[animal.eqId] = true end
            end
        end
    end
    return carried
end


--- A base horse's id, handing out one the first time it is asked for.
--- @param animal table a base horse cluster
--- @return string|nil id
function EqBase.idOf(animal)
    if animal == nil then return nil end
    if animal.eqId ~= nil then return animal.eqId end
    -- Only the server hands out ids; a client has no records to match them to yet.
    if g_currentMission == nil or (g_currentMission.getIsServer ~= nil and not g_currentMission:getIsServer()) then
        return nil
    end

    local records = EqRegistry ~= nil and EqRegistry.records or {}
    local id = EqBase.matchByName(nameOf(animal), records, carriedIds())
    if id ~= nil then
        Log:info("EqBase: %s had lost its id; matched back to %s by name", tostring(nameOf(animal)), id)
        EqBase.remember(id)
    else
        id = EqBase.newId(records)
    end
    animal.eqId = id
    return id
end


-- SECTION: husbandries

--- Every husbandry a farm owns, sorted by name, as RLRM's query lists them.
--- @param farmId number
--- @return table placeables
function EqBase.listHusbandriesForFarm(farmId)
    local system = g_currentMission ~= nil and g_currentMission.husbandrySystem or nil
    if farmId == nil or farmId == 0 or system == nil or system.getPlaceablesByFarm == nil then return {} end
    local result = {}
    for _, placeable in ipairs(system:getPlaceablesByFarm(farmId) or {}) do table.insert(result, placeable) end
    table.sort(result, function(a, b)
        local nameA = (a.getName ~= nil and a:getName()) or ""
        local nameB = (b.getName ~= nil and b:getName()) or ""
        return nameA < nameB
    end)
    return result
end


--- @param husbandry table a husbandry placeable
--- @return table clusters its animal clusters
function EqBase.clustersOf(husbandry)
    if husbandry.getClusters ~= nil then return husbandry:getClusters() or {} end
    local spec = husbandry.spec_husbandryAnimals
    local system = spec ~= nil and spec.clusterSystem or nil
    return system ~= nil and system.getClusters ~= nil and system:getClusters() or {}
end


--- Note where a base horse was last found: RLRM's animals know their farm and pen, the base
--- game's clusters may not.
--- @param animal table
--- @param farmId number
--- @param husbandry table|nil its pen, nil while ridden or in a trailer
function EqBase.place(animal, farmId, husbandry)
    animal.eqFarmId = farmId
    animal.eqHusbandry = husbandry
end


--- @param animal table|nil
--- @return number|nil farmId the farm it was last found on
function EqBase.farmOf(animal)
    if animal == nil then return nil end
    if animal.eqFarmId == nil and g_farmManager ~= nil and g_farmManager.getFarms ~= nil then
        for _, farm in pairs(g_farmManager:getFarms() or {}) do
            if farm.farmId ~= nil and farm.farmId ~= 0 then EqRLRM.listHorsesForFarm(farm.farmId) end
            if animal.eqFarmId ~= nil then break end
        end
    end
    return animal.eqFarmId
end


--- @param animal table|nil
--- @return table|nil husbandry the pen it was last found in
function EqBase.husbandryOf(animal)
    if animal == nil then return nil end
    local system = animal.clusterSystem
    if system ~= nil and system.owner ~= nil then return system.owner end
    if animal.eqHusbandry == nil then EqBase.farmOf(animal) end
    return animal.eqHusbandry
end


--- A husbandry's lasting key: its unique id in the savegame.
--- @param placeable table|nil
--- @return string|nil key
function EqBase.husbandryKey(placeable)
    if placeable == nil or placeable.getUniqueId == nil then return nil end
    local key = placeable:getUniqueId()
    return type(key) == "string" and key ~= "" and key or nil
end


-- SECTION: genetics bands

-- The words RLRM gives its genetics bands, and their colours, for the skill and potential words.
EqBase.BAND_TEXT = {
    rl_ui_genetics_extremelyLow = "eq_band_extremelyLow",
    rl_ui_genetics_veryLow = "eq_band_veryLow",
    rl_ui_genetics_low = "eq_band_low",
    rl_ui_genetics_average = "eq_band_average",
    rl_ui_genetics_high = "eq_band_high",
    rl_ui_genetics_veryHigh = "eq_band_veryHigh",
    rl_ui_genetics_extremelyHigh = "eq_band_extremelyHigh",
}
EqBase.BAND_COLOR = {
    rl_ui_genetics_extremelyLow = { 1.00, 0.00, 0.00, 1 },
    rl_ui_genetics_veryLow = { 1.00, 0.20, 0.00, 1 },
    rl_ui_genetics_low = { 1.00, 0.52, 0.00, 1 },
    rl_ui_genetics_average = { 1.00, 1.00, 0.00, 1 },
    rl_ui_genetics_high = { 0.52, 1.00, 0.00, 1 },
    rl_ui_genetics_veryHigh = { 0.20, 1.00, 0.00, 1 },
    rl_ui_genetics_extremelyHigh = { 0.00, 1.00, 0.00, 1 },
}


--- @param key string an RLRM genetics band key, such as "rl_ui_genetics_high"
--- @return string text its word: RLRM's when RLRM is there, else ours
function EqBase.bandText(key)
    if EqRLRM.isAvailable then return g_i18n:getText(key, EqRLRM.MOD_NAME) end
    return g_i18n:getText(EqBase.BAND_TEXT[key] or key)
end


--- @param key string an RLRM genetics band key
--- @return table|nil color our copy of RLRM's colour for it
function EqBase.bandColor(key)
    local color = EqBase.BAND_COLOR[key]
    return color ~= nil and { color[1], color[2], color[3], color[4] } or nil
end


-- SECTION: hooks

--- @param class table|nil
--- @param name string
--- @return boolean present
local function has(class, name)
    return type(class) == "table" and type(class[name]) == "function"
end


--- Our id goes into the savegame beside the horse's own attributes, and comes back on load.
--- AnimalCluster's save and load run for horses too (AnimalClusterHorse calls them first).
local function installSaveLoad(guarded, found, missing)
    if has(AnimalCluster, "saveToXMLFile") then
        AnimalCluster.saveToXMLFile = Utils.appendedFunction(AnimalCluster.saveToXMLFile, function(self, xmlFile, key)
            if self.eqId == nil then return end
            guarded("horse id save", function() xmlFile:setString(key .. EqBase.ID_ATTRIBUTE, self.eqId) end)
        end)
        table.insert(found, "AnimalCluster.saveToXMLFile")
    else
        table.insert(missing, "AnimalCluster.saveToXMLFile")
    end

    if has(AnimalCluster, "loadFromXMLFile") then
        AnimalCluster.loadFromXMLFile = Utils.overwrittenFunction(AnimalCluster.loadFromXMLFile,
            function(self, superFunc, xmlFile, key, ...)
                local result = superFunc(self, xmlFile, key, ...)
                guarded("horse id load", function()
                    local id = xmlFile:getString(key .. EqBase.ID_ATTRIBUTE)
                    if id ~= nil and id ~= "" then
                        self.eqId = id
                        EqBase.remember(id)
                    end
                end)
                return result
            end)
        table.insert(found, "AnimalCluster.loadFromXMLFile")
    else
        table.insert(missing, "AnimalCluster.loadFromXMLFile")
    end
end


--- Riding a horse clones its cluster onto the horse vehicle; the clone keeps the id.
local function installClone(guarded, found, missing)
    for _, entry in ipairs({ { AnimalCluster, "AnimalCluster" }, { AnimalClusterHorse, "AnimalClusterHorse" } }) do
        local class, label = entry[1], entry[2]
        if has(class, "clone") then
            class.clone = Utils.overwrittenFunction(class.clone, function(self, superFunc, ...)
                local copy = superFunc(self, ...)
                if copy ~= nil and self.eqId ~= nil then copy.eqId = self.eqId end
                return copy
            end)
            table.insert(found, label .. ".clone")
        else
            table.insert(missing, label .. ".clone")
        end
    end
end


--- RLRM's Animal answers isHorse; the base clusters get the same question answered.
local function installIsHorse(found)
    if type(AnimalCluster) == "table" and AnimalCluster.isHorse == nil then
        AnimalCluster.isHorse = function() return false end
    end
    if type(AnimalClusterHorse) == "table" and rawget(AnimalClusterHorse, "isHorse") == nil then
        AnimalClusterHorse.isHorse = function() return true end
        table.insert(found, "AnimalClusterHorse.isHorse (ours)")
    end
end


--- The daily tick, once per horse per day, before the base game resets its riding.
--- @param animal table
--- @param riding number|nil the day's riding, when the cluster's own was reset already
function EqBase.tickHorse(animal, riding)
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return end
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    local today = environment ~= nil and environment.currentMonotonicDay or 0
    local id = EqBase.idOf(animal)
    if id == nil or EqBase.tickedDay[id] == today then return end
    EqBase.tickedDay[id] = today

    if riding ~= nil and (animal.riding or 0) < riding then
        local own = animal.riding
        animal.riding = riding
        EqLog.finally(function() animal.riding = own end, EqTrainingHooks.onHorseDay, animal)
    else
        EqTrainingHooks.onHorseDay(animal)
    end
end


--- Every horse on every farm: in pens, being ridden and in trailers.
--- @return table animals
local function allHorses()
    local horses = {}
    if g_farmManager == nil or g_farmManager.getFarms == nil then return horses end
    for _, farm in pairs(g_farmManager:getFarms() or {}) do
        if farm.farmId ~= nil and farm.farmId ~= 0 then
            for _, animal in ipairs(EqRLRM.listHorsesForFarm(farm.farmId)) do table.insert(horses, animal) end
            for _, animal in ipairs(EqRLRM.listHorsesInTrailers(farm.farmId)) do table.insert(horses, animal) end
        end
    end
    return horses
end


--- Note each horse's riding once an hour, for a day change that may come after the reset.
function EqBase.snapshotRiding()
    for _, animal in ipairs(allHorses()) do
        local id = EqBase.idOf(animal)
        if id ~= nil then EqBase.ridingAtHour[id] = animal.riding or 0 end
    end
end


--- The day changed: tick every horse the cluster hook didn't.
function EqBase.onDayChanged()
    for _, animal in ipairs(allHorses()) do
        local id = EqBase.idOf(animal)
        EqBase.tickHorse(animal, id ~= nil and EqBase.ridingAtHour[id] or nil)
    end
    EqBase.ridingAtHour = {}
end


local function installDaily(guarded, found, missing)
    if has(AnimalClusterHorse, "onDayChanged") then
        AnimalClusterHorse.onDayChanged = Utils.prependedFunction(AnimalClusterHorse.onDayChanged, function(self)
            if not EqMain.isActive or g_currentMission == nil or not g_currentMission:getIsServer() then return end
            guarded("daily training", function() EqBase.tickHorse(self) end)
        end)
        EqBase.dailyFromCluster = true
        table.insert(found, "AnimalClusterHorse.onDayChanged")
    else
        table.insert(missing, "AnimalClusterHorse.onDayChanged (the day change message ticks instead)")
    end
end


--- Start the session's message-driven parts. Server only.
--- @param guarded function
function EqBase.start(guarded)
    if not EqBase.installed or g_messageCenter == nil then return end
    -- Also when the cluster hook works: a horse in a trailer or being ridden may not get the
    -- cluster's day change, and tickHorse skips any horse already ticked today.
    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, function()
        guarded("riding snapshot", EqBase.snapshotRiding)
    end, EqBase)
    g_messageCenter:subscribe(MessageType.DAY_CHANGED, function()
        guarded("daily training (day change)", EqBase.onDayChanged)
    end, EqBase)
end


function EqBase.stop()
    if g_messageCenter ~= nil then g_messageCenter:unsubscribeAll(EqBase) end
    EqBase.known = {}
    EqBase.highest = 0
    EqBase.ridingAtHour = {}
    EqBase.tickedDay = {}
end


--- Hook the base game's horse clusters. Call once, from EqMain.activate, only without RLRM.
--- @param guarded function main.lua's error guard
function EqBase.install(guarded)
    if EqBase.installed then return end
    EqBase.installed = true
    local found, missing = {}, {}
    installIsHorse(found)
    installSaveLoad(guarded, found, missing)
    installClone(guarded, found, missing)
    installDaily(guarded, found, missing)
    Log:info("Running without Realistic Livestock. Base horse hooks: %s", table.concat(found, ", "))
    if #missing > 0 then Log:warning("Base horse functions not found: %s", table.concat(missing, ", ")) end
end

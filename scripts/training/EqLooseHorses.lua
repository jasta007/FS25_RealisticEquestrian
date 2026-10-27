--[[
    EqLooseHorses.lua
    Staff bring loose horses home. A horse the player rode and left out in the world stays a
    rideable vehicle, and the base game leaves it there overnight. When a pen's paid animal
    workers do their round (the riding or grooming task, at the end of the day or on "Do it
    now"), they also fetch that farm's loose horses: each goes back into its own pen, or the
    nearest staffed horse pen with room, and gets the same care the pen just had. With no
    staff on any of the farm's horse pens, loose horses stay where they were left.

    The base game's worker has no API we know of, so a round is noticed through RLRM's worker
    hooks on Animal (applyExercise / applyGrooming, and the getNeeds* checks the worker makes in
    the last hour of the day). The horses are fetched on the next frame, after the round, so the
    pen's animal list is never changed while the worker walks it. A horse goes into its pen the
    way the base game's trailer load takes a loose horse: added first, then the rideable removed.
    Server and single player only.
]]

EqLooseHorses = {}

-- Pens whose workers did a round since the last fetch: placeable -> { exercise, grooming }.
EqLooseHorses.staffed = {}
-- Where each horse was ridden from, by our horse id: placeable. Memory only; after a reload
-- the farm's nearest staffed horse pen with room takes it.
EqLooseHorses.homes = {}
EqLooseHorses.guarded = nil
EqLooseHorses.busy = false

-- The worker's own checks also run when menus ask; only those this late count as a round.
EqLooseHorses.ROUND_FROM_HOUR = 23

local Log = EqLog


--- @param animal table RLRM Animal
--- @return table|nil placeable the horse pen the animal is in
local function penOf(animal)
    local system = animal ~= nil and animal.clusterSystem or nil
    local placeable = system ~= nil and system.owner or nil
    if placeable ~= nil and placeable.spec_husbandryAnimals ~= nil then return placeable end
    return nil
end


--- @return boolean true in the last hour of the day, when the worker does its round
local function isRoundTime()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    local dayTime = environment ~= nil and environment.dayTime or nil
    return dayTime ~= nil and dayTime >= EqLooseHorses.ROUND_FROM_HOUR * 3600000
end


--- Note that a pen's workers are at work on one of its horses.
--- @param animal table RLRM Animal the worker is looking at
--- @param task string|nil "exercise" or "grooming" when the worker did that task
function EqLooseHorses.noteRound(animal, task)
    if EqLooseHorses.busy or g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return end
    local placeable = penOf(animal)
    if placeable == nil then return end

    local round = EqLooseHorses.staffed[placeable]
    if round == nil then
        round = {}
        EqLooseHorses.staffed[placeable] = round
    end
    if task ~= nil then round[task] = true end
end


--- The farm's horses left out in the world: rideables nobody is sitting on.
--- @return table list of { vehicle, animal, farmId }
function EqLooseHorses.findLoose()
    local loose = {}
    local vehicleSystem = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, vehicle in ipairs(vehicleSystem ~= nil and vehicleSystem.vehicles or {}) do
        local spec = vehicle.spec_rideable
        local animal = spec ~= nil and spec.cluster or nil
        local ridden = vehicle.getIsControlled ~= nil and vehicle:getIsControlled()
        local deleting = vehicle.isDeleted or vehicle.isDeleting
        if animal ~= nil and animal.uniqueId ~= nil and animal.isHorse ~= nil and animal:isHorse()
            and not ridden and not deleting then
            table.insert(loose, { vehicle = vehicle, animal = animal, farmId = vehicle:getOwnerFarmId() })
        end
    end
    return loose
end


--- @param placeable table horse pen
--- @param subTypeIndex number
--- @return boolean room for one more of this subtype
local function hasRoom(placeable, subTypeIndex)
    if placeable.getNumOfFreeAnimalSlots == nil then return false end
    local ok, free = EqLog.try("EqLooseHorses.hasRoom getNumOfFreeAnimalSlots", placeable.getNumOfFreeAnimalSlots, placeable, subTypeIndex)
    return ok and (free or 0) >= 1
end


--- @param placeable table
--- @return number|nil x, number|nil z
local function placeablePosition(placeable)
    local node = placeable.rootNode
    if type(node) ~= "number" or node == 0 then return nil end
    local ok, x, _, z = EqLog.try("EqLooseHorses.placeablePosition getWorldTranslation", getWorldTranslation, node)
    if ok then return x, z end
    return nil
end


--- Choose the pen a loose horse goes back to: its own pen when that has staff and room, else
--- the nearest of the farm's staffed pens with room. Pens are given as plain entries so the
--- choice can be tested without the game.
--- @param home table|nil the entry of the pen the horse came from
--- @param pens table list of { farmId, hasRoom, x, z } entries for staffed pens
--- @param farmId number the horse's farm
--- @param x number|nil the horse's position
--- @param z number|nil
--- @return table|nil pen the chosen entry
function EqLooseHorses.choosePen(home, pens, farmId, x, z)
    for _, pen in ipairs(pens) do
        if pen == home and pen.farmId == farmId and pen.hasRoom then return pen end
    end
    local best, bestDistance = nil, math.huge
    for _, pen in ipairs(pens) do
        if pen.farmId == farmId and pen.hasRoom then
            local distance = 0
            if x ~= nil and pen.x ~= nil then distance = math.sqrt((pen.x - x) ^ 2 + (pen.z - z) ^ 2) end
            if distance < bestDistance then best, bestDistance = pen, distance end
        end
    end
    return best
end


--- @param text string
local function notify(text)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
end


--- Put one loose horse back in a pen, as the base game's trailer load does: into the pen
--- first, then the rideable goes.
--- @param entry table from findLoose
--- @param placeable table horse pen
--- @param round table the pen's round: { exercise, grooming }
--- @return boolean ok
function EqLooseHorses.bringHome(entry, placeable, round)
    local animal = entry.animal
    if animal.clearPendingSpawnWorldPosition ~= nil then animal:clearPendingSpawnWorldPosition() end

    placeable:addAnimals({ animal })
    if penOf(animal) ~= placeable then
        Log:warning("EqLooseHorses: %s did not go into %s; left out in the world", tostring(animal.uniqueId),
            tostring(placeable.getName ~= nil and placeable:getName() or placeable))
        return false
    end

    entry.vehicle:delete()

    -- The horse missed the round it was fetched for, so it gets it now.
    if round.exercise and animal.applyExercise ~= nil then animal:applyExercise() end
    if round.grooming and animal.applyGrooming ~= nil then animal:applyGrooming() end
    return true
end


--- Fetch every loose horse whose farm had staff out on this round.
function EqLooseHorses.fetch()
    local staffed = EqLooseHorses.staffed
    EqLooseHorses.staffed = {}
    if next(staffed) == nil then return end

    local loose = EqLooseHorses.findLoose()
    if #loose == 0 then return end

    local pens, entryOf = {}, {}
    for placeable in pairs(staffed) do
        local x, z = placeablePosition(placeable)
        local pen = { placeable = placeable, farmId = placeable:getOwnerFarmId(), x = x, z = z }
        table.insert(pens, pen)
        entryOf[placeable] = pen
    end

    EqLooseHorses.busy = true
    for _, horse in ipairs(loose) do
        for _, pen in ipairs(pens) do pen.hasRoom = hasRoom(pen.placeable, horse.animal.subTypeIndex) end

        local id = EqRegistry.getId(horse.animal)
        local home = id ~= nil and EqLooseHorses.homes[id] or nil
        local x, z = nil, nil
        if horse.vehicle.rootNode ~= nil then
            local ok, hx, _, hz = EqLog.try("EqLooseHorses.fetch getWorldTranslation", getWorldTranslation, horse.vehicle.rootNode)
            if ok then x, z = hx, hz end
        end

        local pen = EqLooseHorses.choosePen(home ~= nil and entryOf[home] or nil, pens, horse.farmId, x, z)
        if pen ~= nil then
            local name = horse.animal.getName ~= nil and horse.animal:getName() or ""
            if EqLooseHorses.bringHome(horse, pen.placeable, staffed[pen.placeable]) then
                if id ~= nil then EqLooseHorses.homes[id] = nil end
                local penName = pen.placeable.getName ~= nil and pen.placeable:getName() or ""
                Log:info("EqLooseHorses: staff brought %s (%s) back to %s", name, tostring(horse.animal.uniqueId), penName)
                if g_currentMission:getFarmId() == horse.farmId then
                    if name ~= "" then
                        notify(string.format(g_i18n:getText("eq_loose_broughtHome"), name, penName))
                    else
                        notify(string.format(g_i18n:getText("eq_loose_broughtHomeUnnamed"), penName))
                    end
                end
            end
        end
    end
    EqLooseHorses.busy = false
end


--- The mission's updateable hook: fetch once a round has been noticed.
function EqLooseHorses:update(_)
    if next(EqLooseHorses.staffed) == nil then return end
    EqLooseHorses.guarded("loose horses", EqLooseHorses.fetch)
    -- A failed fetch must not leave the round hooks switched off.
    EqLooseHorses.busy = false
end


--- Remember the pen a horse is ridden from.
--- @param placeable table horse pen
--- @param clusterId string RLRM's key for the horse
function EqLooseHorses.noteRide(placeable, clusterId)
    local spec = placeable.spec_husbandryAnimals
    local system = spec ~= nil and spec.clusterSystem or nil
    local animal = system ~= nil and system.getClusterById ~= nil and system:getClusterById(clusterId) or nil
    local id = animal ~= nil and EqRegistry.getId(animal) or nil
    if id ~= nil then EqLooseHorses.homes[id] = placeable end
end


--- Hook the worker's checks and the start of a ride. Call from EqMain.activate.
--- @param guarded function main.lua's error guard
function EqLooseHorses.install(guarded)
    EqLooseHorses.guarded = guarded
    local Animal = EqRLRM.get("Animal")

    for _, task in ipairs({ { "applyExercise", "exercise" }, { "applyGrooming", "grooming" } }) do
        Animal[task[1]] = Utils.overwrittenFunction(Animal[task[1]], function(self, superFunc, ...)
            guarded("loose horses round", function() EqLooseHorses.noteRound(self, task[2]) end)
            return superFunc(self, ...)
        end)
    end
    for _, check in ipairs({ "getNeedsExercise", "getNeedsGrooming" }) do
        if Animal[check] ~= nil then
            Animal[check] = Utils.overwrittenFunction(Animal[check], function(self, superFunc, ...)
                guarded("loose horses round", function()
                    if isRoundTime() then EqLooseHorses.noteRound(self, nil) end
                end)
                return superFunc(self, ...)
            end)
        end
    end

    if PlaceableHusbandryAnimals ~= nil and PlaceableHusbandryAnimals.startRiding ~= nil then
        PlaceableHusbandryAnimals.startRiding = Utils.prependedFunction(PlaceableHusbandryAnimals.startRiding,
            function(self, clusterId)
                guarded("loose horses ride", function() EqLooseHorses.noteRide(self, clusterId) end)
            end)
    end
    Log:debug("EqLooseHorses: hooked the animal worker's tasks and PlaceableHusbandryAnimals:startRiding")
end


--- @param mission table
function EqLooseHorses.start(mission)
    if EqLooseHorses.guarded == nil then return end
    EqLooseHorses.staffed = {}
    mission:addUpdateable(EqLooseHorses)
end


--- @param mission table
function EqLooseHorses.stop(mission)
    if EqLooseHorses.guarded == nil then return end
    mission:removeUpdateable(EqLooseHorses)
    EqLooseHorses.staffed = {}
    EqLooseHorses.homes = {}
end

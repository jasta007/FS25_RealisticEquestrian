--[[
    EqAway.lua
    Horses away at events leave the game world: a horse entered in an open event (and, for
    Manual Transport, delivered) has no visual in its pasture until its result is in, and one
    back from abroad stays away until its quarantine is over.

    The horse stays in its husbandry the whole time (RLRM still feeds, ages and saves it); only
    its visual goes. We wrap AnimalClusterHusbandry:updateVisuals, which RLRM replaces with its
    own version: before RLRM's runs, we take away horses out of the list it draws and remove any
    visual they already have, the same steps RLRM's own stale-visual pass takes. When the horse
    is back, the next update draws it again. No RLRM file changes.

    A horse left out in the world (a rideable nobody is sitting on) has no pen visual to hide,
    so one that is away, in quarantine or injured is taken back to its pen (EqLooseHorses),
    staff or not; one being ridden goes when its rider gets off. Such a horse can't be ridden
    from its pen either: the ride prompt gives way to a line saying why.
]]

EqAway = {}

local Log = EqLog


--- @return table set horse id -> true for every horse entered in an open event, or in
---     quarantine after one abroad (EqQuarantine)
function EqAway.awayIds()
    local ids = {}
    for id, record in pairs(EqRegistry.records or {}) do
        if EqQuarantine.isIn(record) then ids[id] = true end
    end
    for _, event in pairs(EqCompetitionManager.events or {}) do
        -- Horses entered in their own farm's event stay at home to be ridden.
        for _, entry in ipairs(event.hosted == nil and event.entries or {}) do
            -- A Manual Transport horse stays home, to be loaded, until it is delivered.
            if EqCompetitionManager.isDelivered(entry) then ids[entry.horseId] = true end
        end
    end
    return ids
end


--- @param animal table RLRM Animal
--- @param ids table|nil from awayIds, built when nil
--- @return boolean away
function EqAway.isAway(animal, ids)
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return false end
    local id = EqRegistry.getId(animal)
    return id ~= nil and (ids or EqAway.awayIds())[id] == true
end


--- Why a horse can't be ridden now: away at an event, in quarantine, or injured.
--- @param animal table RLRM Animal
--- @param ids table|nil from awayIds, built when nil
--- @return string|nil reason "quarantine", "away" or "injured", nil when it can be ridden
function EqAway.rideBlock(animal, ids)
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return nil end
    local id = EqRegistry.getId(animal)
    if id == nil then return nil end
    local record = EqRegistry.getById(id)
    if record ~= nil and EqQuarantine.isIn(record) then return "quarantine" end
    if (ids or EqAway.awayIds())[id] == true then return "away" end
    if record ~= nil and record.injury ~= nil then return "injured" end
    return nil
end


--- @param animal table RLRM Animal
--- @param reason string from rideBlock
--- @return string text the line telling the player why the horse can't be ridden
function EqAway.rideBlockText(animal, reason)
    local name = animal.getName ~= nil and animal:getName() or ""
    if name == "" then name = g_i18n:getText("eq_ride_blocked_horse") end
    return string.format(g_i18n:getText("eq_ride_blocked_" .. reason), name)
end


--- Stop a ride from the pen for a horse that can't be ridden. The ride key's prompt goes and
--- a line says why; startRiding refuses too, for any other way in (the menu, other mods).
--- @param guarded function main.lua's error guard
function EqAway.installRideBlock(guarded)
    if PlayerInputComponent ~= nil and PlayerInputComponent.update ~= nil then
        PlayerInputComponent.update = Utils.appendedFunction(PlayerInputComponent.update, function(self)
            if self.rideableCluster == nil then return end
            guarded("ride block prompt", function()
                local animal = self.rideableCluster
                local reason = EqAway.rideBlock(animal)
                if reason == nil then return end
                self.rideablePlaceable = nil
                self.rideableCluster = nil
                if self.enterActionId ~= nil then g_inputBinding:setActionEventActive(self.enterActionId, false) end
                g_currentMission:addExtraPrintText(EqAway.rideBlockText(animal, reason))
            end)
        end)
    end

    if PlaceableHusbandryAnimals ~= nil and PlaceableHusbandryAnimals.startRiding ~= nil then
        PlaceableHusbandryAnimals.startRiding = Utils.overwrittenFunction(PlaceableHusbandryAnimals.startRiding,
            function(self, superFunc, clusterId, ...)
                local text
                guarded("ride block", function()
                    local spec = self.spec_husbandryAnimals
                    local system = spec ~= nil and spec.clusterSystem or nil
                    local animal = system ~= nil and system.getClusterById ~= nil and system:getClusterById(clusterId) or nil
                    local reason = EqAway.rideBlock(animal)
                    if reason ~= nil then text = EqAway.rideBlockText(animal, reason) end
                end)
                if text ~= nil then
                    Log:info("EqAway: ride refused: %s", text)
                    if g_currentMission.addIngameNotification ~= nil then
                        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text)
                    end
                    return
                end
                return superFunc(self, clusterId, ...)
            end)
    end
    Log:debug("EqAway: ride block on PlayerInputComponent:update and PlaceableHusbandryAnimals:startRiding")
end


--- Remove one horse's visual from a cluster husbandry, as RLRM's stale-visual pass does.
--- @param husbandry table AnimalClusterHusbandry
--- @param index number index into husbandry.husbandryIds
--- @param animalId number the engine's animal id in that husbandry
--- @param animal table RLRM Animal
local function removeVisual(husbandry, index, animalId, animal)
    local engineId = husbandry.husbandryIds[index]
    local count = engineId ~= nil and husbandry.husbandryIdsToVisualAnimalCount[engineId] or nil
    if count ~= nil then
        husbandry.husbandryIdsToVisualAnimalCount[engineId] = math.max(count - 1, 0)
        husbandry.visualAnimalCount = math.max((husbandry.visualAnimalCount or 0) - 1, 0)
    end
    if engineId ~= nil then removeHusbandryAnimal(engineId, animalId) end
    animal.id = nil
    animal.idFull = nil
    animal.visualAnimalIndex = nil
    if animal.deleteVisual ~= nil then animal:deleteVisual() end
end


--- Our part of updateVisuals: drop away horses from the list to draw and from the world.
--- @param husbandry table AnimalClusterHusbandry
--- @return table|nil original the unfiltered list, to put back after RLRM's update
function EqAway.beforeUpdate(husbandry)
    -- RLRM's fields; if a future RLRM renames them, leave the visuals alone.
    if type(husbandry.animalIdToCluster) ~= "table" or type(husbandry.husbandryIds) ~= "table"
        or type(husbandry.husbandryIdsToVisualAnimalCount) ~= "table" then
        return nil
    end

    local ids = EqAway.awayIds()
    if next(ids) == nil then return nil end

    for index, animals in pairs(husbandry.animalIdToCluster) do
        if type(animals) == "table" then
            local gone = {}
            for animalId, animal in pairs(animals) do
                if EqAway.isAway(animal, ids) then
                    removeVisual(husbandry, index, animalId, animal)
                    table.insert(gone, animalId)
                end
            end
            for _, animalId in ipairs(gone) do animals[animalId] = nil end
        end
    end

    local original = husbandry.nextUpdateClusters
    if original ~= nil then
        local home = {}
        for _, animal in pairs(original) do
            if not EqAway.isAway(animal, ids) then table.insert(home, animal) end
        end
        husbandry.nextUpdateClusters = home
    end
    return original
end


--- Redraw the pasture an animal lives in, so it leaves or comes back.
--- @param animal table RLRM Animal
function EqAway.refresh(animal)
    local system = animal ~= nil and animal.clusterSystem or nil
    local placeable = system ~= nil and system.owner or nil
    if placeable ~= nil and placeable.updateVisualAnimals ~= nil then placeable:updateVisualAnimals() end
end


--- Redraw every pasture holding one of these horses.
--- @param animals table list of RLRM Animals
function EqAway.refreshAll(animals)
    local done = {}
    for _, animal in ipairs(animals) do
        local placeable = animal.clusterSystem ~= nil and animal.clusterSystem.owner or nil
        if placeable ~= nil and not done[placeable] then
            done[placeable] = true
            EqAway.refresh(animal)
        end
    end
end


--- Wrap updateVisuals. Call from EqMain.activate, after RLRM has installed its own version.
--- @param guarded function main.lua's error guard
function EqAway.install(guarded)
    AnimalClusterHusbandry.updateVisuals = Utils.overwrittenFunction(AnimalClusterHusbandry.updateVisuals,
        function(self, superFunc, removeAll)
            local original
            guarded("away horses", function() original = EqAway.beforeUpdate(self) end)
            superFunc(self, removeAll)
            -- RLRM clears the list once it has drawn it; put ours back only if it kept it
            -- (a deferred update keeps it to draw later, and must still see every animal).
            if original ~= nil and self.nextUpdateClusters ~= nil then self.nextUpdateClusters = original end
        end)
    Log:debug("EqAway: hooked AnimalClusterHusbandry:updateVisuals")
end

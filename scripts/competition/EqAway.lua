--[[
    EqAway.lua
    Horses away at events leave the game world: a horse entered in an open event has no visual
    in its pasture until the event has run and its result is in.

    The horse stays in its husbandry the whole time (RLRM still feeds, ages and saves it); only
    its visual goes. We wrap AnimalClusterHusbandry:updateVisuals, which RLRM replaces with its
    own version: before RLRM's runs, we take away horses out of the list it draws and remove any
    visual they already have, the same steps RLRM's own stale-visual pass takes. When the horse
    is back, the next update draws it again. No RLRM file changes.
]]

EqAway = {}

local Log = EqLog


--- @return table set horse id -> true for every horse entered in an open event
function EqAway.awayIds()
    local ids = {}
    for _, event in pairs(EqCompetitionManager.events or {}) do
        for _, entry in ipairs(event.entries or {}) do ids[entry.horseId] = true end
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

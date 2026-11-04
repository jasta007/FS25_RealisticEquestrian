--[[
    EqFoals.lua
    Young horses look and act their age.

    - A horse under FOAL_VISUAL_AGE months is drawn smaller in its pen (FOAL_SCALE). The game
      has no foal model for horses, so we scale the adult one's root node; the node sits at the
      hooves, so the foal stays on the ground. At FOAL_VISUAL_AGE it switches to full size in
      one go, as the base game does when a calf or lamb grows up.
    - A horse under AGE_MIN_RIDE months can't be ridden (EqAway.rideBlock gives "tooYoung").

    The scale goes on after every AnimalClusterHusbandry:updateVisuals (RLRM's), when a visual
    is drawn, and on each new day for every pen, as horses grow up between redraws. Visuals are
    local to each machine, so this runs on clients too.
]]

EqFoals = {}

local Log = EqLog


--- @param ageMonths number|nil
--- @return number scale the pen visual's size for a horse this old
function EqFoals.scaleFor(ageMonths)
    if ageMonths ~= nil and ageMonths >= 0 and ageMonths < EqConstants.FOAL_VISUAL_AGE then
        return EqConstants.FOAL_SCALE
    end
    return 1
end


--- @param animal table|nil RLRM Animal
--- @return boolean true for a horse too young to be ridden
function EqFoals.isTooYoungToRide(animal)
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return false end
    local age = animal.age
    if age == nil and animal.getAge ~= nil then age = animal:getAge() end
    return age ~= nil and age >= 0 and age < EqConstants.AGE_MIN_RIDE
end


--- Size every horse visual in one cluster husbandry for its age.
--- @param husbandry table AnimalClusterHusbandry (RLRM's layout: animalIdToCluster[index][animalId])
function EqFoals.apply(husbandry)
    if type(husbandry) ~= "table" or type(husbandry.animalIdToCluster) ~= "table"
        or type(husbandry.husbandryIds) ~= "table" then
        return
    end
    for index, animals in pairs(husbandry.animalIdToCluster) do
        local engineId = husbandry.husbandryIds[index]
        if engineId ~= nil and type(animals) == "table" then
            for animalId, animal in pairs(animals) do
                if type(animal) == "table" and animal.isHorse ~= nil and animal:isHorse() then
                    local node = getAnimalRootNode(engineId, animalId)
                    if node ~= nil and node ~= 0 then
                        local s = EqFoals.scaleFor(animal.age)
                        setScale(node, s, s, s)
                    end
                end
            end
        end
    end
end


--- Size the horses in every pen on the map.
function EqFoals.applyAll()
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local spec = placeable.spec_husbandryAnimals
        if spec ~= nil and spec.clusterHusbandry ~= nil then EqFoals.apply(spec.clusterHusbandry) end
    end
end


--- @param guarded function main.lua's error guard
function EqFoals.install(guarded)
    AnimalClusterHusbandry.updateVisuals = Utils.appendedFunction(AnimalClusterHusbandry.updateVisuals,
        function(self)
            guarded("foal size", function() EqFoals.apply(self) end)
        end)
    Log:debug("EqFoals: hooked AnimalClusterHusbandry:updateVisuals")
end


--- Called once the mission has loaded: size the pens now and every new day.
--- @param guarded function main.lua's error guard
function EqFoals.start(guarded)
    guarded("foal size", EqFoals.applyAll)
    g_messageCenter:subscribe(MessageType.DAY_CHANGED, function()
        guarded("foal size", EqFoals.applyAll)
    end, EqFoals)
end


function EqFoals.stop()
    if g_messageCenter ~= nil then g_messageCenter:unsubscribeAll(EqFoals) end
end

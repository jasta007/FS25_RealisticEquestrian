--[[
    EqFreshStart.lua
    Some maps place horses in their farms' barns with age 0 and health 0 and no weight (Midwest
    Moraines 4X does, in its config/placeables.xml). RLRM loads those numbers as they are, and
    nobody feeds an unowned farm's barn, so by the time the player buys the farm its horses have
    starved to nothing: a few kilograms, no health, worth about $100, and soon dead.

    When such a horse turns up on a player's farm it gets a fresh start: an adult age, full
    health, a normal weight for its type, and starting stats drawn for that age. The check is
    narrow so a real horse never matches it: newborn, no mother, never ridden and almost no
    health. A foal born on a farm has a mother, and a dealer horse is healthy. Server only.
]]

EqFreshStart = {}

EqFreshStart.MAX_HEALTH = 5
EqFreshStart.MIN_AGE_MONTHS = 48
EqFreshStart.MAX_AGE_MONTHS = 144

local Log = EqLog


--- @param animal table RLRM Animal
--- @return boolean true for a horse the map placed with no age and no health
function EqFreshStart.isMapPlaceholder(animal)
    if animal == nil or animal.isDead or animal.isHorse == nil or not animal:isHorse() then return false end
    local motherId = animal.motherId
    local hasMother = motherId ~= nil and motherId ~= "" and motherId ~= "-1" and motherId ~= -1
    return (animal.age or 0) == 0
        and not hasMother
        and (animal.health or 0) < EqFreshStart.MAX_HEALTH
        and (animal.fitness or 0) <= 0
        and (animal.riding or 0) <= 0
end


--- Make a placeholder horse a healthy adult, and redraw its starting stats for its new age.
--- @param animal table RLRM Animal
--- @param rng table EqRandom
function EqFreshStart.repair(animal, rng)
    animal.age = math.floor(rng:uniform(EqFreshStart.MIN_AGE_MONTHS, EqFreshStart.MAX_AGE_MONTHS + 1))
    animal.health = 100

    local subType = animal.getSubType ~= nil and animal:getSubType() or nil
    local target = animal.targetWeight or (subType ~= nil and subType.targetWeight) or nil
    if target ~= nil and target > 0 then
        animal.weight = target * rng:uniform(0.92, 1.0)
    end

    local id = EqRegistry.getId(animal)
    local record = id ~= nil and EqRegistry.getById(id) or nil
    if record ~= nil and record.career.starts == 0 then record.redrawStart = true end
    EqRegistry.getOrCreate(animal)

    if animal.setDirty ~= nil then pcall(animal.setDirty, animal) end
end


--- Give every placeholder horse on the players' farms a fresh start.
--- @return number count horses repaired
function EqFreshStart.check()
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() or g_farmManager == nil then return 0 end

    local count = 0
    for _, farm in pairs(g_farmManager:getFarms()) do
        local farmId = farm.farmId
        if farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID then
            for _, animal in ipairs(EqRLRM.listHorsesForFarm(farmId)) do
                if EqFreshStart.isMapPlaceholder(animal) then
                    EqFreshStart.repair(animal, EqRandom.new("fresh start " .. tostring(EqRegistry.getId(animal))
                        .. " " .. tostring(animal.uniqueId) .. " " .. tostring(farmId)))
                    Log:info("EqFreshStart: %s (%s) on farm %d was a starved map horse, now %d months old",
                        tostring(animal.name), tostring(EqRegistry.getId(animal)), farmId, animal.age)
                    count = count + 1
                end
            end
        end
    end
    return count
end

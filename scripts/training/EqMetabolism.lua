--[[
    EqMetabolism.lua
    RLRM's metabolism gene already sets how much a horse eats (and its weight). Here it also sets
    how quickly the horse gets fit: a fast metabolism costs more feed but builds fitness faster
    from riding, a slow one is cheap to keep but slow to bring back into condition. Fitness lost
    is not changed.

    Wraps RLRM's AnimalHorse.changeFitness, which RLRM's daily riding update goes through.
    No RLRM file changes.
]]

EqMetabolism = {}

local Log = EqLog


--- How much faster than usual a horse with this metabolism gains fitness.
--- @param metabolism number|nil RLRM's genetics.metabolism (1.0 is average, about 0.25..1.75)
--- @return number factor 1 at average
function EqMetabolism.fitnessFactor(metabolism)
    if type(metabolism) ~= "number" then return 1 end
    local factor = 1 + (metabolism - 1) * EqConstants.METABOLISM_FITNESS_LEAN
    return EqStats.clamp(factor, EqConstants.METABOLISM_FITNESS_MIN, EqConstants.METABOLISM_FITNESS_MAX)
end


--- @param animal table RLRM Animal
--- @param delta number RLRM's fitness change
--- @return number delta gains scaled by metabolism, losses as they were
function EqMetabolism.scaleFitness(animal, delta)
    if type(delta) ~= "number" or delta <= 0 then return delta end
    local genetics = animal ~= nil and animal.genetics or nil
    return delta * EqMetabolism.fitnessFactor(genetics ~= nil and genetics.metabolism or nil)
end


--- @param guarded function main.lua's error guard
function EqMetabolism.install(guarded)
    local animalHorse = EqRLRM.get("AnimalHorse")
    local original = animalHorse.changeFitness
    animalHorse.changeFitness = function(animal, delta, ...)
        local scaled = delta
        guarded("metabolism fitness", function() scaled = EqMetabolism.scaleFitness(animal, delta) end)
        return original(animal, scaled, ...)
    end
    Log:debug("EqMetabolism: hooked AnimalHorse.changeFitness")
end

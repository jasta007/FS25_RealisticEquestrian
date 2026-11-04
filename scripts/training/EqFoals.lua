--[[
    EqFoals.lua
    Young horses can't do a grown horse's work.

    - A horse under AGE_MIN_RIDE months can't be ridden (EqAway.rideBlock gives "tooYoung"); up
      to AGE_GROUNDWORK its riding bar fills YOUNG_BAR_SPEED times as fast (ridingBarFactor).

    Foals still use the adult model. Scaling it from Lua doesn't work (tested 2026-11-04): the
    engine resets the animal root's scale every frame, and scaling the skeleton or mesh nodes
    under it tears the skinned mesh. A smaller foal needs its own model.
]]

EqFoals = {}


--- @param animal table|nil RLRM Animal
--- @return boolean true for a horse too young to be ridden
function EqFoals.isTooYoungToRide(animal)
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return false end
    local age = animal.age
    if age == nil and animal.getAge ~= nil then age = animal:getAge() end
    return age ~= nil and age >= 0 and age < EqConstants.AGE_MIN_RIDE
end

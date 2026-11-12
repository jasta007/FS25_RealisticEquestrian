--[[
    EqFoals.lua
    Young horses can't do a grown horse's work, and the Horse maturing setting says how fast
    they grow up (James 2026-11-12):

                     foal model   ridden from   training events   other events
      accelerated    0-6 months   6 months      12-23 months      24 months+    (default)
      realistic      0-12 months  12 months     24-35 months      36 months+

    data/events.xml holds the realistic ages; accelerated takes EVENT_AGE_SHIFT_FAST months off them.
    - A horse too young to ride gets "tooYoung" from EqAway.rideBlock; until training events
      open, its riding bar fills YOUNG_BAR_SPEED times as fast (EqTraining.ridingBarFactor).
    - The foal model itself is EqFoalVisuals (a scaled adult doesn't work: the engine resets
      the animal root's scale every frame, tested 2026-11-04).
]]

EqFoals = {}
EqFoals.ACCELERATED = "accelerated"
EqFoals.REALISTIC = "realistic"


--- The Horse maturing setting, accelerated unless the save says realistic.
--- @return string "accelerated" or "realistic"
function EqFoals.maturing()
    local settings = EqCompetitionManager ~= nil and EqCompetitionManager.settings or nil
    if settings ~= nil and settings.maturing == EqFoals.REALISTIC then return EqFoals.REALISTIC end
    return EqFoals.ACCELERATED
end


--- Months taken off the realistic event ages (and AGE_GROUNDWORK).
function EqFoals.shift()
    return EqFoals.maturing() == EqFoals.REALISTIC and 0 or EqConstants.EVENT_AGE_SHIFT_FAST
end


--- Below this age (months) a horse shows the foal model and can't be ridden.
function EqFoals.rideAge()
    return EqFoals.maturing() == EqFoals.REALISTIC and EqConstants.AGE_MIN_RIDE or EqConstants.AGE_MIN_RIDE_FAST
end


--- Below this age (months) a ridden horse only does light work (training events open here).
function EqFoals.groundworkAge()
    return EqConstants.AGE_GROUNDWORK - EqFoals.shift()
end


--- An event tier's ages under the current setting.
--- @param tier table from EqEventConfig (realistic ages)
--- @return number minAge
--- @return number maxAge 0 for no limit
function EqFoals.tierAges(tier)
    local shift = EqFoals.shift()
    local maxAge = tier.maxAge or 0
    return math.max(0, (tier.minAge or 0) - shift), maxAge > 0 and math.max(0, maxAge - shift) or 0
end


--- @param animal table|nil RLRM Animal
--- @return boolean true for a horse too young to be ridden
function EqFoals.isTooYoungToRide(animal)
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return false end
    local age = animal.age
    if age == nil and animal.getAge ~= nil then age = animal:getAge() end
    return age ~= nil and age >= 0 and age < EqFoals.rideAge()
end

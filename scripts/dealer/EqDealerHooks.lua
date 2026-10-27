--[[
    EqDealerHooks.lua
    Prices a horse by its skill, talent, soundness and breeding value, on top of RLRM's own price. Wraps RLRM's
    AnimalHorse.getHorseSellPrice, which both the dealer's asking price (times RLRM's dealer
    markup) and a horse's sale value go through, so buying and selling stay consistent and the
    markup still stops buy-and-sell-back loops. A farm's broker takes a little off buying and adds a
    little to selling (EqStaff.dealFactor); the sale premium waits a month after buying, so the
    markup still guards against buying to sell back. No RLRM file changes.
]]

EqDealerHooks = {}

local Log = EqLog


--- @param animal table RLRM Animal (a horse)
--- @return number|nil base the subtype's base price at the horse's age
local function basePrice(animal)
    local subType = animal.getSubType ~= nil and animal:getSubType() or nil
    if subType == nil or subType.sellPrice == nil then return nil end
    return subType.sellPrice:get(math.max(animal.age or 0, 0))
end


--- @param animal table RLRM Animal (a horse)
--- @param rlrmPrice number RLRM's price
--- @return number price
function EqDealerHooks.priceFor(animal, rlrmPrice)
    local record = EqRegistry.getOrCreate(animal)
    local base = basePrice(animal)
    if record == nil or base == nil then return rlrmPrice end
    local price = EqDealer.price(rlrmPrice, base, record:getDealerCeilings(), record.trained, animal.age or 0,
        EqDealer.condition(animal, record))
    return price * EqDealerHooks.brokerFactor(animal, record)
end


--- A farm's broker gets a better price: cheaper from the dealer (for the local player, who is
--- the one buying), dearer when selling a horse the farm has had a month or more.
--- @param animal table RLRM Animal (a horse)
--- @param record table EqHorseRecord
--- @return number factor
function EqDealerHooks.brokerFactor(animal, record)
    if EqStaffManager == nil then return 1 end
    local farmId = EqFacilityHooks.farmOfAnimal(animal)
    if farmId == nil then return EqStaff.dealFactor(EqStaffManager.localBroker(), false) end
    if record.ownedMonths ~= nil and record.ownedMonths < 1 then return 1 end
    return EqStaff.dealFactor(EqStaffManager.strength(farmId, "broker"), true)
end


--- @param guarded function main.lua's error guard
function EqDealerHooks.install(guarded)
    local animalHorse = EqRLRM.get("AnimalHorse")
    local original = animalHorse.getHorseSellPrice
    animalHorse.getHorseSellPrice = function(animal, ...)
        local price = original(animal, ...)
        local result = price
        guarded("horse price", function() result = EqDealerHooks.priceFor(animal, price) end)
        return result
    end
    Log:debug("EqDealerHooks: hooked AnimalHorse.getHorseSellPrice")
end

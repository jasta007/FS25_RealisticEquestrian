--[[
    EqProbe.lua
    Remembers the base game's animal loading triggers as they are created, so EqDelivery can
    find a trailer standing in the dealer's trigger. Read-only: it changes nothing in the game.
]]

EqProbe = {}
EqProbe.triggers = setmetatable({}, { __mode = "k" })

local Log = EqLog


--- Remember every animal loading trigger the game creates. Call at source time.
function EqProbe.install()
    if AnimalLoadingTrigger == nil or AnimalLoadingTrigger.new == nil then
        Log:warning("EqProbe: AnimalLoadingTrigger not found; delivery at the dealer is off")
        return
    end
    AnimalLoadingTrigger.new = Utils.overwrittenFunction(AnimalLoadingTrigger.new, function(first, superFunc, ...)
        local trigger = superFunc(first, ...)
        if type(trigger) == "table" then EqProbe.triggers[trigger] = true end
        return trigger
    end)
end

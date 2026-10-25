--[[
    EqProbe.lua
    Testing aid for Manual Transport (step 3): finds the base game's animal loading triggers
    and writes what they hold to the log, so delivery at the dealer can be built against the
    real fields. eqProbe dumps every trigger, nearest first, with any trailer inside it and the
    animals in that trailer. Read-only: it changes nothing in the game. EqDelivery uses the
    triggers it remembers to find a trailer at the dealer.
]]

EqProbe = {}
EqProbe.triggers = setmetatable({}, { __mode = "k" })

local Log = EqLog


--- Remember every animal loading trigger the game creates. Call at source time.
function EqProbe.install()
    if AnimalLoadingTrigger == nil or AnimalLoadingTrigger.new == nil then
        Log:warning("EqProbe: AnimalLoadingTrigger not found; eqProbe will list nothing")
        return
    end
    AnimalLoadingTrigger.new = Utils.overwrittenFunction(AnimalLoadingTrigger.new, function(first, superFunc, ...)
        local trigger = superFunc(first, ...)
        if type(trigger) == "table" then EqProbe.triggers[trigger] = true end
        return trigger
    end)
end


--- @param value any
--- @return string text one-line description
local function describe(value)
    local kind = type(value)
    if kind == "number" or kind == "boolean" or kind == "string" then return tostring(value) end
    if kind == "table" then
        local name = nil
        if type(value.getName) == "function" then
            local ok, result = pcall(value.getName, value)
            if ok then name = result end
        end
        local typeName = value.typeName or (value.customEnvironment ~= nil and "vehicle") or nil
        return string.format("table%s%s", name ~= nil and (" '" .. tostring(name) .. "'") or "",
            typeName ~= nil and (" [" .. tostring(typeName) .. "]") or "")
    end
    return kind
end


--- @return number|nil x, number|nil y, number|nil z the local player's position
local function playerPosition()
    local ok, x, y, z = pcall(function()
        if g_localPlayer ~= nil and g_localPlayer.getPosition ~= nil then return g_localPlayer:getPosition() end
        return nil
    end)
    if ok then return x, y, z end
    return nil
end


--- @param trigger table
--- @return number|nil x, number|nil y, number|nil z
local function triggerPosition(trigger)
    local node = trigger.triggerNode or trigger.rootNode or trigger.activationTrigger
    if type(node) ~= "number" or node == 0 then return nil end
    local ok, x, y, z = pcall(getWorldTranslation, node)
    if ok then return x, y, z end
    return nil
end


--- @param trailer table vehicle
--- @param lines table
local function describeTrailer(trailer, lines)
    table.insert(lines, string.format("    trailer: %s", describe(trailer)))
    local spec = trailer.spec_livestockTrailer
    if spec == nil then
        table.insert(lines, "    (no spec_livestockTrailer)")
        return
    end
    for key, value in pairs(spec) do
        table.insert(lines, string.format("    spec.%s = %s", tostring(key), describe(value)))
    end
    local ok, clusters = pcall(function() return trailer:getClusters() end)
    if ok and type(clusters) == "table" then
        for _, animal in pairs(clusters) do
            local id = EqRegistry ~= nil and EqRegistry.getId(animal) or nil
            local away = EqCompetitionManager ~= nil and EqCompetitionManager.awaitingDelivery(animal)
            table.insert(lines, string.format("    animal: %s id=%s horse=%s awaitingDelivery=%s",
                tostring(animal.getName ~= nil and animal:getName() or "?"), tostring(id),
                tostring(animal.isHorse ~= nil and animal:isHorse()), tostring(away)))
        end
    else
        table.insert(lines, "    getClusters failed or empty")
    end
end


--- eqProbe: write every animal loading trigger to the log, nearest first.
--- @return string summary
function EqProbe.run()
    local px, _, pz = playerPosition()
    local list = {}
    for trigger in pairs(EqProbe.triggers) do
        local x, y, z = triggerPosition(trigger)
        local distance = (x ~= nil and px ~= nil) and math.sqrt((x - px) ^ 2 + (z - pz) ^ 2) or math.huge
        table.insert(list, { trigger = trigger, x = x, y = y, z = z, distance = distance })
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)

    local lines = { string.format("EqProbe: %d animal loading trigger(s); player at %s, %s", #list,
        tostring(px), tostring(pz)) }
    for i, item in ipairs(list) do
        local trigger = item.trigger
        table.insert(lines, string.format("trigger %d: distance %.1f at %s %s %s", i, item.distance,
            tostring(item.x), tostring(item.y), tostring(item.z)))
        local keys = {}
        for key in pairs(trigger) do table.insert(keys, tostring(key)) end
        table.sort(keys)
        for _, key in ipairs(keys) do
            table.insert(lines, string.format("  %s = %s", key, describe(trigger[key])))
        end
        for _, key in ipairs({ "loadingVehicle", "activatedTarget", "currentVehicle", "vehicle" }) do
            local value = trigger[key]
            if type(value) == "table" then describeTrailer(value, lines) end
        end
    end

    local ok, vehicle = pcall(function() return g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() or nil end)
    if ok and type(vehicle) == "table" then
        table.insert(lines, "player's vehicle:")
        describeTrailer(vehicle, lines)
        if type(vehicle.getAttachedImplements) == "function" then
            for _, implement in pairs(vehicle:getAttachedImplements() or {}) do
                if implement.object ~= nil then describeTrailer(implement.object, lines) end
            end
        end
    end

    for _, line in ipairs(lines) do Log:info("%s", line) end
    return string.format("EqProbe: wrote %d trigger(s) to log.txt (nearest %.0fm away)", #list,
        list[1] ~= nil and list[1].distance or -1)
end

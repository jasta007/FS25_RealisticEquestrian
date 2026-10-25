--[[
    EqDelivery.lua
    Manual Transport step 3: delivering a horse to its event at the animal dealer. With a
    livestock trailer in the dealer's loading area holding one of your horses that is waiting
    for delivery, a "Deliver to event" action appears beside the dealer's own prompt (its own
    key, so selling is never involved). Pressing it moves the horses home with RLRM's
    AnimalMoveEvent, trailer to pasture, and marks them delivered, so they are hidden there
    until the event is over and RLRM keeps looking after them.

    The dealer trigger is the base game's AnimalLoadingTrigger with isDealer set; the trailer in
    it is its loadingVehicle (eqProbe, in game). Server and single player only for now.
]]

EqDelivery = {}
EqDelivery.actionEventId = nil
EqDelivery.pending = false
EqDelivery.horses = {}
EqDelivery.trailer = nil
EqDelivery.timer = 0
EqDelivery.guarded = nil

-- How often the trailer is checked, and how close the player must be to the trigger.
EqDelivery.CHECK_INTERVAL_MS = 250
EqDelivery.MAX_PLAYER_DISTANCE = 40

local Log = EqLog


--- @param trigger table AnimalLoadingTrigger
--- @return number|nil x, number|nil z
local function triggerPosition(trigger)
    local node = trigger.triggerNode
    if type(node) ~= "number" or node == 0 then return nil end
    local ok, x, _, z = pcall(getWorldTranslation, node)
    if ok then return x, z end
    return nil
end


--- @return number|nil x, number|nil z the local player's position
local function playerPosition()
    if g_localPlayer == nil or g_localPlayer.getPosition == nil then return nil end
    local ok, x, _, z = pcall(g_localPlayer.getPosition, g_localPlayer)
    if ok then return x, z end
    return nil
end


--- Horses in a livestock trailer that are waiting for delivery.
--- @param trailer table vehicle
--- @return table horses RLRM Animals
function EqDelivery.awaitingIn(trailer)
    local horses = {}
    if trailer == nil or trailer.spec_livestockTrailer == nil or trailer.getClusters == nil then return horses end
    for _, animal in pairs(trailer:getClusters() or {}) do
        if animal.isHorse ~= nil and animal:isHorse() and EqCompetitionManager.awaitingDelivery(animal) then
            table.insert(horses, animal)
        end
    end
    return horses
end


--- The farm's trailer standing in a dealer's loading area near the player, and the horses in it
--- waiting for delivery.
--- @param farmId number
--- @return table|nil trailer
--- @return table horses
function EqDelivery.find(farmId)
    local px, pz = playerPosition()
    if px == nil then return nil, {} end

    for trigger in pairs(EqProbe.triggers) do
        local trailer = trigger.isDealer == true and trigger.loadingVehicle or nil
        if trailer ~= nil and trailer.getOwnerFarmId ~= nil and trailer:getOwnerFarmId() == farmId then
            local x, z = triggerPosition(trigger)
            if x ~= nil and math.sqrt((x - px) ^ 2 + (z - pz) ^ 2) <= EqDelivery.MAX_PLAYER_DISTANCE then
                local horses = EqDelivery.awaitingIn(trailer)
                if #horses > 0 then return trailer, horses end
            end
        end
    end
    return nil, {}
end


--- The pasture with the most room for these horses, butchers left out.
--- @param farmId number
--- @param horses table RLRM Animals, at least one
--- @return table|nil destination RLRM destination entry ({placeable, name, freeSlots, ...})
function EqDelivery.destinationFor(farmId, horses)
    local service = EqRLRM.get("RLAnimalMoveService")
    local best = nil
    for _, destination in ipairs(service.getValidDestinations(nil, farmId, horses[1].subTypeIndex) or {}) do
        if not destination.isEPP and (destination.freeSlots or 0) > 0
            and (best == nil or destination.freeSlots > best.freeSlots) then
            best = destination
        end
    end
    return best
end


--- @param horses table
--- @return string text for the action prompt
local function promptText(horses)
    if #horses == 1 then
        local name = horses[1].getName ~= nil and horses[1]:getName() or ""
        if name ~= "" then return string.format(g_i18n:getText("eq_deliver_prompt"), name) end
    end
    return string.format(g_i18n:getText("eq_deliver_promptMany"), #horses)
end


--- @param kind number FSBaseMission.INGAME_NOTIFICATION_*
--- @param text string
local function notify(kind, text)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(kind, text)
    end
end


--- The action: move the horses home and mark them delivered.
function EqDelivery.onAction()
    if EqDelivery.pending or EqDelivery.trailer == nil or #EqDelivery.horses == 0 then return end
    local trailer, horses = EqDelivery.trailer, EqDelivery.horses
    local farmId = g_currentMission:getFarmId()

    local destination = EqDelivery.destinationFor(farmId, horses)
    if destination == nil then
        notify(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("eq_deliver_noRoom"))
        return
    end

    local service = EqRLRM.get("RLAnimalMoveService")
    local pasture = destination.placeable
    EqDelivery.pending = true
    local ok, accepted = pcall(service.moveAnimals, trailer, pasture, horses, "TARGET", function(errorCode)
        EqDelivery.pending = false
        if errorCode ~= nil and errorCode ~= AnimalMoveEvent.MOVE_SUCCESS then
            notify(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                string.format(g_i18n:getText("eq_deliver_failed"), service.getErrorText(errorCode)))
            return
        end
        EqDelivery.guarded("delivery", function() EqDelivery.complete(trailer, horses, pasture) end)
    end)
    if not ok then
        EqDelivery.pending = false
        error(accepted, 0)
    end
    if not accepted then EqDelivery.pending = false end
    Log:info("EqDelivery: %d horse(s) from '%s' to '%s' (accepted=%s)", #horses,
        tostring(trailer.getName ~= nil and trailer:getName()), tostring(destination.name), tostring(accepted))
end


--- Mark the horses that left the trailer delivered and hide them in their pasture.
--- @param trailer table vehicle the horses came from
--- @param horses table RLRM Animals that were in the trailer
--- @param pasture table placeable they were moved to
function EqDelivery.complete(trailer, horses, pasture)
    -- A pasture can run out of room part way; only the horses that left the trailer go.
    local still = {}
    for _, animal in pairs(trailer.getClusters ~= nil and trailer:getClusters() or {}) do still[animal] = true end

    local delivered = {}
    for _, animal in ipairs(horses) do
        if not still[animal] and EqCompetitionManager.deliver(animal) > 0 then table.insert(delivered, animal) end
    end
    if pasture ~= nil and pasture.updateVisualAnimals ~= nil then pasture:updateVisualAnimals() end

    if #delivered == 1 then
        local name = delivered[1].getName ~= nil and delivered[1]:getName() or ""
        notify(FSBaseMission.INGAME_NOTIFICATION_OK, string.format(g_i18n:getText("eq_deliver_done"), name))
    elseif #delivered > 1 then
        notify(FSBaseMission.INGAME_NOTIFICATION_OK, string.format(g_i18n:getText("eq_deliver_doneMany"), #delivered))
    end
    Log:info("EqDelivery: %d of %d horse(s) delivered", #delivered, #horses)
end


--- Show or hide the action. Runs every frame from the mission; checks a few times a second.
--- @param dt number ms
function EqDelivery.check(dt)
    EqDelivery.timer = EqDelivery.timer - dt
    if EqDelivery.timer > 0 then return end
    EqDelivery.timer = EqDelivery.CHECK_INTERVAL_MS

    local trailer, horses = nil, {}
    local mission = g_currentMission
    if mission ~= nil and mission:getIsServer() and not EqDelivery.pending then
        trailer, horses = EqDelivery.find(mission:getFarmId())
    end
    EqDelivery.trailer, EqDelivery.horses = trailer, horses

    local id = EqDelivery.actionEventId
    if id == nil then return end
    local active = trailer ~= nil
    g_inputBinding:setActionEventActive(id, active)
    g_inputBinding:setActionEventTextVisibility(id, active)
    if active then g_inputBinding:setActionEventText(id, promptText(horses)) end
end


--- Register the action in every player context (on foot and in a vehicle), as RLRM does for
--- its menu key. It starts hidden; update switches it on at the dealer.
local function registerAction()
    local ok, id = g_inputBinding:registerActionEvent(InputAction.EQ_DELIVER, EqDelivery, function()
        EqDelivery.guarded("delivery action", EqDelivery.onAction)
    end, false, true, false, false, nil, true)
    if not ok or id == nil or id == "" then return end
    EqDelivery.actionEventId = id
    g_inputBinding:setActionEventTextPriority(id, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventTextVisibility(id, false)
    EqDelivery.timer = 0
end


--- @param guarded function main.lua's error guard
function EqDelivery.install(guarded)
    if InputAction.EQ_DELIVER == nil then
        Log:warning("EqDelivery: input action EQ_DELIVER missing from modDesc; no delivery at the dealer")
        return
    end
    EqDelivery.guarded = guarded
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents, function()
            guarded("delivery action registration", registerAction)
        end)
    Log:debug("EqDelivery: hooked PlayerInputComponent.registerGlobalPlayerActionEvents")
end


--- Start checking for trailers at the dealer. Call once the mission has loaded.
--- @param mission table
function EqDelivery.start(mission)
    if EqDelivery.guarded == nil then return end
    EqDelivery.pending = false
    mission:addUpdateable(EqDelivery)
end


--- The mission's updateable hook.
--- @param dt number ms
function EqDelivery:update(dt)
    EqDelivery.guarded("delivery check", function() EqDelivery.check(dt) end)
end


--- @param mission table
function EqDelivery.stop(mission)
    if EqDelivery.guarded == nil then return end
    mission:removeUpdateable(EqDelivery)
    EqDelivery.actionEventId = nil
    EqDelivery.trailer, EqDelivery.horses = nil, {}
end

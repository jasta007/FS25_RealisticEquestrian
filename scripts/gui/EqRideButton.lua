--[[
    EqRideButton.lua
    A Ride horse button on RLRM's Info tab, so a horse can be picked from the list and ridden
    without hunting for it across a big pasture.

    It does what walking up to the horse and pressing the ride key does: the pen's own
    startRiding takes the horse out of its pen as a rideable where it stands, and the base game
    puts the player on it however far away they are. A horse with no visual in the pen right
    now (RLRM can draw only some of a big herd) has no spot to stand on, so the host lends it
    one: the pen's delivery area, where bought animals are dropped, else the pen itself.
]]

EqRideButton = {}

local Log = EqLog


--- @param animal table|nil the Info tab's selected animal (an RLRM Animal)
--- @return boolean rideable a horse the base game lets a player ride
function EqRideButton.isRideable(animal)
    return type(animal) == "table" and animal.getRidableFilename ~= nil and animal:getRidableFilename() ~= nil
end


--- Put Ride horse right after Back: RLRM's bar has 9 slots and a horse already fills 8, so a
--- button at the end could be cut off by any later one.
--- @param buttons table the frame's menuButtonInfo
--- @param info table our button
--- @param disabled boolean
function EqRideButton.addTo(buttons, info, disabled)
    info.disabled = disabled
    table.insert(buttons, math.min(2, #buttons + 1), info)
end


--- Add Ride horse to the Info tab's buttons while a horse is selected.
--- @param frame table RLMenuInfoFrame
function EqRideButton.updateButtons(frame)
    if type(frame.menuButtonInfo) ~= "table" or frame.getSelectedAnimal == nil then return end
    local animal = frame:getSelectedAnimal()
    if not EqRideButton.isRideable(animal) or frame.selectedHusbandry == nil then return end

    frame.eqRideButtonInfo = frame.eqRideButtonInfo or {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("eq_ui_button_rideHorse"),
        callback = function() EqRideButton.guarded("ride horse", function() EqRideButton.ride(frame) end) end,
    }
    -- A horse away at an event has no body in the pen to ride.
    EqRideButton.addTo(frame.menuButtonInfo, frame.eqRideButtonInfo, EqAway.isAway(animal))
    frame:setMenuButtonInfoDirty()
end


--- A spot for a horse that has no visual: the middle of the pen's delivery area, else the pen.
--- @param placeable table the horse's pen
--- @return number|nil x
--- @return number|nil y
--- @return number|nil z
function EqRideButton.spareSpot(placeable)
    local spec = placeable.spec_husbandryAnimals
    local area = spec ~= nil and spec.deliveryAreas ~= nil and spec.deliveryAreas[1] or nil
    local x, z
    if area ~= nil then
        local sx, _, sz = getWorldTranslation(area.start)
        local wx, _, wz = getWorldTranslation(area.width)
        local hx, _, hz = getWorldTranslation(area.height)
        x = sx + (wx - sx) / 2 + (hx - sx) / 2
        z = sz + (wz - sz) / 2 + (hz - sz) / 2
    elseif placeable.rootNode ~= nil then
        x, _, z = getWorldTranslation(placeable.rootNode)
    end
    if x == nil then return nil end
    local y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    return x, y, z
end


--- Close the menu and put the player on the Info tab's selected horse.
--- @param frame table RLMenuInfoFrame
function EqRideButton.ride(frame)
    local animal = frame.getSelectedAnimal ~= nil and frame:getSelectedAnimal() or nil
    local placeable = frame.selectedHusbandry
    local player = g_localPlayer
    if not EqRideButton.isRideable(animal) or placeable == nil or placeable.startRiding == nil or player == nil then return end
    if EqAway.isAway(animal) then return end

    local mission = g_currentMission
    if placeable.getAnimalCanBeRidden ~= nil and not placeable:getAnimalCanBeRidden(animal.id) then
        mission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("shop_messageAnimalRideableLimitReached"))
        return
    end

    local key = animal.farmId .. " " .. animal.uniqueId
    local spec = placeable.spec_husbandryAnimals
    local herd = spec ~= nil and spec.clusterHusbandry or nil
    local hasSpot = herd ~= nil and herd:getAnimalPosition(key) ~= nil
    if not hasSpot and not placeable.isServer then
        -- A client cannot lend the host a spot; walking up to a drawn horse still works.
        mission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("eq_ui_rideNotInPen"), animal.getName ~= nil and animal:getName() or ""))
        return
    end

    local menu = EqEventsFrame.menu
    if menu ~= nil and menu.exitMenu ~= nil then
        menu:exitMenu()
    else
        g_gui:showGui("")
    end

    if hasSpot then
        placeable:startRiding(key, player)
        Log:info("Ride horse: %s from the menu", tostring(key))
        return
    end

    -- On the host startRiding reads the horse's spot straight away, so the pen's herd answers
    -- with the spare spot for this one call and is put back right after.
    local x, y, z = EqRideButton.spareSpot(placeable)
    if x == nil then
        Log:warning("Ride horse: no spot in the pen for %s", tostring(key))
        return
    end
    local getAnimalPosition = herd.getAnimalPosition
    herd.getAnimalPosition = function(self, id, ...)
        if id == key then return x, y, z, 0, 0, 0 end
        return getAnimalPosition(self, id, ...)
    end
    local ok, err = pcall(placeable.startRiding, placeable, key, player)
    herd.getAnimalPosition = nil
    if not ok then error(err) end
    Log:info("Ride horse: %s from the menu, at the pen's spare spot (no visual)", tostring(key))
end


--- Hook RLRM's Info tab. Call once, after EqRLRM.init succeeded.
--- @param guarded function main.lua's error guard
function EqRideButton.install(guarded)
    EqRideButton.guarded = guarded
    local frameClass = EqRLRM.get("RLMenuInfoFrame")
    frameClass.updateButtonVisibility = Utils.appendedFunction(frameClass.updateButtonVisibility, function(frame)
        guarded("ride button", function() EqRideButton.updateButtons(frame) end)
    end)
    Log:debug("EqRideButton: hooked RLRM's Info tab")
end

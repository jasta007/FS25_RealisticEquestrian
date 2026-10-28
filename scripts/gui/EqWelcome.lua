--[[
    EqWelcome.lua
    Welcome popups: a short tour of the mod, in the same bottom-of-screen popups as the training
    help (EqTrainingHud), each shown once.

        welcome   the first time the player comes near a horse pen, or first rides a horse:
                  what the mod adds and how to open RLRM's menu
        menu      the first time RLRM's menu opens with horses on the farm: which tabs to look at
        info      the first time its Information tab shows with horses on the farm: skills,
                  potential, roles, staff and feed
        events    the first time the Events tab opens: disciplines, transport, injuries
        diseases  the first time RLRM's Diseases dialog opens for a horse: treatment, retiring

    The menu popups are drawn after RLMenu draws, so they sit on top of it, and the diseases
    popup after DiseaseDialog draws. Which have been
    seen is kept with the training help's, and the Help popups setting clears them all.
]]

EqWelcome = {}

local Log = EqLog

EqWelcome.PEN_DISTANCE = 35          -- metres from a horse pen's origin
EqWelcome.CHECK_INTERVAL_MS = 500
EqWelcome.HORSES_INTERVAL_MS = 2000  -- how long "the farm has horses" is trusted

-- Each series' pages; page p's texts are eq_welcome_<p>_title and eq_welcome_<p>.
EqWelcome.SERIES = {
    welcome = { "welcome_1" },
    menu = { "menu_1" },
    info = { "info_skills", "info_potential", "info_roles", "info_feed" },
    events = { "events_disciplines", "events_transport", "events_risks" },
    diseases = { "diseases_treatment" },
}

EqWelcome.checkedAt = nil
EqWelcome.horsesAt = nil
EqWelcome.horses = false


--- @param series string an EqWelcome.SERIES name
--- @return string the seen-flag name it is remembered under
function EqWelcome.seenKey(series)
    return "welcome_" .. series
end


--- @param series string
--- @return table pages for EqTrainingHud.showHelp
function EqWelcome.pages(series)
    local pages = {}
    for _, page in ipairs(EqWelcome.SERIES[series] or {}) do
        table.insert(pages, { title = g_i18n:getText("eq_welcome_" .. page .. "_title"),
            text = g_i18n:getText("eq_welcome_" .. page) })
    end
    return pages
end


--- Pop a series up; it counts as seen once its last page is clicked away.
--- @param series string
--- @param place string|nil "menu" or "dialog", nil in the world (see EqTrainingHud.showHelp)
function EqWelcome.show(series, place)
    EqTrainingHud.showHelp(EqWelcome.pages(series), place, EqWelcome.seenKey(series))
    Log:info("EqWelcome: showing the '%s' popups", series)
end


--- @param series string
--- @return boolean true once a series has been shown
function EqWelcome.hasSeen(series)
    return EqTrainingHud.hasSeen(EqWelcome.seenKey(series))
end


--- Which menu series to show now, if any. Pure, for the tests.
--- @param state table { hasHorses, infoOpen, eventsOpen, seen = function(series) }
--- @return string|nil series
function EqWelcome.menuSeries(state)
    if state.hasHorses and not state.seen("menu") then return "menu" end
    if state.infoOpen and state.hasHorses and not state.seen("info") then return "info" end
    if state.eventsOpen and not state.seen("events") then return "events" end
    return nil
end


--- @param placeable table
--- @return boolean true for a pen that keeps horses
function EqWelcome.isHorsePen(placeable)
    local spec = placeable ~= nil and placeable.spec_husbandryAnimals or nil
    return spec ~= nil and AnimalType ~= nil and spec.animalTypeIndex == AnimalType.HORSE
end


--- Whether any horse pen's origin is within distance of a point. Pure apart from the position
--- lookup, which is passed in.
--- @param placeables table list of placeables
--- @param x number
--- @param z number
--- @param distance number
--- @param positionOf function placeable -> x, z (or nil)
--- @return boolean
function EqWelcome.nearHorsePen(placeables, x, z, distance, positionOf)
    for _, placeable in ipairs(placeables or {}) do
        if EqWelcome.isHorsePen(placeable) then
            local px, pz = positionOf(placeable)
            if px ~= nil and (px - x) ^ 2 + (pz - z) ^ 2 <= distance ^ 2 then return true end
        end
    end
    return false
end


--- @param node number
--- @return number|nil x, number|nil z
local function nodePosition(node)
    if type(node) ~= "number" or node == 0 then return nil end
    local ok, x, _, z = EqLog.try("EqWelcome.nodePosition getWorldTranslation", getWorldTranslation, node)
    if ok then return x, z end
    return nil
end


--- The local player's position, or their vehicle's while they sit in one.
--- @return number|nil x, number|nil z
local function playerPosition()
    if g_localPlayer == nil then return nil end
    local vehicle = g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() or nil
    if type(vehicle) == "table" then return nodePosition(vehicle.rootNode) end
    if g_localPlayer.getPosition == nil then return nil end
    local ok, x, _, z = EqLog.try("EqWelcome.playerPosition getPosition", g_localPlayer.getPosition, g_localPlayer)
    if ok then return x, z end
    return nil
end


--- @return boolean true when the local farm has a horse (checked every few seconds)
local function farmHasHorses()
    local now = g_time or 0
    if EqWelcome.horsesAt == nil or now - EqWelcome.horsesAt > EqWelcome.HORSES_INTERVAL_MS then
        EqWelcome.horsesAt = now
        local farmId = g_currentMission ~= nil and g_currentMission:getFarmId() or nil
        EqWelcome.horses = farmId ~= nil and #EqRLRM.listHorsesForFarm(farmId) > 0
    end
    return EqWelcome.horses
end


--- Appended to the mission's draw: the welcome near a horse pen, and any popup showing out in
--- the world (the riding draw shows the same popup; it only draws once a frame).
function EqWelcome.onMissionDraw()
    if not EqMain.isActive or (g_gui ~= nil and g_gui:getIsGuiVisible()) then return end
    if not EqTrainingHud.isHelpShowing() and not EqWelcome.hasSeen("welcome") then
        local now = g_time or 0
        if EqWelcome.checkedAt == nil or now - EqWelcome.checkedAt >= EqWelcome.CHECK_INTERVAL_MS then
            EqWelcome.checkedAt = now
            local x, z = playerPosition()
            local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
            if x ~= nil and system ~= nil and EqWelcome.nearHorsePen(system.placeables, x, z,
                EqWelcome.PEN_DISTANCE, function(placeable) return nodePosition(placeable.rootNode) end) then
                EqWelcome.show("welcome")
            end
        end
    end
    EqTrainingHud.drawHelp(false)
end


--- The welcome when a horse is first ridden, before the training help. Called from the riding
--- draw.
--- @return boolean true when it showed
function EqWelcome.onRide()
    if EqWelcome.hasSeen("welcome") then return false end
    -- In the saddle the welcome is titled for what comes next (James).
    local pages = EqWelcome.pages("welcome")
    pages[1].title = g_i18n:getText("eq_welcome_ride_title")
    EqTrainingHud.showHelp(pages, nil, EqWelcome.seenKey("welcome"))
    Log:info("EqWelcome: showing the 'welcome' popups on a first ride")
    return true
end


--- @param menu table RLMenu
--- @param frame table|nil one of its pages
--- @return boolean true while that page is the one showing
local function isPageOpen(menu, frame)
    if frame == nil then return false end
    if menu.currentPage ~= nil then return menu.currentPage == frame end
    return frame.getIsVisible ~= nil and frame:getIsVisible()
end


--- Appended to RLMenu:draw: the menu's welcome popups, drawn over it.
--- @param menu table RLMenu
function EqWelcome.onMenuDraw(menu)
    if not EqMain.isActive then return end
    local fullMenu = menu.openMode == nil or menu.openMode == "full"
    if fullMenu and not (EqTrainingHud.isHelpShowing() and EqTrainingHud.place ~= nil) then
        local series = EqWelcome.menuSeries({
            hasHorses = farmHasHorses(),
            infoOpen = isPageOpen(menu, menu.infoFrame),
            eventsOpen = isPageOpen(menu, menu.eqEventsFrame),
            seen = EqWelcome.hasSeen,
        })
        if series ~= nil then EqWelcome.show(series, "menu") end
    end
    EqTrainingHud.drawHelp("menu")
end


--- Appended to RLRM's DiseaseDialog:draw: the treatment popup, the first time it shows a horse.
--- @param dialog table DiseaseDialog
function EqWelcome.onDiseaseDialogDraw(dialog)
    if not EqMain.isActive then return end
    local animal = dialog.animal
    local isHorse = animal ~= nil and animal.isHorse ~= nil and animal:isHorse()
    if isHorse and not EqWelcome.hasSeen("diseases")
        and not (EqTrainingHud.isHelpShowing() and EqTrainingHud.place == "dialog") then
        EqWelcome.show("diseases", "dialog")
    end
    EqTrainingHud.drawHelp("dialog")
end


--- Hook the mission's and RLRM menu's draws. Call from EqMain.activate.
--- @param guarded function main.lua's error guard
function EqWelcome.install(guarded)
    local missionClass = FSBaseMission ~= nil and FSBaseMission.draw ~= nil and FSBaseMission or BaseMission
    if missionClass ~= nil and missionClass.draw ~= nil then
        missionClass.draw = Utils.appendedFunction(missionClass.draw, function()
            guarded("welcome popups", EqWelcome.onMissionDraw)
        end)
    else
        Log:warning("EqWelcome: the mission has no draw; the welcome near horse pens is off")
    end
    local rlMenu = EqRLRM.get("RLMenu")
    if rlMenu ~= nil and rlMenu.draw ~= nil then
        rlMenu.draw = Utils.appendedFunction(rlMenu.draw, function(menu)
            guarded("menu welcome popups", function() EqWelcome.onMenuDraw(menu) end)
        end)
    else
        Log:warning("EqWelcome: RLRM's menu has no draw; the menu's welcome popups are off")
    end
    local dialog = EqRLRM.get("DiseaseDialog")
    if dialog ~= nil and dialog.draw ~= nil then
        dialog.draw = Utils.appendedFunction(dialog.draw, function(self)
            guarded("diseases welcome popup", function() EqWelcome.onDiseaseDialogDraw(self) end)
        end)
    end
    if dialog ~= nil and dialog.onClose ~= nil then
        -- Its popup goes with it; unread, it shows again next time.
        dialog.onClose = Utils.appendedFunction(dialog.onClose, function()
            if EqTrainingHud.place == "dialog" then EqTrainingHud.closeHelp() end
        end)
    end
end


function EqWelcome.reset()
    EqWelcome.checkedAt = nil
    EqWelcome.horsesAt = nil
    EqWelcome.horses = false
end

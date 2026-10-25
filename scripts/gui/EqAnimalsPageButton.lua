--[[
    EqAnimalsPageButton.lua
    Works around an RLRM gap: on the Esc menu's Animals page, RLRM adds a "Manage Animals"
    button (R) that opens its own menu on the selected pen. It shows for cows, sheep and pigs
    but not when a horse stable is selected, so the player has to reach the horses with
    Shift+O instead.

    RLRM only adds the button when the page has a selectedHusbandry, which the base game does
    not seem to set for horse stables. So if the button is missing we look for the pen another
    way (the selected horse's own pen, then the pen named in the page's selector) and add the
    same button for it.

    The base-game source for this page is not public, so the button is checked both when the
    page rebuilds its buttons and when the menu reads them, in case the base game sets a horse
    stable's buttons somewhere else.
]]

EqAnimalsPageButton = {}

local Log = EqLog

-- Frame fields the page might keep its pen list in, tried in order. Unverified guesses.
EqAnimalsPageButton.HUSBANDRY_LIST_FIELDS = { "husbandries", "sortedHusbandries", "husbandryList" }


--- @param husbandry any
--- @return boolean isPen true for an animal pen placeable
local function isAnimalPen(husbandry)
    return type(husbandry) == "table" and husbandry.spec_husbandryAnimals ~= nil
end


--- @param husbandry table
--- @return string name
local function penName(husbandry)
    return husbandry.getName ~= nil and tostring(husbandry:getName()) or "?"
end


--- @param frame table the Animals page
--- @return table|nil animal the animal under the list cursor, read the way RLRM reads it
local function getSelectedAnimal(frame)
    local list = frame.list
    if type(list) ~= "table" or type(frame.husbandrySubTypes) ~= "table"
        or type(frame.subTypeIndexToClusters) ~= "table" then
        return nil
    end
    local subType = frame.husbandrySubTypes[list.selectedSectionIndex]
    local animals = subType ~= nil and frame.subTypeIndexToClusters[subType] or nil
    return type(animals) == "table" and animals[list.selectedIndex] or nil
end


--- @param selector table|nil the page's pen selector
--- @return string|nil text the selector's current text
local function getSelectorText(selector)
    if type(selector) ~= "table" or selector.getState == nil then return nil end
    local state = selector:getState()
    if type(selector.texts) == "table" and state ~= nil then
        return selector.texts[state]
    end
    return nil
end


--- The player's farm's pens, through RLRM's own lookup.
--- @return table pens
function EqAnimalsPageButton.listFarmPens()
    local query = EqRLRM.get("RLAnimalQuery")
    local mission = g_currentMission
    if query == nil or mission == nil or mission.getFarmId == nil then return {} end
    return query.listHusbandriesForFarm(mission:getFarmId()) or {}
end


--- Find the pen the Animals page is showing.
--- @param frame table the Animals page
--- @param listPens function|nil returns the farm's pens; defaults to listFarmPens
--- @return table|nil husbandry the pen placeable
--- @return string source which lookup found it, for the log
function EqAnimalsPageButton.findHusbandry(frame, listPens)
    if isAnimalPen(frame.selectedHusbandry) then
        return frame.selectedHusbandry, "selectedHusbandry"
    end

    local animal = getSelectedAnimal(frame)
    local clusterSystem = type(animal) == "table" and animal.clusterSystem or nil
    if type(clusterSystem) == "table" and isAnimalPen(clusterSystem.owner) then
        return clusterSystem.owner, "selected animal"
    end

    local selector = frame.subCategorySelector
    local state = type(selector) == "table" and selector.getState ~= nil and selector:getState() or nil
    if state ~= nil then
        for _, field in ipairs(EqAnimalsPageButton.HUSBANDRY_LIST_FIELDS) do
            local list = frame[field]
            if type(list) == "table" and isAnimalPen(list[state]) then
                return list[state], field
            end
        end
    end

    -- Last resort: the selector shows the pen's name, so match it against the farm's pens.
    local text = getSelectorText(selector)
    if text ~= nil then
        for _, pen in ipairs((listPens or EqAnimalsPageButton.listFarmPens)()) do
            if isAnimalPen(pen) and penName(pen) == text then
                return pen, "selector name"
            end
        end
    end

    return nil, "none"
end


--- @param buttons table|nil the page's menuButtonInfo
--- @param action any the input action to look for
--- @return boolean present
function EqAnimalsPageButton.hasButton(buttons, action)
    if type(buttons) ~= "table" then return false end
    for _, info in ipairs(buttons) do
        if type(info) == "table" and info.inputAction == action then return true end
    end
    return false
end


--- @param frame table
--- @return string names the frame's table fields, sorted
local function describeFields(frame)
    local names = {}
    for key, value in pairs(frame) do
        if type(key) == "string" and type(value) == "table" then table.insert(names, key) end
    end
    table.sort(names)
    return table.concat(names, ", ")
end


--- @param buttons table
--- @return string list the buttons' texts in order, for the log
local function describeButtons(buttons)
    local texts = {}
    for _, info in ipairs(buttons) do
        table.insert(texts, tostring(type(info) == "table" and (info.text or info.inputAction) or info))
    end
    return string.format("%d [%s]", #buttons, table.concat(texts, ", "))
end


-- The last outcome logged, so the log gets one line per change rather than one per call.
local lastOutcome = nil
local reportedFields = false

--- @param outcome string
--- @param frame table
local function report(outcome, frame)
    if outcome == lastOutcome then return end
    lastOutcome = outcome
    Log:info("EqAnimalsPageButton: %s", outcome)
    if outcome:find("no pen found", 1, true) and not reportedFields then
        reportedFields = true
        Log:info("EqAnimalsPageButton: page fields: %s", describeFields(frame))
    end
end


--- Add RLRM's Manage Animals button to a button list when RLRM left it out.
--- @param frame table the Animals page
--- @param buttons table|nil the button list to fill (the page's menuButtonInfo)
--- @param action any InputAction.RL_OPEN_ANIMAL_SCREEN
--- @param openMenu function RLRM's RLMenu.openFromBridge
--- @param listPens function|nil passed to findHusbandry
--- @return boolean added
function EqAnimalsPageButton.ensureButton(frame, buttons, action, openMenu, listPens)
    if type(buttons) ~= "table" or EqAnimalsPageButton.hasButton(buttons, action) then
        return false
    end

    local husbandry, source = EqAnimalsPageButton.findHusbandry(frame, listPens)
    if husbandry == nil then
        report(string.format("no pen found for Manage Animals (selector text '%s', selectedHusbandry %s)",
            tostring(getSelectorText(frame.subCategorySelector)), tostring(frame.selectedHusbandry)), frame)
        return false
    end

    table.insert(buttons, {
        inputAction = action,
        text = g_i18n:getText("eq_ui_button_manageAnimals"),
        callback = function()
            -- Page 4 is RLRM's Manage tab, and fromInGameMenu makes Back return here, as RLRM's
            -- own button does.
            openMenu(4, EqRLRM.get("RLMenu").MODE_FULL, { husbandry = husbandry, fromInGameMenu = true })
        end
    })
    -- The menu only redraws the bar when the page says its buttons changed. The page opens
    -- with its list still empty, so the pen is often found only after the bar was drawn.
    if frame.setMenuButtonInfoDirty ~= nil then
        frame:setMenuButtonInfoDirty()
    end
    report(string.format("added Manage Animals for '%s' (found via %s); buttons now: %s",
        penName(husbandry), source, describeButtons(buttons)), frame)
    return true
end


--- Hook the Animals page's button list. Call once, after every mod has been sourced, so the
--- hooks run after RLRM's.
--- @param guarded function main.lua's error guard
function EqAnimalsPageButton.install(guarded)
    local action = InputAction ~= nil and InputAction.RL_OPEN_ANIMAL_SCREEN or nil
    if InGameMenuAnimalsFrame == nil or InGameMenuAnimalsFrame.updateMenuButtons == nil
        or InGameMenuAnimalsFrame.getMenuButtonInfo == nil or action == nil then
        Log:warning("EqAnimalsPageButton: Animals page or RLRM's R action not found; horse pens keep no Manage Animals button")
        return
    end

    local openMenu = EqRLRM.get("RLMenu").openFromBridge
    local function ensure(frame, buttons)
        guarded("animals page button", function()
            EqAnimalsPageButton.ensureButton(frame, buttons, action, openMenu)
        end)
    end

    InGameMenuAnimalsFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuAnimalsFrame.updateMenuButtons,
        function(frame) ensure(frame, frame.menuButtonInfo) end)

    -- The menu reads the buttons through getMenuButtonInfo, so this catches a list set anywhere.
    InGameMenuAnimalsFrame.getMenuButtonInfo = Utils.overwrittenFunction(InGameMenuAnimalsFrame.getMenuButtonInfo,
        function(frame, superFunc)
            local buttons = superFunc(frame)
            ensure(frame, buttons)
            return buttons
        end)

    Log:info("EqAnimalsPageButton: hooked the Animals page buttons")
end

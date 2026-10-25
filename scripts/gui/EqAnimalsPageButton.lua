--[[
    EqAnimalsPageButton.lua
    Works around an RLRM gap: on the Esc menu's Animals page, RLRM adds a "Manage Animals"
    button (R) that opens its own menu on the selected pen. It shows for cows, sheep and pigs
    but not when a horse stable is selected, so the player has to reach the horses with
    Shift+O instead.

    RLRM only adds the button when the page has a selectedHusbandry, which the base game does
    not seem to set for horse stables. So after RLRM has had its turn, if the button is still
    missing we look for the pen another way (the selected horse's own pen, then the pen picked
    in the page's selector) and add the same button for it.
]]

EqAnimalsPageButton = {}

local Log = EqLog

-- Frame fields the page might keep its pen list in, tried in order. Unverified guesses:
-- the base-game source for this page is not public.
EqAnimalsPageButton.HUSBANDRY_LIST_FIELDS = { "husbandries", "sortedHusbandries", "husbandryList" }


--- @param husbandry any
--- @return boolean isPen true for an animal pen placeable
local function isAnimalPen(husbandry)
    return type(husbandry) == "table" and husbandry.spec_husbandryAnimals ~= nil
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


--- Find the pen the Animals page is showing.
--- @param frame table the Animals page
--- @return table|nil husbandry the pen placeable
--- @return string source which lookup found it, for the log
function EqAnimalsPageButton.findHusbandry(frame)
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


-- Logged once per session when no pen is found, so a log shows which fields the page has.
local reportedMissing = false

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


--- Add RLRM's Manage Animals button when RLRM left it out; runs after RLRM's own hook.
--- @param frame table the Animals page
--- @param action any InputAction.RL_OPEN_ANIMAL_SCREEN
--- @param openMenu function RLRM's RLMenu.openFromBridge
--- @return boolean added
function EqAnimalsPageButton.afterUpdateMenuButtons(frame, action, openMenu)
    if type(frame.menuButtonInfo) ~= "table" or EqAnimalsPageButton.hasButton(frame.menuButtonInfo, action) then
        return false
    end

    local husbandry, source = EqAnimalsPageButton.findHusbandry(frame)
    if husbandry == nil then
        if not reportedMissing then
            reportedMissing = true
            Log:info("EqAnimalsPageButton: no pen found for the Manage Animals button; page fields: %s",
                describeFields(frame))
        end
        return false
    end

    table.insert(frame.menuButtonInfo, {
        inputAction = action,
        text = g_i18n:getText("eq_ui_button_manageAnimals"),
        callback = function()
            -- Page 4 is RLRM's Manage tab, and fromInGameMenu makes Back return here, as RLRM's
            -- own button does.
            openMenu(4, EqRLRM.get("RLMenu").MODE_FULL, { husbandry = husbandry, fromInGameMenu = true })
        end
    })
    Log:debug("EqAnimalsPageButton: added Manage Animals for %s (found via %s)",
        tostring(husbandry.getName ~= nil and husbandry:getName() or "?"), source)
    return true
end


--- Hook the Animals page's updateMenuButtons. Call once, after every mod has been sourced, so
--- the hook runs after RLRM's.
--- @param guarded function main.lua's error guard
function EqAnimalsPageButton.install(guarded)
    local action = InputAction ~= nil and InputAction.RL_OPEN_ANIMAL_SCREEN or nil
    if InGameMenuAnimalsFrame == nil or InGameMenuAnimalsFrame.updateMenuButtons == nil or action == nil then
        Log:warning("EqAnimalsPageButton: Animals page or RLRM's R action not found; horse pens keep no Manage Animals button")
        return
    end

    local rlMenu = EqRLRM.get("RLMenu")
    InGameMenuAnimalsFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuAnimalsFrame.updateMenuButtons,
        function(frame)
            guarded("animals page button", function()
                EqAnimalsPageButton.afterUpdateMenuButtons(frame, action, rlMenu.openFromBridge)
            end)
        end)
    Log:debug("EqAnimalsPageButton: hooked InGameMenuAnimalsFrame:updateMenuButtons")
end

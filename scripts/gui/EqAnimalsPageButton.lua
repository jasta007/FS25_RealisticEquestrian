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

    The button is checked at the last step, when the menu puts a list into its button bar,
    because the base game builds a horse stable's buttons in more than one place. The bar has
    a fixed number of slots and a horse stable fills them, so the button goes just after Back.
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


--- @param buttons table
--- @param action any
--- @return integer|nil index where the action's button sits
local function findButton(buttons, action)
    for i, info in ipairs(buttons) do
        if type(info) == "table" and info.inputAction == action then return i end
    end
    return nil
end


--- Add RLRM's Manage Animals button to a button list when RLRM left it out, and keep it inside
--- the bar's slots.
--- @param frame table the Animals page
--- @param buttons table|nil the button list to fill
--- @param action any InputAction.RL_OPEN_ANIMAL_SCREEN
--- @param openMenu function RLRM's RLMenu.openFromBridge
--- @param listPens function|nil passed to findHusbandry
--- @param slots integer|nil how many buttons the bar can show; nil when unknown
--- @return boolean changed true when the list was changed
function EqAnimalsPageButton.ensureButton(frame, buttons, action, openMenu, listPens, slots)
    if type(buttons) ~= "table" then return false end

    local index = findButton(buttons, action)
    local added = false
    local husbandry, source

    if index == nil then
        husbandry, source = EqAnimalsPageButton.findHusbandry(frame, listPens)
        if husbandry == nil then
            report(string.format("no pen found for Manage Animals (selector text '%s', selectedHusbandry %s)",
                tostring(getSelectorText(frame.subCategorySelector)), tostring(frame.selectedHusbandry)), frame)
            return false
        end
        table.insert(buttons, {
            inputAction = action,
            text = g_i18n:getText("eq_ui_button_manageAnimals"),
            callback = function()
                -- Page 4 is RLRM's Manage tab, and fromInGameMenu makes Back return here, as
                -- RLRM's own button does.
                openMenu(4, EqRLRM.get("RLMenu").MODE_FULL, { husbandry = husbandry, fromInGameMenu = true })
            end
        })
        index = #buttons
        added = true
    end

    -- The bar shows only its first few buttons, and a horse stable fills them (rename, map tag,
    -- workers and the page buttons). Move the button up to just after Back so it is one of them.
    local moved = false
    if slots ~= nil and index > slots and index > 2 then
        table.insert(buttons, 2, table.remove(buttons, index))
        moved = true
    end

    if not added and not moved then return false end

    -- The menu only redraws the bar when the page says its buttons changed, and the page opens
    -- with its list still empty, so the pen is often found only after the bar was drawn.
    if frame.setMenuButtonInfoDirty ~= nil then
        frame:setMenuButtonInfoDirty()
    end
    report(string.format("%s Manage Animals%s; bar slots %s, buttons now: %s",
        added and "added" or "moved", added and string.format(" for '%s' (found via %s)", penName(husbandry), source) or "",
        tostring(slots), describeButtons(buttons)), frame)
    return true
end


--- @param menu table the in-game menu
--- @return boolean isAnimalsPage true when its current page is the Animals page
local function showsAnimalsPage(menu)
    local page = menu.currentPage
    if type(page) ~= "table" then return false end
    local mt = getmetatable(page)
    return (mt ~= nil and mt.__index == InGameMenuAnimalsFrame) or (menu.pageAnimals ~= nil and menu.pageAnimals == page)
end


--- Hook the Animals page's button list. Call once, after every mod has been sourced, so the
--- hooks run after RLRM's.
--- @param guarded function main.lua's error guard
function EqAnimalsPageButton.install(guarded)
    local action = InputAction ~= nil and InputAction.RL_OPEN_ANIMAL_SCREEN or nil
    if InGameMenuAnimalsFrame == nil or InGameMenuAnimalsFrame.updateMenuButtons == nil
        or InGameMenu == nil or InGameMenu.assignMenuButtonInfo == nil or action == nil then
        Log:warning("EqAnimalsPageButton: Animals page or RLRM's R action not found; horse pens keep no Manage Animals button")
        return
    end

    local openMenu = EqRLRM.get("RLMenu").openFromBridge

    InGameMenuAnimalsFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuAnimalsFrame.updateMenuButtons,
        function(frame)
            guarded("animals page button", function()
                EqAnimalsPageButton.ensureButton(frame, frame.menuButtonInfo, action, openMenu)
            end)
        end)

    -- Every list the bar shows passes through here, whoever built it, and here the number of
    -- slots is known.
    InGameMenu.assignMenuButtonInfo = Utils.overwrittenFunction(InGameMenu.assignMenuButtonInfo,
        function(menu, superFunc, buttons, ...)
            guarded("animals page button", function()
                if showsAnimalsPage(menu) then
                    local slots = type(menu.menuButton) == "table" and #menu.menuButton or nil
                    EqAnimalsPageButton.ensureButton(menu.currentPage, buttons, action, openMenu, nil, slots)
                end
            end)
            return superFunc(menu, buttons, ...)
        end)

    Log:info("EqAnimalsPageButton: hooked the Animals page buttons")
end

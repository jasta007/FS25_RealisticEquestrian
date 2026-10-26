--[[
    EqRoleMenu.lua
    Horse roles (EqRole) in RLRM's Info tab: a Role button (G) on a selected horse cycles its
    role, and the horse list is grouped by role (Dressage, Show Jumping, ... then No role) once
    any horse in the pen has one. With no roles the list stays RLRM's colour groups.

    RLRM's button bar has 9 slots and a horse already fills 8 (9 with the Ride horse button), so
    the bar gets more slots, copies of its last button, when the buttons would not fit.

    The button is the host's only for now, like the Events tab's entries: roles are saved with
    the horse records, which only the server keeps. No RLRM file changes.
]]

EqRoleMenu = {}

local Log = EqLog


--- @param cluster table RLRM Animal
--- @return string|nil role nil for anything but a horse
function EqRoleMenu.roleOf(cluster)
    if cluster.isHorse == nil or not cluster:isHorse() then return nil end
    return EqRole.get(EqRegistry.getOrCreate(cluster))
end


--- @return boolean true where the role can be changed
local function canSetRole()
    return InputAction.EQ_HORSE_ROLE ~= nil and g_currentMission ~= nil and g_currentMission:getIsServer()
end


--- @param frame table RLMenuInfoFrame
--- @return table|nil animal the selected horse
local function selectedHorse(frame)
    local animal = frame.getSelectedAnimal ~= nil and frame:getSelectedAnimal() or nil
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return nil end
    return animal
end


--- Appended to RLMenuInfoFrame:updateButtonVisibility: the Role button for a selected horse.
--- @param frame table RLMenuInfoFrame
function EqRoleMenu.updateButtons(frame)
    if type(frame.menuButtonInfo) ~= "table" or not canSetRole() then return end
    local animal = selectedHorse(frame)
    local record = animal ~= nil and EqRegistry.getOrCreate(animal) or nil
    if record == nil then return end

    frame.eqRoleButtonInfo = frame.eqRoleButtonInfo or {
        inputAction = InputAction.EQ_HORSE_ROLE,
        callback = function() EqRoleMenu.cycle(frame) end,
    }
    frame.eqRoleButtonInfo.text = string.format(g_i18n:getText("eq_ui_button_role"), EqRole.text(EqRole.get(record)))
    table.insert(frame.menuButtonInfo, frame.eqRoleButtonInfo)
    -- One spare, for a button another hook adds after this one.
    EqRoleMenu.ensureSlots(EqEventsFrame.menu, #frame.menuButtonInfo + 1)
    frame:setMenuButtonInfoDirty()
end


--- Give RLRM's menu enough button slots: the menu fills its menuButton elements in order and
--- hides the rest, so a button past the last slot never shows.
--- @param menu table|nil RLRM's menu
--- @param count number buttons to show
function EqRoleMenu.ensureSlots(menu, count)
    local slots = menu ~= nil and menu.menuButton or nil
    if type(slots) ~= "table" or #slots == 0 or #slots >= count then return end
    local last = slots[#slots]
    local panel = last.parent
    if last.clone == nil or panel == nil then return end
    while #slots < count do
        table.insert(slots, last:clone(panel, false, true))
    end
    if panel.invalidateLayout ~= nil then panel:invalidateLayout() end
    Log:info("EqRoleMenu: RLRM's button bar now has %d slots", #slots)
end


--- Give the selected horse the next role, then regroup the list (the selection follows the horse).
--- @param frame table RLMenuInfoFrame
function EqRoleMenu.cycle(frame)
    if not canSetRole() then return end
    local animal = selectedHorse(frame)
    local record = animal ~= nil and EqRegistry.getOrCreate(animal) or nil
    if record == nil then return end

    record.focus = EqRole.next(EqRole.get(record))
    Log:info("EqRoleMenu: %s '%s' role %s", record.id, animal:getName() or "", record.focus)
    if frame.reloadAnimalList ~= nil then frame:reloadAnimalList() end
    if frame.updateAnimalDisplay ~= nil then frame:updateAnimalDisplay(animal) end
end


--- @param guarded function main.lua's error guard
function EqRoleMenu.install(guarded)
    local query = EqRLRM.get("RLAnimalQuery")
    local build = query.buildSections
    local failed = false
    query.buildSections = function(items, ...)
        local order, byKey, titles = build(items, ...)
        local ok, newOrder, newByKey, newTitles = pcall(EqRole.groupSections, items, order, byKey, titles, EqRoleMenu.roleOf)
        if ok then return newOrder, newByKey, newTitles end
        if not failed then
            failed = true
            Log:error("EqRoleMenu: grouping by role failed: %s", tostring(newOrder))
        end
        return order, byKey, titles
    end

    local frame = EqRLRM.get("RLMenuInfoFrame")
    frame.updateButtonVisibility = Utils.appendedFunction(frame.updateButtonVisibility, function(f)
        guarded("role button", function() EqRoleMenu.updateButtons(f) end)
    end)
    Log:debug("EqRoleMenu: hooked RLAnimalQuery.buildSections and RLMenuInfoFrame.updateButtonVisibility")
end

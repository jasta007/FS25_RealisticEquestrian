--[[
    EqMessagesLink.lua
    From a result line in RLRM's Messages tab to that horse on our Events tab's Results page.

    Our result lines carry the horse's id as a second, never shown argument (EqMessages.linkFor).
    RLRM's message service drops the arguments when it builds the tab's rows, so we keep the
    horse id on the row it returns. The Messages tab then gets a View results button while such
    a line is selected; it opens our tab on the Results page with that horse picked.
]]

EqMessagesLink = {}

local Log = EqLog


--- Appended to RLMessageService.formatMessage: keep the linked horse on the row.
--- @param row table|nil the row RLRM built
--- @param message table|nil the logged line
--- @return table|nil row
function EqMessagesLink.tagRow(row, message)
    if type(row) == "table" and type(message) == "table" then
        row.eqHorseId = EqMessages.linkedHorse(message.args)
    end
    return row
end


--- @param frame table RLMenuMessagesFrame
--- @return string|nil horseId the horse the selected line links to
function EqMessagesLink.selectedHorse(frame)
    local list = frame.messagesList
    local index = list ~= nil and list.selectedIndex or nil
    local row = index ~= nil and frame.rows ~= nil and frame.rows[index] or nil
    return row ~= nil and row.eqHorseId or nil
end


--- Add View results to the Messages tab's buttons while a linked line is selected.
--- @param frame table RLMenuMessagesFrame
function EqMessagesLink.updateButtons(frame)
    if type(frame.menuButtonInfo) ~= "table" then return end
    if EqMessagesLink.selectedHorse(frame) == nil or EqEventsFrame.instance == nil then return end
    frame.eqViewResultsButtonInfo = frame.eqViewResultsButtonInfo or {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("eq_ui_button_viewResults"),
        callback = function() EqMessagesLink.open(frame) end,
    }
    table.insert(frame.menuButtonInfo, frame.eqViewResultsButtonInfo)
    frame:setMenuButtonInfoDirty()
end


--- Switch the menu to our Events tab, on the Results page with the line's horse.
--- @param frame table RLMenuMessagesFrame
function EqMessagesLink.open(frame)
    local horseId = EqMessagesLink.selectedHorse(frame)
    local page, menu = EqEventsFrame.instance, EqEventsFrame.menu
    if horseId == nil or page == nil or menu == nil then return end

    page:showResultsFor(horseId)
    if menu.goToPage ~= nil then
        menu:goToPage(page)
        return
    end
    -- Older menus: pick the page through the page selector.
    local paging = menu.pagingElement
    local index = paging ~= nil and paging.getPageMappingIndexByElement ~= nil and paging:getPageMappingIndexByElement(page) or nil
    if index ~= nil and menu.pageSelector ~= nil then
        menu.pageSelector:setState(index, true)
    else
        Log:warning("EqMessagesLink: could not switch the menu to the Events tab")
    end
end


--- Hook RLRM's message service and Messages tab. Call once, after EqRLRM.init succeeded.
--- @param guarded function main.lua's error guard
function EqMessagesLink.install(guarded)
    local service = EqRLRM.get("RLMessageService")
    local formatMessage = service.formatMessage
    service.formatMessage = function(message, ...)
        local row = formatMessage(message, ...)
        guarded("message link row", function() EqMessagesLink.tagRow(row, message) end)
        return row
    end

    local frameClass = EqRLRM.get("RLMenuMessagesFrame")
    frameClass.updateButtonVisibility = Utils.appendedFunction(frameClass.updateButtonVisibility, function(frame)
        guarded("message link button", function() EqMessagesLink.updateButtons(frame) end)
    end)
    -- RLRM's tab has no selection handler; the list calls this one on its delegate (the frame).
    local onSelection = frameClass.onListSelectionChanged
    frameClass.onListSelectionChanged = function(frame, list, ...)
        if onSelection ~= nil then onSelection(frame, list, ...) end
        if list == frame.messagesList and frame.updateButtonVisibility ~= nil then frame:updateButtonVisibility() end
    end
    Log:debug("EqMessagesLink: hooked RLRM's Messages tab")
end

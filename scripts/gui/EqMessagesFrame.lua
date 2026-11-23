--[[
    EqMessagesFrame.lua
    The Messages tab of our own menu (EqMenu), for games without Realistic Livestock: the farm's
    lines from our own log (EqMessages.linesFor), newest first. A result line links to its horse:
    View results opens the Events tab's Results page on it, as RLRM's Messages tab does with
    EqMessagesLink. Clear empties the farm's log (it asks first).
]]

EqMessagesFrame = {}
local EqMessagesFrame_mt = Class(EqMessagesFrame, TabbedMenuFrameElement)

local Log = EqLog
local modDirectory = g_currentModDirectory

EqMessagesFrame.NAME = "EqMessagesFrame"
EqMessagesFrame.ICON_SLICE = "eqMenu.messages"
EqMessagesFrame.SEVERITY_COLOR = {
    SUCCESS = { 0.52, 1.00, 0.00, 1 },
    WARNING = { 1.00, 0.52, 0.00, 1 },
}


--- @return table self
function EqMessagesFrame.new()
    local self = EqMessagesFrame:superClass().new(nil, EqMessagesFrame_mt)
    self.name = EqMessagesFrame.NAME
    self.rows = {}
    self.selectedIndex = nil
    self.hasCustomMenuButtons = true
    self.backButtonInfo = { inputAction = InputAction.MENU_BACK }
    self.viewButtonInfo = {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("eq_ui_button_viewResults"),
        callback = function() self:onClickView() end,
    }
    self.clearButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = g_i18n:getText("eq_messages_button_clear"),
        callback = function() self:onClickClear() end,
    }
    self.menuButtonInfo = { self.backButtonInfo }
    return self
end


function EqMessagesFrame:onGuiSetupFinished()
    EqMessagesFrame:superClass().onGuiSetupFinished(self)
    if self.messageList ~= nil then
        self.messageList:setDataSource(self)
        self.messageList:setDelegate(self)
    end
end


function EqMessagesFrame:onFrameOpen()
    EqMessagesFrame:superClass().onFrameOpen(self)
    EqEventsFrame.applyHeaderIcon(self, EqMessagesFrame.ICON_SLICE)
    self:refresh()
    if self.messageList ~= nil then FocusManager:setFocus(self.messageList) end
end


function EqMessagesFrame:update(dt)
    EqMessagesFrame:superClass().update(self, dt)
    EqEventsFrame.applyHeaderIcon(self, EqMessagesFrame.ICON_SLICE)
end


--- @param line table an EqMessages line
--- @return string date such as "Day 3, March, Year 2"
function EqMessagesFrame.dateText(line)
    if line.period ~= nil and line.dayInPeriod ~= nil and g_i18n.formatPeriod ~= nil then
        local ok, month = pcall(g_i18n.formatPeriod, g_i18n, line.period, false)
        if ok and month ~= nil then
            return string.format(g_i18n:getText("eq_messages_date"), line.dayInPeriod, month, line.year or 1)
        end
    end
    return string.format(g_i18n:getText("eq_messages_day"), line.day or 0)
end


function EqMessagesFrame:refresh()
    self.rows = g_currentMission ~= nil and EqMessages.linesFor(g_currentMission:getFarmId()) or {}
    self.messageList:reloadData()
    local index = #self.rows > 0 and 1 or nil
    if index ~= nil then self.messageList:setSelectedIndex(index) end
    self:select(index)
    local empty = #self.rows == 0 and g_i18n:getText("eq_messages_none") or nil
    self.emptyState:setText(empty or "")
    self.emptyState:setVisible(empty ~= nil)
    self.summaryText:setText(g_i18n:getText("eq_messages_summary"))
end


--- @param index number|nil
function EqMessagesFrame:select(index)
    self.selectedIndex = index
    self.menuButtonInfo = { self.backButtonInfo }
    local row = index ~= nil and self.rows[index] or nil
    if row ~= nil and row.horseId ~= nil and EqEventsFrame.instance ~= nil then
        table.insert(self.menuButtonInfo, self.viewButtonInfo)
    end
    if #self.rows > 0 and g_currentMission ~= nil and g_currentMission:getIsServer() then
        table.insert(self.menuButtonInfo, self.clearButtonInfo)
    end
    self:setMenuButtonInfoDirty()
end


function EqMessagesFrame:getNumberOfItemsInSection(_list, _section)
    return #self.rows
end


function EqMessagesFrame:populateCellForItemInSection(_list, _section, index, cell)
    local line = self.rows[index]
    if line == nil then return end
    local kind = EqMessages.TYPES[line.id]
    local color = kind ~= nil and EqMessagesFrame.SEVERITY_COLOR[kind.severity] or nil
    local date, type, text = cell:getAttribute("date"), cell:getAttribute("type"), cell:getAttribute("text")
    if date ~= nil then date:setText(EqMessagesFrame.dateText(line)) end
    if type ~= nil then
        type:setText(EqMessages.titleOf(line.id))
        if color ~= nil then type:setTextColor(unpack(color)) end
    end
    if text ~= nil then text:setText(line.text or "") end
end


function EqMessagesFrame:onListSelectionChanged(_list, _section, index)
    if index ~= self.selectedIndex then self:select(index) end
end


function EqMessagesFrame:onClickView()
    local row = self.selectedIndex ~= nil and self.rows[self.selectedIndex] or nil
    local page, menu = EqEventsFrame.instance, EqEventsFrame.menu
    if row == nil or row.horseId == nil or page == nil or menu == nil then return end
    page:showResultsFor(row.horseId)
    menu:goToPage(page)
end


function EqMessagesFrame:onClickClear()
    local farm = g_currentMission:getFarmId()
    YesNoDialog.show(function(_, yes)
        if not yes then return end
        for i = #EqMessages.lines, 1, -1 do
            if EqMessages.lines[i].farmId == farm then table.remove(EqMessages.lines, i) end
        end
        self:refresh()
    end, self, g_i18n:getText("eq_messages_clearConfirm"), g_i18n:getText("eq_messages_button_clear"))
end


--- @param menu table our menu (EqMenu)
function EqMessagesFrame.addToMenu(menu)
    local frame = EqMessagesFrame.new()
    g_gui:loadGui(modDirectory .. "gui/eqMessagesFrame.xml", EqMessagesFrame.NAME, frame, true)
    EqMenu.addFrame(menu, frame, EqMessagesFrame.ICON_SLICE)
    EqMessagesFrame.instance = frame
    Log:info("EqMessagesFrame: Messages tab added")
end

--[[
    EqEventsFrame.lua
    The Events tab in RLRM's menu: open events on the left (or your results, toggled), your
    horses for the selected event on the right, and an Enter button for the selected horse.

    The tab is added from our side: EqEventsFrame.install appends to RLMenu:setupMenuPages, so
    once RLRM has registered its own pages we load our frame and register it as one more page,
    the way the base game's own TabbedMenu:addPage does. No RLRM file changes.

    Entering goes through EqCompetitionManager.enter, which runs on the server only, so for now
    the tab works for a single player or the host; a multiplayer client sees a note instead
    (client entries need a network event, milestone 7).
]]

EqEventsFrame = {}
local EqEventsFrame_mt = Class(EqEventsFrame, TabbedMenuFrameElement)

local Log = EqLog
local modDirectory = g_currentModDirectory

EqEventsFrame.NAME = "EqEventsFrame"
EqEventsFrame.ICON_SLICE = "eqMenu.events"

EqEventsFrame.MODE_EVENTS = "events"
EqEventsFrame.MODE_RESULTS = "results"


--- @return table self
function EqEventsFrame.new()
    local self = EqEventsFrame:superClass().new(nil, EqEventsFrame_mt)
    self.name = EqEventsFrame.NAME
    self.mode = EqEventsFrame.MODE_EVENTS
    self.eventRows = {}
    self.horseRows = {}
    self.resultRows = {}
    self.selectedEventId = nil
    self.selectedHorseIndex = nil
    self.hasCustomMenuButtons = true

    self.backButtonInfo = { inputAction = InputAction.MENU_BACK }
    self.enterButtonInfo = {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("eq_ui_button_enter"),
        callback = function() self:onClickEnter() end,
    }
    self.toggleButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = g_i18n:getText("eq_ui_button_results"),
        callback = function() self:onClickToggle() end,
    }
    self.menuButtonInfo = { self.backButtonInfo, self.toggleButtonInfo }
    return self
end


function EqEventsFrame:onGuiSetupFinished()
    EqEventsFrame:superClass().onGuiSetupFinished(self)
    for _, list in ipairs({ self.eventsList, self.horsesList, self.resultsList }) do
        if list ~= nil then
            list:setDataSource(self)
            list:setDelegate(self)
        end
    end
end


--- @return boolean ok
--- @return string|nil reason text for the player when the tab cannot work here
local function readiness()
    if g_currentMission == nil then return false, "" end
    if not g_currentMission:getIsServer() then return false, g_i18n:getText("eq_ui_clientNote") end
    if EqCompetitionManager.config == nil then return false, g_i18n:getText("eq_ui_noConfig") end
    return true
end


--- @return number farmId
local function farmId()
    return g_currentMission:getFarmId()
end


function EqEventsFrame:onFrameOpen()
    EqEventsFrame:superClass().onFrameOpen(self)
    self:refresh()
    if self.eventsList ~= nil and self.mode == EqEventsFrame.MODE_EVENTS then
        FocusManager:setFocus(self.eventsList)
    end
end


--- Rebuild every list from the manager, keeping the selected event where possible.
function EqEventsFrame:refresh()
    local ok, reason = readiness()
    self.isReady = ok
    if not ok then
        self.eventRows, self.horseRows, self.resultRows = {}, {}, {}
    else
        self.eventRows = EqEventsView.eventRows(farmId())
        self.resultRows = EqEventsView.resultRows(farmId())
    end

    local isEvents = self.mode == EqEventsFrame.MODE_EVENTS
    self.eventsHeader:setVisible(isEvents)
    self.eventsBox:setVisible(isEvents)
    self.horsesHeader:setVisible(isEvents)
    self.horsesBox:setVisible(isEvents)
    self.resultsHeader:setVisible(not isEvents)
    self.resultsBox:setVisible(not isEvents)

    self.eventsList:reloadData()
    self.resultsList:reloadData()

    local selectIndex = 1
    for i, row in ipairs(self.eventRows) do
        if row.event.id == self.selectedEventId then selectIndex = i end
    end
    if #self.eventRows > 0 then
        self.eventsList:setSelectedIndex(selectIndex)
    end
    self:selectEvent(self.eventRows[selectIndex])

    local empty
    if not ok then
        empty = reason
    elseif isEvents and #self.eventRows == 0 then
        empty = g_i18n:getText("eq_ui_noEvents")
    elseif not isEvents and #self.resultRows == 0 then
        empty = g_i18n:getText("eq_ui_noResults")
    end
    self.emptyState:setText(empty or "")
    self.emptyState:setVisible(empty ~= nil and empty ~= "")

    self:updateButtons()
end


--- @param row table|nil an event row
function EqEventsFrame:selectEvent(row)
    self.selectedEventId = row ~= nil and row.event.id or nil
    self.horseRows = (row ~= nil and self.isReady) and EqEventsView.horseRows(row.event, farmId()) or {}
    self.horsesList:reloadData()
    if #self.horseRows > 0 then
        self.horsesList:setSelectedIndex(1)
        self.selectedHorseIndex = 1
    else
        self.selectedHorseIndex = nil
    end

    local showHorses = self.mode == EqEventsFrame.MODE_EVENTS and row ~= nil
    local noHorses = showHorses and #self.horseRows == 0
    self.horsesEmptyState:setText(noHorses and g_i18n:getText("eq_ui_noHorses") or "")
    self.horsesEmptyState:setVisible(noHorses)

    self:updateSummary()
end


function EqEventsFrame:updateSummary()
    local text = ""
    if self.message ~= nil then
        text = self.message
    elseif self.mode == EqEventsFrame.MODE_EVENTS and self.selectedEventId ~= nil then
        local event = EqCompetitionManager.events[self.selectedEventId]
        local tier = event ~= nil and EqCompetitionManager.config.tierByName[event.tier] or nil
        if tier ~= nil then
            local ages = tier.maxAge > 0 and string.format(g_i18n:getText("eq_ui_ages_range"), tier.minAge, tier.maxAge)
                or string.format(g_i18n:getText("eq_ui_ages_from"), tier.minAge)
            text = string.format(g_i18n:getText("eq_ui_summary_event"), EqCompetitionManager.eventTitle(event), ages,
                tier.minRating, tier.maxRating, tier.field)
            local left = EqCompetitionManager.entriesLeft(farmId())
            if left ~= nil then
                text = text .. " " .. string.format(g_i18n:getText("eq_ui_entriesLeft"), left,
                    EqCompetitionManager.settings.entriesPerMonth)
            end
        end
    end
    self.summaryText:setText(text)
end


function EqEventsFrame:updateButtons()
    self.toggleButtonInfo.text = g_i18n:getText(self.mode == EqEventsFrame.MODE_EVENTS and "eq_ui_button_results" or "eq_ui_button_events")
    self.menuButtonInfo = { self.backButtonInfo, self.toggleButtonInfo }

    local horse = self.selectedHorseIndex ~= nil and self.horseRows[self.selectedHorseIndex] or nil
    if self.mode == EqEventsFrame.MODE_EVENTS and horse ~= nil and horse.canEnter then
        local event = EqCompetitionManager.events[self.selectedEventId]
        self.enterButtonInfo.text = string.format(g_i18n:getText("eq_ui_button_enter"), horse.name,
            g_i18n:formatMoney((event ~= nil and event.fee or 0) + horse.transport, 0, true, true))
        table.insert(self.menuButtonInfo, self.enterButtonInfo)
    end
    self:setMenuButtonInfoDirty()
end


-- LIST DATA SOURCE AND DELEGATE

function EqEventsFrame:getNumberOfItemsInSection(list, _section)
    if list == self.eventsList then return #self.eventRows end
    if list == self.horsesList then return #self.horseRows end
    if list == self.resultsList then return #self.resultRows end
    return 0
end


--- @param cell table ListItem
--- @param name string
--- @param text string|nil
local function setCell(cell, name, text)
    local element = cell:getAttribute(name)
    if element ~= nil then element:setText(text or "") end
end


function EqEventsFrame:populateCellForItemInSection(list, _section, index, cell)
    if list == self.eventsList then
        local row = self.eventRows[index]
        if row == nil then return end
        setCell(cell, "title", row.title)
        setCell(cell, "level", row.level)
        setCell(cell, "going", row.going)
        setCell(cell, "when", row.when)
        setCell(cell, "fee", row.fee)
        setCell(cell, "prize", row.prize)
        setCell(cell, "yours", row.yours)
    elseif list == self.horsesList then
        local row = self.horseRows[index]
        if row == nil then return end
        setCell(cell, "name", row.name)
        setCell(cell, "age", row.age)
        setCell(cell, "rating", row.rating)
        setCell(cell, "status", row.status)
    elseif list == self.resultsList then
        local row = self.resultRows[index]
        if row == nil then return end
        setCell(cell, "day", row.day)
        setCell(cell, "title", row.title)
        setCell(cell, "horse", row.horse)
        setCell(cell, "result", row.result)
        setCell(cell, "prize", row.prize)
    end
end


function EqEventsFrame:onListSelectionChanged(list, _section, index)
    if list == self.eventsList then
        local row = self.eventRows[index]
        if row ~= nil and row.event.id ~= self.selectedEventId then
            self.message = nil
            self:selectEvent(row)
        end
        self:updateButtons()
    elseif list == self.horsesList then
        self.selectedHorseIndex = index
        self:updateButtons()
    end
end


-- BUTTONS

function EqEventsFrame:onClickEnter()
    local horse = self.selectedHorseIndex ~= nil and self.horseRows[self.selectedHorseIndex] or nil
    if horse == nil or self.selectedEventId == nil then return end

    local _, text = EqCompetitionManager.enter(self.selectedEventId, horse.animal, farmId())
    self.message = text
    self:refresh()
end


function EqEventsFrame:onClickToggle()
    self.mode = self.mode == EqEventsFrame.MODE_EVENTS and EqEventsFrame.MODE_RESULTS or EqEventsFrame.MODE_EVENTS
    self.message = nil
    self:refresh()
    local list = self.mode == EqEventsFrame.MODE_EVENTS and self.eventsList or self.resultsList
    if list ~= nil then FocusManager:setFocus(list) end
end


-- INSTALL

--- Our icon atlas, so the tab and the header can use "eqMenu.events". Registered when RLRM
--- builds its menu, the same moment RLRM registers its own atlas.
function EqEventsFrame.registerIcons()
    g_overlayManager:addTextureConfigFile(modDirectory .. "gui/eqMenuIcons.xml", "eqMenu")
end


--- Load our frame and register it as the last page of RLRM's menu.
--- @param menu table the RLMenu instance, inside its setupMenuPages
function EqEventsFrame.addToMenu(menu)
    EqEventsFrame.registerIcons()
    local frame = EqEventsFrame.new()
    g_gui:loadGui(modDirectory .. "gui/eqEventsFrame.xml", EqEventsFrame.NAME, frame, true)

    -- Size the frame to the paging area, as a FrameReference would.
    local paging = menu.pagingElement
    frame.positionOrigin = paging.positionOrigin
    frame.screenAlign = paging.screenAlign
    frame:setSize(unpack(paging.size))
    local root = frame:getRootElement()
    root.positionOrigin = paging.positionOrigin
    root.screenAlign = paging.screenAlign
    root:setSize(unpack(paging.size))

    paging:addElement(frame)
    menu.eqEventsFrame = frame

    local predicate = function()
        return g_currentMission ~= nil and EqMain.isActive
            and (menu.openMode == nil or menu.openMode == "full")
    end
    menu:registerPage(frame, nil, predicate)
    menu:addPageTab(frame, nil, nil, EqEventsFrame.ICON_SLICE)
    if frame.initialize ~= nil then frame:initialize() end

    paging:updateAbsolutePosition()
    paging:updatePageMapping()
    Log:info("EqEventsFrame: Events tab added to RLRM's menu")
end


--- Append our page to RLRM's menu setup. Call once, after EqRLRM.init succeeded.
--- @param guarded function main.lua's error guard
function EqEventsFrame.install(guarded)
    local rlMenu = EqRLRM.get("RLMenu")
    rlMenu.setupMenuPages = Utils.appendedFunction(rlMenu.setupMenuPages, function(menu)
        guarded("events tab", function() EqEventsFrame.addToMenu(menu) end)
    end)
    Log:debug("EqEventsFrame: hooked RLMenu:setupMenuPages")
end

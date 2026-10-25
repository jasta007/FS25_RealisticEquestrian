--[[
    EqEventsFrame.lua
    The Events tab in RLRM's menu, with two tabs of its own like RLRM's Settings page:
    - Upcoming events: open events on the left, your horses for the selected event on the right
      with a panel for the selected horse, and Enter buttons for it.
    - Results: your horses on the right with the selected one's career under them, and its last
      events on the left, each with the few lines on how it went (EqStory). The Messages tab's
      result lines open this tab on their horse (EqMessagesLink).

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

-- RLRM genetics bands whose colours the Success and Training words borrow.
EqEventsFrame.SUCCESS_COLORS = {
    favourite = "rl_ui_genetics_extremelyHigh",
    contender = "rl_ui_genetics_high",
    outsider = "rl_ui_genetics_low",
    longShot = "rl_ui_genetics_extremelyLow",
}
EqEventsFrame.TRAINING_COLORS = {
    high = "rl_ui_genetics_veryHigh",
    medium = "rl_ui_genetics_average",
    low = "rl_ui_genetics_low",
    none = "rl_ui_genetics_extremelyLow",
}
EqEventsFrame.RISK_COLORS = {
    low = "rl_ui_genetics_veryHigh",
    minor = "rl_ui_genetics_average",
    moderate = "rl_ui_genetics_low",
    risky = "rl_ui_genetics_extremelyLow",
}


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
        text = g_i18n:getText("eq_ui_button_enterAuto"),
        callback = function() self:onClickEnter(EqCompetitionManager.TRANSPORT_AUTO) end,
    }
    self.enterManualButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = g_i18n:getText("eq_ui_button_enterManual"),
        callback = function() self:onClickEnter(EqCompetitionManager.TRANSPORT_MANUAL) end,
    }
    self.toggleButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = g_i18n:getText("eq_ui_tab_results"),
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


--- Point the header icon at our texture for every overlay state, without a slice id. Loaded from
--- the XML's imageSliceId, the icon showed the whole base UI atlas squashed into the square,
--- so set the overlay ourselves: our file, our UVs, no per-state overrides.
--- @return boolean changed true when the icon was not showing our slice
function EqEventsFrame:applyHeaderIcon()
    local icon = self.headerIcon
    if icon == nil or icon.overlay == nil then return false end
    local slice = g_overlayManager:getSliceInfoById(EqEventsFrame.ICON_SLICE)
    if slice == nil then return false end

    local overlay = icon.overlay
    if not self.loggedIconState then
        self.loggedIconState = true
        local uvs = overlay.uvs or {}
        Log:info("EqEventsFrame: header icon file '%s' uvs (%s) state %s",
            tostring(overlay.filename), table.concat(uvs, " "), tostring(icon:getOverlayState()))
    end
    local clean = overlay.filename == slice.filename and overlay.overlay ~= nil and overlay.sliceId == nil
    for state, suffix in pairs(GuiOverlay.OVERLAY_STATE_SUFFIXES) do
        if state ~= GuiOverlay.STATE_NORMAL
            and (overlay["filename" .. suffix] ~= nil or overlay["uvs" .. suffix] ~= nil) then
            clean = false
        end
    end
    if clean then return false end

    if not self.loggedHeaderIcon then
        self.loggedHeaderIcon = true
        Log:info("EqEventsFrame: header icon was '%s' in state %s, setting it to '%s'",
            tostring(overlay.filename), tostring(icon:getOverlayState()), slice.filename)
    end

    GuiOverlay.deleteOverlay(overlay)
    for state, suffix in pairs(GuiOverlay.OVERLAY_STATE_SUFFIXES) do
        if state ~= GuiOverlay.STATE_NORMAL then
            overlay["filename" .. suffix] = nil
            overlay["uvs" .. suffix] = nil
            overlay["sliceId" .. suffix] = nil
        end
    end
    overlay.filename = slice.filename
    overlay.uvs = table.clone(slice.uvs)
    -- No sliceId: GuiOverlay hands it to the engine's createImageOverlay, and with our id the
    -- engine drew the base UI atlas even though filename and UVs were ours (log, 25 Oct). The
    -- tab button never passes one.
    overlay.sliceId = nil
    overlay.overlay = nil
    GuiOverlay.createOverlay(overlay)
    return true
end


function EqEventsFrame:onFrameOpen()
    EqEventsFrame:superClass().onFrameOpen(self)
    self:applyHeaderIcon()
    self:initializeSubCategoryPages()
    self:refresh()
    self:focusMode()
end


function EqEventsFrame:update(dt)
    EqEventsFrame:superClass().update(self, dt)
    -- Cheap check each frame: the profile can come back after onFrameOpen.
    self:applyHeaderIcon()
end


-- TABS (the same profiles and wiring as RLRM's Settings page)

EqEventsFrame.TAB_MODES = { EqEventsFrame.MODE_EVENTS, EqEventsFrame.MODE_RESULTS }


--- @param mode string
--- @return number index the mode's tab
local function tabIndex(mode)
    return mode == EqEventsFrame.MODE_RESULTS and 2 or 1
end


--- Number the tabs and light the current one, as RLRM's settings frame does: the paging option
--- holds one text per tab and the tab buttons ask it whether they are selected.
function EqEventsFrame:initializeSubCategoryPages()
    if self.subCategoryPaging == nil or self.subCategoryTabs == nil then return end
    local texts = {}
    for index, button in ipairs(self.subCategoryTabs) do
        local isSelected = function()
            return index == tonumber(self.subCategoryPaging.texts[self.subCategoryPaging:getState()])
        end
        button.getIsSelected = isSelected
        local background = button:getDescendantByName("background")
        if background ~= nil then background.getIsSelected = isSelected end
        table.insert(texts, tostring(index))
    end
    if self.subCategoryBox ~= nil then
        self.subCategoryBox:invalidateLayout()
        self.subCategoryPaging:setTexts(texts)
        self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)
    else
        self.subCategoryPaging:setTexts(texts)
    end
    -- Without the callback: onFrameOpen refreshes once afterwards.
    self.subCategoryPaging:setState(tabIndex(self.mode), false)
end


--- The paging option changed: show that tab.
--- @param state number
function EqEventsFrame:onSubCategoryChanged(state)
    local index = self.subCategoryPaging ~= nil and tonumber(self.subCategoryPaging.texts[state]) or nil
    local mode = index ~= nil and EqEventsFrame.TAB_MODES[index] or nil
    if mode == nil or mode == self.mode then return end
    self.mode = mode
    self.message = nil
    self:refresh()
    self:focusMode()
end


--- @param mode string
function EqEventsFrame:showMode(mode)
    if self.subCategoryPaging ~= nil and self.subCategoryPaging.texts ~= nil and #self.subCategoryPaging.texts > 0 then
        self.subCategoryPaging:setState(tabIndex(mode), true)
    elseif mode ~= self.mode then
        self.mode = mode
        self.message = nil
        self:refresh()
        self:focusMode()
    end
end


function EqEventsFrame:onClickUpcomingTab()
    self:showMode(EqEventsFrame.MODE_EVENTS)
end


function EqEventsFrame:onClickResultsTab()
    self:showMode(EqEventsFrame.MODE_RESULTS)
end


--- Focus the list the current tab starts on.
function EqEventsFrame:focusMode()
    local list = self.mode == EqEventsFrame.MODE_EVENTS and self.eventsList or self.horsesList
    if list ~= nil then FocusManager:setFocus(list) end
end


--- @param element table|nil
--- @param visible boolean
local function show(element, visible)
    if element ~= nil then element:setVisible(visible) end
end


--- Rebuild every list from the manager, keeping the selected event or horse where possible.
function EqEventsFrame:refresh()
    local ok, reason = readiness()
    self.isReady = ok
    local isEvents = self.mode == EqEventsFrame.MODE_EVENTS
    self.eventRows = ok and EqEventsView.eventRows(farmId()) or {}

    show(self.eventsHeader, isEvents)
    show(self.eventsBox, isEvents)
    show(self.horsesHeader, isEvents)
    show(self.resultsHeader, not isEvents)
    show(self.resultsBox, not isEvents)
    show(self.resultHorsesHeader, not isEvents)

    self.eventsList:reloadData()
    if isEvents then
        self.resultRows = {}
        self.resultsList:reloadData()
        local selectIndex = 1
        for i, row in ipairs(self.eventRows) do
            if row.event.id == self.selectedEventId then selectIndex = i end
        end
        if #self.eventRows > 0 then
            self.eventsList:setSelectedIndex(selectIndex)
        end
        self:selectEvent(self.eventRows[selectIndex])
    else
        self:refreshResults()
    end

    local empty
    if not ok then
        empty = reason
    elseif isEvents and #self.eventRows == 0 then
        empty = g_i18n:getText("eq_ui_noEvents")
    elseif not isEvents then
        local horse = self.selectedHorseIndex ~= nil and self.horseRows[self.selectedHorseIndex] or nil
        if horse == nil then
            empty = g_i18n:getText("eq_ui_noResults")
        elseif #self.resultRows == 0 then
            empty = string.format(g_i18n:getText("eq_ui_noHorseResults"), horse.name)
        end
    end
    self.emptyState:setText(empty or "")
    self.emptyState:setVisible(empty ~= nil and empty ~= "")

    self:updateButtons()
end


--- The Results tab: every horse of the farm on the right, the selected one's last events left.
function EqEventsFrame:refreshResults()
    self.horseRows = self.isReady and EqEventsView.resultHorseRows(farmId()) or {}
    self.horsesList:reloadData()
    local selectIndex = nil
    for i, row in ipairs(self.horseRows) do
        if row.record.id == self.selectedResultHorseId then selectIndex = i end
    end
    selectIndex = selectIndex or (#self.horseRows > 0 and 1 or nil)
    if selectIndex ~= nil then self.horsesList:setSelectedIndex(selectIndex) end
    self:selectResultHorse(selectIndex)

    local noHorses = #self.horseRows == 0 and self.isReady
    self.horsesEmptyState:setText(noHorses and g_i18n:getText("eq_ui_noHorses") or "")
    self.horsesEmptyState:setVisible(noHorses)
end


--- @param index number|nil the horse's row on the Results tab
function EqEventsFrame:selectResultHorse(index)
    self.selectedHorseIndex = index
    local row = index ~= nil and self.horseRows[index] or nil
    if row ~= nil then self.selectedResultHorseId = row.record.id end
    self.resultRows = row ~= nil and EqEventsView.horseResultRows(row.record) or {}
    self.resultsList:reloadData()
    if #self.resultRows > 0 then self.resultsList:setSelectedIndex(1) end
    if self.resultsHeaderText ~= nil then
        self.resultsHeaderText:setText(row ~= nil and row.name or g_i18n:getText("eq_ui_col_result"))
    end
    self:updateHorsePanel()
    self:updateCareerPanel()
    self:updateSummary()
end


--- Open the Results tab on one horse: the Messages tab's View results button.
--- @param horseId string
function EqEventsFrame:showResultsFor(horseId)
    self.selectedResultHorseId = horseId
    self.mode = EqEventsFrame.MODE_RESULTS
    self.message = nil
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
    self:updateHorsePanel()
    self:updateCareerPanel()

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
    elseif self.mode == EqEventsFrame.MODE_RESULTS then
        text = string.format(g_i18n:getText("eq_ui_summary_results"), EqHorseRecord.RESULTS_KEPT)
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
    self.toggleButtonInfo.text = g_i18n:getText(self.mode == EqEventsFrame.MODE_EVENTS and "eq_ui_tab_results" or "eq_ui_tab_upcoming")
    self.menuButtonInfo = { self.backButtonInfo, self.toggleButtonInfo }

    local horse = self.selectedHorseIndex ~= nil and self.horseRows[self.selectedHorseIndex] or nil
    if self.mode == EqEventsFrame.MODE_EVENTS and horse ~= nil and horse.canEnter then
        local event = EqCompetitionManager.events[self.selectedEventId]
        local fee = event ~= nil and event.fee or 0
        self.enterButtonInfo.text = string.format(g_i18n:getText("eq_ui_button_enterAuto"),
            g_i18n:formatMoney(fee + horse.autoCost, 0, true, true))
        self.enterManualButtonInfo.text = string.format(g_i18n:getText("eq_ui_button_enterManual"),
            g_i18n:formatMoney(fee + horse.manualCost, 0, true, true))
        table.insert(self.menuButtonInfo, self.enterButtonInfo)
        table.insert(self.menuButtonInfo, self.enterManualButtonInfo)
    end
    self:setMenuButtonInfoDirty()
end


--- @param element table|nil Text
--- @param text string|nil
--- @param color table|nil { r, g, b, a }, nil for the profile's colour
local function setText(element, text, color)
    if element == nil then return end
    element:setText(text or "")
    if color ~= nil then
        element:setTextColor(unpack(color))
    elseif element.eqDefaultColor ~= nil then
        element:setTextColor(unpack(element.eqDefaultColor))
    end
end


--- Remember a text's profile colour before we first colour it, so uncoloured text goes back to it.
--- @param element table|nil Text
local function keepDefaultColor(element)
    if element ~= nil and element.eqDefaultColor == nil and element.textColor ~= nil then
        element.eqDefaultColor = { unpack(element.textColor) }
    end
end


--- @param colors table band name -> RLRM genetics band key
--- @param band string|nil
--- @return table|nil color
local function wordColor(colors, band)
    return band ~= nil and colors[band] ~= nil and EqInfoDisplay.bandColor(colors[band]) or nil
end


--- Fill the panel under the horses table for the selected horse, or hide it.
function EqEventsFrame:updateHorsePanel()
    if self.horsePanel == nil then return end
    local row = self.selectedHorseIndex ~= nil and self.horseRows[self.selectedHorseIndex] or nil
    local show = row ~= nil and self.mode == EqEventsFrame.MODE_EVENTS
    self.horsePanel:setVisible(show)
    if not show then return end

    setText(self.panelName, row.name)
    setText(self.panelAge, string.format(g_i18n:getText("eq_ui_ageLong"), row.animal.age or 0))
    setText(self.panelStatus, row.status)
    for i, stat in ipairs(EqConstants.STAT_KEYS) do
        local label, value = self.panelStatLabel[i], self.panelStatValue[i]
        keepDefaultColor(label)
        keepDefaultColor(value)
        local text, color = EqInfoDisplay.skillValue(row.record.trained[stat] or 0)
        setText(label, g_i18n:getText("eq_stat_" .. stat), color)
        setText(value, text, color)
    end
    keepDefaultColor(self.panelTraining)
    keepDefaultColor(self.panelSuccess)
    keepDefaultColor(self.panelRisk)
    setText(self.panelRisk, row.risk, wordColor(EqEventsFrame.RISK_COLORS, row.riskBand))
    setText(self.panelTraining, row.training, wordColor(EqEventsFrame.TRAINING_COLORS, row.trainingBand))
    local event = EqCompetitionManager.events[self.selectedEventId]
    local fee = event ~= nil and event.fee or 0
    -- The label names a trip abroad, so the dearer price explains itself.
    local distance = EqCompetitionManager.eventDistance(event)
    setText(self.panelTransportLabel, g_i18n:getText(distance == "local" and "eq_ui_transportLabel" or ("eq_ui_transportLabel_" .. distance)))
    setText(self.panelTransport, string.format(g_i18n:getText("eq_ui_transportLine"),
        g_i18n:formatMoney(fee + row.autoCost, 0, true, true), g_i18n:formatMoney(fee + row.manualCost, 0, true, true)))
    setText(self.panelSuccess, row.success, wordColor(EqEventsFrame.SUCCESS_COLORS, row.successBand))
    setText(self.panelSpecialty, EqCompetitionManager.specialtyText(row.record))
end


--- Fill the career panel under the horses on the Results tab, or hide it.
function EqEventsFrame:updateCareerPanel()
    if self.careerPanel == nil then return end
    local row = self.selectedHorseIndex ~= nil and self.horseRows[self.selectedHorseIndex] or nil
    local show = row ~= nil and self.mode == EqEventsFrame.MODE_RESULTS
    self.careerPanel:setVisible(show)
    if not show then return end

    local record, career = row.record, row.record.career
    setText(self.careerName, row.name)
    setText(self.careerAge, string.format(g_i18n:getText("eq_ui_ageLong"), row.animal.age or 0))
    for i, stat in ipairs(EqConstants.STAT_KEYS) do
        local label, value = self.careerStatLabel ~= nil and self.careerStatLabel[i] or nil,
            self.careerStatValue ~= nil and self.careerStatValue[i] or nil
        keepDefaultColor(label)
        keepDefaultColor(value)
        local text, color = EqInfoDisplay.skillValue(record.trained[stat] or 0)
        setText(label, g_i18n:getText("eq_stat_" .. stat), color)
        setText(value, text, color)
    end
    setText(self.careerStarts, tostring(career.starts))
    setText(self.careerRecord, string.format("%d / %d", career.wins, career.places))
    setText(self.careerEarnings, g_i18n:formatMoney(career.earnings, 0, true, true))
    setText(self.careerEliminations, tostring(career.eliminations))
    setText(self.careerSpecialty, EqCompetitionManager.specialtyText(record))
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
        -- The events list reloads on the Results tab too, hidden; it must not take the horse list.
        if self.mode ~= EqEventsFrame.MODE_EVENTS then return end
        local row = self.eventRows[index]
        if row == nil then return end
        setCell(cell, "title", row.title)
        setCell(cell, "type", row.type)
        setCell(cell, "level", row.level)
        setCell(cell, "going", row.going)
        local risk = cell:getAttribute("risk")
        keepDefaultColor(risk)
        setText(risk, row.risk, wordColor(EqEventsFrame.RISK_COLORS, row.riskBand))
        setCell(cell, "fee", row.fee)
        setCell(cell, "prize", row.prize)
        setCell(cell, "yours", row.yours)
    elseif list == self.horsesList and self.mode == EqEventsFrame.MODE_RESULTS then
        local row = self.horseRows[index]
        if row == nil then return end
        setCell(cell, "name", row.name)
        local starts, wins = cell:getAttribute("success"), cell:getAttribute("training")
        keepDefaultColor(starts)
        keepDefaultColor(wins)
        setText(starts, row.starts)
        setText(wins, row.wins)
        setCell(cell, "status", row.last)
    elseif list == self.horsesList then
        local row = self.horseRows[index]
        if row == nil then return end
        setCell(cell, "name", row.name)
        setCell(cell, "status", row.status)
        local success, training = cell:getAttribute("success"), cell:getAttribute("training")
        keepDefaultColor(success)
        keepDefaultColor(training)
        setText(success, row.success, wordColor(EqEventsFrame.SUCCESS_COLORS, row.successBand))
        setText(training, row.training, wordColor(EqEventsFrame.TRAINING_COLORS, row.trainingBand))
    elseif list == self.resultsList then
        local row = self.resultRows[index]
        if row == nil then return end
        setCell(cell, "title", row.title and row.text or "")
        setCell(cell, "line", row.title and "" or row.text)
    end
end


function EqEventsFrame:onListSelectionChanged(list, _section, index)
    if list == self.eventsList then
        -- The events list reloads on the Results tab too, hidden; it must not take the horse list.
        if self.mode ~= EqEventsFrame.MODE_EVENTS then return end
        local row = self.eventRows[index]
        if row ~= nil and row.event.id ~= self.selectedEventId then
            self.message = nil
            self:selectEvent(row)
        end
        self:updateButtons()
    elseif list == self.horsesList and self.mode == EqEventsFrame.MODE_RESULTS then
        if index ~= self.selectedHorseIndex then
            self:selectResultHorse(index)
            local row = self.horseRows[index]
            local empty = (row ~= nil and #self.resultRows == 0) and string.format(g_i18n:getText("eq_ui_noHorseResults"), row.name) or nil
            self.emptyState:setText(empty or "")
            self.emptyState:setVisible(empty ~= nil)
        end
        self:updateButtons()
    elseif list == self.horsesList then
        self.selectedHorseIndex = index
        self:updateHorsePanel()
        self:updateButtons()
    end
end


-- BUTTONS

--- @param transport string EqCompetitionManager.TRANSPORT_AUTO or TRANSPORT_MANUAL
function EqEventsFrame:onClickEnter(transport)
    local horse = self.selectedHorseIndex ~= nil and self.horseRows[self.selectedHorseIndex] or nil
    if horse == nil or self.selectedEventId == nil then return end

    local _, text = EqCompetitionManager.enter(self.selectedEventId, horse.animal, farmId(), transport)
    self.message = text
    self:refresh()
end


function EqEventsFrame:onClickToggle()
    self:showMode(self.mode == EqEventsFrame.MODE_EVENTS and EqEventsFrame.MODE_RESULTS or EqEventsFrame.MODE_EVENTS)
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
    EqEventsFrame.menu = menu
    EqEventsFrame.instance = frame

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

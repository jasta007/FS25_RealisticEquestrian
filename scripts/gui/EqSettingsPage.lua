--[[
    EqSettingsPage.lua
    Adds an "Equestrian" tab to RLRM's Settings page (next to General and Filters), one row per
    EqSettings row. The rows are built from the base game's settings profiles, the same ones
    RLRM's General tab uses, the first time the page opens, and refreshed from the savegame
    settings each time it opens. If RLRM's settings frame is not found, the rows go in a
    section of the base game's Esc > Settings > General page instead.

    The settings belong to the savegame and the server: they are saved in rlEquestrian.xml with
    the rest of our data. There is no multiplayer sync yet, so on a client the rows are shown
    but cannot be changed. The last row, Help popups, is the player's own: "Show again" forgets
    which help and welcome popups were seen (modSettings), so each pops up once more.
]]

EqSettingsPage = {}

local Log = EqLog

EqSettingsPage.controls = {}    -- row id -> MultiTextOptionElement
EqSettingsPage.layout = nil     -- the layout the rows were added to
EqSettingsPage.guarded = function(_, fn) fn() end

-- The player's own row, after the savegame's.
EqSettingsPage.HELP_ROW = { id = "helpPopups",
    texts = { { key = "eq_settings_helpPopups_seen" }, { key = "eq_settings_helpPopups_again" } } }


--- @param row table an EqSettings.ROWS entry
--- @return table texts the row's option texts
local function optionTexts(row)
    local texts = {}
    for i, entry in ipairs(row.texts) do
        texts[i] = entry.key ~= nil and g_i18n:getText(entry.key) or entry.text
    end
    return texts
end


--- @return boolean canChange true where the settings live (single player or the host)
local function canChange()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end


--- @param layout table the layout the row goes into
--- @param row table an EqSettings.ROWS entry
--- @return table option
local function addRow(layout, row)
    local box = BitmapElement.new()
    box:loadProfile(g_gui:getProfile("fs25_multiTextOptionContainer"), true)

    local option = MultiTextOptionElement.new()
    option:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOption"), true)
    option.id = "eqSetting_" .. row.id
    option.eqSettingId = row.id
    option.target = EqSettingsPage
    option:setCallback("onClickCallback", "onOptionChanged")

    local title = TextElement.new()
    title:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOptionTitle"), true)
    title:setText(g_i18n:getText("eq_settings_" .. row.id))

    local tooltip = TextElement.new()
    tooltip.name = "ignore"
    tooltip:loadProfile(g_gui:getProfile("fs25_multiTextOptionTooltip"), true)
    tooltip:setText(g_i18n:getText("eq_settings_" .. row.id .. "_tooltip"))

    option:addElement(tooltip)
    box:addElement(option)
    box:addElement(title)
    option:onGuiSetupFinished()
    title:onGuiSetupFinished()
    tooltip:onGuiSetupFinished()
    option:setTexts(optionTexts(row))
    layout:addElement(box)
    box:onGuiSetupFinished()
    return option
end


--- Add every row to a layout and remember the options.
--- @param layout table
local function addRows(layout)
    EqSettingsPage.controls = {}
    for _, row in ipairs(EqSettings.ROWS) do
        EqSettingsPage.controls[row.id] = addRow(layout, row)
    end
    EqSettingsPage.controls.helpPopups = addRow(layout, EqSettingsPage.HELP_ROW)

    local credit = TextElement.new()
    credit.name = "sectionHeader"
    credit:loadProfile(g_gui:getProfile("fs25_settingsSectionHeader"), true)
    credit.textSize = credit.textSize * 0.5
    credit:setText(string.format(g_i18n:getText("eq_settings_credit"), EqRandom.mark()))
    layout:addElement(credit)
    credit:onGuiSetupFinished()
end


--- Fallback when RLRM's settings frame has changed: a section on the base game's
--- Settings > General page, built once per settings layout.
--- @param page table InGameMenuSettingsFrame
local function buildOnGeneralPage(page)
    local layout = page.gameSettingsLayout
    if layout == nil or EqSettingsPage.layout == layout then return end

    EqSettingsPage.layout = layout
    EqSettingsPage.name = page.name

    local header = TextElement.new()
    header.name = "sectionHeader"
    header:loadProfile(g_gui:getProfile("fs25_settingsSectionHeader"), true)
    header:setText(g_i18n:getText("eq_settings_title"))
    layout:addElement(header)
    header:onGuiSetupFinished()

    addRows(layout)

    layout:invalidateLayout()
    if page.updateAlternatingElements ~= nil then page:updateAlternatingElements(layout) end
    if page.updateGeneralSettings ~= nil then page:updateGeneralSettings(layout) end
    Log:info("EqSettingsPage: added %d settings to the General settings page", #EqSettings.ROWS + 1)
end


--- Widen a copied tab button so its label fits: the copy keeps the width of the tab it came from.
--- Two estimates, the larger wins: the measured label plus the model tab's padding, and the
--- model's width scaled by label length (in game the measured widths came out too small).
--- @param tab table the new tab button
--- @param label string the new tab's label
--- @param model table the tab it was copied from
local function fitTabToText(tab, label, model)
    if model.size == nil or tab.size == nil then return end
    local modelText = tostring(model.text or "")
    local function upper(text)
        if model.textUpperCase and utf8ToUpper ~= nil then return utf8ToUpper(text) end
        return text
    end
    local function length(text)
        return utf8Strlen ~= nil and utf8Strlen(text) or #text
    end
    local function measure(text)
        if getTextWidth == nil or model.textSize == nil then return 0 end
        if setTextBold ~= nil then setTextBold(model.textBold == true) end
        local width = getTextWidth(model.textSize, upper(text))
        if setTextBold ~= nil then setTextBold(false) end
        return width
    end

    local modelWidth = model.size[1]
    local measured = measure(label) + math.max(modelWidth - measure(modelText), 0)
    local byLength = length(modelText) > 0 and modelWidth * length(label) / length(modelText) or modelWidth
    local width = math.max(modelWidth, measured, byLength)
    Log:info("EqSettingsPage: tab '%s' from '%s' (%.4f): measured %.4f, by length %.4f -> %.4f",
        label, modelText, modelWidth, measured, byLength, width)
    if width <= tab.size[1] then return end

    tab:setSize(width, nil)
    for _, child in ipairs(tab.elements) do
        if child.setSize ~= nil and child.size ~= nil and child.size[1] >= modelWidth * 0.9 then
            child:setSize(width, nil)
        end
    end
end


--- Add an "Equestrian" tab after General and Filters on RLRM's Settings page, once per frame.
--- RLRM's own tab code then treats it like its others: initializeSubCategoryPages numbers
--- every button in subCategoryTabs, and updateSubCategoryPages shows the matching entry of
--- subCategoryPages and hides the rest.
--- @param frame table RLRM's RLMenuSettingsFrame
local function buildRLRMTab(frame)
    if frame.eqSettingsTab ~= nil then return end
    local tabs, pages = frame.subCategoryTabs, frame.subCategoryPages
    if type(tabs) ~= "table" or type(pages) ~= "table" or tabs[#tabs] == nil or pages[1] == nil
        or frame.subCategoryBox == nil or frame.subCategoryPaging == nil then
        Log:warning("EqSettingsPage: RLRM's settings frame has no tab bar; Equestrian tab not added")
        return
    end

    local index = #tabs + 1
    local tab = tabs[#tabs]:clone(frame.subCategoryBox)
    tab.id = "eqSettingsTab"
    local label = g_i18n:getText("eq_settings_tab")
    tab:setText(label)
    fitTabToText(tab, label, tabs[#tabs])
    tab.onClickCallback = function()
        frame.subCategoryPaging:setState(index, true)
    end
    table.insert(tabs, tab)

    -- The page is a copy of RLRM's General page, so it keeps that page's place and size under
    -- the tab bar, with RLRM's rows taken out of the copied layout and ours put in.
    local page = pages[1]:clone(pages[1].parent)
    page.id = nil
    local layout
    for _, child in ipairs(page.elements) do
        if child.invalidateLayout ~= nil then layout = child break end
    end
    if layout == nil then
        page:delete()
        tab:delete()
        table.remove(tabs)
        Log:warning("EqSettingsPage: RLRM's General page has no layout to copy; Equestrian tab not added")
        return
    end
    layout.id = nil
    for i = #layout.elements, 1, -1 do
        local child = layout.elements[i]
        layout:removeElement(child)
        child:delete()
    end

    addRows(layout)

    page:setVisible(false)
    table.insert(pages, page)
    frame.eqSettingsTab = tab

    for _, option in pairs(EqSettingsPage.controls) do
        FocusManager:loadElementFromCustomValues(option, nil, {}, false, false)
    end
    layout:invalidateLayout()
    if frame.updateAlternatingElements ~= nil then frame:updateAlternatingElements(layout) end
    Log:info("EqSettingsPage: added the Equestrian tab to RLRM's settings with %d settings", #EqSettings.ROWS + 1)
end


--- Show the current settings, and lock the rows where they cannot be changed.
function EqSettingsPage.refresh()
    local settings = EqCompetitionManager.settings
    local locked = not canChange()
    for _, row in ipairs(EqSettings.ROWS) do
        local option = EqSettingsPage.controls[row.id]
        if option ~= nil then
            option:setState(EqSettings.stateOf(row, settings[row.id]))
            option:setDisabled(locked)
        end
    end
    local help = EqSettingsPage.controls.helpPopups
    if help ~= nil then help:setState(EqTrainingHud.anySeen() and 1 or 2) end
end


--- Appended to InGameMenuSettingsFrame.onFrameOpen (the fallback).
--- @param page table InGameMenuSettingsFrame
function EqSettingsPage.onGeneralPageOpen(page)
    if not EqMain.isActive then return end
    buildOnGeneralPage(page)
    EqSettingsPage.refresh()
end


--- Prepended to RLMenuSettingsFrame:onFrameOpen, so the tab is in place before RLRM numbers
--- its tabs.
--- @param frame table RLMenuSettingsFrame
function EqSettingsPage.onRLRMSettingsOpen(frame)
    if not EqMain.isActive then return end
    buildRLRMTab(frame)
    EqSettingsPage.refresh()
end


--- A row's option changed. Changes are saved with the game, like the rest of our data.
--- @param state number
--- @param option table the MultiTextOptionElement
function EqSettingsPage:onOptionChanged(state, option)
    EqSettingsPage.guarded("settings change", function()
        local id = option ~= nil and option.eqSettingId or nil
        if id == nil then return end
        if id == EqSettingsPage.HELP_ROW.id then
            if state == 2 then
                EqTrainingHud.resetSeen()
                Log:info("EqSettingsPage: help popups will show again")
            end
            return
        end
        if not canChange() then
            EqSettingsPage.refresh()
            return
        end

        local settings = EqCompetitionManager.settings
        if EqSettings.apply(settings, id, state) then
            Log:info("EqSettingsPage: %s set to %s", id, tostring(settings[id]))
        end
    end)
end


--- Put the settings on their own tab of RLRM's Settings page, or, if RLRM's frame has changed,
--- on the base game's Settings > General page.
--- @param guarded function main.lua's error guard
--- @param useRLRMTab boolean EqRLRM.features.settingsTab
function EqSettingsPage.install(guarded, useRLRMTab)
    EqSettingsPage.guarded = guarded
    if useRLRMTab then
        local frameClass = EqRLRM.get("RLMenuSettingsFrame")
        frameClass.onFrameOpen = Utils.prependedFunction(frameClass.onFrameOpen, function(frame)
            guarded("settings tab", function() EqSettingsPage.onRLRMSettingsOpen(frame) end)
        end)
        Log:debug("EqSettingsPage: hooked RLMenuSettingsFrame:onFrameOpen")
    else
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function(page)
            guarded("settings page", function() EqSettingsPage.onGeneralPageOpen(page) end)
        end)
        Log:info("EqSettingsPage: RLRM's settings frame not found; using the General settings page instead")
    end
end

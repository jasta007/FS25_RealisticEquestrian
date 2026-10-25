--[[
    EqSettingsPage.lua
    Adds a "Realistic Equestrian" section to the Esc menu's Settings > General page, one row per
    EqSettings row. The rows are built from the base game's own profiles (the way other mods
    add settings there) the first time the page opens, and refreshed from the savegame settings
    each time it opens.

    The settings belong to the savegame and the server: they are saved in rlEquestrian.xml with
    the rest of our data. There is no multiplayer sync yet, so on a client the rows are shown
    but cannot be changed.
]]

EqSettingsPage = {}

local Log = EqLog

EqSettingsPage.controls = {}    -- row id -> MultiTextOptionElement
EqSettingsPage.layout = nil     -- the layout the rows were added to
EqSettingsPage.guarded = function(_, fn) fn() end


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


--- @param page table InGameMenuSettingsFrame
--- @param row table an EqSettings.ROWS entry
--- @return table option
local function addRow(page, row)
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
    page.gameSettingsLayout:addElement(box)
    box:onGuiSetupFinished()
    return option
end


--- Build our section once per settings layout.
--- @param page table InGameMenuSettingsFrame
local function build(page)
    local layout = page.gameSettingsLayout
    if layout == nil or EqSettingsPage.layout == layout then return end

    EqSettingsPage.layout = layout
    EqSettingsPage.controls = {}
    EqSettingsPage.name = page.name

    local header = TextElement.new()
    header.name = "sectionHeader"
    header:loadProfile(g_gui:getProfile("fs25_settingsSectionHeader"), true)
    header:setText(g_i18n:getText("eq_settings_title"))
    layout:addElement(header)
    header:onGuiSetupFinished()

    for _, row in ipairs(EqSettings.ROWS) do
        EqSettingsPage.controls[row.id] = addRow(page, row)
    end

    layout:invalidateLayout()
    if page.updateAlternatingElements ~= nil then page:updateAlternatingElements(layout) end
    if page.updateGeneralSettings ~= nil then page:updateGeneralSettings(layout) end
    Log:info("EqSettingsPage: added %d settings to the General settings page", #EqSettings.ROWS)
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
end


--- Appended to InGameMenuSettingsFrame.onFrameOpen.
--- @param page table InGameMenuSettingsFrame
function EqSettingsPage.onFrameOpen(page)
    if not EqMain.isActive then return end
    build(page)
    EqSettingsPage.refresh()
end


--- A row's option changed. Changes are saved with the game, like the rest of our data.
--- @param state number
--- @param option table the MultiTextOptionElement
function EqSettingsPage:onOptionChanged(state, option)
    EqSettingsPage.guarded("settings change", function()
        local id = option ~= nil and option.eqSettingId or nil
        if id == nil then return end
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


--- @param guarded function main.lua's error guard
function EqSettingsPage.install(guarded)
    EqSettingsPage.guarded = guarded
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function(page)
        guarded("settings page", function() EqSettingsPage.onFrameOpen(page) end)
    end)
end

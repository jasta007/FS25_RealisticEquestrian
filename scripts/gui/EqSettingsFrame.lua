--[[
    EqSettingsFrame.lua
    The Settings tab of our own menu (EqMenu), for games without Realistic Livestock: the rows
    RLRM's Settings page shows on its Equestrian tab (EqSettingsPage), built the first time the
    tab opens and refreshed from the savegame's settings each time.
]]

EqSettingsFrame = {}
local EqSettingsFrame_mt = Class(EqSettingsFrame, TabbedMenuFrameElement)

local Log = EqLog
local modDirectory = g_currentModDirectory

EqSettingsFrame.NAME = "EqSettingsFrame"
EqSettingsFrame.ICON_SLICE = "gui.icon_options_generalSettings"


--- @return table self
function EqSettingsFrame.new()
    local self = EqSettingsFrame:superClass().new(nil, EqSettingsFrame_mt)
    self.name = EqSettingsFrame.NAME
    self.hasCustomMenuButtons = true
    self.backButtonInfo = { inputAction = InputAction.MENU_BACK }
    self.menuButtonInfo = { self.backButtonInfo }
    return self
end


function EqSettingsFrame:onFrameOpen()
    EqSettingsFrame:superClass().onFrameOpen(self)
    local guarded = EqMenu.guarded or function(_, fn) fn() end
    guarded("settings tab", function()
        EqSettingsPage.buildInto(self.settingsLayout, EqMenu.guarded)
        EqSettingsPage.refresh()
    end)
    local first = EqSettingsPage.controls ~= nil and EqSettingsPage.controls[EqSettings.ROWS[1].id] or nil
    if first ~= nil then FocusManager:setFocus(first) end
end


--- @param menu table our menu (EqMenu)
function EqSettingsFrame.addToMenu(menu)
    local frame = EqSettingsFrame.new()
    g_gui:loadGui(modDirectory .. "gui/eqSettingsFrame.xml", EqSettingsFrame.NAME, frame, true)
    EqMenu.addFrame(menu, frame, EqSettingsFrame.ICON_SLICE)
    EqSettingsFrame.instance = frame
    Log:info("EqSettingsFrame: Settings tab added")
end

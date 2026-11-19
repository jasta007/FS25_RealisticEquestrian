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
        EqSettingsFrame.tintRows(self.settingsLayout)
    end)
    local first = EqSettingsPage.controls ~= nil and EqSettingsPage.controls[EqSettings.ROWS[1].id] or nil
    if first ~= nil then FocusManager:setFocus(first) end
end


--- @param menu table our menu (EqMenu)
--- The base row container draws a plain white bitmap until it is tinted; the base settings page
--- (and RLRM's) tint the rows in alternating shades, so do the same. Section headers restart it.
--- @param layout table
function EqSettingsFrame.tintRows(layout)
    if layout == nil or layout.elements == nil then return end
    local colors = InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.COLOR_ALTERNATING or nil
    local alternate = true
    for _, row in ipairs(layout.elements) do
        if row.setImageColor ~= nil and row.visible ~= false and row.elements ~= nil and #row.elements > 0 then
            if colors ~= nil and colors[alternate] ~= nil then
                row:setImageColor(nil, unpack(colors[alternate]))
            else
                row:setImageColor(nil, 0, 0, 0, alternate and 0.25 or 0)
            end
            alternate = not alternate
        else
            alternate = true
        end
    end
    layout:invalidateLayout()
end


function EqSettingsFrame.addToMenu(menu)
    local frame = EqSettingsFrame.new()
    g_gui:loadGui(modDirectory .. "gui/eqSettingsFrame.xml", EqSettingsFrame.NAME, frame, true)
    EqMenu.addFrame(menu, frame, EqSettingsFrame.ICON_SLICE)
    EqSettingsFrame.instance = frame
    Log:info("EqSettingsFrame: Settings tab added")
end

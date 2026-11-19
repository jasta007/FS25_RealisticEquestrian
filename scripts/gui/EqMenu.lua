--[[
    EqMenu.lua
    Realistic Equestrian's own menu, for games without Realistic Livestock (RLRM). With RLRM our
    tabs live in RLRM's menu instead and this file installs nothing.

    A full-screen TabbedMenu like RLRM's (and the base game's own menus), with five tabs:
    Horses (EqHorsesFrame), Events (EqEventsFrame), Staff (EqStaffFrame), Messages
    (EqMessagesFrame) and Settings (EqSettingsFrame). Events and Staff are the same frames RLRM's
    menu shows; they add themselves with the same addToMenu they use there.

    Opened with the EQ_MENU key (Right Shift + O by default) or the Equestrian button on a horse
    stable's Esc > Animals page (EqAnimalsPageButton), which brings you back there on Back.
]]

EqMenu = {}
local EqMenu_mt = Class(EqMenu, TabbedMenu)

local Log = EqLog

EqMenu.NAME = "EqMenu"
EqMenu.ACTION_NAME = "EQ_MENU"
EqMenu.instance = nil
EqMenu.modDirectory = nil
EqMenu.installed = false


--- @return table self
function EqMenu.new(target, custom_mt)
    local self = TabbedMenu.new(target, custom_mt or EqMenu_mt)
    self.isOpen = false
    self.openedFromInGameMenu = false
    -- A horse to land on in the Horses tab, set by the open that asked for it.
    self.anchoredHusbandry = nil
    return self
end


--- Load the profiles our frames use and build the menu. Runs once per session, after the
--- mission has loaded.
function EqMenu.setupGui()
    if EqMenu.instance ~= nil or g_gui == nil then return end
    local dir = EqMenu.modDirectory
    -- The frames use RLRM's table profiles; without RLRM we bring the same names ourselves.
    g_gui:loadProfiles(dir .. "gui/eqMenuProfiles.xml")
    EqEventsFrame.registerIcons()

    EqMenu.instance = EqMenu.new()
    EqMenu.instance.eqIconsRegistered = true
    g_gui:loadGui(dir .. "gui/eqMenu.xml", EqMenu.NAME, EqMenu.instance, false)
    Log:info("EqMenu: Equestrian menu ready (no Realistic Livestock)")
end


function EqMenu:onGuiSetupFinished()
    EqMenu:superClass().onGuiSetupFinished(self)
    self:setupMenuPages()
end


--- Our frames, in tab order. Each adds itself to the paging, as in RLRM's menu.
function EqMenu:setupMenuPages()
    local guarded = EqMenu.guarded or function(_, fn) fn() end
    guarded("horses tab", function() EqHorsesFrame.addToMenu(self) end)
    guarded("events tab", function() EqEventsFrame.addToMenu(self) end)
    guarded("staff tab", function() EqStaffFrame.addToMenu(self) end)
    guarded("messages tab", function() EqMessagesFrame.addToMenu(self) end)
    guarded("settings tab", function() EqSettingsFrame.addToMenu(self) end)
end


--- Size a loaded frame to the paging area, as a FrameReference would, and register it as the
--- next tab. The same steps our Events and Staff tabs take in RLRM's menu.
--- @param menu table
--- @param frame table a loaded TabbedMenuFrameElement
--- @param iconSlice string
function EqMenu.addFrame(menu, frame, iconSlice)
    local paging = menu.pagingElement
    frame.positionOrigin = paging.positionOrigin
    frame.screenAlign = paging.screenAlign
    frame:setSize(unpack(paging.size))
    local root = frame:getRootElement()
    root.positionOrigin = paging.positionOrigin
    root.screenAlign = paging.screenAlign
    root:setSize(unpack(paging.size))
    paging:addElement(frame)

    menu:registerPage(frame, nil, function() return g_currentMission ~= nil and EqMain.isActive end)
    menu:addPageTab(frame, nil, nil, iconSlice)
    if frame.initialize ~= nil then frame:initialize() end
    paging:updateAbsolutePosition()
    paging:updatePageMapping()
end


function EqMenu:setupMenuButtonInfo()
    EqMenu:superClass().setupMenuButtonInfo(self)
    self.clickBackCallback = self:makeSelfCallback(self.onButtonBack)
    self.backButtonInfo = { inputAction = InputAction.MENU_BACK, text = g_i18n:getText("button_back"),
        callback = self.clickBackCallback }
    self.defaultMenuButtonInfo = { self.backButtonInfo }
    self.defaultMenuButtonInfoByActions[InputAction.MENU_BACK] = self.backButtonInfo
    self.defaultButtonActionCallbacks = { [InputAction.MENU_BACK] = self.clickBackCallback }
end


--- Back returns to the Esc menu when we came from there, else closes.
function EqMenu:onButtonBack()
    if self.openedFromInGameMenu then
        self.openedFromInGameMenu = false
        local ok = pcall(function() g_gui:showGui("InGameMenu") end)
        if ok then return end
    end
    self:exitMenu()
end


function EqMenu:onOpen()
    EqMenu:superClass().onOpen(self)
    self.isOpen = true
end


function EqMenu:onClose()
    self.openedFromInGameMenu = false
    self.anchoredHusbandry = nil
    pcall(function() EqMenu:superClass().onClose(self) end)
    self.isOpen = false
end


--- Show the menu.
--- @param context table|nil { husbandry, fromInGameMenu }: the Animals page's button lands on
---     the Horses tab of that stable and makes Back return there
--- @return boolean opened
function EqMenu.open(context)
    local menu = EqMenu.instance
    if menu == nil or g_gui == nil then return false end
    local fromMenu = type(context) == "table" and context.fromInGameMenu == true
    if not fromMenu and g_gui:getIsGuiVisible() then return false end
    if g_gui.getIsDialogVisible ~= nil and g_gui:getIsDialogVisible() then return false end

    menu.openedFromInGameMenu = fromMenu
    menu.anchoredHusbandry = type(context) == "table" and context.husbandry or nil
    if fromMenu then
        menu.restorePageIndex = 1
        menu.restorePage = nil
    end
    local ok, err = pcall(function() g_gui:showGui(EqMenu.NAME) end)
    if not ok then
        Log:warning("EqMenu: could not open: %s", tostring(err))
        menu.openedFromInGameMenu = false
        return false
    end
    return true
end


--- Open on one tab.
--- @param frame table one of our frames, once added
function EqMenu.openOn(frame)
    local menu = EqMenu.instance
    if menu == nil or frame == nil then return end
    if menu.isOpen then
        menu:goToPage(frame)
        return
    end
    menu.restorePage = frame
    EqMenu.open()
end


--- The EQ_MENU key on foot, in a vehicle or on a horse.
function EqMenu.onMenuKey()
    if not EqMain.isActive then return end
    if not EqMenu.open() then Log:info("EqMenu: menu key pressed, but another screen is open") end
end


local function registerKey()
    if InputAction == nil or InputAction[EqMenu.ACTION_NAME] == nil then return end
    local ok, eventId = g_inputBinding:registerActionEvent(InputAction[EqMenu.ACTION_NAME], EqMenu, EqMenu.onMenuKey,
        false, true, false, true, nil, true)
    if ok and eventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(eventId, false)
        if not EqMenu.keyLogged then
            EqMenu.keyLogged = true
            Log:info("EqMenu: menu key registered")
        end
    elseif not EqMenu.keyFailLogged then
        EqMenu.keyFailLogged = true
        Log:warning("EqMenu: menu key not registered (event %s)", tostring(eventId))
    end
end


--- Hook the key. Call once, from EqMain.activate, only without RLRM.
--- @param guarded function main.lua's error guard
--- @param modDirectory string
function EqMenu.install(guarded, modDirectory)
    if EqMenu.installed then return end
    EqMenu.installed = true
    EqMenu.guarded = guarded
    EqMenu.modDirectory = modDirectory
    if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
        PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
            PlayerInputComponent.registerGlobalPlayerActionEvents, function()
                guarded("equestrian menu key", registerKey)
            end)
    else
        Log:warning("EqMenu: no global player actions to add the menu key to; open it from Esc > Animals")
    end
end

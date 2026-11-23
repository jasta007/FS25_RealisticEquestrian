--[[
    EqHorsesFrame.lua
    The Horses tab of our own menu (EqMenu), for games without Realistic Livestock. With RLRM
    the same things show in RLRM's Info tab (EqInfoDisplay, EqRoleMenu, EqRideButton).

    Left, the farm's horses (in pens, being ridden or in a trailer): name, role, age, the four
    skills and their competition status. Right, the selected horse's lines from the look-at
    Skills box (EqInfoDisplay.fillSkillsBox), then its stable, daily training, fitness, health
    and career. Buttons: Ride horse (a horse in a pen), Role (cycles, as G does in RLRM's list)
    and Retire (permanent, asks first).

    Roles and retiring change the horse records, which only the server keeps, so on a
    multiplayer client the buttons are hidden (milestone 7).
]]

EqHorsesFrame = {}
local EqHorsesFrame_mt = Class(EqHorsesFrame, TabbedMenuFrameElement)

local Log = EqLog
local modDirectory = g_currentModDirectory

EqHorsesFrame.NAME = "EqHorsesFrame"
EqHorsesFrame.ICON_SLICE = "eqMenu.horses"
EqHorsesFrame.CELLS = { "name", "role", "age", "stamina", "speed", "agility", "temperament", "status" }
EqHorsesFrame.GREY = { 0.6, 0.6, 0.6, 1 }


--- @return table self
function EqHorsesFrame.new()
    local self = EqHorsesFrame:superClass().new(nil, EqHorsesFrame_mt)
    self.name = EqHorsesFrame.NAME
    self.rows = {}
    self.selectedIndex = nil
    self.selectedId = nil
    self.hasCustomMenuButtons = true

    self.backButtonInfo = { inputAction = InputAction.MENU_BACK }
    self.rideButtonInfo = {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("eq_ui_button_rideHorse"),
        callback = function() self:onClickRide() end,
    }
    self.roleButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        callback = function() self:onClickRole() end,
    }
    self.retireButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = g_i18n:getText("eq_ui_retire"),
        callback = function() self:onClickRetire() end,
    }
    self.menuButtonInfo = { self.backButtonInfo }
    return self
end


function EqHorsesFrame:onGuiSetupFinished()
    EqHorsesFrame:superClass().onGuiSetupFinished(self)
    if self.horseList ~= nil then
        self.horseList:setDataSource(self)
        self.horseList:setDelegate(self)
    end
end


--- @return boolean true where records can be changed (single player or the host)
local function isServer()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end


--- @return number farmId
local function farmId()
    return g_currentMission:getFarmId()
end


function EqHorsesFrame:onFrameOpen()
    EqHorsesFrame:superClass().onFrameOpen(self)
    EqEventsFrame.applyHeaderIcon(self, EqHorsesFrame.ICON_SLICE)
    -- The Esc > Animals page's button opens on its stable: its first horse is selected.
    local menu = EqHorsesFrame.menu
    local anchor = menu ~= nil and menu.anchoredHusbandry or nil
    if menu ~= nil then menu.anchoredHusbandry = nil end
    self.anchor = anchor
    self:refresh()
    if self.horseList ~= nil then FocusManager:setFocus(self.horseList) end
end


function EqHorsesFrame:update(dt)
    EqHorsesFrame:superClass().update(self, dt)
    EqEventsFrame.applyHeaderIcon(self, EqHorsesFrame.ICON_SLICE)
end


-- ROWS

--- @param element table|nil
--- @param text string|nil
--- @param color table|nil
local function setText(element, text, color)
    if element == nil then return end
    if element.eqDefaultColor == nil and element.textColor ~= nil then element.eqDefaultColor = { unpack(element.textColor) } end
    element:setText(text or "")
    if color ~= nil then
        element:setTextColor(unpack(color))
    elseif element.eqDefaultColor ~= nil then
        element:setTextColor(unpack(element.eqDefaultColor))
    end
end


--- @param months number
--- @param short boolean|nil true for the list cell ("3y 4m")
--- @return string such as "3 years, 4 months"
function EqHorsesFrame.ageText(months, short)
    return short and EqAge.short(months) or EqAge.long(months)
end


--- @param animal table
--- @return string name
local function nameOf(animal, record)
    local name = animal.getName ~= nil and animal:getName() or nil
    if name == nil or name == "" then name = record.id end
    return name
end


--- Where a horse is: its pen, or "Being ridden" / "In a trailer".
--- @param animal table
--- @return table|nil pen
--- @return string where
local function whereIs(animal)
    local pen = EqBase.installed and EqBase.husbandryOf(animal) or nil
    if pen == nil and animal.clusterSystem ~= nil then pen = animal.clusterSystem.owner end
    if pen ~= nil and pen.spec_husbandryAnimals ~= nil then
        return pen, pen.getName ~= nil and pen:getName() or ""
    end
    return nil, ""
end


--- @param farm number
--- @return table rows one per horse, by name
function EqHorsesFrame.buildRows(farm)
    local rows, seen = {}, {}
    local function add(animal, where)
        local record = EqRegistry.getOrCreate(animal)
        if record == nil or seen[record.id] then return end
        seen[record.id] = true
        local pen, penName = whereIs(animal)
        table.insert(rows, {
            animal = animal,
            record = record,
            pen = pen,
            where = where or penName,
            name = nameOf(animal, record),
        })
    end
    for _, animal in ipairs(EqRLRM.listHorsesForFarm(farm)) do add(animal) end
    for _, animal in ipairs(EqRLRM.listHorsesInTrailers(farm)) do add(animal, g_i18n:getText("eq_horses_inTrailer")) end
    table.sort(rows, function(a, b)
        if string.lower(a.name) ~= string.lower(b.name) then return string.lower(a.name) < string.lower(b.name) end
        return a.record.id < b.record.id
    end)
    return rows
end


--- @param row table
--- @return string|nil status, table|nil color
local function statusOf(row)
    local status = EqInfoDisplay.statusText(row.record, row.animal)
    if status ~= nil then return status, EqHorsesFrame.GREY end
    if EqFoals ~= nil and EqFoals.isTooYoungToRide ~= nil and EqFoals.isTooYoungToRide(row.animal) then
        return g_i18n:getText("eq_horses_foal"), EqHorsesFrame.GREY
    end
    return g_i18n:getText("eq_horses_ready"), nil
end


function EqHorsesFrame:refresh()
    local ready = g_currentMission ~= nil
    self.rows = ready and EqHorsesFrame.buildRows(farmId()) or {}
    self.horseList:reloadData()

    local selectIndex = nil
    for i, row in ipairs(self.rows) do
        if self.anchor ~= nil and row.pen == self.anchor and selectIndex == nil then selectIndex = i end
        if self.anchor == nil and row.record.id == self.selectedId then selectIndex = i end
    end
    self.anchor = nil
    selectIndex = selectIndex or (#self.rows > 0 and 1 or nil)
    if selectIndex ~= nil then self.horseList:setSelectedIndex(selectIndex) end
    self:select(selectIndex)

    local empty = ready and #self.rows == 0 and g_i18n:getText("eq_horses_none") or nil
    self.emptyState:setText(empty or "")
    self.emptyState:setVisible(empty ~= nil)
end


--- @param index number|nil
function EqHorsesFrame:select(index)
    self.selectedIndex = index
    local row = index ~= nil and self.rows[index] or nil
    self.selectedId = row ~= nil and row.record.id or self.selectedId
    self:updatePanel()
    self:updateSummary()
    self:updateButtons()
end


--- Collects the look-at Skills box's lines, so the panel shows exactly what that box shows.
--- @return table box
local function lineCollector()
    local box = { eqColored = true, lines = {} }
    function box:addLine(key, value, color, suffix, suffixColor, keyColor)
        table.insert(self.lines, { key = key, value = value, color = color, suffix = suffix,
            suffixColor = suffixColor, keyColor = keyColor })
    end
    return box
end


--- @param row table
--- @return table lines { key, value, color, keyColor }
function EqHorsesFrame.panelLines(row)
    local animal, record = row.animal, row.record
    local box = lineCollector()
    EqInfoDisplay.fillSkillsBox(record, box, animal)
    local lines = {}
    for _, line in ipairs(box.lines) do
        local value = line.value or ""
        -- The panel has one colour per value, so the potential goes in brackets in the skill's colour.
        if line.suffix ~= nil and line.suffix ~= "" then value = value .. " " .. line.suffix end
        table.insert(lines, { key = line.key, value = value, color = line.color, keyColor = line.keyColor })
    end

    local function add(key, value, color)
        if value ~= nil and value ~= "" then table.insert(lines, { key = key, value = value, color = color }) end
    end
    add(g_i18n:getText("eq_horses_stable"), row.where)
    if animal.riding ~= nil then
        add(g_i18n:getText("eq_ui_riding"), string.format("%d%%", math.floor(animal.riding + 0.5)),
            EqInfoDisplay.isRidingFull(animal) and EqInfoDisplay.FULL_COLOR or nil)
    end
    if animal.fitness ~= nil then add(g_i18n:getText("eq_horses_fitness"), string.format("%d%%", math.floor(animal.fitness + 0.5))) end
    if animal.health ~= nil then add(g_i18n:getText("eq_horses_health"), string.format("%d%%", math.floor(animal.health + 0.5))) end
    local career = record.career
    add(g_i18n:getText("eq_horses_career"), string.format(g_i18n:getText("eq_horses_careerValue"), career.starts, career.wins,
        g_i18n:formatMoney(career.earnings or 0, 0, true, true)))
    return lines
end


function EqHorsesFrame:updatePanel()
    local row = self.selectedIndex ~= nil and self.rows[self.selectedIndex] or nil
    self.horsePanel:setVisible(row ~= nil)
    if row == nil then return end

    setText(self.panelName, row.name)
    local subType = row.animal.getSubType ~= nil and row.animal:getSubType() or nil
    local breed = subType ~= nil and subType.fillTypeIndex ~= nil and g_fillTypeManager ~= nil
        and g_fillTypeManager:getFillTypeTitleByIndex(subType.fillTypeIndex) or nil
    local age = EqHorsesFrame.ageText(row.animal.age)
    setText(self.panelSubtitle, breed ~= nil and string.format("%s, %s", breed, age) or age)

    local lines = EqHorsesFrame.panelLines(row)
    for i = 1, #self.lineLabel do
        local line = lines[i]
        setText(self.lineLabel[i], line ~= nil and line.key or "", line ~= nil and line.keyColor or nil)
        setText(self.lineValue[i], line ~= nil and line.value or "", line ~= nil and line.color or nil)
    end
end


function EqHorsesFrame:updateSummary()
    local text = self.message
    if text == nil then
        text = g_i18n:getText(#self.rows == 1 and "eq_horses_summaryOne" or "eq_horses_summary")
        text = string.format(text, #self.rows)
    end
    self.summaryText:setText(text)
end


--- @return table|nil row
function EqHorsesFrame:selectedRow()
    return self.selectedIndex ~= nil and self.rows[self.selectedIndex] or nil
end


function EqHorsesFrame:updateButtons()
    self.menuButtonInfo = { self.backButtonInfo }
    local row = self:selectedRow()
    if row ~= nil then
        if row.pen ~= nil and EqRideButton.isRideable(row.animal) and EqAway.rideBlock(row.animal) == nil then
            table.insert(self.menuButtonInfo, self.rideButtonInfo)
        end
        if isServer() and not row.record.retired then
            self.roleButtonInfo.text = string.format(g_i18n:getText("eq_ui_button_role"), EqRole.text(EqRole.get(row.record)))
            table.insert(self.menuButtonInfo, self.roleButtonInfo)
            table.insert(self.menuButtonInfo, self.retireButtonInfo)
        end
    end
    self:setMenuButtonInfoDirty()
end


-- LIST

function EqHorsesFrame:getNumberOfItemsInSection(_list, _section)
    return #self.rows
end


function EqHorsesFrame:populateCellForItemInSection(_list, _section, index, cell)
    local row = self.rows[index]
    if row == nil then return end
    local record = row.record
    local status, statusColor = statusOf(row)
    local texts = {
        name = row.name,
        role = EqRole.text(EqRole.shown(record)),
        age = EqHorsesFrame.ageText(row.animal.age, true),
        status = status,
    }
    for _, name in ipairs(EqHorsesFrame.CELLS) do
        local element = cell:getAttribute(name)
        if element ~= nil then
            local trained = record.trained[name]
            if trained ~= nil then
                setText(element, tostring(math.floor(trained + 0.5)), EqInfoDisplay.skillColor(trained, name))
            elseif name == "status" then
                setText(element, texts.status, statusColor)
            elseif name == "role" then
                setText(element, texts.role, EqRole.has(record) and EqRole.COLOR or EqInfoDisplay.NO_ROLE_COLOR)
            else
                setText(element, texts[name])
            end
        end
    end
end


function EqHorsesFrame:onListSelectionChanged(_list, _section, index)
    if index ~= self.selectedIndex then
        self.message = nil
        self:select(index)
    end
end


-- BUTTONS

function EqHorsesFrame:onClickRide()
    local row = self:selectedRow()
    if row == nil or row.pen == nil then return end
    EqRideButton.rideAnimal(row.animal, row.pen)
end


function EqHorsesFrame:onClickRole()
    local row = self:selectedRow()
    if row == nil or not isServer() or row.record.retired then return end
    row.record.focus = EqRole.next(EqRole.get(row.record))
    Log:info("EqHorsesFrame: %s '%s' role %s", row.record.id, row.name, row.record.focus)
    self.message = nil
    self:refresh()
end


function EqHorsesFrame:onClickRetire()
    local row = self:selectedRow()
    if row == nil or not isServer() or row.record.retired then return end
    local record = row.record
    YesNoDialog.show(function(_, yes)
        if not yes or record.retired then return end
        local _, message = EqCompetitionManager.setRetired(record, true)
        self.message = message
        self:refresh()
    end, self, string.format(g_i18n:getText("eq_ui_retireConfirm"), row.name), g_i18n:getText("eq_ui_retire"))
end


-- INSTALL

--- Load our frame and register it as a page of a menu (our own, EqMenu).
--- @param menu table
function EqHorsesFrame.addToMenu(menu)
    local frame = EqHorsesFrame.new()
    g_gui:loadGui(modDirectory .. "gui/eqHorsesFrame.xml", EqHorsesFrame.NAME, frame, true)
    EqMenu.addFrame(menu, frame, EqHorsesFrame.ICON_SLICE)
    EqHorsesFrame.menu = menu
    EqHorsesFrame.instance = frame
    Log:info("EqHorsesFrame: Horses tab added")
end

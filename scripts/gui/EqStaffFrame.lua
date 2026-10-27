--[[
    EqStaffFrame.lua
    The Staff tab in RLRM's menu, laid out like the Events tab, with two tabs of its own:
    - Hire: the candidates on offer (EqStaffManager.candidates). Hire takes the selected one on.
    - Your staff: the farm's staff. Works on steps through General, each role your horses have
      and each horse; Let go asks first.
    Left, the people in a table; right, the selected person's job, all ten skills, wage and who
    they work on. Added to RLRM's menu after the Events tab (EqStaffFrame.install), the same way.

    Hiring changes server state, so for now the tab works for a single player or the host; a
    multiplayer client sees a note instead (milestone 7).
]]

EqStaffFrame = {}
local EqStaffFrame_mt = Class(EqStaffFrame, TabbedMenuFrameElement)

local Log = EqLog
local modDirectory = g_currentModDirectory

EqStaffFrame.NAME = "EqStaffFrame"
EqStaffFrame.ICON_SLICE = "eqMenu.staff"

EqStaffFrame.MODE_HIRE = "hire"
EqStaffFrame.MODE_STAFF = "staff"
EqStaffFrame.TAB_MODES = { EqStaffFrame.MODE_HIRE, EqStaffFrame.MODE_STAFF }


--- @return table self
function EqStaffFrame.new()
    local self = EqStaffFrame:superClass().new(nil, EqStaffFrame_mt)
    self.name = EqStaffFrame.NAME
    self.mode = EqStaffFrame.MODE_HIRE
    self.rows = {}
    self.selectedIndex = nil
    self.selectedId = nil
    self.hasCustomMenuButtons = true

    self.backButtonInfo = { inputAction = InputAction.MENU_BACK }
    self.hireButtonInfo = {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("eq_staff_button_hire"),
        callback = function() self:onClickHire() end,
    }
    self.worksButtonInfo = {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("eq_staff_button_worksOn"),
        callback = function() self:onClickWorksOn() end,
    }
    self.fireButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = g_i18n:getText("eq_staff_button_fire"),
        callback = function() self:onClickFire() end,
    }
    self.toggleButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = g_i18n:getText("eq_staff_tab_staff"),
        callback = function() self:onClickToggle() end,
    }
    self.menuButtonInfo = { self.backButtonInfo, self.toggleButtonInfo }
    return self
end


function EqStaffFrame:onGuiSetupFinished()
    EqStaffFrame:superClass().onGuiSetupFinished(self)
    if self.peopleList ~= nil then
        self.peopleList:setDataSource(self)
        self.peopleList:setDelegate(self)
    end
end


--- @return boolean ok
--- @return string|nil reason
local function readiness()
    if g_currentMission == nil then return false, "" end
    if not g_currentMission:getIsServer() then return false, g_i18n:getText("eq_staff_clientNote") end
    return true
end


--- @return number farmId
local function farmId()
    return g_currentMission:getFarmId()
end


function EqStaffFrame:onFrameOpen()
    EqStaffFrame:superClass().onFrameOpen(self)
    EqEventsFrame.applyHeaderIcon(self, EqStaffFrame.ICON_SLICE)
    self:initializeSubCategoryPages()
    self:refresh()
    if self.peopleList ~= nil then FocusManager:setFocus(self.peopleList) end
end


function EqStaffFrame:update(dt)
    EqStaffFrame:superClass().update(self, dt)
    EqEventsFrame.applyHeaderIcon(self, EqStaffFrame.ICON_SLICE)
end


-- TABS (as on the Events tab)

local function tabIndex(mode)
    return mode == EqStaffFrame.MODE_STAFF and 2 or 1
end


function EqStaffFrame:initializeSubCategoryPages()
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
    self.subCategoryPaging:setTexts(texts)
    if self.subCategoryBox ~= nil then
        self.subCategoryBox:invalidateLayout()
        self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)
    end
    self.subCategoryPaging:setState(tabIndex(self.mode), false)
end


function EqStaffFrame:onSubCategoryChanged(state)
    local index = self.subCategoryPaging ~= nil and tonumber(self.subCategoryPaging.texts[state]) or nil
    local mode = index ~= nil and EqStaffFrame.TAB_MODES[index] or nil
    if mode == nil or mode == self.mode then return end
    self.mode = mode
    self.message = nil
    self.selectedId = nil
    self:refresh()
end


function EqStaffFrame:showMode(mode)
    if self.subCategoryPaging ~= nil and self.subCategoryPaging.texts ~= nil and #self.subCategoryPaging.texts > 0 then
        self.subCategoryPaging:setState(tabIndex(mode), true)
    elseif mode ~= self.mode then
        self.mode = mode
        self.message = nil
        self.selectedId = nil
        self:refresh()
    end
end


function EqStaffFrame:onClickHireTab()
    self:showMode(EqStaffFrame.MODE_HIRE)
end


function EqStaffFrame:onClickStaffTab()
    self:showMode(EqStaffFrame.MODE_STAFF)
end


function EqStaffFrame:onClickToggle()
    self:showMode(self.mode == EqStaffFrame.MODE_HIRE and EqStaffFrame.MODE_STAFF or EqStaffFrame.MODE_HIRE)
end


-- TEXTS

--- @param job string
--- @return string
function EqStaffFrame.jobText(job)
    return g_i18n:getText("eq_staff_job_" .. job)
end


--- @param skill string
--- @return string
function EqStaffFrame.skillName(skill)
    if EqInfoDisplay.STAT_COLOR[skill] ~= nil then return g_i18n:getText("eq_stat_" .. skill) end
    return g_i18n:getText("eq_staff_skill_" .. skill)
end


--- @param works table|nil worksOn
--- @return string
function EqStaffFrame.worksText(works)
    if works == nil or works.kind == EqStaff.WORKS_GENERAL then return g_i18n:getText("eq_staff_works_general") end
    if works.kind == EqStaff.WORKS_ROLE then
        return string.format(g_i18n:getText("eq_staff_works_role"), g_i18n:getText("eq_role_" .. tostring(works.role)))
    end
    return tostring(works.name or works.id)
end


--- @param farm number
--- @return table horses { id, role, retired, name } for the farm's horses
local function farmHorses(farm)
    local horses = {}
    for _, animal in ipairs(EqRLRM.listHorsesForFarm(farm)) do
        local record = EqRegistry.getOrCreate(animal)
        if record ~= nil then
            local horse = EqStaffManager.horseInfo(record)
            horse.name = animal.getName ~= nil and animal:getName() or record.id
            if horse.name == "" then horse.name = record.id end
            table.insert(horses, horse)
        end
    end
    return horses
end


--- @param member table
--- @param horses table|nil for the Your staff tab: the farm's horses
--- @return table row
local function personRow(member, horses)
    local row = {
        member = member,
        name = member.name,
        job = EqStaffFrame.jobText(member.job),
        grade = g_i18n:getText("eq_staff_grade_" .. EqStaff.GRADES[member.grade].name),
        wage = g_i18n:formatMoney(member.wage, 0, true, true),
    }
    if horses ~= nil then
        row.fourth = EqStaff.trains(member.job) and EqStaffFrame.worksText(member.worksOn) or g_i18n:getText("eq_staff_works_passive")
        local count = 0
        for _, horse in ipairs(horses) do
            if EqStaff.targets(member, horse) then count = count + 1 end
        end
        row.covers = count
    else
        local best = {}
        for _, skill in ipairs(EqStaff.bestSkills(member, 3)) do
            table.insert(best, string.format("%s %d", EqStaffFrame.skillName(skill), member.skills[skill] or 0))
        end
        row.fourth = table.concat(best, ", ")
    end
    return row
end


-- REFRESH

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


function EqStaffFrame:refresh()
    local ok, reason = readiness()
    self.isReady = ok
    local isHire = self.mode == EqStaffFrame.MODE_HIRE
    self.rows = {}
    self.horses = {}
    if ok then
        if isHire then
            for _, member in ipairs(EqStaffManager.candidates) do table.insert(self.rows, personRow(member, nil)) end
        else
            self.horses = farmHorses(farmId())
            for _, member in ipairs(EqStaffManager.membersOf(farmId())) do
                table.insert(self.rows, personRow(member, self.horses))
            end
        end
    end
    setText(self.peopleHeaderFourth, g_i18n:getText(isHire and "eq_staff_col_best" or "eq_staff_col_worksOn"))

    self.peopleList:reloadData()
    local selectIndex = nil
    for i, row in ipairs(self.rows) do
        if row.member.id == self.selectedId then selectIndex = i end
    end
    selectIndex = selectIndex or (#self.rows > 0 and 1 or nil)
    if selectIndex ~= nil then self.peopleList:setSelectedIndex(selectIndex) end
    self:select(selectIndex)

    local empty
    if not ok then
        empty = reason
    elseif #self.rows == 0 then
        empty = g_i18n:getText(isHire and "eq_staff_noCandidates" or "eq_staff_noStaff")
    end
    self.emptyState:setText(empty or "")
    self.emptyState:setVisible(empty ~= nil and empty ~= "")
end


--- @param index number|nil
function EqStaffFrame:select(index)
    self.selectedIndex = index
    local row = index ~= nil and self.rows[index] or nil
    self.selectedId = row ~= nil and row.member.id or self.selectedId
    self:updatePanel()
    self:updateSummary()
    self:updateButtons()
end


function EqStaffFrame:updatePanel()
    local row = self.selectedIndex ~= nil and self.rows[self.selectedIndex] or nil
    self.personPanel:setVisible(row ~= nil)
    if row == nil then return end
    local member = row.member

    setText(self.panelName, member.name)
    setText(self.panelJob, string.format("%s, %s", row.job, row.grade))
    for i, skill in ipairs(EqStaff.SKILLS) do
        local value = member.skills[skill] or 0
        local level = EqStaff.level(value)
        local statColor = EqInfoDisplay.STAT_COLOR[skill]
        setText(self.skillLabel[i], EqStaffFrame.skillName(skill), statColor)
        setText(self.skillValue[i], string.format("%d - %s", value, g_i18n:getText("eq_staff_level_" .. level.word)),
            EqInfoDisplay.bandColor(level.band))
    end
    setText(self.panelWage, string.format(g_i18n:getText("eq_staff_perMonth"), row.wage))

    if self.mode == EqStaffFrame.MODE_STAFF then
        if EqStaff.trains(member.job) then
            setText(self.panelWorksOn, string.format(g_i18n:getText("eq_staff_coversHorses"), row.fourth, row.covers))
        else
            setText(self.panelWorksOn, row.fourth)
        end
    else
        local left = (member.leavesMonth or 0) - EqStaffManager.month
        setText(self.panelWorksOn, g_i18n:getText(left <= 0 and "eq_staff_available_1" or "eq_staff_available_2"))
    end
    setText(self.panelNoteLabel, g_i18n:getText("eq_staff_does"))
    setText(self.panelNote, EqStaffFrame.jobDoes(member.job))
    -- The Works on row reads On offer on the Hire tab.
    setText(self.panelWorksOnLabel, g_i18n:getText(self.mode == EqStaffFrame.MODE_STAFF and "eq_staff_col_worksOn" or "eq_staff_onOffer"))
end


--- @param job string
--- @return string what the job does, one line
function EqStaffFrame.jobDoes(job)
    local info = EqStaff.JOBS[job]
    if info ~= nil and info.event ~= nil then
        local stats = {}
        for _, stat in ipairs(EqStaff.STATS) do
            if info.trains[stat] then table.insert(stats, g_i18n:getText("eq_stat_" .. stat)) end
        end
        return string.format(g_i18n:getText("eq_staff_does_trainer"), stats[1] or "", stats[2] or "")
    end
    return g_i18n:getText("eq_staff_does_" .. job)
end


function EqStaffFrame:updateSummary()
    local text = self.message
    if text == nil and self.isReady then
        local wages = EqStaff.monthlyWages(EqStaffManager.membersOf(farmId()))
        if self.mode == EqStaffFrame.MODE_HIRE then
            text = g_i18n:getText("eq_staff_summary_hire")
        else
            text = string.format(g_i18n:getText("eq_staff_summary_staff"), g_i18n:formatMoney(wages, 0, true, true))
        end
    end
    self.summaryText:setText(text or "")
end


function EqStaffFrame:updateButtons()
    self.toggleButtonInfo.text = g_i18n:getText(self.mode == EqStaffFrame.MODE_HIRE and "eq_staff_tab_staff" or "eq_staff_tab_hire")
    self.menuButtonInfo = { self.backButtonInfo, self.toggleButtonInfo }
    local row = self.selectedIndex ~= nil and self.rows[self.selectedIndex] or nil
    if row ~= nil and self.isReady then
        if self.mode == EqStaffFrame.MODE_HIRE then
            self.hireButtonInfo.text = string.format(g_i18n:getText("eq_staff_button_hire"), row.wage)
            table.insert(self.menuButtonInfo, self.hireButtonInfo)
        else
            if EqStaff.trains(row.member.job) then table.insert(self.menuButtonInfo, self.worksButtonInfo) end
            table.insert(self.menuButtonInfo, self.fireButtonInfo)
        end
    end
    self:setMenuButtonInfoDirty()
end


-- LIST

function EqStaffFrame:getNumberOfItemsInSection(_list, _section)
    return #self.rows
end


function EqStaffFrame:populateCellForItemInSection(_list, _section, index, cell)
    local row = self.rows[index]
    if row == nil then return end
    for _, name in ipairs({ "name", "job", "grade", "fourth", "wage" }) do
        local element = cell:getAttribute(name)
        if element ~= nil then element:setText(row[name] or "") end
    end
end


function EqStaffFrame:onListSelectionChanged(_list, _section, index)
    if index ~= self.selectedIndex then
        self.message = nil
        self:select(index)
    end
end


-- BUTTONS

function EqStaffFrame:onClickHire()
    local row = self.selectedIndex ~= nil and self.rows[self.selectedIndex] or nil
    if row == nil then return end
    local ok, why = EqStaffManager.hire(row.member.id, farmId())
    if ok then
        self.message = string.format(g_i18n:getText("eq_staff_hired"), row.member.name)
        self.selectedId = nil
    elseif why == "unique" then
        self.message = string.format(g_i18n:getText("eq_staff_unique"), row.job)
    else
        self.message = nil
    end
    self:refresh()
end


function EqStaffFrame:onClickWorksOn()
    local row = self.selectedIndex ~= nil and self.rows[self.selectedIndex] or nil
    if row == nil or not EqStaff.trains(row.member.job) then return end
    local options = EqStaff.worksOptions(self.horses or {}, EqRole.ORDER)
    EqStaffManager.setWorksOn(row.member.id, farmId(), EqStaff.nextWorks(options, row.member.worksOn))
    self.message = nil
    self:refresh()
end


function EqStaffFrame:onClickFire()
    local row = self.selectedIndex ~= nil and self.rows[self.selectedIndex] or nil
    if row == nil then return end
    local id = row.member.id
    YesNoDialog.show(function(_, yes)
        if yes and EqStaffManager.fire(id, farmId()) then
            self.message = string.format(g_i18n:getText("eq_staff_letGo"), row.member.name)
            self.selectedId = nil
            self:refresh()
        end
    end, self, string.format(g_i18n:getText("eq_staff_fire_confirm"), row.member.name), g_i18n:getText("eq_staff_button_fire"))
end


-- INSTALL

--- Load our frame and register it after the Events tab in RLRM's menu.
--- @param menu table the RLMenu instance, inside its setupMenuPages
function EqStaffFrame.addToMenu(menu)
    local frame = EqStaffFrame.new()
    g_gui:loadGui(modDirectory .. "gui/eqStaffFrame.xml", EqStaffFrame.NAME, frame, true)

    local paging = menu.pagingElement
    frame.positionOrigin = paging.positionOrigin
    frame.screenAlign = paging.screenAlign
    frame:setSize(unpack(paging.size))
    local root = frame:getRootElement()
    root.positionOrigin = paging.positionOrigin
    root.screenAlign = paging.screenAlign
    root:setSize(unpack(paging.size))

    paging:addElement(frame)
    menu.eqStaffFrame = frame
    EqStaffFrame.instance = frame

    local predicate = function()
        return g_currentMission ~= nil and EqMain.isActive
            and (menu.openMode == nil or menu.openMode == "full")
    end
    menu:registerPage(frame, nil, predicate)
    menu:addPageTab(frame, nil, nil, EqStaffFrame.ICON_SLICE)
    if frame.initialize ~= nil then frame:initialize() end

    paging:updateAbsolutePosition()
    paging:updatePageMapping()
    Log:info("EqStaffFrame: Staff tab added to RLRM's menu")
end


--- Append our page to RLRM's menu setup, after the Events tab. Call after EqEventsFrame.install.
--- @param guarded function main.lua's error guard
function EqStaffFrame.install(guarded)
    local rlMenu = EqRLRM.get("RLMenu")
    rlMenu.setupMenuPages = Utils.appendedFunction(rlMenu.setupMenuPages, function(menu)
        guarded("staff tab", function() EqStaffFrame.addToMenu(menu) end)
    end)
    Log:debug("EqStaffFrame: hooked RLMenu:setupMenuPages")
end

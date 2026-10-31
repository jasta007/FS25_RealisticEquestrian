--[[
    EqDressageEditor.lua
    The in-game editor for the player's own dressage tests (EqDressageTests, James 2026-10-31).

    Near one of our arenas the test key (EQ_DRESSAGE_TEST, Ctrl+L) starts a new test or edits the
    arena's saved one. The horse stands still and the camera looks straight down on the arena,
    C at the top. The opening (A to a halt at X) shows in white, and the option for the next step
    in cyan from where the test has got to:
    - N and M (EQ_DT_PREV, EQ_DT_NEXT) step through the options, nearest first.
    - R (EQ_DT_RANDOM) picks one at random.
    - F (EQ_DT_MODE) swaps between figures and movements on the spot at the letters ahead (a halt,
      a halt and rein back, a piaffe or a pirouette).
    - Enter (EQ_DT_ACCEPT) keeps it; the next options come from its end.
    - Backspace (EQ_DT_UNDO) takes the last step kept back off.
    - The test key again saves: the final centre line to a halt at X is added. A test with every
      step undone deletes the arena's test.
    - The course delete key (Ctrl+Backspace, EqCourseHooks) cancels without saving.
    Getting off the horse saves what was kept, like recording a course.

    The editor keys are only live while editing. The editor runs where the rider is, so it is
    single player for now, like the course editor.

    Part of Realistic Equestrian by Jasta007.
]]

EqDressageEditor = {}

local Log = EqLog

-- Editing ends when the rider has not been seen for this long (they got off).
EqDressageEditor.STALE_MS = 1500
-- The camera over the arena: its view's height covers the arena's length and this many metres
-- more each end.
EqDressageEditor.CAMERA_FOV = 60
EqDressageEditor.CAMERA_MARGIN = 6
EqDressageEditor.CAMERA_FAILED = false

EqDressageEditor.active = nil


local function text(key)
    return g_i18n:getText(key)
end


local function notify(value)
    Log:info("Dressage test editor: %s", value)
    EqLog.try("EqDressageEditor.notify", function()
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, value)
    end)
end


function EqDressageEditor.reset()
    local active = EqDressageEditor.active
    if active ~= nil then EqLog.try("EqDressageEditor.reset camera", EqDressageEditor.cameraOff, active) end
    EqDressageEditor.active = nil
end


--- @return boolean true while a test is being edited
function EqDressageEditor.isEditing()
    return EqDressageEditor.active ~= nil
end


--- @param vehicle table
--- @return boolean true while this horse's rider edits a test: it stands still
function EqDressageEditor.holds(vehicle)
    local active = EqDressageEditor.active
    return active ~= nil and active.vehicle == vehicle
end


--- The arena the horse is at, if it is one of ours.
--- @param vehicle table
--- @return table|nil frame EqDressagePath.frameFor
function EqDressageEditor.arenaFrame(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil then return nil end
    local course = EqDressageHooks.courseFor(vehicle, spec)
    if course == nil or not EqDressage.nearArena(course) then return nil end
    local x = EqDressage.arenaX(course)
    return x ~= nil and EqDressagePath.frameFor(course.markers, x) or nil
end


--- @param vehicle table
--- @return table|nil frame the arena a test can be edited for now: none while a test, round or
--- course recording is under way
function EqDressageEditor.startFrame(vehicle)
    if EqDressageEditor.active ~= nil or EqCourseHooks.isEditing() or EqCourseHooks.dressageActive then return nil end
    if EqCourseHooks.isBusy() then return nil end
    local ok, frame = EqLog.try("EqDressageEditor.arenaFrame", EqDressageEditor.arenaFrame, vehicle)
    return ok and frame or nil
end


-- THE CAMERA ---------------------------------------------------------------------------------

--- Look straight down on the arena, C at the top of the screen.
--- @param active table
function EqDressageEditor.cameraOn(active)
    if EqDressageEditor.CAMERA_FAILED or createCamera == nil or g_cameraManager == nil then return end
    local ok, err = EqLog.try("EqDressageEditor.cameraOn", function()
        local frame = active.frame
        local fov = math.rad(EqDressageEditor.CAMERA_FOV)
        local camera = createCamera("eqDressageTestCamera", fov, 0.5, 2000)
        link(getRootNode(), camera)
        local height = (frame.halfL + EqDressageEditor.CAMERA_MARGIN) / math.tan(fov / 2)
        local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
        local ground = terrain ~= nil and getTerrainHeightAtWorldPos(terrain, frame.cx, 0, frame.cz) or 0
        setWorldTranslation(camera, frame.cx, ground + height, frame.cz)
        -- A camera looks down its -z: z up, y (the screen's top) towards C.
        setDirection(camera, 0, 1, 0, frame.ux, 0, frame.uz)
        g_cameraManager:addCamera(camera, nil, false)
        g_cameraManager:setActiveCamera(camera)
        active.camera = camera
    end)
    if not ok then
        EqDressageEditor.CAMERA_FAILED = true
        Log:warning("Dressage test editor: no camera over the arena (%s)", tostring(err))
    end
end


--- Back to the horse's own camera (unless the player already moved on to another).
--- @param active table
function EqDressageEditor.cameraOff(active)
    local camera = active.camera
    if camera == nil then return end
    active.camera = nil
    if g_cameraManager:getActiveCamera() == camera then
        local vehicle = active.vehicle
        local enterable = vehicle ~= nil and vehicle.spec_enterable or nil
        if enterable ~= nil and vehicle.setActiveCameraIndex ~= nil and enterable.camIndex ~= nil then
            vehicle:setActiveCameraIndex(enterable.camIndex)
        end
    end
    g_cameraManager:removeCamera(camera)
    delete(camera)
end


-- EDITING ------------------------------------------------------------------------------------

--- Start editing the test of the arena the horse is at.
--- @param vehicle table
--- @param frame table
function EqDressageEditor.begin(vehicle, frame)
    local plan = EqDressageTests.planFor(frame)
    local ed = EqDressageTests.newEditor(frame, plan, function(n) return math.random(n) end)
    local active = { vehicle = vehicle, frame = frame, ed = ed, seenAt = g_time or 0 }
    EqDressageEditor.active = active
    EqDressageEditor.cameraOn(active)
    Log:info("Dressage test editor: %s test, %d steps, %d figure options", plan ~= nil and "editing the" or "new",
        #ed.plan.steps, #ed.options.figure)
end


--- Stop editing.
--- @param save boolean keep what was made (or delete the arena's test when every step was undone)
--- @param left boolean|nil the rider got off: keep the saved test rather than delete it
function EqDressageEditor.finish(save, left)
    local active = EqDressageEditor.active
    if active == nil then return end
    EqDressageEditor.active = nil
    EqLog.try("EqDressageEditor.cameraOff", EqDressageEditor.cameraOff, active)
    local ed = active.ed
    if not save then
        notify(text("eq_dt_cancelled"))
        return
    end
    local ok, plan, test = EqLog.try("EqDressageEditor.finished", EqDressageTests.finished, ed)
    if not ok then return end
    if plan ~= nil then
        EqDressageTests.set(active.frame, plan)
        notify(string.format(text("eq_dt_saved"), #test.moves))
    elseif ed.saved and not left then
        EqDressageTests.set(active.frame, nil)
        notify(text("eq_dt_deleted"))
    end
end


--- The test key: start editing near an arena, or save while editing.
--- @param vehicle table
function EqDressageEditor.onTestAction(vehicle)
    local active = EqDressageEditor.active
    if active ~= nil then
        if active.vehicle == vehicle then EqDressageEditor.finish(true) end
        return
    end
    local frame = EqDressageEditor.startFrame(vehicle)
    if frame ~= nil then EqDressageEditor.begin(vehicle, frame) end
end


--- Ctrl+Backspace while editing (from EqCourseHooks.onDeleteAction).
function EqDressageEditor.onCancel()
    EqDressageEditor.finish(false)
end


--- @param fn function (ed)
local function withEditor(vehicle, fn, ...)
    local active = EqDressageEditor.active
    if active == nil or active.vehicle ~= vehicle then return end
    local ok, err = EqLog.try("EqDressageEditor key", fn, active.ed, ...)
    if not ok then Log:warning("Dressage test editor: %s", tostring(err)) end
end


local function ctrlHeld()
    if Input == nil or Input.isKeyPressed == nil then return false end
    return (Input.KEY_lctrl ~= nil and Input.isKeyPressed(Input.KEY_lctrl)) or (Input.KEY_rctrl ~= nil and Input.isKeyPressed(Input.KEY_rctrl))
end


function EqDressageEditor.onPrev(vehicle) withEditor(vehicle, EqDressageTests.cycle, -1) end
function EqDressageEditor.onNext(vehicle) withEditor(vehicle, EqDressageTests.cycle, 1) end
function EqDressageEditor.onRandom(vehicle) withEditor(vehicle, EqDressageTests.random) end
function EqDressageEditor.onMode(vehicle) withEditor(vehicle, EqDressageTests.toggle) end
function EqDressageEditor.onAccept(vehicle) withEditor(vehicle, EqDressageTests.accept) end
function EqDressageEditor.onUndo(vehicle)
    -- Ctrl+Backspace is cancel, not undo.
    if ctrlHeld() then return end
    withEditor(vehicle, EqDressageTests.undo)
end


-- THE KEYS -----------------------------------------------------------------------------------

-- By spec field, action, handler, and whether it is an editor key (live only while editing).
local ACTIONS = {
    { field = "eqDtTestEventId", action = "EQ_DRESSAGE_TEST", handler = "onTestAction" },
    { field = "eqDtPrevEventId", action = "EQ_DT_PREV", handler = "onPrev", editor = true },
    { field = "eqDtNextEventId", action = "EQ_DT_NEXT", handler = "onNext", editor = true },
    { field = "eqDtRandomEventId", action = "EQ_DT_RANDOM", handler = "onRandom", editor = true },
    { field = "eqDtModeEventId", action = "EQ_DT_MODE", handler = "onMode", editor = true },
    { field = "eqDtAcceptEventId", action = "EQ_DT_ACCEPT", handler = "onAccept", editor = true },
    { field = "eqDtUndoEventId", action = "EQ_DT_UNDO", handler = "onUndo", editor = true },
}


--- From EqTrainingHooks.onRegisterActionEvents.
--- @param vehicle table
--- @param spec table spec_rideable
function EqDressageEditor.registerActions(vehicle, spec)
    spec.eqDtShown = nil
    for _, entry in ipairs(ACTIONS) do
        spec[entry.field] = nil
        if InputAction[entry.action] ~= nil then
            local _, id = vehicle:addActionEvent(spec.actionEvents, InputAction[entry.action], vehicle,
                function() EqDressageEditor[entry.handler](vehicle) end, false, true, false, true, nil)
            spec[entry.field] = id
            if id ~= nil then
                g_inputBinding:setActionEventTextPriority(id, entry.editor and GS_PRIO_HIGH or GS_PRIO_LOW)
                g_inputBinding:setActionEventText(id, text("input_" .. entry.action))
            end
        end
    end
    EqDressageEditor.updateActions(vehicle)
end


--- Which keys show and are live, for the state now. Called every frame while drawing.
--- @param vehicle table
function EqDressageEditor.updateActions(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil then return end
    local active = EqDressageEditor.active
    local mine = active ~= nil and active.vehicle == vehicle
    local now = g_time or 0
    -- Whether an arena is near is worked out once a second (courseFor), not every frame.
    if not mine and (spec.eqDtCheckedAt == nil or now - spec.eqDtCheckedAt >= 1000 or now < spec.eqDtCheckedAt) then
        spec.eqDtCheckedAt = now
        local frame = EqDressageEditor.startFrame(vehicle)
        spec.eqDtCanStart = frame ~= nil
        spec.eqDtHasTest = frame ~= nil and EqDressageTests.planFor(frame) ~= nil
    end
    local testText
    if mine then
        testText = text("eq_dt_saveAction")
    elseif spec.eqDtHasTest then
        testText = text("eq_dt_editAction")
    else
        testText = text("eq_dt_newAction")
    end
    local modeText = ""
    if mine then modeText = text(active.ed.mode == "figure" and "eq_dt_modeSpot" or "eq_dt_modeFigure") end
    local state = string.format("%s|%s|%s|%s", testText, modeText, tostring(mine), tostring(spec.eqDtCanStart))
    if spec.eqDtShown == state then return end
    spec.eqDtShown = state
    local binding = g_inputBinding
    for _, entry in ipairs(ACTIONS) do
        local id = spec[entry.field]
        if id ~= nil then
            local live = entry.editor and mine or (not entry.editor and (mine or spec.eqDtCanStart == true))
            binding:setActionEventActive(id, live)
            binding:setActionEventTextVisibility(id, live)
            if entry.action == "EQ_DRESSAGE_TEST" then binding:setActionEventText(id, testText) end
            if entry.action == "EQ_DT_MODE" and mine then binding:setActionEventText(id, modeText) end
        end
    end
end


-- DRAWING ------------------------------------------------------------------------------------

EqDressageEditor.POLE_HEIGHT = 1.5


--- @return number the ground's height under a test point (worked out once)
local function pointY(frame, p)
    if p.wy == nil then
        p.wx, p.wz = EqDressagePath.toWorld(frame, p.x, p.y)
        local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
        p.wy = terrain ~= nil and getTerrainHeightAtWorldPos(terrain, p.wx, 0, p.wz) or 0
    end
    return p.wy
end


--- The name of an option: "20 m circle at B (Trot)", "Halt at E (Walk)".
--- @param option table
--- @return string
function EqDressageEditor.optionText(option)
    local gait = option.kind == "spot" and option.gait or option.figure.gait
    local name
    if option.kind == "spot" then
        name = EqTrainingHooks.figureText({ key = option.style, labels = { option.letter } })
    else
        name = EqTrainingHooks.figureText(option.figure)
    end
    return string.format("%s (%s)", name, text("eq_dressage_gait_" .. gait))
end


--- Draw the option showing (cyan) and, on the first step, the opening (white), from
--- EqCourseHooks.onDraw between the course glow's begin and finish; the editor's notes beside
--- the panel.
--- @param vehicle table
function EqDressageEditor.draw(vehicle)
    local active = EqDressageEditor.active
    if active == nil or active.vehicle ~= vehicle then return end
    active.seenAt = g_time or 0
    local ed, frame = active.ed, active.frame
    local test = EqDressageTests.preview(ed)
    if test ~= nil then
        local opening, option = {}, {}
        for _, p in ipairs(test.pts) do
            local y = pointY(frame, p)
            local point = { x = p.wx, y = y, z = p.wz }
            if p.s <= test.fromS then table.insert(opening, point) end
            if p.s >= test.fromS then table.insert(option, point) end
        end
        local style = { length = function(s) return EqDressagePath.DASH[EqDressagePath.gaitAt(test, s + 1e-6)] end,
            step = function(s) return EqDressagePath.DASH_STEP[EqDressagePath.gaitAt(test, s + 1e-6)] end }
        if #ed.plan.steps == 0 and #opening >= 2 then EqCourseGlow.path(opening, "white", 0, nil, nil, nil, style) end
        if #option >= 2 then EqCourseGlow.path(option, "cyan", test.fromS, nil, nil, nil, style) end
        -- Where the option starts, and its halts and movements on the spot.
        local start = option[1]
        if start ~= nil then EqCourseGlow.pole(start.x, start.y, start.z, EqDressageEditor.POLE_HEIGHT) end
        local run = { test = test, frame = frame }
        for _, e in ipairs(test.events) do
            if (e.kind == "halt" or e.kind == "spot") and (e.s >= test.fromS or #ed.plan.steps == 0) then EqDressageHooks.drawSymbol(run, e) end
        end
    end

    -- Beside the panel, not in the middle: the middle is for alerts.
    local option, index, count = EqDressageTests.current(ed)
    local title = string.format(text(ed.saved and "eq_dt_editing" or "eq_dt_new"), #ed.plan.steps + 1)
    EqTrainingHud.drawPanelNote(title, EqTrainingHud.STAT_COLOR.temperament, true)
    if option ~= nil then
        local kind = text(ed.mode == "figure" and "eq_dt_figure" or "eq_dt_spot")
        local name = EqDressageEditor.optionText(option)
        -- The first step also picks the way the test tracks at C.
        if #ed.plan.steps == 0 and test ~= nil and test.moves[2] ~= nil then name = EqTrainingHooks.figureText(test.moves[2]) .. ", " .. name end
        local line = string.format("%s %d/%d: %s", kind, index, count, name)
        EqTrainingHud.drawPanelNote(line, nil, false)
    else
        EqTrainingHud.drawPanelNote(text("eq_dt_noOptions"), nil, false)
    end
end


--- Each frame (FSBaseMission.update): the rider got off, so editing ends and what was kept is saved.
function EqDressageEditor.update()
    local active = EqDressageEditor.active
    if active == nil then return end
    local now = g_time or 0
    if now - active.seenAt > EqDressageEditor.STALE_MS or now < active.seenAt then
        Log:info("Dressage test editor: rider gone, saving what was kept")
        EqDressageEditor.finish(true, true)
    end
end

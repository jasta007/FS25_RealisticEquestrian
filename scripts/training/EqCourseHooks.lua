--[[
    EqCourseHooks.lua
    Records and edits show jumping courses (EqCourse) in the game.

    Courses are made in an edit mode (James, 2026-10-27). While editing, every show jump on the
    map has no collision, so the rider goes straight through them in order instead of jumping a
    course they don't know yet, and the course's line is drawn with the fence numbers.

    - The record key (EQ_COURSE_RECORD, Ctrl+J) starts a new course, or edits the saved course
      the horse is near. While editing, the same key saves (if recording) and finishes: the
      line goes and the jumps get their collision back. A new course too short to save stays
      recording. (James, 2026-10-27: a separate save key and finish key were too alike.)
    - The rewind key (EQ_COURSE_REWIND, Ctrl+K) drops everything after the recorded point
      nearest the horse (a white line points to it, like AutoDrive's) and records on from there.
    - The delete key (EQ_COURSE_DELETE, Ctrl+Backspace) asks, then deletes the nearby course.
    Getting off the horse leaves edit mode and throws away what was not saved.

    Show jumps are Riding Hall 2k26's shop jumps (and any other "jumps" facility placeable),
    the jumps inside another facility placeable such as the Equestrian Pack's outdoor arena
    (any node with a red and a white flag under it), and map scenery such as Elmcreek's course.
    A jump's line runs between its red and white flags, or across its placement area.

    Recording runs where the rider is (Rideable.onDraw), so it is single player for now.

    Part of Realistic Equestrian by Jasta007.
]]

EqCourseHooks = {}

local Log = EqLog

-- Edit mode ends when the rider has not been seen for this long (they got off).
EqCourseHooks.STALE_MS = 1500
-- The show jumps are listed again this often while editing.
EqCourseHooks.SCAN_MS = 3000
-- A saved course within this many metres of the horse is "nearby": edited or deleted by the keys.
EqCourseHooks.NEAR_RADIUS = 40
EqCourseHooks.NEAR_CHECK_MS = 1000
-- Only the part of a line within this many metres of the horse is drawn.
EqCourseHooks.DRAW_RADIUS = 80
-- The line floats this far over the ground, the fence numbers this far over a jump.
EqCourseHooks.LINE_LIFT = 0.15
EqCourseHooks.NUMBER_LIFT = 2.2
-- A jump with no flags or placement test area is taken as this wide either side of its middle.
EqCourseHooks.DEFAULT_HALF_WIDTH = 2.5
-- How deep under a placeable or node we look for a jump's flags.
EqCourseHooks.FLAG_DEPTH = 6
EqCourseHooks.LINE_COLOR = { 0.2, 0.9, 1 }
EqCourseHooks.TRAIL_COLOR = { 1, 0.6, 0.1 }
EqCourseHooks.NEAREST_COLOR = { 1, 1, 1 }

EqCourseHooks.editing = nil
EqCourseHooks.near = nil
EqCourseHooks.bodies = {}
EqCourseHooks.drawFailed = false
EqCourseHooks.textFailed = false


function EqCourseHooks.reset()
    EqCourseHooks.editing, EqCourseHooks.near, EqCourseHooks.bodies = nil, nil, {}
end


--- @param text string
local function notify(text)
    Log:info("Course: %s", text)
    pcall(function()
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, text)
    end)
end


--- @param key string
--- @return string
local function text(key)
    return g_i18n:getText(key)
end


--- @return number ground height at x, z (y when there is no terrain)
local function groundAt(x, y, z)
    local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
    if terrain ~= nil and terrain ~= 0 and getTerrainHeightAtWorldPos ~= nil then
        local ok, height = pcall(getTerrainHeightAtWorldPos, terrain, x, 0, z)
        if ok and height ~= nil then return height end
    end
    return y
end


--- The red and white flags under a node: Riding Hall and Equestrian Pack jumps carry
--- "modernFlagsRed" and "modernFlagsWhite" at their two ends.
--- @param node number
--- @return number|nil red flag node, number|nil white flag node
local function findFlags(node)
    local red, white = nil, nil
    local stack = { { node, 0 } }
    while #stack > 0 do
        local entry = table.remove(stack)
        local current, depth = entry[1], entry[2]
        local name = getName(current):lower()
        if red == nil and string.find(name, "flagsred", 1, true) then red = current end
        if white == nil and string.find(name, "flagswhite", 1, true) then white = current end
        if red ~= nil and white ~= nil then return red, white end
        if depth < EqCourseHooks.FLAG_DEPTH then
            for i = 0, getNumOfChildren(current) - 1 do table.insert(stack, { getChildAt(current, i), depth + 1 }) end
        end
    end
    return nil, nil
end


local endsCache = {}

--- A jump's two ends in its node's space, from its flags, else its placement test area.
--- Measured once per node.
--- @param node number
--- @param placeable table|nil
--- @return table ends { x1, z1, x2, z2 } in node space
local function jumpEnds(node, placeable)
    local ends = endsCache[node]
    if ends ~= nil then return ends end
    local red, white = findFlags(node)
    if red ~= nil then
        local x1, _, z1 = localToLocal(red, node, 0, 0, 0)
        local x2, _, z2 = localToLocal(white, node, 0, 0, 0)
        ends = { x1, z1, x2, z2 }
    end
    local spec = placeable ~= nil and placeable.spec_placement or nil
    if ends == nil and spec ~= nil and type(spec.testAreas) == "table" then
        for _, area in ipairs(spec.testAreas) do
            if area.startNode ~= nil and area.endNode ~= nil then
                local x1 = localToLocal(area.startNode, node, 0, 0, 0)
                local x2 = localToLocal(area.endNode, node, 0, 0, 0)
                ends = { x1, 0, x2, 0 }
                break
            end
        end
    end
    ends = ends or { -EqCourseHooks.DEFAULT_HALF_WIDTH, 0, EqCourseHooks.DEFAULT_HALF_WIDTH, 0 }
    endsCache[node] = ends
    return ends
end


--- @param list table
--- @param node number
--- @param placeable table|nil
local function addJump(list, node, placeable)
    local x, _, z = getWorldTranslation(node)
    local _, ry = getWorldRotation(node)
    local ends = jumpEnds(node, placeable)
    local ax, _, az = localToWorld(node, ends[1], 0, ends[2])
    local bx, _, bz = localToWorld(node, ends[3], 0, ends[4])
    table.insert(list, { node = node, x = x, z = z, ry = ry, ax = ax, az = az, bx = bx, bz = bz })
end


--- The jumps inside a facility placeable that is not itself a jump (an arena with a course in
--- it): every node with a red and a white flag right under it. Found once per placeable.
--- @param placeable table
--- @return table nodes
local function innerJumps(placeable)
    if placeable.eqInnerJumps ~= nil then return placeable.eqInnerJumps end
    local nodes = {}
    local stack = { { placeable.rootNode, 0 } }
    while #stack > 0 do
        local entry = table.remove(stack)
        local node, depth = entry[1], entry[2]
        local red, white = false, false
        for i = 0, getNumOfChildren(node) - 1 do
            local name = getName(getChildAt(node, i)):lower()
            if string.find(name, "flagsred", 1, true) then red = true end
            if string.find(name, "flagswhite", 1, true) then white = true end
        end
        if red and white then
            table.insert(nodes, node)
        elseif depth < 12 then
            for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, { getChildAt(node, i), depth + 1 }) end
        end
    end
    placeable.eqInnerJumps = nodes
    if #nodes > 0 then Log:info("Course: %d jump(s) inside %s", #nodes, tostring(placeable.configFileName)) end
    return nodes
end


--- @return table every show jump on the map: { node, x, z, ry, ax, az, bx, bz }
function EqCourseHooks.listJumps()
    local list = {}
    for _, entry in ipairs(EqFacilityHooks.listPlaceables()) do
        local placeable = entry.placeable
        if placeable.rootNode ~= nil then
            if entry.kind == "jumps" then
                addJump(list, placeable.rootNode, placeable)
            else
                for _, node in ipairs(innerJumps(placeable)) do addJump(list, node, nil) end
            end
        end
    end
    for _, point in ipairs(EqFacilityHooks.mapPoints or {}) do
        if point.kind == "jumps" and point.node ~= nil and (entityExists == nil or entityExists(point.node)) then
            addJump(list, point.node, nil)
        end
    end
    return list
end


--- Take the collision off everything under a jump's node, keeping it to put back.
--- @param node number
local function collisionOff(node)
    if EqCourseHooks.bodies[node] ~= nil or setRigidBodyType == nil or getRigidBodyType == nil then return end
    local none = RigidBodyType ~= nil and RigidBodyType.NONE or "NoRigidBody"
    local bodies = {}
    local stack = { node }
    while #stack > 0 do
        local current = table.remove(stack)
        local okType, kind = pcall(getRigidBodyType, current)
        if okType and kind ~= nil and kind ~= none and kind ~= "NoRigidBody" then
            if pcall(setRigidBodyType, current, none) then table.insert(bodies, { node = current, kind = kind }) end
        end
        for i = 0, getNumOfChildren(current) - 1 do table.insert(stack, getChildAt(current, i)) end
    end
    EqCourseHooks.bodies[node] = bodies
end


--- Every jump gets its collision back.
local function collisionOnAll()
    for _, bodies in pairs(EqCourseHooks.bodies) do
        for _, body in ipairs(bodies) do
            if entityExists == nil or entityExists(body.node) then pcall(setRigidBodyType, body.node, body.kind) end
        end
    end
    EqCourseHooks.bodies = {}
end


--- List the jumps (again) and take their collision off.
--- @param editing table
local function scanJumps(editing)
    editing.scannedAt = g_time or 0
    editing.jumps = EqCourseHooks.listJumps()
    for _, jump in ipairs(editing.jumps) do
        local ok, err = pcall(collisionOff, jump.node)
        if not ok then Log:warning("Course jump collision: %s", tostring(err)) end
    end
end


--- @return boolean true while editing a course
function EqCourseHooks.isEditing()
    return EqCourseHooks.editing ~= nil
end


--- @param vehicle table
--- @return table|nil the saved course near the horse, number|nil its index
function EqCourseHooks.nearCourse(vehicle)
    local now = g_time or 0
    local near = EqCourseHooks.near
    if near == nil or now - near.at >= EqCourseHooks.NEAR_CHECK_MS or now < near.at then
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        local course, index = EqCourse.nearest(x, z, EqCourseHooks.NEAR_RADIUS)
        near = { at = now, course = course, index = index }
        EqCourseHooks.near = near
    end
    if near.course ~= nil and EqCourse.list[near.index] ~= near.course then return nil end
    return near.course, near.index
end


--- Enter edit mode.
--- @param vehicle table
--- @param index number|nil the saved course to edit, nil for a new one
local function startEditing(vehicle, index)
    local editing = { vehicle = vehicle, index = index, seenAt = g_time or 0 }
    if index ~= nil then
        local course = EqCourse.list[index]
        editing.name = course.name
        editing.course = EqCourse.editRecording(course)
        editing.recording = false
    else
        local x, y, z = getWorldTranslation(vehicle.rootNode)
        editing.name = EqCourse.nextName(text("eq_course_name"))
        editing.course = EqCourse.newRecording(x, groundAt(x, y, z), z)
        editing.recording = true
    end
    EqCourseHooks.editing = editing
    scanJumps(editing)
    Log:info("Course: editing %s '%s', %d show jump(s) on the map without collision", index ~= nil and "saved" or "new",
        editing.name, #editing.jumps)
    if #editing.jumps == 0 then
        notify(text("eq_course_noJumps"))
    else
        notify(string.format(text(index ~= nil and "eq_course_editStarted" or "eq_course_started"), editing.name))
    end
end


--- Save what is being edited. A new course with too few fences is not saved.
--- @param editing table
--- @return boolean true when saved
local function save(editing)
    local vehicle = editing.vehicle
    if editing.recording and vehicle.rootNode ~= nil then
        local x, y, z = getWorldTranslation(vehicle.rootNode)
        EqCourse.recordStep(editing.course, x, groundAt(x, y, z), z, true)
    end
    local course = EqCourse.finish(editing.course, editing.name)
    if course == nil then
        notify(string.format(text("eq_course_tooFew"), EqCourse.MIN_JUMPS))
        return false
    end
    if editing.index ~= nil and EqCourse.list[editing.index] ~= nil then
        EqCourse.replace(editing.index, course)
    else
        EqCourse.add(course)
        editing.index = #EqCourse.list
    end
    -- Carry on editing the copy just saved.
    editing.course = EqCourse.editRecording(course)
    editing.recording = false
    EqCourseHooks.near = nil
    Log:info("Course: saved '%s', %d jump(s), %d point(s), %.0f m", course.name, #course.jumps, #course.points, course.length)
    notify(string.format(text("eq_course_saved"), course.name, #course.jumps, course.length))
    return true
end


--- Back to the recorded point nearest the horse, recording on from there.
--- @param editing table
local function rewind(editing)
    local vehicle = editing.vehicle
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local index, distance = EqCourse.nearestPoint(editing.course, x, z)
    local points, jumps = EqCourse.rewind(editing.course, index)
    local was = editing.recording
    editing.recording = true
    Log:info("Course: rewound to point %d (%.1f m away), dropped %d point(s) and %d fence(s)", index, distance, points, jumps)
    if was or points > 0 then
        notify(string.format(text("eq_course_rewound"), #editing.course.jumps))
    else
        notify(text("eq_course_resumed"))
    end
end


--- Leave edit mode: the jumps get their collision back and the line goes.
--- @param why string|nil a notification text key, nil to say nothing
local function stopEditing(why)
    EqCourseHooks.editing = nil
    EqCourseHooks.near = nil
    collisionOnAll()
    if why ~= nil then notify(text(why)) end
end


--- The record key: a new course, edit the nearby one, or save and finish.
--- @param vehicle table
function EqCourseHooks.onRecordAction(vehicle)
    if vehicle.rootNode == nil then return end
    local editing = EqCourseHooks.editing
    if editing == nil then
        local _, index = EqCourseHooks.nearCourse(vehicle)
        startEditing(vehicle, index)
    elseif editing.vehicle ~= vehicle then
        return
    elseif not editing.recording or save(editing) then
        stopEditing("eq_course_finished")
    end
    EqCourseHooks.updateActions(vehicle)
end


--- The rewind key.
--- @param vehicle table
function EqCourseHooks.onRewindAction(vehicle)
    local editing = EqCourseHooks.editing
    if editing == nil or editing.vehicle ~= vehicle or vehicle.rootNode == nil then return end
    rewind(editing)
    EqCourseHooks.updateActions(vehicle)
end


--- The delete key: ask, then delete the nearby course.
--- @param vehicle table
function EqCourseHooks.onDeleteAction(vehicle)
    if EqCourseHooks.editing ~= nil or vehicle.rootNode == nil then return end
    local course, index = EqCourseHooks.nearCourse(vehicle)
    if course == nil then return end
    local question = string.format(text("eq_course_deleteAsk"), course.name, #course.jumps, course.length or 0)
    local function confirmed(yes)
        if not yes or EqCourse.list[index] ~= course then return end
        EqCourse.remove(index)
        EqCourseHooks.near = nil
        notify(string.format(text("eq_course_deleted"), course.name))
        EqCourseHooks.updateActions(vehicle)
    end
    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        YesNoDialog.show(confirmed, nil, question, text("eq_course_deleteTitle"), nil, nil,
            DialogElement ~= nil and DialogElement.TYPE_QUESTION or nil)
    else
        -- No dialog: a second press within 3 seconds deletes.
        local now = g_time or 0
        if EqCourseHooks.deleteArmed == course and now - (EqCourseHooks.deleteArmedAt or 0) < 3000 then
            EqCourseHooks.deleteArmed = nil
            confirmed(true)
        else
            EqCourseHooks.deleteArmed, EqCourseHooks.deleteArmedAt = course, now
            notify(question)
        end
    end
end


-- The keys, by spec field, action and handler; registered from EqTrainingHooks.
local ACTIONS = {
    { field = "eqCourseEventId", action = "EQ_COURSE_RECORD", handler = "onRecordAction" },
    { field = "eqRewindEventId", action = "EQ_COURSE_REWIND", handler = "onRewindAction" },
    { field = "eqDeleteEventId", action = "EQ_COURSE_DELETE", handler = "onDeleteAction" },
}


--- Appended to Rideable:onRegisterActionEvents (through EqTrainingHooks): the course keys.
--- @param vehicle table
--- @param spec table spec_rideable
function EqCourseHooks.registerActions(vehicle, spec)
    spec.eqCourseShown = nil
    for _, entry in ipairs(ACTIONS) do
        spec[entry.field] = nil
        if InputAction[entry.action] ~= nil then
            local _, id = vehicle:addActionEvent(spec.actionEvents, InputAction[entry.action], vehicle,
                function() EqCourseHooks[entry.handler](vehicle) end, false, true, false, true, nil)
            spec[entry.field] = id
            if id ~= nil then g_inputBinding:setActionEventTextPriority(id, GS_PRIO_LOW) end
        end
    end
    EqCourseHooks.updateActions(vehicle)
end


--- Set the course keys' texts and which of them show, for the state now.
--- @param vehicle table
function EqCourseHooks.updateActions(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil or vehicle.rootNode == nil then return end
    local editing = EqCourseHooks.editing
    local mine = editing ~= nil and editing.vehicle == vehicle
    local near = editing == nil and EqCourseHooks.nearCourse(vehicle) or nil
    local recordText
    if mine then
        recordText = editing.recording and text("eq_course_saveAction") or text("eq_course_doneAction")
    elseif near ~= nil then
        recordText = string.format(text("eq_course_editAction"), near.name)
    else
        recordText = text("eq_course_recordAction")
    end
    local state = string.format("%s|%s|%s", recordText, tostring(mine), tostring(near ~= nil))
    if spec.eqCourseShown == state then return end
    spec.eqCourseShown = state
    local binding = g_inputBinding
    if spec.eqCourseEventId ~= nil then binding:setActionEventText(spec.eqCourseEventId, recordText) end
    if spec.eqRewindEventId ~= nil then
        binding:setActionEventText(spec.eqRewindEventId, text("input_EQ_COURSE_REWIND"))
        binding:setActionEventTextVisibility(spec.eqRewindEventId, mine)
    end
    if spec.eqDeleteEventId ~= nil then
        binding:setActionEventText(spec.eqDeleteEventId, near ~= nil and string.format(text("eq_course_deleteAction"), near.name) or "")
        binding:setActionEventTextVisibility(spec.eqDeleteEventId, near ~= nil)
    end
end


--- Follow the horse: drop trail points and note jumps passed through.
--- @param editing table
--- @param vehicle table
local function step(editing, vehicle)
    local now = g_time or 0
    if now - editing.scannedAt >= EqCourseHooks.SCAN_MS or now < editing.scannedAt then
        -- Jumps placed while editing join in (and lose their collision too).
        scanJumps(editing)
    end
    local x, y, z = getWorldTranslation(vehicle.rootNode)
    local last = editing.last
    editing.last = { x, z }
    if not editing.recording or last == nil then return end
    local course = editing.course
    local passed = false
    for _, jump in ipairs(editing.jumps) do
        local side = EqCourse.crossSide(jump.ax, jump.az, jump.bx, jump.bz, last[1], last[2], x, z)
        if side ~= nil then
            local number = EqCourse.addJump(course, jump, side, now)
            if number ~= nil then
                passed = true
                Log:info("Course: fence %d at %.1f, %.1f (side %d)", number, jump.x, jump.z, side)
                EqTrainingHud.pop("courseFence", number)
            end
        end
    end
    EqCourse.recordStep(course, x, groundAt(x, y, z), z, passed)
end


--- @param points table
--- @param color table
--- @param x number horse position
--- @param z number
local function drawLine(points, color, x, z)
    if EqCourseHooks.drawFailed or drawDebugLine == nil then return end
    local radius2 = EqCourseHooks.DRAW_RADIUS * EqCourseHooks.DRAW_RADIUS
    local lift = EqCourseHooks.LINE_LIFT
    local ok, err = pcall(function()
        for i = 2, #points do
            local a, b = points[i - 1], points[i]
            local dx, dz = b.x - x, b.z - z
            if dx * dx + dz * dz <= radius2 then
                drawDebugLine(a.x, a.y + lift, a.z, color[1], color[2], color[3], b.x, b.y + lift, b.z, color[1], color[2], color[3], true)
            end
        end
    end)
    if not ok then
        EqCourseHooks.drawFailed = true
        Log:warning("Course line drawing unavailable: %s", tostring(err))
    end
end


--- Fence numbers over the jumps of a course (one label per jump, "3, 10" when ridden twice).
--- @param jumps table
local function drawNumbers(jumps)
    if EqCourseHooks.textFailed or Utils == nil or Utils.renderTextAtWorldPosition == nil then return end
    local ok, err = pcall(function()
        for _, label in ipairs(EqCourse.labels(jumps)) do
            local y = groundAt(label.x, 0, label.z)
            Utils.renderTextAtWorldPosition(label.x, y + EqCourseHooks.NUMBER_LIFT, label.z, label.text, getCorrectTextSize(0.025), 0)
        end
    end)
    if not ok then
        EqCourseHooks.textFailed = true
        Log:warning("Course fence numbers unavailable: %s", tostring(err))
    end
end


--- Called from EqTrainingHooks.onDraw for the ridden horse: edit mode's recording and lines.
--- @param vehicle table
function EqCourseHooks.onDraw(vehicle)
    if vehicle.rootNode == nil then return end
    EqCourseHooks.updateActions(vehicle)
    local editing = EqCourseHooks.editing
    if editing == nil or editing.vehicle ~= vehicle then return end
    editing.seenAt = g_time or 0
    step(editing, vehicle)

    local x, y, z = getWorldTranslation(vehicle.rootNode)
    local course = editing.course
    if editing.recording then
        drawLine(course.points, EqCourseHooks.TRAIL_COLOR, x, z)
    else
        if editing.smoothed == nil or editing.smoothedFrom ~= course then
            editing.smoothed, editing.smoothedFrom = EqCourse.smooth(course.points), course
        end
        drawLine(editing.smoothed, EqCourseHooks.LINE_COLOR, x, z)
    end
    drawNumbers(course.jumps)
    -- Where the rewind key would go back to.
    local nearest = course.points[EqCourse.nearestPoint(course, x, z)]
    drawLine({ { x = x, y = groundAt(x, y, z), z = z }, nearest }, EqCourseHooks.NEAREST_COLOR, x, z)
    local key = editing.recording and "eq_course_recording" or "eq_course_editing"
    -- Beside the panel, not in the middle: the middle is for alerts.
    EqTrainingHud.drawPanelNote(string.format(text(key), editing.name, #course.jumps, course.length), EqTrainingHud.STAT_COLOR.agility, true)
    EqTrainingHud.drawPanelNote(text("eq_course_collisionNote"), nil, false)
end


--- Each frame: edit mode ends when the rider gets off, throwing away what was not saved.
function EqCourseHooks.update()
    local editing = EqCourseHooks.editing
    if editing == nil then return end
    local now = g_time or 0
    if now - editing.seenAt > EqCourseHooks.STALE_MS or now < editing.seenAt then
        stopEditing(editing.recording and "eq_course_cancelled" or "eq_course_finished")
    end
end

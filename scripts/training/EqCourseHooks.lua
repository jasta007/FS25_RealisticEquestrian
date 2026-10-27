--[[
    EqCourseHooks.lua
    Records and edits show jumping courses (EqCourse) in the game.

    Courses are made in an edit mode (James, 2026-10-27). While editing, every show jump on the
    map has no collision, so the rider goes straight through them in order instead of jumping a
    course they don't know yet, and the course's line is drawn with the fence numbers.

    - The record key (EQ_COURSE_RECORD, Ctrl+J) starts a new course, or edits the saved course
      the horse is near. While recording, the same key saves; while editing but not recording,
      it records on from the nearest point.
    - The rewind key (EQ_COURSE_REWIND, Ctrl+K) drops everything after the recorded point
      nearest the horse (a white line points to it, like AutoDrive's) and records on from there.
    - The finish key (EQ_COURSE_FINISH, Ctrl+L) saves and leaves edit mode: the line goes and
      the jumps get their collision back.
    - The delete key (EQ_COURSE_DELETE, Ctrl+Backspace) asks, then deletes the nearby course.
    Getting off the horse leaves edit mode and throws away what was not saved.

    Show jumps are Riding Hall 2k26's shop jumps (and any other "jumps" facility placeable),
    the jumps inside another facility placeable such as the Equestrian Pack's outdoor arena
    (any node with a red and a white flag under it), and map scenery such as Elmcreek's course.
    A jump's line runs between its red and white flags, or across its placement area.

    Out of edit mode, near a saved course the horse rides a timed round (EqShowJumping): "Move
    to the start line to begin Show Jumping", a 3, 2, 1 countdown, then the fences in order with
    the next one tagged on the map and the way to it drawn. A placed start or finish line
    (placeables/courseLines) close to where the course begins or ends is used, else one is made
    12 m before fence 1 and after the last fence.

    Recording and rounds run where the rider is (Rideable.onDraw), so they are single player for now.

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
-- In a round: the way to the next fence, and the start and finish lines.
EqCourseHooks.ROUND_COLOR = { 1, 0.85, 0.2 }
EqCourseHooks.START_COLOR = { 0.3, 1, 0.3 }
EqCourseHooks.FINISH_COLOR = { 1, 0.3, 0.3 }
-- The way to the next fence is drawn as a band of lines this far apart, so it reads as solid.
EqCourseHooks.BAND = { -0.12, -0.06, 0, 0.06, 0.12 }
-- In a round the way to the next fence stops this far short of it (its pointIndex is just past
-- the fence), and the fence's label stands beside its white flag.
EqCourseHooks.WAY_SHORT = 5
EqCourseHooks.ROUND_NUMBER_LIFT = 1.8
EqCourseHooks.NUMBER_ASIDE = 1.5
-- The start line is tagged on the map only until the horse is this close (the game draws the
-- tag on the line itself).
EqCourseHooks.TAG_CLOSE = 25
-- A course saved before fence points were kept: a fence's point is the first one within this
-- many metres of it.
EqCourseHooks.PASS_NEAR = 6
-- A placed start or finish line counts for a course within this many metres of the line the
-- course would make itself.
EqCourseHooks.LINE_RADIUS = 30
EqCourseHooks.LINE_FILES = {
    start = "placeables/courselines/coursestartline.xml",
    finish = "placeables/courselines/coursefinishline.xml",
}

EqCourseHooks.editing = nil
EqCourseHooks.round = nil
EqCourseHooks.near = nil
EqCourseHooks.bodies = {}
EqCourseHooks.drawFailed = false
EqCourseHooks.textFailed = false


function EqCourseHooks.reset()
    EqCourseHooks.editing, EqCourseHooks.near, EqCourseHooks.bodies = nil, nil, {}
    EqCourseHooks.round, EqCourseHooks.judged, EqCourseHooks.crashed, EqCourseHooks.payoff = nil, nil, false, 0
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
    EqCourseHooks.round = nil
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


--- The record key: a new course, edit the nearby one, save, or record on.
--- @param vehicle table
function EqCourseHooks.onRecordAction(vehicle)
    if vehicle.rootNode == nil then return end
    local editing = EqCourseHooks.editing
    if editing == nil then
        local _, index = EqCourseHooks.nearCourse(vehicle)
        startEditing(vehicle, index)
    elseif editing.vehicle ~= vehicle then
        return
    elseif editing.recording then
        save(editing)
    else
        rewind(editing)
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


--- The finish key: save and leave edit mode.
--- @param vehicle table
function EqCourseHooks.onFinishAction(vehicle)
    local editing = EqCourseHooks.editing
    if editing == nil or editing.vehicle ~= vehicle then return end
    -- A new course with too few fences is left behind, not saved.
    if editing.recording then save(editing) end
    stopEditing("eq_course_finished")
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
    { field = "eqFinishEventId", action = "EQ_COURSE_FINISH", handler = "onFinishAction" },
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
        recordText = editing.recording and text("eq_course_saveAction") or text("eq_course_resumeAction")
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
    if spec.eqFinishEventId ~= nil then
        binding:setActionEventText(spec.eqFinishEventId, text("input_EQ_COURSE_FINISH"))
        binding:setActionEventTextVisibility(spec.eqFinishEventId, mine)
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
--- @param labels table|nil { x, z, text } to draw instead
--- @param lift number|nil metres over the ground, NUMBER_LIFT when nil
local function drawNumbers(jumps, labels, lift)
    if EqCourseHooks.textFailed or Utils == nil or Utils.renderTextAtWorldPosition == nil then return end
    local ok, err = pcall(function()
        for _, label in ipairs(labels or EqCourse.labels(jumps)) do
            local y = groundAt(label.x, 0, label.z)
            Utils.renderTextAtWorldPosition(label.x, y + (lift or EqCourseHooks.NUMBER_LIFT), label.z, label.text, getCorrectTextSize(0.025), 0)
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
    if editing == nil then
        EqCourseHooks.roundDraw(vehicle)
        return
    end
    if editing.vehicle ~= vehicle then return end
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
    EqTrainingHud.drawPrompt(string.format(text(key), editing.name, #course.jumps, course.length), 1, EqTrainingHud.STAT_COLOR.agility)
end


--- A placed start or finish line's two posts, red end a and white end b.
--- @param placeable table
--- @return table|nil line { ax, az, bx, bz, x, z }
local function placedLine(placeable)
    local red, white = nil, nil
    local stack = { placeable.rootNode }
    while #stack > 0 and (red == nil or white == nil) do
        local node = table.remove(stack)
        local name = getName(node)
        if name == "eqLineRed" then red = node elseif name == "eqLineWhite" then white = node end
        for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
    end
    if red == nil or white == nil then return nil end
    local ax, _, az = getWorldTranslation(red)
    local bx, _, bz = getWorldTranslation(white)
    return { ax = ax, az = az, bx = bx, bz = bz, x = (ax + bx) / 2, z = (az + bz) / 2 }
end


--- The placed line of a kind nearest a line made from the path, turned so the horse rides it
--- the right way: towards fence 1 over a start line, away from the last fence over a finish.
--- @param kind string "start" or "finish"
--- @param made table the line made from the path
--- @param fence table the course's first (start) or last (finish) fence
--- @return table|nil
local function findPlacedLine(kind, made, fence)
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return nil end
    local file = EqCourseHooks.LINE_FILES[kind]
    local best, bestDistance = nil, EqCourseHooks.LINE_RADIUS
    for _, placeable in ipairs(system.placeables) do
        local config = placeable.configFileName ~= nil and placeable.configFileName:lower():gsub("\\", "/") or ""
        if placeable.rootNode ~= nil and config:sub(-#file) == file then
            local line = placedLine(placeable)
            if line ~= nil then
                local dx, dz = line.x - made.x, line.z - made.z
                local d = math.sqrt(dx * dx + dz * dz)
                if d <= bestDistance then best, bestDistance = line, d end
            end
        end
    end
    if best == nil then return nil end
    -- However it was put down, fence 1 lies past a start line and the last fence before a finish.
    local past = EqShowJumping.sideOf(best, fence.x, fence.z) == 1
    if (kind == "start") ~= past then
        best.ax, best.az, best.bx, best.bz = best.bx, best.bz, best.ax, best.az
    end
    return best
end


--- Fill in what a course saved by an earlier version lacks: each fence's point on the path
--- (the nearest one after the fence before, so a jump ridden twice gets two), its ends from the
--- jumps on the map, and then the side it is jumped from, read off the path.
--- @param course table
local function fillEnds(course)
    local points = course.points
    local from = 1
    for _, jump in ipairs(course.jumps) do
        if jump.pointIndex == nil then
            -- The first pass close by, not the nearest overall: a jump ridden twice is passed
            -- twice, and the later pass may happen to be closer.
            local best, bestDistance = nil, math.huge
            local nearest, nearestDistance = from, math.huge
            for i = from, #points do
                local dx, dz = points[i].x - jump.x, points[i].z - jump.z
                local d = dx * dx + dz * dz
                if d < nearestDistance then nearest, nearestDistance = i, d end
                if d <= EqCourseHooks.PASS_NEAR ^ 2 and d < bestDistance then
                    best, bestDistance = i, d
                elseif best ~= nil then
                    break
                end
            end
            jump.pointIndex = best or nearest
        end
        from = math.max(from, jump.pointIndex)
    end
    local live = nil
    for _, jump in ipairs(course.jumps) do
        if jump.ax == nil then
            live = live or EqCourseHooks.listJumps()
            for _, found in ipairs(live) do
                if EqCourse.sameJump(jump, found) then
                    jump.ax, jump.az, jump.bx, jump.bz = found.ax, found.az, found.bx, found.bz
                    -- The path before the fence says which way it was ridden.
                    local before = points[math.max(1, jump.pointIndex - 2)]
                    if before ~= nil then jump.side = EqShowJumping.sideOf(jump, before.x, before.z) end
                    break
                end
            end
        end
    end
end


--- A new round on a course, with any placed start and finish lines.
--- @param vehicle table
--- @param course table
--- @return table
local function newRound(vehicle, course)
    fillEnds(course)
    local start = findPlacedLine("start", EqShowJumping.startFromPath(course), course.jumps[1])
    local finish = findPlacedLine("finish", EqShowJumping.finishFromPath(course), course.jumps[#course.jumps])
    local sj = EqShowJumping.newRound(course, start, finish)
    Log:info("Show jumping: round on '%s', %d fence(s), time allowed %d s, %s start line, %s finish line", course.name,
        #course.jumps, sj.allowed, start ~= nil and "placed" or "path", finish ~= nil and "placed" or "path")
    return { vehicle = vehicle, course = course, sj = sj, seenAt = g_time or 0 }
end


--- Judged jumps and crashes from EqTrainingHooks, for the round's next frame.
--- @param result string "clear", "knock" or "nothing"
function EqCourseHooks.onJumpJudged(result)
    if EqCourseHooks.round ~= nil then EqCourseHooks.judged = result end
end


function EqCourseHooks.onCrash()
    if EqCourseHooks.round ~= nil then EqCourseHooks.crashed = true end
end


--- Agility effort earned by a finished round, handed over once (EqTrainingHooks adds it).
--- @return number
function EqCourseHooks.takePayoff()
    local effort = EqCourseHooks.payoff or 0
    EqCourseHooks.payoff = 0
    return effort
end


--- @param seconds number
--- @return string "52.3 s"
local function secondsText(seconds)
    return string.format("%.1f s", seconds)
end


--- Tell the rider what the round just did.
--- @param round table
--- @param event string from EqShowJumping.step
local function announce(round, event)
    local sj = round.sj
    if event == "count" then
        EqTrainingHud.pop("showJumping", tostring(sj.count))
    elseif event == "go" then
        EqTrainingHud.pop("showJumping", text("eq_sj_go"))
    elseif event == "early" then
        notify(text("eq_sj_early"))
    elseif event == "started" then
        Log:info("Show jumping: started '%s'", round.course.name)
    elseif event == "fence" then
        -- A clear fence: the jump's own combo pop says so, the panel counts on.
        Log:info("Show jumping: fence %d of %d clear", sj.next - 1, #round.course.jumps)
    elseif event == "rail" then
        EqTrainingHud.pop("showJumping", string.format(text("eq_sj_rail"), sj.faults))
    elseif event == "runout" then
        Log:info("Show jumping: run-out at fence %d (past its flags)", sj.next)
        EqTrainingHud.pop("showJumping", string.format(text("eq_sj_runout"), sj.faults))
    elseif event == "refusal" then
        EqTrainingHud.pop("showJumping", string.format(text("eq_sj_refusal"), sj.faults))
    elseif event == "eliminated" then
        local why = sj.result.eliminated
        Log:info("Show jumping: eliminated (%s) after %.1f s", why, sj.result.seconds)
        local message = why == "wrongCourse" and string.format(text("eq_sj_out_wrongCourse"), sj.why)
            or text("eq_sj_out_" .. why)
        notify(message)
        EqTrainingHud.pop("showJumping", text("eq_sj_eliminated"))
    elseif event == "finished" then
        local result = sj.result
        local effort = EqShowJumping.payoff(result)
        EqCourseHooks.payoff = (EqCourseHooks.payoff or 0) + effort
        Log:info("Show jumping: finished '%s' in %.1f s (allowed %d), %d fault(s) + %d time fault(s), agility effort %.3f",
            round.course.name, result.seconds, sj.allowed, result.faults, result.timeFaults, effort)
        local message = result.clear and string.format(text("eq_sj_clear"), secondsText(result.seconds))
            or string.format(text("eq_sj_faults"), result.total, secondsText(result.seconds))
        notify(message)
        EqTrainingHud.pop("showJumping", result.clear and text("eq_sj_clearPop") or string.format(text("eq_sj_faultsPop"), result.total))
    end
end


--- A line across the ground between a line's two ends, with a post at each.
--- @param line table
--- @param color table
local function drawCrossing(line, color, x, z)
    local ya = groundAt(line.ax, 0, line.az)
    local yb = groundAt(line.bx, 0, line.bz)
    for _, lift in ipairs({ 0.1, 0.2, 0.3 }) do
        drawLine({ { x = line.ax, y = ya + lift, z = line.az }, { x = line.bx, y = yb + lift, z = line.bz } }, color, x, z)
    end
    drawLine({ { x = line.ax, y = ya, z = line.az }, { x = line.ax, y = ya + 2, z = line.az } }, color, x, z)
    drawLine({ { x = line.bx, y = yb, z = line.bz }, { x = line.bx, y = yb + 2, z = line.bz } }, color, x, z)
end


--- The way from one path index to another, smoothed and drawn as a band.
--- @param round table
--- @param from number
--- @param to number
local function drawWay(round, from, to, x, z, short)
    local key = from .. ":" .. to
    if round.wayKey ~= key then
        local slice = {}
        local points = round.course.points
        for i = math.max(1, from), math.min(#points, to) do table.insert(slice, points[i]) end
        local way = #slice >= 2 and EqCourse.smooth(slice) or slice
        -- Stop short of the fence, so the line doesn't run through the jump.
        local left = short or 0
        while left > 0 and #way > 2 do
            local a, b = way[#way - 1], way[#way]
            local dx, dz = b.x - a.x, b.z - a.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d > left then
                way[#way] = { x = b.x - dx / d * left, y = b.y, z = b.z - dz / d * left }
                break
            end
            left = left - d
            table.remove(way)
        end
        round.way, round.wayKey = way, key
    end
    local way = round.way
    if #way < 2 then return end
    for _, offset in ipairs(EqCourseHooks.BAND) do
        local band = {}
        for i, p in ipairs(way) do
            local q = way[math.min(#way, i + 1)]
            local r = way[math.max(1, i - 1)]
            local tx, tz = q.x - r.x, q.z - r.z
            local d = math.sqrt(tx * tx + tz * tz)
            if d < 1e-6 then tx, tz, d = 0, 1, 1 end
            band[i] = { x = p.x - tz / d * offset, y = p.y + 0.05, z = p.z + tx / d * offset }
        end
        drawLine(band, EqCourseHooks.ROUND_COLOR, x, z)
    end
end


--- Where the round tags the map: the start line until the clock runs, then the next fence.
--- @return table|nil { x, z }, string|nil its name
function EqCourseHooks.tagTarget()
    local round = EqCourseHooks.round
    if round == nil then return nil, nil end
    local sj = round.sj
    if sj.state == "approach" or sj.state == "countdown" or sj.state == "go" then
        local last = round.last
        if last ~= nil then
            local dx, dz = last[1] - sj.start.x, last[2] - sj.start.z
            if dx * dx + dz * dz < EqCourseHooks.TAG_CLOSE ^ 2 then return nil, nil end
        end
        return sj.start, text("eq_sj_startLine")
    end
    if sj.state == "running" then
        -- No tag on the fences: the game draws it right in front of the jump (James, 2026-10-27).
        -- The label over the next fence and the way to it show where to go.
        if round.course.jumps[sj.next] == nil and sj.finish ~= nil then return sj.finish, text("eq_sj_finishLine") end
    end
    return nil, nil
end


--- The round's rows in the riding panel.
--- @param rows table
function EqCourseHooks.roundRows(rows)
    local round = EqCourseHooks.round
    if round == nil or round.sj.state ~= "running" then return end
    local sj = round.sj
    local color = EqTrainingHud.STAT_COLOR.agility
    local jumps = #round.course.jumps
    table.insert(rows, { left = string.format(text("eq_sj_fenceRow"), math.min(sj.next, jumps), jumps), leftColor = color,
        right = string.format(text("eq_sj_faultsRow"), sj.faults), rightColor = sj.faults > 0 and EqTrainingHud.COLOR.orange or color })
    local seconds = sj.clock / 1000
    table.insert(rows, { left = text("eq_sj_timeRow"), leftColor = color,
        right = string.format("%s / %d s", secondsText(seconds), sj.allowed),
        rightColor = seconds > sj.allowed and EqTrainingHud.COLOR.red or color })
end


--- Out of edit mode, each frame for the ridden horse: the round on the nearby course.
--- @param vehicle table
function EqCourseHooks.roundDraw(vehicle)
    local now = g_time or 0
    local round = EqCourseHooks.round
    local course, _ = EqCourseHooks.nearCourse(vehicle)
    if round ~= nil and (round.vehicle ~= vehicle or round.course ~= course) then
        -- Away from the course (or onto another): a round under way is over.
        if round.sj.state == "running" or round.sj.state == "go" then notify(text("eq_sj_retired")) end
        round = nil
        EqCourseHooks.round = nil
    end
    if course == nil or #course.jumps < EqCourse.MIN_JUMPS then return end
    if round == nil then
        round = newRound(vehicle, course)
        EqCourseHooks.round = round
        EqCourseHooks.judged, EqCourseHooks.crashed = nil, false
    end

    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local dt = round.at ~= nil and math.max(0, math.min(200, now - round.at)) or 0
    local last = round.last or { x, z }
    round.at, round.last, round.seenAt = now, { x, z }, now
    local sj = round.sj
    local event = EqShowJumping.step(sj, { px = last[1], pz = last[2], x = x, z = z, dt = dt,
        judged = EqCourseHooks.judged, crashed = EqCourseHooks.crashed })
    EqCourseHooks.judged, EqCourseHooks.crashed = nil, false
    if event ~= nil then announce(round, event) end

    local state = sj.state
    if state == "approach" or state == "countdown" or state == "go" then
        drawCrossing(sj.start, EqCourseHooks.START_COLOR, x, z)
        local _, from = EqShowJumping.startFromPath(round.course)
        drawWay(round, from, round.course.jumps[1].pointIndex or from, x, z, EqCourseHooks.WAY_SHORT)
        if state == "approach" then
            EqTrainingHud.drawPrompt(text("eq_sj_begin"), nil, EqTrainingHud.STAT_COLOR.agility)
        elseif state == "countdown" then
            EqTrainingHud.drawPrompt(text("eq_sj_ready"), sj.countMs / EqShowJumping.COUNT_MS, EqTrainingHud.STAT_COLOR.agility)
        else
            EqTrainingHud.drawPrompt(text("eq_sj_cross"), sj.goMs / EqShowJumping.GO_MS, EqTrainingHud.STAT_COLOR.agility)
        end
    elseif state == "running" then
        local jumps = round.course.jumps
        local fence = jumps[sj.next]
        local previous = jumps[sj.next - 1]
        if fence ~= nil then
            local from = previous ~= nil and previous.pointIndex or select(2, EqShowJumping.startFromPath(round.course))
            drawWay(round, from, fence.pointIndex or from, x, z, EqCourseHooks.WAY_SHORT)
            -- The gold line across the fence between its flags, like the start line (James's
            -- pick), and its number beside the white flag rather than over the poles.
            drawCrossing(fence, EqCourseHooks.ROUND_COLOR, x, z)
            local dx, dz = fence.bx - fence.ax, fence.bz - fence.az
            local d = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
            local out = EqCourseHooks.NUMBER_ASIDE
            drawNumbers(nil, { { x = fence.bx + dx / d * out, z = fence.bz + dz / d * out,
                text = string.format(text("eq_pop_courseFence"), sj.next) } }, EqCourseHooks.ROUND_NUMBER_LIFT)
        elseif sj.finish ~= nil then
            local _, to = EqShowJumping.finishFromPath(round.course)
            drawWay(round, previous.pointIndex or to, to, x, z)
            drawCrossing(sj.finish, EqCourseHooks.FINISH_COLOR, x, z)
        end
    elseif state == "done" and sj.result ~= nil then
        local result = sj.result
        local message
        if result.eliminated ~= nil then
            message = text("eq_sj_eliminated")
        elseif result.clear then
            message = string.format(text("eq_sj_clear"), secondsText(result.seconds))
        else
            message = string.format(text("eq_sj_faults"), result.total, secondsText(result.seconds))
        end
        EqTrainingHud.drawPrompt(message, sj.restMs / EqShowJumping.REST_MS, EqTrainingHud.STAT_COLOR.agility)
    end
end


--- Each frame: edit mode ends when the rider gets off, throwing away what was not saved.
function EqCourseHooks.update()
    local now = g_time or 0
    local round = EqCourseHooks.round
    if round ~= nil and (now - round.seenAt > EqCourseHooks.STALE_MS or now < round.seenAt) then
        if round.sj.state == "running" or round.sj.state == "go" then notify(text("eq_sj_retired")) end
        EqCourseHooks.round = nil
    end
    local editing = EqCourseHooks.editing
    if editing == nil then return end
    if now - editing.seenAt > EqCourseHooks.STALE_MS or now < editing.seenAt then
        stopEditing(editing.recording and "eq_course_cancelled" or "eq_course_finished")
    end
end

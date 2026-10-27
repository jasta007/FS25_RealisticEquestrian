--[[
    EqCourseHooks.lua
    Records show jumping courses (EqCourse) in the game, and draws the saved ones.

    The record key (EQ_COURSE_RECORD) starts a recording on the ridden horse: every show jump
    on the map (a "jumps" facility placeable, such as Riding Hall 2k26's) loses its collision,
    so the rider goes straight through them in order instead of jumping a course they don't
    know yet (James, 2026-10-27). Each frame the horse's position feeds the trail, and crossing
    a jump's line between its ends adds that jump to the course. The key again saves it;
    getting off throws it away. Collision comes back either way. While recording, a line runs
    from the horse to the nearest recorded point, and the rewind key (EQ_COURSE_REWIND) drops
    everything after that point and carries on from it, like AutoDrive's.

    Near a saved course the line is drawn on the ground with the fence numbers above the jumps.
    Recording runs where the rider is (Rideable.onDraw), so it is single player for now.

    Part of Realistic Equestrian by Jasta007.
]]

EqCourseHooks = {}

local Log = EqLog

-- A recording whose rider has not been seen for this long (they got off) is thrown away.
EqCourseHooks.STALE_MS = 1500
-- The show jumps are listed again this often while recording.
EqCourseHooks.SCAN_MS = 3000
-- A saved course within this many metres of the horse is drawn.
EqCourseHooks.SHOW_RADIUS = 40
EqCourseHooks.SHOW_CHECK_MS = 1000
-- Only the part of a line within this many metres of the horse is drawn.
EqCourseHooks.DRAW_RADIUS = 80
-- The line floats this far over the ground, the fence numbers this far over a jump.
EqCourseHooks.LINE_LIFT = 0.15
EqCourseHooks.NUMBER_LIFT = 2.2
-- A jump with no placement test area is taken as this wide either side of its middle.
EqCourseHooks.DEFAULT_HALF_WIDTH = 2.5
EqCourseHooks.LINE_COLOR = { 0.2, 0.9, 1 }
EqCourseHooks.TRAIL_COLOR = { 1, 0.6, 0.1 }
EqCourseHooks.NEAREST_COLOR = { 1, 1, 1 }

EqCourseHooks.recording = nil
EqCourseHooks.shown = nil
EqCourseHooks.drawFailed = false
EqCourseHooks.textFailed = false


function EqCourseHooks.reset()
    EqCourseHooks.recording, EqCourseHooks.shown = nil, nil
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


--- @param x number
--- @param z number
--- @return number ground height
local function groundAt(x, y, z)
    local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
    if terrain ~= nil and terrain ~= 0 and getTerrainHeightAtWorldPos ~= nil then
        local ok, height = pcall(getTerrainHeightAtWorldPos, terrain, x, 0, z)
        if ok and height ~= nil then return height end
    end
    return y
end


--- A show jump's line in its own space: its poles run along local x, through local z = 0.
--- Measured from the placement test area, once.
--- @param placeable table
--- @return number minX, number maxX
local function jumpEnds(placeable)
    if placeable.eqJumpEnds ~= nil then return placeable.eqJumpEnds[1], placeable.eqJumpEnds[2] end
    local minX, maxX = -EqCourseHooks.DEFAULT_HALF_WIDTH, EqCourseHooks.DEFAULT_HALF_WIDTH
    local spec = placeable.spec_placement
    if spec ~= nil and type(spec.testAreas) == "table" then
        for _, area in ipairs(spec.testAreas) do
            if area.startNode ~= nil and area.endNode ~= nil then
                local x1 = localToLocal(area.startNode, placeable.rootNode, 0, 0, 0)
                local x2 = localToLocal(area.endNode, placeable.rootNode, 0, 0, 0)
                minX, maxX = math.min(x1, x2), math.max(x1, x2)
                break
            end
        end
    end
    placeable.eqJumpEnds = { minX, maxX }
    return minX, maxX
end


--- @return table every show jump placeable: { placeable, node, x, z, ry, minX, maxX }
function EqCourseHooks.listJumps()
    local list = {}
    for _, entry in ipairs(EqFacilityHooks.listPlaceables()) do
        local placeable = entry.placeable
        if entry.kind == "jumps" and placeable.rootNode ~= nil then
            local x, _, z = getWorldTranslation(placeable.rootNode)
            local _, ry = getWorldRotation(placeable.rootNode)
            local minX, maxX = jumpEnds(placeable)
            table.insert(list, { placeable = placeable, node = placeable.rootNode, x = x, z = z, ry = ry, minX = minX, maxX = maxX })
        end
    end
    return list
end


--- Take the collision off every show jump in the list that still has it.
--- @param jumps table from listJumps
local function collisionOff(jumps)
    for _, jump in ipairs(jumps) do
        local ok, err = pcall(EqDressageHooks.removeCollision, jump.placeable)
        if not ok then Log:warning("Course jump collision: %s", tostring(err)) end
    end
end


--- @param jumps table from listJumps
local function collisionOn(jumps)
    for _, jump in ipairs(jumps) do
        pcall(EqDressageHooks.restoreCollision, jump.placeable)
    end
end


--- @return boolean true while recording
function EqCourseHooks.isRecording()
    return EqCourseHooks.recording ~= nil
end


--- @param vehicle table the ridden horse
function EqCourseHooks.start(vehicle)
    if vehicle.rootNode == nil then return end
    local x, y, z = getWorldTranslation(vehicle.rootNode)
    local jumps = EqCourseHooks.listJumps()
    collisionOff(jumps)
    EqCourseHooks.recording = { vehicle = vehicle, course = EqCourse.newRecording(x, groundAt(x, y, z), z), jumps = jumps,
        prev = {}, seenAt = g_time or 0, scannedAt = g_time or 0 }
    Log:info("Course: recording started at %.1f, %.1f, %d show jump(s) on the map without collision", x, z, #jumps)
    notify(#jumps > 0 and text("eq_course_started") or text("eq_course_noJumps"))
end


--- Save the recording, or say why it could not be.
function EqCourseHooks.finish()
    local recording = EqCourseHooks.recording
    if recording == nil then return end
    EqCourseHooks.recording = nil
    collisionOn(recording.jumps)
    local vehicle = recording.vehicle
    if vehicle.rootNode ~= nil then
        local x, y, z = getWorldTranslation(vehicle.rootNode)
        EqCourse.recordStep(recording.course, x, groundAt(x, y, z), z, true)
    end
    local course = EqCourse.finish(recording.course, EqCourse.nextName(text("eq_course_name")))
    if course == nil then
        notify(string.format(text("eq_course_tooFew"), EqCourse.MIN_JUMPS))
        return
    end
    EqCourse.add(course)
    EqCourseHooks.shown = nil
    Log:info("Course: saved '%s', %d jump(s), %d point(s), %.0f m", course.name, #course.jumps, #course.points, course.length)
    notify(string.format(text("eq_course_saved"), course.name, #course.jumps, course.length))
end


--- Throw the recording away (the rider got off).
function EqCourseHooks.cancel()
    local recording = EqCourseHooks.recording
    if recording == nil then return end
    EqCourseHooks.recording = nil
    collisionOn(recording.jumps)
    notify(text("eq_course_cancelled"))
end


--- The rewind key was pressed: back to the recorded point nearest the horse.
--- @param vehicle table
function EqCourseHooks.onRewindAction(vehicle)
    local recording = EqCourseHooks.recording
    if recording == nil or recording.vehicle ~= vehicle or vehicle.rootNode == nil then return end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local index, distance = EqCourse.nearestPoint(recording.course, x, z)
    local points, jumps = EqCourse.rewind(recording.course, index)
    Log:info("Course: rewound to point %d (%.1f m away), dropped %d point(s) and %d fence(s)", index, distance, points, jumps)
    notify(string.format(text("eq_course_rewound"), #recording.course.jumps))
end


--- The record key was pressed.
--- @param vehicle table
function EqCourseHooks.onRecordAction(vehicle)
    if EqCourseHooks.recording ~= nil then
        EqCourseHooks.finish()
    else
        EqCourseHooks.start(vehicle)
    end
    local spec = vehicle.spec_rideable
    if spec ~= nil and spec.eqCourseEventId ~= nil then
        g_inputBinding:setActionEventText(spec.eqCourseEventId, EqCourseHooks.actionText())
    end
    if spec ~= nil and spec.eqRewindEventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(spec.eqRewindEventId, EqCourseHooks.isRecording())
    end
end


--- @return string the record key's text in the help panel
function EqCourseHooks.actionText()
    return text(EqCourseHooks.recording ~= nil and "eq_course_finishAction" or "eq_course_recordAction")
end


--- Follow the horse: drop trail points and note jumps passed through.
--- @param recording table
--- @param vehicle table
local function step(recording, vehicle)
    local now = g_time or 0
    recording.seenAt = now
    if now - recording.scannedAt >= EqCourseHooks.SCAN_MS or now < recording.scannedAt then
        -- Jumps placed while recording join in (and lose their collision too).
        recording.scannedAt = now
        local jumps = EqCourseHooks.listJumps()
        collisionOff(jumps)
        recording.jumps = jumps
    end
    local x, y, z = getWorldTranslation(vehicle.rootNode)
    local course = recording.course
    local passed = false
    for _, jump in ipairs(recording.jumps) do
        if entityExists == nil or entityExists(jump.node) then
            local lx, _, lz = worldToLocal(jump.node, x, y, z)
            local prev = recording.prev[jump.node]
            local side = prev ~= nil and EqCourse.passSide(prev[1], prev[2], lx, lz, jump.minX, jump.maxX) or nil
            recording.prev[jump.node] = { lx, lz }
            if side ~= nil then
                local number = EqCourse.addJump(course, jump, side, now)
                if number ~= nil then
                    passed = true
                    Log:info("Course: fence %d at %.1f, %.1f (from the %s side)", number, jump.x, jump.z, side > 0 and "+z" or "-z")
                    EqTrainingHud.pop("courseFence", number)
                end
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


--- Called from EqTrainingHooks.onDraw for the ridden horse: records, or draws a nearby course.
--- @param vehicle table
function EqCourseHooks.onDraw(vehicle)
    if vehicle.rootNode == nil then return end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local recording = EqCourseHooks.recording
    if recording ~= nil and recording.vehicle == vehicle then
        step(recording, vehicle)
        drawLine(recording.course.points, EqCourseHooks.TRAIL_COLOR, x, z)
        -- Where the rewind key would go back to.
        local index = EqCourse.nearestPoint(recording.course, x, z)
        local nearest = recording.course.points[index]
        local _, y = getWorldTranslation(vehicle.rootNode)
        drawLine({ { x = x, y = groundAt(x, y, z), z = z }, nearest }, EqCourseHooks.NEAREST_COLOR, x, z)
        drawNumbers(recording.course.jumps)
        EqTrainingHud.drawPrompt(string.format(text("eq_course_recording"), #recording.course.jumps, recording.course.length), 1,
            EqTrainingHud.STAT_COLOR.agility)
        return
    end

    local now = g_time or 0
    local shown = EqCourseHooks.shown
    if shown == nil or now - shown.at >= EqCourseHooks.SHOW_CHECK_MS or now < shown.at then
        local course = EqCourse.nearest(x, z, EqCourseHooks.SHOW_RADIUS)
        if shown == nil or shown.course ~= course then
            shown = { course = course, line = course ~= nil and EqCourse.smooth(course.points) or nil }
            if course ~= nil then Log:info("Course: showing '%s' (%d jumps)", course.name, #course.jumps) end
        end
        shown.at = now
        EqCourseHooks.shown = shown
    end
    if shown.course ~= nil then
        drawLine(shown.line, EqCourseHooks.LINE_COLOR, x, z)
        drawNumbers(shown.course.jumps)
    end
end


--- Each frame: a recording whose rider got off is thrown away.
function EqCourseHooks.update()
    local recording = EqCourseHooks.recording
    if recording == nil then return end
    local now = g_time or 0
    if now - recording.seenAt > EqCourseHooks.STALE_MS or now < recording.seenAt then EqCourseHooks.cancel() end
end

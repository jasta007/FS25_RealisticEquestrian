--[[
    EqCourse.lua
    Show jumping courses recorded by riding them: pure functions with no game calls, so they
    run headless. EqCourseHooks takes the show jumps' collision off, feeds the horse's position
    in each frame, and draws the saved line.

    Recording works like a GPS trail (James, 2026-10-27, after AutoDrive's recorder): a point is
    dropped once the horse is far enough from the last one, and how far depends on how sharply
    it is turning (POINT_SPACING), so straights stay light and tight turns stay accurate. The
    jumps are ridden through with their collision off, in order; each one passed is kept with
    the side it was taken from. A smooth curve through the points (smooth) is only for drawing.

    A course is { name, points = { {x, y, z}... }, jumps = { {x, z, ry, side}... }, length }.
    A jump is kept by where its placeable stands and which way it faces, so a jump moved in
    construction mode is no longer part of the course.

    Part of Realistic Equestrian by Jasta007.
]]

EqCourse = {}

-- Saved courses, in the order they were recorded.
EqCourse.list = {}

-- How far from the last point the next is dropped, by how many degrees the horse has turned
-- from the last leg: the first row whose angle is above the turn sets the spacing (metres).
EqCourse.POINT_SPACING = {
    { angle = 2, spacing = 10 },
    { angle = 5, spacing = 5 },
    { angle = 10, spacing = 3 },
    { angle = 20, spacing = 1.5 },
    { angle = 180, spacing = 0.75 },
}
-- The first point after the start is dropped this far out.
EqCourse.FIRST_SPACING = 3
-- A horse passes through a jump when it crosses the jump's line (local z = 0) between its ends,
-- with this much to spare either side, and moves less than PASS_MAX_STEP along z in one frame.
EqCourse.PASS_MARGIN = 0.75
EqCourse.PASS_MAX_STEP = 4
-- The same jump passed again this soon (milliseconds) is the horse wobbling across its line.
EqCourse.PASS_REPEAT_MS = 4000
-- A show jumping course needs this many jumps.
EqCourse.MIN_JUMPS = 2
EqCourse.MAX_COURSES = 50
-- Drawing: one smoothed point about every SMOOTH_STEP metres.
EqCourse.SMOOTH_STEP = 1


function EqCourse.reset()
    EqCourse.list = {}
end


--- @param x number
--- @param y number
--- @param z number
--- @return table recording
function EqCourse.newRecording(x, y, z)
    return { points = { { x = x, y = y, z = z } }, jumps = {}, length = 0 }
end


--- @param ax number
--- @param az number
--- @param bx number
--- @param bz number
--- @return number degrees between the two directions, 0 to 180
function EqCourse.turnAngle(ax, az, bx, bz)
    local la, lb = math.sqrt(ax * ax + az * az), math.sqrt(bx * bx + bz * bz)
    if la < 1e-6 or lb < 1e-6 then return 0 end
    local cos = (ax * bx + az * bz) / (la * lb)
    cos = math.max(-1, math.min(1, cos))
    return math.deg(math.acos(cos))
end


--- @param angle number degrees turned
--- @return number metres before the next point
function EqCourse.spacingFor(angle)
    for _, row in ipairs(EqCourse.POINT_SPACING) do
        if angle <= row.angle then return row.spacing end
    end
    return EqCourse.POINT_SPACING[#EqCourse.POINT_SPACING].spacing
end


--- @param recording table
--- @param x number
--- @param y number
--- @param z number
--- @param force boolean|nil drop a point here whatever the spacing (at a jump)
--- @return boolean true when a point was dropped
function EqCourse.recordStep(recording, x, y, z, force)
    local points = recording.points
    local last = points[#points]
    local dx, dz = x - last.x, z - last.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance < 0.05 then return false end
    local spacing
    if #points < 2 then
        spacing = EqCourse.FIRST_SPACING
    else
        local before = points[#points - 1]
        spacing = EqCourse.spacingFor(EqCourse.turnAngle(last.x - before.x, last.z - before.z, dx, dz))
    end
    if not force and distance < spacing then return false end
    table.insert(points, { x = x, y = y, z = z })
    recording.length = recording.length + distance
    return true
end


--- Whether the horse went through a jump between two frames, in the jump's own space (its
--- poles run along local x).
--- @param prevX number
--- @param prevZ number
--- @param x number
--- @param z number
--- @param minX number the jump's ends along local x
--- @param maxX number
--- @return number|nil the side it came from: 1 from +z, -1 from -z; nil when it did not pass
function EqCourse.passSide(prevX, prevZ, x, z, minX, maxX)
    if prevZ == nil or (prevZ > 0) == (z > 0) or prevZ == 0 then return nil end
    if math.abs(z - prevZ) > EqCourse.PASS_MAX_STEP then return nil end
    local share = prevZ / (prevZ - z)
    local crossX = prevX + (x - prevX) * share
    if crossX < minX - EqCourse.PASS_MARGIN or crossX > maxX + EqCourse.PASS_MARGIN then return nil end
    return prevZ > 0 and 1 or -1
end


--- Note a jump passed through. A jump can be in a course more than once, but not twice running
--- within PASS_REPEAT_MS.
--- @param recording table
--- @param jump table { x, z, ry } where the jump stands
--- @param side number from passSide
--- @param now number milliseconds
--- @return number|nil the jump's number in the course, nil when ignored
function EqCourse.addJump(recording, jump, side, now)
    local last = recording.jumps[#recording.jumps]
    if last ~= nil and EqCourse.sameJump(last, jump) and now - (last.at or 0) < EqCourse.PASS_REPEAT_MS then
        last.at = now
        return nil
    end
    -- The point dropped at the jump (EqCourseHooks drops one right after), for rewind.
    table.insert(recording.jumps, { x = jump.x, z = jump.z, ry = jump.ry or 0, side = side, at = now,
        pointIndex = #recording.points + 1 })
    return #recording.jumps
end


--- @param recording table
--- @param x number
--- @param z number
--- @return number index of the recorded point nearest (x, z), number its distance
function EqCourse.nearestPoint(recording, x, z)
    local bestIndex, best = 1, math.huge
    for i, point in ipairs(recording.points) do
        local dx, dz = point.x - x, point.z - z
        local d = dx * dx + dz * dz
        if d < best then bestIndex, best = i, d end
    end
    return bestIndex, math.sqrt(best)
end


--- Go back to a point: everything recorded after it, points and jumps, is dropped, and the
--- recording carries on from there (James, 2026-10-27, like AutoDrive's line to the nearest point).
--- @param recording table
--- @param index number point to keep as the last
--- @return number points dropped, number jumps dropped
function EqCourse.rewind(recording, index)
    local points, jumps = recording.points, recording.jumps
    index = math.max(1, math.min(#points, index))
    local droppedPoints, droppedJumps = #points - index, 0
    for i = #points, index + 1, -1 do points[i] = nil end
    for i = #jumps, 1, -1 do
        if (jumps[i].pointIndex or 0) > index then
            table.remove(jumps, i)
            droppedJumps = droppedJumps + 1
        end
    end
    recording.length = EqCourse.pathLength(points)
    return droppedPoints, droppedJumps
end


--- @param a table jump { x, z }
--- @param b table
--- @return boolean true when they stand in the same place
function EqCourse.sameJump(a, b)
    return math.abs(a.x - b.x) < 0.5 and math.abs(a.z - b.z) < 0.5
end


--- @return string the next free name: "Course 1", "Course 2"...
function EqCourse.nextName(format)
    format = format or "Course %d"
    local taken = {}
    for _, course in ipairs(EqCourse.list) do taken[course.name] = true end
    local n = 1
    while taken[string.format(format, n)] do n = n + 1 end
    return string.format(format, n)
end


--- End a recording.
--- @param recording table
--- @param name string
--- @return table|nil course, string|nil why not ("jumps" when too few were passed)
function EqCourse.finish(recording, name)
    if #recording.jumps < EqCourse.MIN_JUMPS then return nil, "jumps" end
    local jumps = {}
    for _, jump in ipairs(recording.jumps) do
        table.insert(jumps, { x = jump.x, z = jump.z, ry = jump.ry, side = jump.side })
    end
    return { name = name, points = recording.points, jumps = jumps, length = recording.length }
end


--- Keep a finished course; the oldest goes once there are MAX_COURSES.
--- @param course table
function EqCourse.add(course)
    table.insert(EqCourse.list, course)
    while #EqCourse.list > EqCourse.MAX_COURSES do table.remove(EqCourse.list, 1) end
end


--- @param index number
--- @return table|nil the removed course
function EqCourse.remove(index)
    if EqCourse.list[index] == nil then return nil end
    return table.remove(EqCourse.list, index)
end


--- @param points table
--- @return number metres along the points
function EqCourse.pathLength(points)
    local length = 0
    for i = 2, #points do
        local dx, dz = points[i].x - points[i - 1].x, points[i].z - points[i - 1].z
        length = length + math.sqrt(dx * dx + dz * dz)
    end
    return length
end


--- A smooth curve through the points (Catmull-Rom), about SMOOTH_STEP metres apart, for drawing.
--- @param points table
--- @return table points { x, y, z }
function EqCourse.smooth(points)
    local count = #points
    if count < 3 then return points end
    local out = { { x = points[1].x, y = points[1].y, z = points[1].z } }
    for i = 1, count - 1 do
        local p0, p1, p2, p3 = points[math.max(1, i - 1)], points[i], points[i + 1], points[math.min(count, i + 2)]
        local dx, dz = p2.x - p1.x, p2.z - p1.z
        local steps = math.max(1, math.floor(math.sqrt(dx * dx + dz * dz) / EqCourse.SMOOTH_STEP + 0.5))
        for s = 1, steps do
            local t = s / steps
            local t2, t3 = t * t, t * t * t
            local function at(key)
                return 0.5 * (2 * p1[key] + (-p0[key] + p2[key]) * t + (2 * p0[key] - 5 * p1[key] + 4 * p2[key] - p3[key]) * t2
                    + (-p0[key] + 3 * p1[key] - 3 * p2[key] + p3[key]) * t3)
            end
            table.insert(out, { x = at("x"), y = at("y"), z = at("z") })
        end
    end
    return out
end


--- @param course table
--- @param x number
--- @param z number
--- @return number metres from (x, z) to the course's nearest point
function EqCourse.distanceTo(course, x, z)
    local best = math.huge
    for _, point in ipairs(course.points) do
        local dx, dz = point.x - x, point.z - z
        local d = dx * dx + dz * dz
        if d < best then best = d end
    end
    return math.sqrt(best)
end


--- @param x number
--- @param z number
--- @param radius number
--- @return table|nil, number|nil the nearest saved course within radius, and its index
function EqCourse.nearest(x, z, radius)
    local best, bestIndex, bestDistance = nil, nil, radius
    for i, course in ipairs(EqCourse.list) do
        local d = EqCourse.distanceTo(course, x, z)
        if d <= bestDistance then best, bestIndex, bestDistance = course, i, d end
    end
    return best, bestIndex
end


--- @param points table
--- @return string "x,y,z;x,y,z" with one decimal
local function encodePoints(points)
    local parts = {}
    for _, p in ipairs(points) do table.insert(parts, string.format("%.1f,%.1f,%.1f", p.x, p.y, p.z)) end
    return table.concat(parts, ";")
end


--- @param text string|nil
--- @return table points
local function decodePoints(text)
    local points = {}
    for x, y, z in string.gmatch(text or "", "(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+)") do
        table.insert(points, { x = tonumber(x), y = tonumber(y), z = tonumber(z) })
    end
    return points
end


--- @param xmlFile table
--- @param key string e.g. "rlEquestrian.courses"
function EqCourse.saveToXMLFile(xmlFile, key)
    for i, course in ipairs(EqCourse.list) do
        local courseKey = string.format("%s.course(%d)", key, i - 1)
        xmlFile:setString(courseKey .. "#name", course.name)
        xmlFile:setString(courseKey .. "#points", encodePoints(course.points))
        for j, jump in ipairs(course.jumps) do
            local jumpKey = string.format("%s.jump(%d)", courseKey, j - 1)
            xmlFile:setFloat(jumpKey .. "#x", jump.x)
            xmlFile:setFloat(jumpKey .. "#z", jump.z)
            xmlFile:setFloat(jumpKey .. "#ry", jump.ry or 0)
            xmlFile:setInt(jumpKey .. "#side", jump.side or 1)
        end
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqCourse.loadFromXMLFile(xmlFile, key)
    EqCourse.reset()
    if xmlFile == nil then return end
    local i = 0
    while true do
        local courseKey = string.format("%s.course(%d)", key, i)
        if not xmlFile:hasProperty(courseKey) then break end
        local course = { name = xmlFile:getString(courseKey .. "#name", string.format("Course %d", i + 1)),
            points = decodePoints(xmlFile:getString(courseKey .. "#points")), jumps = {} }
        local j = 0
        while true do
            local jumpKey = string.format("%s.jump(%d)", courseKey, j)
            if not xmlFile:hasProperty(jumpKey) then break end
            table.insert(course.jumps, { x = xmlFile:getFloat(jumpKey .. "#x", 0), z = xmlFile:getFloat(jumpKey .. "#z", 0),
                ry = xmlFile:getFloat(jumpKey .. "#ry", 0), side = xmlFile:getInt(jumpKey .. "#side", 1) })
            j = j + 1
        end
        course.length = EqCourse.pathLength(course.points)
        if #course.points >= 2 then table.insert(EqCourse.list, course) end
        i = i + 1
    end
end

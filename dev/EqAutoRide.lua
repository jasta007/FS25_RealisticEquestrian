--[[
    EqAutoRide.lua
    DEV ONLY, never shipped: the release build packs data, gui, placeables, scripts, sounds and
    translations, not dev/, and main.lua only sources this file when it is there.

    An autopilot for filming (James, 2026-11-03: fly-cam footage for the 1.0 video). You sit on
    the horse, so your character is the rider with reins and animations, and the horse rides a
    route by itself while you fly a camera round it.

    The base game has no AI for horses and holds an unridden horse still every frame, so the
    autopilot steers the ridden horse instead: just before Rideable:updateKinematic it sets the
    steering (inputValues.axisSteer) and the gait (inputValues.currentGait), the same inputs the
    keys set. Steering is pure pursuit: aim at the route a little way ahead (more at speed).

    Routes are recorded by riding them, like courses (EqCourse.recordStep's GPS trail), and keep
    the gait at each point, so a replay walks, trots and canters where you did. Halts and backing
    up are left out. Routes live in modSettings/FS25_RealisticEquestrian_autoRide.xml, so they
    work in any savegame on the same map. Saved show jumping and cross country courses can be
    ridden too (at a canter).

    Console: eqAutoRide record <name> | save | cancel | play <name> [loop] | stop | list | delete <name>
    Host or single player only.
]]

EqAutoRide = {}

EqAutoRide.FILE = "FS25_RealisticEquestrian_autoRide.xml"
-- The route is followed through points about this far apart (metres).
EqAutoRide.STEP = 1
-- Aim this far ahead along the route: at least LOOK_MIN metres, else LOOK_SECONDS of travel.
EqAutoRide.LOOK_MIN = 3
EqAutoRide.LOOK_SECONDS = 0.9
-- Turn so the heading error closes in about this many seconds.
EqAutoRide.STEER_SECONDS = 0.35
-- How many points ahead the horse's place on the route is looked for each frame.
EqAutoRide.WINDOW = 40
-- Done (when not looping) this close to the last point.
EqAutoRide.END_RADIUS = 2
-- A loop joins its end to its start when they are this close.
EqAutoRide.LOOP_JOIN = 25
EqAutoRide.MOVING = { walk = true, trot = true, canter = true, gallop = true }
-- Gait for a course recorded without gaits.
EqAutoRide.DEFAULT_GAIT = "canter"

-- Saved routes: name -> { name, points = { {x, y, z, gait} } }
EqAutoRide.routes = {}
-- { vehicle, recording } while recording, { vehicle, path, index, loop } while playing.
EqAutoRide.recording = nil
EqAutoRide.playing = nil


-- PURE: no game calls below until the GAME section.

--- @return number angle wrapped to -pi..pi
function EqAutoRide.wrap(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end


--- The heading the base game moves along (x = sin, z = cos), from (x, z) towards (tx, tz).
function EqAutoRide.headingTo(x, z, tx, tz)
    return math.atan2(tx - x, tz - z)
end


--- Points about STEP metres apart along the route, each with the gait of the leg it is on.
--- @param points table { x, y, z, gait }
--- @return table path
function EqAutoRide.densify(points, step)
    step = step or EqAutoRide.STEP
    local out = {}
    if #points == 0 then return out end
    local gait = EqAutoRide.DEFAULT_GAIT
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        gait = a.gait or gait
        local dx, dz = b.x - a.x, b.z - a.z
        local n = math.max(1, math.floor(math.sqrt(dx * dx + dz * dz) / step + 0.5))
        for s = 0, n - 1 do
            local t = s / n
            table.insert(out, { x = a.x + dx * t, y = a.y + (b.y - a.y) * t, z = a.z + dz * t, gait = gait })
        end
    end
    local last = points[#points]
    table.insert(out, { x = last.x, y = last.y, z = last.z, gait = last.gait or gait })
    return out
end


local function dist2(p, x, z)
    local dx, dz = p.x - x, p.z - z
    return dx * dx + dz * dz
end


--- @return number index of the route point nearest (x, z)
function EqAutoRide.nearestIndex(path, x, z)
    local best, bestD = 1, math.huge
    for i, p in ipairs(path) do
        local d = dist2(p, x, z)
        if d < bestD then best, bestD = i, d end
    end
    return best
end


--- The horse's place on the route: the nearest point from index on, up to WINDOW ahead, never
--- going back (so a route that crosses itself is ridden in order).
--- @return number index
function EqAutoRide.advance(path, index, x, z, loop)
    local count = #path
    local best, bestD = index, dist2(path[index], x, z)
    for k = 1, math.min(EqAutoRide.WINDOW, count - 1) do
        local i = index + k
        if i > count then
            if not loop then break end
            i = i - count
        end
        local d = dist2(path[i], x, z)
        if d < bestD then best, bestD = i, d end
    end
    return best
end


--- The point aimed at: the first from index on at least look metres from the horse.
--- @return table point, boolean true when it ran out of route (not looping)
function EqAutoRide.target(path, index, x, z, look, loop)
    local count = #path
    local look2 = look * look
    for k = 0, count - 1 do
        local i = index + k
        if i > count then
            if not loop then return path[count], true end
            i = i - count
        end
        if dist2(path[i], x, z) >= look2 then return path[i], false end
    end
    return path[loop and index or count], not loop
end


--- One frame of the autopilot.
--- @param play table { path, index, loop }
--- @param x number horse position
--- @param z number
--- @param heading number spec.currentTurnAngle
--- @param speed number metres per second
--- @param maxTurnSpeed number rad/s at full steer
--- @return number axisSteer (-1..1, left positive like the base game), string gait, boolean done
function EqAutoRide.drive(play, x, z, heading, speed, maxTurnSpeed)
    local path = play.path
    play.index = EqAutoRide.advance(path, play.index, x, z, play.loop)
    local gait = path[play.index].gait or EqAutoRide.DEFAULT_GAIT
    if not play.loop and play.index >= #path - 1 and dist2(path[#path], x, z) <= EqAutoRide.END_RADIUS ^ 2 then
        return 0, "halt", true
    end
    local look = math.max(EqAutoRide.LOOK_MIN, math.abs(speed) * EqAutoRide.LOOK_SECONDS)
    local aim = EqAutoRide.target(path, play.index, x, z, look, play.loop)
    local err = EqAutoRide.wrap(EqAutoRide.headingTo(x, z, aim.x, aim.z) - heading)
    local rate = err / EqAutoRide.STEER_SECONDS
    local steer = maxTurnSpeed > 0 and math.max(-1, math.min(1, rate / maxTurnSpeed)) or 0
    return steer, gait, false
end


--- Start following a route from the point nearest the horse.
--- @param points table the route's recorded points
--- @return table play
function EqAutoRide.newPlay(points, x, z, loop)
    local list = points
    if loop and #points > 2 and dist2(points[#points], points[1].x, points[1].z) <= EqAutoRide.LOOP_JOIN ^ 2 then
        -- Close the loop so the join is ridden as a leg like any other.
        list = {}
        for _, p in ipairs(points) do table.insert(list, p) end
        local first = points[1]
        table.insert(list, { x = first.x, y = first.y, z = first.z, gait = points[#points].gait })
    end
    local path = EqAutoRide.densify(list)
    return { path = path, index = EqAutoRide.nearestIndex(path, x, z), loop = loop == true }
end


--- Recording: one frame. The gait is the last moving gait; a change of gait drops a point.
--- @param rec table EqCourse recording with .gait
--- @param gait string|nil the horse's gait this frame
function EqAutoRide.recordStep(rec, x, y, z, gait)
    if gait ~= nil and EqAutoRide.MOVING[gait] then
        if #rec.points == 1 and rec.points[1].gait == nil then rec.points[1].gait = gait end
        local changed = rec.gait ~= nil and rec.gait ~= gait
        rec.gait = gait
        if EqCourse.recordStep(rec, x, y, z, changed) then rec.points[#rec.points].gait = gait end
        return
    end
    -- Standing or backing up: nothing recorded.
end


--- @return string "x,y,z,gait;..."
function EqAutoRide.encode(points)
    local parts = {}
    for _, p in ipairs(points) do
        table.insert(parts, string.format("%.2f,%.2f,%.2f,%s", p.x, p.y, p.z, p.gait or EqAutoRide.DEFAULT_GAIT))
    end
    return table.concat(parts, ";")
end


--- @return table points
function EqAutoRide.decode(text)
    local points = {}
    for x, y, z, gait in string.gmatch(text or "", "(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+),(%a+)") do
        table.insert(points, { x = tonumber(x), y = tonumber(y), z = tonumber(z), gait = gait })
    end
    return points
end


-- GAME: everything below calls the game.

local Log = EqLog

local function gaitName(spec)
    local types = Rideable.GAITTYPES
    local current = spec.inputValues ~= nil and spec.inputValues.currentGait or nil
    -- Named one by one: GAITTYPES.MAX shares the gallop's value.
    for _, name in ipairs({ "STILL", "WALK", "TROT", "CANTER", "GALLOP", "BACKWARDS" }) do
        if types[name] ~= nil and types[name] == current then return string.lower(name) end
    end
    return nil
end


local function setGait(spec, name)
    local types = Rideable.GAITTYPES
    local value = name == "halt" and types.STILL or types[string.upper(name)]
    if value ~= nil then spec.inputValues.currentGait = value end
end


local function filePath()
    if g_modSettingsDirectory == nil then return nil end
    return g_modSettingsDirectory .. EqAutoRide.FILE
end


function EqAutoRide.load()
    EqAutoRide.routes = {}
    local path = filePath()
    local xmlFile = path ~= nil and XMLFile.loadIfExists("eqAutoRide", path) or nil
    if xmlFile == nil then return end
    xmlFile:iterate("autoRide.route", function(_, key)
        local name = xmlFile:getString(key .. "#name")
        local points = EqAutoRide.decode(xmlFile:getString(key .. "#points"))
        if name ~= nil and #points >= 2 then EqAutoRide.routes[string.lower(name)] = { name = name, points = points } end
    end)
    xmlFile:delete()
end


function EqAutoRide.save()
    local path = filePath()
    if path == nil then return false end
    if createFolder ~= nil then createFolder(g_modSettingsDirectory) end
    local xmlFile = XMLFile.create("eqAutoRide", path, "autoRide")
    if xmlFile == nil then return false end
    local i = 0
    for _, route in pairs(EqAutoRide.routes) do
        local key = string.format("autoRide.route(%d)", i)
        xmlFile:setString(key .. "#name", route.name)
        xmlFile:setString(key .. "#points", EqAutoRide.encode(route.points))
        i = i + 1
    end
    xmlFile:save()
    xmlFile:delete()
    return true
end


--- A saved route or, failing that, a saved course by name.
local function findRoute(name)
    local route = EqAutoRide.routes[string.lower(name)]
    if route ~= nil then return route end
    for _, course in ipairs(EqCourse.list or {}) do
        if string.lower(course.name or "") == string.lower(name) then
            return { name = course.name, points = course.points, course = true }
        end
    end
    return nil
end


--- Each frame on the server, just before the base game moves the horse.
local function beforeMove(vehicle, dt)
    local spec = vehicle.spec_rideable
    if spec == nil or spec.inputValues == nil then return end
    local rec = EqAutoRide.recording
    if rec ~= nil and rec.vehicle == vehicle then
        local x, y, z = getWorldTranslation(vehicle.rootNode)
        EqAutoRide.recordStep(rec.recording, x, y, z, gaitName(spec))
    end
    local play = EqAutoRide.playing
    if play == nil or play.vehicle ~= vehicle then return end
    if not vehicle:getIsEntered() then
        EqAutoRide.playing = nil
        Log:info("AutoRide: rider got off, autopilot stopped")
        return
    end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local steer, gait, done = EqAutoRide.drive(play.play, x, z, spec.currentTurnAngle or 0, spec.currentSpeed or 0, spec.maxTurnSpeed or 1)
    spec.inputValues.axisSteer = steer
    setGait(spec, gait)
    if done then
        EqAutoRide.playing = nil
        Log:info("AutoRide: end of '%s'", play.name)
    end
end


--- Patch Rideable's move. Called by main.lua before EqLateral.install, so the autopilot's
--- steering is set inside EqLateral's hook and wins over mouse steering.
function EqAutoRide.install()
    if type(Rideable) ~= "table" or type(Rideable.updateKinematic) ~= "function" then
        Log:warning("AutoRide: Rideable.updateKinematic missing")
        return
    end
    Rideable.updateKinematic = Utils.overwrittenFunction(Rideable.updateKinematic, function(self, superFunc, dt)
        if (EqAutoRide.recording ~= nil or EqAutoRide.playing ~= nil) and not EqAutoRide.failed then
            if not EqLog.try("EqAutoRide", beforeMove, self, dt) then
                EqAutoRide.failed = true
                EqAutoRide.playing, EqAutoRide.recording = nil, nil
            end
        end
        return superFunc(self, dt)
    end)
    addConsoleCommand("eqAutoRide", "DEV: autopilot for filming: eqAutoRide record <name> | save | cancel | play <name> [loop] | stop | list | delete <name>",
        "consoleAutoRide", EqAutoRide)
    Log:info("AutoRide: dev autopilot installed (eqAutoRide)")
end


local function ridden()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return nil, "Host or single player only" end
    local vehicle = g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() or nil
    if vehicle == nil or vehicle.spec_rideable == nil then return nil, "Get on a horse first" end
    return vehicle
end


function EqAutoRide:consoleAutoRide(command, ...)
    if EqAutoRide.loaded == nil then
        EqAutoRide.loaded = true
        EqAutoRide.load()
    end
    command = string.lower(command or "")
    local name = table.concat({ ... }, " ")
    if command == "record" then
        local vehicle, why = ridden()
        if vehicle == nil then return why end
        if name == "" then return "Usage: eqAutoRide record <name>" end
        local x, y, z = getWorldTranslation(vehicle.rootNode)
        local recording = EqCourse.newRecording(x, y, z)
        recording.points[1].gait = nil
        EqAutoRide.playing = nil
        EqAutoRide.recording = { vehicle = vehicle, recording = recording, name = name }
        return string.format("Recording '%s': ride the route (gaits are kept), then eqAutoRide save", name)
    elseif command == "save" then
        local rec = EqAutoRide.recording
        if rec == nil then return "Not recording" end
        local points = rec.recording.points
        -- Where the horse is now ends the route.
        if rec.vehicle.rootNode ~= nil and entityExists(rec.vehicle.rootNode) then
            local x, y, z = getWorldTranslation(rec.vehicle.rootNode)
            if EqCourse.recordStep(rec.recording, x, y, z, true) then points[#points].gait = rec.recording.gait end
        end
        EqAutoRide.recording = nil
        if #points < 2 then return "Too short to save" end
        EqAutoRide.routes[string.lower(rec.name)] = { name = rec.name, points = points }
        local ok = EqAutoRide.save()
        return string.format("Saved '%s': %d points, %.0f m%s", rec.name, #points, EqCourse.pathLength(points),
            ok and "" or " (could not write the file, kept until you quit)")
    elseif command == "cancel" then
        EqAutoRide.recording = nil
        return "Recording thrown away"
    elseif command == "play" then
        local vehicle, why = ridden()
        if vehicle == nil then return why end
        local loop = false
        local loopName = string.match(name, "^(.-)%s+[Ll][Oo][Oo][Pp]$")
        if loopName ~= nil then name, loop = loopName, true end
        if name == "" then return "Usage: eqAutoRide play <name> [loop]" end
        local route = findRoute(name)
        if route == nil then return string.format("No route or course called '%s' (eqAutoRide list)", name) end
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        EqAutoRide.recording = nil
        EqAutoRide.playing = { vehicle = vehicle, name = route.name, play = EqAutoRide.newPlay(route.points, x, z, loop) }
        return string.format("Riding '%s'%s: eqAutoRide stop to take over", route.name, loop and " on a loop" or "")
    elseif command == "stop" then
        local play = EqAutoRide.playing
        EqAutoRide.playing = nil
        if play ~= nil and play.vehicle.spec_rideable ~= nil then
            setGait(play.vehicle.spec_rideable, "walk")
        end
        return play ~= nil and "Autopilot off, you have the reins (walking)" or "Autopilot was not on"
    elseif command == "list" then
        local lines = {}
        for _, route in pairs(EqAutoRide.routes) do
            table.insert(lines, string.format("  %s: %.0f m", route.name, EqCourse.pathLength(route.points)))
        end
        for _, course in ipairs(EqCourse.list or {}) do
            table.insert(lines, string.format("  %s: %.0f m (course, cantered)", course.name, course.length or 0))
        end
        if #lines == 0 then return "No routes yet: eqAutoRide record <name>" end
        table.sort(lines)
        return "Routes:\n" .. table.concat(lines, "\n")
    elseif command == "delete" then
        local key = string.lower(name)
        if EqAutoRide.routes[key] == nil then return string.format("No route called '%s'", name) end
        EqAutoRide.routes[key] = nil
        EqAutoRide.save()
        return string.format("Deleted '%s'", name)
    end
    return "Usage: eqAutoRide record <name> | save | cancel | play <name> [loop] | stop | list | delete <name>"
end

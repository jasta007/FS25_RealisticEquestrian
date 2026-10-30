--[[
    EqDressageHooks.lua
    Finds the dressage markers on the map for the temperament routine (EqDressage), and tags the
    marker a leg goes to with the game's map target, the way the player tags a place on the map.

    Markers are Riding Hall 2k26's letter boards (EqDressage.MARKER_XML), $1 decorations. The
    letter is the configuration picked when placing one ("solarPanels" in its xml, A to Z).
    Our own arenas (EqDressage.ARENA_XML) carry every letter as a node named eqMarker_<letter>,
    and have no collision to take off.
    The boards come with collision, which a horse runs into in the middle of an arena, so we take
    their collision off while a horse is ridden and put it back after (James, 2026-10-27), so
    they can still be picked up and sold in construction mode.

    Part of Realistic Equestrian by Jasta007.
]]

EqDressageHooks = {}

local Log = EqLog

-- The map's markers are listed again this often, and the course round the horse worked out.
EqDressageHooks.SCAN_MS = 5000
EqDressageHooks.COURSE_MS = 1000
-- A tag not refreshed for this long (the rider got off) is taken down.
EqDressageHooks.TAG_STALE_MS = 1000
-- Markers have no collision while a horse was ridden within this long (see setRiding).
EqDressageHooks.RIDING_GRACE_MS = 1000

EqDressageHooks.markers = {}
EqDressageHooks.placeables = {}
EqDressageHooks.collisionOff = false
EqDressageHooks.ridingSeen = nil
EqDressageHooks.scannedAt = nil
EqDressageHooks.logged = {}
EqDressageHooks.tag = nil
EqDressageHooks.tagFailed = false


function EqDressageHooks.reset()
    EqDressageHooks.clearTag()
    EqDressageHooks.markers, EqDressageHooks.scannedAt, EqDressageHooks.logged = {}, nil, {}
    EqDressageHooks.placeables, EqDressageHooks.collisionOff, EqDressageHooks.ridingSeen = {}, false, nil
end


--- The name of a placeable's picked configuration, if the store item has one.
--- @param placeable table
--- @param key string configuration name
--- @param index number
--- @return string|nil
local function configName(placeable, key, index)
    if g_storeManager == nil or g_storeManager.getItemByXMLFilename == nil then return nil end
    local item = g_storeManager:getItemByXMLFilename(placeable.configFileName)
    local configs = item ~= nil and item.configurations ~= nil and item.configurations[key] or nil
    local config = configs ~= nil and configs[index] or nil
    return config ~= nil and config.name or nil
end


--- Take the collision off a marker: every rigid body under its root node goes, and is kept
--- so restoreCollision can put it back.
--- @param placeable table
function EqDressageHooks.removeCollision(placeable)
    if placeable.eqBodies ~= nil or setRigidBodyType == nil or getRigidBodyType == nil then return end
    local none = RigidBodyType ~= nil and RigidBodyType.NONE or "NoRigidBody"
    local bodies = {}
    local stack = { placeable.rootNode }
    while #stack > 0 do
        local node = table.remove(stack)
        local okType, kind = EqLog.try("EqDressageHooks.removeCollision getRigidBodyType", getRigidBodyType, node)
        if okType and kind ~= nil and kind ~= none and kind ~= "NoRigidBody" then
            if EqLog.try("EqDressageHooks.removeCollision setRigidBodyType", setRigidBodyType, node, none) then table.insert(bodies, { node = node, kind = kind }) end
        end
        for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
    end
    placeable.eqBodies = bodies
    if not EqDressageHooks.loggedCollision then
        EqDressageHooks.loggedCollision = true
        Log:info("Dressage marker: collision off on %d node(s) while riding", #bodies)
    end
end


--- Give a marker its collision back, so it can be picked up, moved or sold.
--- @param placeable table
function EqDressageHooks.restoreCollision(placeable)
    local bodies = placeable.eqBodies
    if bodies == nil then return end
    placeable.eqBodies = nil
    for _, body in ipairs(bodies) do
        if entityExists == nil or entityExists(body.node) then EqLog.try("EqDressageHooks.restoreCollision setRigidBodyType", setRigidBodyType, body.node, body.kind) end
    end
end


--- Markers only lose their collision while the player rides (James, 2026-10-27: off a horse
--- they must be selectable in construction mode). Called each frame.
--- @param riding boolean
function EqDressageHooks.setRiding(riding)
    if riding == EqDressageHooks.collisionOff then return end
    EqDressageHooks.collisionOff = riding
    for _, placeable in ipairs(EqDressageHooks.placeables) do
        local ok, err = EqLog.try("EqDressageHooks.setRiding", riding and EqDressageHooks.removeCollision or EqDressageHooks.restoreCollision, placeable)
        if not ok then Log:warning("Dressage marker collision: %s", tostring(err)) end
    end
    Log:info("Dressage markers: collision %s (%d markers)", riding and "off while riding" or "back on", #EqDressageHooks.placeables)
end


--- Add the markers of one of our arenas: its nodes named eqMarker_<letter>.
--- @param placeable table
--- @param list table
function EqDressageHooks.addArena(placeable, list)
    local stack = { placeable.rootNode }
    while #stack > 0 do
        local node = table.remove(stack)
        local letter = EqDressage.arenaLetter(getName(node))
        if letter ~= nil then
            local x, _, z = getWorldTranslation(node)
            table.insert(list, { letter = letter, x = x, z = z, arena = true, arenaId = placeable.rootNode })
            local key = string.format("%.1f:%.1f", x, z)
            if not EqDressageHooks.logged[key] then
                EqDressageHooks.logged[key] = true
                Log:info("Dressage arena marker %s at %.1f, %.1f", letter, x, z)
            end
        end
        for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
    end
end


--- @return table every dressage marker on the map: { letter, x, z }
function EqDressageHooks.scan()
    local list, placeables = {}, {}
    EqDressageHooks.placeables = placeables
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return list end
    for _, placeable in ipairs(system.placeables) do
        if EqDressage.isArenaXml(placeable.configFileName) and placeable.rootNode ~= nil then
            local ok, err = EqLog.try("EqDressageHooks.scan addArena", EqDressageHooks.addArena, placeable, list)
            if not ok then Log:warning("Dressage arena: %s", tostring(err)) end
        elseif EqDressage.isMarkerXml(placeable.configFileName) and placeable.rootNode ~= nil then
            local index = placeable.configurations ~= nil and placeable.configurations.solarPanels or nil
            local okName, name = EqLog.try("EqDressageHooks.scan configName", configName, placeable, "solarPanels", index)
            name = okName and name or nil
            local letter = EqDressage.letterFor(index, name)
            table.insert(placeables, placeable)
            if EqDressageHooks.collisionOff then
                local okCollision, err = EqLog.try("EqDressageHooks.scan removeCollision", EqDressageHooks.removeCollision, placeable)
                if not okCollision then Log:warning("Dressage marker collision: %s", tostring(err)) end
            end
            local x, _, z = getWorldTranslation(placeable.rootNode)
            table.insert(list, { letter = letter, x = x, z = z })
            local key = string.format("%.1f:%.1f", x, z)
            if not EqDressageHooks.logged[key] then
                EqDressageHooks.logged[key] = true
                Log:info("Dressage marker %s at %.1f, %.1f (configuration %s, '%s')", letter, x, z, tostring(index), tostring(name))
            end
        end
    end
    return list
end


--- The course round a ridden horse, or nil. Worked out once a second and kept on the spec.
--- @param vehicle table
--- @param spec table spec_rideable
--- @return table|nil course { x, z, markers }
function EqDressageHooks.courseFor(vehicle, spec)
    if vehicle.rootNode == nil then return nil end
    local now = g_time or 0
    if EqDressageHooks.scannedAt == nil or now - EqDressageHooks.scannedAt >= EqDressageHooks.SCAN_MS or now < EqDressageHooks.scannedAt then
        EqDressageHooks.scannedAt = now
        EqDressageHooks.markers = EqDressageHooks.scan()
    end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    if spec.eqCourseAt == nil or now - spec.eqCourseAt >= EqDressageHooks.COURSE_MS or now < spec.eqCourseAt then
        spec.eqCourseAt = now
        local markers = #EqDressageHooks.markers >= 3 and EqDressage.findCourse(EqDressageHooks.markers, x, z) or nil
        if (markers ~= nil) ~= (spec.eqCourse ~= nil) then
            Log:info("Dressage course: %s", markers ~= nil and string.format("%d markers", #markers) or "none near")
        end
        spec.eqCourse = markers
        -- In the month of your own event the arena rides its fixed test, which counts for a
        -- horse entered in it (EqHostManager.dressageTestFor).
        spec.eqTest = nil
        if markers ~= nil and EqHostManager ~= nil then
            local ok, test = EqLog.try("EqDressageHooks dressageTestFor", function()
                return EqHostManager.dressageTestFor(EqHostManager.horseIdOf(vehicle), markers)
            end)
            if ok then spec.eqTest = test end
        end
        -- The horse's temperament: how far ahead it sees the line, and how soon changes show.
        local record = spec.cluster ~= nil and EqRegistry.getOrCreate(spec.cluster) or nil
        spec.eqTemperament = record ~= nil and record.trained ~= nil and record.trained.temperament or nil
    end
    if spec.eqCourse == nil then return nil end
    -- The way the horse faces and its head bend, for lateral work (EqLateral).
    local dirX, _, dirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
    local bend = EqLateral ~= nil and EqLateral.vehicle == vehicle and EqLateral.bend or 0
    return { x = x, z = z, markers = spec.eqCourse, test = spec.eqTest, temperament = spec.eqTemperament, dirX = dirX, dirZ = dirZ, bend = bend }
end


-- The test's line on the ground (EqDressagePath) is a path guide (EqCourseGlow.path): gold until
-- the test begins, then green to red by how far off it the horse is, eased over SHADE_MS so it
-- doesn't flicker.
EqDressageHooks.SHADE_MS = 400
EqDressageHooks.shownDev = nil
-- James 2026-10-30: white ahead, coloured as the horse reaches it (within NEAR metres, by how
-- far off it is now), and the pieces up to BEHIND metres behind keep the colour they were ridden.
EqDressageHooks.NEAR = 2
EqDressageHooks.BEHIND = 3


--- Each piece's colour along the line (pure): behind the horse by how far off its points were
--- ridden, near it by now, white further on.
--- @param run table EqDressagePath run
--- @param from number index of the first point drawn
--- @param now string the colour for the pieces the horse is on
--- @return function (s) -> colour
function EqDressageHooks.colourAlong(run, from, now)
    local pts = run.test.pts
    return function(s)
        local here = run.s
        if s + 1 <= here then
            -- Behind: the worst of the points in the piece.
            local worst = nil
            for k = from, run.i do
                if pts[k].s >= s and pts[k].s < s + 1 and run.devAt[k] ~= nil then worst = math.max(worst or 0, run.devAt[k]) end
            end
            return worst ~= nil and EqDressagePath.colourFor(worst) or now
        elseif s <= here + EqDressageHooks.NEAR then
            return now
        end
        return "white"
    end
end
-- A gold pole stands where a change or halt is coming, and where the test begins.
EqDressageHooks.POLE_HEIGHT = 1.2
-- The run drawn, kept by EqTrainingHooks each frame while a test is on (pathAt: when).
EqDressageHooks.pathRun = nil
EqDressageHooks.pathAt = nil


--- @return number the ground's height under a path point (worked out once)
local function pointY(frame, p)
    if p.wy == nil then
        p.wx, p.wz = EqDressagePath.toWorld(frame, p.x, p.y)
        local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
        p.wy = terrain ~= nil and getTerrainHeightAtWorldPos(terrain, p.wx, 0, p.wz) or 0
    end
    return p.wy
end


--- Temperament's stickiness for EqLateral: the pull back onto the test's line and the body angle
--- a lateral section asks for, while a test is on (EqDressagePath.assist).
--- @return number dx, number dz, number|nil wantX, number|nil wantZ, number turnRate
function EqDressageHooks.assist(vehicle, lateral, dt)
    local run = EqDressageHooks.pathRun
    local now = g_time or 0
    if run == nil or EqDressageHooks.pathAt == nil or now - EqDressageHooks.pathAt > 500 or now < EqDressageHooks.pathAt then return 0, 0, nil, nil, 0 end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    return EqDressagePath.assist(run, x, z, lateral, dt)
end


--- Draw the test's line ahead of the horse, from EqCourseHooks.onDraw between the course glow's
--- begin and finish: as far ahead as the horse's temperament lets it see, and a pole at the
--- change or halt coming up once it is near enough to show.
--- @param vehicle table the ridden horse
function EqDressageHooks.drawPath(vehicle)
    local run = EqDressageHooks.pathRun
    local now = g_time or 0
    if run == nil or EqDressageHooks.pathAt == nil or now - EqDressageHooks.pathAt > 500 or now < EqDressageHooks.pathAt then return end
    local pts, frame = run.test.pts, run.frame
    local first = run.started and run.i or 1
    local reach = pts[first].s + run.look
    -- A few pieces behind the horse too, coloured by how they were ridden.
    local back = first
    while back > 1 and pts[first].s - pts[back].s < EqDressageHooks.BEHIND do back = back - 1 end
    local line = {}
    for i = back, #pts do
        local p = pts[i]
        local y = pointY(frame, p)
        table.insert(line, { x = p.wx, y = y, z = p.wz })
        if p.s >= reach then break end
    end
    local colour = nil
    if run.started then
        local dt = EqDressageHooks.drawnAt ~= nil and math.max(0, now - EqDressageHooks.drawnAt) or 0
        local dev = run.dev or 0
        local shown = EqDressageHooks.shownDev or dev
        EqDressageHooks.shownDev = shown + (dev - shown) * math.min(1, dt / EqDressageHooks.SHADE_MS)
        colour = EqDressageHooks.colourAlong(run, back, EqDressagePath.colourFor(EqDressageHooks.shownDev))
    else
        EqDressageHooks.shownDev = nil
    end
    EqDressageHooks.drawnAt = now
    if not EqCourseGlow.path(line, colour, pts[back].s) then return end
    if not run.started then
        local p = pts[1]
        EqCourseGlow.pole(p.wx, pointY(frame, p), p.wz, EqDressageHooks.POLE_HEIGHT)
        return
    end
    local event = EqDressagePath.upcoming(run)
    if event ~= nil then
        for k = run.i, #pts do
            if pts[k].s >= event.s or k == #pts then
                local y = pointY(frame, pts[k])
                EqCourseGlow.pole(pts[k].wx, y, pts[k].wz, EqDressageHooks.POLE_HEIGHT)
                break
            end
        end
    end
end


--- Our hotspot's methods (its own and inherited), each guarded: an error in one takes our tag
--- down for the rest of the game instead of breaking the whole HUD's draw every frame (James's
--- log, 2026-10-28: "PlaceableHotspot.lua:225: attempt to index nil with 'width'", HUD gone).
--- @param hotspot table
local function guardHotspot(hotspot)
    local seen = {}
    local mt = getmetatable(hotspot)
    local class = mt ~= nil and mt.__index or nil
    while type(class) == "table" and not seen[class] do
        seen[class] = true
        for name, fn in pairs(class) do
            if type(fn) == "function" and name ~= "new" and rawget(hotspot, name) == nil then
                hotspot[name] = function(self, ...)
                    local result = { pcall(fn, self, ...) }
                    if result[1] then return unpack(result, 2, table.maxn(result)) end
                    if not EqDressageHooks.tagFailed then
                        EqDressageHooks.tagFailed = true
                        Log:warning("Map tag hotspot failed in %s, tags off for this game: %s", tostring(name), tostring(result[2]))
                        EqDressageHooks.clearTag()
                    end
                    return nil
                end
            end
        end
        local parent = getmetatable(class)
        class = parent ~= nil and parent.__index or nil
    end
end


--- Tag a marker as the map target (the game's own "tag" on the map), unless the player has
--- tagged something of their own. Does nothing more after any error.
--- @param marker table|nil { letter, x, z }; nil takes our tag down
--- @param name string|nil the tag's name, instead of the marker's letter (a show jump's fence)
function EqDressageHooks.setTag(marker, name)
    if marker == nil then
        EqDressageHooks.clearTag()
        return
    end
    if EqDressageHooks.tagFailed or g_currentMission == nil or g_currentMission.setMapTargetHotspot == nil
        or PlaceableHotspot == nil then return end
    local tag = EqDressageHooks.tag
    EqDressageHooks.tagSeen = g_time or 0
    name = name or string.format(g_i18n:getText("eq_dressage_marker"), marker.letter)
    if tag ~= nil and tag.x == marker.x and tag.z == marker.z and tag.name == name then return end
    local ok, err = EqLog.try("EqDressageHooks.setTag", function()
        local current = g_currentMission.currentMapTargetHotspot
        if current ~= nil and (tag == nil or current ~= tag.hotspot) then return end
        if tag ~= nil and current == nil then
            -- The game took our tag down itself (it may have deleted it): never use it again.
            EqDressageHooks.clearTag()
            tag = nil
        end
        if tag == nil then
            -- A fresh hotspot each time: one the game or we let go of may be deleted.
            local hotspot = PlaceableHotspot.new()
            if PlaceableHotspot.TYPE ~= nil and PlaceableHotspot.TYPE.EXCLAMATION_MARK ~= nil then
                hotspot:setPlaceableType(PlaceableHotspot.TYPE.EXCLAMATION_MARK)
            end
            guardHotspot(hotspot)
            g_currentMission:addMapHotspot(hotspot)
            tag = { hotspot = hotspot }
            EqDressageHooks.tag = tag
        end
        tag.x, tag.z, tag.name = marker.x, marker.z, name
        tag.hotspot:setWorldPosition(marker.x, marker.z)
        if tag.hotspot.setName ~= nil then tag.hotspot:setName(name) end
        g_currentMission:setMapTargetHotspot(tag.hotspot)
    end)
    if not ok then
        EqDressageHooks.tagFailed = true
        Log:warning("Dressage marker tag unavailable: %s", tostring(err))
        EqDressageHooks.clearTag()
    end
end


--- Take our tag down (leaving any of the player's own). The hotspot is let go, never deleted: the
--- map went on drawing a deleted one for a moment and logged "PlaceableHotspot.lua:225: attempt to
--- index nil with 'width'" every frame (James's log, 2026-10-27). Nor is it reused (2026-10-28).
function EqDressageHooks.clearTag()
    local tag = EqDressageHooks.tag
    if tag == nil then return end
    EqDressageHooks.tag = nil
    EqLog.try("EqDressageHooks.clearTag", function()
        if g_currentMission.currentMapTargetHotspot == tag.hotspot then g_currentMission:setMapTargetHotspot(nil) end
        g_currentMission:removeMapHotspot(tag.hotspot)
    end)
end


--- Each frame: list the markers every SCAN_MS (taking newly placed ones' collision off), and
--- take the tag down once the riding overlay stops refreshing it.
function EqDressageHooks.update()
    local now = g_time or 0
    EqDressageHooks.setRiding(EqDressageHooks.ridingSeen ~= nil and now >= EqDressageHooks.ridingSeen
        and now - EqDressageHooks.ridingSeen < EqDressageHooks.RIDING_GRACE_MS)
    if EqDressageHooks.scannedAt == nil or now - EqDressageHooks.scannedAt >= EqDressageHooks.SCAN_MS or now < EqDressageHooks.scannedAt then
        EqDressageHooks.scannedAt = now
        EqDressageHooks.markers = EqDressageHooks.scan()
    end
    if EqDressageHooks.tag ~= nil and (g_time or 0) - (EqDressageHooks.tagSeen or 0) > EqDressageHooks.TAG_STALE_MS then
        EqDressageHooks.clearTag()
    end
end

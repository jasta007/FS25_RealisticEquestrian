--[[
    EqSpectators.lua
    Spectators at your hosted events (James, 2026-11-01): a few people sitting on our bleachers
    and standing in the spectator boxes of the Rope Marker's spectator segment, so events look
    lively. Only seen, local to each player: nothing is saved or sent over the network.

    FS25 has no sit animation. A tractor's driver is the game's own character playing an idle
    clip, with IK chains pulling the hands to the wheel and the feet to the pedals
    (VehicleCharacter). A spectator is seated the same way: the character is lowered until its
    hips sit on the bench, its feet are pulled onto the row below and its hands onto its knees.
    People standing in a rope's spectator box play the game's standing idle clips.

    When: while one of your hosted events runs (its month), from 08:00 to 19:00. How many: the
    Crowd density setting (Off / Low / Medium / High). Bleachers and rope boxes beside a dressage
    arena fill too (James): nobody is ever put on an arena's own boundary, only in seats and boxes
    the player placed. The console command eqSpectators shows them at any time, for testing, and
    tunes the seated pose.

    Part of Realistic Equestrian by Jasta007.
]]

EqSpectators = {}

local Log = EqLog

-- Crowd density setting values, and the most seated and standing people each allows.
EqSpectators.DENSITIES = { "off", "low", "medium", "high" }
EqSpectators.COUNTS = {
    off = { seated = 0, standing = 0 },
    low = { seated = 4, standing = 3 },
    medium = { seated = 8, standing = 6 },
    high = { seated = 16, standing = 12 },
}
EqSpectators.DEFAULT = "medium"

-- Hours of the day spectators are there (from, to).
EqSpectators.HOURS = { 8, 19 }

-- Bleacher shape (art/source/bleachers.py): each row's tread is ROW_DEPTH deep and ROW_RISE
-- higher than the one in front, the front tread BASE above the ground; spectators face -z. The
-- bench stands BENCH_HEIGHT above its tread, from BENCH_FROM to BENCH_TO back from its front.
EqSpectators.ROW_DEPTH = 0.8
EqSpectators.ROW_RISE = 0.42
EqSpectators.BASE = 0.3
EqSpectators.BENCH_HEIGHT = 0.42
EqSpectators.BENCH_FROM = 0.42
EqSpectators.BENCH_TO = 0.74
-- Room each seated person takes along a row, and the gap kept at each end.
EqSpectators.SEAT_WIDTH = 0.65
EqSpectators.SEAT_END = 0.45

-- The Rope Marker's spectator box (art/source/rope_fence.py CROWD_BOX): x from the rope on its
-- +x side, along a 2.5 m panel; people stand inside it, facing the rope, at most PER_BOX a panel.
EqSpectators.ROPE_BOX = { 0.6, 1.8 }
EqSpectators.ROPE_PANEL = 2.5
EqSpectators.ROPE_INSET = 0.12
EqSpectators.PER_BOX = 2
EqSpectators.BOX_NODE = "eqCrowdBox"

-- Seated pose (tuned with eqSpectators pose): the hips this high above the bench and this far back
-- from its front edge, the feet this far forward of the bench and apart, the hands on the knees.
-- Hands (James 2026-11-02: first try bent the arms like rubber): resting on the thighs, the hand
-- targets turned by handPitch/handYaw/handRoll degrees (yaw and roll mirrored for the left hand);
-- arms = 0 leaves the arms to the idle clip. Second try (James 2026-11-02, hands still odd: on the
-- knees, fingers curled): the wrists further back, mid-thigh. seatClip = 1 sits them with the
-- standing idle instead of the driver's one (relaxed hands, arms hanging by the sides).
EqSpectators.pose = {
    hipLift = 0.10, hipBack = 0.18, footForward = 0.45, footApart = 0.13,
    handForward = -0.02, handApart = 0.18, handLift = 0.13,
    handPitch = 0, handYaw = 0, handRoll = 0, arms = 1, seatClip = 0,
    -- standing: the ankle joints this high above the ground
    ankle = 0.09,
}
EqSpectators.ARM_CHAINS = { leftArm = 1, rightArm = -1 }

-- Outfits: presets and items whose names have any of these words are never worn by spectators
-- (James 2026-11-02: no bike helmets, face masks or chainsaw kit in the stands).
EqSpectators.NO_WEAR = { "helmet", "visor", "mask", "veil", "bee", "motocross", "motor", "bike", "goggle",
    "earmuff", "ear protect", "hearing", "protect", "chainsaw", "forest", "safety", "hivis", "hi-vis",
    "highvis", "reflect", "riding", "welding", "respirator" }
-- Faces and clothes of the game's named characters (headNPCQG01 / bodyNPCQG01 the animal dealer,
-- headFisherman01): one spectator each at most, and only by chance.
EqSpectators.NAMED = { "npc", "fisherman" }
EqSpectators.NAMED_CHANCE = 0.08
-- Women in the crowd (the female player character, same slots as the male one)
EqSpectators.FEMALE_XML = "dataS/character/playerF/playerF.xml"
EqSpectators.FEMALE_SHARE = 0.45

-- Hidden beyond this distance from the camera. Seated people are posed live (idle clip plus IK)
-- only within IK_DISTANCE (James, 2026-11-01: they're stationary, so be heavy handed); further
-- out their clip stops and they hold the last pose, solved for POSE_FRAMES frames once seated.
EqSpectators.VISIBLE_DISTANCE = 150
EqSpectators.IK_DISTANCE = 25
EqSpectators.POSE_FRAMES = 5
-- How often the map is checked for bleachers, rope boxes and whether an event runs.
EqSpectators.SCAN_MS = 5000

-- IK chains of the game's character that a seated spectator sets.
EqSpectators.CHAINS = { "leftFoot", "rightFoot", "leftArm", "rightArm" }
-- Standing idle clips, tried in turn; the first ones found are used.
EqSpectators.STAND_CLIPS = { "idle1Source", "idle2Source", "NPCIdleMale01Source", "NPCIdleFemale01Source", "idleSource" }
EqSpectators.SEAT_CLIP = "idle1Source"

EqSpectators.people = {}
EqSpectators.boxes = {}
EqSpectators.forced = nil       -- true / false from the console, nil = automatic
EqSpectators.key = nil
EqSpectators.scannedAt = nil
EqSpectators.boxesShown = nil
EqSpectators.loggedSetup = false
EqSpectators.lastScan = { ropes = 0, owners = {} }
EqSpectators.failed = false     -- an error each frame would fill the log: stop after the first


-- ---------------------------------------------------------------------------------------------
-- Pure planning (runs headless in tests)

--- @param settings table|nil EqCompetitionManager.settings
--- @return string density "off", "low", "medium" or "high"
function EqSpectators.density(settings)
    local value = settings ~= nil and settings.crowdDensity or nil
    if EqSpectators.COUNTS[value] ~= nil then return value end
    return EqSpectators.DEFAULT
end


--- @param filename string|nil a placeable's xml
--- @return number|nil rows, number|nil length (m) for our bleachers
function EqSpectators.bleacherSize(filename)
    if type(filename) ~= "string" then return nil end
    local path = string.lower(string.gsub(filename, "\\", "/"))
    if string.find(path, "placeables/bleachers/", 1, true) == nil then return nil end
    local rows, length = string.match(path, "bleachers(%d+)x(%d+)%.xml$")
    if rows == nil then return nil end
    return tonumber(rows), tonumber(length)
end


--- Every seat on a bleacher, in its own frame.
--- @param rows number
--- @param length number
--- @return table seats list of { row, x, y (bench top), z (hips' line), floorY (the tread below the feet), frontZ (bench front) }
function EqSpectators.seatsOf(rows, length)
    local seats = {}
    local half = length / 2
    local usable = length - 2 * EqSpectators.SEAT_END
    local count = math.max(1, math.floor(usable / EqSpectators.SEAT_WIDTH) + 1)
    for r = 0, rows - 1 do
        local tread = EqSpectators.BASE + r * EqSpectators.ROW_RISE
        local z0 = r * EqSpectators.ROW_DEPTH
        for i = 0, count - 1 do
            local x = count == 1 and 0 or (-half + EqSpectators.SEAT_END + usable * i / (count - 1))
            table.insert(seats, { row = r, x = x, y = tread + EqSpectators.BENCH_HEIGHT, floorY = tread,
                frontZ = z0 + EqSpectators.BENCH_FROM, z = z0 + EqSpectators.BENCH_FROM })
        end
    end
    return seats
end


--- Pick up to count items, in a shuffled order that depends only on the seed.
--- @param list table
--- @param count number
--- @param rng table EqRandom
--- @return table picked
function EqSpectators.pick(list, count, rng)
    local order = {}
    for i = 1, #list do order[i] = i end
    for i = #order, 2, -1 do
        local j = math.min(i, math.floor(rng:next() * i) + 1)
        order[i], order[j] = order[j], order[i]
    end
    local picked = {}
    for i = 1, math.min(count, #order) do picked[i] = list[order[i]] end
    return picked
end


--- @param hour number the hour of the day, 0-24
--- @return boolean true while spectators are there
function EqSpectators.inHours(hour)
    return hour >= EqSpectators.HOURS[1] and hour < EqSpectators.HOURS[2]
end


-- ---------------------------------------------------------------------------------------------
-- In game

local function farmId()
    local mission = g_currentMission
    return mission ~= nil and mission.getFarmId ~= nil and mission:getFarmId() or nil
end


local function placeables()
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    return system ~= nil and system.placeables or {}
end


local function ownerOf(placeable)
    return placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() or nil
end


local function terrainY(x, z)
    local mission = g_currentMission
    local terrain = mission ~= nil and mission.terrainRootNode or g_terrainNode
    if terrain == nil or getTerrainHeightAtWorldPos == nil then return 0 end
    return getTerrainHeightAtWorldPos(terrain, x, 0, z)
end


--- Nodes named name under a node (a rope with many panels has many).
local function findNamed(root, name, out)
    local stack, seen = { root }, 0
    while #stack > 0 and seen < 20000 do
        local node = table.remove(stack)
        seen = seen + 1
        if getName(node) == name then table.insert(out, node) end
        for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
    end
end


--- The farm's seats and rope spectator places.
--- @param farm number
--- @return table seats, table stands, table boxes (every box node, for showing them in construction)
function EqSpectators.places(farm)
    local seats, stands, boxes = {}, {}, {}
    EqSpectators.lastScan = { ropes = 0, owners = {} }
    for _, placeable in ipairs(placeables()) do
        local root = placeable.rootNode
        if type(root) == "number" and root ~= 0 and (entityExists == nil or entityExists(root)) then
            local rows, length = EqSpectators.bleacherSize(placeable.configFileName)
            local mine = ownerOf(placeable) == farm
            if rows ~= nil and mine then
                for _, seat in ipairs(EqSpectators.seatsOf(rows, length)) do
                    seat.parent = root
                    table.insert(seats, seat)
                end
            elseif EqSponsors ~= nil and EqSponsors.isRope(placeable.configFileName) then
                -- a fence is owned by farm 0: EqSponsors.ownerOf counts it as the player's farm
                local found = {}
                findNamed(root, EqSpectators.BOX_NODE, found)
                EqSpectators.lastScan.ropes = EqSpectators.lastScan.ropes + 1
                EqSpectators.lastScan.firstRope = EqSpectators.lastScan.firstRope or root
                EqSpectators.lastScan.owners[tostring(ownerOf(placeable))] = true
                local ours = EqSponsors.ownerOf(placeable) == farm
                for _, node in ipairs(found) do
                    table.insert(boxes, node)
                    if ours then
                        for slot = 1, EqSpectators.PER_BOX do table.insert(stands, { box = node, slot = slot, root = root }) end
                    end
                end
            end
        end
    end
    return seats, stands, boxes
end


-- A random look for each person: the default outfit with one of the style's presets on it.
--- @param name string|nil an outfit preset's or item's name
--- @return boolean true when spectators shouldn't wear it
function EqSpectators.unwearable(name)
    local lower = string.lower(tostring(name or ""))
    for _, word in ipairs(EqSpectators.NO_WEAR) do
        if string.find(lower, word, 1, true) ~= nil then return true end
    end
    return false
end


local function itemName(item)
    if type(item) ~= "table" then return tostring(item) end
    return tostring(item.name or item.id or item.filename or "")
end


--- Take off anything a spectator shouldn't wear: that slot goes back to its first (plain) item,
--- or the first wearable one.
local function sanitize(style)
    if type(style.configs) ~= "table" then return end
    for _, config in pairs(style.configs) do
        local items = type(config) == "table" and config.items or nil
        local selected = type(config) == "table" and config.selectedItemIndex or nil
        if type(items) == "table" and selected ~= nil and items[selected] ~= nil and EqSpectators.unwearable(itemName(items[selected])) then
            local replace = 1
            for i = 1, #items do
                if not EqSpectators.unwearable(itemName(items[i])) then replace = i break end
            end
            config.selectedItemIndex = replace
        end
    end
end


--- The outfit names in the log once, so unwanted ones can be added to NO_WEAR.
local function logOutfits(base)
    if EqSpectators.loggedOutfits then return end
    EqSpectators.loggedOutfits = true
    local presets = {}
    for _, preset in pairs(type(base.presets) == "table" and base.presets or {}) do
        table.insert(presets, itemName(preset) .. (EqSpectators.unwearable(itemName(preset)) and " (not worn)" or ""))
    end
    Log:info("EqSpectators: outfit presets: %s", table.concat(presets, ", "))
    for slot, config in pairs(type(base.configs) == "table" and base.configs or {}) do
        local names = {}
        for i, item in ipairs(type(config) == "table" and type(config.items) == "table" and config.items or {}) do
            if i <= 40 then table.insert(names, itemName(item)) end
        end
        Log:info("EqSpectators: outfit slot %s: %s", tostring(slot), table.concat(names, ", "))
    end
end


--- @param name string|nil a face or body item's name
--- @return string|nil the named FS25 character it belongs to (animal dealer, fisherman), or nil
function EqSpectators.namedCharacter(name)
    local lower = string.lower(tostring(name or ""))
    for _, word in ipairs(EqSpectators.NAMED) do
        if string.find(lower, word, 1, true) ~= nil then return word end
    end
    return nil
end


--- @return boolean true when a beard item is made for this face (beards are per head: goatee01_head02)
function EqSpectators.beardFits(beard, face)
    beard, face = tostring(beard or ""), tostring(face or "")
    return face ~= "" and string.sub(beard, -(#face + 1)) == "_" .. face
end


local function findItem(config, name)
    for i, item in ipairs(type(config) == "table" and type(config.items) == "table" and config.items or {}) do
        if itemName(item) == name then return i end
    end
    return nil
end


--- The male or female base style, loaded once (nil when the game won't load it).
local function baseStyle(female)
    local key = female and "female" or "male"
    EqSpectators.bases = EqSpectators.bases or {}
    if EqSpectators.bases[key] ~= nil then return EqSpectators.bases[key] or nil end
    local style = nil
    if not female then
        if PlayerStyle.defaultStyle ~= nil then
            local ok, result = pcall(PlayerStyle.defaultStyle)
            if ok then style = result end
        end
    else
        for _, method in ipairs({ "loadConfigurationXML", "loadConfigurationXMLFile", "loadFromXMLFile", "loadXML" }) do
            local candidate = PlayerStyle.new()
            if type(candidate[method]) == "function" then
                local ok = pcall(candidate[method], candidate, EqSpectators.FEMALE_XML)
                if ok and type(candidate.configs) == "table" and next(candidate.configs) ~= nil then
                    candidate.xmlFilename = candidate.xmlFilename or EqSpectators.FEMALE_XML
                    style = candidate
                    break
                end
            end
        end
        Log:info("EqSpectators: female characters %s", style ~= nil and "loaded" or "not available, men only")
    end
    EqSpectators.bases[key] = style or false
    return style
end


--- A random face, hair (and colour) and beard; named characters' faces at most once per crowd.
local function setLook(style, female, rng, used)
    local configs = type(style.configs) == "table" and style.configs or {}
    local face = configs.face
    local faces, named = {}, {}
    for i, item in ipairs(type(face) == "table" and type(face.items) == "table" and face.items or {}) do
        local who = EqSpectators.namedCharacter(itemName(item))
        if who == nil then table.insert(faces, i)
        elseif not used[who] then table.insert(named, i) end
    end
    local faceName = nil
    if #named > 0 and rng:next() < EqSpectators.NAMED_CHANCE then
        local i = named[math.floor(rng:next() * #named) + 1]
        local who = EqSpectators.namedCharacter(itemName(face.items[i]))
        used[who] = true
        face.selectedItemIndex, faceName = i, itemName(face.items[i])
        -- and their own clothes, when the style has them
        local body = findItem(configs.onepiece, "body" .. string.sub(faceName, 5))
        if body ~= nil then configs.onepiece.selectedItemIndex = body end
    elseif #faces > 0 then
        local i = faces[math.floor(rng:next() * #faces) + 1]
        face.selectedItemIndex, faceName = i, itemName(face.items[i])
    end
    local hair = configs.hairStyle
    if type(hair) == "table" and type(hair.items) == "table" then
        local hairs = {}
        for i, item in ipairs(hair.items) do
            if not string.find(string.lower(itemName(item)), "gear", 1, true) then table.insert(hairs, i) end
        end
        if #hairs > 0 then hair.selectedItemIndex = hairs[math.floor(rng:next() * #hairs) + 1] end
    end
    local beard = configs.beard
    if type(beard) == "table" and type(beard.items) == "table" then
        local fits = {}
        for i, item in ipairs(beard.items) do
            if EqSpectators.beardFits(itemName(item), faceName) then table.insert(fits, i) end
        end
        if female or #fits == 0 or rng:next() < 0.4 then
            beard.selectedItemIndex = 0
        else
            beard.selectedItemIndex = fits[math.floor(rng:next() * #fits) + 1]
        end
    end
    -- hair colour (beard matches), when the style keeps a colour per slot
    if type(hair) == "table" and type(hair.selectedColorIndex) == "number" then
        local colors = hair.colors or (hair.items ~= nil and hair.items[hair.selectedItemIndex or 1] ~= nil and hair.items[hair.selectedItemIndex or 1].colors) or nil
        local n = type(colors) == "table" and #colors or 0
        if n > 1 then
            hair.selectedColorIndex = math.floor(rng:next() * n) + 1
            if type(beard) == "table" and type(beard.selectedColorIndex) == "number" then beard.selectedColorIndex = hair.selectedColorIndex end
        end
    end
end


--- No named character's clothes on anyone else (a preset could pick them).
local function dropNamedBodies(style, used)
    for _, config in pairs(type(style.configs) == "table" and style.configs or {}) do
        local items = type(config) == "table" and config.items or nil
        local selected = type(config) == "table" and config.selectedItemIndex or nil
        if type(items) == "table" and selected ~= nil and items[selected] ~= nil and EqSpectators.namedCharacter(itemName(items[selected])) ~= nil
            and not used[EqSpectators.namedCharacter(itemName(items[selected]))] then
            config.selectedItemIndex = 1
        end
    end
end


--- The first style's slots, one line per slot with what's selected and the colour fields, once.
local function logSlots(style, female)
    local key = female and "loggedFemale" or "loggedMale"
    if EqSpectators[key] then return end
    EqSpectators[key] = true
    local parts = {}
    for slot, config in pairs(type(style.configs) == "table" and style.configs or {}) do
        if type(config) == "table" then
            local fields = {}
            for k, v in pairs(config) do if type(v) ~= "table" then table.insert(fields, tostring(k) .. "=" .. tostring(v)) end end
            table.insert(parts, tostring(slot) .. "(" .. table.concat(fields, " ") .. ")")
        end
    end
    Log:info("EqSpectators: %s slots: %s", female and "female" or "male", table.concat(parts, "; "))
end


--- A random person: man or woman, a face, hair and beard of their own, and one of the style's
--- outfit presets (James 2026-11-02: they were all the same man in different clothes).
local function styleFor(rng, used)
    if PlayerStyle == nil then return nil end
    used = used or {}
    local female = rng:next() < EqSpectators.FEMALE_SHARE and baseStyle(true) ~= nil
    local base = baseStyle(female)
    if base == nil and female then female, base = false, baseStyle(false) end
    if base == nil then return nil end
    if not female then EqLog.try("EqSpectators outfit names", logOutfits, base) end
    local presets = {}
    if type(base.presets) == "table" then
        for _, preset in pairs(base.presets) do
            if preset.applyToStyle ~= nil and not EqSpectators.unwearable(itemName(preset)) then
                table.insert(presets, preset)
            end
        end
    end
    local ok, copy = pcall(function()
        local copy = PlayerStyle.new()
        if copy.copyFrom ~= nil then copy:copyFrom(base) elseif copy.copyConfigurationFrom ~= nil then copy:copyConfigurationFrom(base) else return nil end
        copy.xmlFilename = copy.xmlFilename or base.xmlFilename
        if #presets > 0 then
            presets[math.min(#presets, math.floor(rng:next() * #presets) + 1)]:applyToStyle(copy)
        end
        return copy
    end)
    if not ok or copy == nil then return base end
    EqLog.try("EqSpectators outfit", sanitize, copy)
    EqLog.try("EqSpectators look", setLook, copy, female, rng, used)
    EqLog.try("EqSpectators named clothes", dropNamedBodies, copy, used)
    EqLog.try("EqSpectators slots", logSlots, copy, female)
    return copy
end


local function clipIndex(charset, names)
    for _, name in ipairs(names) do
        local index = getAnimClipIndex(charset, name)
        if index ~= nil and index >= 0 then return index, name end
    end
    return nil
end


--- Put the game's animations on a loaded character and start an idle clip.
local function startIdle(person)
    local skeleton = person.model.skeleton
    if skeleton == nil or g_animCache == nil or AnimationCache == nil then return end
    local driver = person.seated and EqSpectators.pose.seatClip == 0
    local cacheId = driver and (AnimationCache.VEHICLE_CHARACTER or AnimationCache.CHARACTER) or AnimationCache.CHARACTER
    local animNode = g_animCache:getNode(cacheId)
    if animNode == nil or animNode == 0 then return end
    cloneAnimCharacterSet(getChildAt(animNode, 0), skeleton)
    local charset = getAnimCharacterSet(skeleton)
    if (charset == nil or charset == 0) and getNumOfChildren(skeleton) > 0 then charset = getAnimCharacterSet(getChildAt(skeleton, 0)) end
    if charset == nil or charset == 0 then return end
    if not EqSpectators.loggedSetup then
        EqSpectators.loggedSetup = true
        local names = {}
        for i = 0, math.min(getAnimNumOfClips(charset), 60) - 1 do table.insert(names, getAnimClipName(charset, i)) end
        Log:info("EqSpectators: %s clips: %s", person.seated and "seated" or "standing", table.concat(names, ", "))
    end
    local names = driver and { EqSpectators.SEAT_CLIP } or {}
    if not driver then
        -- start the list at a random clip, so the crowd doesn't all idle the same way
        local n = #EqSpectators.STAND_CLIPS
        local first = math.floor(person.rng:next() * n)
        for i = 0, n - 1 do table.insert(names, EqSpectators.STAND_CLIPS[(first + i) % n + 1]) end
    end
    local clip, name = clipIndex(charset, names)
    if clip == nil then return end
    clearAnimTrackClip(charset, 0)
    assignAnimTrackClip(charset, 0, clip)
    setAnimTrackLoopState(charset, 0, true)
    if getAnimClipDuration ~= nil and setAnimTrackTime ~= nil then
        pcall(setAnimTrackTime, charset, 0, person.rng:next() * (getAnimClipDuration(charset, clip) or 0), true)
    end
    enableAnimTrack(charset, 0)
    person.charset, person.clip = charset, name
end


--- Seated: targets for the feet and hands, in the seat's frame (+z the way the person faces).
--- @return boolean true when the hands are placed by IK (not with arms 0 or the standing clip)
function EqSpectators.armsOn()
    return EqSpectators.pose.arms ~= 0 and EqSpectators.pose.seatClip == 0
end


local function placeTargets(person)
    local p = EqSpectators.pose
    local drop = person.seat.y - person.seat.floorY
    local spots = {
        leftFoot = { p.footApart, -drop, p.footForward },
        rightFoot = { -p.footApart, -drop, p.footForward },
        leftArm = { p.handApart, p.handLift, p.handForward },
        rightArm = { -p.handApart, p.handLift, p.handForward },
    }
    for id, at in pairs(spots) do
        local node = person.targets[id]
        if node ~= nil then setTranslation(node, at[1], at[2], at[3]) end
    end
    local chains = person.model ~= nil and person.model:getIKChains() or nil
    for id, side in pairs(EqSpectators.ARM_CHAINS) do
        local node = person.targets[id]
        if node ~= nil then
            setRotation(node, math.rad(p.handPitch), math.rad(p.handYaw * side), math.rad(p.handRoll * side))
            if chains ~= nil then
                local on = EqSpectators.armsOn()
                if on and IKUtil.setIKChainActive ~= nil then pcall(IKUtil.setIKChainActive, chains, id) end
                if not on and IKUtil.setIKChainInactive ~= nil then pcall(IKUtil.setIKChainInactive, chains, id) end
            end
        end
    end
end


--- Seated: lower the character until its hips sit on the bench (measured once it is posed).
local function settle(person)
    local model = person.model
    local hips = model.thirdPersonHipsNode
    if hips == nil then return true end
    setTranslation(model.rootNode, 0, 0, 0)
    local hx, hy, hz = worldToLocal(person.holder, getWorldTranslation(hips))
    local p = EqSpectators.pose
    -- the holder sits on the bench's front edge; hips go up hipLift and back hipBack (-z)
    setTranslation(model.rootNode, -hx, p.hipLift - hy, -p.hipBack - hz)
    if not person.loggedHips then
        person.loggedHips = true
        if not EqSpectators.loggedHips then
            EqSpectators.loggedHips = true
            local chains = {}
            for id in pairs(model:getIKChains() or {}) do table.insert(chains, tostring(id)) end
            Log:info("EqSpectators: hips %.2f m above the character's root (%.2f, %.2f); IK chains: %s", hy, hx, hz, table.concat(chains, ", "))
        end
    end
    return true
end


--- Standing: lift the character until its feet are on the ground (James 2026-11-02: the first
--- ones stood waist deep; the character's root is near its hips, not its feet).
local function ground(person)
    local model = person.model
    local left, right = model.thirdPersonLeftFootNode, model.thirdPersonRightFootNode
    if left == nil and right == nil then return true end
    setTranslation(model.rootNode, 0, 0, 0)
    local low = math.huge
    for _, foot in ipairs({ left, right }) do
        if foot ~= nil then
            local _, y = worldToLocal(person.holder, getWorldTranslation(foot))
            low = math.min(low, y)
        end
    end
    setTranslation(model.rootNode, 0, EqSpectators.pose.ankle - low, 0)
    if not EqSpectators.loggedFeet then
        EqSpectators.loggedFeet = true
        Log:info("EqSpectators: standing feet %.2f m from the character's root, lifted to the ground", low)
    end
    return true
end


local function onModelLoaded(_, state, person)
    local model = person.model
    if person.deleted or model == nil then
        if model ~= nil then model:delete() end
        return
    end
    if HumanModelLoadingState == nil or state ~= HumanModelLoadingState.OK or model.rootNode == nil then
        Log:warning("EqSpectators: a spectator's character didn't load (%s)", tostring(state))
        person.failed = true
        return
    end
    link(person.holder, model.rootNode)
    EqLog.try("EqSpectators idle", startIdle, person)
    if person.seated then
        local chains = model:getIKChains()
        for _, id in ipairs(EqSpectators.CHAINS) do
            if chains ~= nil and chains[id] ~= nil then
                local node = createTransformGroup("eqSpectator_" .. id)
                link(person.holder, node)
                person.targets[id] = node
                IKUtil.setTarget(chains, id, { targetNode = node })
                if IKUtil.setIKChainActive ~= nil then pcall(IKUtil.setIKChainActive, chains, id) end
            end
        end
        placeTargets(person)
    end
    model:setVisibility(false)
    local style = person.style
    if style == nil then
        person.ready = true
        return
    end
    model:loadFromStyleAsync(style, function(_, styleState)
        if person.deleted then return end
        person.ready = HumanModelLoadingState == nil or styleState == HumanModelLoadingState.OK
        if not person.ready then person.ready = true end   -- shown in the default look anyway
    end, nil, nil)
end


--- Make one person: seat = { parent, x, y, frontZ, floorY } or stand = { box, slot }.
local function spawn(seat, stand, rng, used)
    if HumanModel == nil or PlayerStyle == nil then return nil end
    local style = styleFor(rng, used)
    if style == nil or style.xmlFilename == nil then return nil end
    local holder = createTransformGroup("eqSpectator")
    local person = { seated = seat ~= nil, seat = seat, stand = stand, holder = holder, targets = {}, rng = rng, frames = 0, style = style }
    if seat ~= nil then
        link(seat.parent, holder)
        -- on the bench's front edge, turned to face the bleacher's front (-z)
        setTranslation(holder, seat.x, seat.y, seat.frontZ)
        setRotation(holder, 0, math.pi, 0)
    else
        local box = EqSpectators.ROPE_BOX
        local half = (EqSpectators.ROPE_PANEL - 2 * EqSpectators.ROPE_INSET) / 2
        local lane = (stand.slot - 0.5) / EqSpectators.PER_BOX     -- each slot its own half of the box
        local lx = rng:uniform(box[1] + 0.25, box[2] - 0.25)
        local lz = EqSpectators.ROPE_INSET + 0.3 + (2 * half - 0.6) * (lane + rng:uniform(-0.2, 0.2))
        local x, _, z = localToWorld(stand.box, lx, 0, lz)
        local dx, _, dz = localDirectionToWorld(stand.box, -1, 0, 0)
        link(getRootNode(), holder)
        setWorldTranslation(holder, x, terrainY(x, z), z)
        setWorldRotation(holder, 0, math.atan2(dx, dz) + rng:uniform(-0.5, 0.5), 0)
    end
    person.model = HumanModel.new()
    person.model:load(style.xmlFilename, false, false, false, onModelLoaded, EqSpectators, person)
    return person
end


local function remove(person)
    person.deleted = true
    if person.model ~= nil and person.model.rootNode ~= nil then
        EqLog.try("EqSpectators delete model", person.model.delete, person.model)
    end
    person.model = nil
    if person.holder ~= nil and (entityExists == nil or entityExists(person.holder)) then delete(person.holder) end
    person.holder = nil
end


local function exists(node)
    return node ~= nil and (entityExists == nil or entityExists(node))
end


--- @return boolean true when a person's bleacher or rope panel is gone (sold, or a rope segment deleted)
local function placeGone(person)
    if not exists(person.holder) then return true end
    if person.seat ~= nil then return not exists(person.seat.parent) end
    return person.stand ~= nil and not exists(person.stand.box)
end


--- Take away anyone whose place is gone; the next scan picks a new crowd from what is left.
--- @return boolean true when someone was taken away
function EqSpectators.dropGone()
    local kept, dropped = {}, false
    for _, person in ipairs(EqSpectators.people) do
        if placeGone(person) then
            dropped = true
            person.deleted = true
            -- a sold bleacher took the character's nodes with it: only forget it then
            if exists(person.holder) then pcall(remove, person) end
            person.model, person.holder = nil, nil
        else
            table.insert(kept, person)
        end
    end
    if dropped then
        EqSpectators.people = kept
        EqSpectators.key, EqSpectators.scannedAt = nil, nil
    end
    return dropped
end


--- A placeable is about to be sold or deleted: take its spectators off first, while their nodes
--- still exist (a seated person's are under the bleacher's).
--- @param placeable table
function EqSpectators.onPlaceableDeleted(placeable)
    local root = placeable ~= nil and placeable.rootNode or nil
    if root == nil or #EqSpectators.people == 0 then return end
    local kept, dropped = {}, false
    for _, person in ipairs(EqSpectators.people) do
        if (person.seat ~= nil and person.seat.parent == root) or (person.stand ~= nil and person.stand.root == root) then
            dropped = true
            EqLog.try("EqSpectators remove", remove, person)
        else
            table.insert(kept, person)
        end
    end
    if dropped then
        EqSpectators.people = kept
        EqSpectators.key, EqSpectators.scannedAt = nil, nil
    end
end


function EqSpectators.clear()
    for _, person in ipairs(EqSpectators.people) do EqLog.try("EqSpectators remove", remove, person) end
    EqSpectators.people = {}
    EqSpectators.key = nil
end


--- Fill the farm's places: counts.seated on the bleachers, counts.standing in rope boxes.
function EqSpectators.spawnAll(farm, counts, seed, seats, stands)
    EqSpectators.clear()
    local rng = EqRandom.new(seed)
    -- named FS25 characters (animal dealer, fisherman) at most once in the crowd (James 2026-11-02)
    local used = {}
    for _, seat in ipairs(EqSpectators.pick(seats, counts.seated, rng)) do
        local person = spawn(seat, nil, EqRandom.new(math.floor(rng:next() * 2147483000) + 1), used)
        if person ~= nil then table.insert(EqSpectators.people, person) end
    end
    for _, stand in ipairs(EqSpectators.pick(stands, counts.standing, rng)) do
        local person = spawn(nil, stand, EqRandom.new(math.floor(rng:next() * 2147483000) + 1), used)
        if person ~= nil then table.insert(EqSpectators.people, person) end
    end
    Log:info("EqSpectators: %d people (%d seats and %d rope places on farm %s; %d Rope Marker(s) seen)", #EqSpectators.people, #seats, #stands,
        tostring(farm), EqSpectators.lastScan.ropes)
end


--- @return boolean true while one of the farm's hosted events runs
local function hostedRunning(farm)
    for _, event in pairs(EqCompetitionManager ~= nil and EqCompetitionManager.events or {}) do
        if event.hosted ~= nil and event.hosted.farmId == farm then return true end
    end
    return false
end


local function hourNow()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment == nil or environment.dayTime == nil then return 12 end
    return environment.dayTime / 3600000
end


local function dayNow()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    return environment ~= nil and environment.currentDay or 0
end


--- Rope Markers stay in sight (no collision) while your hosted event runs, all day, and while
--- the console shows the crowd: they're the spectators' barrier (James, 2026-11-02). EqXcHide asks.
--- @return boolean
function EqSpectators.ropesShown()
    if EqSpectators.forced == true then return true end
    if EqSpectators.forced == false then return false end
    local farm = farmId()
    return farm ~= nil and hostedRunning(farm)
end


--- The counts wanted now: from the console, or the setting during a hosted event's hours.
local function wanted(farm)
    local density = EqSpectators.density(EqCompetitionManager ~= nil and EqCompetitionManager.settings or nil)
    if EqSpectators.forced == false then return nil end
    if EqSpectators.forced == true then
        return EqSpectators.forcedCounts or EqSpectators.COUNTS[density == "off" and EqSpectators.DEFAULT or density], density
    end
    if density == "off" or not EqSpectators.inHours(hourNow()) or not hostedRunning(farm) then return nil end
    return EqSpectators.COUNTS[density], density
end


--- Each frame: spawn or clear the crowd, hide far people, keep seated ones posed.
function EqSpectators.update()
    local now = g_time or 0
    local farm = farmId()
    if farm == nil then return end
    if EqSpectators.scannedAt == nil or now - EqSpectators.scannedAt >= EqSpectators.SCAN_MS or now < EqSpectators.scannedAt then
        EqSpectators.scannedAt = now
        local counts, density = wanted(farm)
        local seats, stands, boxes = EqSpectators.places(farm)
        EqSpectators.boxes = boxes
        EqSpectators.boxesShown = nil
        if counts == nil then
            if #EqSpectators.people > 0 then EqSpectators.clear() end
        else
            local key = string.format("%d/%s/%d/%d/%d/%d", dayNow(), tostring(density), counts.seated, counts.standing, #seats, #stands)
            if key ~= EqSpectators.key then
                EqSpectators.spawnAll(farm, counts, dayNow() * 7919 + farm * 31 + 17, seats, stands)
                EqSpectators.key = key
            end
        end
    end

    -- the spectator boxes show only in construction mode
    local construction = EqXcFlags ~= nil and EqXcFlags.inConstruction() or false
    if EqSpectators.boxesShown ~= construction then
        EqSpectators.boxesShown = construction
        for _, node in ipairs(EqSpectators.boxes) do
            if entityExists == nil or entityExists(node) then setVisibility(node, construction) end
        end
    end

    if #EqSpectators.people == 0 then return end
    EqSpectators.dropGone()
    local camera = g_cameraManager ~= nil and g_cameraManager:getActiveCamera() or nil
    if camera == nil or camera == 0 then return end
    local cx, cy, cz = getWorldTranslation(camera)
    for _, person in ipairs(EqSpectators.people) do
        local model = person.model
        if person.ready and model ~= nil and model.rootNode ~= nil then
            person.frames = person.frames + 1
            -- the idle pose is in place after a frame or two: then the hips can be measured
            if not person.settled and person.frames >= 3 then
                if person.seated then person.settled = settle(person) else person.settled = ground(person) end
            end
            local shown = person.settled
            local x, y, z = getWorldTranslation(person.holder)
            local distance = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2)
            local visible = shown and distance <= EqSpectators.VISIBLE_DISTANCE
            if visible ~= person.visible then
                person.visible = visible
                model:setVisibility(visible)
            end
            -- seated: live within IK_DISTANCE, and for the first few frames once settled so the
            -- held pose is a seated one; standing: the clip plays while seen
            local live = visible
            if person.seated then
                if person.settled then person.posed = (person.posed or 0) + 1 end
                live = (visible and distance <= EqSpectators.IK_DISTANCE) or not person.settled
                    or person.posed <= EqSpectators.POSE_FRAMES
            end
            if person.charset ~= nil and live ~= person.animating then
                person.animating = live
                if live then enableAnimTrack(person.charset, 0) else disableAnimTrack(person.charset, 0) end
            end
            if person.seated and live then
                local chains = model:getIKChains()
                for id in pairs(person.targets) do
                    if EqSpectators.armsOn() or EqSpectators.ARM_CHAINS[id] == nil then IKUtil.setIKChainDirty(chains, id) end
                end
                IKUtil.updateIKChains(chains, true)
            end
        end
    end
end


--- Seated people take a changed pose (eqSpectators pose).
function EqSpectators.repose()
    for _, person in ipairs(EqSpectators.people) do
        if person.seated and person.model ~= nil and person.model.rootNode ~= nil then
            placeTargets(person)
            if person.settled then settle(person) end
            person.posed = 0     -- solve the new pose again, near or far
        elseif not person.seated and person.settled and person.model ~= nil and person.model.rootNode ~= nil then
            ground(person)
        end
    end
end


--- eqSpectators [on [seated standing] | off | auto | pose <name> <value> | info]
function EqSpectators.console(command, a, b)
    command = string.lower(tostring(command or "info"))
    if command == "on" then
        EqSpectators.forced = true
        local seated, standing = tonumber(a), tonumber(b)
        EqSpectators.forcedCounts = seated ~= nil and { seated = math.max(0, math.floor(seated)), standing = math.max(0, math.floor(standing or seated)) } or nil
        EqSpectators.key, EqSpectators.scannedAt = nil, nil
        return "Spectators shown now, on your bleachers and rope spectator boxes nearby (eqSpectators auto to go back to normal)"
    elseif command == "off" then
        EqSpectators.forced = false
        EqSpectators.scannedAt = nil
        return "Spectators hidden until eqSpectators auto"
    elseif command == "auto" then
        EqSpectators.forced, EqSpectators.forcedCounts = nil, nil
        EqSpectators.key, EqSpectators.scannedAt = nil, nil
        return "Spectators come to your hosted events (08:00-19:00) as the Crowd density setting says"
    elseif command == "pose" then
        local value = tonumber(b)
        if a ~= nil and EqSpectators.pose[a] ~= nil and value ~= nil then
            EqSpectators.pose[a] = value
            EqSpectators.repose()
            -- the idle clip is chosen as a person loads: seat everyone again
            if a == "seatClip" then EqSpectators.key, EqSpectators.scannedAt = nil, nil end
        end
        local parts = {}
        for name, v in pairs(EqSpectators.pose) do table.insert(parts, string.format("%s=%.2f", name, v)) end
        table.sort(parts)
        return "Seated pose: " .. table.concat(parts, "  ") .. "  (eqSpectators pose <name> <value>: metres; hand angles in degrees; arms 0 = no hand IK; seatClip 1 = sit with the standing idle)"
    end
    local farm = farmId()
    local seats, stands = {}, {}
    if farm ~= nil then seats, stands = EqSpectators.places(farm) end
    local ready = 0
    for _, person in ipairs(EqSpectators.people) do if person.ready then ready = ready + 1 end end
    local scan = EqSpectators.lastScan or { ropes = 0, owners = {} }
    local owners = {}
    for owner in pairs(scan.owners) do table.insert(owners, owner) end
    if scan.firstRope ~= nil and (entityExists == nil or entityExists(scan.firstRope)) then
        -- the first rope's node names, to see where the game puts the fence panels
        local names, stack = {}, { { scan.firstRope, 0 } }
        while #stack > 0 and #names < 60 do
            local entry = table.remove(stack, 1)
            table.insert(names, string.rep(">", entry[2]) .. tostring(getName(entry[1])))
            if entry[2] < 5 then
                for i = 0, math.min(getNumOfChildren(entry[1]), 6) - 1 do table.insert(stack, { getChildAt(entry[1], i), entry[2] + 1 }) end
            end
        end
        print("EqSpectators: first Rope Marker's nodes: " .. table.concat(names, " "))
    end
    print(string.format("EqSpectators: %d Rope Marker(s) on the map (owner farms %s, you are farm %s), %d spectator box(es)",
        scan.ropes, table.concat(owners, ","), tostring(farm), math.floor(#stands / EqSpectators.PER_BOX)))
    return string.format("Crowd density %s; %d people (%d loaded); %d free seats on your bleachers, %d rope places; mode %s. Usage: eqSpectators [on [seated standing] | off | auto | pose <name> <metres> | info]",
        EqSpectators.density(EqCompetitionManager ~= nil and EqCompetitionManager.settings or nil), #EqSpectators.people, ready,
        #seats, #stands, EqSpectators.forced == nil and "auto" or (EqSpectators.forced and "on" or "off"))
end


function EqSpectators.reset()
    EqSpectators.clear()
    EqSpectators.boxes = {}
    EqSpectators.scannedAt, EqSpectators.boxesShown = nil, nil
    EqSpectators.forced, EqSpectators.forcedCounts = nil, nil
    EqSpectators.failed = false
end


function EqSpectators.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive or EqSpectators.failed then return end
        local ok = EqLog.try("EqSpectators update", EqSpectators.update)
        if not ok then
            EqSpectators.failed = true
            Log:warning("EqSpectators: stopped after that error; no spectators this session")
            EqLog.try("EqSpectators clear", EqSpectators.clear)
        end
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        guarded("spectators cleanup", EqSpectators.reset)
    end)
    -- a sold bleacher or rope takes its spectators with it, cleanly
    if Placeable ~= nil and Placeable.delete ~= nil then
        Placeable.delete = Utils.prependedFunction(Placeable.delete, function(placeable)
            if not EqMain.isActive then return end
            EqLog.try("EqSpectators placeable deleted", EqSpectators.onPlaceableDeleted, placeable)
        end)
    end
end

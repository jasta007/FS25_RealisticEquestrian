--[[
    EqHosting.lua
    Hosting your own event (James, 2026-10-28): what each rating asks of the farm, how popular
    the event is, and what it costs and earns. Pure functions with no game calls, so they run
    headless; EqHostVenue reads the farm (courses, arenas, bleachers, stables, feed) into a
    plain venue table for them.

    A venue is { courses = { { name, kind, jumps, length, seating, indoor } },
    arenas = { { name, length, seating, indoor } }, freePlaces, feed, feedPerHorse, facilityKinds }:
    seating is the bleachers near that course or arena, indoor whether it is in an indoor
    arena, feed the litres of horse feed in troughs and storage, feedPerHorse a visiting horse's
    ration for the month. See data/hosting.xml for the numbers.

    Part of Realistic Equestrian by Jasta007.
]]

EqHosting = {}

-- Event types, by the events.xml discipline they run as. A 3 Day Event is eventing.
EqHosting.TYPES = { "dressage", "showJumping", "crossCountry", "eventing" }
EqHosting.EVENTING = "eventing"

-- Our arenas' A and C boards stand just outside the rail, so a 20x40 measures a little over
-- 40 m from A to C: the first row whose length the A to C distance reaches is the arena.
EqHosting.ARENA_SIZES = {
    { from = 50, length = 60 },
    { from = 36, length = 40 },
    { from = 26, length = 30 },
}
-- Loose letter boards (Riding Hall) make an arena when an A has a C within this many metres.
EqHosting.LOOSE_ARENA_MAX = 80

local Log = EqLog


--- @param path string|nil
--- @return string path lowercased, with forward slashes
local function normalise(path)
    return string.lower(string.gsub(path or "", "\\", "/"))
end


--- @param xmlFile table An open XMLFile on hosting.xml
--- @return table config { ratings, ratingByName, popularity, seating = { matches, keywords }, ... }
function EqHosting.read(xmlFile)
    local config = {
        ownPlaces = xmlFile:getInt("hosting#ownPlaces", 2),
        seatingRadius = xmlFile:getFloat("hosting#seatingRadius", 60),
        eventingSetupFactor = xmlFile:getFloat("hosting#eventingSetupFactor", 1.5),
        eventingFeeFactor = xmlFile:getFloat("hosting#eventingFeeFactor", 2),
        turnoutMin = xmlFile:getFloat("hosting#turnoutMin", 0.5),
        ratings = {}, ratingByName = {},
        seating = { matches = {}, keywords = {} },
    }

    local i = 0
    while true do
        local key = string.format("hosting.ratings.rating(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local rating = {
            name = xmlFile:getString(key .. "#name"),
            tier = xmlFile:getString(key .. "#tier"),
            field = xmlFile:getInt(key .. "#field", 8),
            setupFee = xmlFile:getFloat(key .. "#setupFee", 0),
            entryFee = xmlFile:getFloat(key .. "#entryFee", 0),
            gate = xmlFile:getFloat(key .. "#gate", 0),
            seating = xmlFile:getInt(key .. "#seating", 0),
            dressageArena = xmlFile:getFloat(key .. "#dressageArena", 30),
            dressageMoves = xmlFile:getInt(key .. "#dressageMoves", 15),
            showJumps = xmlFile:getInt(key .. "#showJumps", 6),
            xcLength = xmlFile:getFloat(key .. "#xcLength", 3000),
            xcJumps = xmlFile:getInt(key .. "#xcJumps", 20),
        }
        table.insert(config.ratings, rating)
        config.ratingByName[rating.name] = rating
        i = i + 1
    end

    local p = "hosting.popularity"
    config.popularity = {
        base = xmlFile:getFloat(p .. "#base", 30),
        course = xmlFile:getFloat(p .. "#course", 15),
        courseFullAt = xmlFile:getFloat(p .. "#courseFullAt", 0.25),
        seating = xmlFile:getFloat(p .. "#seating", 15),
        seatingEach = xmlFile:getFloat(p .. "#seatingEach", 5),
        indoor = xmlFile:getFloat(p .. "#indoor", 5),
        facilities = xmlFile:getFloat(p .. "#facilities", 10),
        facilitiesEach = xmlFile:getFloat(p .. "#facilitiesEach", 5),
        reputationMin = xmlFile:getFloat(p .. "#reputationMin", -25),
        reputationMax = xmlFile:getFloat(p .. "#reputationMax", 20),
        success = xmlFile:getFloat(p .. "#success", 8),
        cancel = xmlFile:getFloat(p .. "#cancel", -15),
        star = xmlFile:getFloat(p .. "#star", 10),
        winter = xmlFile:getFloat(p .. "#winter", -10),
    }

    for _, element in ipairs({ "match", "keyword" }) do
        local j = 0
        while true do
            local key = string.format("hosting.seating.%s(%d)", element, j)
            if not xmlFile:hasProperty(key) then break end
            if element == "match" then
                local xml = xmlFile:getString(key .. "#xml")
                if xml ~= nil then table.insert(config.seating.matches, { kind = "seating", value = normalise(xml) }) end
            else
                local pattern = xmlFile:getString(key .. "#pattern")
                if pattern ~= nil then table.insert(config.seating.keywords, { kind = "seating", value = string.lower(pattern) }) end
            end
            j = j + 1
        end
    end

    return config
end


--- @param path string
--- @return table|nil config
function EqHosting.load(path)
    local xmlFile = XMLFile.load("eqHosting", path)
    if xmlFile == nil then
        Log:error("EqHosting: could not open %s", path)
        return nil
    end
    local config = EqHosting.read(xmlFile)
    xmlFile:delete()
    Log:info("EqHosting: %d ratings, %d bleacher matches, %d keywords", #config.ratings, #config.seating.matches,
        #config.seating.keywords)
    return config
end


--- @param config table
--- @param xmlFilename string|nil a placeable's xml
--- @return boolean true for a bleacher or grandstand
function EqHosting.isSeatingXml(config, xmlFilename)
    -- The seating lists have the shape of facilities.xml's, so the facility matcher reads them.
    return EqFacility.kindForXml(config.seating, xmlFilename, false) == "seating"
end


--- @param typeName string
--- @return boolean
function EqHosting.isType(typeName)
    for _, name in ipairs(EqHosting.TYPES) do
        if name == typeName then return true end
    end
    return false
end


--- @param length number metres from an arena's A to its C
--- @return number nominal 30, 40 or 60, 0 when too small to be an arena
function EqHosting.arenaLength(length)
    for _, size in ipairs(EqHosting.ARENA_SIZES) do
        if length >= size.from then return size.length end
    end
    return 0
end


local function distance(ax, az, bx, bz)
    return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end


--- Dressage arenas from the map's letters (EqDressageHooks.scan): one per arena placeable of
--- ours, and one per loose A with a C near it.
--- @param markers table list of { letter, x, z, arena, arenaId }
--- @return table arenas list of { x, z, length (nominal), measured, halfLength }
function EqHosting.arenasFromMarkers(markers)
    local groups, order = {}, {}
    local looseA, looseC = {}, {}
    for _, marker in ipairs(markers) do
        if marker.arena and marker.arenaId ~= nil then
            local group = groups[marker.arenaId]
            if group == nil then
                group = {}
                groups[marker.arenaId] = group
                table.insert(order, marker.arenaId)
            end
            if marker.letter == "A" then group.a = marker elseif marker.letter == "C" then group.c = marker end
        elseif marker.letter == "A" then
            table.insert(looseA, marker)
        elseif marker.letter == "C" then
            table.insert(looseC, marker)
        end
    end

    local pairsFound = {}
    for _, id in ipairs(order) do
        local group = groups[id]
        if group.a ~= nil and group.c ~= nil then table.insert(pairsFound, { a = group.a, c = group.c }) end
    end
    local usedC = {}
    for _, a in ipairs(looseA) do
        local best, bestDistance = nil, EqHosting.LOOSE_ARENA_MAX
        for i, c in ipairs(looseC) do
            local d = distance(a.x, a.z, c.x, c.z)
            if not usedC[i] and d <= bestDistance then best, bestDistance = i, d end
        end
        if best ~= nil then
            usedC[best] = true
            table.insert(pairsFound, { a = a, c = looseC[best] })
        end
    end

    local arenas = {}
    for _, pair in ipairs(pairsFound) do
        local measured = distance(pair.a.x, pair.a.z, pair.c.x, pair.c.z)
        local length = EqHosting.arenaLength(measured)
        if length > 0 then
            table.insert(arenas, { x = (pair.a.x + pair.c.x) / 2, z = (pair.a.z + pair.c.z) / 2, length = length,
                measured = measured, halfLength = measured / 2 })
        end
    end
    return arenas
end


--- @param part table a course or arena
--- @return number seating it counts: its bleachers, and one for an indoor arena
local function seatingOf(part)
    return (part.seating or 0) + (part.indoor and 1 or 0)
end


--- The best show jumping course for a rating: the one that passes with the most jumps to
--- spare, else the one nearest passing.
--- @param courses table
--- @param rating table
--- @return table|nil course, number extra share of jumps above the minimum
local function pickShowJumping(courses, rating)
    local best, bestKey = nil, nil
    for _, course in ipairs(courses) do
        if course.kind == "showJumping" then
            local jumpsOk = course.jumps >= rating.showJumps
            local seatOk = seatingOf(course) >= rating.seating
            local key = (jumpsOk and 2 or 0) + (seatOk and 1 or 0) + course.jumps / 1000 + seatingOf(course) / 1e6
            if bestKey == nil or key > bestKey then best, bestKey = course, key end
        end
    end
    if best == nil then return nil, 0 end
    return best, math.max(0, best.jumps / math.max(1, rating.showJumps) - 1)
end


--- @param courses table
--- @param rating table
--- @return table|nil course, number extra the average share above the minimum length and jumps
local function pickCrossCountry(courses, rating)
    local best, bestKey = nil, nil
    for _, course in ipairs(courses) do
        if course.kind == "crossCountry" then
            local lengthShare = (course.length or 0) / math.max(1, rating.xcLength)
            local jumpsShare = course.jumps / math.max(1, rating.xcJumps)
            local passes = (lengthShare >= 1 and 1 or 0) + (jumpsShare >= 1 and 1 or 0)
            local key = passes * 10 + math.min(lengthShare, 5) + math.min(jumpsShare, 5)
            if bestKey == nil or key > bestKey then best, bestKey = course, key end
        end
    end
    if best == nil then return nil, 0 end
    local extra = ((best.length or 0) / math.max(1, rating.xcLength) - 1 + best.jumps / math.max(1, rating.xcJumps) - 1) / 2
    return best, math.max(0, extra)
end


--- @param arenas table
--- @param rating table
--- @return table|nil arena, number extra 1 for an arena bigger than the rating needs, else 0
local function pickArena(arenas, rating)
    local best, bestKey = nil, nil
    for _, arena in ipairs(arenas) do
        local sizeOk = arena.length >= rating.dressageArena
        local seatOk = seatingOf(arena) >= rating.seating
        local key = (sizeOk and 2 or 0) + (seatOk and 1 or 0) + arena.length / 1000 + seatingOf(arena) / 1e6
        if bestKey == nil or key > bestKey then best, bestKey = arena, key end
    end
    if best == nil then return nil, 0 end
    return best, best.length > rating.dressageArena and 1 or 0
end


--- @param typeName string
--- @param part string "dressage", "showJumping" or "crossCountry"
--- @return boolean true when the event type has this part
function EqHosting.hasPart(typeName, part)
    return typeName == part or typeName == EqHosting.EVENTING
end


--- How many visiting horses an event brings: the field less the places kept for your own.
--- @param config table
--- @param rating table
--- @return number
function EqHosting.visitors(config, rating)
    return math.max(0, rating.field - config.ownPlaces)
end


--- @param config table
--- @param typeName string
--- @param rating table
--- @return number fee the setup fee
function EqHosting.setupFee(config, typeName, rating)
    local factor = typeName == EqHosting.EVENTING and config.eventingSetupFactor or 1
    return math.floor(rating.setupFee * factor + 0.5)
end


--- Check a farm against a rating's requirements.
--- @param config table
--- @param typeName string one of EqHosting.TYPES
--- @param ratingName string
--- @param venue table see the top of this file
--- @return table result { ok, checks = list of { id, ok, have, need }, picks = { showJumping, crossCountry, dressage },
---     extra (course beyond the minimum, a share), seatingExtra, seatingTotal, indoor, visitors, feedNeed, setupFee }
function EqHosting.check(config, typeName, ratingName, venue)
    local rating = config.ratingByName[ratingName]
    local result = { ok = true, checks = {}, picks = {}, extras = {}, seatingExtra = 0, seatingTotal = 0, indoor = false }
    if rating == nil or not EqHosting.isType(typeName) then
        result.ok = false
        return result
    end

    local function add(id, have, need)
        local ok = have >= need
        table.insert(result.checks, { id = id, ok = ok, have = have, need = need })
        if not ok then result.ok = false end
    end
    local function seat(part, id)
        local have = part ~= nil and seatingOf(part) or 0
        if rating.seating > 0 then add(id, have, rating.seating) end
        result.seatingTotal = result.seatingTotal + have
        result.seatingExtra = result.seatingExtra + math.max(0, have - rating.seating)
        if part ~= nil and part.indoor then result.indoor = true end
    end

    if EqHosting.hasPart(typeName, "dressage") then
        local arena, extra = pickArena(venue.arenas or {}, rating)
        result.picks.dressage = arena
        table.insert(result.extras, extra)
        add("arena", arena ~= nil and arena.length or 0, rating.dressageArena)
        seat(arena, "dressageSeating")
    end
    if EqHosting.hasPart(typeName, "showJumping") then
        local course, extra = pickShowJumping(venue.courses or {}, rating)
        result.picks.showJumping = course
        table.insert(result.extras, extra)
        add("showJumps", course ~= nil and course.jumps or 0, rating.showJumps)
        seat(course, "showJumpingSeating")
    end
    if EqHosting.hasPart(typeName, "crossCountry") then
        local course, extra = pickCrossCountry(venue.courses or {}, rating)
        result.picks.crossCountry = course
        table.insert(result.extras, extra)
        add("xcLength", course ~= nil and math.floor(course.length or 0) or 0, rating.xcLength)
        add("xcJumps", course ~= nil and course.jumps or 0, rating.xcJumps)
    end

    local extraSum = 0
    for _, extra in ipairs(result.extras) do extraSum = extraSum + extra end
    result.extra = #result.extras > 0 and extraSum / #result.extras or 0

    result.visitors = EqHosting.visitors(config, rating)
    add("stables", venue.freePlaces or 0, result.visitors)
    result.feedNeed = math.ceil(result.visitors * (venue.feedPerHorse or 0))
    add("feed", math.floor(venue.feed or 0), result.feedNeed)
    result.setupFee = EqHosting.setupFee(config, typeName, rating)
    return result
end


--- How popular the event is, out of 100, and where the points come from.
--- @param config table
--- @param typeName string
--- @param result table from EqHosting.check
--- @param context table|nil { facilityKinds, reputation, star (a Champion or Legendary entrant), winter }
--- @return number score 0..100
--- @return table parts list of { id, points }, in the Host page's order
function EqHosting.popularity(config, typeName, result, context)
    context = context or {}
    local p = config.popularity
    local parts = {}
    local function add(id, points)
        if points ~= 0 then table.insert(parts, { id = id, points = points }) end
    end
    add("base", p.base)
    local courseShare = p.courseFullAt > 0 and math.min(1, math.max(0, (result.extra or 0) / p.courseFullAt)) or 0
    add("course", math.floor(p.course * courseShare + 0.5))
    add("seating", math.min(p.seating, (result.seatingExtra or 0) * p.seatingEach + (result.indoor and p.indoor or 0)))
    add("facilities", math.min(p.facilities, (context.facilityKinds or 0) * p.facilitiesEach))
    add("reputation", math.min(p.reputationMax, math.max(p.reputationMin, context.reputation or 0)))
    if context.star then add("star", p.star) end
    if context.winter and EqHosting.hasPart(typeName, "crossCountry") then add("winter", p.winter) end

    local score = 0
    for _, part in ipairs(parts) do score = score + part.points end
    return math.min(100, math.max(0, score)), parts
end


--- A hosting reputation after an event, kept in its range.
--- @param config table
--- @param reputation number|nil
--- @param succeeded boolean false for a cancelled event
--- @return number
function EqHosting.nextReputation(config, reputation, succeeded)
    local p = config.popularity
    local value = (reputation or 0) + (succeeded and p.success or p.cancel)
    return math.min(p.reputationMax, math.max(p.reputationMin, value))
end


--- What an event takes: the visitors who turn up pay their entry, and every bleacher its gate.
--- @param config table
--- @param typeName string
--- @param rating table
--- @param popularity number 0..100
--- @param seating number bleachers (and indoor arenas) at the event
--- @return table { visitors, competitors, entryFee, entries, gate, total }
function EqHosting.takings(config, typeName, rating, popularity, seating)
    local share = math.min(1, math.max(0, popularity / 100))
    local visitors = EqHosting.visitors(config, rating)
    local turnout = config.turnoutMin + (1 - config.turnoutMin) * share
    local competitors = math.floor(visitors * turnout + 0.5)
    local entryFee = rating.entryFee * (typeName == EqHosting.EVENTING and config.eventingFeeFactor or 1)
    local entries = competitors * entryFee
    local gate = math.floor((seating or 0) * rating.gate * share + 0.5)
    return { visitors = visitors, competitors = competitors, entryFee = entryFee, entries = entries, gate = gate,
        total = entries + gate }
end

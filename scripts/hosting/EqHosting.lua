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
        quality = xmlFile:getFloat(p .. "#quality", 5),
        varietyFull = xmlFile:getFloat(p .. "#varietyFull", 5),
        aheadEach = xmlFile:getFloat(p .. "#aheadEach", 2),
        aheadMax = xmlFile:getFloat(p .. "#aheadMax", 10),
        buzz = xmlFile:getInt(p .. "#buzz", 5),
    }

    -- Star entries (James, 2026-11-01): points by the best entry's rating for the event.
    config.stars = {}
    i = 0
    while xmlFile:hasProperty(string.format("hosting.stars.star(%d)", i)) do
        local key = string.format("hosting.stars.star(%d)", i)
        table.insert(config.stars, { from = xmlFile:getFloat(key .. "#from", 90), points = xmlFile:getFloat(key .. "#points", 0) })
        i = i + 1
    end
    table.sort(config.stars, function(a, b) return a.from > b.from end)

    -- Weather (James, 2026-11-01): counted hourly in the event month, hail worst, then snow, then rain.
    local w = "hosting.weather"
    config.weather = {
        hourFrom = xmlFile:getInt(w .. "#hourFrom", 8), hourTo = xmlFile:getInt(w .. "#hourTo", 20),
        scale = xmlFile:getFloat(w .. "#scale", 40), max = xmlFile:getFloat(w .. "#max", 25),
        gate = xmlFile:getFloat(w .. "#gate", 0.6), gateMin = xmlFile:getFloat(w .. "#gateMin", 0.4),
        types = {},
    }
    i = 0
    while xmlFile:hasProperty(string.format("%s.type(%d)", w, i)) do
        local key = string.format("%s.type(%d)", w, i)
        local name = xmlFile:getString(key .. "#name")
        if name ~= nil then
            config.weather.types[string.upper(name)] = { weight = xmlFile:getFloat(key .. "#weight", 1),
                flat = xmlFile:getFloat(key .. "#flat", 0) }
        end
        i = i + 1
    end

    -- Advertising: an optional spend at booking.
    config.adverts = {}
    i = 0
    while xmlFile:hasProperty(string.format("hosting.advertising.level(%d)", i)) do
        local key = string.format("hosting.advertising.level(%d)", i)
        local level = { name = xmlFile:getString(key .. "#name", "local"), points = xmlFile:getFloat(key .. "#points", 0), cost = {} }
        for _, rating in ipairs(config.ratings) do level.cost[rating.name] = xmlFile:getFloat(key .. "#" .. rating.name, 0) end
        table.insert(config.adverts, level)
        i = i + 1
    end

    -- Shops and goods visitors buy (James, 2026-11-01).
    local s = "hosting.shops"
    config.shops = {
        source = xmlFile:getFloat(s .. "#source", 2), good = xmlFile:getFloat(s .. "#good", 1), max = xmlFile:getFloat(s .. "#max", 6),
        minStock = xmlFile:getFloat(s .. "#minStock", 50), markup = xmlFile:getFloat(s .. "#markup", 1.25),
        sell = {}, goods = {}, keywords = {},
    }
    for _, rating in ipairs(config.ratings) do config.shops.sell[rating.name] = xmlFile:getFloat(s .. "#" .. rating.name, 0) end
    i = 0
    while xmlFile:hasProperty(string.format("%s.good(%d)", s, i)) do
        local name = xmlFile:getString(string.format("%s.good(%d)#name", s, i))
        if name ~= nil then table.insert(config.shops.goods, string.upper(name)) end
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("%s.shop(%d)", s, i)) do
        local keyword = xmlFile:getString(string.format("%s.shop(%d)#keyword", s, i))
        if keyword ~= nil then table.insert(config.shops.keywords, string.lower(keyword)) end
        i = i + 1
    end

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


--- The share of an event out in the weather, 0..1: an indoor arena keeps show jumping and
--- dressage dry; cross country counts the share of its jumps outdoors (outdoor, measured once
--- when the event opens), else its middle. Phases count alike. Pure.
--- @param typeName string
--- @param picks table from EqHosting.check
--- @return number share
function EqHosting.outdoorShare(typeName, picks)
    local total, count = 0, 0
    for _, phase in ipairs(EqHosting.phasesOf(typeName)) do
        local pick = picks ~= nil and picks[phase] or nil
        local share = 1
        if pick ~= nil then
            if phase == "crossCountry" and pick.outdoor ~= nil then share = pick.outdoor
            elseif pick.indoor then share = 0 end
        end
        total, count = total + share, count + 1
    end
    return count > 0 and total / count or 1
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
    -- How well built its jumping courses are (EqHosting.courseQuality, measured by EqHostVenue).
    local qualities = {}
    for _, phase in ipairs({ "showJumping", "crossCountry" }) do
        local pick = result.picks[phase]
        if pick ~= nil then table.insert(qualities, pick.quality or 0) end
    end
    local qualitySum = 0
    for _, q in ipairs(qualities) do qualitySum = qualitySum + q end
    result.quality = #qualities > 0 and qualitySum / #qualities or 0

    result.visitors = EqHosting.visitors(config, rating)
    add("stables", venue.freePlaces or 0, result.visitors)
    result.feedNeed = math.ceil(result.visitors * (venue.feedPerHorse or 0))
    add("feed", math.floor(venue.feed or 0), result.feedNeed)
    result.setupFee = EqHosting.setupFee(config, typeName, rating)
    return result
end


--- Points for the best of your entries in the field, by its rating for the event. Pure.
--- @param config table
--- @param rating number|nil the entry's rating for the event
--- @return number points
function EqHosting.starPoints(config, rating)
    if rating == nil then return 0 end
    for _, star in ipairs(config.stars or {}) do
        if rating >= star.from then return star.points end
    end
    return 0
end


--- Points for booking ahead: aheadEach a month beyond the first, at most aheadMax. Pure.
--- @param config table
--- @param monthsAhead number|nil months between booking and the event
--- @return number points
function EqHosting.aheadPoints(config, monthsAhead)
    local p = config.popularity
    return math.min(p.aheadMax, math.max(0, ((monthsAhead or 1) - 1) * p.aheadEach))
end


--- @param config table
--- @param name string|nil an advertising level's name
--- @return table|nil level { name, points, cost }
function EqHosting.advert(config, name)
    for _, level in ipairs(config.adverts or {}) do
        if level.name == name then return level end
    end
    return nil
end


--- @param config table
--- @param name string|nil advertising level
--- @param ratingName string
--- @return number cost
function EqHosting.advertCost(config, name, ratingName)
    local level = EqHosting.advert(config, name)
    return level ~= nil and (level.cost[ratingName] or 0) or 0
end


--- How well built the jumps of a course are, 0..1. Half for jumping different obstacles rather
--- than the same few again, half for a mix of jump types (full at varietyFull). Pure.
--- @param config table
--- @param jumps table list of { x, z, type|nil }
--- @return number quality
function EqHosting.courseQuality(config, jumps)
    if jumps == nil or #jumps == 0 then return 0 end
    local spots, types, nSpots, nTypes = {}, {}, 0, 0
    for _, jump in ipairs(jumps) do
        local spot = string.format("%d:%d", math.floor((jump.x or 0) + 0.5), math.floor((jump.z or 0) + 0.5))
        if not spots[spot] then spots[spot], nSpots = true, nSpots + 1 end
        if jump.type ~= nil and not types[jump.type] then types[jump.type], nTypes = true, nTypes + 1 end
    end
    local full = math.max(1, config.popularity.varietyFull or 5)
    return 0.5 * nSpots / #jumps + 0.5 * math.min(1, nTypes / full)
end


--- The weather's hold on an event so far. Pure.
--- @param config table
--- @param tally table|nil { hours (counted), bad (summed weights x outdoor share), flat (one-off losses) }
--- @return number points popularity lost
--- @return number share 0..1 of the counted hours lost to bad weather (weight 1 = one hour)
function EqHosting.weatherLoss(config, tally)
    local w = config.weather
    if w == nil or tally == nil or (tally.hours or 0) <= 0 then return 0, 0 end
    local share = math.min(1, (tally.bad or 0) / tally.hours)
    local points = math.min(w.max, w.scale * share + (tally.flat or 0))
    return math.floor(points + 0.5), share
end


--- Count one hour of weather into a tally. Pure.
--- @param config table
--- @param tally table changed
--- @param typeName string|nil the WeatherType's name, such as "RAIN"
--- @param outdoor number 0..1 share of the event outdoors
--- @return boolean first true the first time a one-off (flat) weather is seen
function EqHosting.countWeather(config, tally, typeName, outdoor)
    tally.hours = (tally.hours or 0) + 1
    local kind = typeName ~= nil and config.weather.types[string.upper(typeName)] or nil
    if kind == nil or (outdoor or 0) <= 0 then return false end
    tally.bad = (tally.bad or 0) + kind.weight * outdoor
    if kind.flat > 0 then
        tally.seen = tally.seen or {}
        if not tally.seen[typeName] then
            tally.seen[typeName] = true
            tally.flat = (tally.flat or 0) + kind.flat * outdoor
            return true
        end
    end
    return false
end


--- Points for shops and goods visitors buy. Pure.
--- @param config table
--- @param shops table|nil { sources (shops or productions making goods), goods (kinds in stock) }
--- @return number points
function EqHosting.shopPoints(config, shops)
    local c = config.shops
    if c == nil or shops == nil or (shops.sources or 0) <= 0 and (shops.goods or 0) <= 0 then return 0 end
    return math.min(c.max, ((shops.sources or 0) > 0 and c.source or 0) + (shops.goods or 0) * c.good)
end


--- What souvenirs and refreshments visitors buy: a few hundred litres at most, shared out over
--- the goods in stock, at the best sell price plus the markup. Pure.
--- @param config table
--- @param ratingName string
--- @param popularity number 0..100
--- @param stock table list of { name, litres, price (per litre, best sell price) }
--- @return table sale { litres, total, items = list of { name, litres, money } }
function EqHosting.goodsSale(config, ratingName, popularity, stock)
    local c = config.shops
    local sale = { litres = 0, total = 0, items = {} }
    if c == nil or stock == nil then return sale end
    local share = math.min(1, math.max(0, (popularity or 0) / 100))
    local budget = (c.sell[ratingName] or 0) * (0.5 + 0.5 * share)
    local left = {}
    for _, item in ipairs(stock) do
        if (item.litres or 0) >= 1 and (item.price or 0) > 0 then table.insert(left, { name = item.name, litres = item.litres, price = item.price, sold = 0 }) end
    end
    -- Even shares; what a good can't fill goes round again to the others.
    while budget >= 1 and #left > 0 do
        local each = budget / #left
        local still = {}
        for _, item in ipairs(left) do
            local take = math.min(each, item.litres - item.sold)
            item.sold = item.sold + take
            budget = budget - take
            if item.litres - item.sold >= 1 then table.insert(still, item) end
            if item.done == nil then
                item.done = true
                table.insert(sale.items, item)
            end
        end
        left = still
    end
    for i = #sale.items, 1, -1 do
        local item = sale.items[i]
        item.litres = math.floor(item.sold)
        item.money = math.floor(item.litres * item.price * c.markup + 0.5)
        item.sold, item.done, item.price = nil, nil, nil
        if item.litres <= 0 then
            table.remove(sale.items, i)
        else
            sale.litres = sale.litres + item.litres
            sale.total = sale.total + item.money
        end
    end
    return sale
end


--- @param config table
--- @param rng function|nil like math.random
--- @return number buzz a random roll, -buzz..+buzz
function EqHosting.rollBuzz(config, rng)
    local b = config.popularity.buzz or 0
    if b <= 0 then return 0 end
    return (rng or math.random)(-b, b)
end


--- How popular the event is, out of 100, and where the points come from.
--- @param config table
--- @param typeName string
--- @param result table from EqHosting.check
--- @param context table|nil { facilityKinds, reputation, starRating (your best entry's rating for the event),
---     monthsAhead, advert (level name), shops = { sources, goods }, buzz, weather (tally), sponsor }
--- @return number score 0..100
--- @return table parts list of { id, points }, in the Host page's order
function EqHosting.popularity(config, typeName, result, context)
    context = context or {}
    local p = config.popularity
    local parts = {}
    local function add(id, points)
        points = math.floor(points + 0.5)
        if points ~= 0 then table.insert(parts, { id = id, points = points }) end
    end
    add("base", p.base)
    local courseShare = p.courseFullAt > 0 and math.min(1, math.max(0, (result.extra or 0) / p.courseFullAt)) or 0
    add("course", p.course * courseShare)
    add("quality", p.quality * math.min(1, math.max(0, result.quality or 0)))
    add("seating", math.min(p.seating, (result.seatingExtra or 0) * p.seatingEach + (result.indoor and p.indoor or 0)))
    add("facilities", math.min(p.facilities, (context.facilityKinds or 0) * p.facilitiesEach))
    add("shops", EqHosting.shopPoints(config, context.shops))
    add("reputation", math.min(p.reputationMax, math.max(p.reputationMin, context.reputation or 0)))
    add("ahead", EqHosting.aheadPoints(config, context.monthsAhead))
    local advert = EqHosting.advert(config, context.advert)
    if advert ~= nil then add("advert", advert.points) end
    -- The farm's sponsors, when they back the event's rating (EqSponsorManager, 0.8 PRs).
    add("sponsor", context.sponsor or 0)
    add("star", EqHosting.starPoints(config, context.starRating))
    add("buzz", context.buzz or 0)
    add("weather", -EqHosting.weatherLoss(config, context.weather))

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
--- @param weather table|nil the event's weather tally: bad weather keeps spectators away
--- @return table { visitors, competitors, entryFee, entries, gate, total }
function EqHosting.takings(config, typeName, rating, popularity, seating, weather)
    local share = math.min(1, math.max(0, popularity / 100))
    local visitors = EqHosting.visitors(config, rating)
    local turnout = config.turnoutMin + (1 - config.turnoutMin) * share
    local competitors = math.floor(visitors * turnout + 0.5)
    local entryFee = rating.entryFee * (typeName == EqHosting.EVENTING and config.eventingFeeFactor or 1)
    local entries = competitors * entryFee
    local _, wet = EqHosting.weatherLoss(config, weather)
    local w = config.weather
    local dry = w ~= nil and math.max(w.gateMin, 1 - w.gate * wet) or 1
    local gate = math.floor((seating or 0) * rating.gate * share * dry + 0.5)
    return { visitors = visitors, competitors = competitors, entryFee = entryFee, entries = entries, gate = gate,
        total = entries + gate }
end


-- RIDDEN ROUNDS
-- While your event runs, a round you ride on a course that qualifies for it, or the dressage
-- test in an arena that does, is that horse's phase: its real penalties are placed against the
-- simulated field, once per horse and phase. Dressage penalties are 100 less the test's
-- percentage (testSheet); the test's third error of course eliminates.

-- Show jumping faults per rail down or refusal (EqShowJumping counts them together).
EqHosting.SJ_FAULT = 4

--- Does a recorded course qualify for a phase at this rating?
--- @param rating table
--- @param phase string "showJumping" or "crossCountry"
--- @param course table { kind ("showJumping"/"crossCountry"), jumps (count), length (m) }
--- @return boolean
function EqHosting.courseQualifies(rating, phase, course)
    if course.kind ~= phase then return false end
    if phase == "crossCountry" then
        return course.jumps >= rating.xcJumps and (course.length or 0) >= rating.xcLength
    end
    return course.jumps >= rating.showJumps
end


--- The phases an event type is ridden in.
--- @param typeName string
--- @return table phase names
function EqHosting.phasesOf(typeName)
    if typeName == EqHosting.EVENTING then return { "dressage", "showJumping", "crossCountry" } end
    return { typeName }
end


-- A ridden jumping round is not put straight against the simulated rivals (a human picks up
-- far more time faults, and the rivals ride no real course). It grades the ride instead, 0..1,
-- and the grade picks where in its own good-to-bad range the horse's simulated phase lands
-- (James, 2026-10-29: "your ride sets the luck", with some randomness around it).
-- Time is judged against the time allowed, which comes from the course's length.
EqHosting.GRADE_TIME_SLOPE = 1.5     -- each 10% over the time allowed takes 0.15 off the time part
EqHosting.GRADE_TIME_SHARE = 0.6     -- how much of the grade the time part can take away
EqHosting.GRADE_FAULTS = { showJumping = 10, crossCountry = 25 }  -- jump faults that take the grade to 1/e
EqHosting.GRADE_SD = 0.1             -- randomness around the ride
EqHosting.GRADE_DRAWS = 9            -- simulated rounds the grade picks from

--- A ridden show jumping or cross country round as a phase sheet.
--- @param result table EqShowJumping round.result
--- @param refusals number refusals and run-outs in the round
--- @param allowed number|nil the round's time allowed in seconds
--- @return table sheet { penalties, down, refusals, time, eliminated, grade }
function EqHosting.roundSheet(result, refusals, allowed)
    if result.eliminated ~= nil then return { penalties = 0, down = 0, refusals = refusals or 0, time = 0, eliminated = true } end
    local time = math.floor((result.timeFaults or 0) * 10 + 0.5) / 10
    local down = 0
    if not result.xc then down = math.max(0, math.floor(((result.faults or 0) - (refusals or 0) * EqHosting.SJ_FAULT) / EqHosting.SJ_FAULT + 0.5)) end
    local sheet = { penalties = math.floor((result.total or 0) * 10 + 0.5) / 10, down = down, refusals = refusals or 0, time = time }
    sheet.grade = EqHosting.rideGrade(result.xc and "crossCountry" or "showJumping", result.faults or 0, result.seconds, allowed)
    return sheet
end


--- How good a ridden round was, 0 (dreadful) to 1 (clear inside the time). Pure.
--- @param phase string "showJumping" or "crossCountry"
--- @param faults number jump faults (rails, refusals, run-outs), no time
--- @param seconds number|nil the round's time
--- @param allowed number|nil the time allowed
--- @return number grade
function EqHosting.rideGrade(phase, faults, seconds, allowed)
    local timePart = 1
    if seconds ~= nil and allowed ~= nil and allowed > 0 and seconds > allowed then
        timePart = math.max(0, 1 - (seconds / allowed - 1) * EqHosting.GRADE_TIME_SLOPE)
    end
    local faultPart = math.exp(-(faults or 0) / (EqHosting.GRADE_FAULTS[phase] or 10))
    return faultPart * (1 - EqHosting.GRADE_TIME_SHARE * (1 - timePart))
end


--- Which of the horse's simulated rounds a ride earns: the grade, give or take a little luck,
--- picks from the best (grade 1) to the worst (grade 0) of GRADE_DRAWS. Pure but for rng.
--- @param grade number 0..1
--- @param draws table simulated phases { score, checks }
--- @param rng table EqRandom
--- @return table draw
function EqHosting.pickDraw(grade, draws, rng)
    table.sort(draws, function(a, b) return a.score > b.score end)
    local g = math.max(0, math.min(1, grade + rng:normal(0, EqHosting.GRADE_SD)))
    return draws[1 + math.floor((1 - g) * (#draws - 1) + 0.5)]
end


--- A ridden dressage test as a phase sheet: penalties are 100 less the test's percentage, as in
--- eventing (EqPerformance's dressage winner, 22, is a 78% test).
--- @param percent number|nil
--- @param lost boolean eliminated
--- @return table sheet
function EqHosting.testSheet(percent, lost)
    if lost or percent == nil then return { penalties = 0, down = 0, refusals = 0, time = 0, eliminated = true } end
    return { penalties = math.floor((100 - percent) * 10 + 0.5) / 10, down = 0, refusals = 0, time = 0 }
end


--- What the ridden phases decide about a horse's elimination.
--- @param ridden table|nil horseId -> phase -> sheet
--- @param horseId string
--- @param typeName string the event type
--- @return string|nil "eliminated" when a ridden phase eliminated it, "finished" when every
---     phase was ridden and finished, nil to leave it to the simulation
function EqHosting.riddenFate(ridden, horseId, typeName)
    local mine = ridden ~= nil and ridden[horseId] or nil
    if mine == nil then return nil end
    local all = true
    for _, phase in ipairs(EqHosting.phasesOf(typeName)) do
        local sheet = mine[phase]
        if sheet ~= nil and sheet.eliminated then return "eliminated" end
        if sheet == nil then all = false end
    end
    return all and "finished" or nil
end


--- Put ridden phases in place of the simulated ones and total them again. The runners must be
--- scored already (EqPerformance.scorePenalties).
--- @param runners table list of { key, run = { phases = { { name, sheet } } } }
--- @param ridden table horseId -> phase -> sheet
function EqHosting.applyRidden(runners, ridden)
    for _, runner in ipairs(runners) do
        local mine = runner.key ~= nil and ridden[runner.key] or nil
        if mine ~= nil and runner.run.phases ~= nil then
            local total = 0
            for _, phase in ipairs(runner.run.phases) do
                local sheet = mine[phase.name]
                -- A graded round was already played into the simulation (EqCompetition.run).
                if sheet ~= nil and sheet.grade ~= nil then
                    phase.sheet.ridden = true
                elseif sheet ~= nil and not sheet.eliminated then
                    phase.sheet = { penalties = sheet.penalties, down = sheet.down or 0, refusals = sheet.refusals or 0,
                        time = sheet.time or 0, ridden = true }
                end
                total = total + phase.sheet.penalties
            end
            runner.run.penalties = math.floor(total * 10 + 0.5) / 10
        end
    end
end

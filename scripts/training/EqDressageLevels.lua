--[[
    EqDressageLevels.lua
    Dressage test levels (James 2026-11-22/23): a test waiting at its start can be the arena's own
    test (EqDressageTests), a random test or a set test, at one of seven levels. Ctrl+N cycles the
    type, Ctrl+M the level; the choice is kept per arena (saved).

    - Levels: Novice, Elementary, Medium, Advanced, Prix St Georges, Intermediate, Grand Prix.
      Each is ridden only in the arenas it suits: first (15 x 30), second (20 x 40), third (20 x 60).
    - A random test picks only from its level's figures (and every level's below it), with the
      movements on the spot it has, and a figure count by level.
    - A set test is a fixed list of steps per level and arena, turned into a test from the arena's
      figures at start (EqDressagePath.build with plan.set), never saved.
    - In the first arena canter comes only on straights: a long side or the long diagonal
      (EqDressagePath canterStretch), never a turn.
    - Your own events (EqHostManager.dressageTestFor) ride the arena's own test, else a random test
      at a level drawn from the event's rating, fixed for the month.

    Adapted from real test sheets: no federation names or test numbers in game.

    Part of Realistic Equestrian by Jasta007.
]]

EqDressageLevels = {}

EqDressageLevels.ORDER = { "novice", "elementary", "medium", "advanced", "prixStGeorges", "intermediate", "grandPrix" }
EqDressageLevels.TYPES = { "own", "random", "set" }
-- The level a test starts at the first time: it suits every arena.
EqDressageLevels.DEFAULT = "elementary"

-- Each level: its voltes' size across by gait (James, 2026-11-23: a 6 m canter volte at Grand
-- Prix, wider for the easier levels, none before Medium), the arenas it is ridden in (first, second, third), figures in a random test, what
-- it adds to the random pool ("name/gait", EqDressagePath.FIGURE_ORDER) and to the movements on
-- the spot, and how it weighs lateral work and plain figures.
EqDressageLevels.LEVELS = {
    novice = {
        arenas = { true, true, false }, figures = 6, reinBack = false,
        adds = { "circleEnd/trot", "circleMid/trot", "halfVolte/trot", "diagonals/trot", "across/trot", "centre/trot",
            "centreToX/trot", "centreFromX/trot", "serpentine/trot", "shallowLoop/trot", "throughCircle/trot", "legYield/trot",
            "legYieldCentre/trot", "diagonals/walk", "circleEnd/canter", "circleMid/canter", "diagonals/canter",
            "canterStretch/trot" },
        spots = {},
    },
    elementary = {
        arenas = { true, true, true }, figures = 7, reinBack = true,
        adds = { "shoulderIn/walk", "shoulderIn/trot", "travers/walk", "travers/trot", "legYieldRail/walk", "legYieldRail/trot",
            "legYield/walk", "legYieldCentre/walk", "halfVolte/walk", "across/walk", "centreToX/walk", "centreFromX/walk",
            "shallowLoop/walk", "eight/trot", "eight/canter", "shallowLoop/canter" },
        spots = { "walkPirouette" },
    },
    medium = {
        voltes = { walk = 8, trot = 10, canter = 10 },
        arenas = { false, true, true }, figures = 8, reinBack = true,
        adds = { "volte/walk", "volte/trot", "volte/canter", "halfPass/trot", "halfPass/canter", "halfPassCentre/trot", "renvers/walk", "renvers/trot" },
        spots = {},
    },
    advanced = {
        voltes = { walk = 8, trot = 8, canter = 9 },
        arenas = { false, true, true }, figures = 9, reinBack = true,
        adds = { "halfPassCentre/canter" },
        spots = { "canterPirouette" },
    },
    prixStGeorges = {
        voltes = { walk = 8, trot = 8, canter = 8 },
        arenas = { false, false, true }, figures = 10, reinBack = true, lateralWeight = 2, plainWeight = 0.6, spotTrack = 20,
        adds = {}, spots = {},
    },
    intermediate = {
        voltes = { walk = 8, trot = 8, canter = 7 },
        arenas = { false, false, true }, figures = 11, reinBack = true, lateralWeight = 2, plainWeight = 0.6, spotTrack = 20,
        adds = { "passageRail/trot" },
        spots = { "piaffe" },
    },
    grandPrix = {
        voltes = { walk = 8, trot = 8, canter = 6 },
        arenas = { false, false, true }, figures = 12, reinBack = true, lateralWeight = 2, plainWeight = 0.5, spotTrack = 25,
        adds = { "passageDiagonal/trot" },
        spots = {},
    },
}

-- Your own events: the levels a random test is drawn from, by the event's rating (data/hosting.xml).
EqDressageLevels.HOSTED = {
    novice = { "novice", "elementary" },
    intermediate = { "medium", "advanced" },
    championship = { "prixStGeorges", "intermediate", "grandPrix" },
}


--- Set tests (from the real sheets, adapted to the figures we have): per level, per arena, the
--- way it tracks at C (1 left, -1 right) and its steps between the opening and the final centre
--- line. A step is "name gait letters [size] [L|R]" (a figure, EqDressagePath.library; L or R:
--- the one that tracks left or right after it) or
--- "spot style letter gait" (a movement on the spot at a letter).
EqDressageLevels.SET = {
    novice = {
        [1] = { turn = 1, steps = { "circleMid trot E", "circleMid trot B", "circleEnd trot C 15", "diagonals trot H-F", "diagonals walk K-M",
            "canterStretch trot H-K", "canterStretch trot F-H", "shallowLoop trot M-B-F" } },
        [2] = { turn = 1, steps = { "halfVolte trot E", "halfVolte trot B", "circleEnd trot C 20", "diagonals trot H-F", "diagonals walk K-M",
            "circleMid canter E", "diagonals canter F-H", "circleMid canter B", "legYield trot K" } },
    },
    elementary = {
        [1] = { turn = 1, steps = { "shoulderIn trot E-K", "diagonals trot F-H", "shoulderIn trot M-B", "spot reinBack A trot",
            "diagonals walk K-M", "spot pirouetteLeft H walk", "canterStretch trot F-M", "canterStretch trot H-F", "travers trot K-E" } },
        [2] = { turn = 1, steps = { "shoulderIn trot E-K", "diagonals trot F-H", "shoulderIn trot M-B", "spot reinBack A trot",
            "diagonals walk K-M", "spot pirouetteLeft H walk", "circleMid canter E", "shallowLoop canter F-B-M", "diagonals canter H-F",
            "travers trot K-E" } },
        [3] = { turn = 1, steps = { "shoulderIn trot S-V", "diagonals trot F-H", "shoulderIn trot R-P", "spot reinBack A trot",
            "diagonals walk K-M", "spot pirouetteLeft H walk", "circleMid canter E", "shallowLoop canter F-B-M", "diagonals canter H-F",
            "travers trot K-V" } },
    },
    medium = {
        [2] = { turn = 1, steps = { "shoulderIn trot E-K", "halfPassCentre trot F-C L", "renvers trot E-K", "diagonals trot F-H",
            "halfPassCentre trot M-A R", "spot reinBack C trot", "diagonals walk M-K", "spot pirouetteRight B walk",
            "spot pirouetteLeft H walk", "volte canter E", "eight canter A-C", "diagonals canter M-K",
            "volte canter B", "diagonals trot H-F" } },
        [3] = { turn = 1, steps = { "shoulderIn trot S-V", "halfPassCentre trot P-C L", "shoulderIn trot E-V", "diagonals trot F-H",
            "halfPassCentre trot R-A R", "renvers trot V-E", "spot reinBack C trot", "diagonals walk M-K",
            "spot pirouetteRight P walk", "spot pirouetteLeft H walk", "volte canter V", "halfPassCentre canter P-C L",
            "volte canter S", "diagonals canter F-H", "diagonals trot M-K" } },
    },
    advanced = {
        [2] = { turn = 1, steps = { "shoulderIn trot E-K", "halfPassCentre trot F-C R", "halfPassCentre trot K-C L", "diagonals trot F-H",
            "shoulderIn trot M-B", "diagonals walk K-M", "spot pirouetteRight H walk", "spot pirouetteLeft K walk",
            "diagonals canter F-H", "spot pirouetteLeft B canter", "spot pirouetteRight K canter", "circleEnd canter C 20",
            "eight canter A-C", "diagonals canter H-F", "diagonals trot K-M" } },
        [3] = { turn = 1, steps = { "shoulderIn trot S-V", "halfPassCentre trot P-C R", "halfPassCentre trot V-C L", "diagonals trot F-H",
            "shoulderIn trot R-B", "diagonals walk K-M", "spot pirouetteRight S walk", "spot pirouetteLeft V walk",
            "halfPassCentre canter P-C R", "spot pirouetteLeft B canter", "spot pirouetteRight E canter",
            "circleEnd canter C 20", "eight canter A-C", "halfPassCentre canter S-A L", "diagonals trot H-F" } },
    },
    prixStGeorges = {
        [3] = { turn = -1, steps = { "shoulderIn trot R-B", "volte trot P", "halfPassCentre trot V-C L", "diagonals trot F-H",
            "shoulderIn trot M-R", "volte trot B", "halfPassCentre trot V-C R", "spot pirouetteLeft R walk",
            "spot pirouetteRight P walk", "diagonals walk K-M", "halfPassCentre canter S-A R",
            "halfPassCentre canter V-C L", "spot pirouetteLeft S canter", "spot pirouetteRight K canter",
            "shallowLoop canter F-B-M", "diagonals canter H-F", "diagonals canter K-M", "diagonals canter H-F" } },
    },
    intermediate = {
        [3] = { turn = 1, steps = { "shoulderIn trot S-V", "volte trot P", "halfPassCentre trot B-C R", "halfPassCentre trot V-C L",
            "spot reinBack A trot", "passageRail trot P-B", "spot piaffe R trot", "passageRail trot H-S",
            "diagonals walk F-H", "halfPassCentre canter R-A L", "halfPassCentre canter P-C R",
            "spot pirouetteLeft R canter", "spot pirouetteRight P canter", "diagonals canter K-M", "diagonals canter H-F",
            "diagonals trot K-M" } },
    },
    grandPrix = {
        [3] = { turn = 1, steps = { "diagonals trot F-H", "halfPassCentre trot R-A R", "halfPassCentre trot V-C L",
            "passageRail trot E-V", "spot piaffe K trot", "passageRail trot F-P", "spot reinBack M trot",
            "diagonals walk H-F", "passageDiagonal trot K-M", "spot piaffe H trot", "passageRail trot E-K",
            "diagonals canter F-H", "diagonals canter M-K", "halfPassCentre canter P-C R", "halfPassCentre canter R-A L",
            "spot pirouetteLeft P canter", "spot pirouetteRight S canter", "diagonals trot F-H" } },
    },
}


-- LEVELS -------------------------------------------------------------------------------------

--- @param name string|nil
--- @return table|nil level
function EqDressageLevels.get(name)
    return name ~= nil and EqDressageLevels.LEVELS[name] or nil
end


--- Which arena a frame is (pure): 1 the first (15 m wide), 2 the second (up to 40-odd m long),
--- 3 the third (60 m). A riding hall's ring counts by its size the same way.
--- @param frame table EqDressagePath.frameFor
--- @return number arena 1..3
function EqDressageLevels.arenaOf(frame)
    if frame.halfW * 2 < 18 then return 1 end
    if frame.halfL * 2 < 50 then return 2 end
    return 3
end


--- @return boolean the level is ridden in this arena
function EqDressageLevels.allowed(name, arena)
    local level = EqDressageLevels.get(name)
    return level ~= nil and level.arenas[arena] == true
end


--- @return number index of a level in ORDER, or nil
local function rank(name)
    for i, n in ipairs(EqDressageLevels.ORDER) do
        if n == name then return i end
    end
    return nil
end
EqDressageLevels.rank = rank


--- The nearest level to `name` this arena allows: itself, else the nearest below, else above.
--- @param name string|nil
--- @param arena number
--- @return string level
function EqDressageLevels.fit(name, arena)
    local at = rank(name) or rank(EqDressageLevels.DEFAULT)
    for d = 0, #EqDressageLevels.ORDER do
        for _, i in ipairs({ at - d, at + d }) do
            local n = EqDressageLevels.ORDER[i]
            if n ~= nil and EqDressageLevels.allowed(n, arena) then return n end
        end
    end
    return EqDressageLevels.DEFAULT
end


--- What a level gives EqDressagePath.build (pure): its pool (its own figures and every level's
--- below), the movements on the spot, rein back, weights, and canter on straights in the first arena.
--- @param name string
--- @param frame table
--- @return table level for EqDressagePath.build
function EqDressageLevels.forBuild(name, frame)
    local pool, spots = {}, {}
    local own = EqDressageLevels.get(name)
    for _, n in ipairs(EqDressageLevels.ORDER) do
        local level = EqDressageLevels.LEVELS[n]
        for _, entry in ipairs(level.adds) do pool[entry] = true end
        for _, spot in ipairs(level.spots) do spots[spot] = true end
        if n == name then break end
    end
    return { name = name, pool = pool, spots = spots, reinBack = own ~= nil and own.reinBack or false,
        lateralWeight = own ~= nil and own.lateralWeight or nil, plainWeight = own ~= nil and own.plainWeight or nil,
        spotTrack = own ~= nil and own.spotTrack or nil, voltes = own ~= nil and own.voltes or nil, straight = EqDressageLevels.arenaOf(frame) == 1 }
end


--- @return number figures in a random test at this level
function EqDressageLevels.figuresOf(name)
    local level = EqDressageLevels.get(name)
    return level ~= nil and level.figures or EqDressagePath.TRAINING_FIGURES
end


--- A set test as a plan for EqDressagePath.build (pure), or nil when the level has none for
--- this arena.
--- @param name string
--- @param arena number
--- @return table|nil plan { turn, seed, set = true, steps }
function EqDressageLevels.setPlan(name, arena)
    local sets = EqDressageLevels.SET[name]
    local set = sets ~= nil and sets[arena] or nil
    if set == nil then return nil end
    local steps = {}
    for i, text in ipairs(set.steps) do
        local words = {}
        for word in text:gmatch("%S+") do table.insert(words, word) end
        if words[1] == "spot" then
            table.insert(steps, { kind = "spot", style = words[2], letter = words[3], gait = words[4], seed = i })
        else
            -- After the letters: a size, and L or R for the way it leaves the figure (tracking left or right).
            local step = { kind = "find", name = words[1], gait = words[2], letters = words[3], seed = i }
            for k = 4, #words do
                if words[k] == "L" then step.exitRein = 1
                elseif words[k] == "R" then step.exitRein = -1
                else step.size = tonumber(words[k]) end
            end
            table.insert(steps, step)
        end
    end
    return { turn = set.turn, seed = string.format("set %s %d", name, arena), set = true, steps = steps }
end


-- THE CHOICE PER ARENA -----------------------------------------------------------------------

-- How near (metres) an arena's centre and size must be to the one a choice was kept for.
EqDressageLevels.NEAR = 1.5
EqDressageLevels.SIZE_NEAR = 1
-- { x, z, length, width, type, level } per arena.
EqDressageLevels.choices = {}


function EqDressageLevels.reset()
    EqDressageLevels.choices = {}
end


local function findChoice(frame)
    for i, entry in ipairs(EqDressageLevels.choices) do
        local d = math.sqrt((entry.x - frame.cx) ^ 2 + (entry.z - frame.cz) ^ 2)
        if d <= EqDressageLevels.NEAR and math.abs(entry.length - frame.halfL * 2) <= EqDressageLevels.SIZE_NEAR
            and math.abs(entry.width - frame.halfW * 2) <= EqDressageLevels.SIZE_NEAR then
            return i, entry
        end
    end
    return nil, nil
end


--- The test type and level for an arena: as kept, else the arena's own test if it has one, else
--- random at the default level. The level always suits the arena; own only when there is one.
--- @param frame table
--- @param hasOwn boolean the arena has a player's own test
--- @return string type "own", "random" or "set", string level
function EqDressageLevels.choiceFor(frame, hasOwn)
    local _, entry = findChoice(frame)
    local arena = EqDressageLevels.arenaOf(frame)
    local kind = entry ~= nil and entry.type or (hasOwn and "own" or "random")
    if kind == "own" and not hasOwn then kind = "random" end
    if kind ~= "own" and kind ~= "random" and kind ~= "set" then kind = "random" end
    return kind, EqDressageLevels.fit(entry ~= nil and entry.level or nil, arena)
end


--- Keep an arena's choice.
--- @param frame table
--- @param kind string
--- @param level string
function EqDressageLevels.setChoice(frame, kind, level)
    local index = findChoice(frame)
    if index ~= nil then table.remove(EqDressageLevels.choices, index) end
    table.insert(EqDressageLevels.choices, { x = frame.cx, z = frame.cz, length = frame.halfL * 2, width = frame.halfW * 2,
        type = kind, level = level })
end


--- The next test type (Ctrl+N): own, random, set, round again; own only when there is one.
--- @return string type
function EqDressageLevels.cycleType(frame, hasOwn)
    local kind, level = EqDressageLevels.choiceFor(frame, hasOwn)
    local list = {}
    for _, t in ipairs(EqDressageLevels.TYPES) do
        if t ~= "own" or hasOwn then table.insert(list, t) end
    end
    local at = 1
    for i, t in ipairs(list) do if t == kind then at = i end end
    local nextKind = list[at % #list + 1]
    EqDressageLevels.setChoice(frame, nextKind, level)
    return nextKind
end


--- The next level the arena allows (Ctrl+M). Picking a level while on the own test moves to random.
--- @return string level, string type
function EqDressageLevels.cycleLevel(frame, hasOwn)
    local kind, level = EqDressageLevels.choiceFor(frame, hasOwn)
    local arena = EqDressageLevels.arenaOf(frame)
    local at = rank(level) or 1
    local n = #EqDressageLevels.ORDER
    local nextLevel = level
    for d = 1, n do
        local candidate = EqDressageLevels.ORDER[(at - 1 + d) % n + 1]
        if EqDressageLevels.allowed(candidate, arena) then
            nextLevel = candidate
            break
        end
    end
    if kind == "own" then kind = "random" end
    EqDressageLevels.setChoice(frame, kind, nextLevel)
    return nextLevel, kind
end


--- For your own event: the level of its random test, drawn once from the rating's levels this
--- arena allows (else the nearest one it does).
--- @param rating string|nil the event's rating name
--- @param frame table
--- @param rng function (n) -> 1..n, seeded by the event
--- @return string|nil level, nil for an unknown rating
function EqDressageLevels.hostedLevel(rating, frame, rng)
    local levels = rating ~= nil and EqDressageLevels.HOSTED[rating] or nil
    if levels == nil then return nil end
    local arena = EqDressageLevels.arenaOf(frame)
    local fits = {}
    for _, name in ipairs(levels) do
        if EqDressageLevels.allowed(name, arena) then table.insert(fits, name) end
    end
    if #fits == 0 then return EqDressageLevels.fit(levels[#levels], arena) end
    return fits[rng(#fits)]
end


-- SAVING -------------------------------------------------------------------------------------

--- @param xmlFile table
--- @param key string
function EqDressageLevels.saveToXMLFile(xmlFile, key)
    for i, entry in ipairs(EqDressageLevels.choices) do
        local choiceKey = string.format("%s.choice(%d)", key, i - 1)
        xmlFile:setFloat(choiceKey .. "#x", entry.x)
        xmlFile:setFloat(choiceKey .. "#z", entry.z)
        xmlFile:setFloat(choiceKey .. "#length", entry.length)
        xmlFile:setFloat(choiceKey .. "#width", entry.width)
        xmlFile:setString(choiceKey .. "#type", entry.type)
        xmlFile:setString(choiceKey .. "#level", entry.level)
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqDressageLevels.loadFromXMLFile(xmlFile, key)
    EqDressageLevels.reset()
    if xmlFile == nil then return end
    local i = 0
    while true do
        local choiceKey = string.format("%s.choice(%d)", key, i)
        if not xmlFile:hasProperty(choiceKey) then break end
        table.insert(EqDressageLevels.choices, { x = xmlFile:getFloat(choiceKey .. "#x", 0), z = xmlFile:getFloat(choiceKey .. "#z", 0),
            length = xmlFile:getFloat(choiceKey .. "#length", 0), width = xmlFile:getFloat(choiceKey .. "#width", 0),
            type = xmlFile:getString(choiceKey .. "#type", "random"), level = xmlFile:getString(choiceKey .. "#level", EqDressageLevels.DEFAULT) })
        i = i + 1
    end
end

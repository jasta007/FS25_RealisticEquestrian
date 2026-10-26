--[[
    EqRivals.lua
    The named horses other yards bring to events. Pure functions with no game or RLRM calls, so
    they run headless.

    A save gets RIVAL_COUNT rivals, drawn from a seed kept in the save, so they stay the same
    horses for the whole game. Each has a level in every discipline: about a third are racehorses
    (good on the flat and over steeplechase fences, poor in the arena) and the rest sport horses,
    each with a favourite discipline. When a simulated rival finishes in the top three, it takes
    the name of a rival whose level in that discipline is close to its rating (the closest when
    none is near), so the same names keep turning up at their level in their best events.
]]

EqRivals = {}

EqRivals.RIVAL_COUNT = 50
EqRivals.RACER_SHARE = 0.35
EqRivals.RACING = { raceShort = true, raceLong = true, steeplechase = true }
-- A rival within this many points of a rating can take the place, so one horse doesn't win
-- everything at its level.
EqRivals.MATCH_RANGE = 6

-- Plain horse names, none a famous real horse. Shown as written (not translated).
EqRivals.NAMES = {
    "Applejack", "Torben", "Winter", "Bramble", "Copper Kettle", "Hazelnut", "Midnight Lark", "Saffron",
    "Juniper", "Tamsin", "Barley Twist", "Pepperpot", "Rosebay", "Finch", "Clover Hill", "Morello",
    "Sable", "Thistledown", "Larkspur", "Quill", "Marigold", "Oakley", "Tinderbox", "Wren", "Bonfire",
    "Cobalt", "Delphine", "Ember", "Fennel", "Gossamer", "Harrow", "Indigo Rose", "Jasper", "Kestrel",
    "Lupin", "Merlot", "Nettle", "Orchard Gold", "Piper", "Rowan", "Sorrel", "Tansy", "Umber",
    "Velvet Storm", "Willow Bay", "Yarrow", "Zephyr", "Acorn", "Biscuit", "Cinder", "Dapple Dawn",
    "Elderflower", "Foxglove", "Gingersnap", "Heather Bell", "Islay", "Juno", "Kingfisher", "Linden",
    "Mistral", "Nutmeg", "Oatcake", "Primrose", "Russet", "Starling", "Tumbleweed", "Vesper", "Woodsmoke",
}


--- Draw a save's rivals.
--- @param seed number the save's rival seed
--- @param disciplines table config.disciplines
--- @return table rivals list of { name, levels = discipline -> level 5..100 }
function EqRivals.generate(seed, disciplines)
    local rng = EqRandom.new("rivals " .. tostring(seed))
    local names = {}
    for i, name in ipairs(EqRivals.NAMES) do names[i] = name end
    -- Shuffle, then take the first RIVAL_COUNT.
    for i = #names, 2, -1 do
        local j = math.min(i, math.floor(rng:next() * i) + 1)
        names[i], names[j] = names[j], names[i]
    end

    local rivals = {}
    for i = 1, math.min(EqRivals.RIVAL_COUNT, #names) do
        local base = rng:uniform(15, 97)
        local racer = rng:next() < EqRivals.RACER_SHARE
        local favourite = disciplines[math.min(#disciplines, math.floor(rng:next() * #disciplines) + 1)]
        local levels = {}
        for _, discipline in ipairs(disciplines) do
            local level = base - rng:uniform(0, 20)
            if (EqRivals.RACING[discipline.name] == true) ~= racer then level = level - 30 end
            if discipline == favourite then level = base + rng:uniform(0, 6) end
            levels[discipline.name] = math.max(5, math.min(100, level))
        end
        table.insert(rivals, { name = names[i], levels = levels })
    end
    return rivals
end


--- A rival matching a rating in a discipline, leaving out names already used: any rival within
--- MATCH_RANGE of the rating, else the closest.
--- @param rivals table from generate
--- @param discipline string
--- @param rating number
--- @param used table name -> true, names taken in this event; the pick is added
--- @param rng table EqRandom
--- @return string|nil name nil when every rival is used
function EqRivals.pick(rivals, discipline, rating, used, rng)
    local best, bestGap, near = nil, math.huge, {}
    for _, rival in ipairs(rivals) do
        if not used[rival.name] then
            local gap = math.abs((rival.levels[discipline] or 0) - rating)
            if gap < bestGap then best, bestGap = rival, gap end
            if gap <= EqRivals.MATCH_RANGE then table.insert(near, rival) end
        end
    end
    if #near > 0 then best = near[math.min(#near, math.floor(rng:next() * #near) + 1)] end
    if best == nil then return nil end
    used[best.name] = true
    return best.name
end

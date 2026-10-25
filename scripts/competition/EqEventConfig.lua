--[[
    EqEventConfig.lua
    Reads data/events.xml: disciplines, tiers, the schedule's spread, the goings and the injuries.
    See the comment at the top of that file for what each attribute means.
]]

EqEventConfig = {}

local Log = EqLog


--- @param xmlFile table XMLFile handle
--- @param key string
--- @return table weights stat -> weight
local function readStats(xmlFile, key, default)
    local stats = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        stats[stat] = xmlFile:getFloat(key .. "#" .. stat, default)
    end
    return stats
end


--- @param xmlFile table An open XMLFile on events.xml
--- @return table config { disciplines, disciplineByName, tiers, tierByName, goings, copiesMax, priceSpread, transport, injuries }
function EqEventConfig.read(xmlFile)
    local config = { disciplines = {}, disciplineByName = {}, tiers = {}, tierByName = {}, goings = {} }

    local i = 0
    while true do
        local key = string.format("events.disciplines.discipline(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local discipline = {
            name = xmlFile:getString(key .. "#name"),
            weights = readStats(xmlFile, key, 0),
            weakestShare = xmlFile:getFloat(key .. "#weakestShare", 0),
            outdoor = xmlFile:getBool(key .. "#outdoor", false),
            racing = xmlFile:getBool(key .. "#racing", false),
            elimination = xmlFile:getFloat(key .. "#elimination", 0),
            injury = xmlFile:getFloat(key .. "#injury", 0),
            chance = xmlFile:getFloat(key .. "#chance", 1),
            related = {},
        }
        for name in (xmlFile:getString(key .. "#related", "")):gmatch("%S+") do table.insert(discipline.related, name) end
        table.insert(config.disciplines, discipline)
        config.disciplineByName[discipline.name] = discipline
        i = i + 1
    end

    i = 0
    while true do
        local key = string.format("events.tiers.tier(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local tier = {
            name = xmlFile:getString(key .. "#name"),
            minAge = xmlFile:getInt(key .. "#minAge", EqConstants.AGE_MIN_COMPETE),
            maxAge = xmlFile:getInt(key .. "#maxAge", 0),
            minRating = xmlFile:getFloat(key .. "#minRating", 0),
            maxRating = xmlFile:getFloat(key .. "#maxRating", 100),
            fee = xmlFile:getFloat(key .. "#fee", 0),
            prize = xmlFile:getFloat(key .. "#prize", 0),
            field = xmlFile:getInt(key .. "#field", 10),
            rivalMin = xmlFile:getFloat(key .. "#rivalMin", 20),
            rivalMax = xmlFile:getFloat(key .. "#rivalMax", 50),
            monthly = xmlFile:getBool(key .. "#monthly", false),
            chance = xmlFile:getFloat(key .. "#chance", 1),
            trainingBoost = xmlFile:getFloat(key .. "#trainingBoost", 0),
            risk = xmlFile:getFloat(key .. "#risk", 1),
            venue = xmlFile:getBool(key .. "#venue", false),
        }
        table.insert(config.tiers, tier)
        config.tierByName[tier.name] = tier
        i = i + 1
    end

    config.copiesMax = xmlFile:getInt("events.schedule#copiesMax", 3)
    config.priceSpread = xmlFile:getFloat("events.schedule#priceSpread", 0.3)
    config.eventsMin = xmlFile:getInt("events.schedule#eventsMin", 3)
    config.eventsMax = xmlFile:getInt("events.schedule#eventsMax", 8)
    config.monthlyMin = xmlFile:getInt("events.schedule#monthlyMin", 1)
    config.monthlyMax = xmlFile:getInt("events.schedule#monthlyMax", 2)
    config.extraFarmShare = xmlFile:getFloat("events.schedule#extraFarmShare", 0.5)

    i = 0
    while true do
        local key = string.format("events.goings.going(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        table.insert(config.goings, {
            name = xmlFile:getString(key .. "#name"),
            chance = xmlFile:getFloat(key .. "#chance", 1),
            modifiers = readStats(xmlFile, key, 1),
            injury = xmlFile:getFloat(key .. "#injury", 1),
        })
        i = i + 1
    end

    config.regions = {}
    i = 0
    while true do
        local key = string.format("events.venues.region(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local region = { name = xmlFile:getString(key .. "#name"), venues = {} }
        local j = 0
        while true do
            local venueKey = string.format("%s.venue(%d)", key, j)
            if not xmlFile:hasProperty(venueKey) then break end
            table.insert(region.venues, xmlFile:getString(venueKey .. "#name"))
            j = j + 1
        end
        if #region.venues > 0 then table.insert(config.regions, region) end
        i = i + 1
    end

    config.transport = {
        share = xmlFile:getFloat("events.transport#share", 0.25),
        fallback = xmlFile:getFloat("events.transport#fallback", 150),
    }

    config.distances, config.routes = {}, {}
    i = 0
    while true do
        local key = string.format("events.routes.distance(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local distance = {
            name = xmlFile:getString(key .. "#name"),
            chance = xmlFile:getFloat(key .. "#chance", 0),
            factor = xmlFile:getFloat(key .. "#factor", 1),
            quarantine = xmlFile:getFloat(key .. "#quarantine", 0),
            quarantineYard = xmlFile:getFloat(key .. "#quarantineYard", 0),
            injury = xmlFile:getFloat(key .. "#injury", 1),
        }
        config.distances[distance.name] = distance
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("events.routes.route(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local from, to = xmlFile:getString(key .. "#from"), xmlFile:getString(key .. "#to")
        local distance = xmlFile:getString(key .. "#distance", "far")
        config.routes[from .. ">" .. to] = distance
        config.routes[to .. ">" .. from] = distance
        i = i + 1
    end

    config.home = { default = xmlFile:getString("events.home#default", "europe"), maps = {}, countries = {} }
    i = 0
    while true do
        local key = string.format("events.home.map(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        config.home.maps[xmlFile:getString(key .. "#title")] = xmlFile:getString(key .. "#region")
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("events.home.country(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        config.home.countries[xmlFile:getString(key .. "#code")] = xmlFile:getString(key .. "#region")
        i = i + 1
    end

    config.injuries = {}
    i = 0
    while true do
        local key = string.format("events.risk.injury(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        table.insert(config.injuries, {
            name = xmlFile:getString(key .. "#name"),
            chance = xmlFile:getFloat(key .. "#chance", 1),
            careerEnding = xmlFile:getFloat(key .. "#careerEnding", 0),
        })
        i = i + 1
    end

    return config
end


--- @param path string events.xml
--- @return table|nil config
function EqEventConfig.load(path)
    local xmlFile = XMLFile.load("eqEvents", path)
    if xmlFile == nil then
        Log:error("EqEventConfig: could not open %s", path)
        return nil
    end

    local config = EqEventConfig.read(xmlFile)
    xmlFile:delete()
    Log:info("EqEventConfig: %d disciplines, %d tiers, %d goings", #config.disciplines, #config.tiers, #config.goings)
    return config
end

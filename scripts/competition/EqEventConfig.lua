--[[
    EqEventConfig.lua
    Reads data/events.xml: disciplines, tiers, the schedule's spread and the goings.
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
--- @return table config { disciplines, disciplineByName, tiers, tierByName, goings, copiesMax, priceSpread }
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
        }
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
        }
        table.insert(config.tiers, tier)
        config.tierByName[tier.name] = tier
        i = i + 1
    end

    config.copiesMax = xmlFile:getInt("events.schedule#copiesMax", 3)
    config.priceSpread = xmlFile:getFloat("events.schedule#priceSpread", 0.3)

    i = 0
    while true do
        local key = string.format("events.goings.going(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        table.insert(config.goings, {
            name = xmlFile:getString(key .. "#name"),
            chance = xmlFile:getFloat(key .. "#chance", 1),
            modifiers = readStats(xmlFile, key, 1),
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

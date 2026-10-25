--[[
    EqHorseRecord.lua
    One horse's Realistic Equestrian data, keyed by RLRM's identifier string
    ("<country code> <farmId> <uniqueId>"). Everything RLRM already tracks - name, age, health,
    fitness, RLRM genetics - stays on RLRM's Animal and is read from there, never copied here.
]]

EqHorseRecord = {}
EqHorseRecord.__index = EqHorseRecord

EqHorseRecord.ORIGIN_ROLLED = "rolled"
EqHorseRecord.ORIGIN_BRED = "bred"
EqHorseRecord.ORIGIN_DEALER = "dealer"

EqHorseRecord.FOCUS_BALANCED = "balanced"


--- @param id string RLRM identifier
--- @return table record
function EqHorseRecord.new(id)
    local self = setmetatable({}, EqHorseRecord)
    self.id = id
    self.genes = {}
    self.budgetGene = EqConstants.GENE_MEAN
    self.trained = {}
    self.focus = EqHorseRecord.FOCUS_BALANCED
    self.origin = EqHorseRecord.ORIGIN_ROLLED
    self.retired = false
    self.careerEnded = false     -- retired by a career-ending injury; cannot be undone
    self.injury = nil            -- { name, monthsLeft, monthlyCost } while on box rest
    self.career = { starts = 0, wins = 0, places = 0, earnings = 0, eliminations = 0, injuries = 0 }
    self.lastSeenDay = 0
    self.idleDays = 0
    self.monthStarts = 0         -- round events started this month
    self.advertised = nil        -- the dealer's view of each ceiling, for a horse bought from the dealer
    self.revealed = true         -- false until a dealer horse's real potential has shown
    self.ownedMonths = nil       -- months on the farm, counted for a horse bought from the dealer
    return self
end


--- The potential the player can see: the dealer's view until the real one has shown.
--- @return table ceilings stat key -> ceiling
function EqHorseRecord:getShownCeilings()
    if self.advertised ~= nil and not self.revealed then return self.advertised end
    return self:getCeilings()
end


--- @return boolean true for a horse bought from the dealer that is still settling in
function EqHorseRecord:isSettling()
    return self.ownedMonths ~= nil and self.ownedMonths < EqConstants.SETTLE_MONTHS
end


--- @return table ceilings stat key -> ceiling after the talent budget
function EqHorseRecord:getCeilings()
    return EqStats.computeCeilings(self.genes, self.budgetGene)
end


--- @param xmlFile table XMLFile handle
--- @param key string
function EqHorseRecord:saveToXMLFile(xmlFile, key)
    xmlFile:setString(key .. "#id", self.id)
    xmlFile:setString(key .. "#origin", self.origin)
    if self.redrawStart then xmlFile:setBool(key .. "#redrawStart", true) end
    xmlFile:setString(key .. "#focus", self.focus)
    xmlFile:setBool(key .. "#retired", self.retired)
    xmlFile:setBool(key .. "#careerEnded", self.careerEnded)
    if self.injury ~= nil then
        xmlFile:setString(key .. ".injury#name", self.injury.name)
        xmlFile:setInt(key .. ".injury#monthsLeft", self.injury.monthsLeft)
        xmlFile:setFloat(key .. ".injury#monthlyCost", self.injury.monthlyCost)
    end
    xmlFile:setInt(key .. "#lastSeenDay", self.lastSeenDay)
    xmlFile:setInt(key .. "#idleDays", self.idleDays)
    xmlFile:setInt(key .. "#monthStarts", self.monthStarts)
    if self.ownedMonths ~= nil then xmlFile:setInt(key .. "#ownedMonths", self.ownedMonths) end
    if self.advertised ~= nil then
        xmlFile:setBool(key .. ".advertised#revealed", self.revealed)
        for _, stat in ipairs(EqConstants.STAT_KEYS) do
            xmlFile:setFloat(key .. ".advertised#" .. stat, self.advertised[stat])
        end
    end
    xmlFile:setFloat(key .. ".genes#budget", self.budgetGene)

    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        xmlFile:setFloat(key .. ".genes#" .. stat, self.genes[stat] or EqConstants.GENE_MEAN)
        xmlFile:setFloat(key .. ".trained#" .. stat, self.trained[stat] or 0)
    end

    xmlFile:setInt(key .. ".career#starts", self.career.starts)
    xmlFile:setInt(key .. ".career#wins", self.career.wins)
    xmlFile:setInt(key .. ".career#places", self.career.places)
    xmlFile:setFloat(key .. ".career#earnings", self.career.earnings)
    xmlFile:setInt(key .. ".career#eliminations", self.career.eliminations)
    xmlFile:setInt(key .. ".career#injuries", self.career.injuries)
end


--- @param xmlFile table XMLFile handle
--- @param key string
--- @return table|nil record nil when the entry has no id
function EqHorseRecord.loadFromXMLFile(xmlFile, key)
    local id = xmlFile:getString(key .. "#id")
    if id == nil or id == "" then return nil end

    local self = EqHorseRecord.new(id)
    self.origin = xmlFile:getString(key .. "#origin", EqHorseRecord.ORIGIN_ROLLED)
    self.redrawStart = xmlFile:getBool(key .. "#redrawStart", false) or nil
    self.focus = xmlFile:getString(key .. "#focus", EqHorseRecord.FOCUS_BALANCED)
    self.retired = xmlFile:getBool(key .. "#retired", false)
    self.careerEnded = xmlFile:getBool(key .. "#careerEnded", false)
    if xmlFile:hasProperty(key .. ".injury") then
        self.injury = {
            name = xmlFile:getString(key .. ".injury#name", "minor"),
            monthsLeft = xmlFile:getInt(key .. ".injury#monthsLeft", 1),
            monthlyCost = xmlFile:getFloat(key .. ".injury#monthlyCost", 0),
        }
    end
    self.lastSeenDay = xmlFile:getInt(key .. "#lastSeenDay", 0)
    self.idleDays = xmlFile:getInt(key .. "#idleDays", 0)
    self.monthStarts = xmlFile:getInt(key .. "#monthStarts", 0)
    self.ownedMonths = xmlFile:getInt(key .. "#ownedMonths")
    if xmlFile:hasProperty(key .. ".advertised") then
        self.advertised = {}
        for _, stat in ipairs(EqConstants.STAT_KEYS) do
            self.advertised[stat] = EqStats.clamp(xmlFile:getFloat(key .. ".advertised#" .. stat, 70),
                EqConstants.CEILING_FLOOR, 100)
        end
        self.revealed = xmlFile:getBool(key .. ".advertised#revealed", false)
    end
    self.budgetGene = EqStats.clampGene(xmlFile:getFloat(key .. ".genes#budget", EqConstants.GENE_MEAN))

    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        self.genes[stat] = EqStats.clampGene(xmlFile:getFloat(key .. ".genes#" .. stat, EqConstants.GENE_MEAN))
    end

    -- Trained levels are clamped against the ceilings the genes give now, so a balance change
    -- between versions can never leave a horse above its ceiling.
    local ceilings = self:getCeilings()
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        self.trained[stat] = EqStats.clamp(xmlFile:getFloat(key .. ".trained#" .. stat, 0), 0, ceilings[stat])
    end

    self.career.starts = xmlFile:getInt(key .. ".career#starts", 0)
    self.career.wins = xmlFile:getInt(key .. ".career#wins", 0)
    self.career.places = xmlFile:getInt(key .. ".career#places", 0)
    self.career.earnings = xmlFile:getFloat(key .. ".career#earnings", 0)
    self.career.eliminations = xmlFile:getInt(key .. ".career#eliminations", 0)
    self.career.injuries = xmlFile:getInt(key .. ".career#injuries", 0)

    return self
end

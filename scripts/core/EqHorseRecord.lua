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
    self.career = { starts = 0, wins = 0, places = 0, earnings = 0 }
    self.lastSeenDay = 0
    return self
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
    xmlFile:setString(key .. "#focus", self.focus)
    xmlFile:setBool(key .. "#retired", self.retired)
    xmlFile:setInt(key .. "#lastSeenDay", self.lastSeenDay)
    xmlFile:setFloat(key .. ".genes#budget", self.budgetGene)

    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        xmlFile:setFloat(key .. ".genes#" .. stat, self.genes[stat] or EqConstants.GENE_MEAN)
        xmlFile:setFloat(key .. ".trained#" .. stat, self.trained[stat] or 0)
    end

    xmlFile:setInt(key .. ".career#starts", self.career.starts)
    xmlFile:setInt(key .. ".career#wins", self.career.wins)
    xmlFile:setInt(key .. ".career#places", self.career.places)
    xmlFile:setFloat(key .. ".career#earnings", self.career.earnings)
end


--- @param xmlFile table XMLFile handle
--- @param key string
--- @return table|nil record nil when the entry has no id
function EqHorseRecord.loadFromXMLFile(xmlFile, key)
    local id = xmlFile:getString(key .. "#id")
    if id == nil or id == "" then return nil end

    local self = EqHorseRecord.new(id)
    self.origin = xmlFile:getString(key .. "#origin", EqHorseRecord.ORIGIN_ROLLED)
    self.focus = xmlFile:getString(key .. "#focus", EqHorseRecord.FOCUS_BALANCED)
    self.retired = xmlFile:getBool(key .. "#retired", false)
    self.lastSeenDay = xmlFile:getInt(key .. "#lastSeenDay", 0)
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

    return self
end

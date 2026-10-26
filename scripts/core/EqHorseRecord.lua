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
--- The three injuries of 0.1.0.0, and the injury each becomes in a save made by that version.
EqHorseRecord.OLD_INJURIES = { minor = "soreBack", moderate = "tendon", serious = "suspensory" }
--- Event results kept per horse for the Events tab's Results page.
EqHorseRecord.RESULTS_KEPT = 5


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
    self.injury = nil            -- while hurt: { name, rlrm = true } or { name, untilDay } (see EqInjury)
    self.career = { starts = 0, wins = 0, places = 0, earnings = 0, eliminations = 0, injuries = 0 }
    self.lastSeenDay = 0
    self.idleDays = 0
    self.gains = {}              -- recent stat changes, { day, stat -> change } per day, oldest first
    self.monthStarts = 0         -- round events started this month
    self.advertised = nil        -- the dealer's view of each ceiling, for a horse bought from the dealer
    self.revealed = true         -- false until a dealer horse's real potential has shown
    self.ownedMonths = nil       -- months on the farm, counted for a horse bought from the dealer
    self.experience = nil        -- discipline -> { value, idle }, see EqExperience
    self.form = nil              -- peak form from the player's riding: { month, stat -> points }, see EqTraining.formFor
    self.results = {}            -- latest events first: { day, discipline, tier, venue, place, field, prize, status, lines }
    return self
end


--- The potential the player can see: the dealer's view until the real one has shown.
--- @return table ceilings stat key -> ceiling
function EqHorseRecord:getShownCeilings()
    if self.advertised ~= nil and not self.revealed then return self.advertised end
    return self:getCeilings()
end


--- Keep an event's result, newest first, dropping the oldest past RESULTS_KEPT.
--- @param result table { day, discipline, tier, venue, place, field, prize, status, lines }
function EqHorseRecord:addResult(result)
    table.insert(self.results, 1, result)
    while #self.results > EqHorseRecord.RESULTS_KEPT do table.remove(self.results) end
end


--- @return boolean true for a horse bought from the dealer that is still settling in
function EqHorseRecord:isSettling()
    return self.ownedMonths ~= nil and self.ownedMonths < EqConstants.SETTLE_MONTHS
end


--- Days of stat changes kept for the "(+2.8)" shown after each skill.
EqHorseRecord.GAIN_DAYS = 7


--- Add stat changes made on a day (daily training, an event's training boost) to the recent
--- gains, dropping days older than GAIN_DAYS.
--- @param day number monotonic day
--- @param deltas table|nil stat -> change
function EqHorseRecord:addGains(day, deltas)
    if deltas == nil then return end
    local last = self.gains[#self.gains]
    if last == nil or last.day ~= day then
        last = { day = day }
        table.insert(self.gains, last)
    end
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        last[stat] = (last[stat] or 0) + (deltas[stat] or 0)
    end
    while #self.gains > 0 and self.gains[1].day <= day - EqHorseRecord.GAIN_DAYS do table.remove(self.gains, 1) end
end


--- @param today number monotonic day
--- @return table stat -> net change over the last GAIN_DAYS days, today included
function EqHorseRecord:getRecentGains(today)
    local total = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do total[stat] = 0 end
    for _, entry in ipairs(self.gains) do
        if entry.day > today - EqHorseRecord.GAIN_DAYS then
            for _, stat in ipairs(EqConstants.STAT_KEYS) do total[stat] = total[stat] + (entry[stat] or 0) end
        end
    end
    return total
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
        if self.injury.rlrm then xmlFile:setBool(key .. ".injury#rlrm", true) end
        if self.injury.untilDay ~= nil then xmlFile:setInt(key .. ".injury#untilDay", self.injury.untilDay) end
        if self.injury.monthsLeft ~= nil then xmlFile:setInt(key .. ".injury#monthsLeft", self.injury.monthsLeft) end
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
    if self.form ~= nil then
        xmlFile:setInt(key .. ".form#month", self.form.month or 0)
        for _, stat in ipairs(EqConstants.STAT_KEYS) do xmlFile:setFloat(key .. ".form#" .. stat, self.form[stat] or 0) end
    end

    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        xmlFile:setFloat(key .. ".genes#" .. stat, self.genes[stat] or EqConstants.GENE_MEAN)
        -- While eqStats (testing) overrides the stats, the real ones are saved.
        local trained = self.testStats ~= nil and self.testStats[stat] or self.trained[stat]
        xmlFile:setFloat(key .. ".trained#" .. stat, trained or 0)
    end
    for i, entry in ipairs(self.gains) do
        local entryKey = string.format("%s.gains.day(%d)", key, i - 1)
        xmlFile:setInt(entryKey .. "#day", entry.day)
        for _, stat in ipairs(EqConstants.STAT_KEYS) do xmlFile:setFloat(entryKey .. "#" .. stat, entry[stat] or 0) end
    end

    xmlFile:setInt(key .. ".career#starts", self.career.starts)
    xmlFile:setInt(key .. ".career#wins", self.career.wins)
    xmlFile:setInt(key .. ".career#places", self.career.places)
    xmlFile:setFloat(key .. ".career#earnings", self.career.earnings)
    xmlFile:setInt(key .. ".career#eliminations", self.career.eliminations)
    xmlFile:setInt(key .. ".career#injuries", self.career.injuries)
    EqExperience.save(xmlFile, key, self)

    for i, result in ipairs(self.results) do
        local resultKey = string.format("%s.results.result(%d)", key, i - 1)
        xmlFile:setInt(resultKey .. "#day", result.day or 0)
        xmlFile:setString(resultKey .. "#discipline", result.discipline)
        xmlFile:setString(resultKey .. "#tier", result.tier)
        if result.venue ~= nil then xmlFile:setString(resultKey .. "#venue", result.venue) end
        xmlFile:setInt(resultKey .. "#place", result.place or 0)
        xmlFile:setInt(resultKey .. "#field", result.field or 0)
        xmlFile:setFloat(resultKey .. "#prize", result.prize or 0)
        if result.status ~= nil then xmlFile:setString(resultKey .. "#status", result.status) end
        for j, line in ipairs(result.lines or {}) do
            xmlFile:setString(string.format("%s.line(%d)#text", resultKey, j - 1), line)
        end
    end
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
        local name = xmlFile:getString(key .. ".injury#name", "soreBack")
        self.injury = {
            name = EqHorseRecord.OLD_INJURIES[name] or name,
            rlrm = xmlFile:getBool(key .. ".injury#rlrm", false) or nil,
            untilDay = xmlFile:getInt(key .. ".injury#untilDay"),
        }
        -- Saves from before the day clock kept whole months left; EqInjury.daily turns them into days.
        if not self.injury.rlrm and self.injury.untilDay == nil then
            self.injury.monthsLeft = xmlFile:getInt(key .. ".injury#monthsLeft", 1)
        end
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
    if xmlFile:hasProperty(key .. ".form") then
        self.form = { month = xmlFile:getInt(key .. ".form#month", 0) }
        for _, stat in ipairs(EqConstants.STAT_KEYS) do self.form[stat] = xmlFile:getFloat(key .. ".form#" .. stat, 0) end
    end

    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        self.genes[stat] = EqStats.clampGene(xmlFile:getFloat(key .. ".genes#" .. stat, EqConstants.GENE_MEAN))
    end

    -- Trained levels are clamped against the ceilings the genes give now, so a balance change
    -- between versions can never leave a horse above its ceiling.
    local ceilings = self:getCeilings()
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        self.trained[stat] = EqStats.clamp(xmlFile:getFloat(key .. ".trained#" .. stat, 0), 0, ceilings[stat])
    end
    local day = 0
    while xmlFile:hasProperty(string.format("%s.gains.day(%d)", key, day)) do
        local entryKey = string.format("%s.gains.day(%d)", key, day)
        local entry = { day = xmlFile:getInt(entryKey .. "#day", 0) }
        for _, stat in ipairs(EqConstants.STAT_KEYS) do entry[stat] = xmlFile:getFloat(entryKey .. "#" .. stat, 0) end
        table.insert(self.gains, entry)
        day = day + 1
    end

    self.career.starts = xmlFile:getInt(key .. ".career#starts", 0)
    self.career.wins = xmlFile:getInt(key .. ".career#wins", 0)
    self.career.places = xmlFile:getInt(key .. ".career#places", 0)
    self.career.earnings = xmlFile:getFloat(key .. ".career#earnings", 0)
    self.career.eliminations = xmlFile:getInt(key .. ".career#eliminations", 0)
    self.career.injuries = xmlFile:getInt(key .. ".career#injuries", 0)
    EqExperience.load(xmlFile, key, self)

    local i = 0
    while i < EqHorseRecord.RESULTS_KEPT do
        local resultKey = string.format("%s.results.result(%d)", key, i)
        if not xmlFile:hasProperty(resultKey) then break end
        local result = {
            day = xmlFile:getInt(resultKey .. "#day", 0),
            discipline = xmlFile:getString(resultKey .. "#discipline", ""),
            tier = xmlFile:getString(resultKey .. "#tier", ""),
            venue = xmlFile:getString(resultKey .. "#venue"),
            place = xmlFile:getInt(resultKey .. "#place", 0),
            field = xmlFile:getInt(resultKey .. "#field", 0),
            prize = xmlFile:getFloat(resultKey .. "#prize", 0),
            status = xmlFile:getString(resultKey .. "#status"),
            lines = {},
        }
        local j = 0
        while true do
            local lineKey = string.format("%s.line(%d)", resultKey, j)
            if not xmlFile:hasProperty(lineKey) then break end
            table.insert(result.lines, xmlFile:getString(lineKey .. "#text", ""))
            j = j + 1
        end
        table.insert(self.results, result)
        i = i + 1
    end

    return self
end

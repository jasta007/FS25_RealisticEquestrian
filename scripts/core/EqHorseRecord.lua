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
    self.gains = {}              -- recent stat changes, { month, stat -> change } per month, oldest first
    self.monthStarts = 0         -- round events started this month
    self.quarantine = nil        -- rounds left in quarantine after an event abroad (EqQuarantine)
    self.advertised = nil        -- the dealer's view of each ceiling, for a horse bought from the dealer
    self.revealed = true         -- false until a dealer horse's real potential has shown
    self.ownedMonths = nil       -- months on the farm, counted for a horse bought from the dealer
    self.experience = nil        -- discipline -> { value, idle }, see EqExperience
    self.form = nil              -- peak form from the player's riding: { month, stat -> points }, see EqTraining.formFor
    self.results = {}            -- latest events first: { day, discipline, tier, venue, place, field, prize, status, lines }
    self.start = nil             -- { day, stat -> level } when the horse joined the farm, for eqChanges
    return self
end


-- The farm's Broker skill, 0..1 (EqStaffManager sets it; none in the headless tests).
EqHorseRecord.brokerStrength = nil


--- The potential the player can see: the dealer's view until the real one has shown, read by
--- the farm's broker (EqStaff.brokerView).
--- @return table ceilings stat key -> ceiling
function EqHorseRecord:getShownCeilings()
    if self.advertised ~= nil and not self.revealed then
        local strength = EqHorseRecord.brokerStrength ~= nil and EqHorseRecord.brokerStrength() or 0
        if strength > 0 and EqStaff ~= nil then return EqStaff.brokerView(self.advertised, self:getCeilings(), strength) end
        return self.advertised
    end
    return self:getCeilings()
end


--- The potential the dealer prices by: the dealer's own view until the real one has shown.
--- @return table ceilings stat key -> ceiling
function EqHorseRecord:getDealerCeilings()
    if self.advertised ~= nil and not self.revealed then return self.advertised end
    return self:getCeilings()
end


--- Keep an event's result, newest first, dropping the oldest past RESULTS_KEPT.
--- @param result table { day, discipline, tier, venue, hosted, place, field, prize, status, lines }
function EqHorseRecord:addResult(result)
    table.insert(self.results, 1, result)
    while #self.results > EqHorseRecord.RESULTS_KEPT do table.remove(self.results) end
end


--- @return boolean true for a horse bought from the dealer that is still settling in
function EqHorseRecord:isSettling()
    return self.ownedMonths ~= nil and self.ownedMonths < EqConstants.SETTLE_MONTHS
end


--- Stat changes for the "(+2.8)" shown after each skill: summed per in-game month (the months
--- EqCompetitionManager counts), since days are too odd a unit in this game (James, 2026-11-01).
--- The month before is kept too, for the day that ends it and is counted after the change.


--- Add stat changes made in a month (daily training, an event's training boost) to that month's
--- gains, dropping months before the one before it.
--- @param month number months played (EqCompetitionManager.month)
--- @param deltas table|nil stat -> change
function EqHorseRecord:addGains(month, deltas)
    if deltas == nil then return end
    local entry = nil
    for _, e in ipairs(self.gains) do
        if e.month == month then entry = e end
    end
    if entry == nil then
        entry = { month = month }
        table.insert(self.gains, entry)
        table.sort(self.gains, function(a, b) return a.month < b.month end)
    end
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        entry[stat] = (entry[stat] or 0) + (deltas[stat] or 0)
    end
    local newest = self.gains[#self.gains].month
    while #self.gains > 0 and self.gains[1].month < newest - 1 do table.remove(self.gains, 1) end
end


--- @param month number months played (EqCompetitionManager.month)
--- @return table stat -> net change in that month
function EqHorseRecord:getRecentGains(month)
    local total = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do total[stat] = 0 end
    for _, entry in ipairs(self.gains) do
        if entry.month == month then
            for _, stat in ipairs(EqConstants.STAT_KEYS) do total[stat] = total[stat] + (entry[stat] or 0) end
        end
    end
    return total
end


--- Note the stats a horse joined the farm with (bought, bred or first seen), once.
--- @param day number monotonic day
function EqHorseRecord:markStart(day)
    if self.start ~= nil then return end
    self.start = { day = day }
    for _, stat in ipairs(EqConstants.STAT_KEYS) do self.start[stat] = self.trained[stat] or 0 end
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
    if self.quarantine ~= nil then xmlFile:setInt(key .. "#quarantine", self.quarantine) end
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
    if self.start ~= nil then
        xmlFile:setInt(key .. ".start#day", self.start.day)
        for _, stat in ipairs(EqConstants.STAT_KEYS) do xmlFile:setFloat(key .. ".start#" .. stat, self.start[stat]) end
    end
    for i, entry in ipairs(self.gains) do
        local entryKey = string.format("%s.gains.month(%d)", key, i - 1)
        xmlFile:setInt(entryKey .. "#month", entry.month)
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
        if result.hosted then xmlFile:setBool(resultKey .. "#hosted", true) end
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
    local quarantine = xmlFile:getInt(key .. "#quarantine")
    self.quarantine = quarantine ~= nil and quarantine > 0 and quarantine or nil
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
    if xmlFile:hasProperty(key .. ".start") then
        self.start = { day = xmlFile:getInt(key .. ".start#day", 0) }
        for _, stat in ipairs(EqConstants.STAT_KEYS) do self.start[stat] = xmlFile:getFloat(key .. ".start#" .. stat, 0) end
    end
    -- Saves from before 2026-11-01 kept gains per day (gains.day): those are left behind.
    local n = 0
    while xmlFile:hasProperty(string.format("%s.gains.month(%d)", key, n)) do
        local entryKey = string.format("%s.gains.month(%d)", key, n)
        local entry = { month = xmlFile:getInt(entryKey .. "#month", 0) }
        for _, stat in ipairs(EqConstants.STAT_KEYS) do entry[stat] = xmlFile:getFloat(entryKey .. "#" .. stat, 0) end
        table.insert(self.gains, entry)
        n = n + 1
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
            hosted = xmlFile:getBool(resultKey .. "#hosted", false),
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

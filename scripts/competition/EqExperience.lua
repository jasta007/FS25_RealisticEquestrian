--[[
    EqExperience.lua
    Event experience: what a horse has learned from competing in each discipline, on top of its
    four stats. Pure - no g_* globals - so it runs headless.

    - Every start (a finish or an elimination, not a scratch) adds experience in that discipline,
      quickly at first and slower as it fills up (0..100). Related disciplines (events.xml
      "related") pick up a share: eventing teaches some show jumping, dressage and cross country.
    - Experience adds up to RATING_BONUS points to the horse's rating in that discipline.
    - It fades slowly once a horse has gone FADE_GRACE_MONTHS without a start in that discipline.
    - The UI shows one word for it, the horse's specialty: its best discipline, a pair, "3 Day
      Eventer", "Racehorse" or "All Rounder" when several are close.
]]

EqExperience = {}

EqExperience.MAX = 100
-- A start adds GAIN * (1 - experience / MAX): about 10 starts to half full, 30 to 90.
EqExperience.GAIN = 7
EqExperience.RELATED_SHARE = 0.3
-- Rating points at full experience.
EqExperience.RATING_BONUS = 8
-- Months without a start in a discipline before it fades, then the share lost each month.
EqExperience.FADE_GRACE_MONTHS = 3
EqExperience.FADE_SHARE = 0.05

-- Below this nothing shows as a specialty; disciplines within CLOSE_SHARE of the best are close.
EqExperience.SPECIALTY_MIN = 10
EqExperience.CLOSE_SHARE = 0.8

-- The three phases of a three-day event (eventing itself may be close too), and the races.
EqExperience.EVENTER = { showJumping = true, dressage = true, crossCountry = true }
EqExperience.EVENTER_EXTRA = { eventing = true }
EqExperience.RACING = { raceShort = true, raceLong = true, steeplechase = true }


--- @param record table EqHorseRecord
--- @param name string discipline
--- @return number experience 0..MAX
function EqExperience.get(record, name)
    local entry = record.experience ~= nil and record.experience[name] or nil
    return entry ~= nil and entry.value or 0
end


--- @param record table
--- @param name string
--- @param share number share of a full start's gain
local function gain(record, name, share)
    record.experience = record.experience or {}
    local entry = record.experience[name] or { value = 0, idle = 0 }
    entry.value = math.min(EqExperience.MAX, entry.value + EqExperience.GAIN * share * (1 - entry.value / EqExperience.MAX))
    entry.idle = 0
    record.experience[name] = entry
end


--- One start in an event of this discipline.
--- @param record table
--- @param discipline table from EqEventConfig (name, related)
function EqExperience.addStart(record, discipline)
    gain(record, discipline.name, 1)
    for _, related in ipairs(discipline.related or {}) do
        gain(record, related, EqExperience.RELATED_SHARE)
    end
end


--- Start of a month: experience not kept up fades.
--- @param record table
function EqExperience.monthlyFade(record)
    if record.experience == nil then return end
    for name, entry in pairs(record.experience) do
        entry.idle = entry.idle + 1
        if entry.idle > EqExperience.FADE_GRACE_MONTHS then
            entry.value = entry.value * (1 - EqExperience.FADE_SHARE)
            if entry.value < 0.5 then record.experience[name] = nil end
        end
    end
end


--- @param record table
--- @param name string discipline
--- @return number points added to the horse's rating there
function EqExperience.ratingBonus(record, name)
    return EqExperience.RATING_BONUS * EqExperience.get(record, name) / EqExperience.MAX
end


--- @param set table name -> true
--- @param names table list
--- @return number count of names in set
local function countIn(set, names)
    local n = 0
    for _, name in ipairs(names) do
        if set[name] then n = n + 1 end
    end
    return n
end


--- The horse's specialty, for the UI.
--- @param record table
--- @param disciplines table config.disciplines, for a steady order
--- @return string kind "none", "one", "pair", "eventer", "racehorse" or "allRounder"
--- @return table names the close disciplines, best first
function EqExperience.specialty(record, disciplines)
    local best = 0
    for _, discipline in ipairs(disciplines) do
        best = math.max(best, EqExperience.get(record, discipline.name))
    end
    if best < EqExperience.SPECIALTY_MIN then return "none", {} end

    local close = {}
    for _, discipline in ipairs(disciplines) do
        if EqExperience.get(record, discipline.name) >= best * EqExperience.CLOSE_SHARE then
            table.insert(close, discipline.name)
        end
    end
    table.sort(close, function(a, b) return EqExperience.get(record, a) > EqExperience.get(record, b) end)

    local eventer = countIn(EqExperience.EVENTER, close)
    if eventer == 3 and eventer + countIn(EqExperience.EVENTER_EXTRA, close) == #close then return "eventer", close end
    if #close == 1 then return "one", close end
    if countIn(EqExperience.RACING, close) == #close then return "racehorse", close end
    if #close == 2 then return "pair", close end
    return "allRounder", close
end


--- @param xmlFile table
--- @param key string the horse's key
--- @param record table
function EqExperience.save(xmlFile, key, record)
    if record.experience == nil then return end
    local names = {}
    for name in pairs(record.experience) do table.insert(names, name) end
    table.sort(names)
    for i, name in ipairs(names) do
        local entryKey = string.format("%s.experience.discipline(%d)", key, i - 1)
        xmlFile:setString(entryKey .. "#name", name)
        xmlFile:setFloat(entryKey .. "#value", record.experience[name].value)
        xmlFile:setInt(entryKey .. "#idle", record.experience[name].idle)
    end
end


--- @param xmlFile table
--- @param key string the horse's key
--- @param record table
function EqExperience.load(xmlFile, key, record)
    local i = 0
    while true do
        local entryKey = string.format("%s.experience.discipline(%d)", key, i)
        if not xmlFile:hasProperty(entryKey) then break end
        local name = xmlFile:getString(entryKey .. "#name")
        if name ~= nil and name ~= "" then
            record.experience = record.experience or {}
            record.experience[name] = {
                value = math.max(0, math.min(EqExperience.MAX, xmlFile:getFloat(entryKey .. "#value", 0))),
                idle = xmlFile:getInt(entryKey .. "#idle", 0),
            }
        end
        i = i + 1
    end
end

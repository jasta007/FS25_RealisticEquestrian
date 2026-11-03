--[[
    EqQuarantine.lua
    International quarantine: a horse back from an event in another region (overseas or
    long-haul) does not come straight home. It spends a number of rounds in quarantine, set per
    distance in data/events.xml (<distance quarantineRounds>), away from the pasture like a horse
    at an event: hidden, not rideable, not enterable. RLRM still feeds and ages it.

    Counted in rounds, so it follows the "Show events" cadence: a horse back from an overseas
    round misses the next round's entries and is home for the one after. The quarantine fee each
    entry pays abroad (Auto Transport's quarantine, Manual's quarantine yard) is the cost of
    that stay. The "International quarantine" setting turns the stay off (the fees remain).

    Pure: no game or RLRM calls, so it runs headless. The record field is
    record.quarantine = rounds left (nil when home).
]]

EqQuarantine = {}


--- Rounds of quarantine after an event at this distance.
--- @param config table|nil EqEventConfig
--- @param distance string|nil "local", "near" or "far"
--- @param settings table|nil EqCompetitionManager.settings
--- @return number rounds 0 when none
function EqQuarantine.roundsFor(config, distance, settings)
    if settings ~= nil and settings.quarantine == false then return 0 end
    local entry = config ~= nil and config.distances ~= nil and distance ~= nil and config.distances[distance] or nil
    return entry ~= nil and math.max(math.floor(entry.quarantineRounds or 0), 0) or 0
end


--- Put a horse into quarantine; a longer stay already running is kept.
--- @param record table EqHorseRecord
--- @param rounds number
--- @return boolean started
function EqQuarantine.start(record, rounds)
    if record == nil or rounds == nil or rounds <= 0 then return false end
    record.quarantine = math.max(record.quarantine or 0, rounds)
    return true
end


--- @param record table|nil EqHorseRecord
--- @return number rounds left, 0 when home
function EqQuarantine.roundsLeft(record)
    return record ~= nil and record.quarantine or 0
end


--- @param record table|nil EqHorseRecord
--- @return boolean true while the horse is in quarantine
function EqQuarantine.isIn(record)
    return EqQuarantine.roundsLeft(record) > 0
end


--- One round has passed.
--- @param record table EqHorseRecord
--- @return boolean released true when this round ended the horse's quarantine
function EqQuarantine.tick(record)
    if not EqQuarantine.isIn(record) then return false end
    record.quarantine = record.quarantine - 1
    if record.quarantine > 0 then return false end
    record.quarantine = nil
    return true
end

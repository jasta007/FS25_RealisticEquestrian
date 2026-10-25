--[[
    EqRisk.lua
    What can go wrong at a competition: pure functions with no game or RLRM calls, so they run
    headless.

    - Scratch: a horse that has retired or is injured since it was entered, or unsound on the day (RLRM health under 50), does not
      start, and the owner gets half the entry fee back. Now and then a sound horse is scratched
      too (a lost shoe).
    - Elimination: refusals and falls in the jumping tests, pulled up in a race. The chance is
      the discipline's base, scaled by the tier, how the horse's rating sits in the field and its
      temperament. An eliminated horse wins nothing.
    - Injury: the discipline's base chance, scaled by the tier, the going, the trip (a horse
      hauled abroad arrives tired), fitness and stamina, and doubled for a horse eliminated over
      fences (that is where falls happen). Most injuries
      mean months of box rest and vet bills; a forced retirement is rare, and only with that
      setting on.
]]

EqRisk = {}

EqRisk.SCRATCH_HEALTH = 50
EqRisk.LOST_SHOE_CHANCE = 0.01
EqRisk.SCRATCH_REFUND = 0.5

EqRisk.SCRATCH_INJURED = "injured"
EqRisk.SCRATCH_UNSOUND = "unsound"
EqRisk.SCRATCH_SHOE = "shoe"
EqRisk.SCRATCH_RETIRED = "retired"


--- @param record table EqHorseRecord
--- @param health number RLRM health 0..100
--- @param rng table EqRandom
--- @return string|nil reason SCRATCH_* or nil when the horse starts
function EqRisk.scratchReason(record, health, rng)
    if record.retired then return EqRisk.SCRATCH_RETIRED end
    if record.injury ~= nil then return EqRisk.SCRATCH_INJURED end
    if (health or 100) < EqRisk.SCRATCH_HEALTH then return EqRisk.SCRATCH_UNSOUND end
    if rng:next() < EqRisk.LOST_SHOE_CHANCE then return EqRisk.SCRATCH_SHOE end
    return nil
end


--- Where a rating sits against the tier's rivals: 0 at the bottom of their range, 1 at the top.
local function fieldPosition(tier, rating)
    local span = math.max(tier.rivalMax - tier.rivalMin, 1)
    return EqStats.clamp((rating - tier.rivalMin) / span, 0, 1)
end


--- @param discipline table
--- @param tier table
--- @param rating number the horse's rating for this event
--- @param temperament number trained temperament 0..100
--- @return number chance 0..1
function EqRisk.eliminationChance(discipline, tier, rating, temperament)
    local skill = 1.5 - fieldPosition(tier, rating)          -- 1.5 out of its depth .. 0.5 outclassing the field
    local calm = 1.3 - 0.6 * EqStats.clamp((temperament or 0) / 100, 0, 1)
    return EqStats.clamp(discipline.elimination * (tier.risk or 1) * skill * calm, 0, 0.9)
end


--- @param discipline table
--- @param tier table
--- @param going table|nil
--- @param fitness number RLRM fitness 0..100
--- @param stamina number trained stamina 0..100
--- @param eliminated boolean
--- @param travel number|nil the trip's injury factor (events.xml routes); 1 when nil
--- @return number chance 0..1
function EqRisk.injuryChance(discipline, tier, going, fitness, stamina, eliminated, travel)
    local ground = (discipline.outdoor and going ~= nil) and (going.injury or 1) or 1
    local fit = 1.5 - EqStats.clamp((fitness or 0) / 100, 0, 1)
    local hardy = 1.3 - 0.6 * EqStats.clamp((stamina or 0) / 100, 0, 1)
    local fall = (eliminated and not discipline.racing and discipline.elimination >= 0.05) and 2 or 1
    return EqStats.clamp(discipline.injury * (tier.risk or 1) * ground * (travel or 1) * fit * hardy * fall, 0, 0.5)
end


--- The chance a horse is hurt in a run, whether or not it is eliminated: what the Events tab
--- shows as the injury risk.
--- @param elimination number from eliminationChance
--- @return number chance 0..1
function EqRisk.runInjuryChance(discipline, tier, going, fitness, stamina, elimination, travel)
    local clean = EqRisk.injuryChance(discipline, tier, going, fitness, stamina, false, travel)
    local fallen = EqRisk.injuryChance(discipline, tier, going, fitness, stamina, true, travel)
    return (1 - elimination) * clean + elimination * fallen
end


-- A horse that is neither unfit nor hardened, for an event's own risk before a horse is picked.
EqRisk.TYPICAL_FITNESS = 75
EqRisk.TYPICAL_STAMINA = 50
EqRisk.TYPICAL_TEMPERAMENT = 50

--- Injury risk words, by the chance of an injury in one run.
EqRisk.RISK_BANDS = {
    { from = 0.03, name = "risky" },
    { from = 0.02, name = "moderate" },
    { from = 0.0075, name = "minor" },
    { from = -math.huge, name = "low" },
}


--- @param chance number
--- @return string name a RISK_BANDS name
function EqRisk.riskBand(chance)
    for _, band in ipairs(EqRisk.RISK_BANDS) do
        if chance >= band.from then return band.name end
    end
end


--- An event's injury risk for a typical horse rated mid-field.
--- @param travel number|nil
--- @return number chance 0..1
function EqRisk.eventInjuryChance(discipline, tier, going, travel)
    local rating = (tier.rivalMin + tier.rivalMax) / 2
    local elimination = EqRisk.eliminationChance(discipline, tier, rating, EqRisk.TYPICAL_TEMPERAMENT)
    return EqRisk.runInjuryChance(discipline, tier, going, EqRisk.TYPICAL_FITNESS, EqRisk.TYPICAL_STAMINA, elimination, travel)
end


--- Pick how bad an injury is.
--- @param injuries table config.injuries
--- @param rng table EqRandom
--- @param forcedRetirement boolean the setting
--- @return table outcome { name, months, monthlyCost, careerEnding }
function EqRisk.rollInjury(injuries, rng, forcedRetirement)
    local total = 0
    for _, injury in ipairs(injuries) do total = total + injury.chance end

    local roll = rng:uniform(0, total)
    local picked = injuries[#injuries]
    for _, injury in ipairs(injuries) do
        roll = roll - injury.chance
        if roll <= 0 then picked = injury break end
    end

    -- Always draw the career-ending roll, so the setting never shifts the rest of the sequence.
    local ending = rng:next() < (picked.careerEnding or 0)
    return {
        name = picked.name,
        months = picked.months,
        monthlyCost = picked.monthlyCost,
        careerEnding = ending and forcedRetirement,
    }
end


--- Roll elimination and injury for every entrant before the event is scored.
--- @param event table
--- @param config table EqEventConfig
--- @param entrants table list of { key, rating, temperament, fitness, stamina, travel }
--- @param rng table EqRandom
--- @param settings table { injuries, forcedRetirement }
--- @return table outcomes key -> { eliminated, injury }
function EqRisk.rollEvent(event, config, entrants, rng, settings)
    local discipline = config.disciplineByName[event.discipline]
    local tier = config.tierByName[event.tier]
    local going = nil
    for _, g in ipairs(config.goings) do
        if g.name == event.going then going = g end
    end

    local outcomes = {}
    for _, entrant in ipairs(entrants) do
        -- Fixed draw order per entrant, so turning injuries off does not change who is eliminated.
        local eliminationRoll, injuryRoll = rng:next(), rng:next()
        local eliminated = eliminationRoll < EqRisk.eliminationChance(discipline, tier, entrant.rating, entrant.temperament)
        local injury = nil
        if settings.injuries and #config.injuries > 0
            and injuryRoll < EqRisk.injuryChance(discipline, tier, going, entrant.fitness, entrant.stamina, eliminated, entrant.travel) then
            injury = EqRisk.rollInjury(config.injuries, rng, settings.forcedRetirement)
        end
        outcomes[entrant.key] = { eliminated = eliminated, injury = injury }
    end
    return outcomes
end

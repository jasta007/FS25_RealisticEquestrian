--[[
    EqDealer.lua
    Dealer horses as an investment: pure functions with no game or RLRM calls, so they run
    headless.

    - Talent leans on the horse's RLRM genetics, and a few horses are well-bred prospects, so
      the dealer does sell really good horses now and then.
    - A dealer horse arrives green (low trained levels), so it needs months of work before it
      wins anything worth having.
    - The dealer's view of each stat's potential is a judgement, not a guarantee: usually right,
      sometimes generous, now and then modest. The player sees the dealer's view until the horse
      has been on the farm REVEAL_MONTHS, then the real potential.
    - Price follows the potential the player can see and how schooled the horse is, so a good
      prospect costs real money and pays back over a year or more of competing.
]]

EqDealer = {}

EqDealer.VERDICT_BETTER = "better"
EqDealer.VERDICT_WORSE = "worse"
EqDealer.VERDICT_FAIR = "fair"

-- Points the shown potential must move, summed over the four stats, for the reveal to say
-- better or worse rather than "a firmer idea". Set so one small slip reads as fair: fair is the
-- usual message, worse needs a big or doubled overstatement, and better is rare.
EqDealer.VERDICT_MARGIN = 12


--- Lean rolled genes toward the horse's RLRM genetics.
--- @param genes table stat -> gene, changed in place
--- @param budgetGene number
--- @param rlrmQuality number|nil average RLRM genetics (1.0 average), nil to leave genes alone
--- @return number budgetGene
function EqDealer.leanOnRlrm(genes, budgetGene, rlrmQuality)
    if rlrmQuality == nil then return budgetGene end
    local shift = EqConstants.RLRM_GENE_LEAN * (rlrmQuality - EqConstants.GENE_MEAN)
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        genes[stat] = EqStats.clampGene(genes[stat] + shift)
    end
    return EqStats.clampGene(budgetGene + shift)
end


--- Maybe make a rolled horse a well-bred prospect. Always draws once.
--- @param genes table stat -> gene, changed in place
--- @param budgetGene number
--- @param rng table EqRandom
--- @return number budgetGene
--- @return boolean isProspect
function EqDealer.maybeProspect(genes, budgetGene, rng)
    if rng:next() >= EqConstants.PROSPECT_CHANCE then return budgetGene, false end

    local order = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do table.insert(order, stat) end
    -- Ties keep the canonical order, so the pick is the same everywhere.
    table.sort(order, function(a, b)
        if genes[a] ~= genes[b] then return genes[a] > genes[b] end
        return EqDealer.statIndex(a) < EqDealer.statIndex(b)
    end)
    for i = 1, 2 do
        genes[order[i]] = EqStats.clampGene(genes[order[i]] + EqConstants.PROSPECT_BOOST)
    end
    return EqStats.clampGene(budgetGene + EqConstants.PROSPECT_BOOST), true
end


--- @param stat string
--- @return number index in STAT_KEYS
function EqDealer.statIndex(stat)
    for i, key in ipairs(EqConstants.STAT_KEYS) do
        if key == stat then return i end
    end
    return #EqConstants.STAT_KEYS + 1
end


--- Trained levels for a horse at the dealer: the usual starting curve, a little lower.
--- @param ceilings table
--- @param ageMonths number
--- @param rng table EqRandom
--- @return table trained
function EqDealer.greenTrained(ceilings, ageMonths, rng)
    return EqStats.initialTrained(ceilings, ageMonths, rng, EqConstants.DEALER_START_SHIFT)
end


--- The dealer's view of each ceiling. Draws three numbers per stat whatever the outcome.
--- @param ceilings table true ceilings
--- @param rng table EqRandom
--- @return table advertised stat -> ceiling as the dealer describes it
function EqDealer.advertise(ceilings, rng)
    local advertised = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local kind, generous, modest = rng:next(), rng:uniform(EqConstants.ADVERT_GENEROUS_MIN, EqConstants.ADVERT_GENEROUS_MAX),
            rng:uniform(EqConstants.ADVERT_MODEST_MIN, EqConstants.ADVERT_MODEST_MAX)
        local shift = 0
        if kind < EqConstants.ADVERT_GENEROUS_CHANCE then
            shift = generous
        elseif kind < EqConstants.ADVERT_GENEROUS_CHANCE + EqConstants.ADVERT_MODEST_CHANCE then
            shift = -modest
        end
        advertised[stat] = EqStats.clamp(ceilings[stat] + shift, EqConstants.CEILING_FLOOR, 100)
    end
    return advertised
end


--- @param advertised table
--- @param ceilings table
--- @return string verdict VERDICT_*
function EqDealer.verdict(advertised, ceilings)
    local difference = 0
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        difference = difference + (ceilings[stat] - advertised[stat])
    end
    if difference >= EqDealer.VERDICT_MARGIN then return EqDealer.VERDICT_BETTER end
    if difference <= -EqDealer.VERDICT_MARGIN then return EqDealer.VERDICT_WORSE end
    return EqDealer.VERDICT_FAIR
end


--- Talent the market pays for: the mean of the two best ceilings, since a specialist in two
--- stats is what wins.
--- @param ceilings table
--- @return number score 40..100
function EqDealer.talentScore(ceilings)
    local values = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do table.insert(values, ceilings[stat]) end
    table.sort(values, function(a, b) return a > b end)
    return (values[1] + values[2]) / 2
end


--- @param score number from talentScore
--- @return number factor times the base price
function EqDealer.talentFactor(score)
    local factor = 2 ^ ((score - EqConstants.VALUE_PIVOT) / EqConstants.VALUE_DOUBLING)
    return EqStats.clamp(factor, EqConstants.VALUE_MIN_FACTOR, EqConstants.VALUE_MAX_FACTOR)
end


--- What the horse can do now: the mean of its two best trained stats.
--- @param trained table
--- @return number score
function EqDealer.skillScore(trained)
    local values = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do table.insert(values, trained[stat] or 0) end
    table.sort(values, function(a, b) return a > b end)
    return (values[1] + values[2]) / 2
end


--- @param score number from skillScore
--- @return number factor times the base price
function EqDealer.skillFactor(score)
    local factor = 2 ^ ((score - EqConstants.SKILL_PIVOT) / EqConstants.SKILL_DOUBLING)
    return EqStats.clamp(factor, EqConstants.VALUE_MIN_FACTOR, EqConstants.VALUE_MAX_FACTOR)
end


--- Talent's share of a horse's value at this age.
--- @param ageMonths number
--- @return number weight POTENTIAL_WEIGHT_YOUNG .. POTENTIAL_WEIGHT_ADULT
function EqDealer.potentialWeight(ageMonths)
    local from, to = EqConstants.AGE_GROUNDWORK, EqConstants.POTENTIAL_ADULT_MONTHS
    local t = EqStats.clamp(((ageMonths or 0) - from) / (to - from), 0, 1)
    return EqConstants.POTENTIAL_WEIGHT_YOUNG + (EqConstants.POTENTIAL_WEIGHT_ADULT - EqConstants.POTENTIAL_WEIGHT_YOUNG) * t
end


--- @param ageMonths number
--- @return number factor 1 through the horse's peak, down to VALUE_OLD_FACTOR at AGE_DECLINE
function EqDealer.ageFactor(ageMonths)
    local peakEnd, decline = EqConstants.AGE_PEAK_END, EqConstants.AGE_DECLINE
    if ageMonths <= peakEnd then return 1 end
    if ageMonths >= decline then return EqConstants.VALUE_OLD_FACTOR end
    return 1 - (1 - EqConstants.VALUE_OLD_FACTOR) * (ageMonths - peakEnd) / (decline - peakEnd)
end


--- What the horse is worth beyond its talent and skill: soundness and whether it can breed.
--- @param animal table|nil RLRM Animal; nil reads as healthy and entire
--- @param record table|nil our record (injury, careerEnded)
--- @return table condition { soundness 0..1 (performance value kept), intact boolean }
function EqDealer.condition(animal, record)
    local health = 1
    if animal ~= nil and animal.getHealthFactor ~= nil then
        local ok, value = EqLog.try("EqDealer.condition getHealthFactor", animal.getHealthFactor, animal)
        if ok and type(value) == "number" then health = EqStats.clamp(value, 0, 1) end
    end
    local soundness = health
    if record ~= nil and record.careerEnded then
        soundness = 0
    elseif record ~= nil and record.injury ~= nil then
        soundness = soundness * EqConstants.VALUE_INJURED_FACTOR
    end
    local gelding = animal ~= nil and animal.gender == "male" and animal.isCastrated == true
    return { health = health, soundness = soundness, intact = not gelding }
end


--- A horse's price with our premium: skill now and talent to come, blended by age, as a riding
--- horse (kept as far as it is sound) and as breeding stock (only while entire).
--- @param rlrmPrice number RLRM's price for the horse
--- @param basePrice number the subtype's base price at this age
--- @param shownCeilings table the potential the player can see
--- @param trained table
--- @param ageMonths number
--- @param condition table|nil from EqDealer.condition; nil for a sound, entire horse
--- @return number price
function EqDealer.price(rlrmPrice, basePrice, shownCeilings, trained, ageMonths, condition)
    condition = condition or { health = 1, soundness = 1, intact = true }
    local weight = EqDealer.potentialWeight(ageMonths)
    local talent = EqDealer.talentFactor(EqDealer.talentScore(shownCeilings))
    local performance = weight * talent + (1 - weight) * EqDealer.skillFactor(EqDealer.skillScore(trained))
    local stud = condition.intact and talent * condition.health or 0
    local factor = (1 - EqConstants.STUD_SHARE) * performance * condition.soundness + EqConstants.STUD_SHARE * stud
    local premium = basePrice * (factor - 1) * EqDealer.ageFactor(ageMonths or 0)
    return math.max(rlrmPrice + premium, rlrmPrice * EqConstants.VALUE_FLOOR)
end

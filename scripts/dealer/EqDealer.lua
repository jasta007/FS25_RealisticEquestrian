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
-- better or worse rather than about right.
EqDealer.VERDICT_MARGIN = 3


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


--- Trained levels for a green horse at the dealer.
--- @param ceilings table
--- @param ageMonths number
--- @param rng table EqRandom
--- @return table trained
function EqDealer.greenTrained(ceilings, ageMonths, rng)
    local trained = {}
    local maturity = EqStats.maturity(ageMonths or 0)
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local share = maturity * rng:uniform(EqConstants.DEALER_TRAINED_MIN, EqConstants.DEALER_TRAINED_MAX)
        trained[stat] = EqStats.clamp(math.max(EqConstants.FOAL_TRAINED, ceilings[stat] * share), 0, ceilings[stat])
    end
    return trained
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


--- @param trained table
--- @param ceilings table
--- @return number factor SCHOOL_BASE (green) .. SCHOOL_BASE + SCHOOL_RANGE (fully schooled)
function EqDealer.schoolFactor(trained, ceilings)
    local share = 0
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        share = share + EqStats.clamp((trained[stat] or 0) / math.max(ceilings[stat], 1), 0, 1)
    end
    return EqConstants.SCHOOL_BASE + EqConstants.SCHOOL_RANGE * share / #EqConstants.STAT_KEYS
end


--- @param ageMonths number
--- @return number factor 1 through the horse's peak, down to VALUE_OLD_FACTOR at AGE_DECLINE
function EqDealer.ageFactor(ageMonths)
    local peakEnd, decline = EqConstants.AGE_PEAK_END, EqConstants.AGE_DECLINE
    if ageMonths <= peakEnd then return 1 end
    if ageMonths >= decline then return EqConstants.VALUE_OLD_FACTOR end
    return 1 - (1 - EqConstants.VALUE_OLD_FACTOR) * (ageMonths - peakEnd) / (decline - peakEnd)
end


--- A horse's price with our premium.
--- @param rlrmPrice number RLRM's price for the horse
--- @param basePrice number the subtype's base price at this age
--- @param shownCeilings table the potential the player can see
--- @param trained table
--- @param ageMonths number
--- @return number price
function EqDealer.price(rlrmPrice, basePrice, shownCeilings, trained, ageMonths)
    local factor = EqDealer.talentFactor(EqDealer.talentScore(shownCeilings))
        * EqDealer.schoolFactor(trained, shownCeilings)
    local premium = basePrice * (factor - 1) * EqDealer.ageFactor(ageMonths or 0)
    return math.max(rlrmPrice + premium, rlrmPrice * EqConstants.VALUE_FLOOR)
end

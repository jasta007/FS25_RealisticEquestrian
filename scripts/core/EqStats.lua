--[[
    EqStats.lua
    The stats maths: ceilings from genes, the talent budget, seeded rolls, inheritance and the
    age curve. Pure - no g_* globals, no RLRM lookups - so it runs headless. Anything it needs
    from RLRM (BreedingMath.breedOffspring) is passed in by the caller.
]]

EqStats = {}


local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

EqStats.clamp = clamp


--- @param gene number
--- @return number gene clamped to the genetics domain
function EqStats.clampGene(gene)
    return clamp(gene, EqConstants.GENE_MIN, EqConstants.GENE_MAX)
end


--- @param gene number A stat gene
--- @return number ceiling Before the talent budget is applied, 40..100
function EqStats.ceilingFromGene(gene)
    return EqConstants.CEILING_BASE + EqConstants.CEILING_PER_GENE * EqStats.clampGene(gene)
end


--- @param budgetGene number
--- @return number budget The most the four ceilings may add up to
function EqStats.budgetFromGene(budgetGene)
    return EqConstants.BUDGET_BASE + EqConstants.BUDGET_PER_GENE * EqStats.clampGene(budgetGene)
end


--- Turn genes into ceilings, squeezing them to fit the talent budget.
---
--- When the raw ceilings add up to more than the budget, each one's height above the floor
--- shrinks by the same factor, so the horse keeps its shape (a jumper stays a jumper) but
--- cannot be great at everything.
--- @param genes table stat key -> gene
--- @param budgetGene number
--- @return table ceilings stat key -> ceiling
function EqStats.computeCeilings(genes, budgetGene)
    local floor = EqConstants.CEILING_FLOOR
    local ceilings, total = {}, 0

    for _, key in ipairs(EqConstants.STAT_KEYS) do
        local ceiling = EqStats.ceilingFromGene(genes[key] or EqConstants.GENE_MEAN)
        ceilings[key] = ceiling
        total = total + ceiling
    end

    local budget = EqStats.budgetFromGene(budgetGene or EqConstants.GENE_MEAN)
    local headroom = total - floor * #EqConstants.STAT_KEYS

    if total > budget and headroom > 0 then
        local factor = math.max(budget - floor * #EqConstants.STAT_KEYS, 0) / headroom
        for _, key in ipairs(EqConstants.STAT_KEYS) do
            ceilings[key] = floor + (ceilings[key] - floor) * factor
        end
    end

    return ceilings
end


--- Pull a parent's gene part of the way back to the mean before it is passed on.
--- @param gene number
--- @return number gene
function EqStats.regress(gene)
    return EqConstants.GENE_MEAN + EqConstants.REGRESSION * (gene - EqConstants.GENE_MEAN)
end


--- Roll genes for a horse with no recorded parents.
--- @param rng table An EqRandom
--- @return table genes stat key -> gene
--- @return number budgetGene
function EqStats.rollGenes(rng)
    local genes = {}
    for _, key in ipairs(EqConstants.STAT_KEYS) do
        genes[key] = EqStats.clampGene(rng:normal(EqConstants.GENE_MEAN, EqConstants.ROLL_SD))
    end
    local budgetGene = EqStats.clampGene(rng:normal(EqConstants.GENE_MEAN, EqConstants.ROLL_SD))
    return genes, budgetGene
end


--- Breed a foal's genes from its dam and sire through RLRM's BreedingMath.
--- @param dam table { genes = {...}, budgetGene = n }
--- @param sire table { genes = {...}, budgetGene = n }
--- @param breedOffspring function RLRM's BreedingMath.breedOffspring(p1, p2, opts)
--- @param sd number Within-family spread, normally RLRM's BreedingMath.SD_CONST
--- @return table genes
--- @return number budgetGene
function EqStats.breedGenes(dam, sire, breedOffspring, sd)
    local opts = { sd = sd, min_val = EqConstants.GENE_MIN, max_val = EqConstants.GENE_MAX }
    local genes = {}

    for _, key in ipairs(EqConstants.STAT_KEYS) do
        local damGene = dam.genes[key] or EqConstants.GENE_MEAN
        local sireGene = sire.genes[key] or EqConstants.GENE_MEAN
        genes[key] = breedOffspring(EqStats.regress(damGene), EqStats.regress(sireGene), opts)
    end

    local budgetGene = breedOffspring(EqStats.regress(dam.budgetGene or EqConstants.GENE_MEAN),
        EqStats.regress(sire.budgetGene or EqConstants.GENE_MEAN), opts)

    return genes, budgetGene
end


--- Share of a full day's training a horse of this age takes in.
--- @param ageMonths number
--- @return number factor 0..1
function EqStats.ageTrainingFactor(ageMonths)
    if ageMonths < EqConstants.AGE_GROUNDWORK then return 0.3 end
    if ageMonths < EqConstants.AGE_MIN_COMPETE then return 0.6 end
    if ageMonths <= EqConstants.AGE_PEAK_END then return 1.0 end
    if ageMonths <= EqConstants.AGE_DECLINE then return 0.6 end
    return 0.3
end


--- @param ageMonths number
--- @return number 0 for a newborn, 1 from START_ADULT_MONTHS
function EqStats.startMaturity(ageMonths)
    return clamp((ageMonths or 0) / EqConstants.START_ADULT_MONTHS, 0, 1)
end


--- Trained levels for a horse first seen at this age with no history: a bell curve per stat,
--- leaning toward the horse's talent, and never above its ceiling.
--- @param ceilings table stat key -> ceiling
--- @param ageMonths number
--- @param rng table An EqRandom
--- @param shift number|nil points added to the curve's centre (a green dealer horse is lower)
--- @return table trained stat key -> trained level
function EqStats.initialTrained(ceilings, ageMonths, rng, shift)
    local trained = {}
    local m = EqStats.startMaturity(ageMonths)
    local mean = EqConstants.START_FOAL_MEAN + (EqConstants.START_MEAN - EqConstants.START_FOAL_MEAN) * m + (shift or 0)
    local sd = EqConstants.START_FOAL_SD + (EqConstants.START_SD - EqConstants.START_FOAL_SD) * m

    for _, key in ipairs(EqConstants.STAT_KEYS) do
        local lean = EqConstants.START_CEILING_LEAN * m * (ceilings[key] - EqConstants.START_CEILING_PIVOT)
        trained[key] = clamp(rng:normal(mean + lean, sd), math.min(EqConstants.START_MIN, ceilings[key]), ceilings[key])
    end

    return trained
end

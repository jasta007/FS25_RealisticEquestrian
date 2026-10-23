--[[
    Headless tests for the pure stats maths.

    Run from the repo root:  luajit tests/run.lua <path to an RLRM checkout>
    RLRM's own BreedingMath.lua is loaded from that checkout rather than copied here.
]]

local rlrmPath = arg[1]
assert(rlrmPath, "usage: luajit tests/run.lua <path to FS25_RealisticLivestockRM>")

dofile(rlrmPath .. "/scripts/animal/BreedingMath.lua")
dofile("scripts/core/EqConstants.lua")
dofile("scripts/core/EqRandom.lua")
dofile("scripts/core/EqStats.lua")

local passed, failed = 0, 0

local function check(name, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. (detail and (": " .. detail) or ""))
    end
end

local function genesOf(s, sp, a, t)
    return { stamina = s, speed = sp, agility = a, temperament = t }
end

local function countAtLeast(ceilings, value)
    local n = 0
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if ceilings[stat] >= value then n = n + 1 end
    end
    return n
end

-- Ceiling range follows the gene range.
check("ceiling at min gene", EqStats.ceilingFromGene(0.25) == 40)
check("ceiling at mean gene", EqStats.ceilingFromGene(1.0) == 70)
check("ceiling at max gene", EqStats.ceilingFromGene(1.75) == 100)

-- Talent budget: two stats can max, three never can, four is far out.
local two = EqStats.computeCeilings(genesOf(1.75, 1.75, 0.25, 0.25), 1.75)
check("two maxed stats fit the top budget", countAtLeast(two, 99.999) == 2)

local three = EqStats.computeCeilings(genesOf(1.75, 1.75, 1.75, 0.25), 1.75)
check("three maxed stats never fit", countAtLeast(three, 95) == 0,
    string.format("got %.1f %.1f %.1f", three.stamina, three.speed, three.agility))

local four = EqStats.computeCeilings(genesOf(1.75, 1.75, 1.75, 1.75), 1.75)
check("perfect genes squeeze to an all-rounder", math.abs(four.stamina - 80) < 0.01,
    string.format("got %.3f", four.stamina))

local average = EqStats.computeCeilings(genesOf(1, 1, 1, 1), 1)
check("an average horse is not squeezed", average.speed == 70)

-- Seeded rolls are repeatable and differ between horses.
local a1, b1 = EqStats.rollGenes(EqRandom.new("DE 1 42"))
local a2, b2 = EqStats.rollGenes(EqRandom.new("DE 1 42"))
local a3 = EqStats.rollGenes(EqRandom.new("DE 1 43"))
check("same id rolls the same genes", a1.speed == a2.speed and b1 == b2)
check("different ids roll different genes", a1.speed ~= a3.speed)

-- Rolled genes look like a population around the mean.
local sum, n = 0, 2000
for i = 1, n do
    local genes = EqStats.rollGenes(EqRandom.new("horse " .. i))
    sum = sum + genes.stamina
end
check("rolled genes average about 1.0", math.abs(sum / n - 1.0) < 0.03, string.format("mean %.3f", sum / n))

-- Selective breeding: always breed the best two horses in a herd for 40 generations. With
-- the talent budget, no horse may ever reach three ceilings at 99+.
math.randomseed(12345)
local breed, sd = BreedingMath.breedOffspring, BreedingMath.SD_CONST
local rng = EqRandom.new(7)
local herd = {}
for i = 1, 20 do
    local genes, budgetGene = EqStats.rollGenes(rng)
    herd[i] = { genes = genes, budgetGene = budgetGene }
end

local function score(horse)
    local ceilings = EqStats.computeCeilings(horse.genes, horse.budgetGene)
    return ceilings.agility * 3 + ceilings.temperament * 2 + ceilings.speed
end

local worstViolation, bestAgility, maxedTwo = 0, 0, 0
for _ = 1, 40 do
    table.sort(herd, function(x, y) return score(x) > score(y) end)
    local dam, sire = herd[1], herd[2]
    local foals = {}
    for i = 1, 20 do
        local genes, budgetGene = EqStats.breedGenes(dam, sire, breed, sd)
        foals[i] = { genes = genes, budgetGene = budgetGene }
        local ceilings = EqStats.computeCeilings(genes, budgetGene)
        worstViolation = math.max(worstViolation, countAtLeast(ceilings, 95))
        bestAgility = math.max(bestAgility, ceilings.agility)
        if countAtLeast(ceilings, 99) == 2 then maxedTwo = maxedTwo + 1 end
    end
    herd = foals
end
check("selective breeding never gets three stats to 95+", worstViolation <= 2, "max maxed " .. worstViolation)
print(string.format("info: 40 generations of show-jumping selection -> best agility ceiling %.1f, foals with two stats at 99+: %d of 800",
    bestAgility, maxedTwo))

-- Regression keeps a single elite cross from beating its parents on average.
local elite = { genes = genesOf(1.6, 1.6, 1.6, 1.6), budgetGene = 1.6 }
local total = 0
for _ = 1, 2000 do
    local genes = EqStats.breedGenes(elite, elite, breed, sd)
    total = total + genes.speed
end
check("elite x elite averages below the parents", total / 2000 < 1.5, string.format("mean %.3f", total / 2000))

-- Age curve.
check("foals do groundwork only", EqStats.ageTrainingFactor(12) == 0.3)
check("prime age trains fully", EqStats.ageTrainingFactor(100) == 1.0)
check("an untracked yearling starts at foal level",
    EqStats.initialTrained(average, 12, EqRandom.new(1)).speed == EqConstants.FOAL_TRAINED)
local adult = EqStats.initialTrained(average, 120, EqRandom.new(1))
check("an untracked adult is part-trained, below its ceiling", adult.speed > 30 and adult.speed < 70,
    string.format("got %.1f", adult.speed))

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

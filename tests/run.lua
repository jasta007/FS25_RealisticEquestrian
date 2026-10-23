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
dofile("scripts/training/EqTraining.lua")
dofile("scripts/core/EqRLRM.lua")

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

-- SEEDED BREEDING through RLRM's own BreedingMath

local mare = { genes = genesOf(1.5, 0.8, 1.4, 1.2), budgetGene = 1.3 }
local stallion = { genes = genesOf(1.3, 1.1, 1.6, 0.9), budgetGene = 1.2 }
local function foalGenes(id)
    local genes = EqStats.breedGenes(mare, stallion, EqRLRM.makeSeededBreeder(BreedingMath, EqRandom.new(id)), BreedingMath.SD_CONST)
    return genes
end
local f1, f1again, f2 = foalGenes("UK 1 500"), foalGenes("UK 1 500"), foalGenes("UK 1 501")
check("a foal breeds the same genes everywhere", f1.agility == f1again.agility and f1.speed == f1again.speed)
check("siblings differ", f1.agility ~= f2.agility)
local realRandn = BreedingMath.randn
pcall(EqRLRM.makeSeededBreeder(BreedingMath, EqRandom.new(1)), 1, 1, { sd = "bad" })
check("RLRM's randn is put back even after an error", BreedingMath.randn == realRandn)

local agilitySum = 0
for i = 1, 2000 do agilitySum = agilitySum + foalGenes("UK 1 " .. (1000 + i)).agility end
local expected = (EqStats.regress(1.4) + EqStats.regress(1.6)) / 2
check("seeded foals centre on the regressed mid-parent", math.abs(agilitySum / 2000 - expected) < 0.02,
    string.format("mean %.3f expected %.3f", agilitySum / 2000, expected))

-- TRAINING

local function horse(focus, level)
    return { trained = { stamina = level, speed = level, agility = level, temperament = level }, focus = focus, idleDays = 0 }
end

local function ridden(gait, ms, jumps)
    local sheet = EqTraining.newSheet()
    EqTraining.addRiding(sheet, gait, ms)
    for _ = 1, jumps or 0 do EqTraining.addJump(sheet) end
    return sheet
end

local cap70 = { stamina = 70, speed = 70, agility = 70, temperament = 70 }

local canterDay = EqTraining.playerEffort(ridden("canter", 150000))
check("a full canter day trains stamina and agility", math.abs(canterDay.stamina - 0.8) < 1e-9 and canterDay.speed == 0)
check("galloping fills riding three times as fast", EqTraining.playerRidingPoints(ridden("gallop", 100000)) == 100)
local jumpDay = EqTraining.playerEffort(ridden("canter", 0, 10))
check("jumps add agility", jumpDay.agility > 0.39)
check("jumps add some temperament", jumpDay.temperament > 0.29 and jumpDay.temperament < jumpDay.agility)
check("effort is capped at a full day", EqTraining.playerEffort(ridden("gallop", 900000)).speed == 1)

local racingStaff = EqTraining.staffEffort(100, 0, "racing", false)
check("staff train to the focus", racingStaff.speed == 1.0 and racingStaff.agility < 0.2)
check("riding the player did is not credited to staff", EqTraining.staffEffort(100, 100, "racing", false).speed == 0)
check("grooming adds temperament", EqTraining.staffEffort(0, 0, "balanced", true).temperament > 0)

-- Staff alone stop at 95% of the ceiling; the player's riding takes it the rest of the way.
local staffHorse = horse("racing", 10)
for _ = 1, 400 do
    EqTraining.applyDay(staffHorse, cap70, { riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 })
end
check("staff stop at 95% of the ceiling", staffHorse.trained.speed <= 70 * 0.95 + 1e-6 and staffHorse.trained.speed > 66,
    string.format("got %.2f", staffHorse.trained.speed))
for _ = 1, 400 do
    EqTraining.applyDay(staffHorse, cap70, { sheet = ridden("gallop", 100000), riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 })
end
check("the player's riding reaches the ceiling", staffHorse.trained.speed > 69.5, string.format("got %.2f", staffHorse.trained.speed))

-- Pace: two years of full work takes a prime horse most of the way.
local paced = horse("crossCountry", 10)
for _ = 1, 24 do
    EqTraining.applyDay(paced, cap70, { riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 })
end
check("two years of staff work gets stamina most of the way", paced.trained.stamina > 0.8 * 66.5,
    string.format("got %.1f", paced.trained.stamina))
print(string.format("info: 24 months of cross-country staff work from 10 -> sta %.1f spd %.1f agi %.1f tem %.1f (ceilings 70)",
    paced.trained.stamina, paced.trained.speed, paced.trained.agility, paced.trained.temperament))

-- The same months give the same result whatever the days per month.
local short, long = horse("balanced", 10), horse("balanced", 10)
for _ = 1, 12 do EqTraining.applyDay(short, cap70, { riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 }) end
for _ = 1, 12 * 28 do EqTraining.applyDay(long, cap70, { riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 / 28 }) end
check("days per month does not change the yearly gain", math.abs(short.trained.stamina - long.trained.stamina) < 2.5,
    string.format("1 day/month %.1f, 28 days/month %.1f", short.trained.stamina, long.trained.stamina))

-- Fading.
local idle = horse("balanced", 60)
EqTraining.applyDay(idle, cap70, { riding = 0, dirt = 50, ageMonths = 60, timeAdjustment = 1 })
check("one idle day is forgiven", idle.trained.stamina == 60)
for _ = 1, 40 do EqTraining.applyDay(idle, cap70, { riding = 0, dirt = 50, ageMonths = 60, timeAdjustment = 1 }) end
check("an idle horse fades to half its ceiling", math.abs(idle.trained.stamina - 35) < 1e-6, string.format("got %.2f", idle.trained.stamina))
local green = horse("balanced", 20)
for _ = 1, 10 do EqTraining.applyDay(green, cap70, { riding = 0, dirt = 50, ageMonths = 60, timeAdjustment = 1 }) end
check("fading never raises a horse to the floor", green.trained.stamina == 20)

local veteran = horse("balanced", 60)
for _ = 1, 12 do EqTraining.applyDay(veteran, cap70, { riding = 100, dirt = 50, ageMonths = 200, timeAdjustment = 1 }) end
check("a veteran in work still declines", veteran.trained.speed < 60, string.format("got %.2f", veteran.trained.speed))

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

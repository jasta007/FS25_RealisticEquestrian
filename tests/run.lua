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
dofile("scripts/competition/EqEventConfig.lua")
dofile("scripts/competition/EqCompetition.lua")
dofile("scripts/competition/EqRisk.lua")
EqLog = { debug = function() end, info = function() end, warning = function() end, error = function() end }
dofile("scripts/core/EqHorseRecord.lua")
dofile("scripts/dealer/EqDealer.lua")
dofile("scripts/core/EqRegistry.lua")
local TestXML = dofile("tests/xml.lua")

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

-- COMPETITIONS

local config = EqEventConfig.read(TestXML.load("data/events.xml"))
check("events.xml has the seven disciplines", #config.disciplines == 7)
check("events.xml has five tiers with training first", #config.tiers == 5 and config.tiers[1].name == "training")
check("events.xml has three goings", #config.goings == 3)

local jumping = config.disciplineByName.showJumping
local eventing = config.disciplineByName.eventing
local specialist = { stamina = 40, speed = 50, agility = 95, temperament = 85 }
local allRounder = { stamina = 72, speed = 72, agility = 72, temperament = 72 }
check("a specialist beats an all-rounder at its discipline",
    EqCompetition.rating(specialist, jumping) > EqCompetition.rating(allRounder, jumping))
check("an all-rounder beats a specialist at eventing",
    EqCompetition.rating(allRounder, eventing) > EqCompetition.rating(specialist, eventing),
    string.format("all-rounder %.1f specialist %.1f", EqCompetition.rating(allRounder, eventing), EqCompetition.rating(specialist, eventing)))
check("dressage ignores speed", EqCompetition.rating({ stamina = 0, speed = 0, agility = 60, temperament = 60 }, config.disciplineByName.dressage) == 60)

local sprinter = { stamina = 50, speed = 90, agility = 30, temperament = 30 }
local race = config.disciplineByName.raceShort
local firm, soft = config.goings[1], config.goings[3]
check("firm going suits a fast horse", EqCompetition.rating(sprinter, race, firm) > EqCompetition.rating(sprinter, race, soft))
check("going does not change arena events", EqCompetition.rating(specialist, jumping, firm) == EqCompetition.rating(specialist, jumping, soft))

check("condition is 1 for a fit, healthy horse", EqCompetition.condition(100, 100) == 1)
check("an unfit horse is held back", EqCompetition.condition(0, 100) == 0.75)

local training, novice = config.tierByName.training, config.tierByName.novice
check("two-year-olds can enter Training Events", EqCompetition.canEnter(training, 26, 20))
check("three-year-olds cannot", not EqCompetition.canEnter(training, 40, 20))
local okYoung, whyYoung = EqCompetition.canEnter(novice, 30, 20)
check("two-year-olds cannot enter Novice", not okYoung and whyYoung == "tooYoung")
local okHigh, whyHigh = EqCompetition.canEnter(novice, 60, 70)
check("strong horses cannot farm Novice", not okHigh and whyHigh == "ratingHigh")

local rounds, monthly, empty, racing, monthlyInRound = 0, 0, 0, 0, 0
local disciplinesSeen = {}
for round = 1, 200 do
    local events = EqCompetition.drawSchedule(config, EqRandom.new("round " .. round), EqCompetition.KIND_ROUND, false)
    rounds = rounds + #events
    local perDiscipline = {}
    for _, event in ipairs(events) do
        perDiscipline[event.discipline] = (perDiscipline[event.discipline] or 0) + 1
        if config.disciplineByName[event.discipline].racing then racing = racing + 1 end
        if config.tierByName[event.tier].monthly then monthlyInRound = monthlyInRound + 1 end
    end
    if (perDiscipline.dressage or 0) == 0 then empty = empty + 1 end
    for name in pairs(perDiscipline) do disciplinesSeen[name] = true end
    monthly = monthly + #EqCompetition.drawSchedule(config, EqRandom.new("month " .. round), EqCompetition.KIND_MONTH, true)
end
check("racing off means no races", racing == 0)
check("round draws hold no monthly tiers", monthlyInRound == 0)
check("a round usually has several events", rounds / 200 > 5, string.format("%.1f per round", rounds / 200))
check("some rounds have no dressage at all", empty > 0 and empty < 100, empty .. " of 200")
print(string.format("info: %.1f round events and %.1f monthly events per draw; dressage missing in %d of 200 rounds",
    rounds / 200, monthly / 200, empty))

local sameDraw = EqCompetition.drawSchedule(config, EqRandom.new("round 7"), EqCompetition.KIND_ROUND, true)
local sameAgain = EqCompetition.drawSchedule(config, EqRandom.new("round 7"), EqCompetition.KIND_ROUND, true)
check("a round draws the same events from the same seed", #sameDraw == #sameAgain and sameDraw[1].fee == sameAgain[1].fee)

-- Running a field: a strong horse in its band places well most of the time.
local event = { discipline = "showJumping", tier = "novice", prize = 2000 }
local wins, podiums, paid, fullField = 0, 0, 0, true
for i = 1, 500 do
    local results = EqCompetition.run(event, config, { { key = "me", rating = 45, condition = 1 } }, EqRandom.new("race " .. i))
    if #results ~= config.tierByName.novice.field then fullField = false end
    for _, runner in ipairs(results) do
        if runner.key == "me" then
            if runner.place == 1 then wins = wins + 1 end
            if runner.place <= 3 then podiums = podiums + 1 end
            paid = paid + runner.prize
        end
    end
end
check("the field is always full", fullField)
check("a top-of-band horse often wins, but not always", wins > 60 and wins < 250, wins .. " wins of 500")
print(string.format("info: rating 45 in Novice: %d wins, %d podiums of 500, average prize %.0f vs fee 250",
    wins, podiums, paid / 500))

local weak = 0
for i = 1, 500 do
    local results = EqCompetition.run(event, config, { { key = "me", rating = 20, condition = 0.8 } }, EqRandom.new("weak " .. i))
    for _, runner in ipairs(results) do if runner.key == "me" and runner.place <= 3 then weak = weak + 1 end end
end
check("an unready horse rarely places", weak < 25, weak .. " podiums of 500")

-- Risk: config, scratches, eliminations, injuries.
check("risk config: three injury kinds", #config.injuries == 3)
check("risk config: cross country riskier than dressage",
    config.disciplineByName.crossCountry.elimination > config.disciplineByName.dressage.elimination
    and config.disciplineByName.crossCountry.injury > config.disciplineByName.dressage.injury)
check("risk config: Training Events are gentler", config.tierByName.training.risk < config.tierByName.intermediate.risk)

local rng = EqRandom.new("scratch")
check("an injured horse is scratched", EqRisk.scratchReason({ injury = { monthsLeft = 2 } }, 100, rng) == EqRisk.SCRATCH_INJURED)
check("an unsound horse is scratched", EqRisk.scratchReason({}, 40, rng) == EqRisk.SCRATCH_UNSOUND)
local shoes = 0
for i = 1, 5000 do if EqRisk.scratchReason({}, 100, EqRandom.new("shoe " .. i)) ~= nil then shoes = shoes + 1 end end
check("a sound horse is rarely scratched", shoes > 10 and shoes < 120, shoes .. " of 5000")

local xc, intermediate = config.disciplineByName.crossCountry, config.tierByName.intermediate
local outclassed = EqRisk.eliminationChance(xc, intermediate, 40, 20)
local outclassing = EqRisk.eliminationChance(xc, intermediate, 75, 80)
check("a horse out of its depth is eliminated more", outclassed > 2.5 * outclassing,
    string.format("%.3f vs %.3f", outclassed, outclassing))
local firm, good = config.goings[1], config.goings[2]
check("firm going injures more than good", EqRisk.injuryChance(xc, intermediate, firm, 80, 50, false)
    > EqRisk.injuryChance(xc, intermediate, good, 80, 50, false))
check("an unfit horse is injured more", EqRisk.injuryChance(xc, intermediate, good, 20, 50, false)
    > 1.5 * EqRisk.injuryChance(xc, intermediate, good, 100, 50, false))
check("falls over fences injure more", EqRisk.injuryChance(xc, intermediate, good, 80, 50, true)
    == 2 * EqRisk.injuryChance(xc, intermediate, good, 80, 50, false))

local counts, endings, endingsOff = {}, 0, 0
for i = 1, 20000 do
    local injury = EqRisk.rollInjury(config.injuries, EqRandom.new("injury " .. i), true)
    counts[injury.name] = (counts[injury.name] or 0) + 1
    if injury.careerEnding then endings = endings + 1 end
    if EqRisk.rollInjury(config.injuries, EqRandom.new("injury " .. i), false).careerEnding then endingsOff = endingsOff + 1 end
end
check("most injuries are minor", counts.minor > counts.moderate and counts.moderate > counts.serious)
check("forced retirement is rare", endings > 100 and endings < 320, endings .. " of 20000")
check("forced retirement off means never", endingsOff == 0)
print(string.format("info: injuries minor %d moderate %d serious %d, career-ending %d of 20000",
    counts.minor, counts.moderate, counts.serious, endings))

-- Over a season of Intermediate cross country: how often a fit, matched horse comes to grief.
local event2 = { discipline = "crossCountry", tier = "intermediate", going = "good" }
local elim, hurt = 0, 0
local settingsOn = { injuries = true, forcedRetirement = false }
for i = 1, 5000 do
    local out = EqRisk.rollEvent(event2, config, { { key = "me", rating = 60, temperament = 50, fitness = 80, stamina = 60 } },
        EqRandom.new("season " .. i), settingsOn)
    if out.me.eliminated then elim = elim + 1 end
    if out.me.injury ~= nil then hurt = hurt + 1 end
end
check("a matched horse is eliminated now and then", elim > 150 and elim < 700, elim .. " of 5000")
check("a matched horse is injured rarely", hurt > 20 and hurt < 200, hurt .. " of 5000")
print(string.format("info: Intermediate cross country, matched fit horse: %.1f%% eliminated, %.1f%% injured per run",
    elim / 50, hurt / 50))
local off = EqRisk.rollEvent(event2, config, { { key = "me", rating = 60, temperament = 50, fitness = 80, stamina = 60 } },
    EqRandom.new("season 1"), { injuries = false })
local on = EqRisk.rollEvent(event2, config, { { key = "me", rating = 60, temperament = 50, fitness = 80, stamina = 60 } },
    EqRandom.new("season 1"), settingsOn)
check("injuries off changes nothing else", off.me.eliminated == on.me.eliminated and off.me.injury == nil)


-- DEALER HORSES

-- Talent leans on RLRM genetics, and only when the horse has them.
local leanGenes = genesOf(1, 1, 1, 1)
local leanBudget = EqDealer.leanOnRlrm(leanGenes, 1, 1.4)
check("good RLRM genetics lift talent", math.abs(leanGenes.speed - (1 + 0.4 * EqConstants.RLRM_GENE_LEAN)) < 1e-9 and leanBudget > 1)
local plainGenes = genesOf(1, 1, 1, 1)
check("no RLRM genetics, no lean", EqDealer.leanOnRlrm(plainGenes, 1, nil) == 1 and plainGenes.speed == 1)

-- Dealer stock: mostly ordinary, a few really good horses.
local good, great, prospects, n = 0, 0, 0, 4000
local qualities = { 0.7, 0.9, 1.0, 1.0, 1.1, 1.3 }
for i = 1, n do
    local record = EqRegistry.rollRecord("dealer " .. i, 60, qualities[i % #qualities + 1], true)
    local talent = EqDealer.talentScore(record:getCeilings())
    if talent >= 85 then good = good + 1 end
    if talent >= 90 then great = great + 1 end
    local _, isProspect = EqDealer.maybeProspect(genesOf(1, 1, 1, 1), 1, EqRandom.new("p " .. i))
    if isProspect then prospects = prospects + 1 end
end
check("prospects are about 8% of rolled horses", prospects > 0.06 * n and prospects < 0.1 * n, prospects .. " of " .. n)
check("the dealer has some really good horses", good > 0.03 * n and good < 0.15 * n, good .. " of " .. n)
check("championship prospects are rare but there", great > 0 and great < 0.05 * n, great .. " of " .. n)
print(string.format("info: dealer stock: %.1f%% talent 85+, %.1f%% talent 90+", good / n * 100, great / n * 100))

-- Dealer horses arrive green; the same horse is the same at the dealer on every machine.
local greenSum, homeSum = 0, 0
for i = 1, 500 do
    local dealer = EqRegistry.rollRecord("horse " .. i, 72, 1, true)
    local home = EqRegistry.rollRecord("horse " .. i, 72, 1, false)
    local dc, hc = dealer:getCeilings(), home:getCeilings()
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        greenSum = greenSum + dealer.trained[stat] / dc[stat]
        homeSum = homeSum + home.trained[stat] / hc[stat]
    end
end
check("dealer horses are greener than home-produced ones", greenSum < 0.7 * homeSum,
    string.format("%.2f vs %.2f", greenSum / 2000, homeSum / 2000))
local d1, d2 = EqRegistry.rollRecord("DE 3 77", 60, 1.2, true), EqRegistry.rollRecord("DE 3 77", 60, 1.2, true)
check("a dealer horse rolls the same everywhere", d1.trained.speed == d2.trained.speed and d1.advertised.agility == d2.advertised.agility
    and d1.origin == "dealer" and d1.revealed == false)
check("shown potential is the dealer's view until revealed", d1:getShownCeilings() == d1.advertised)
d1.revealed = true
check("then the real one", d1:getShownCeilings().speed == d1:getCeilings().speed)

-- The dealer's view: usually right, sometimes generous, now and then modest.
local exact, generous, modest = 0, 0, 0
for i = 1, 2000 do
    local ceilings = { stamina = 70, speed = 70, agility = 70, temperament = 70 }
    local view = EqDealer.advertise(ceilings, EqRandom.new("advert " .. i))
    local d = view.speed - 70
    if d == 0 then exact = exact + 1 elseif d > 0 then generous = generous + 1 else modest = modest + 1 end
end
check("the dealer is usually right", exact > 1000 and exact < 1300, exact .. " of 2000")
check("generous more often than modest", generous > modest and modest > 200, generous .. " vs " .. modest)
check("verdict better", EqDealer.verdict({ stamina = 70, speed = 70, agility = 70, temperament = 70 },
    { stamina = 75, speed = 70, agility = 70, temperament = 70 }) == "better")
check("verdict worse", EqDealer.verdict({ stamina = 75, speed = 70, agility = 70, temperament = 70 },
    { stamina = 70, speed = 70, agility = 70, temperament = 70 }) == "worse")
check("verdict fair", EqDealer.verdict({ stamina = 71, speed = 70, agility = 70, temperament = 70 },
    { stamina = 70, speed = 70, agility = 70, temperament = 70 }) == "fair")

-- Price: talent doubles every VALUE_DOUBLING points, schooling adds to it, age takes it away.
check("talent 75 is worth the base price", math.abs(EqDealer.talentFactor(75) - 1) < 1e-9)
check("talent 82.5 is worth double", math.abs(EqDealer.talentFactor(82.5) - 2) < 1e-9)
check("talent factor is capped", EqDealer.talentFactor(200) == EqConstants.VALUE_MAX_FACTOR and EqDealer.talentFactor(0) == EqConstants.VALUE_MIN_FACTOR)
local c85 = { stamina = 88, speed = 82, agility = 60, temperament = 60 }
local green = { stamina = 25, speed = 25, agility = 20, temperament = 20 }
local schooled = { stamina = 84, speed = 78, agility = 57, temperament = 57 }
local greenPrice = EqDealer.price(4000, 5000, c85, green, 60)
local schooledPrice = EqDealer.price(4000, 5000, c85, schooled, 60)
check("a green talent-85 horse costs about $9-15k", greenPrice > 9000 and greenPrice < 15000, string.format("%.0f", greenPrice))
check("schooling adds value, but not a fortune", schooledPrice > greenPrice and schooledPrice < 1.7 * greenPrice,
    string.format("%.0f -> %.0f", greenPrice, schooledPrice))
check("an old horse's talent is worth less", EqDealer.price(4000, 5000, c85, schooled, 200) < 0.6 * schooledPrice)
local poorPrice = EqDealer.price(4000, 5000, { stamina = 50, speed = 50, agility = 50, temperament = 50 }, green, 60)
check("a poor horse is cheaper, but never nothing", poorPrice < 0.4 * 4000 and poorPrice >= 4000 * EqConstants.VALUE_FLOOR,
    string.format("%.0f", poorPrice))

-- The investment: a green talent-85 dealer horse in full work, two round starts a month plus a
-- monthly event when it can, entering whatever pays best. Not a quick flip, but it pays back.
local tiers = config.tierByName
local function bestDiscipline(trained)
    local bestD, bestR
    for _, d in ipairs(config.disciplines) do
        local r = EqCompetition.rating(trained, d, nil)
        if bestR == nil or r > bestR then bestD, bestR = d, r end
    end
    return bestD, bestR
end
local evCache = {}
local function expected(d, tier, rating)
    local key = d.name .. tier.name .. math.floor(rating)
    if evCache[key] == nil then
        local total, rng = 0, EqRandom.new(key)
        local event = { discipline = d.name, tier = tier.name, prize = tier.prize }
        for _ = 1, 150 do
            for _, r in ipairs(EqCompetition.run(event, config, { { key = "me", rating = rating, condition = 0.95 } }, rng)) do
                if r.key == "me" then total = total + r.prize end
            end
        end
        evCache[key] = total / 150 - tier.fee - 150   -- transport
    end
    return evCache[key]
end
local function bestEarning(d, monthly, age, rating)
    local best = 0
    for _, tier in ipairs(config.tiers) do
        if tier.monthly == monthly and tier.prize > 0 and EqCompetition.canEnter(tier, age, rating) then
            best = math.max(best, expected(d, tier, rating))
        end
    end
    return best
end
local prospectCeilings = { stamina = 90, speed = 80, agility = 66, temperament = 72 }
local trained = EqDealer.greenTrained(prospectCeilings, 48, EqRandom.new("investment"))
local price = EqDealer.price(5000, 5000, prospectCeilings, trained, 48) * 1.075
local cash, worth = -price, {}
for month = 1, 36 do
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        trained[stat] = trained[stat] + EqTraining.gain(trained[stat], prospectCeilings[stat] * 0.97,
            EqConstants.TRAIN_MONTHLY[stat], 0.8, EqStats.ageTrainingFactor(48 + month), 1)
    end
    local d, rating = bestDiscipline(trained)
    if month > EqConstants.SETTLE_MONTHS then
        cash = cash + EqConstants.MAX_ROUND_STARTS * bestEarning(d, false, 48 + month, rating) + 0.5 * bestEarning(d, true, 48 + month, rating)
    end
    worth[month] = cash + EqDealer.price(5000, 5000, prospectCeilings, trained, 48 + month)
end
check("no quick flip: after 3 months you are about where you started", worth[3] < 0.15 * price,
    string.format("price %.0f, up %.0f", price, worth[3]))
check("after two years it has paid for itself", worth[24] > 0, string.format("%.0f", worth[24]))
check("but it takes a while to make a lot", worth[12] < 1.0 * price, string.format("%.0f", worth[12]))
print(string.format("info: talent-%.0f dealer horse at $%.0f: up $%.0f after 3 months, $%.0f after 12, $%.0f after 24, $%.0f after 36",
    EqDealer.talentScore(prospectCeilings), price, worth[3], worth[12], worth[24], worth[36]))

-- No dead zones: from rating 50 up, some tier pays.
local zones = {}
for rating = 50, 100, 5 do
    local d = config.disciplineByName.showJumping
    local best = math.max(bestEarning(d, false, 60, rating), bestEarning(d, true, 60, rating))
    if best <= 0 then table.insert(zones, rating) end
end
check("every rating from 50 has an event worth entering", #zones == 0, table.concat(zones, ","))

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

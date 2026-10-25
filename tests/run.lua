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
dofile("scripts/training/EqMetabolism.lua")
dofile("scripts/core/EqRLRM.lua")
dofile("scripts/competition/EqEventConfig.lua")
dofile("scripts/competition/EqCompetition.lua")
dofile("scripts/competition/EqExperience.lua")
dofile("scripts/competition/EqRisk.lua")
EqLog = { debug = function() end, info = function() end, warning = function() end, error = function() end }
dofile("scripts/facilities/EqFacility.lua")
dofile("scripts/core/EqHorseRecord.lua")
dofile("scripts/training/EqFeed.lua")
dofile("scripts/dealer/EqDealer.lua")
dofile("scripts/core/EqRegistry.lua")
dofile("scripts/gui/EqMenuPaging.lua")
dofile("scripts/training/EqLooseHorses.lua")
dofile("scripts/gui/EqAnimalsPageButton.lua")
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
do
    -- Starting stats: a bell curve, low for the young, around START_MEAN for adults.
    local function spread(ceilings, age, n)
        local sum, sq, over80, values = 0, 0, 0, 0
        for i = 1, n do
            local t = EqStats.initialTrained(ceilings, age, EqRandom.new("start " .. i))
            for _, stat in ipairs(EqConstants.STAT_KEYS) do
                sum, sq, values = sum + t[stat], sq + t[stat] ^ 2, values + 1
                if t[stat] > 80 then over80 = over80 + 1 end
            end
        end
        local mean = sum / values
        return mean, math.sqrt(sq / values - mean ^ 2), over80 / values
    end
    local typical = { stamina = 70, speed = 70, agility = 70, temperament = 70 }
    local mean, sd = spread(typical, 120, 2000)
    check("adult starting stats centre around 50", mean > 46 and mean < 53, string.format("%.1f", mean))
    check("adult starting stats spread widely", sd > 11 and sd < 16, string.format("%.1f", sd))
    -- Across real rolled horses (each with its own ceilings), a start above 80 is very rare.
    local over80, values, horses80 = 0, 0, 0
    for i = 1, 3000 do
        local record = EqRegistry.rollRecord("adult " .. i, 120, 1, false)
        local any = false
        for _, stat in ipairs(EqConstants.STAT_KEYS) do
            values = values + 1
            if record.trained[stat] > 80 then over80, any = over80 + 1, true end
        end
        if any then horses80 = horses80 + 1 end
    end
    print(string.format("info: adult starting stats: mean %.1f, sd %.1f; %.2f%% of stats and %.1f%% of horses above 80",
        mean, sd, 100 * over80 / values, 100 * horses80 / 3000))
    check("starting above 80 is very rare", over80 > 0 and over80 / values < 0.01, string.format("%d of %d", over80, values))
    local young = spread(typical, 12, 500)
    check("a yearling starts low", young > 15 and young < 30, string.format("%.1f", young))
    local foal = EqStats.initialTrained(typical, 0, EqRandom.new(1))
    check("a newborn starts near foal level", math.abs(foal.speed - EqConstants.START_FOAL_MEAN) < 15)
    local talented = spread({ stamina = 95, speed = 95, agility = 95, temperament = 95 }, 120, 500)
    check("talent leans the start upward", talented > mean + 4, string.format("%.1f vs %.1f", talented, mean))
    local capped = EqStats.initialTrained({ stamina = 42, speed = 42, agility = 42, temperament = 42 }, 120, EqRandom.new(3))
    check("a start never passes the ceiling", capped.speed <= 42)
end

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

local canterDay = EqTraining.playerEffort(ridden("canter", 100000))
check("a full canter day trains stamina and agility", math.abs(canterDay.stamina - 0.8) < 1e-9 and canterDay.speed == 0)
check("galloping fills riding three times as fast", EqTraining.playerRidingPoints(ridden("gallop", 100000)) == 100)
check("walking trains its stats as fast as galloping trains its own",
    math.abs(EqTraining.playerEffort(ridden("walk", 60000)).temperament - EqTraining.playerEffort(ridden("gallop", 60000)).speed) < 1e-9)
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
check("events.xml has five conditions", #config.goings == 5)
check("steeplechase is drawn rarely", config.disciplineByName.steeplechase.chance < 0.3
    and config.disciplineByName.showJumping.chance == 1)
do
    local counts = {}
    for seed = 1, 200 do
        local schedule = EqCompetition.drawSchedule(config, EqRandom.new("rare " .. seed), EqCompetition.KIND_ROUND, true)
        for _, event in ipairs(schedule) do counts[event.discipline] = (counts[event.discipline] or 0) + 1 end
    end
    print(string.format("info: 200 round draws: %d steeplechases vs %d show jumping", counts.steeplechase or 0, counts.showJumping or 0))
    check("steeplechases are far rarer than show jumping", (counts.steeplechase or 0) * 4 < (counts.showJumping or 1))

do
    check("events.xml has four venue regions", #config.regions == 4)
    local regions, venues, unnamed, named = {}, {}, 0, 0
    for seed = 1, 300 do
        for _, event in ipairs(EqCompetition.drawSchedule(config, EqRandom.new("venue " .. seed), EqCompetition.KIND_MONTH, true)) do
            if event.venue ~= nil then
                named = named + 1
                regions[event.region] = (regions[event.region] or 0) + 1
                venues[event.venue] = true
            else
                unnamed = unnamed + 1
            end
        end
    end
    local regionCount, venueCount = 0, 0
    for _ in pairs(regions) do regionCount = regionCount + 1 end
    for _ in pairs(venues) do venueCount = venueCount + 1 end
    print(string.format("info: %d named monthly events across %d regions and %d venues", named, regionCount, venueCount))
    check("every monthly event has a venue", named > 0 and unnamed == 0)
    check("every region hosts events", regionCount == 4)
    local listed = 0
    for _, region in ipairs(config.regions) do listed = listed + #region.venues end
    check("every venue is used", venueCount == listed, string.format("%d of %d", venueCount, listed))
    for _, event in ipairs(EqCompetition.drawSchedule(config, EqRandom.new("round 3"), EqCompetition.KIND_ROUND, true)) do
        check("everyday events have no venue", event.venue == nil)
    end
end

do
    local d = function(a, b) return EqCompetition.distanceBetween(config, a, b) end
    check("same region is local", d("europe", "europe") == "local")
    check("North America to Europe is near, both ways", d("northAmerica", "europe") == "near" and d("europe", "northAmerica") == "near")
    check("North America to South America is near", d("southAmerica", "northAmerica") == "near")
    check("Europe to South America is far", d("europe", "southAmerica") == "far")
    check("Asia and Oceania is far from everywhere", d("asiaOceania", "europe") == "far" and d("northAmerica", "asiaOceania") == "far")
    check("far costs more than near", config.distances.far.factor > config.distances.near.factor
        and config.distances.far.quarantine > config.distances.near.quarantine)

    for _, home in ipairs({ "northAmerica", "southAmerica", "europe", "asiaOceania" }) do
        local byDistance, total = {}, 0
        for seed = 1, 300 do
            for _, event in ipairs(EqCompetition.drawSchedule(config, EqRandom.new("trip " .. seed), EqCompetition.KIND_MONTH, true, home)) do
                local distance = d(home, event.region)
                byDistance[distance] = (byDistance[distance] or 0) + 1
                total = total + 1
            end
        end
        local l, n, f = byDistance["local"] or 0, byDistance.near or 0, byDistance.far or 0
        print(string.format("info: home %s: %d named events, local %.0f%%, near %.0f%%, far %.0f%%", home, total,
            100 * l / total, 100 * n / total, 100 * f / total))
        check("home " .. home .. ": local events most common", l > n and l > f)
        check("home " .. home .. ": far trips rarest", f < l and (n == 0 or f < n))
    end
end
end

-- Success and training words on the Events tab
do
    local event = { discipline = "dressage", tier = "novice", prize = 2000 }
    local line = {}
    local last = -1
    local rising = true
    for _, rating in ipairs({ 25, 35, 42, 48, 55 }) do
        local chance = EqCompetition.podiumChance(event, config, rating, 1, 0, EqRandom.new("odds " .. rating))
        if chance < last then rising = false end
        last = chance
        table.insert(line, string.format("%d: %.2f %s", rating, chance, EqCompetition.successBand(chance)))
    end
    print("info: Novice podium chance by rating -> " .. table.concat(line, ", "))
    check("podium chance rises with rating", rising)
    check("a weak horse is a long shot", EqCompetition.successBand(
        EqCompetition.podiumChance(event, config, 25, 1, 0, EqRandom.new("odds weak"))) == "longShot")
    check("a strong horse is the favourite", EqCompetition.successBand(
        EqCompetition.podiumChance(event, config, 58, 1, 0, EqRandom.new("odds strong"))) == "favourite")
    check("elimination risk lowers the chance", EqCompetition.podiumChance(event, config, 48, 1, 0.5, EqRandom.new("x"))
        < EqCompetition.podiumChance(event, config, 48, 1, 0, EqRandom.new("x")))

    local ceilings = { stamina = 60, speed = 60, agility = 60, temperament = 60 }
    local weights = config.disciplineByName.dressage.weights
    local green = { stamina = 10, speed = 10, agility = 10, temperament = 10 }
    local schooled = { stamina = 56, speed = 56, agility = 56, temperament = 56 }
    local _, greenBand = EqTraining.boostBenefit(green, ceilings, weights, 24)
    local _, schooledBand = EqTraining.boostBenefit(schooled, ceilings, weights, 30)
    check("a green two-year-old gets a medium training benefit", greenBand == "medium")
    check("a horse at staff level gets none", schooledBand == "none")
    local full = EqTraining.boostBenefit(green, ceilings, weights, 60, 1)
    local novice = EqTraining.boostBenefit(green, ceilings, weights, 60, config.tierByName.novice.trainingBoost)
    local older = EqTraining.boostBenefit(green, ceilings, weights, 160, config.tierByName.novice.trainingBoost)
    check("a Novice event teaches less than a young horse class, but something", novice > 0 and novice < full)
    check("a Novice event teaches an older horse less", older < novice)
end

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

-- Event experience: grows with starts, adds to the rating, fades when not kept up.
local function experienceOf(values)
    local record = { experience = {} }
    for name, value in pairs(values) do record.experience[name] = { value = value, idle = 0 } end
    return record
end
local dressageHorse = { experience = nil }
for _ = 1, 10 do EqExperience.addStart(dressageHorse, config.disciplineByName.dressage) end
local xp10 = EqExperience.get(dressageHorse, "dressage")
check("ten starts take experience about half way", xp10 > 40 and xp10 < 60, string.format("%.1f", xp10))
for _ = 1, 200 do EqExperience.addStart(dressageHorse, config.disciplineByName.dressage) end
check("experience never passes the maximum", EqExperience.get(dressageHorse, "dressage") <= EqExperience.MAX)
check("dressage teaches a little eventing", EqExperience.get(dressageHorse, "eventing") > 0
    and EqExperience.get(dressageHorse, "eventing") < EqExperience.get(dressageHorse, "dressage"))
check("full experience adds the whole bonus", math.abs(EqExperience.ratingBonus(experienceOf({ dressage = 100 }), "dressage")
    - EqExperience.RATING_BONUS) < 1e-9)
check("no experience adds nothing", EqExperience.ratingBonus({}, "dressage") == 0)

local fading = experienceOf({ dressage = 80 })
for _ = 1, EqExperience.FADE_GRACE_MONTHS do EqExperience.monthlyFade(fading) end
check("experience holds through the grace months", EqExperience.get(fading, "dressage") == 80)
for _ = 1, 9 do EqExperience.monthlyFade(fading) end
local afterYear = EqExperience.get(fading, "dressage")
check("a year without dressage fades it slowly", afterYear > 40 and afterYear < 60, string.format("%.1f", afterYear))
EqExperience.addStart(fading, config.disciplineByName.dressage)
EqExperience.monthlyFade(fading)
check("a start restarts the grace months", EqExperience.get(fading, "dressage") > afterYear)

local function specialtyOf(values)
    return (EqExperience.specialty(experienceOf(values), config.disciplines))
end
check("no experience, no specialty", specialtyOf({}) == "none")
check("a little experience is not a specialty", specialtyOf({ dressage = 5 }) == "none")
check("one clear best is the specialty", specialtyOf({ dressage = 60, showJumping = 30 }) == "one")
local _, names = EqExperience.specialty(experienceOf({ dressage = 30, showJumping = 60 }), config.disciplines)
check("the specialty names the best", names[1] == "showJumping")
check("two close make a pair", specialtyOf({ dressage = 60, showJumping = 55 }) == "pair")
check("jumping, dressage and cross country close make an eventer",
    specialtyOf({ dressage = 60, showJumping = 55, crossCountry = 58, eventing = 50 }) == "eventer")
check("close races make a racehorse", specialtyOf({ raceShort = 60, raceLong = 55, steeplechase = 50 }) == "racehorse")
check("three unrelated close make an all-rounder", specialtyOf({ dressage = 60, raceShort = 55, crossCountry = 58 }) == "allRounder")

-- Experience is saved with the horse.
local function memoryXML()
    local values = {}
    local store = {}
    function store:setString(path, v) values[path] = v end
    store.setFloat, store.setInt, store.setBool = store.setString, store.setString, store.setString
    function store:getString(path, default) local v = values[path]; if v == nil then return default end return v end
    function store:getFloat(path, default) local v = values[path]; if v == nil then return default end return tonumber(v) end
    store.getInt = store.getFloat
    function store:getBool(path, default) local v = values[path]; if v == nil then return default end return v == true end
    function store:hasProperty(path)
        for key in pairs(values) do
            if key == path or key:sub(1, #path + 1) == path .. "#" or key:sub(1, #path + 1) == path .. "." then return true end
        end
        return false
    end
    return store
end
local saved = EqHorseRecord.new("DE 1 7")
EqExperience.addStart(saved, config.disciplineByName.eventing)
local xml = memoryXML()
saved:saveToXMLFile(xml, "horse")
local loaded = EqHorseRecord.loadFromXMLFile(xml, "horse")
check("experience survives a save", math.abs(EqExperience.get(loaded, "eventing") - EqExperience.get(saved, "eventing")) < 1e-9
    and math.abs(EqExperience.get(loaded, "dressage") - EqExperience.get(saved, "dressage")) < 1e-9)
check("an old save loads with no experience", EqHorseRecord.loadFromXMLFile((function()
    local x = memoryXML(); EqHorseRecord.new("DE 1 8"):saveToXMLFile(x, "h"); return x end)(), "h").experience == nil)

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
check("a far trip injures more", EqRisk.injuryChance(xc, intermediate, good, 80, 50, false, config.distances.far.injury)
    > EqRisk.injuryChance(xc, intermediate, good, 80, 50, false, config.distances["local"].injury))

-- Risk words on the Events tab.
local heavy = config.goings[4]
local function eventBand(discipline, tier, going, distance)
    return EqRisk.riskBand(EqRisk.eventInjuryChance(config.disciplineByName[discipline], config.tierByName[tier],
        going, config.distances[distance].injury))
end
check("dressage is low risk", eventBand("dressage", "championship", nil, "far") == "low")
check("training show jumping is low risk", eventBand("showJumping", "training", nil, "local") == "low")
check("a heavy steeplechase abroad is risky", eventBand("steeplechase", "advanced", heavy, "far") == "risky")
check("a good-going steeplechase at home is moderate, not risky", eventBand("steeplechase", "advanced", good, "local") == "moderate")
check("an unfit horse carries more risk than the event's typical horse",
    EqRisk.runInjuryChance(xc, intermediate, good, 20, 10, 0.1, 1) > EqRisk.eventInjuryChance(xc, intermediate, good, 1))

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
check("dealer horses are greener than home-produced ones", greenSum < 0.95 * homeSum,
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
    { stamina = 82, speed = 70, agility = 70, temperament = 70 }) == "better")
check("verdict worse", EqDealer.verdict({ stamina = 84, speed = 70, agility = 70, temperament = 70 },
    { stamina = 70, speed = 70, agility = 70, temperament = 70 }) == "worse")
check("verdict fair", EqDealer.verdict({ stamina = 78, speed = 70, agility = 70, temperament = 70 },
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
check("a green talent-85 horse costs about $6-12k", greenPrice > 6000 and greenPrice < 12000, string.format("%.0f", greenPrice))
check("skill drives the price: a schooled horse is worth far more", schooledPrice > 1.8 * greenPrice,
    string.format("%.0f -> %.0f", greenPrice, schooledPrice))
local youngTalent = EqDealer.price(4000, 5000, c85, green, 20)
local youngPlain = EqDealer.price(4000, 5000, { stamina = 60, speed = 60, agility = 60, temperament = 60 }, green, 20)
check("in a young horse, potential is worth a lot", youngTalent > 1.8 * youngPlain,
    string.format("%.0f vs %.0f", youngTalent, youngPlain))
local sick = EqDealer.price(4000, 5000, c85, schooled, 60, { health = 0.05, soundness = 0.05, intact = true })
check("a sick horse loses most of its premium", sick < 0.4 * schooledPrice, string.format("%.0f", sick))
local gelded = EqDealer.price(4000, 5000, c85, schooled, 60, { health = 1, soundness = 1, intact = false })
check("gelding takes away the stud value", gelded < schooledPrice and gelded > 0.6 * schooledPrice,
    string.format("%.0f vs %.0f", gelded, schooledPrice))
local ended = EqDealer.price(4000, 5000, c85, schooled, 60, { health = 1, soundness = 0, intact = true })
check("a career-ended horse keeps only its stud value", ended < 0.5 * schooledPrice, string.format("%.0f", ended))
check("a gelding with no stud value reads as not intact", not EqDealer.condition({ gender = "male", isCastrated = true }, nil).intact
    and EqDealer.condition({ gender = "female" }, nil).intact)
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

-- Metabolism: faster gets fit faster, slower slower; losses unchanged.
check("average metabolism changes nothing", EqMetabolism.fitnessFactor(1.0) == 1 and EqMetabolism.fitnessFactor(nil) == 1)
check("fast metabolism gains fitness faster", EqMetabolism.scaleFitness({ genetics = { metabolism = 1.5 } }, 10) == 13)
check("slow metabolism gains fitness slower", EqMetabolism.scaleFitness({ genetics = { metabolism = 0.5 } }, 10) == 7)
check("metabolism factor is bounded", EqMetabolism.fitnessFactor(0.25) == EqConstants.METABOLISM_FITNESS_MIN
    and EqMetabolism.fitnessFactor(1.75) == EqConstants.METABOLISM_FITNESS_MAX)
check("fitness lost is not scaled", EqMetabolism.scaleFitness({ genetics = { metabolism = 1.5 } }, -5) == -5)

-- Facilities: data/facilities.xml matches the supported mods and caps the bonuses.
local facilities = EqFacility.read(TestXML.load("data/facilities.xml"))
local modsDir = "C:/Users/User/Documents/My Games/FarmingSimulator2025/mods/"
check("horsePack riding hall is an indoor arena",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_horsePack/xml/ridingHall.xml", false) == "indoorArena")
check("horsePack outdoor area is an outdoor arena",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_horsePack/xml/outdoorRidingArea.xml", false) == "outdoorArena")
check("Riding Hall 2k26 hall matches, backslashes and case aside",
    EqFacility.kindForXml(facilities, "C:\\mods\\fs25_ridinghall\\reithalle.xml", false) == "indoorArena")
check("Riding Hall 2k26 jumps match by prefix",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_RidingHall/props07.xml", false) == "jumps")
check("Riding Hall 2k26 letters are not jumps",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_RidingHall/objekt.xml", false) == nil)
check("Riding Stable is a riding centre",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_RidingStable/XML/horseBarnBig.xml", true) == "ridingCentre")
check("Horse Stable is a stable", EqFacility.kindForXml(facilities, modsDir .. "FS25_horseStable/horseStable.xml", true) == "stable")
check("keywords catch an unknown riding hall",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_SomeRidingHall/ridingHallBig.xml", false) == "indoorArena")
check("keywords skip husbandries",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_SomeRidingHall/ridingHallBig.xml", true) == nil)
check("base game stables are not facilities",
    EqFacility.kindForXml(facilities, "data/placeables/mapUS/stable02/stable02.xml", true) == nil)
check("the base game round barn is a round pen",
    EqFacility.kindForXml(facilities, "data/placeables/mapUS/barn02/barn02.xml", false) == "roundPen")
check("the game's round barn matches however the path is resolved",
    EqFacility.kindForXml(facilities, "$data/placeables/mapUS/barn02/barn02.xml", false) == "roundPen")
check("a map's or mod's own barn02 is not a round pen",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_SomeMap/maps/map/placeables/barn02/barn02.xml", false) == nil
    and EqFacility.kindForXml(facilities, modsDir .. "FS25_SomeMap/data/placeables/mapUS/barn02/barn02.xml", false) == nil)
check("other barns are not round pens",
    EqFacility.kindForXml(facilities, "data/placeables/mapUS/barn01/barn01.xml", false) == nil
    and EqFacility.kindForXml(facilities, "data/placeables/mapUS/oldbarn02/barn02.xml", false) == nil)
check("a round pen is a temperament and dressage place",
    EqFacility.improvedStats(facilities.kindByName.roundPen)[1] == "temperament"
    and EqFacility.eventBonus(facilities, { roundPen = 1 }, "dressage") > EqFacility.eventBonus(facilities, { roundPen = 1 }, "showJumping"))
check("Elmcreek obstacles are jumps", EqFacility.kindForNode(facilities, "horseObstacleBales_PREFAB") == "jumps"
    and EqFacility.kindForNode(facilities, "horseSoccerBall") == nil)

local points = EqFacility.dedupe({
    { kind = "jumps", x = 0, z = 0 }, { kind = "jumps", x = 0.5, z = 0 }, { kind = "jumps", x = 0, z = 12 },
}, 2)
check("a prefab and its model count as one fence", #points == 2)

local noneOwned, noneRidden = EqFacility.boosts(facilities, {}, nil)
check("no facilities, no boost", noneOwned.agility == 0 and noneRidden.agility == 0)
local hallOwned, hallRidden = EqFacility.boosts(facilities, { indoorArena = 1 }, { indoorArena = 0.5 })
check("an owned hall speeds staff up", math.abs(hallOwned.agility - 0.10) < 1e-9 and hallOwned.speed == 0)
check("riding half the day in it adds half its ridden share", math.abs(hallRidden.agility - 0.175) < 1e-9)
local threeJumps = EqFacility.boosts(facilities, { jumps = 3 }, nil)
check("half a jump course gives half the bonus", math.abs(threeJumps.agility - 0.05) < 1e-9)
local everything = EqFacility.boosts(facilities, { stable = 2, indoorArena = 2, ridingCentre = 1, outdoorArena = 1, roundPen = 1, jumps = 20 },
    { indoorArena = 1, ridingCentre = 1, jumps = 1 })
check("owned shares are capped", everything.agility <= facilities.ownedCap + 1e-9 and everything.temperament <= facilities.ownedCap + 1e-9)
local _, everythingRidden = EqFacility.boosts(facilities, { indoorArena = 1, ridingCentre = 1, jumps = 6 }, { indoorArena = 1, ridingCentre = 1, jumps = 1 })
check("ridden shares are capped", everythingRidden.agility <= facilities.riddenCap + 1e-9)
check("a jump course helps show jumping", EqFacility.eventBonus(facilities, { jumps = 6 }, "showJumping") > 0
    and EqFacility.eventBonus(facilities, { jumps = 6 }, "raceShort") == 0)
check("event bonus is capped", EqFacility.eventBonus(facilities, { indoorArena = 1, ridingCentre = 1, jumps = 6 }, "showJumping") <= facilities.eventCap + 1e-9)
local hall = facilities.kindByName.indoorArena
local improved = EqFacility.improvedStats(hall)
check("a hall improves agility and temperament first", (improved[1] == "agility" or improved[1] == "temperament") and #improved == 3)

local insideSheet = ridden("canter", 100000)
EqTraining.addInside(insideSheet, "indoorArena", 25000)
check("inside share is time inside over time ridden", math.abs(EqFacility.insideShares(insideSheet).indoorArena - 0.25) < 1e-9)

-- A facility speeds training up; riding inside speeds the player's riding up more.
local plain, faster, inside = horse("balanced", 10), horse("balanced", 10), horse("balanced", 10)
local day = { riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 }
EqTraining.applyDay(plain, cap70, day)
EqTraining.applyDay(faster, cap70, { riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1, facilityOwned = hallOwned })
check("an owned facility speeds staff training", faster.trained.agility > plain.trained.agility
    and faster.trained.speed == plain.trained.speed)
local riddenPlain, riddenInside = horse("balanced", 10), horse("balanced", 10)
EqTraining.applyDay(riddenPlain, cap70, { sheet = ridden("canter", 100000), riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1, facilityOwned = hallOwned })
EqTraining.applyDay(riddenInside, cap70, { sheet = ridden("canter", 100000), riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1,
    facilityOwned = hallOwned, facilityRidden = hallRidden })
check("riding inside trains faster still", riddenInside.trained.agility > riddenPlain.trained.agility)


-- Feeds: the map's horse groups are rewritten from data/feeds.xml.
local feeds = EqFeed.read(TestXML.load("data/feeds.xml"))
local function namesOf(group)
    local set = {}
    for _, name in ipairs(group.names) do set[name] = true end
    return set
end
local function groupWith(groups, name)
    for _, group in ipairs(groups) do if namesOf(group)[name] then return group end end
end

-- Geistal's horse groups. Geistal calls its apples APPLE_GT; there is no plain APPLE.
local geistalKnown = {}
for name in ("OAT SORGHUM BARLEY WINTERBARLEY MAIZE WHEAT WINTERWHEAT SPELT TRITICALE RYE CARROT PARSNIP BEETROOT APPLE_GT "
    .. "DRYGRASS_WINDROW GRASS_WINDROW ALFALFA_WINDROW DRYALFALFA_WINDROW CLOVER_WINDROW DRYCLOVER_WINDROW ALFALFA_CHAFF CLOVER_CHAFF"):gmatch("%S+") do
    geistalKnown[name] = true
end
local geistal = EqFeed.planGroups({
    { names = { "OAT", "SORGHUM" } },
    { names = { "DRYGRASS_WINDROW", "GRASS_WINDROW", "ALFALFA_WINDROW", "DRYALFALFA_WINDROW", "CLOVER_WINDROW", "DRYCLOVER_WINDROW" } },
    { names = { "CARROT", "PARSNIP", "BEETROOT" } },
}, feeds, function(name) return geistalKnown[name] == true end)
check("sorghum is no longer a horse feed", groupWith(geistal, "SORGHUM") == nil)
check("barley joins the oats", groupWith(geistal, "BARLEY") == geistal[1] and groupWith(geistal, "MAIZE") == geistal[1])
check("winter crops join too", groupWith(geistal, "WINTERBARLEY") == geistal[1] and groupWith(geistal, "WINTERWHEAT") == geistal[1])
check("Geistal's apples are a treat", groupWith(geistal, "APPLE_GT") == geistal[3])
check("an unknown fill type is not added", groupWith(geistal, "APPLE") == nil)
check("chaff goes with the hay", groupWith(geistal, "ALFALFA_CHAFF") == geistal[2])
check("no group is invented when the map has all three", #geistal == 3)

-- A map whose horses only eat sorghum and hay: the emptied group goes, a treat group is made.
local sparse = EqFeed.planGroups({ { names = { "SORGHUM" } }, { names = { "DRYGRASS_WINDROW" } } }, feeds,
    function(name) return name == "OAT" or name == "CARROT" or name == "APPLE" or name == "DRYGRASS_WINDROW" end)
local oatGroup, appleGroup = groupWith(sparse, "OAT"), groupWith(sparse, "APPLE")
check("a map without the kind gets a new group", oatGroup ~= nil and oatGroup.isNew and oatGroup.group.name == "grain")
check("the emptied sorghum group is dropped", #sparse == 3, tostring(#sparse))
check("Orchards and Greenhouses apples are a treat", appleGroup ~= nil and appleGroup == groupWith(sparse, "CARROT"))

-- Boosts: hay gives nothing, every feed in the trough adds its full boost, carrots and apples count once.
local function near(a, b) return math.abs(a - b) < 1e-9 end
local hayOnly = EqFeed.dietBoost({ DRYGRASS_WINDROW = 5000 }, feeds)
check("hay gives no boost", hayOnly.stamina == 0 and hayOnly.speed == 0 and hayOnly.agility == 0 and hayOnly.temperament == 0)
local oats = EqFeed.dietBoost({ DRYGRASS_WINDROW = 5000, OAT = 100 }, feeds)
check("oats: small stamina and temperament", near(oats.stamina, 0.10) and near(oats.temperament, 0.10) and oats.speed == 0)
local barley = EqFeed.dietBoost({ BARLEY = 100 }, feeds)
check("barley: moderate agility and stamina", near(barley.agility, 0.20) and near(barley.stamina, 0.20))
check("corn: strong speed", near(EqFeed.dietBoost({ MAIZE = 1 }, feeds).speed, 0.30))
check("carrots: strong temperament", near(EqFeed.dietBoost({ CARROT = 1 }, feeds).temperament, 0.30))
check("apples match carrots", near(EqFeed.dietBoost({ APPLE_GT = 1 }, feeds).temperament, 0.30))
local mixed = EqFeed.dietBoost({ OAT = 50, BARLEY = 10, MAIZE = 50, CARROT = 10 }, feeds)
check("oats, barley and corn stack", near(mixed.speed, 0.30) and near(mixed.stamina, 0.30) and near(mixed.agility, 0.20))
check("grain and treats add up", near(mixed.temperament, 0.10 + 0.30))
local sweet = EqFeed.dietBoost({ CARROT = 10, APPLE = 10, APPLE_GT = 10 }, feeds)
check("carrots and apples do not stack", near(sweet.temperament, 0.30), string.format("%.2f", sweet.temperament))
check("an empty trough gives nothing", EqFeed.dietBoost({ MAIZE = 0 }, feeds).speed == 0)

-- The boost speeds training up, and gives nothing on a day without work.
local function trainedSpeed(feedBoost, sheet)
    local record = { trained = { stamina = 30, speed = 30, agility = 30, temperament = 30 }, focus = "balanced", idleDays = 0 }
    local ceilings = { stamina = 80, speed = 80, agility = 80, temperament = 80 }
    EqTraining.applyDay(record, ceilings, { sheet = sheet, riding = 0, ageMonths = 60, timeAdjustment = 1 / 30, feedBoost = feedBoost })
    return record.trained.speed
end
local gallop = ridden("gallop", 100000)
local plain, corn = trainedSpeed(nil, gallop), trainedSpeed(EqFeed.dietBoost({ MAIZE = 1 }, feeds), ridden("gallop", 100000))
check("corn makes galloping train speed faster", corn > plain and near((corn - 30) / (plain - 30), 1.30),
    string.format("%.4f vs %.4f", corn, plain))
check("feed alone trains nothing", trainedSpeed(EqFeed.dietBoost({ MAIZE = 1 }, feeds), nil) == 30)

-- Pen food rows: each group is named for what it mostly holds, and lists the stats it can boost.
check("Geistal's groups are hard feed, hay and treats", EqFeed.groupKind(geistal[1].names, feeds) == "grain"
    and EqFeed.groupKind(geistal[2].names, feeds) == "hay" and EqFeed.groupKind(geistal[3].names, feeds) == "treat")
check("a map's own extra feed does not decide the group", EqFeed.groupKind({ "MINERAL_FEED", "OAT" }, feeds) == "grain")
check("hard feed can boost every stat", #EqFeed.boostedStats(geistal[1].names, feeds) == 4)
check("hay boosts nothing", #EqFeed.boostedStats(geistal[2].names, feeds) == 0)
local treatStats = EqFeed.boostedStats(geistal[3].names, feeds)
check("treats boost temperament", #treatStats == 1 and treatStats[1] == "temperament")
check("strength marks: small, moderate, strong", EqFeed.strengthMarks(0.10) == "+" and EqFeed.strengthMarks(0.20) == "++"
    and EqFeed.strengthMarks(0.30) == "+++" and EqFeed.strengthMarks(0.40) == "+++")
check("no boost, no marks", EqFeed.strengthMarks(0) == "" and EqFeed.strengthMarks(nil) == "")
local grainBest = EqFeed.bestBoost(geistal[1].names, feeds)
check("hard feed's best: corn's speed, barley's stamina and agility, oats' temperament", near(grainBest.speed, 0.30)
    and near(grainBest.stamina, 0.20) and near(grainBest.agility, 0.20) and near(grainBest.temperament, 0.10))

-- Pen food rows: oats, barley and corn get a row each; the rest of the grain only while it is fed.
local function rowNames(rows)
    local out = {}
    for _, row in ipairs(rows) do table.insert(out, (row.row or "rest") .. "=" .. row.value) end
    return table.concat(out, " ")
end
local grainRows = EqFeed.splitRows(geistal[1].names, { OAT = 100, MAIZE = 50, WINTERBARLEY = 5 }, feeds)
check("oats, barley and corn get a row each", rowNames(grainRows) == "eq_feedRow_oats=100 eq_feedRow_barley=5 eq_feedRow_corn=50",
    rowNames(grainRows))
local withWheat = EqFeed.splitRows(geistal[1].names, { WHEAT = 20 }, feeds)
check("other grain shows while it is fed", rowNames(withWheat) == "eq_feedRow_oats=0 eq_feedRow_barley=0 eq_feedRow_corn=0 rest=20",
    rowNames(withWheat))
local hayRows = EqFeed.splitRows(geistal[2].names, {}, feeds)
check("a group without rows stays one row", #hayRows == 1 and hayRows[1].row == nil)

-- RLRM's message log: our ids go into RLRM's real RLMessage, and lines land in the horse's husbandry.
-- In its own function: the main chunk is close to Lua's 200-local limit.
local function messageLogTests()
    local rlrmEnv = { RLConstants = { SEVERITY = { INFO = "info", SUCCESS = "success", NOTICE = "notice", WARNING = "warning" } } }
    RLConstants = rlrmEnv.RLConstants
    dofile(rlrmPath .. "/scripts/messaging/RLMessage.lua")
    rlrmEnv.RLMessage = RLMessage

    local texts = { rl_message_eqText = "%s", rl_messageTitle_eqCompetition = "Competition" }
    local savedI18n, savedMission, savedEnv = g_i18n, g_currentMission, EqRLRM.env
    g_i18n = { texts = {}, hasText = function(_, key) return texts[key] ~= nil end, getText = function(_, key) return texts[key] end }
    _G.g_i18n = g_i18n
    EqRLRM.env = rlrmEnv
    dofile("scripts/core/EqMessages.lua")

    local function husbandry(animals)
        local logged = {}
        return { logged = logged, spec_husbandryAnimals = { getClusters = function() return animals end },
            addRLMessage = function(_, id, animal, args) table.insert(logged, { id = id, animal = animal, args = args }) end }
    end
    local horse = { isHorse = function() return true end, getIdentifiers = function() return "GB 1 42" end }
    local cow = { isHorse = function() return false end }
    local cows, stable = husbandry({ cow }), husbandry({ horse })
    rlrmEnv.RLAnimalQuery = { listHusbandriesForFarm = function() return { cows, stable } end }

    g_currentMission = { getIsServer = function() return true end }
    EqMessages.post(1, "EQ_PLACED", "Not yet installed", horse)
    check("nothing is logged before install", #stable.logged == 0)

    check("message ids install", EqMessages.install())
    local placed = RLMessage.EQ_PLACED
    check("a placing is a success line in the Competition group",
        placed ~= nil and placed.severity == "success" and placed.title == "eqCompetition" and placed.text == "eqText")
    check("RLRM's own ids are untouched", RLMessage.DEATH ~= nil and RLMessage.DEATH.text == "death")
    check("every id has a real severity", (function()
        for id in pairs(EqMessages.TYPES) do
            if RLMessage[id] == nil or RLMessage[id].severity == nil then return false end
        end
        return true
    end)())
    check("our texts reach the global table", g_i18n.texts.rl_message_eqText == "%s")

    EqMessages.post(1, "EQ_PLACED", "Star finished 1 of 8 in Dressage, winning $500.", horse)
    check("an unhoused horse's line goes in the farm's pen with horses", #stable.logged == 1 and #cows.logged == 0)
    check("the line carries the sentence and the horse",
        stable.logged[1] ~= nil and stable.logged[1].args[1] == "Star finished 1 of 8 in Dressage, winning $500."
            and stable.logged[1].animal == "GB 1 42")

    local home = husbandry({})
    horse.clusterSystem = { owner = home }
    EqMessages.post(1, "EQ_INJURED", "Star was injured.", horse)
    check("a horse's line goes in its own husbandry", #home.logged == 1 and home.logged[1].id == "EQ_INJURED")

    EqMessages.post(1, "NOT_OURS", "x", horse)
    check("unknown ids are not logged", #home.logged == 1)

    g_currentMission = { getIsServer = function() return false end }
    EqMessages.post(1, "EQ_INJURED", "Star was injured.", horse)
    check("clients don't log; the server's line syncs to them", #home.logged == 1)

    g_i18n, g_currentMission, EqRLRM.env = savedI18n, savedMission, savedEnv
    _G.g_i18n = savedI18n
end
messageLogTests()

-- Menu paging reset. A minimal paging element with the base game's updatePageMapping logic.
local function newPaging(n)
    local paging = { pages = {}, idPageHash = {}, currentPageIndex = 1, currentPageMappingIndex = 1 }
    for i = 1, n do
        local page = { id = "P" .. i, disabled = false, mappingIndex = i }
        paging.pages[i] = page
        paging.idPageHash[page.id] = page
    end
    function paging:updatePageMapping()
        self.pageMapping = {}
        for i, page in ipairs(self.pages) do
            if not page.disabled then
                table.insert(self.pageMapping, i)
                page.mappingIndex = #self.pageMapping
            else
                page.mappingIndex = 1
            end
        end
    end
    function paging:setPageIdDisabled(id, disabled)
        self.idPageHash[id].disabled = disabled
        self:updatePageMapping()
    end
    return paging
end
-- The Transfer view left only page 9 enabled and current.
local stale = newPaging(10)
for i = 1, 10 do stale.pages[i].disabled = (i ~= 9) end
stale.currentPageIndex = 9
stale:updatePageMapping()
local menu = { pagingElement = stale, openMode = "full", eqLastPagingMode = "trailer", restorePageScrollOffset = 3 }
EqMenuPaging.beforeUpdatePages(menu)
check("paging reset enables every page", #stale.pageMapping == 10)
check("paging reset moves to page 1", stale.currentPageIndex == 1 and stale.currentPageMappingIndex == 1)
check("paging reset unmutes updates", stale.neuterPageUpdates == false)
check("paging reset clears the tab scroll", menu.restorePageScrollOffset == 0)
check("paging remembers the mode", menu.eqLastPagingMode == "full")
-- Same mode again: left alone.
stale.pages[3].disabled = true
stale.currentPageIndex = 4
EqMenuPaging.beforeUpdatePages(menu)
check("same mode leaves paging alone", stale.pages[3].disabled and stale.currentPageIndex == 4)
-- First open after load: nothing to reset.
local fresh = { pagingElement = newPaging(3), openMode = "trailer" }
fresh.pagingElement.currentPageIndex = 2
EqMenuPaging.beforeUpdatePages(fresh)
check("first open leaves paging alone", fresh.pagingElement.currentPageIndex == 2 and fresh.eqLastPagingMode == "trailer")
check("reset refuses a missing paging element", EqMenuPaging.reset({}) == false)

-- Animals page: RLRM's Manage Animals button for horse pens.
local function testAnimalsPageButton()
g_i18n = g_i18n or { getText = function(_, key) return key end }
local savedGet = EqRLRM.get
EqRLRM.get = function(name) if name == "RLMenu" then return { MODE_FULL = "full" } end return savedGet(name) end
local RL_ACTION = 77
local horsePen = { spec_husbandryAnimals = {}, getName = function() return "Horse Barn" end }
local cowPen = { spec_husbandryAnimals = {} }
local opened
local function openMenu(page, mode, context) opened = { page = page, mode = mode, context = context } end
-- RLRM already added it: left alone.
local cowFrame = { selectedHusbandry = cowPen, menuButtonInfo = { { inputAction = 1 }, { inputAction = RL_ACTION } } }
check("button kept when RLRM added it", EqAnimalsPageButton.ensureButton(cowFrame, cowFrame.menuButtonInfo, RL_ACTION, openMenu) == false
    and #cowFrame.menuButtonInfo == 2)
-- Horse selected, no selectedHusbandry: found through the horse's pen.
local horseFrame = {
    menuButtonInfo = { { inputAction = 1 } },
    list = { selectedSectionIndex = 1, selectedIndex = 2 },
    husbandrySubTypes = { 5 },
    subTypeIndexToClusters = { [5] = { {}, { clusterSystem = { owner = horsePen } } } },
}
check("button added for a horse pen", EqAnimalsPageButton.ensureButton(horseFrame, horseFrame.menuButtonInfo, RL_ACTION, openMenu) == true
    and #horseFrame.menuButtonInfo == 2 and horseFrame.menuButtonInfo[2].inputAction == RL_ACTION)
local dirtyFrame = { selectedHusbandry = horsePen, setMenuButtonInfoDirty = function(f) f.dirty = true end }
EqAnimalsPageButton.ensureButton(dirtyFrame, {}, RL_ACTION, openMenu)
check("adding the button redraws the bar", dirtyFrame.dirty == true)
local fullBar = { { inputAction = 1 }, { inputAction = 2 }, { inputAction = 3 } }
EqAnimalsPageButton.ensureButton(horseFrame, fullBar, RL_ACTION, openMenu, nil, 3)
check("full bar: button moves just after Back", fullBar[2].inputAction == RL_ACTION and #fullBar == 4)
local horseBar = { { inputAction = "BACK" }, { inputAction = "NEXT" }, { inputAction = "PREV" },
    { inputAction = "TAG" }, { inputAction = "RENAME" }, { inputAction = "WORKERS" } }
EqAnimalsPageButton.ensureButton(horseFrame, horseBar, RL_ACTION, openMenu, nil, 6, { NEXT = true, PREV = true })
check("full horse bar: page buttons make room, Workers kept", #horseBar == 5 and horseBar[2].inputAction == RL_ACTION
    and horseBar[5].inputAction == "WORKERS")
local roomyBar = { { inputAction = 1 }, { inputAction = 2 } }
EqAnimalsPageButton.ensureButton(horseFrame, roomyBar, RL_ACTION, openMenu, nil, 6)
check("bar with room: button goes last", roomyBar[3].inputAction == RL_ACTION)
local lateBar = { { inputAction = 1 }, { inputAction = 2 }, { inputAction = 3 }, { inputAction = RL_ACTION } }
check("button past the slots is moved", EqAnimalsPageButton.ensureButton(horseFrame, lateBar, RL_ACTION, openMenu, nil, 3) == true
    and lateBar[2].inputAction == RL_ACTION)
horseFrame.menuButtonInfo[2].callback()
check("button opens the Manage tab on that pen", opened.page == 4 and opened.mode == "full"
    and opened.context.husbandry == horsePen and opened.context.fromInGameMenu == true)
-- Empty stable: found through the page selector.
local emptyFrame = { menuButtonInfo = {}, husbandries = { cowPen, horsePen },
    subCategorySelector = { getState = function() return 2 end } }
check("selector finds the pen", EqAnimalsPageButton.findHusbandry(emptyFrame) == horsePen)
local noPens = function() return {} end
check("no pen, no button", EqAnimalsPageButton.ensureButton({}, {}, RL_ACTION, openMenu, noPens) == false)
-- Only the selector's text to go on: matched against the farm's pens by name.
local namedFrame = { subCategorySelector = { texts = { "Cow Barn", "Horse Barn" }, getState = function() return 2 end } }
local pens = function() return { { spec_husbandryAnimals = {}, getName = function() return "Cow Barn" end }, horsePen } end
check("selector name finds the pen", EqAnimalsPageButton.findHusbandry(namedFrame, pens) == horsePen)
EqRLRM.get = savedGet
end
testAnimalsPageButton()

-- Loose horses go home to their own staffed pen, else the nearest staffed pen with room.
;(function()
    local p = {
        home = { farmId = 1, hasRoom = true, x = 500, z = 0 },
        near = { farmId = 1, hasRoom = true, x = 10, z = 0 },
        full = { farmId = 1, hasRoom = false, x = 0, z = 0 },
        other = { farmId = 2, hasRoom = true, x = 1, z = 0 },
    }
    p.all = { p.home, p.near, p.full, p.other }
    check("loose horse goes to its own pen", EqLooseHorses.choosePen(p.home, p.all, 1, 0, 0) == p.home)
    check("loose horse from an unstaffed pen goes to the nearest staffed one",
        EqLooseHorses.choosePen(nil, p.all, 1, 0, 0) == p.near)
    p.home.hasRoom = false
    check("full home pen sends the horse to the nearest with room", EqLooseHorses.choosePen(p.home, p.all, 1, 0, 0) == p.near)
    check("no staffed pen on the farm leaves the horse out", EqLooseHorses.choosePen(nil, { p.other, p.full }, 1, 0, 0) == nil)
    check("loose horse with no position still finds a pen", EqLooseHorses.choosePen(nil, { p.other, p.near }, 1, nil, nil) == p.near)
end)()

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

--[[
    Headless tests for the pure stats maths.

    Run from the repo root:  luajit tests/run.lua <path to an RLRM checkout>
    RLRM's own BreedingMath.lua is loaded from that checkout rather than copied here.
]]

local rlrmPath = arg[1]
assert(rlrmPath, "usage: luajit tests/run.lua <path to FS25_RealisticLivestockRM>")

dofile(rlrmPath .. "/scripts/animal/BreedingMath.lua")
dofile("scripts/core/EqConstants.lua")
dofile("scripts/core/EqSettings.lua")
dofile("scripts/core/EqRandom.lua")
dofile("scripts/core/EqStats.lua")
dofile("scripts/training/EqExertion.lua")
dofile("scripts/training/EqTraining.lua")
dofile("scripts/training/EqDressage.lua")
dofile("scripts/training/EqCourse.lua")
dofile("scripts/training/EqMetabolism.lua")
dofile("scripts/core/EqRLRM.lua")
dofile("scripts/core/EqI18N.lua")
dofile("scripts/competition/EqEventConfig.lua")
dofile("scripts/competition/EqPerformance.lua")
dofile("scripts/competition/EqRivals.lua")
dofile("scripts/competition/EqStory.lua")
dofile("scripts/competition/EqCompetition.lua")
dofile("scripts/competition/EqExperience.lua")
dofile("scripts/competition/EqRisk.lua")
EqLog = { debug = function() end, info = function() end, warning = function() end, error = function() end }
dofile("scripts/competition/EqInjury.lua")
dofile("scripts/facilities/EqFacility.lua")
dofile("scripts/core/EqHorseRecord.lua")
dofile("scripts/core/EqRole.lua")
dofile("scripts/core/EqStatLog.lua")
dofile("scripts/training/EqFeed.lua")
dofile("scripts/dealer/EqDealer.lua")
dofile("scripts/core/EqRegistry.lua")
dofile("scripts/core/EqFreshStart.lua")
dofile("scripts/gui/EqMenuPaging.lua")
dofile("scripts/training/EqLooseHorses.lua")
dofile("scripts/gui/EqAnimalsPageButton.lua")
dofile("scripts/gui/EqRideButton.lua")
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
-- Translations: no key twice in English, and every other language has each English key with the
-- same placeholders in the same order (string.format can't reorder them).
;(function()
    local function texts(path)
        local list, byName = {}, {}
        for _, node in ipairs(TestXML.load(path).root.children[1].children[1].children) do
            table.insert(list, node.attrs.name)
            byName[node.attrs.name] = (byName[node.attrs.name] or 0) > 0 and false or node.attrs.text
        end
        return list, byName
    end
    local function placeholders(text)
        local found = {}
        for spec in text:gmatch("%%[-+]?%d*%.?%d*[sdf%%]") do table.insert(found, spec) end
        return table.concat(found, " ")
    end
    local enList, en = texts("translations/translation_en.xml")
    for _, name in ipairs(enList) do check("English text " .. name .. " appears once", en[name] ~= false) end
    for _, language in ipairs({ "de" }) do
        local _, other = texts("translations/translation_" .. language .. ".xml")
        for _, name in ipairs(enList) do
            check(language .. " has " .. name, type(other[name]) == "string")
            if type(other[name]) == "string" and en[name] then
                check(language .. " " .. name .. " keeps the placeholders", placeholders(other[name]) == placeholders(en[name]),
                    placeholders(en[name]) .. " / " .. placeholders(other[name]))
            end
        end
    end
end)()

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
check("young horses train at full speed", EqStats.ageTrainingFactor(12) == 1.0 and EqStats.ageTrainingFactor(30) == 1.0)
check("a stat at 0 trains three times as fast", EqTraining.lowSkillFactor(0) == EqTraining.LOW_SKILL_MAX)
check("a stat at 20 trains twice as fast", math.abs(EqTraining.lowSkillFactor(20) - 2) < 1e-9)
check("from 40 a stat trains at the normal rate", EqTraining.lowSkillFactor(40) == 1 and EqTraining.lowSkillFactor(70) == 1)
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

-- Horses left in a farm's livestock trailer still count as the farm's.
;(function()
    local savedMission = g_currentMission
    local function horse(name) return { name = name, isHorse = function() return true end } end
    local cow = { isHorse = function() return false end }
    local function trailer(farmId, animals)
        return { spec_livestockTrailer = {}, getOwnerFarmId = function() return farmId end,
            getClusters = function() return animals end }
    end
    local tractor = { getOwnerFarmId = function() return 1 end }
    g_currentMission = { vehicleSystem = { vehicles = {
        trailer(1, { horse("Iolanthe"), cow }), trailer(2, { horse("Other farm") }), tractor,
        trailer(1, { horse("Shiver") }) } } }
    local found = EqRLRM.listHorsesInTrailers(1)
    check("trailer horses found, cows and other farms left out", #found == 2
        and found[1].name == "Iolanthe" and found[2].name == "Shiver")
    g_currentMission = nil
    check("no trailer horses without a mission", #EqRLRM.listHorsesInTrailers(1) == 0)
    g_currentMission = savedMission
end)()

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
check("a full canter day trains agility a little; stamina and speed don't train from riding for now",
    canterDay.stamina == 0 and math.abs(canterDay.agility - 0.12) < 1e-9 and canterDay.speed == 0)
check("galloping fills riding three times as fast", EqTraining.playerRidingPoints(ridden("gallop", 100000)) == 100)
check("galloping trains no speed while the exertion system is tested", EqTraining.playerEffort(ridden("gallop", 60000)).speed == 0)
check("backing up fills riding 2.5 times as fast as walking", EqTraining.playerRidingPoints(ridden("reverse", 120000)) == 100)
do
    local reversePoints, reverseTimer, reverseTotal = 0, 0, 0
    for _ = 1, 6000 do
        reversePoints, reverseTimer = EqTraining.reverseExtraRiding(reverseTimer, 20, EqConstants.RIDING_FULL_MS)
        reverseTotal = reverseTotal + reversePoints
    end
    check("two minutes of backing up add 60 riding points on top of the base game's 40", reverseTotal == 60,
        string.format("got %d", reverseTotal))
end
do
    -- Jump combos: each clear in a row is worth more, up to x5; the clock runs ten times as fast
    -- at a walk or a halt, but not at a trot.
    local jumping = EqTraining.newSheet()
    local mults = {}
    for _ = 1, 7 do table.insert(mults, EqTraining.clearJump(jumping, false)) end
    check("a jump combo climbs to x5", table.concat(mults, ",") == "1,2,3,4,5,5,5")
    check("cleared jumps train agility", math.abs(jumping.focused.agility - EqTraining.AGILITY_PER_JUMP * 25) < 1e-9)
    for _ = 1, 90 do EqTraining.comboTick(jumping, "trot", 100) end
    check("trotting keeps the combo for ten seconds", jumping.combo.count == 7)
    local lost = false
    for _ = 1, 15 do lost = EqTraining.comboTick(jumping, "trot", 100) or lost end
    check("the combo is lost after ten seconds without a clear", lost and jumping.combo.count == 0)
    for _ = 1, 25 do EqTraining.comboTick(jumping, "canter", 100) end
    EqTraining.clearJump(jumping, false)
    for _ = 1, 10 do lost = EqTraining.comboTick(jumping, "walk", 100) end
    for _ = 1, 25 do EqTraining.comboTick(jumping, "canter", 100) end
    check("walking drains the combo clock ten times as fast", lost and jumping.combo.count == 0)
    EqTraining.clearJump(jumping, false)
    check("losing a combo reports it", EqTraining.loseCombo(jumping) and not EqTraining.loseCombo(jumping))
    check("a clear just after losing a combo starts no new one", EqTraining.clearJump(jumping, false) == nil and jumping.combo.count == 0)
    for _ = 1, 25 do EqTraining.comboTick(jumping, "canter", 100) end
    check("a new combo can start 2.5 s after losing one", EqTraining.clearJump(jumping, false) == 1)
    local knocked = EqTraining.newSheet()
    EqTraining.clearJump(knocked, false)
    check("a knock takes time off the combo clock", EqTraining.knockCombo(knocked) == "knocked"
        and knocked.combo.count == 1 and math.abs(knocked.combo.timer - (EqTraining.COMBO_SECONDS - EqTraining.COMBO_KNOCK_SECONDS)) < 1e-9)
    check("a second knock straight after costs nothing", EqTraining.knockCombo(knocked) == nil)
    for _ = 1, 30 do EqTraining.comboTick(knocked, "canter", 100) end
    do
        local air = EqTraining.newSheet()
        EqTraining.clearJump(air, false)
        local lost = false
        for _ = 1, 120 do lost = EqTraining.comboTick(air, "canter", 100, true) or lost end
        check("the combo can't run out mid-jump", not lost and air.combo.count == 1)
        check("it runs out once the jump has landed without a clear", EqTraining.comboTick(air, "canter", 100, false))
    end
    knocked.combo.timer = 2
    check("a knock that runs the clock out loses the combo", EqTraining.knockCombo(knocked) == "lost" and knocked.combo.count == 0)
    local wornJump = EqTraining.newSheet()
    EqTraining.clearJump(wornJump, true)
    check("a worn-out horse's jumps count for the combo but train nothing", wornJump.combo.count == 1 and wornJump.focused.agility == 0)
    local showJump = EqTraining.newSheet()
    EqTraining.clearJump(showJump, false, true)
    check("a cleared show jump trains more agility than a fence",
        math.abs(showJump.focused.agility - EqTraining.AGILITY_PER_JUMP * EqTraining.SHOW_JUMP_FACTOR) < 1e-9)

    do
        -- Quicker after a halt, and less time to react at a high multiplier.
        local sheet = EqTraining.newSheet()
        local r = sheet.routine
        r.active, r.mult, r.current, r.clock, r.request, r.deadline = true, 5, "walk", 0, "halt", 10000
        EqTraining.routineStep(sheet, "halt", nil, 100, false, function() return 1 end)
        check("after a full stop the next request comes sooner", r.nextAt - r.clock <= 2500 * 0.7 + 1)
        r.clock = r.nextAt
        EqTraining.routineStep(sheet, "halt", nil, 0, false, function() return 1 end)
        check("a high routine multiplier gives less time to react", r.request ~= nil and r.deadline - r.clock < EqTraining.ROUTINE_REACT_MS)
    end
    do
        -- The routine goes past the jump combo's x5, and from x4 the pace must be held.
        local one = function() return 1 end
        local sheet = EqTraining.newSheet()
        local r = sheet.routine
        r.active, r.mult, r.current, r.clock, r.request, r.deadline = true, EqTraining.ROUTINE_MAX - 1, "walk", 0, "trot", 10000
        EqTraining.routineStep(sheet, "trot", nil, 100, false, one)
        check("the routine climbs to x8", EqTraining.ROUTINE_MAX == 8 and r.mult == 8)
        r.request, r.deadline, r.nextAt = "halt", r.clock + 3000, r.clock + 100000
        r.current = "trot"
        for _ = 1, 10 do EqTraining.routineStep(sheet, "walk", nil, 100, false, one) end
        check("passing through a walk on the way to a stop is fine", r.active)
        EqTraining.routineStep(sheet, "halt", nil, 100, false, one)
        local event
        for _ = 1, 10 do event = EqTraining.routineStep(sheet, "walk", nil, 100, false, one) or event end
        check("at a high multiplier, walking off unasked breaks the routine", not r.active and event == "lost")

        local low = EqTraining.newSheet()
        local lr = low.routine
        lr.active, lr.mult, lr.current, lr.clock, lr.nextAt = true, 2, "walk", 0, 100000
        for _ = 1, 20 do EqTraining.routineStep(low, "trot", nil, 100, false, one) end
        check("at a low multiplier the pace may drift", lr.active)

        local turn = EqTraining.newSheet()
        local tr = turn.routine
        tr.active, tr.mult, tr.current, tr.clock, tr.nextAt = true, 5, "walk", 0, 100000
        tr.request, tr.deadline = "left", 3000
        for _ = 1, 5 do EqTraining.routineStep(turn, "trot", "left", 100, false, one) end
        for _ = 1, 10 do EqTraining.routineStep(turn, "trot", nil, 100, false, one) end
        check("a turn takes any pace, and the pace it ends at is the one to hold", tr.active and tr.current == "trot" and tr.mult == 6)
    end
    do
        -- A routine command shows for a moment even when it is done at once.
        local quick = EqTraining.newSheet()
        local r = quick.routine
        r.active, r.mult, r.current, r.nextAt = true, 1, "walk", 0
        EqTraining.routineStep(quick, "walk", nil, 100, false, function() return 1 end)
        local asked = r.request
        EqTraining.routineStep(quick, (asked == "left" or asked == "right") and "walk" or asked, asked, 400, false, function() return 1 end)
        check("a command done at once still shows for a moment", r.shown == asked and r.clock < r.shownUntil)
    end
    -- Temperament routine.
    local first = function() return 1 end
    local routine = EqTraining.newSheet()
    local events = {}
    local function ride(move, ms)
        for _ = 1, ms / 100 do
            local gait, steer = move, nil
            if move == "left" or move == "right" then gait, steer = "walk", move end
            local event = EqTraining.routineStep(routine, gait, steer, 100, false, first)
            if event ~= nil then table.insert(events, event) end
        end
    end
    ride("trot", 3000)
    check("trotting does not start a routine", not routine.routine.active)
    ride("walk", 2000)
    check("walking starts a routine", routine.routine.active and routine.routine.mult == 1 and events[1] == "start")
    ride("walk", 5000)
    check("the routine asks for a new movement", routine.routine.request == "trot" and events[2] == "request")
    ride("trot", 500)
    check("doing it raises the multiplier", routine.routine.mult == 2 and events[3] == "done" and routine.routine.current == "trot")
    check("from a trot it never asks to back up", not table.concat(EqTraining.routineChoices("trot"), ","):find("reverse")
        and not table.concat(EqTraining.routineChoices("reverse"), ","):find("trot"))
    local before = routine.focused.temperament
    ride("trot", 4000)
    check("a routine above x1 trains temperament", routine.focused.temperament > before)
    ride("trot", 5000)
    check("missing a request ends the routine", not routine.routine.active and events[#events] == "lost")
    ride("walk", 2000)
    ride("fast", 100)
    check("a canter ends the routine", not routine.routine.active and events[#events] == "lost")

    -- Turns come from the steering key, whatever the gait; gaits ignore steering.
    local turning = EqTraining.newSheet()
    local function rideSteer(gait, steer, ms)
        local last
        for _ = 1, ms / 100 do last = EqTraining.routineStep(turning, gait, steer, 100, false, first) or last end
        return last
    end
    rideSteer("walk", "left", 2000)
    check("walking while steering starts a routine", turning.routine.active)
    turning.routine.request, turning.routine.deadline = "right", turning.routine.clock + 3000
    rideSteer("reverse", "left", 500)
    check("steering the wrong way does not count as the turn", turning.routine.request == "right")
    check("backing up while turning counts as the asked-for turn",
        rideSteer("reverse", "right", 500) == "done" and turning.routine.mult == 2)
    turning.routine.request, turning.routine.deadline = "halt", turning.routine.clock + 3000
    check("a stop counts while the rider steers", rideSteer("halt", "left", 200) == "done")
    rideSteer("halt", nil, 100)
    turning.routine.request, turning.routine.deadline = "left", turning.routine.clock + 3000
    rideSteer("halt", "left", 200)
    check("a turn needs its key held for a moment", turning.routine.request == "left")
    rideSteer("halt", "left", 200)
    check("held, it counts at a standstill too", turning.routine.request == nil)
end
do
    -- One riding bar of jumping or a routine, ridden frame by frame.
    local function bar(policy)
        local sheet, t, state = EqTraining.newSheet(), 0, {}
        local rng = function() return 1 end
        while EqTraining.playerRidingPoints(sheet) < 100 and t < 3600000 do
            local gait, move, jumped = policy(sheet, t, state)
            if jumped then EqTraining.clearJump(sheet, false) end
            EqTraining.comboTick(sheet, gait, 50)
            local steer = (move == "left" or move == "right") and move or nil
            EqTraining.routineStep(sheet, steer == nil and (move or gait) or gait, steer, 50, false, rng)
            if gait ~= "halt" then EqTraining.addRiding(sheet, gait, 50) end
            t = t + 50
        end
        return EqTraining.playerEffort(sheet)
    end
    local course = bar(function(_, t) return "canter", "fast", t > 0 and t % 5000 == 0 end)
    local spaced = bar(function(_, t) return "canter", "fast", t > 0 and t % 12000 == 0 end)
    local walked = bar(function() return "walk" end)
    local danced = bar(function(sheet, _, state)
        if sheet.routine.request ~= nil then state.move = sheet.routine.request end
        local move = state.move or "walk"
        if move == "walk" or move == "trot" then state.base = move end
        local gait = (move == "left" or move == "right") and (state.base or "walk") or move
        return gait, move
    end)
    check("a jump course with a clear every 5 s trains agility up to double the old full day", course.agility >= 1.8,
        string.format("got %.2f", course.agility))
    check("jumps too far apart for a combo train agility far less", spaced.agility < course.agility / 3,
        string.format("got %.2f", spaced.agility))
    check("a routine done well trains temperament up to double the old full day", danced.temperament >= 1.8,
        string.format("got %.2f", danced.temperament))
    check("just walking trains temperament at about a quarter of the old day", walked.temperament < 0.3,
        string.format("got %.2f", walked.temperament))
end
do
    local big = ridden("canter", 900000)
    big.focused.agility = 5
    check("agility effort is capped at two full days", EqTraining.playerEffort(big).agility == 2)
end
do
    local function near(a, b) return math.abs(a - b) < 1e-6 end
    do
        local slow, fast, mid = EqTraining.handling(10, 0, 0), EqTraining.handling(100, 100, 100), EqTraining.handling(nil, nil, nil)
        local function near(a, b) return math.abs(a - b) < 0.01 end
        check("speed 10 runs about 10% slower, speed 100 20% faster", near(slow.speed, 0.9) and near(fast.speed, 1.2))
        check("agility raises jump height and turn rate", slow.jump < 1 and fast.jump > 1 and slow.turn < mid.turn and fast.turn > mid.turn and slow.turn >= 1)
        check("temperament quickens gait changes and shortens crash stops",
            slow.acceleration < fast.acceleration and slow.crashHalt > fast.crashHalt)
        check("an unknown horse rides like the base game", near(mid.speed, 1.035) and near(mid.acceleration, 1) and near(mid.crashHalt, 1))
        check("handling stays inside its limits", near(EqTraining.handling(150, -20).speed, 1.2)
            and near(EqTraining.handling(150, -20).jump, 0.8))
    end
    check("a fit horse's riding bar fills more slowly", EqTraining.ridingBarFactor(40) == 1
        and math.abs(EqTraining.ridingBarFactor(100) - 1.4) < 1e-9)
    do
        local timer, total = 0, 0
        for _ = 1, 1000 do
            local points
            points, timer = EqTraining.ridingAdjust(timer, 100, "gallop", 1.5, EqConstants.RIDING_FULL_MS)
            total = total + points
        end
        -- 100 s of gallop is 100 points to the base game; at 1.5x it should be 67.
        check("a fit horse's gallop takes riding points back off", total == -33, string.format("got %d", total))
    end
end

-- EXERTION: the gallop's Pushing, Recovering and Sprinting (EqExertion).
do
    local E = EqExertion
    local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-6) end
    local function ride(ex, gait, ms, stamina, speed)
        local events = {}
        for _ = 1, ms / 50 do
            local event = E.step(ex, gait, 50, stamina, speed)
            if event ~= nil then table.insert(events, event) end
        end
        return events
    end

    local ex = E.new()
    ride(ex, "canter", 2000)
    check("a canter is not a gallop pace and stays empty", ex.mode == nil and ex.value == 0)
    ride(ex, "gallop", 50)
    check("galloping starts Pushing", ex.mode == "push")
    ride(ex, "gallop", 5000)
    local early = E.rate(ex, "gallop", 50)
    ex.value = 80
    check("Pushing tires the horse faster the higher exertion is", E.rate(ex, "gallop", 50) > early * 1.5)
    check("a fitter horse tires more slowly when Pushing", E.rate(ex, "gallop", 90) < E.rate(ex, "gallop", 20))

    local function pushUntilBlown(stamina)
        local p, t = E.new(), 0
        while p.lock == nil and t < 600000 do
            E.step(p, "gallop", 50, stamina)
            t = t + 50
        end
        return t / 1000
    end
    local unfit, average, fit = pushUntilBlown(10), pushUntilBlown(50), pushUntilBlown(90)
    check("Pushing from empty blows an average horse in about a quarter of a minute, a fit one later",
        unfit < average and average < fit and average > 10 and average < 22 and fit < 30,
        string.format("stamina 10 %.0f s, 50 %.0f s, 90 %.0f s", unfit, average, fit))

    local blown = E.new()
    local events = {}
    while blown.lock == nil and #events == 0 do events = ride(blown, "gallop", 50) end
    check("Pushing up to the line blows the horse", events[#events] == "blown" and blown.lock == "blown"
        and blown.value == E.LINE and E.forcedGait(blown) == "canter")
    check("a blown horse can't gallop", not E.allowGait(blown, "canter", "gallop"))
    events = ride(blown, "canter", 5000)
    check("a blown horse's exertion falls fast at a canter", blown.value < 85 and blown.lock == "blown")
    events = ride(blown, "canter", 30000)
    check("once empty it may gallop again", events[#events] == "fresh" and blown.lock == nil and E.allowGait(blown, "canter", "gallop"))
    local walkFall, canterFall = E.new(), E.new()
    walkFall.value, canterFall.value = 50, 50
    ride(walkFall, "walk", 2000)
    ride(canterFall, "canter", 2000)
    check("slower gaits bring exertion down faster", walkFall.value < canterFall.value)

    -- Recovering, and slowing to a canter.
    local r = E.new()
    ride(r, "gallop", 8000)
    check("S while Pushing Recovers", E.press(r, "back") == "recover" and r.mode == "recover")
    check("a single S while Recovering with exertion left keeps the gallop", (function()
        ride(r, "gallop", 1000)
        E.press(r, "back")
        return not E.allowGait(r, "gallop", "canter") and r.mode == "recover"
    end)())
    local before = r.value
    ride(r, "gallop", 3000)
    check("Recovering brings exertion down while still galloping", r.value < before and r.mode == "recover")
    ride(r, "gallop", 120000)
    check("Recovering stops at empty and stays a gallop", r.value == 0 and r.mode == "recover")
    check("one S while Recovering with an empty bar allows a canter", E.press(r, "back") == "canter" and E.allowGait(r, "gallop", "canter"))
    ride(r, "gallop", 1000)
    check("the canter is allowed only just after the press", not E.allowGait(r, "gallop", "canter"))
    local recoverHigh, recoverLow = E.new(), E.new()
    recoverHigh.mode, recoverHigh.value, recoverLow.mode, recoverLow.value = "recover", 90, "recover", 10
    local recoverZone = E.new()
    recoverZone.mode, recoverZone.value = "recover", 50
    check("Recovering is fast in the top and bottom thirds and slow in the middle zone",
        E.band(90) == "high" and E.band(50) == "zone" and E.band(10) == "low"
        and -E.rate(recoverHigh, "gallop") > -E.rate(recoverZone, "gallop") * 2
        and -E.rate(recoverLow, "gallop") > -E.rate(recoverZone, "gallop") * 2)
    local d = E.new()
    ride(d, "gallop", 6000)
    E.press(d, "back")
    ride(d, "gallop", 200)
    check("a quick double tap of S allows a canter from Pushing", E.press(d, "back") == "canter" and E.allowGait(d, "gallop", "canter"))
    ride(d, "canter", 50)
    check("in a canter the gallop's pace is gone", d.mode == nil)
    local slowTaps = E.new()
    ride(slowTaps, "gallop", 6000)
    E.press(slowTaps, "back")
    ride(slowTaps, "gallop", 800)
    check("two slow presses of S are not a double tap", E.press(slowTaps, "back") == "recover" and not E.allowGait(slowTaps, "gallop", "canter"))
    check("W while Recovering pushes on", E.press(slowTaps, "forward") == "push" and slowTaps.mode == "push")

    -- Sprinting.
    local function tap(sp, n, gap)
        local event
        for i = 1, n do
            event = E.press(sp, "forward") or event
            if i < n then ride(sp, "gallop", gap) end
        end
        return event
    end
    local slow = E.new()
    ride(slow, "gallop", 1000)
    check("slow W presses don't Sprint", tap(slow, 4, 600) ~= "sprint" and slow.mode == "push")
    local sp = E.new()
    ride(sp, "gallop", 1000)
    check("three quick taps of W Sprint", tap(sp, 3, 150) == "sprint" and sp.mode == "sprint")
    check("Sprint is the fastest pace, Recovering the slowest", E.speedShare(sp) > 1
        and E.GALLOP_SHARE.recover < E.GALLOP_SHARE.push and E.GALLOP_SHARE.push < E.speedShare(sp))
    events = ride(sp, "gallop", 1000)
    check("a Sprint ends when the tapping stops, into Recovering", events[1] == "sprintOver" and sp.mode == "recover")
    check("no new Sprint until the bar is empty", not E.canSprint(sp) and tap(sp, 3, 150) ~= "sprint" and sp.mode == "push")
    check("but Pushing is fine", sp.mode == "push")
    ride(sp, "canter", 30000)
    ride(sp, "gallop", 100)
    check("an empty bar allows a Sprint again", E.canSprint(sp) and tap(sp, 3, 150) == "sprint")
    local ramp = E.new()
    ramp.mode, ramp.tapAt = "sprint", 0
    local first = E.rate(ramp, "gallop", 50, 50)
    ramp.sprintMs = 6000
    check("a Sprint fills the bar slowly at first, then ever faster", E.rate(ramp, "gallop", 50, 50) > first * 3)
    local pushRate = E.new()
    pushRate.mode, pushRate.value = "push", 40
    check("a Sprint starts no faster than Pushing near the top", first < E.rate(pushRate, "gallop", 50) * 1.5)
    local function sprintFill(gap)
        local f = E.new()
        f.mode, f.value, f.tapAt = "sprint", 40, 0
        local t = 0
        while f.value < E.LINE and t < 60000 do
            E.press(f, "forward")
            ride(f, "gallop", gap)
            t = t + gap
        end
        return t / 1000
    end
    local quickFill, slowFill = sprintFill(150), sprintFill(450)
    print(string.format("info: Sprint from 40%% to the line: quick taps %.1f s, slow taps %.1f s", quickFill, slowFill))
    check("a Sprint from 40% reaches the line in a few seconds, sooner with slow taps",
        slowFill < quickFill and quickFill < 9 and slowFill > 2.5, string.format("quick taps %.1f s, slow taps %.1f s", quickFill, slowFill))
    local function sprintRise(gap, after)
        local s2 = E.new()
        ride(s2, "gallop", 100)
        tap(s2, 3, 100)
        local t = 0
        while t < after do
            s2.value = 0
            ride(s2, "gallop", gap)
            E.press(s2, "forward")
            t = t + gap
        end
        return E.rate(s2, "gallop", 50, 50)
    end
    check("quick taps slow the Sprint's rise", sprintRise(150, 1000) < sprintRise(400, 1000) * 0.7)
    check("but only for so long", near(sprintRise(150, 11000), sprintRise(400, 11000), 1e-9))
    check("a faster horse tires more slowly when Sprinting", (function()
        local a, b = E.new(), E.new()
        a.mode, b.mode = "sprint", "sprint"
        return E.rate(a, "gallop", 50, 90) < E.rate(b, "gallop", 50, 10)
    end)())

    local last = E.new()
    last.mode, last.value = "push", 95
    E.press(last, "forward")
    ride(last, "gallop", 100)
    E.press(last, "forward")
    ride(last, "gallop", 100)
    E.press(last, "forward")
    for _ = 1, 30 do
        ride(last, "gallop", 100)
        E.press(last, "forward")
    end
    check("a Sprint goes past the Fatigued line without blowing", last.mode == "sprint" and last.value > E.LINE and last.lock == nil)
    check("the marker runs on into the Fatigued section", E.marker(last, "gallop") > E.BAR.line)
    events = ride(last, "gallop", 1000)
    check("a Sprint that ends past the line leaves the horse exhausted", events[1] == "spent" and last.lock == "spent"
        and E.forcedGait(last) == "canter")
    local fresh = E.new()
    fresh.lock, fresh.value = "blown", last.value
    check("an exhausted horse recovers much more slowly while past the line", -E.rate(last, "canter") < -E.rate(fresh, "canter") * 0.3)
    check("slower gaits still help an exhausted horse", -E.rate(last, "trot") > -E.rate(last, "canter"))
    local under = E.new()
    under.lock, under.value = "spent", 60
    check("once back under the line it recovers at the normal rate", near(E.rate(under, "canter"), E.rate(fresh, "canter")))
    local recovering = E.new()
    recovering.mode, recovering.value = "recover", 60
    check("dropping to a canter brings the bar down much faster than Recovering", -E.rate(fresh, "canter") > -E.rate(recovering, "gallop") * 2)
    local gasp = E.new()
    gasp.mode, gasp.value, gasp.tapAt = "sprint", E.EXERTION_MAX - 0.01, 0
    events = ride(gasp, "gallop", 50)
    check("the last gasp ends at the end of the bar", events[1] == "spent" and gasp.lock == "spent")
    local dropOut = E.new()
    dropOut.mode, dropOut.value, dropOut.tapAt = "sprint", 110, 0
    E.press(dropOut, "back")
    check("easing off a Sprint past the line exhausts the horse too", dropOut.lock == "spent")

    -- The bar.
    local m = E.new()
    check("an empty bar sits on the gait's line", E.marker(m, "walk") == E.BAR.walk and E.marker(m, "canter") == E.BAR.canter
        and E.marker(m, "gallop") == E.BAR.canter and E.marker(m, "reverse") == 0)
    m.value = 50
    check("exertion runs along the gallop section", near(E.marker(m, "walk"), (E.BAR.canter + E.BAR.line) / 2))
    m.value = E.LINE
    check("the Fatigued line is the end of the gallop section", near(E.marker(m, "gallop"), E.BAR.line))
    check("the state names the pace, the lock or the gait", E.state(E.new(), "trot") == "trot" and E.state(blown, "canter") ~= nil
        and E.state(sp, "gallop") == "sprint")

    -- A rider who pushes, eases off before the line and pushes again keeps a fast average for
    -- five minutes without blowing; one who only pushes blows.
    local function gallopFor(policy, stamina)
        local g, t, share, blownAt = E.new(), 0, 0, nil
        E.step(g, "gallop", 50, stamina)
        while t < 300000 do
            local key = policy(g)
            if key ~= nil then E.press(g, key) end
            local gait = g.lock ~= nil and "canter" or "gallop"
            if E.step(g, gait, 50, stamina) == "blown" and blownAt == nil then blownAt = t end
            share = share + (g.lock ~= nil and 0.5 or E.speedShare(g)) * 50
            t = t + 50
        end
        return share / t, blownAt
    end
    local skilled, skilledBlown = gallopFor(function(g)
        if g.mode == "push" and g.value >= 90 then return "back" end
        if g.mode == "recover" and g.value <= 50 then return "forward" end
    end, 50)
    local reckless, recklessBlown = gallopFor(function() return nil end, 50)
    check("pushing and recovering in turn never blows and keeps up the pace", skilledBlown == nil and skilled > 0.83,
        string.format("average %.2f of the gallop", skilled))
    check("pushing flat out blows, and is slower in the end", recklessBlown ~= nil and reckless < skilled,
        string.format("average %.2f, blown at %s ms", reckless, tostring(recklessBlown)))
    print(string.format("info: five minutes at a gallop: push 90/recover 50 %.2f of top speed, flat out %.2f", skilled, reckless))

    local resting = E.new()
    resting.value, resting.mode = 60, "push"
    E.rest(resting, 60000)
    check("time out of the saddle rests the horse", resting.value == 0 and resting.mode == nil)
end

-- GALLOP TRAINING: speed banked from Sprints, stamina at a live multiplier (EqTraining).
do
    local E, T = EqExertion, EqTraining
    check("a Sprint's speed multiplier is 2x half way to the line and nearly 10x at it",
        math.abs(T.sprintMultiplier(50) - 2) < 1e-6 and T.sprintMultiplier(99.9) > 9.9 and T.sprintMultiplier(20) < 1.3)
    check("a Sprint that ends at or past the line is worth only 1x", T.sprintMultiplier(E.LINE) == 1 and T.sprintMultiplier(80, true) == 1)

    -- Gallop under a policy (rider's key for the frame, from the sheet), returning the sheet.
    local function gallop(policy, ms, worn)
        local sheet = T.newSheet()
        local ex = sheet.exertion
        local banked, blown, multMs = {}, false, 0
        for _ = 1, ms / 50 do
            local key = policy(ex, sheet)
            if key == "sprint" then
                for _ = 1, E.SPRINT_TAPS do E.press(ex, "forward") end
            elseif key ~= nil then
                E.press(ex, key)
            end
            if ex.mode == "sprint" and ex.clock - ex.tapAt > 150 then E.press(ex, "forward") end
            local gait = ex.lock ~= nil and "canter" or "gallop"
            if E.step(ex, gait, 50) == "blown" then blown = true end
            local mult = T.speedStep(sheet, 50, worn)
            if mult ~= nil then table.insert(banked, mult) end
            T.staminaStep(sheet, 50, worn)
            multMs = multMs + sheet.stamina.mult * 50
        end
        sheet.banked, sheet.blown, sheet.averageMult = banked, blown, multMs / ms
        return sheet
    end
    local function sprintTo(stop)
        return function(ex)
            if ex.mode == "push" and E.canSprint(ex) then return "sprint" end
            if ex.mode == "sprint" and ex.value >= stop then return "back" end
        end
    end
    local high, half = gallop(sprintTo(95), 20000), gallop(sprintTo(50), 20000)
    check("a Sprint banks speed when it ends, more for one taken higher",
        #high.banked >= 1 and high.banked[1] > 7 and #half.banked >= 1 and half.banked[1] < 2.5
        and high.focused.speed > half.focused.speed * 3,
        string.format("x%.1f %.3f vs x%.1f %.3f", high.banked[1] or 0, high.focused.speed, half.banked[1] or 0, half.focused.speed))
    local over = gallop(sprintTo(115), 20000)
    check("a Sprint past the line banks only 1x", over.banked[1] == 1 and over.exertion.lock == "spent")
    local tooTired = gallop(sprintTo(95), 20000, true)
    check("a worn-out horse's Sprints bank nothing", tooTired.focused.speed == 0)
    local dropped = T.newSheet()
    dropped.exertion.mode, dropped.exertion.value, dropped.exertion.tapAt = "sprint", 70, 0
    T.speedStep(dropped, 3000, false)
    check("dropping out of a Sprint to a canter ends and banks it",
        E.step(dropped.exertion, "canter", 50) == "sprintOver" and T.speedStep(dropped, 50, false) ~= nil and dropped.focused.speed > 0)

    -- Stamina: push near the top, recover into the zone and wait there, push again.
    local skilled = gallop(function(ex)
        if ex.mode == "push" and ex.value >= 92 then return "back" end
        if ex.mode == "recover" and ex.value <= 45 then return "forward" end
    end, 150000)
    local jiggler = gallop(function(ex)
        if ex.mode == "push" and ex.value >= 95 then return "back" end
        if ex.mode == "recover" and ex.value <= 85 then return "forward" end
    end, 150000)
    local lazy = gallop(function(ex)
        if ex.mode == "push" and ex.value >= 92 then return "back" end
        if ex.mode == "recover" and ex.value <= 3 then return "forward" end
    end, 150000)
    local flatOut = gallop(function() return nil end, 150000)
    check("riding in the zone builds the stamina multiplier towards x5 without Fatigued",
        not skilled.blown and skilled.stamina.mult > 2.5 and skilled.averageMult > 3,
        string.format("x%.1f now, x%.2f average", skilled.stamina.mult, skilled.averageMult))
    check("bouncing between Push and Recover near the top earns little multiplier",
        jiggler.averageMult < skilled.averageMult * 0.6, string.format("x%.2f average", jiggler.averageMult))
    check("recovering too far loses the multiplier", lazy.averageMult < skilled.averageMult * 0.75,
        string.format("x%.2f average", lazy.averageMult))
    check("Fatigued drops the multiplier to x1 and stops stamina training",
        flatOut.blown and flatOut.focused.stamina < skilled.focused.stamina * 0.6)
    check("good stamina riding fills most of a day's effort in a riding bar of gallop",
        skilled.focused.stamina > 1.2, string.format("%.2f in 150 s", skilled.focused.stamina))
    local blownSheet = T.newSheet()
    blownSheet.exertion.lock, blownSheet.exertion.value, blownSheet.stamina.mult = "blown", 60, 4
    T.staminaStep(blownSheet, 1000, false)
    check("while Fatigued there is no multiplier and no stamina training",
        blownSheet.stamina.mult == 1 and blownSheet.focused.stamina == 0)
    print(string.format("info: stamina over 150 s: zone x%.2f avg (%.2f effort), jiggle x%.2f, over-recover x%.2f, flat out %.2f effort; speed Sprint to 95%% x%.1f %.3f",
        skilled.averageMult, skilled.focused.stamina, jiggler.averageMult, lazy.averageMult, flatOut.focused.stamina,
        high.banked[1] or 0, high.focused.speed))
    do
        -- Riding that earns nothing costs a quarter of the bar; steady focused work the full rate.
        local easy = EqTraining.newSheet()
        local share
        for _ = 1, 600 do share = EqTraining.workStep(easy, 100) end
        check("an easy ride costs a quarter of the riding bar", math.abs(share - EqTraining.CRUISE_BAR_SHARE) < 1e-9)
        local busy = EqTraining.newSheet()
        for _ = 1, 600 do
            busy.focused.stamina = busy.focused.stamina + 0.015 * 0.1
            share = EqTraining.workStep(busy, 100)
        end
        check("good focused work costs the full riding bar", math.abs(share - 1) < 1e-6, string.format("got %.3f", share))
        -- Two clear jumps keep it above the easy rate for a while, then it fades.
        local jumps = EqTraining.newSheet()
        EqTraining.workStep(jumps, 100)
        EqTraining.clearJump(jumps, false)
        EqTraining.clearJump(jumps, false)
        local after = EqTraining.workStep(jumps, 100)
        for _ = 1, 1200 do share = EqTraining.workStep(jumps, 100) end
        check("jumps lift the riding cost, then it fades", after > 0.3 and share < 0.26,
            string.format("after %.3f, later %.3f", after, share))
        local sheet = EqTraining.newSheet()
        EqTraining.addRiding(sheet, "canter", 1000, 0.25)
        check("easy riding counts less towards the player's share", sheet.ms.canter == 250)
    end
end

local racingStaff = EqTraining.staffEffort(100, 0, "racing", false)
check("staff train to the focus, at half its profile", racingStaff.speed == 0.5 and racingStaff.agility < 0.1)
check("riding the player did is not credited to staff", EqTraining.staffEffort(100, 100, "racing", false).speed == 0)
check("grooming adds temperament", EqTraining.staffEffort(0, 0, "balanced", true).temperament > 0)

-- Staff alone stop at 95% of the ceiling; the player's riding takes it the rest of the way.
local staffHorse = horse("showJumping", 10)
for _ = 1, 400 do
    EqTraining.applyDay(staffHorse, cap70, { riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 })
end
check("staff stop at 95% of the ceiling", staffHorse.trained.agility <= 70 * 0.95 + 1e-6 and staffHorse.trained.agility > 66,
    string.format("got %.2f", staffHorse.trained.agility))
for _ = 1, 400 do
    local sheet = ridden("canter", 100000)
    sheet.focused.agility = 1
    EqTraining.applyDay(staffHorse, cap70, { sheet = sheet, riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 })
end
check("the player's riding reaches the ceiling", staffHorse.trained.agility > 69.5, string.format("got %.2f", staffHorse.trained.agility))

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
    check("a green two-year-old gets a high training benefit", greenBand == "high")
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
check("a round draws 3 to 8 events by default", rounds / 200 >= 3 and rounds / 200 <= 8, string.format("%.1f per round", rounds / 200))
check("some rounds have no dressage at all", empty > 0 and empty < 100, empty .. " of 200")
print(string.format("info: %.1f round events and %.1f monthly events per draw; dressage missing in %d of 200 rounds",
    rounds / 200, monthly / 200, empty))

do
    local sizes, outside, enterableShort, monthlyCounts = {}, 0, 0, {}
    local onlyNovice = function(_, tierName) return tierName == "novice" end
    for round = 1, 300 do
        local count = EqCompetition.drawCount(EqRandom.new("count " .. round), 3, 8)
        sizes[count] = (sizes[count] or 0) + 1
        if count < 3 or count > 8 then outside = outside + 1 end
        local events = EqCompetition.drawSchedule(config, EqRandom.new("enter " .. round), EqCompetition.KIND_ROUND, true, nil,
            { count = count, enterable = onlyNovice })
        local novices = 0
        for _, event in ipairs(events) do if event.tier == "novice" then novices = novices + 1 end end
        if novices < math.ceil(#events / 2) then enterableShort = enterableShort + 1 end
        local monthly = #EqCompetition.drawSchedule(config, EqRandom.new("monthly " .. round), EqCompetition.KIND_MONTH, true)
        monthlyCounts[monthly] = (monthlyCounts[monthly] or 0) + 1
    end
    local spread = 0
    for _ in pairs(sizes) do spread = spread + 1 end
    check("event counts stay in the range", outside == 0)
    check("event counts vary across the whole range", spread == 6, spread .. " sizes")
    check("at least half of a draw is enterable", enterableShort == 0, enterableShort .. " short draws")
    check("monthly draws hold 1 or 2 events", (monthlyCounts[1] or 0) > 0 and (monthlyCounts[2] or 0) > 0
        and (monthlyCounts[1] or 0) + (monthlyCounts[2] or 0) == 300)
    local noTraining, trainingShort = 0, 0
    for round = 1, 300 do
        local count = EqCompetition.drawCount(EqRandom.new("count " .. round), 1, 8)
        local enterable = round % 2 == 0 and onlyNovice or nil
        local trainings = 0
        for _, event in ipairs(EqCompetition.drawSchedule(config, EqRandom.new("training " .. round), EqCompetition.KIND_ROUND,
            round % 3 ~= 0, nil, { count = count, enterable = enterable })) do
            if event.tier == "training" then trainings = trainings + 1 end
        end
        if trainings == 0 then noTraining = noTraining + 1 end
        if enterable ~= nil and count >= 3 and trainings == 0 then trainingShort = trainingShort + 1 end
    end
    check("every round draw holds a Training Event", noTraining == 0, noTraining .. " draws without one")
    check("the Training Event fits beside the enterable half", trainingShort == 0)
    local none = EqCompetition.drawSchedule(config, EqRandom.new("nobody"), EqCompetition.KIND_ROUND, true, nil,
        { count = 5, enterable = function() return false end })
    check("a draw still fills when no horse can enter anything", #none == 5)
end

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
check("eventing alone makes an eventer", specialtyOf({ eventing = 60, raceShort = 20 }) == "eventer")
check("eventing with a phase makes an eventer", specialtyOf({ eventing = 60, dressage = 55 }) == "eventer")
check("cross country alone stays itself", specialtyOf({ crossCountry = 60 }) == "one")
check("eventing beside a race is a pair", specialtyOf({ eventing = 60, raceLong = 55 }) == "pair")
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

-- Show jumping courses recorded by riding through the jumps (EqCourse).
;(function()
    local rec = EqCourse.newRecording(0, 0, 0)
    -- A straight: points every POINT_SPACING[1] metres after the first.
    for z = 0.5, 40, 0.5 do EqCourse.recordStep(rec, 0, 0, z) end
    check("a straight drops few points", #rec.points >= 4 and #rec.points <= 7, tostring(#rec.points))
    local straight = #rec.points
    -- A tight circle (radius 4 m) drops far more per metre.
    for i = 1, 60 do
        local a = i / 60 * math.pi * 2
        EqCourse.recordStep(rec, 4 - 4 * math.cos(a), 0, 40 + 4 * math.sin(a))
    end
    check("a tight turn drops many points", #rec.points - straight >= 12, tostring(#rec.points - straight))
    check("course length follows the path", rec.length > 60 and rec.length < 70, string.format("%.1f", rec.length))

    -- A jump from (-2, 0) to (2, 0).
    check("crossing a jump between its ends passes it", EqCourse.crossSide(-2, 0, 2, 0, 0, 1, 0.2, -0.5) ~= nil)
    check("crossing the other way is the other side",
        EqCourse.crossSide(-2, 0, 2, 0, 1, -1, 1, 0.5) == -EqCourse.crossSide(-2, 0, 2, 0, 0, 1, 0.2, -0.5))
    check("going round the end of a jump is no pass", EqCourse.crossSide(-2, 0, 2, 0, 4, 1, 4, -1) == nil)
    check("just past an end still counts", EqCourse.crossSide(-2, 0, 2, 0, 2.5, 1, 2.5, -1) ~= nil)
    check("staying on one side is no pass", EqCourse.crossSide(-2, 0, 2, 0, 0, 1, 0, 0.2) == nil)
    check("a jump far away in one frame is no pass", EqCourse.crossSide(-2, 0, 2, 0, 0, 5, 0, -5) == nil)
    check("a jump at an angle works too", EqCourse.crossSide(0, 0, 3, 3, 2, 0, 0, 2) ~= nil)

    local jumpA, jumpB = { x = 10, z = 10, ry = 0 }, { x = 30, z = 10, ry = 1.57 }
    check("first fence is number 1", EqCourse.addJump(rec, jumpA, 1, 1000) == 1)
    check("wobbling back over it counts once", EqCourse.addJump(rec, jumpA, -1, 2000) == nil)
    check("too few fences are not saved", select(2, EqCourse.finish(rec, "Course 1")) == "jumps")
    check("second fence is number 2", EqCourse.addJump(rec, jumpB, 1, 3000) == 2)
    check("the same fence later in the course counts again", EqCourse.addJump(rec, jumpA, 1, 20000) == 3)
    EqCourse.reset()
    local course = EqCourse.finish(rec, EqCourse.nextName())
    check("a course with fences is saved", course ~= nil and #course.jumps == 3 and course.name == "Course 1")
    EqCourse.add(course)
    check("names don't repeat", EqCourse.nextName() == "Course 2")
    check("nearest finds a course close by", EqCourse.nearest(1, 20, 10) == course)
    check("nearest ignores a course far away", EqCourse.nearest(500, 500, 40) == nil)
    local line = EqCourse.smooth(course.points)
    check("the drawn line runs through the ends", #line > #course.points
        and math.abs(line[1].z - course.points[1].z) < 1e-6 and math.abs(line[#line].z - course.points[#course.points].z) < 1e-6)

    -- Rewind: back to the nearest point, dropping later points and fences.
    local again = EqCourse.newRecording(0, 0, 0)
    for z = 1, 30 do EqCourse.recordStep(again, 0, 0, z) end
    EqCourse.addJump(again, jumpA, 1, 1000)
    EqCourse.recordStep(again, 0, 0, 31, true)
    for z = 32, 60 do EqCourse.recordStep(again, 0, 0, z) end
    EqCourse.addJump(again, jumpB, 1, 9000)
    EqCourse.recordStep(again, 0, 0, 61, true)
    local index, away = EqCourse.nearestPoint(again, 2, 40)
    check("nearest point is found", math.abs(again.points[index].z - 40) <= 5 and away < 6)
    EqCourse.rewind(again, index)
    check("rewind drops later points", again.points[#again.points].z <= 45 and #again.jumps == 1)
    check("rewind keeps the length right", math.abs(again.length - EqCourse.pathLength(again.points)) < 1e-6)
    local before = #again.points
    EqCourse.recordStep(again, 3, 0, again.points[#again.points].z + 1)
    check("no point right after a rewind, even on a turn", #again.points == before)
    EqCourse.recordStep(again, 6, 0, again.points[#again.points].z + 2)
    check("the first point after a rewind comes a few metres on", #again.points == before + 1)
    local labels = EqCourse.labels({ { x = 1, z = 1 }, { x = 9, z = 9 }, { x = 1, z = 1 } })
    check("a jump ridden twice gets one label", #labels == 2 and labels[1].text == "1, 3" and labels[2].text == "2")
    EqCourse.rewind(again, 1)
    check("rewind to the start drops every fence", #again.points == 1 and #again.jumps == 0 and again.length == 0)

    local store = memoryXML()
    EqCourse.saveToXMLFile(store, "c")
    EqCourse.loadFromXMLFile(store, "c")
    local back = EqCourse.list[1]
    check("a course survives a save", #EqCourse.list == 1 and back.name == "Course 1" and #back.jumps == 3
        and #back.points == #course.points and math.abs(back.length - course.length) < 1 and back.jumps[2].side == 1
        and math.abs(back.jumps[2].ry - 1.57) < 0.01)
    check("fence points survive a save", back.jumps[1].pointIndex ~= nil and back.jumps[1].pointIndex == course.jumps[1].pointIndex)
    local edit = EqCourse.editRecording(back)
    check("editing starts from the saved course", #edit.points == #back.points and #edit.jumps == 3 and edit.rewound)
    edit.points[1].x = 999
    check("editing does not change the saved course until saved", back.points[1].x ~= 999)
    EqCourse.replace(1, EqCourse.finish(edit, back.name))
    check("a saved edit replaces the course", #EqCourse.list == 1 and EqCourse.list[1].points[1].x == 999)
    EqCourse.loadFromXMLFile(nil, "c")
    check("a new game has no courses", #EqCourse.list == 0)
end)()

-- Peak form: the month's best minigame session per stat, never stacked over days.
;(function()
    local sheet = EqTraining.newSheet()
    sheet.month = 4
    sheet.ms.gallop = 600000
    check("plain gait riding gives no peak form", not EqTraining.hasForm(EqTraining.formFrom(sheet)))
    sheet.focused.speed = EqTraining.FORM_FULL
    sheet.focused.agility = EqTraining.FORM_FULL / 2
    sheet.focused.stamina = EqTraining.FORM_FULL * 3
    local points = EqTraining.formFrom(sheet)
    check("a strong session gives full form", math.abs(points.speed - EqTraining.FORM_MAX) < 1e-9)
    check("half a session gives half", math.abs(points.agility - EqTraining.FORM_MAX / 2) < 1e-9)
    check("form never passes FORM_MAX", math.abs(points.stamina - EqTraining.FORM_MAX) < 1e-9)

    local form = EqTraining.mergeForm(nil, 4, points)
    local weaker = EqTraining.newSheet()
    weaker.month = 4
    weaker.focused.speed = EqTraining.FORM_FULL / 4
    weaker.focused.temperament = EqTraining.FORM_FULL
    form = EqTraining.mergeForm(form, 4, EqTraining.formFrom(weaker))
    check("a second day keeps each stat's best, not the sum", math.abs(form.speed - EqTraining.FORM_MAX) < 1e-9
        and math.abs(form.temperament - EqTraining.FORM_MAX) < 1e-9 and math.abs(form.agility - EqTraining.FORM_MAX / 2) < 1e-9)
    local again = EqTraining.mergeForm(form, 4, EqTraining.formFrom(sheet))
    check("riding the same session again adds nothing", math.abs(again.speed - EqTraining.FORM_MAX) < 1e-9)
    check("a new month starts afresh", EqTraining.mergeForm(form, 5, {}).speed == 0)
    check("an older month's session can't replace a newer form", EqTraining.mergeForm(form, 3, { speed = 1 }) == form)

    check("form counts in its own month", math.abs(EqTraining.formFor(form, 4).speed - EqTraining.FORM_MAX) < 1e-9)
    check("form is gone the next month", not EqTraining.hasForm(EqTraining.formFor(form, 5)))
    local today = EqTraining.newSheet()
    today.month = 5
    today.focused.agility = EqTraining.FORM_FULL
    local live = EqTraining.formFor(form, 5, today)
    check("today's riding counts before the day is applied", math.abs(live.agility - EqTraining.FORM_MAX) < 1e-9 and live.speed == 0)
    check("a sheet from another month doesn't count", not EqTraining.hasForm(EqTraining.formFor(nil, 6, today)))

    local stats = EqTraining.withForm({ stamina = 50, speed = 96, agility = 30, temperament = 0 }, { speed = 8, agility = 4 })
    check("form adds to the stats, capped at 100", stats.speed == 100 and stats.agility == 34 and stats.stamina == 50)

    local horse = EqHorseRecord.new("DE 1 9")
    horse.form = form
    local x = memoryXML()
    horse:saveToXMLFile(x, "h")
    local back = EqHorseRecord.loadFromXMLFile(x, "h")
    check("peak form survives a save", back.form ~= nil and back.form.month == 4
        and math.abs(back.form.speed - form.speed) < 1e-6 and math.abs(back.form.agility - form.agility) < 1e-6)
    check("an old save loads with no form", EqHorseRecord.loadFromXMLFile((function()
        local y = memoryXML(); EqHorseRecord.new("DE 1 10"):saveToXMLFile(y, "h"); return y end)(), "h").form == nil)
end)()

-- Event results: checks, the story lines, rivals and the results kept on a horse.
;(function()
    local sj = config.disciplineByName.showJumping
    check("show jumping has its checks", #sj.checks == 6 and sj.story == "jumping" and sj.checks[6].tag == "hardest")
    check("dressage only ends early with a refusal", config.disciplineByName.dressage.refusalsOnly
        and EqPerformance.storyKey(config.disciplineByName.dressage, { checks = {} }, true, config) == "eq_story_dressage_elimRefusal")
    check("eventing is only ended by a fall, never a refusal",
        EqPerformance.storyKey(config.disciplineByName.eventing, { phases = { { checks = { { check = { stat = "temperament", weight = 1, difficulty = 0 }, passed = false } } } } },
            true, config) == "eq_story_eventing_eliminated")
    local race = config.disciplineByName.raceShort
    local function raceRun(passes)
        local checks = {}
        for i, c in ipairs(race.checks) do checks[i] = { check = c, passed = passes[i] } end
        return { checks = checks }
    end
    local behind = raceRun({ true, false, false, true })
    check("a placed horse that fell behind and won the sprint gets the comeback line",
        EqPerformance.storyKey(race, behind, false, config, 2) == "eq_story_race_comeback")
    check("no comeback off the podium", EqPerformance.storyKey(race, behind, false, config, 4) ~= "eq_story_race_comeback")
    check("no comeback without an early miss", EqPerformance.storyKey(race, raceRun({ true, true, true, true }), false, config, 1) == "eq_story_race_clean")
    check("no comeback when the sprint was lost", EqPerformance.storyKey(race, raceRun({ true, false, true, false }), false, config, 3) == "eq_story_race_finish")
    check("eventing runs three phases", #config.disciplineByName.eventing.phases == 3
        and config.disciplineByName.eventing.phases[1] == "dressage")
    for _, d in ipairs(config.disciplines) do
        check(d.name .. " has checks or phases", #d.checks > 0 or d.phases ~= nil)
    end

    local novice = config.tierByName.novice
    check("a check at difficulty 0 is below the weakest rival", EqPerformance.target(novice, 0) < novice.rivalMin
        and EqPerformance.target(novice, 1) < novice.rivalMax)
    check("an even match passes half the time", math.abs(EqPerformance.passChance(50, 50) - 0.5) < 1e-9)
    check("a better horse passes more", EqPerformance.passChance(60, 50) > 0.75 and EqPerformance.passChance(40, 50) < 0.25)

    local function c(stat, difficulty, weight, tag) return { stat = stat, difficulty = difficulty, weight = weight, tag = tag } end
    local course = { c("agility", 0.1, 1), c("speed", 0, 1), c("agility", 0.5, 1.5), c("temperament", 0.4, 2), c("agility", 1, 2.5, "hardest") }
    local function results(passes)
        local list = {}
        for i, check in ipairs(course) do list[i] = { check = check, passed = passes[i] } end
        return list
    end
    check("a clean run", EqPerformance.issue(results({ true, true, true, true, true })) == "clean")
    check("only the hardest fence down", EqPerformance.issue(results({ true, true, true, true, false })) == "hardest")
    check("the hardest and another fence down: several", EqPerformance.issue(results({ false, true, true, true, false })) == "agilityMany")
    check("a refusal is the biggest problem when it weighs most", EqPerformance.issue(results({ true, true, false, false, true })) == "temperament")
    check("slow round", EqPerformance.issue(results({ true, false, true, true, true })) == "speed")
    check("failing most of it is a struggle", EqPerformance.issue(results({ false, true, false, false, false })) == "struggled")
    check("eliminated with a failed temperament check is a refusal",
        EqPerformance.eliminationIssue(results({ true, true, true, false, true })) == "elimRefusal"
        and EqPerformance.eliminationIssue(results({ true, true, true, true, false })) == "eliminated")

    -- The start check: a layup unless the horse is very fractious.
    local function startRate(temperament)
        local started = 0
        for i = 1, 2000 do
            if EqPerformance.startCheck({ temperament = temperament }, 0.9, EqRandom.new("start " .. i)) then started = started + 1 end
        end
        return started / 2000
    end
    local calm, green, wild = startRate(45), startRate(20), startRate(5)
    print(string.format("info: start check pass rate at temperament 45: %.3f, 20: %.3f, 5: %.3f", calm, green, wild))
    check("an ordinary horse almost always starts", calm > 0.998)
    check("a green horse usually starts", green > 0.85 and green < 0.99)
    check("a very fractious horse often doesn't", wild < 0.5)
    local en0 = io.open("translations/translation_en.xml"):read("*a")
    local de0 = io.open("translations/translation_de.xml"):read("*a")
    for n = 1, EqPerformance.START_FAIL_TEXTS do
        local key = 'name="eq_scratch_fractious_' .. n .. '"'
        check("start scratch text " .. n, en0:find(key, 1, true) ~= nil and de0:find(key, 1, true) ~= nil)
    end

    -- How often each line comes up for a horse in its band, and that the checks match the placing.
    local event = { discipline = "showJumping", tier = "novice", prize = 2000 }
    local stats = { stamina = 45, speed = 45, agility = 45, temperament = 45 }
    local issues, cleanPlace, struggledPlace, cleanRuns, struggledRuns = {}, 0, 0, 0, 0
    for i = 1, 1000 do
        for _, r in ipairs(EqCompetition.run(event, config, { { key = "me", rating = 45, condition = 0.95, stats = stats } }, EqRandom.new("story " .. i))) do
            if r.key == "me" then
                local issue = EqPerformance.issue(r.run.checks)
                issues[issue] = (issues[issue] or 0) + 1
                if issue == "clean" then cleanPlace, cleanRuns = cleanPlace + r.place, cleanRuns + 1 end
                if issue == "struggled" then struggledPlace, struggledRuns = struggledPlace + r.place, struggledRuns + 1 end
            end
        end
    end
    local parts = {}
    for issue, count in pairs(issues) do table.insert(parts, issue .. " " .. count) end
    table.sort(parts)
    print("info: Novice show jumping lines for a mid-band horse (of 1000): " .. table.concat(parts, ", "))
    check("a mid-band horse gets a mix of lines", (issues.clean or 0) > 50 and (issues.hardest or 0) > 30 and (issues.struggled or 0) > 10
        and (issues.temperament or 0) > 20, table.concat(parts, ", "))
    check("clear rounds place better than struggles", cleanRuns > 0 and struggledRuns > 0
        and cleanPlace / cleanRuns + 2 < struggledPlace / struggledRuns,
        string.format("%.1f vs %.1f", cleanPlace / math.max(cleanRuns, 1), struggledPlace / math.max(struggledRuns, 1)))

    -- Eventing: placed per phase, and the phases keep the eventing rating's expectation.
    local scaled = EqPerformance.scalePhases({ dressage = 70, showJumping = 50, crossCountry = 30 }, 45)
    check("phase ratings average the event rating", math.abs((scaled.dressage + scaled.showJumping + scaled.crossCountry) / 3 - 45) < 1e-9
        and scaled.dressage > scaled.crossCountry)
    local eventing = { discipline = "eventing", tier = "intermediate", going = "good", prize = 5000 }
    local ran = EqCompetition.run(eventing, config, { { key = "me", rating = 60, condition = 1, stats = stats, phaseRatings = scaled } }, EqRandom.new("eventing"))
    local mine
    for _, r in ipairs(ran) do if r.key == "me" then mine = r end end
    check("eventing places every runner in every phase", mine.phasePlaces ~= nil and mine.phasePlaces.dressage ~= nil
        and mine.phasePlaces.crossCountry ~= nil and #mine.run.phases == 3)

    -- Every line a run can produce has its text, in English and German.
    local en = io.open("translations/translation_en.xml"):read("*a")
    local de = io.open("translations/translation_de.xml"):read("*a")
    local seen = {}
    for _, d in ipairs(config.disciplines) do
        for _, key in ipairs(EqPerformance.storyKeys(d, config)) do
            if not seen[key] then
                seen[key] = true
                check("story text " .. key, en:find('name="' .. key .. '"', 1, true) ~= nil and de:find('name="' .. key .. '"', 1, true) ~= nil)
            end
        end
    end
    for i = 1, 300 do
        local d = config.disciplines[(i % #config.disciplines) + 1]
        local r = EqPerformance.run(d, config, config.tierByName.intermediate, { rating = 30 + i % 50, condition = 0.9 },
            EqCompetition.LUCK_SD, EqRandom.new("keys " .. i))
        for _, eliminated in ipairs({ false, true }) do
            local key = EqPerformance.storyKey(d, r, eliminated, config)
            if not seen[key] then
                seen[key] = true
                check("rolled story text " .. key, en:find('name="' .. key .. '"', 1, true) ~= nil)
            end
        end
    end

    -- Rivals: the same save draws the same horses; the best name the top events.
    local rivals = EqRivals.generate(42, config.disciplines)
    local again = EqRivals.generate(42, config.disciplines)
    check("fifty rivals", #rivals == EqRivals.RIVAL_COUNT)
    check("a save's rivals are the same every load", rivals[1].name == again[1].name and rivals[50].levels.dressage == again[50].levels.dressage)
    check("another save gets other rivals", EqRivals.generate(7, config.disciplines)[1].name ~= rivals[1].name
        or EqRivals.generate(7, config.disciplines)[1].levels.dressage ~= rivals[1].levels.dressage)
    local names = {}
    for _, rival in ipairs(rivals) do names[rival.name] = true end
    local unique = 0
    for _ in pairs(names) do unique = unique + 1 end
    check("rival names are unique", unique == #rivals)
    local used, pickRng = {}, EqRandom.new("pick")
    local top = EqRivals.pick(rivals, "showJumping", 95, used, pickRng)
    local second = EqRivals.pick(rivals, "showJumping", 95, used, pickRng)
    check("a name is used once per event", top ~= nil and second ~= nil and top ~= second)
    local function levelOf(name)
        for _, rival in ipairs(rivals) do if rival.name == name then return rival.levels.showJumping end end
    end
    check("the picked rival is near the rating", math.abs(levelOf(EqRivals.pick(rivals, "showJumping", 40, {}, pickRng)) - 40)
        <= EqRivals.MATCH_RANGE)
    check("championship and novice podiums name different horses",
        EqRivals.pick(rivals, "showJumping", 92, {}, pickRng) ~= EqRivals.pick(rivals, "showJumping", 40, {}, pickRng))
    -- Over many Advanced show jumping podiums, a handful of names do most of the winning.
    local winners, distinct = {}, 0
    for i = 1, 200 do
        local name = EqRivals.pick(rivals, "showJumping", 80 + (i % 9), {}, EqRandom.new("winner " .. i))
        if winners[name] == nil then distinct = distinct + 1 end
        winners[name] = (winners[name] or 0) + 1
    end
    check("the same names keep turning up, but not just one", distinct >= 3 and distinct <= 20, distinct .. " winners")

    -- Story lines, with a stand-in for the game's texts.
    local savedI18n = g_i18n
    local texts = {
        eq_ord_1 = "%dst", eq_ord_2 = "%dnd", eq_ord_3 = "%drd", eq_ord_n = "%dth",
        eq_story_podium = "Winner: %s, 2nd: %s, 3rd: %s.", eq_story_winner = "Winner: %s.",
        eq_story_phase = "%s %s", eq_story_phases = "%s.", eq_story_gains = "Gained %s.",
        eq_story_injury = "Came home with %s.", eq_story_careerEnded = "Career over.",
        eq_discipline_dressage = "Dressage", eq_discipline_showJumping = "Show Jumping", eq_discipline_crossCountry = "Cross Country",
        eq_stat_stamina = "Stamina", eq_stat_speed = "Speed", eq_stat_agility = "Agility", eq_stat_temperament = "Temperament",
        eq_injury_tendon = "a tendon strain",
    }
    g_i18n = { getText = function(_, key) return texts[key] or key end }
    check("ordinals", EqStory.ordinal(1) == "1st" and EqStory.ordinal(2) == "2nd" and EqStory.ordinal(3) == "3rd"
        and EqStory.ordinal(4) == "4th" and EqStory.ordinal(11) == "11th" and EqStory.ordinal(12) == "12th"
        and EqStory.ordinal(22) == "22nd")
    check("podium line", EqStory.podiumLine({ "Applejack", "Torben", "Winter" }) == "Winner: **Applejack**, 2nd: **Torben**, 3rd: **Winter**.")
    check("phases line", EqStory.phasesLine({ "dressage", "showJumping", "crossCountry" },
        { dressage = 4, showJumping = 2, crossCountry = 6 }) == "Dressage 4th, Show Jumping 2nd, Cross Country 6th.")
    check("gains line skips tiny gains", EqStory.gainsLine({ agility = 0.42, temperament = 0.2, speed = 0.01 })
        == "Gained Agility **+0.4**, Temperament **+0.2**.")
    local runs = EqStory.runs("Winner: **Applejack**, 2nd: **Torben**.")
    check("a line splits into plain and bold runs", #runs == 5 and runs[1].text == "Winner: " and not runs[1].bold
        and runs[2].text == "Applejack" and runs[2].bold and runs[5].text == "." and not runs[5].bold)
    check("an old line with no marks is one plain run", #EqStory.runs("Clear inside the time.") == 1
        and not EqStory.runs("Clear inside the time.")[1].bold)
    check("plain text drops the marks", EqStory.plain("Gained Agility **+0.4**.") == "Gained Agility +0.4.")
    check("no gains, no line", EqStory.gainsLine({ agility = 0.01 }) == nil and EqStory.gainsLine(nil) == nil)
    check("injury line", EqStory.injuryLine({ name = "tendon" }) == "Came home with a tendon strain.")
    local lines = EqStory.lines({ performance = "Jumped clear.", podium = "Winner: X.", gains = "Gained.", injury = "Hurt." })
    check("story keeps it short: the injury replaces the gains", #lines == 3 and lines[3] == "Hurt.")
    check("story skips missing lines", #EqStory.lines({ performance = "Clear.", gains = "Gained." }) == 2)
    g_i18n = savedI18n

    -- The last five results are kept on the horse and saved with it.
    local horse = EqHorseRecord.new("DE 1 9")
    for i = 1, 7 do
        horse:addResult({ day = i, discipline = "showJumping", tier = "novice", place = i, field = 10, prize = 0,
            lines = { "Line " .. i, "Winner: X." } })
    end
    check("five results kept, newest first", #horse.results == 5 and horse.results[1].day == 7 and horse.results[5].day == 3)
    horse.results[2].status = "eliminated"
    horse.results[1].venue = "Pallegney"
    local store = memoryXML()
    horse:saveToXMLFile(store, "horse")
    local back = EqHorseRecord.loadFromXMLFile(store, "horse")
    check("results survive a save", #back.results == 5 and back.results[1].lines[1] == "Line 7" and back.results[1].lines[2] == "Winner: X."
        and back.results[1].venue == "Pallegney" and back.results[2].status == "eliminated" and back.results[5].place == 3)

    -- The hidden link a result line carries to its horse.
    dofile("scripts/core/EqMessages.lua")
    check("link round trip", EqMessages.linkedHorse({ "text", EqMessages.linkFor("GB 1 42") }) == "GB 1 42")
    check("plain lines have no link", EqMessages.linkedHorse({ "text" }) == nil and EqMessages.linkedHorse({ "a", "rl_x" }) == nil
        and EqMessages.linkedHorse(nil) == nil)
end)()

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
check("risk config: eight injury kinds", #config.injuries == 8)
check("risk config: cross country riskier than dressage",
    config.disciplineByName.crossCountry.elimination > config.disciplineByName.dressage.elimination
    and config.disciplineByName.crossCountry.injury > config.disciplineByName.dressage.injury)
check("risk config: Training Events are gentler", config.tierByName.training.risk < config.tierByName.intermediate.risk)

local rng = EqRandom.new("scratch")
check("an injured horse is scratched", EqRisk.scratchReason({ injury = { monthsLeft = 2 } }, 100, rng) == EqRisk.SCRATCH_INJURED)
check("a horse at 25 health or under is always scratched", EqRisk.scratchReason({}, 25, rng) == EqRisk.SCRATCH_UNSOUND)
check("unsound chance: 10% per 5 points under 50", EqRisk.unsoundChance(50) == 0 and EqRisk.unsoundChance(49) == 0.1
    and EqRisk.unsoundChance(45) == 0.1 and math.abs(EqRisk.unsoundChance(44) - 0.2) < 1e-9
    and math.abs(EqRisk.unsoundChance(26) - 0.5) < 1e-9 and EqRisk.unsoundChance(25) == 1 and EqRisk.unsoundChance(nil) == 0)
;(function()
    local unsound40 = 0
    for i = 1, 5000 do
        if EqRisk.scratchReason({}, 40, EqRandom.new("unsound " .. i)) == EqRisk.SCRATCH_UNSOUND then unsound40 = unsound40 + 1 end
    end
    check("a horse at 40 health is scratched about 20% of the time", unsound40 > 900 and unsound40 < 1100, unsound40 .. " of 5000")
end)()
check("poor health raises the injury chance", EqRisk.healthInjuryFactor(100) == 1 and EqRisk.healthInjuryFactor(50) == 1.5
    and EqRisk.healthInjuryFactor(nil) == 1)
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
check("an unhealthy horse is injured more", EqRisk.injuryChance(config.disciplineByName.crossCountry, config.tierByName.intermediate,
    config.goings[2], 80, 50, false, 1, 50) == 1.5 * EqRisk.injuryChance(config.disciplineByName.crossCountry,
    config.tierByName.intermediate, config.goings[2], 80, 50, false, 1))
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
check("most injuries are the small ones", counts.bruisedSole > counts.tendon and counts.tendon > counts.suspensory
    and counts.abscess > counts.chipFracture)
check("forced retirement is rare", endings > 150 and endings < 320, endings .. " of 20000")
check("forced retirement off means never", endingsOff == 0)
print(string.format("info: injuries sole %d abscess %d overreach %d back %d splints %d tendon %d chip %d suspensory %d, career-ending %d of 20000",
    counts.bruisedSole, counts.abscess, counts.overreach, counts.soreBack, counts.splints, counts.tendon,
    counts.chipFracture, counts.suspensory, endings))

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

local forced = EqRisk.rollEvent(event2, config, { { key = "me", rating = 60, temperament = 50, fitness = 100, stamina = 100 } },
    EqRandom.new("season 1"), { injuries = false, forceInjuries = true })
check("forced injuries hurt every starter, even with injuries off", forced.me.injury ~= nil)
check("forced injuries change nothing else", forced.me.eliminated == on.me.eliminated)

-- Stat change log: the day's breakdown and the kept window.
do
    EqStatLog.reset()
    local logged = { trained = { stamina = 20, speed = 20, agility = 20, temperament = 20 }, focus = "balanced", idleDays = 0 }
    local logDay = { sheet = ridden("canter", 100000), riding = 100, dirt = 5, ageMonths = 60, timeAdjustment = 1, feedBoost = { stamina = 0.1 } }
    local logDeltas, logDetail = EqTraining.applyDay(logged, cap70, logDay)
    check("applyDay explains each stat", logDetail.stats.agility ~= nil and logDetail.stats.agility.fromPlayer > 0)
    check("applyDay detail matches the delta", math.abs(math.max(logDetail.stats.agility.fromPlayer, logDetail.stats.agility.fromStaff)
        + logDetail.stats.agility.faded + logDetail.stats.agility.aged - logDeltas.agility) < 1e-9)
    local logNotes = EqStatLog.explainDay(logDetail, logDay, { focus = "balanced", sheet = logDay.sheet,
        playerPoints = EqTraining.playerRidingPoints(logDay.sheet) })
    local joined = table.concat(logNotes, "\n")
    check("explain names the riding", joined:find("canter", 1, true) ~= nil, joined)
    check("explain names the feed boost", joined:find("feed sta +10%", 1, true) ~= nil, joined)
    check("explain says groomed", joined:find("groomed", 1, true) ~= nil, joined)
    for d = 1, 10 do EqStatLog.add("DE 1 1", d, "daily training", logDeltas, logNotes, logged.trained) end
    check("log keeps a week", #EqStatLog.entries["DE 1 1"] == EqStatLog.KEEP_DAYS)
    check("log since yesterday", #EqStatLog.since("DE 1 1", 9) == 2)
    local snapshot = EqStatLog.entries["DE 1 1"][1].after
    logged.trained.speed = 99
    check("log copies the levels", snapshot.speed ~= 99)
    local idleHorse = { trained = { stamina = 40, speed = 40, agility = 40, temperament = 40 }, focus = "balanced", idleDays = 5 }
    local _, idleDetail = EqTraining.applyDay(idleHorse, cap70, { riding = 0, dirt = 50, ageMonths = 60, timeAdjustment = 1 })
    local idleNotes = table.concat(EqStatLog.explainDay(idleDetail, { riding = 0, dirt = 50, ageMonths = 60 }, { focus = "balanced", playerPoints = 0 }), "\n")
    check("explain says fading", idleNotes:find("Fading: idle 6", 1, true) ~= nil, idleNotes)
end


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
-- Green stats train fast (lowSkillFactor), so a year's work can a little more than double the outlay.
check("but it takes a while to make a lot", worth[12] < 1.15 * price, string.format("%.0f", worth[12]))
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
check("plain stables give no bonus",
    EqFacility.kindForXml(facilities, modsDir .. "FS25_horseStable/horseStable.xml", true) == nil
    and EqFacility.kindForXml(facilities, modsDir .. "FS25_horsePack/xml/horseStable.xml", true) == nil)
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
local everything = EqFacility.boosts(facilities, { indoorArena = 2, ridingCentre = 1, outdoorArena = 1, roundPen = 1, jumps = 20 },
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
local function jumpedDay()
    local sheet = ridden("canter", 100000)
    sheet.focused.agility = 1.5
    return sheet
end
EqTraining.applyDay(riddenPlain, cap70, { sheet = jumpedDay(), riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1, facilityOwned = hallOwned })
EqTraining.applyDay(riddenInside, cap70, { sheet = jumpedDay(), riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1,
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
-- Riding trains no speed while the exertion system is tested, so jumping and barley stand in.
do
    local function jumped()
        local sheet = ridden("canter", 100000)
        sheet.focused.agility = 1
        return sheet
    end
    local function trainedAgility(feedBoost, sheet)
        local record = { trained = { stamina = 30, speed = 30, agility = 30, temperament = 30 }, focus = "balanced", idleDays = 0 }
        local ceilings = { stamina = 80, speed = 80, agility = 80, temperament = 80 }
        EqTraining.applyDay(record, ceilings, { sheet = sheet, riding = 0, ageMonths = 60, timeAdjustment = 1 / 30, feedBoost = feedBoost })
        return record.trained.agility
    end
    local plain, barley = trainedAgility(nil, jumped()), trainedAgility(EqFeed.dietBoost({ BARLEY = 1 }, feeds), jumped())
    check("barley makes jumping train agility faster", barley > plain and near((barley - 30) / (plain - 30), 1.20),
        string.format("%.4f vs %.4f", barley, plain))
end
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

-- Texts looked up without a mod name: the money popup and Finances page ask the game's I18N
-- for "eq_money_*" and "finance_eq*" with no mod name, while our texts live under our mod name.
-- A stand-in for the game's I18N, a mod proxy, and a mod environment whose _G is its own table.
EqTestI18N = function()
    local savedI18N, savedI18n, savedMod = I18N, g_i18n, EqI18N.MOD_NAME
    I18N = {}
    I18N.__index = I18N
    function I18N:getText(text, modEnv)
        local env = modEnv ~= nil and self.modEnvironments[modEnv] or nil
        if env ~= nil and env.texts[text] ~= nil then return env.texts[text] end
        return self.texts[text] or string.format("Missing '%s' in l10n_en.xml", text)
    end
    function I18N:hasText(text, modEnv)
        local env = modEnv ~= nil and self.modEnvironments[modEnv] or nil
        return (env ~= nil and env.texts[text] ~= nil) or self.texts[text] ~= nil
    end
    local hadUtils = Utils
    Utils = Utils or {}
    local hadOverwritten = Utils.overwrittenFunction
    Utils.overwrittenFunction = hadOverwritten or function(old, new)
        return function(self, ...) return new(self, old, ...) end
    end

    local game = setmetatable({ texts = { ok = "OK" }, modEnvironments = {} }, I18N)
    local proxy = { texts = { eq_money_entryFees = "Competition Entry Fees", eq_money_transport = "Horse Transport" } }
    game.modEnvironments.FS25_RealisticEquestrian = proxy
    proxy.hasText = function(_, key) return game:hasText(key, "FS25_RealisticEquestrian") end
    proxy.getText = function(_, key) return game:getText(key, "FS25_RealisticEquestrian") end

    check("without the fix, a modless lookup is missing", game:getText("eq_money_entryFees"):find("Missing") ~= nil)

    -- The mod sees its proxy as g_i18n and as _G.g_i18n; the real global sits behind __index.
    local modEnv = setmetatable({ g_i18n = proxy }, { __index = setmetatable({ g_i18n = game }, { __index = _G }) })
    modEnv._G = modEnv
    setfenv(EqI18N.globalI18N, modEnv)
    check("the real global I18N is found past the mod proxy", EqI18N.globalI18N() == game)

    g_i18n = proxy
    EqI18N.MOD_NAME = "FS25_RealisticEquestrian"
    EqI18N.isInstalled = false
    check("the I18N hook installs", EqI18N.install())
    EqI18N.share({ "eq_money_entryFees", "eq_money_transport" }, { finance_eqEntryFees = "eq_money_entryFees" })
    check("the popup finds the entry fee title", game:getText("eq_money_entryFees") == "Competition Entry Fees")
    check("the popup finds the transport title", game:getText("eq_money_transport") == "Horse Transport")
    check("the Finances row finds its title", game:getText("finance_eqEntryFees") == "Competition Entry Fees")
    check("the text is in the real global table", game.texts.eq_money_transport == "Horse Transport")

    -- The hook alone, as when our texts load after the copy: clear the copy and look again.
    game.texts.eq_money_entryFees, game.texts.finance_eqEntryFees = nil, nil
    check("the hook alone finds the title", game:getText("eq_money_entryFees") == "Competition Entry Fees")
    check("the hook alone finds the Finances key", game:getText("finance_eqEntryFees") == "Competition Entry Fees")
    check("hasText sees routed keys", game:hasText("finance_eqEntryFees"))
    check("other keys are untouched", game:getText("ok") == "OK" and game:getText("nope"):find("Missing") ~= nil)

    setfenv(EqI18N.globalI18N, _G)
    I18N, g_i18n, EqI18N.MOD_NAME = savedI18N, savedI18n, savedMod
    Utils.overwrittenFunction = hadOverwritten
    Utils = hadUtils
    EqI18N.routed, EqI18N.isInstalled = {}, false
end
EqTestI18N()
EqTestI18N = nil

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
-- Transfer's single tab was centred; the full tab list must not keep that offset.
local tabbed = { pagingElement = newPaging(3), openMode = "full", eqLastPagingMode = "full",
    pagingTabList = { listItemAlignmentOffset = 0.35 } }
EqMenuPaging.beforeUpdatePages(tabbed)
check("tab list centring offset cleared before updatePages", tabbed.pagingTabList.listItemAlignmentOffset == 0)
check("clearing the tab offset copes with no tab list", EqMenuPaging.clearTabOffset({}) == false)


-- Injuries as RLRM conditions: data/injuries.xml in RLRM's own format, run through RLRM's parser
-- and its progression driver from the checkout, with only its logger and string.split stubbed.
local function injuryTests()
    local injuryXML = TestXML.load("data/injuries.xml")
    local info = EqInjury.readInfo(injuryXML)
    local translations = io.open("translations/translation_en.xml"):read("*a")
    for _, injury in ipairs(config.injuries) do
        local title = EqInjury.titleFor(injury.name)
        check("injury " .. injury.name .. " has healing times", info[injury.name] ~= nil and info[injury.name].title == title)
        check("injury " .. injury.name .. " has its texts", translations:find('name="eq_injury_' .. injury.name .. '"', 1, true) ~= nil
            and translations:find('name="rl_disease_' .. title .. '"', 1, true) ~= nil)
        check("injury title round trip " .. injury.name, EqInjury.nameFor(title) == injury.name)
        local i = info[injury.name]
        if i ~= nil then
            check("treating " .. injury.name .. " is quicker than resting", (i.treatDays ~= nil and 1 or i.treatMonths) < i.restMonths
                or (i.treatDays ~= nil and i.restMonths >= 1))
        end
    end
    check("RLRM's own diseases are not injuries", EqInjury.nameFor("colic") == nil and EqInjury.nameFor("eqInjury") == nil)
    check("the day courses", info.bruisedSole.treatDays == 1 and info.abscess.treatDays == 1 and info.overreach.treatDays == 1
        and info.tendon.treatDays == nil)

    -- Clock maths.
    check("an injury on our clock lasts its months in days", EqInjury.clockFor(2, 100, 28) == 156 and EqInjury.clockFor(1.5, 10, 1) == 12)
    check("months left on our clock", EqInjury.monthsLeftOnClock(156, 128, 28) == 1 and EqInjury.monthsLeftOnClock(10, 20, 28) == 0)
    check("resting takes at least two days", EqInjury.restFor(1, 1) == 2 and EqInjury.restFor(1.5, 1) == 2
        and EqInjury.restFor(1, 2) == 1 and EqInjury.restFor(9, 1) == 9 and EqInjury.restFor(1, 28) == 1)
    check("whole months shown", EqInjury.wholeMonths(0.2) == 1 and EqInjury.wholeMonths(2) == 2 and EqInjury.wholeMonths(2.01) == 3)
    check("a retired horse pays 40%", EqInjury.fee(4000, true) == 1600 and EqInjury.fee(4000, false) == 4000)
    check("the Retire warnings say it is permanent, and there is no way back in game",
        translations:match('name="eq_ui_retireConfirm" text="[^"]*permanent') ~= nil
        and translations:match('name="eq_ui_retireConfirmInjured" text="[^"]*permanent') ~= nil
        and translations:find('eq_ui_unretire', 1, true) == nil)
    check("the event colic chance follows RLRM's age bands",
        EqInjury.monthlyChance({ { ageMonths = 11, perMonth = 0.003 }, { ageMonths = 12, perMonth = 0.006 } }, 6) == 0.003
        and EqInjury.monthlyChance({ { ageMonths = 11, perMonth = 0.003 }, { ageMonths = 12, perMonth = 0.006 } }, 60) == 0.006)

    -- Our own clock, with RLRM's diseases off: the injury heals on its day, whatever the date it began.
    local day = 40
    g_currentMission = { environment = { currentMonotonicDay = day, daysPerPeriod = 3 } }
    local record = { injury = { name = "soreBack", untilDay = 49 } }
    local healedOn
    for d = 40, 60 do
        g_currentMission.environment.currentMonotonicDay = d
        if EqInjury.daily(record, {}) then healedOn = d break end
    end
    check("a rest on our clock heals on its day", healedOn == 49 and record.injury == nil, tostring(healedOn))
    local old = { injury = { name = "tendon", monthsLeft = 2 } }
    g_currentMission.environment.currentMonotonicDay = 100
    EqInjury.daily(old, {})
    check("an old save's months turn into days", old.injury.untilDay == 106 and old.injury.monthsLeft == nil)
    check("months left while resting", EqInjury.monthsLeft(old, {}) == 2)
    g_currentMission = nil

    -- RLRM's parser and progression, from the checkout.
    RmLogging = { LOG_LEVEL = { TRACE = 5 }, getLogger = function()
        local quiet = function() end
        return { trace = quiet, debug = quiet, info = quiet, warning = quiet, error = quiet, level = 0 }
    end }
    string.split = string.split or function(text, sep)
        local parts = {}
        for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do table.insert(parts, part) end
        return parts
    end
    for _, file in ipairs({ "RLDiseaseRecord", "RLDiseaseEffects", "RLDiseaseRates", "RLDiseaseFatality",
        "RLDiseaseProgression", "RLDiseaseDefinition", "RLDiseaseTransmission" }) do
        dofile(rlrmPath .. "/scripts/disease/" .. file .. ".lua")
    end
    local registry, warnings = RLDiseaseDefinition.parse(TestXML.load("data/injuries.xml"),
        { animalTypes = { HORSE = 7 }, i18n = { getText = function(_, key) return key end } })
    local list = {}
    for _, w in ipairs(warnings) do table.insert(list, tostring(w.title) .. ":" .. tostring(w.rule)) end
    check("RLRM's parser takes every injury without a warning", #warnings == 0, table.concat(list, " "))
    local count = 0
    for title, model in pairs(registry) do
        count = count + 1
        check(title .. " cannot spread", RLDiseaseTransmission.betaMonthly(model, 360, 0, 1) == 0
            and RLDiseaseTransmission.betaMonthly(model, 360, 0, 28) == 0)
        check(title .. " never kills", model.caseFatality == 0)
        check(title .. " never starts on its own", EqInjury.monthlyChance(model.infection, 60) == 0)
        check(title .. " is treatable", model.treatment ~= nil and model.treatment.outcome == "cure")
    end
    check("RLRM builds all eight injuries", count == 8, tostring(count))

    -- Tick a record through RLRM's driver: untreated it heals when its months are up; treated
    -- it heals when the course ends; a day course ends the next day. Every day count.
    local function heal(title, dpp, treat, dayCourse)
        local model = registry[title]
        local disease = RLDiseaseRecord.new(model, title)
        disease.state = RLDiseaseRecord.STATE.INFECTIOUS
        local running = false
        if treat then
            RLDiseaseRecord.enrolTreatment(disease, model.treatment)
            running = true
            if dayCourse then disease.treatmentMonthsRemaining = 1 / dpp end
        end
        local billed = 0
        for tick = 1, 400 do
            local _, detail = RLDiseaseProgression.advance(disease, model,
                { daysPerPeriod = dpp, vulnerability = 1, treatmentRunning = running, rng = function() return 0.5 end })
            if detail.served then
                local cost = model.treatment.cost
                if dayCourse then cost = cost * dpp end
                billed = billed + cost / dpp
            end
            if disease.state == RLDiseaseRecord.STATE.RECOVERED then return tick, billed end
        end
        return nil, billed
    end
    for _, dpp in ipairs({ 1, 3, 28 }) do
        local ticks = heal("eqInjuryTendon", dpp, false)
        check("an untreated tendon strain heals in 9 months at " .. dpp .. " day(s) a month", ticks == 9 * dpp, tostring(ticks))
        local treated, bill = heal("eqInjuryTendon", dpp, true)
        check("a treated tendon strain heals in 4 months at " .. dpp, treated == 4 * dpp, tostring(treated))
        check("and costs 4 x $4,000 at " .. dpp, math.abs(bill - 16000) < 1, tostring(bill))
        local dayTicks, dayBill = heal("eqInjuryBruisedSole", dpp, true, true)
        check("a bruised sole's day course takes one day at " .. dpp, dayTicks == 1, tostring(dayTicks))
        check("and costs a flat $400 at " .. dpp, math.abs(dayBill - 400) < 1e-6, tostring(dayBill))
        local abscess = heal("eqInjuryAbscess", dpp, false)
        check("an untreated abscess takes its month and a half at " .. dpp, abscess == math.ceil(1.5 * dpp - 1e-9), tostring(abscess))
    end

    -- The hook on RLRM's Disease.onDayChanged, at one day a month: no tick on the day it
    -- happened, healed the next day, and removed rather than left showing as immune.
    local fakeDisease = {}
    function fakeDisease.onDayChanged(disease, animal, deathEnabled, dpp)
        local instruction, detail = RLDiseaseProgression.advance(disease, disease.model,
            { daysPerPeriod = dpp, vulnerability = 1, treatmentRunning = disease.treatmentRunning, rng = function() return 0.5 end })
        return instruction, detail.served and disease.model.treatment.cost / dpp or 0, detail.treatment
    end
    Utils = Utils or { appendedFunction = function(a, b) return function(...) a(...) b(...) end end }
    local savedEnv, savedInstalled = EqRLRM.env, EqInjury.installed
    EqRLRM.env = { Disease = fakeDisease, DiseaseManager = { loadDiseases = function() end },
        RLDiseaseProgression = RLDiseaseProgression, RLDiseaseRecord = RLDiseaseRecord }
    EqInjury.installed = false
    EqInjury.install(function(_, fn) fn() end)
    g_currentMission = { environment = { currentMonotonicDay = 10, daysPerPeriod = 1 } }
    local sole = RLDiseaseRecord.new(registry.eqInjuryBruisedSole, "eqInjuryBruisedSole")
    sole.model = registry.eqInjuryBruisedSole
    sole.state = RLDiseaseRecord.STATE.INFECTIOUS
    sole.eqStartDay = 10
    local first = fakeDisease.onDayChanged(sole, {}, true, 1)
    check("an injury isn't ticked on the day it happened", first == "KEEP" and sole.state == "INFECTIOUS" and sole.monthsElapsed == 0)
    g_currentMission.environment.currentMonotonicDay = 11
    local second = fakeDisease.onDayChanged(sole, {}, true, 1)
    check("at one day a month a one-month rest still takes two days", second == "KEEP" and sole.state == "INFECTIOUS", tostring(second))
    check("the model keeps its authored month", registry.eqInjuryBruisedSole.durationMonths == 1)
    g_currentMission.environment.currentMonotonicDay = 12
    local third = fakeDisease.onDayChanged(sole, {}, true, 1)
    check("a healed injury is removed, not left immune", third == "REMOVE" and sole.state == "RECOVERED", tostring(third))
    -- RLRM's own Contracted and Cured lines are dropped for injuries, kept for its diseases.
    local posted = {}
    local fakeAnimal = { addMessage = function(_, id, args) table.insert(posted, id .. " " .. args[1]) end }
    EqRLRM.env.Animal = fakeAnimal
    local savedModels = EqInjury.models
    EqInjury.models = { bruisedSole = { name = "Bruised sole" } }
    EqInjury.installed = false
    EqInjury.install(function(_, fn) fn() end)
    fakeAnimal.addMessage({}, "DISEASE_CONTRACTED", { "Bruised sole" })
    fakeAnimal.addMessage({}, "DISEASE_CURED", { "Bruised sole" })
    fakeAnimal.addMessage({}, "DISEASE_CONTRACTED", { "Colic" })
    EqInjury.catching = true
    fakeAnimal.addMessage({}, "DISEASE_CONTRACTED", { "Colic" })
    EqInjury.catching = false
    check("RLRM's injury lines are dropped, its disease lines kept", #posted == 1 and posted[1] == "DISEASE_CONTRACTED Colic",
        table.concat(posted, ", "))
    EqInjury.models = savedModels
    g_currentMission = nil
    EqRLRM.env, EqInjury.installed = savedEnv, savedInstalled
end
injuryTests()
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

-- Settings page rows and the training rate.
;(function()
    local rate = EqSettings.BY_ID.trainingRate
    check("training rate texts", rate.texts[1].text == "0.25x" and rate.texts[2].text == "0.5x" and rate.texts[4].text == "1x")
    check("training rate state of 1", rate.values[EqSettings.stateOf(rate, 1)] == 1)
    check("console rate shows as nearest choice", rate.values[EqSettings.stateOf(rate, 1.1)] == 1)
    check("unset rate shows the default", rate.values[EqSettings.stateOf(rate, nil)] == 1)
    local limits = EqSettings.BY_ID.entriesPerMonth
    check("entries default is 3", limits.values[EqSettings.stateOf(limits, nil)] == 3)
    check("no limit is the first entry choice", limits.values[1] == 0 and limits.texts[1].key == "eq_settings_noLimit")
    local fewest, most = EqSettings.BY_ID.eventsMin, EqSettings.BY_ID.eventsMax
    check("events shown default to 3 to 8", fewest.values[EqSettings.stateOf(fewest, nil)] == 3
        and most.values[EqSettings.stateOf(most, nil)] == 8)
    local cadence = EqSettings.BY_ID.cadence
    check("cadence state", EqSettings.stateOf(cadence, "month") == 2)
    local onOff = EqSettings.BY_ID.racing
    check("racing off state", EqSettings.stateOf(onOff, false) == 1 and EqSettings.stateOf(onOff, true) == 2)

    local settings = { trainingRate = 1, racing = true }
    check("apply changes a value", EqSettings.apply(settings, "trainingRate", 7) and settings.trainingRate == 2)
    check("apply of the same value reports no change", not EqSettings.apply(settings, "trainingRate", 7))
    check("apply turns racing off", EqSettings.apply(settings, "racing", 1) and settings.racing == false)
    check("apply ignores unknown rows and states", not EqSettings.apply(settings, "nope", 1)
        and not EqSettings.apply(settings, "racing", 9))
    check("trainingRate falls back to 1", EqSettings.trainingRate(nil) == 1 and EqSettings.trainingRate({ trainingRate = 0 }) == 1)

    for _, id in ipairs({ "entryFeeScale", "prizeScale" }) do
        local row = EqSettings.BY_ID[id]
        check(id .. " runs 0.5x to 2x", row.values[1] == 0.5 and row.values[#row.values] == 2
            and row.texts[1].text == "0.5x" and row.texts[#row.texts].text == "2x")
        check(id .. " defaults to 1x", row.values[EqSettings.stateOf(row, nil)] == 1)
        check(id .. " falls back to 1", EqSettings.multiplier({}, id) == 1)
    end

    local event = { fee = 250, prize = 1000 }
    EqCompetition.scaleMoney(event, 2, 0.5)
    check("fee and prize scales apply to an event", event.fee == 500 and event.prize == 500)
    event = { fee = 250, prize = 1000 }
    EqCompetition.scaleMoney(event, 0.75, 1.25)
    check("scaled money keeps the draw's rounding", event.fee == 190 and event.prize == 1250)

    local translations = {}
    for _, lang in ipairs({ "en", "de" }) do
        local file = io.open("translations/translation_" .. lang .. ".xml")
        translations[lang] = file:read("*a")
        file:close()
    end
    for _, row in ipairs(EqSettings.ROWS) do
        for _, key in ipairs({ "eq_settings_" .. row.id, "eq_settings_" .. row.id .. "_tooltip" }) do
            check("settings text " .. key, translations.en:find('name="' .. key .. '"', 1, true) ~= nil)
        end
        for _, entry in ipairs(row.texts) do
            if entry.key ~= nil then
                check("settings text " .. entry.key, translations.en:find('name="' .. entry.key .. '"', 1, true) ~= nil)
            end
        end
    end

    local ceilings = { stamina = 90, speed = 90, agility = 90, temperament = 90 }
    local function trainedWith(r)
        local horse = { trained = { stamina = 40, speed = 40, agility = 40, temperament = 40 }, focus = "balanced", idleDays = 0 }
        local deltas = EqTraining.applyDay(horse, ceilings, { riding = 100, dirt = 50, ageMonths = 60, timeAdjustment = 1 / 30, rate = r })
        return deltas.stamina
    end
    local normal, double, quarter = trainedWith(nil), trainedWith(2), trainedWith(0.25)
    check("training rate 2 doubles a day's gain", normal > 0 and math.abs(double - 2 * normal) < 1e-9, string.format("%.4f vs %.4f", double, normal))
    check("training rate 0.25 quarters a day's gain", math.abs(quarter - normal / 4) < 1e-9)

    local function boostedWith(r)
        local horse = { trained = { stamina = 40, speed = 40, agility = 40, temperament = 40 } }
        return EqTraining.applyBoost(horse, ceilings, { stamina = 1, speed = 1 }, 0.5, 60, 1 / 30, r).speed
    end
    check("training rate scales event boosts", math.abs(boostedWith(3) - 3 * boostedWith(nil)) < 1e-9)
end)()

-- Recent stat gains: summed per day, kept seven days, saved with the horse.
;(function()
    local horse = EqHorseRecord.new("DE 1 9")
    horse:addGains(10, { stamina = 0.5, speed = 0.1 })
    horse:addGains(10, { stamina = 0.25 })
    horse:addGains(14, { stamina = 1, agility = -0.3 })
    check("same-day gains share an entry", #horse.gains == 2)
    local gains = horse:getRecentGains(14)
    check("recent gains sum the week", math.abs(gains.stamina - 1.75) < 1e-9 and math.abs(gains.agility + 0.3) < 1e-9)
    check("gains older than a week drop out of the sum", math.abs(horse:getRecentGains(17).stamina - 1) < 1e-9)
    horse:addGains(17, { stamina = 0.1 })
    check("old gain days are dropped", #horse.gains == 2 and horse.gains[1].day == 14)
    horse:addGains(18, nil)
    check("no deltas adds nothing", #horse.gains == 2)
    local x = memoryXML()
    horse:saveToXMLFile(x, "h")
    local back = EqHorseRecord.loadFromXMLFile(x, "h")
    check("gains survive a save", #back.gains == 2 and math.abs(back:getRecentGains(17).stamina - 1.1) < 1e-9)
    check("an old save loads with no gains", #EqHorseRecord.loadFromXMLFile((function()
        local y = memoryXML(); EqHorseRecord.new("DE 1 10"):saveToXMLFile(y, "h"); return y end)(), "h").gains == 0)

    dofile("scripts/gui/EqInfoDisplay.lua")
    check("gain to one decimal", EqInfoDisplay.gainText(2.84) == "(+2.8)")
    check("gain rounds", EqInfoDisplay.gainText(2.86) == "(+2.9)" and EqInfoDisplay.gainText(12.96) == "(+13.0)")
    check("a loss shows a minus", EqInfoDisplay.gainText(-0.45) == "(-0.5)" or EqInfoDisplay.gainText(-0.45) == "(-0.4)")
    check("tiny changes are not shown", EqInfoDisplay.gainText(0.049) == nil and EqInfoDisplay.gainText(-0.04) == nil
        and EqInfoDisplay.gainText(0) == nil and EqInfoDisplay.gainText(nil) == nil)
    check("0.05 shows as 0.1", EqInfoDisplay.gainText(0.051) == "(+0.1)")
    local white, full, half = EqInfoDisplay.skillColor(0, "speed"), EqInfoDisplay.skillColor(100, "speed"), EqInfoDisplay.skillColor(50, "speed")
    check("skill shades white to the stat colour", white[1] == 1 and white[2] == 1 and white[3] == 1
        and full[1] == 1 and math.abs(full[2] - 0.45) < 1e-9 and full[3] == 0 and math.abs(half[3] - 0.5) < 1e-9)
end)()

-- The look-at Skills box draws the skill and the potential in their own colours.
;(function()
    local overlay = function() return { x = 0, y = 0, width = 0, height = 0.01,
        setDimension = function() end, setPosition = function(o, x, y) o.x, o.y = x, y end, render = function() end } end
    local Base = {}
    -- Like the game's Class(): the instance's metatable is protected.
    function Base.new() return setmetatable({ lines = {}, title = "", currentLineIndex = 0, bgScale = overlay(), bgTop = overlay(), bgBottom = overlay() },
        { __index = Base, __metatable = false }) end
    function Base:storeScaledValues() end
    function Base:clear() for _, l in ipairs(self.lines) do l.isActive = false end self.currentLineIndex = 0 end
    local savedEnv = EqRLRM.env
    EqRLRM.env = { RL_InfoDisplayKeyValueBox = Base }
    dofile("scripts/gui/EqSkillsHudBox.lua")
    check("skills box available with RLRM's box", EqSkillsHudBox.isAvailable())

    local rendered = {}
    local current
    _G.setTextColor = function(r, g, b, a) current = { r, g, b, a } end
    _G.setTextAlignment = function() end
    _G.setTextBold = function() end
    _G.renderText = function(_, _, _, text) rendered[text] = current end
    _G.getTextWidth = function(_, text) return #text * 0.01 end
    _G.drawDashedLine = function() end
    _G.g_pixelSizeX = 0.001
    _G.RenderText = { ALIGN_LEFT = 0, ALIGN_RIGHT = 2 }
    _G.HUD = { COLOR = { INACTIVE = { 0.5, 0.5, 0.5, 1 } } }

    local box = EqSkillsHudBox.new({}, 1)
    for k, v in pairs({ boxWidth = 0.2, titleAndBoxHeight = 0.05, lineHeight = 0.02, titleOffsetX = 0, titleOffsetY = 0,
        titleTextSize = 0.01, titleToLineOffsetY = -0.02, keyOffsetX = 0, valueOffsetX = 0, keyTextSize = 0.01,
        valueTextSize = 0.01, lineToLineOffsetY = -0.02, dashedLineHeight = 0.001, dashWidth = 0.005, dashGapWidth = 0.002 }) do
        box[k] = v
    end
    box:clear()
    box:addLine("Stamina", "72 - Competitor", { 0, 1, 0, 1 }, "(Very high)", { 0.2, 1, 0, 1 })
    box:addLine("Favourite event", "None yet")
    box:addLine("Speed", "54 - Amateur (+2.8)", { 1, 1, 0, 1 }, "(High)", { 0.5, 1, 0, 1 }, { 1, 0.55, 0.15, 1 })
    local widths = {}
    box.bgTop.setDimension = function(_, w) if w ~= nil then table.insert(widths, w) end end
    box:draw(0.9, 0.1)
    check("stat title in its own colour", rendered["Speed"] ~= nil and rendered["Speed"][2] == 0.55)
    check("value keeps the skill colour beside a stat colour", rendered["54 - Amateur (+2.8)"] ~= nil
        and rendered["54 - Amateur (+2.8)"][2] == 1)
    check("box grows to fit a long line", widths[1] ~= nil and widths[1] > 0.2, tostring(widths[1]))
    check("skill value in skill colour", rendered["72 - Competitor"] ~= nil and rendered["72 - Competitor"][1] == 0)
    check("stat title in skill colour", rendered["Stamina"] ~= nil and rendered["Stamina"][2] == 1 and rendered["Stamina"][1] == 0)
    check("potential in potential colour", rendered[" (Very high)"] ~= nil and rendered[" (Very high)"][1] == 0.2)
    check("uncoloured line is white", rendered["None yet"] ~= nil and rendered["None yet"][1] == 1 and rendered["None yet"][3] == 1)

    EqRLRM.env = {}
    check("skills box unavailable without RLRM's box", not EqSkillsHudBox.isAvailable())
    EqRLRM.env = savedEnv
end)()

-- The maker's mark agrees everywhere it is kept
;(function()
    check("mark reads Jasta007", EqRandom.mark() == "Jasta007")
    check("mark matches the author constant", EqRandom.mark() == EqConstants.AUTHOR)
    local file = io.open("modDesc.xml", "r")
    local author = file ~= nil and file:read("*a"):match("<author>(.-)</author>") or ""
    if file ~= nil then file:close() end
    check("modDesc names the maker", string.find(author, EqRandom.mark(), 1, true) ~= nil)
end)()

-- Horse roles: cycling, staff profiles and the Info tab's role groups
;(function()
    g_i18n = g_i18n or { getText = function(_, key) return key end }
    check("new horse has no role", EqRole.get(EqHorseRecord.new("X 1 1")) == EqRole.NONE
        and not EqRole.has(EqHorseRecord.new("X 1 1")))
    check("unknown focus reads as no role", EqRole.get({ focus = "bogus" }) == EqRole.NONE)
    local role, seen = EqRole.NONE, 0
    repeat role, seen = EqRole.next(role), seen + 1 until role == EqRole.NONE or seen > 20
    check("Role button cycles every role and back to none", seen == #EqRole.ORDER)
    for _, name in ipairs(EqRole.ORDER) do
        check("staff train to role " .. name, EqTraining.FOCUS[name] ~= nil)
    end
    local good = EqTraining.staffEffort(100, 0, "dressage", false, EqTraining.STAFF_LUCK.high)
    local bad = EqTraining.staffEffort(100, 0, "dressage", false, EqTraining.STAFF_LUCK.low)
    check("staff luck changes a role's own stats", good.temperament > bad.temperament and good.agility > bad.agility)
    check("staff luck leaves the role's other stats", good.stamina == bad.stamina)
    check("no role: staff work is steady", EqTraining.staffEffort(100, 0, "balanced", false, 1.5).speed
        == EqTraining.staffEffort(100, 0, "balanced", false, 0.5).speed)

    local function item(name, focus) return { cluster = { name = name, focus = focus } } end
    local roleOf = function(cluster) return cluster.focus and EqRole.get({ focus = cluster.focus }) or nil end
    local a, b, c, d = item("a", "balanced"), item("b", "racing"), item("c", "dressage"), item("d", "racing")
    local items = { a, b, c, d }
    local order, byKey, titles = { "subtype_1" }, { subtype_1 = items }, { subtype_1 = "Brown horse" }
    local o, k, t = EqRole.groupSections(items, order, byKey, titles, roleOf)
    check("roles group in role order, no role last", #o == 3 and o[1] == "eqRole_dressage" and o[2] == "eqRole_racing"
        and o[3] == "eqRole_balanced", table.concat(o, ","))
    check("a group keeps RLRM's order", k.eqRole_racing[1] == b and k.eqRole_racing[2] == d)
    check("a group is titled by its role", t.eqRole_dressage == "eq_role_dressage")
    local plain = { item("a", "balanced"), item("b", "balanced") }
    local o2 = EqRole.groupSections(plain, order, byKey, titles, roleOf)
    check("no roles: RLRM's groups kept", o2 == order)
    local cow = { cluster = { name = "cow" } }
    local o3 = EqRole.groupSections({ b, cow }, order, byKey, titles, roleOf)
    check("not all horses: RLRM's groups kept", o3 == order)
    local sickOrder = { "__diseased__", "subtype_1" }
    local sickBy = { __diseased__ = { c }, subtype_1 = { a, b, d } }
    local o4, k4 = EqRole.groupSections(items, sickOrder, sickBy, { __diseased__ = "Diseased" }, roleOf)
    local retired = item("r", "dressage")
    local retiredRoleOf = function(cluster)
        return cluster == retired.cluster and EqRole.RETIRED or roleOf(cluster)
    end
    local o5, k5, t5 = EqRole.groupSections({ a, retired, b }, order, { subtype_1 = { a, retired, b } }, titles, retiredRoleOf)
    check("retired horses get the last group", o5[#o5] == "eqRole_retired" and k5.eqRole_retired[1] == retired
        and t5.eqRole_retired == "eq_role_retired", table.concat(o5, ","))
    check("retired shows over a horse's role", EqRole.shown({ focus = "dressage", retired = true }) == EqRole.RETIRED
        and EqRole.get({ focus = "dressage", retired = true }) == "dressage")
    local cycled, guard = EqRole.NONE, 0
    repeat cycled, guard = EqRole.next(cycled), guard + 1 until cycled == EqRole.NONE or cycled == EqRole.RETIRED or guard > 20
    check("the Role button never gives Retired", cycled == EqRole.NONE)
    check("diseased horses stay first", o4[1] == "__diseased__" and k4.__diseased__[1] == c and k4.eqRole_dressage == nil
        and o4[2] == "eqRole_racing", table.concat(o4, ","))
end)()

-- Ride horse on RLRM's Info tab
;(function()
    g_i18n = g_i18n or { getText = function(_, key) return key end }
    InputAction = InputAction or {}
    local savedAway = EqAway
    local away = false
    EqAway = { isAway = function() return away end }
    local horse = { getRidableFilename = function() return "horse.xml" end }
    local cow = { getRidableFilename = function() return nil end }
    check("horse is rideable", EqRideButton.isRideable(horse))
    check("cow is not rideable", not EqRideButton.isRideable(cow) and not EqRideButton.isRideable(nil))

    local function frameWith(animal, buttons)
        local frame = { menuButtonInfo = buttons, selectedHusbandry = {}, dirty = 0 }
        frame.getSelectedAnimal = function() return animal end
        frame.setMenuButtonInfoDirty = function(self) self.dirty = self.dirty + 1 end
        return frame
    end
    local back = { name = "back" }
    local frame = frameWith(horse, { back, {}, {}, {}, {}, {}, {}, {} })
    EqRideButton.updateButtons(frame)
    check("ride button right after Back", frame.menuButtonInfo[1] == back and frame.menuButtonInfo[2] == frame.eqRideButtonInfo
        and #frame.menuButtonInfo == 9 and frame.dirty == 1)
    check("ride button enabled", frame.eqRideButtonInfo.disabled == false)
    away = true
    frame.menuButtonInfo = { back }
    EqRideButton.updateButtons(frame)
    check("ride button greyed out while away", frame.menuButtonInfo[2] == frame.eqRideButtonInfo and frame.eqRideButtonInfo.disabled == true)
    local cowFrame = frameWith(cow, { back })
    EqRideButton.updateButtons(cowFrame)
    check("no ride button for a cow", #cowFrame.menuButtonInfo == 1 and cowFrame.dirty == 0)
    local empty = frameWith(nil, { back })
    EqRideButton.updateButtons(empty)
    check("no ride button without a selection", #empty.menuButtonInfo == 1)
    EqAway = savedAway
end)()

-- Starved map horses get a fresh start; real horses are never touched
;(function()
    local function horse(fields)
        local animal = { isHorse = function() return true end, birthday = { day = 1, month = 1, year = 1, country = 1 },
            age = 0, health = 0, motherId = "-1", fitness = 0, riding = 0, weight = 0.001, targetWeight = 500 }
        for k, v in pairs(fields or {}) do animal[k] = v end
        animal.getIdentifiers = function() return animal.id or "UK 1 1" end
        return animal
    end
    check("a map placeholder is spotted", EqFreshStart.isMapPlaceholder(horse()))
    check("a foal with a mother is not", not EqFreshStart.isMapPlaceholder(horse({ motherId = "UK 4 7" })))
    check("a healthy newborn is not", not EqFreshStart.isMapPlaceholder(horse({ health = 80 })))
    check("a sick adult is not", not EqFreshStart.isMapPlaceholder(horse({ age = 60 })))
    check("a ridden horse is not", not EqFreshStart.isMapPlaceholder(horse({ fitness = 15 })))
    check("a dead horse is not", not EqFreshStart.isMapPlaceholder(horse({ isDead = true })))
    check("a cow is not", not EqFreshStart.isMapPlaceholder({ isHorse = function() return false end, age = 0, health = 0 }))

    EqRegistry.reset()
    local placeholder = horse({ id = "UK 9 9" })
    local before = EqRegistry.getOrCreate(placeholder)
    local foalStats = before.trained.speed + before.trained.agility + before.trained.stamina + before.trained.temperament
    EqFreshStart.repair(placeholder, EqRandom.new("fresh start test"))
    local after = EqRegistry.getById("UK 9 9")
    local adultStats = after.trained.speed + after.trained.agility + after.trained.stamina + after.trained.temperament
    check("repaired horse is an adult", placeholder.age >= EqFreshStart.MIN_AGE_MONTHS and placeholder.age <= EqFreshStart.MAX_AGE_MONTHS)
    check("repaired horse is healthy and a normal weight", placeholder.health == 100 and placeholder.weight >= 460)
    check("repaired horse keeps its record, redrawn for its age", after == before and adultStats > foalStats,
        string.format("foal %.1f adult %.1f", foalStats, adultStats))
    check("a repaired horse no longer matches", not EqFreshStart.isMapPlaceholder(placeholder))
    EqRegistry.reset()
end)()

-- Welcome popups: which menu series shows, and the horse pen check.
;(function()
    EqTrainingHud = EqTrainingHud or {}
    dofile("scripts/gui/EqWelcome.lua")
    local seen = {}
    local function state(t)
        t.seen = function(series) return seen[series] == true end
        return t
    end
    check("no menu welcome without horses", EqWelcome.menuSeries(state({ hasHorses = false, infoOpen = true })) == nil)
    check("menu welcome first", EqWelcome.menuSeries(state({ hasHorses = true, infoOpen = true })) == "menu")
    seen.menu = true
    check("info welcome on the Information tab", EqWelcome.menuSeries(state({ hasHorses = true, infoOpen = true })) == "info")
    check("events welcome even without horses", EqWelcome.menuSeries(state({ hasHorses = false, eventsOpen = true })) == "events")
    seen.info, seen.events = true, true
    check("nothing once all are seen", EqWelcome.menuSeries(state({ hasHorses = true, infoOpen = true, eventsOpen = true })) == nil)

    local oldAnimalType = AnimalType
    AnimalType = { HORSE = 4, COW = 1 }
    local horsePen = { spec_husbandryAnimals = { animalTypeIndex = 4 }, x = 100, z = 0 }
    local cowPen = { spec_husbandryAnimals = { animalTypeIndex = 1 }, x = 0, z = 0 }
    local positionOf = function(p) return p.x, p.z end
    check("a cow pen is not a horse pen", not EqWelcome.nearHorsePen({ cowPen }, 0, 0, 35, positionOf))
    check("near a horse pen", EqWelcome.nearHorsePen({ cowPen, {}, horsePen }, 80, 10, 35, positionOf))
    check("too far from a horse pen", not EqWelcome.nearHorsePen({ horsePen }, 50, 0, 35, positionOf))
    AnimalType = oldAnimalType
end)()

-- Stats a horse joined the farm with, for eqChanges "since joined"
;(function()
    EqRegistry.reset()
    local animal = { isHorse = function() return true end, birthday = { day = 1, month = 1, year = 1, country = 1 },
        age = 60, motherId = "-1", getIdentifiers = function() return "UK 7 77" end }
    local record = EqRegistry.getOrCreate(animal)
    check("a new horse notes its starting stats", record.start ~= nil and record.start.stamina == record.trained.stamina)
    local stamina = record.start.stamina
    record.trained.stamina = record.trained.stamina + 5
    EqRegistry.getOrCreate(animal)
    check("starting stats are noted once", record.start.stamina == stamina)

    local x = memoryXML()
    record:saveToXMLFile(x, "h")
    local back = EqHorseRecord.loadFromXMLFile(x, "h")
    check("starting stats survive a save", back.start ~= nil and math.abs(back.start.stamina - stamina) < 0.001)
    check("an old save loads with no starting stats", EqHorseRecord.loadFromXMLFile((function()
        local y = memoryXML(); EqHorseRecord.new("DE 1 11"):saveToXMLFile(y, "h"); return y end)(), "h").start == nil)
    EqRegistry.reset()
end)()

;(function()
    -- Dressage markers: a standard 20 x 40 m arena.
    local arena = {}
    for _, m in ipairs({ { "A", 10, 0 }, { "K", 0, 6 }, { "E", 0, 20 }, { "H", 0, 34 }, { "C", 10, 40 }, { "M", 20, 34 },
        { "B", 20, 20 }, { "F", 20, 6 }, { "D", 10, 6 }, { "X", 10, 20 }, { "G", 10, 34 } }) do
        table.insert(arena, { letter = m[1], x = m[2], z = m[3] })
    end
    local far = { letter = "Q", x = 500, z = 500 }
    local all = { far }
    for _, m in ipairs(arena) do table.insert(all, m) end
    local course = EqDressage.findCourse(all, 12, 3)
    check("the whole arena is a course", course ~= nil and #course == #arena and course[1].letter == "D")
    check("no markers within 100 m: no course", EqDressage.findCourse(all, 300, 300) == nil)
    check("markers in a line are no course", EqDressage.findCourse({ { letter = "A", x = 0, z = 0 }, { letter = "X", x = 0, z = 20 },
        { letter = "C", x = 0.5, z = 40 } }, 0, 0) == nil)
    check("two markers are no course", EqDressage.findCourse({ arena[1], arena[2] }, 10, 0) == nil)
    check("a marker's letter comes from its configuration", EqDressage.letterFor(2, nil) == "B" and EqDressage.letterFor(26, "letter_Z") == "Z"
        and EqDressage.letterFor(1, "Letter K") == "K" and EqDressage.letterFor(nil, nil) == "?")
    check("Riding Hall 2k26 markers are recognised", EqDressage.isMarkerXml("C:\\mods\\FS25_RidingHall\\objekt.xml")
        and not EqDressage.isMarkerXml("FS25_RidingHall/props01.xml"))
    check("our dressage arenas are recognised", EqDressage.isArenaXml("C:\\mods\\FS25_RealisticEquestrian\\placeables\\dressageArena\\dressageArena20x40.xml")
        and EqDressage.isArenaXml("FS25_RealisticEquestrian/placeables/dressageArena/dressageArena15x30.xml")
        and not EqDressage.isArenaXml("FS25_RidingHall/objekt.xml") and not EqDressage.isArenaXml(nil))
    check("arena marker nodes give their letter", EqDressage.arenaLetter("eqMarker_X") == "X"
        and EqDressage.arenaLetter("eqMarkers") == nil and EqDressage.arenaLetter("arena") == nil)

    -- A rider who does what is asked, ridden frame by frame.
    local SPEED = { walk = 1.7, trot = 3.5, canter = 5.5 }
    local function ride(rng, ms, markers, log)
        local sheet, x, z = EqTraining.newSheet(), 12, 3
        local spin = 0
        local events = {}
        for _ = 1, ms / 50 do
            local r = sheet.routine
            local task, move, steer = r.task, "walk", nil
            if task ~= nil then
                if task.kind == "go" then
                    move = r.bonus ~= nil and r.bonus.gait or task.gait
                    local dx, dz = task.marker.x - x, task.marker.z - z
                    local d = math.sqrt(dx * dx + dz * dz)
                    local step = math.min(d, SPEED[move] * 0.05)
                    if d > 0 then x, z = x + dx / d * step, z + dz / d * step end
                elseif task.kind == "reverse" then move = "reverse"
                elseif task.kind == "turn" then move, steer = "halt", task.side
                elseif task.kind == "circle" then
                    -- A 3 m circle at a walk.
                    move, steer = "walk", task.side
                    spin = spin + 0.03
                    x, z = x + math.sin(spin) * 0.09, z + math.cos(spin) * 0.09
                else move = "halt" end
            end
            local event = EqTraining.routineStep(sheet, move, steer, 50, false, rng, markers and { x = x, z = z, markers = markers } or nil)
            if event ~= nil then events[event] = (events[event] or 0) + 1 end
            if log and task ~= nil and r.task ~= task then log[task.kind] = (log[task.kind] or 0) + 1 end
        end
        return sheet, events
    end
    local seed = 7
    local function rng(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
    local kinds = {}
    local danced, events = ride(rng, 600000, course, kinds)
    check("a rider who follows the markers keeps the routine going", danced.routine.active and danced.routine.mult == EqTraining.ROUTINE_MAX
        and (events.lost or 0) == 0, string.format("mult %d, lost %d", danced.routine.mult, events.lost or 0))
    check("legs are the most common command, backing up the rarest", (kinds.go or 0) > (kinds.halt or 0)
        and (kinds.reverse or 0) < (kinds.halt or 0) and (kinds.reverse or 0) > 0,
        string.format("go %d halt %d turn %d reverse %d", kinds.go or 0, kinds.halt or 0, kinds.turn or 0, kinds.reverse or 0))
    check("passing other markers sometimes earns a bonus", (events.bonus or 0) > 0)
    seed = 7
    local free = ride(rng, 600000, nil)
    check("without markers the free routine runs, training less", free.routine.kind == "free"
        and danced.focused.temperament > free.focused.temperament,
        string.format("markers %.2f free %.2f", danced.focused.temperament, free.focused.temperament))

    local sheet = EqTraining.newSheet()
    local here = { x = 12, z = 3, markers = course }
    local one = function() return 1 end
    for _ = 1, 50 do EqTraining.routineStep(sheet, "walk", nil, 50, false, one, here) end
    local r = sheet.routine
    check("walking near markers starts a marker routine with a leg", r.kind == "markers" and r.request == "go" and r.task.marker ~= nil)
    check("the first leg goes to a marker at least 8 m away", math.sqrt((r.task.marker.x - 12) ^ 2 + (r.task.marker.z - 3) ^ 2) >= 8)
    local deadline = r.deadline
    check("a leg gets far more time than a free command", deadline - r.clock > EqTraining.ROUTINE_REACT_MS * 2)
    r.task.gait = "canter"
    EqTraining.routineStep(sheet, "canter", nil, 50, false, one, here)
    check("a canter asked for keeps the routine", r.active)
    r.mult = 5
    local faults = 0
    for _ = 1, 40 do
        if EqTraining.routineStep(sheet, "gallop", nil, 50, false, one, here) == "fault" then faults = faults + 1 end
    end
    check("galloping is a fault, not the end", r.active and faults == 1 and r.faults == 1 and r.mult == 3 and r.task.kind == "go",
        string.format("faults %d mult %d", faults, r.mult))
    for _ = 1, 400 do EqTraining.routineStep(sheet, "halt", nil, 50, false, one, here) end
    check("three faults end it", not r.active)
    for _ = 1, 50 do EqTraining.routineStep(sheet, "walk", nil, 50, false, one, here) end
    EqTraining.routineStep(sheet, "walk", nil, 50, false, one, nil)
    check("leaving the course carries on with the free routine", r.active and r.kind == "free" and r.task == nil)

    -- In one of our arenas the routine opens at X with a halt.
    local ours = {}
    for _, m in ipairs(course) do ours[#ours + 1] = { letter = m.letter, x = m.x, z = m.z, arena = true } end
    local opening = EqTraining.newSheet()
    local at = { x = 12, z = 8, markers = ours }
    for _ = 1, 50 do EqTraining.routineStep(opening, "walk", nil, 50, false, one, at) end
    local o = opening.routine
    check("in our arenas the first leg goes to A", o.kind == "markers" and o.task.opening == "A" and o.task.marker.letter == "A")
    local toX = EqDressage.plan(o, { x = 10, z = 0, markers = ours }, "go", one)
    check("then a trot down the centre line to X", toX.marker.letter == "X" and toX.gait == "trot")
    o.task = toX
    check("and a halt at X", EqDressage.plan(o, { x = 10, z = 20, markers = ours }, "go", one).kind == "halt")
    check("a horse at A already goes straight to X", EqDressage.openingLeg({ x = 10, z = 1, markers = ours }).opening == "X")
    local toA = EqDressage.openingLeg(at)
    check("the first trip to A is a trot, untimed", toA.gait == "trot" and toA.untimed)
    local near = EqTraining.newSheet()
    EqTraining.routineStep(near, "trot", nil, 50, false, one, at)
    check("coming up to our arena starts its test at once", near.routine.active and near.routine.task.opening == "A")
    -- Far from our arena (past C at the far end): no test, and no "Move to A" from 80 m off.
    local beyond = { x = 10, z = 40 + 50, markers = ours }
    check("not near an arena 50 m past its end", not EqDressage.nearArena(beyond))
    check("near an arena 10 m past its end", EqDressage.nearArena({ x = 10, z = 40 + 10, markers = ours }))
    local away = EqTraining.newSheet()
    for _ = 1, 50 do EqTraining.routineStep(away, "walk", nil, 50, false, one, beyond) end
    check("walking far from our arena rides the free routine", away.routine.active and away.routine.kind == "free")
    for _ = 1, 3 do EqTraining.routineStep(away, "walk", nil, 50, false, one, at) end
    check("riding up to the arena turns it into the test", away.routine.kind == "markers" and away.routine.task.opening == "A")
    local walks = 0
    for _ = 1, 200 do
        local leg = EqDressage.planLeg({ from = nil }, { x = 10, z = 0, markers = ours }, rng)
        if leg.gait == "walk" and math.sqrt((leg.marker.x - 10) ^ 2 + leg.marker.z ^ 2) > EqDressage.GO_MAX_DISTANCE.walk then walks = walks + 1 end
    end
    check("no long walks", walks == 0)
    local badHalt = 0
    for _ = 1, 300 do
        local from = ours[rng(#ours)]
        local nextTask = EqDressage.plan({ from = from }, { x = from.x, z = from.z, markers = ours }, "go", rng)
        if nextTask.kind == "halt" and not EqDressage.HALT_LETTERS[from.letter] then badHalt = badHalt + 1 end
    end
    check("halts only at the middle and end letters", badHalt == 0)
    local bounds = EqDressage.arenaBounds({ markers = ours }, ours[10])
    check("an arena's bounds come from its letters", bounds ~= nil and EqDressage.inArena(bounds, 10, 20)
        and EqDressage.inArena(bounds, 0.5, 39) and not EqDressage.inArena(bounds, -5, 20) and not EqDressage.inArena(bounds, 10, 45))
    local out = EqTraining.newSheet()
    local inside = { x = 10, z = 1, markers = ours }
    EqTraining.routineStep(out, "walk", nil, 50, false, one, inside)
    out.routine.task.opening = nil -- past X: the test proper
    local outside = { x = -10, z = 20, markers = ours }
    local outEvents = {}
    for _ = 1, 70 do
        local e = EqTraining.routineStep(out, "walk", nil, 50, false, one, outside)
        if e then outEvents[e] = (outEvents[e] or 0) + 1 end
    end
    local entering = EqTraining.newSheet()
    local enterEvents = {}
    for _ = 1, 100 do
        local e = EqTraining.routineStep(entering, "trot", nil, 50, false, one, { x = 10, z = -6, markers = ours })
        if e then enterEvents[e] = (enterEvents[e] or 0) + 1 end
    end
    check("no arena faults on the way in to A", entering.routine.active and (enterEvents.fault or 0) == 0)
    check("leaving the arena is a fault after a few seconds", out.routine.active and outEvents.fault == 1 and out.routine.faults == 1,
        string.format("faults %s", tostring(out.routine.faults)))
    check("a change from a walk to a canter is a flying change", EqDressage.changeKey({ gait = "canter", from = "walk" }) == "eq_dressage_flying"
        and EqDressage.changeKey({ gait = "trot", from = "walk" }) == "eq_dressage_change"
        and EqDressage.changeKey({ gait = "walk", from = "canter" }) == "eq_dressage_change")

    -- Ride a whole arena test: it ends at X with a halt and a big payoff.
    seed = 11
    local tested = EqTraining.newSheet()
    local tx, tz = 12, 3
    local spin = 0
    local finished, before = false, 0
    for _ = 1, 20000 do
        local r2 = tested.routine
        local task, move, steer = r2.task, "walk", nil
        if task ~= nil then
            if task.kind == "go" then
                move = r2.bonus ~= nil and r2.bonus.gait or task.gait
                local dx, dz = task.marker.x - tx, task.marker.z - tz
                local d = math.sqrt(dx * dx + dz * dz)
                local stepLen = math.min(d, SPEED[move] * 0.05)
                if d > 0 then tx, tz = tx + dx / d * stepLen, tz + dz / d * stepLen end
            elseif task.kind == "reverse" then move = "reverse"
            elseif task.kind == "turn" then move, steer = "halt", task.side
            elseif task.kind == "circle" then
                move, steer = "walk", task.side
                spin = spin + 0.03
                tx, tz = tx + math.sin(spin) * 0.09, tz + math.cos(spin) * 0.09
            else move = "halt" end
        end
        before = tested.focused.temperament
        if EqTraining.routineStep(tested, move, steer, 50, false, rng, { x = tx, z = tz, markers = ours }) == "test" then
            finished = true
            break
        end
    end
    check("a whole arena test ends in a halt at X", finished and math.abs(tx - 10) < 4 and math.abs(tz - 20) < 4,
        string.format("at %.1f, %.1f", tx, tz))
    check("finishing pays a big bonus and rests", tested.focused.temperament - before
        >= EqTraining.TEMPERAMENT_RATE * (EqTraining.ROUTINE_MAX - 1) * EqDressage.TEST_BONUS_SECONDS * 0.99
        and not tested.routine.active)
    EqTraining.routineStep(tested, "walk", nil, 50, false, one, { x = tx, z = tz, markers = ours })
    check("no new test straight after", not tested.routine.active)
    check("Riding Hall markers open with an ordinary leg", EqDressage.openingLeg(here) == nil)
end)()

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

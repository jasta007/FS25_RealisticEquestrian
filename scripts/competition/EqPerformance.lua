--[[
    EqPerformance.lua
    How a horse got round: a handful of stat checks per run, and the one line that sums them up.
    Pure functions with no game or RLRM calls, so they run headless.

    Each discipline in events.xml lists its checks: a stat, a difficulty and a weight (a show
    jumping round is a few agility checks that get harder, an easy speed check and a temperament
    check). A check's target sits in the tier's field (difficulty 0 a little below the weakest
    rival, 1 well up the field, see TARGET_*), so the same course is harder at Advanced than at
    Novice. The horse's stat,
    scaled by its condition on the day, is rolled against the target.

    The checks are where most of the day's luck comes from. A run that passes more checks than the
    horse usually would scores higher, one that fails more scores lower, and on average they come
    to nothing, so a horse's rating still decides what it can expect; the checks decide how this
    run went and give the story behind the placing.

    Before any of that, every event starts with an easy temperament check: getting the horse off
    the lorry, ready and to the start. Only a very fractious horse fails it, and is scratched.

    Eventing has no checks of its own: it runs the dressage, show jumping and cross country checks
    as three phases, each placed on its own, and the total decides the result.
]]

EqPerformance = {}

-- How sharply a check's pass chance turns around its target, in stat points.
EqPerformance.CHECK_SPREAD = 5
-- Where difficulty 0 and 1 sit in the tier's rival range (0 = weakest rival, 1 = strongest): the
-- easiest checks are below the whole field, the hardest one a horse in the top half passes about
-- half the time.
EqPerformance.TARGET_EASIEST = -0.2
EqPerformance.TARGET_HARDEST = 0.6
-- Share of the day's luck (the discipline's luck SD) that comes from the checks; the rest stays
-- plain luck. The two shares' squares add to 1, so the spread of results stays as it was.
EqPerformance.CHECK_LUCK = 0.8
EqPerformance.PLAIN_LUCK = 0.6
-- Before any event: can the horse be got off the lorry, tacked up and to the start? An easy
-- temperament check against a fixed level, whatever the tier; failing it scratches the horse.
EqPerformance.START_STAT = "temperament"
EqPerformance.START_TARGET = 8
-- Ways a fractious horse fails to start (eq_scratch_fractious_<n>), one picked at random.
EqPerformance.START_FAIL_TEXTS = 3
-- A run that fails at least this share of its check weight "struggled" with the whole course.
EqPerformance.STRUGGLED_SHARE = 0.6
-- A comeback (failed early, passed the "finish" check) only gets its line on the podium.
EqPerformance.COMEBACK_PLACE = 3


--- @param tier table
--- @param difficulty number 0..1
--- @return number target stat level a check at this difficulty asks for
function EqPerformance.target(tier, difficulty)
    local position = EqPerformance.TARGET_EASIEST + difficulty * (EqPerformance.TARGET_HARDEST - EqPerformance.TARGET_EASIEST)
    return tier.rivalMin + position * (tier.rivalMax - tier.rivalMin)
end


--- @param level number the horse's stat, scaled by its condition
--- @param target number
--- @return number chance 0..1
function EqPerformance.passChance(level, target)
    return 1 / (1 + math.exp(-(level - target) / EqPerformance.CHECK_SPREAD))
end


--- The check every event starts with (START_STAT against START_TARGET).
--- @param stats table stat -> level
--- @param condition number from EqCompetition.condition
--- @param rng table EqRandom
--- @return boolean started false when the horse could not be got to the start
--- @return number variant which eq_scratch_fractious_<n> text tells it, 1..START_FAIL_TEXTS
function EqPerformance.startCheck(stats, condition, rng)
    local chance = EqPerformance.passChance((stats[EqPerformance.START_STAT] or 0) * condition, EqPerformance.START_TARGET)
    local started = rng:next() < chance
    local variant = math.min(EqPerformance.START_FAIL_TEXTS, math.floor(rng:next() * EqPerformance.START_FAIL_TEXTS) + 1)
    return started, variant
end


--- Roll a discipline's checks.
--- @param checks table list of { stat, difficulty, weight, tag }
--- @param tier table
--- @param stats table stat -> level (a rival's rating for every stat)
--- @param condition number from EqCompetition.condition
--- @param rng table EqRandom
--- @return table results list of { check, passed, chance }
--- @return number swing how much better (+) or worse (-) the run went than the horse's usual,
---     about -1..1 with a spread of about 1 for an even match
function EqPerformance.roll(checks, tier, stats, condition, rng)
    local results, total, squares = {}, 0, 0
    for _, check in ipairs(checks) do
        local chance = EqPerformance.passChance((stats[check.stat] or 0) * condition, EqPerformance.target(tier, check.difficulty))
        local passed = rng:next() < chance
        table.insert(results, { check = check, passed = passed, chance = chance })
        total = total + check.weight * ((passed and 1 or 0) - chance)
        squares = squares + check.weight * check.weight
    end
    if squares == 0 then return results, 0 end
    -- Scaled so an even match (every chance 1/2) swings with a spread of 1.
    return results, total / math.sqrt(squares * 0.25)
end


--- A runner's score for one set of checks.
--- @param rating number
--- @param condition number
--- @param luck number the discipline's luck SD
--- @param swing number from roll
--- @param rng table EqRandom
--- @return number score
function EqPerformance.score(rating, condition, luck, swing, rng)
    return rating * condition * (1 + rng:normal(0, luck * EqPerformance.PLAIN_LUCK) + luck * EqPerformance.CHECK_LUCK * swing)
end


--- @param stats table|nil stat -> level
--- @param rating number
--- @return table stats the horse's stats, or the rating for every stat (simulated rivals)
function EqPerformance.statsOrFlat(stats, rating)
    if stats ~= nil then return stats end
    local flat = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do flat[stat] = rating end
    return flat
end


--- Run one entrant through an event: its checks (or eventing's phases) and its score.
--- @param discipline table
--- @param config table EqEventConfig
--- @param tier table
--- @param entrant table { rating, condition, stats (nil for a simulated rival), phaseRatings }
--- @param luck number the discipline's luck SD
--- @param rng table EqRandom
--- @return table run { score, checks, phases (eventing: list of { name, score, checks }) }
function EqPerformance.run(discipline, config, tier, entrant, luck, rng)
    local stats = EqPerformance.statsOrFlat(entrant.stats, entrant.rating)
    if discipline.phases == nil or #discipline.phases == 0 then
        local checks, swing = EqPerformance.roll(discipline.checks or {}, tier, stats, entrant.condition, rng)
        return { score = EqPerformance.score(entrant.rating, entrant.condition, luck, swing, rng), checks = checks }
    end

    local phases, total = {}, 0
    for _, name in ipairs(discipline.phases) do
        local phase = config.disciplineByName[name]
        local rating = entrant.phaseRatings ~= nil and entrant.phaseRatings[name] or entrant.rating
        local checks, swing = EqPerformance.roll(phase ~= nil and phase.checks or {}, tier, stats, entrant.condition, rng)
        local score = EqPerformance.score(rating, entrant.condition, luck, swing, rng)
        table.insert(phases, { name = name, score = score, checks = checks })
        total = total + score
    end
    return { score = total / #phases, checks = {}, phases = phases }
end


--- Each phase rating scaled so their average is the event's own rating: a horse is placed on
--- its phases, but what it can expect stays what its eventing rating says.
--- @param ratings table phase name -> rating for that discipline
--- @param rating number the horse's rating for the whole event
--- @return table ratings phase name -> scaled rating
function EqPerformance.scalePhases(ratings, rating)
    local sum, count = 0, 0
    for _, value in pairs(ratings) do
        sum, count = sum + value, count + 1
    end
    local scaled = {}
    local factor = (count > 0 and sum > 0) and rating / (sum / count) or 1
    for name, value in pairs(ratings) do scaled[name] = value * factor end
    return scaled
end


--- @param checks table results from roll
--- @return number failed share of the check weight failed, 0..1
local function failedShare(checks)
    local failed, total = 0, 0
    for _, result in ipairs(checks) do
        total = total + result.check.weight
        if not result.passed then failed = failed + result.check.weight end
    end
    return total > 0 and failed / total or 0
end
EqPerformance.failedShare = failedShare


--- The one thing worth saying about a run, as the end of a text key: "clean" when it passed
--- everything, "struggled" when it failed most of it, otherwise its biggest problem. That is the
--- failed check with the most weight (the harder one on a tie): "<stat>Many" when the horse
--- failed more than one check of that stat, else the check's tag ("hardest" for the hardest
--- fence alone), else the stat.
--- @param checks table results from roll
--- @return string issue
function EqPerformance.issue(checks)
    local worst, failedOfStat = nil, {}
    for _, result in ipairs(checks) do
        if not result.passed then
            local check = result.check
            failedOfStat[check.stat] = (failedOfStat[check.stat] or 0) + 1
            if worst == nil or check.weight > worst.weight
                or (check.weight == worst.weight and check.difficulty > worst.difficulty) then
                worst = check
            end
        end
    end
    if worst == nil then return "clean" end
    if failedShare(checks) >= EqPerformance.STRUGGLED_SHARE then return "struggled" end
    if failedOfStat[worst.stat] > 1 then return worst.stat .. "Many" end
    return worst.tag or worst.stat
end


--- Why an eliminated horse went out: a refusal when it failed a temperament check, else the
--- discipline's usual way out (a fall, pulled up).
--- @param checks table results from roll
--- @return string reason "elimRefusal" or "eliminated"
function EqPerformance.eliminationIssue(checks)
    for _, result in ipairs(checks) do
        if not result.passed and result.check.stat == "temperament" then return "elimRefusal" end
    end
    return "eliminated"
end


--- A horse that fell behind early but won the sprint for the line: it placed, passed its
--- "finish" check and failed at least one check before it.
--- @param checks table results from roll
--- @param place number|nil
--- @return boolean
function EqPerformance.isComeback(checks, place)
    if place == nil or place > EqPerformance.COMEBACK_PLACE then return false end
    local failedEarly = false
    for _, result in ipairs(checks) do
        if result.check.tag == "finish" then return result.passed and failedEarly end
        if not result.passed then failedEarly = true end
    end
    return false
end


--- The text key for a run's line.
--- @param discipline table
--- @param run table from EqPerformance.run
--- @param eliminated boolean
--- @param config table EqEventConfig, for eventing's phases
--- @param place number|nil where the horse finished, for the comeback line
--- @return string key eq_story_<story>_<issue>
function EqPerformance.storyKey(discipline, run, eliminated, config, place)
    if discipline.phases ~= nil and #discipline.phases > 0 then
        return EqPerformance.phasedStoryKey(discipline, run, eliminated, config)
    end
    local issue
    if eliminated then
        issue = discipline.refusalsOnly and "elimRefusal" or EqPerformance.eliminationIssue(run.checks)
    elseif EqPerformance.isComeback(run.checks, place) then
        issue = "comeback"
    else
        issue = EqPerformance.issue(run.checks)
    end
    return string.format("eq_story_%s_%s", discipline.story or discipline.name, issue)
end


--- Eventing: clean or struggled across the phases, else the worst phase's own line. Over three
--- phases a refusal costs marks but doesn't end the event; only a fall on the cross country
--- (the last phase) does.
--- @return string key
function EqPerformance.phasedStoryKey(discipline, run, eliminated, config)
    local all = {}
    for _, phase in ipairs(run.phases or {}) do
        for _, result in ipairs(phase.checks) do table.insert(all, result) end
    end
    local story = discipline.story or discipline.name
    if eliminated then return string.format("eq_story_%s_eliminated", story) end
    local overall = EqPerformance.issue(all)
    if overall == "clean" or overall == "struggled" then return string.format("eq_story_%s_%s", story, overall) end

    local worst, worstShare = nil, -1
    for _, phase in ipairs(run.phases) do
        local share = failedShare(phase.checks)
        if share > worstShare then worst, worstShare = phase, share end
    end
    return EqPerformance.storyKey(config.disciplineByName[worst.name], worst, false, config)
end


--- Every text key a discipline's lines can use, for the translation tests.
--- @param discipline table
--- @param config table
--- @return table keys
function EqPerformance.storyKeys(discipline, config)
    local story = discipline.story or discipline.name
    local keys = {
        string.format("eq_story_%s_clean", story),
        string.format("eq_story_%s_struggled", story),
    }
    -- Dressage only ends early when the horse refuses to go on: no falls, no pulling up.
    local canEliminate = (discipline.elimination or 0) > 0
    if canEliminate and not discipline.refusalsOnly then table.insert(keys, string.format("eq_story_%s_eliminated", story)) end
    if discipline.phases ~= nil and #discipline.phases > 0 then
        for _, name in ipairs(discipline.phases) do
            for _, key in ipairs(EqPerformance.storyKeys(config.disciplineByName[name], config)) do table.insert(keys, key) end
        end
        return keys
    end

    local ofStat = {}
    for _, check in ipairs(discipline.checks or {}) do
        ofStat[check.stat] = (ofStat[check.stat] or 0) + 1
        if check.tag == "finish" then table.insert(keys, string.format("eq_story_%s_comeback", story)) end
        table.insert(keys, string.format("eq_story_%s_%s", story, check.tag or check.stat))
    end
    for stat, count in pairs(ofStat) do
        if count > 1 then table.insert(keys, string.format("eq_story_%s_%sMany", story, stat)) end
        if stat == "temperament" and canEliminate then table.insert(keys, string.format("eq_story_%s_elimRefusal", story)) end
    end
    return keys
end


--- Places within each eventing phase.
--- @param runners table list with .run (from EqPerformance.run)
--- @param phases table phase names
--- @return table places runner -> { phase name -> place }
function EqPerformance.phasePlaces(runners, phases)
    local places = {}
    for _, runner in ipairs(runners) do places[runner] = {} end
    for i, name in ipairs(phases) do
        local order = {}
        for _, runner in ipairs(runners) do
            if runner.run ~= nil and runner.run.phases ~= nil and runner.run.phases[i] ~= nil then table.insert(order, runner) end
        end
        table.sort(order, function(a, b) return a.run.phases[i].score > b.run.phases[i].score end)
        for place, runner in ipairs(order) do places[runner][name] = place end
    end
    return places
end

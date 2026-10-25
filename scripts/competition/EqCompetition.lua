--[[
    EqCompetition.lua
    The competition maths: pure functions with no game or RLRM calls, so they run headless.

    - A horse's discipline rating (0-100) is the weighted average of its trained stats, with the
      going moving weight between stats on outdoor courses. All-round tests (cross country,
      eventing, steeplechase) take part of the rating from the weakest weighted stat, so a hole
      in a horse costs it there; specialists shine in the one-discipline events.
    - On the day, the rating is scaled by condition (RLRM's fitness and health) and a little luck.
    - Simulated rivals fill the rest of the field with ratings drawn from the tier's range.
    - The top three share the prize pool 50/30/20.
]]

EqCompetition = {}

EqCompetition.PRIZE_SHARES = { 0.5, 0.3, 0.2 }

-- Spread of the day's luck around a horse's rating; racing is a little less predictable.
EqCompetition.LUCK_SD = 0.06
EqCompetition.RACING_LUCK_SD = 0.09

EqCompetition.KIND_ROUND = "round"
EqCompetition.KIND_MONTH = "month"


--- @param discipline table
--- @param going table|nil { modifiers }, ignored indoors
--- @return table weights stat -> weight after the going
function EqCompetition.effectiveWeights(discipline, going)
    local weights = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local modifier = (discipline.outdoor and going ~= nil) and going.modifiers[stat] or 1
        weights[stat] = discipline.weights[stat] * modifier
    end
    return weights
end


--- @param trained table stat -> trained level
--- @param discipline table
--- @param going table|nil
--- @return number rating 0..100
function EqCompetition.rating(trained, discipline, going)
    local weights = EqCompetition.effectiveWeights(discipline, going)
    local total, weightSum, weakest = 0, 0, math.huge

    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local weight = weights[stat]
        if weight > 0 then
            local level = trained[stat] or 0
            total = total + weight * level
            weightSum = weightSum + weight
            weakest = math.min(weakest, level)
        end
    end

    if weightSum == 0 then return 0 end
    local average = total / weightSum
    return average * (1 - discipline.weakestShare) + weakest * discipline.weakestShare
end


--- How RLRM's day-to-day condition scales performance.
--- @param fitness number 0..100 (RLRM's horse fitness)
--- @param health number 0..100
--- @return number factor about 0.6..1
function EqCompetition.condition(fitness, health)
    local fitnessFactor = 0.75 + 0.25 * EqStats.clamp((fitness or 0) / 100, 0, 1)
    local healthFactor = 1
    if (health or 100) < 75 then healthFactor = 0.8 + 0.2 * EqStats.clamp((health or 0) / 75, 0, 1) end
    return fitnessFactor * healthFactor
end


--- @param tier table
--- @param ageMonths number
--- @param rating number the horse's rating for this event
--- @return boolean ok
--- @return string|nil reason "tooYoung", "tooOld", "ratingLow" or "ratingHigh"
function EqCompetition.canEnter(tier, ageMonths, rating)
    if ageMonths < tier.minAge then return false, "tooYoung" end
    if tier.maxAge > 0 and ageMonths > tier.maxAge then return false, "tooOld" end
    if rating < tier.minRating then return false, "ratingLow" end
    if rating > tier.maxRating then return false, "ratingHigh" end
    return true
end


--- A horse's chance of a top-three place, for the Events tab: the event run many times
--- against fresh rivals, with the chance of being eliminated taken off.
--- @param event table { discipline, tier, prize }
--- @param config table EqEventConfig
--- @param rating number
--- @param condition number from EqCompetition.condition
--- @param eliminationChance number 0..1
--- @param rng table EqRandom
--- @param runs number|nil default 200
--- @return number chance 0..1
function EqCompetition.podiumChance(event, config, rating, condition, eliminationChance, rng, runs)
    runs = runs or 200
    local podiums = 0
    local entrants = { { key = "horse", rating = rating, condition = condition } }
    for _ = 1, runs do
        for _, runner in ipairs(EqCompetition.run(event, config, entrants, rng)) do
            if runner.key ~= nil then
                if runner.place <= #EqCompetition.PRIZE_SHARES then podiums = podiums + 1 end
                break
            end
        end
    end
    return podiums / runs * (1 - (eliminationChance or 0))
end


-- Words for a podium chance, best first.
EqCompetition.SUCCESS_BANDS = {
    { from = 0.6, name = "favourite" },
    { from = 0.35, name = "contender" },
    { from = 0.12, name = "outsider" },
    { from = -math.huge, name = "longShot" },
}


--- @param chance number from podiumChance
--- @return string name a SUCCESS_BANDS name
function EqCompetition.successBand(chance)
    for _, band in ipairs(EqCompetition.SUCCESS_BANDS) do
        if chance >= band.from then return band.name end
    end
end


--- @param items table list with a .chance each
--- @param rng table EqRandom
--- @return table item
local function pickWeighted(items, rng)
    local total = 0
    for _, item in ipairs(items) do total = total + item.chance end
    local roll = rng:uniform(0, total)
    for _, item in ipairs(items) do
        roll = roll - item.chance
        if roll <= 0 then return item end
    end
    return items[#items]
end


--- @param items table non-empty list
--- @param rng table EqRandom
--- @return any item one item, each as likely as the others
local function pickAny(items, rng)
    return items[math.min(#items, math.floor(rng:next() * #items) + 1)]
end


--- @param config table EqEventConfig
--- @param from string|nil region
--- @param to string|nil region
--- @return string distance "local", "near" or "far" (local when either is unknown)
function EqCompetition.distanceBetween(config, from, to)
    if from == nil or to == nil or from == to then return "local" end
    return config.routes ~= nil and config.routes[from .. ">" .. to] or "far"
end


--- How likely each region is to host a named event: each distance's chance, split evenly
--- between the regions at that distance from home.
--- @param config table EqEventConfig
--- @param home string|nil the player's home region; nil weighs every region the same
--- @return table list of { region, chance }
function EqCompetition.regionWeights(config, home)
    local atDistance = {}
    for _, region in ipairs(config.regions or {}) do
        local distance = EqCompetition.distanceBetween(config, home, region.name)
        atDistance[distance] = (atDistance[distance] or 0) + 1
    end
    local weights = {}
    for _, region in ipairs(config.regions or {}) do
        local distance = EqCompetition.distanceBetween(config, home, region.name)
        local entry = home ~= nil and config.distances ~= nil and config.distances[distance] or nil
        local chance = entry ~= nil and entry.chance / atDistance[distance] or 1
        if chance > 0 then table.insert(weights, { region = region, chance = chance }) end
    end
    return weights
end


-- An event some farm's horse could enter is this many times as likely to be drawn.
EqCompetition.ENTERABLE_WEIGHT = 3
-- Each further run of the same tier in the same discipline is this much less likely.
EqCompetition.COPY_WEIGHT = 0.4


--- A whole number from lo to hi, each as likely.
--- @param rng table EqRandom
--- @param lo number
--- @param hi number
--- @return number
function EqCompetition.drawCount(rng, lo, hi)
    lo, hi = math.floor(lo), math.floor(hi)
    if hi <= lo then return math.max(0, lo) end
    return math.max(0, math.min(hi, lo + math.floor(rng:next() * (hi - lo + 1))))
end


--- Draw the events for one round: a set number of them, picked by each tier's and discipline's
--- chance, favouring events the players' horses could enter.
--- @param config table EqEventConfig
--- @param rng table EqRandom
--- @param kind string KIND_ROUND (the every-round tiers) or KIND_MONTH (the monthly tiers)
--- @param racingEnabled boolean
--- @param home string|nil the player's home region: nearer venues are drawn more often
--- @param options table|nil { count = events to draw (default: a number from the schedule's
---     range for the kind), enterable = function(disciplineName, tierName) -> true when some
---     farm's horse could enter it; then at least half the events drawn are ones it could enter,
---     when there are enough of them }
--- @return table events list of { discipline, tier, going, fee, prize, kind, venue, region }
function EqCompetition.drawSchedule(config, rng, kind, racingEnabled, home, options)
    options = options or {}
    local events = {}
    local wantMonthly = kind == EqCompetition.KIND_MONTH
    local regionWeights = EqCompetition.regionWeights(config, home)

    local count = options.count
    if count == nil then
        if wantMonthly then
            count = EqCompetition.drawCount(rng, config.monthlyMin or 1, config.monthlyMax or 2)
        else
            count = EqCompetition.drawCount(rng, config.eventsMin or 3, config.eventsMax or 8)
        end
    end

    local candidates, enterableKinds = {}, 0
    for _, discipline in ipairs(config.disciplines) do
        if racingEnabled or not discipline.racing then
            for _, tier in ipairs(config.tiers) do
                if tier.monthly == wantMonthly then
                    local enterable = options.enterable ~= nil and options.enterable(discipline.name, tier.name) == true
                    if enterable then enterableKinds = enterableKinds + 1 end
                    table.insert(candidates, { discipline = discipline, tier = tier, copies = 0, enterable = enterable,
                        weight = tier.chance * (discipline.chance or 1) })
                end
            end
        end
    end

    local wantEnterable = enterableKinds > 0 and math.ceil(count / 2) or 0
    local enterableDrawn = 0
    for drawn = 1, count do
        -- Keep the last places for enterable events when too few have come up so far.
        local onlyEnterable = wantEnterable - enterableDrawn >= count - drawn + 1
        local pool = {}
        for _, candidate in ipairs(candidates) do
            if candidate.copies < config.copiesMax and (candidate.enterable or not onlyEnterable) then
                local chance = candidate.weight * EqCompetition.COPY_WEIGHT ^ candidate.copies
                    * (candidate.enterable and EqCompetition.ENTERABLE_WEIGHT or 1)
                if chance > 0 then table.insert(pool, { candidate = candidate, chance = chance }) end
            end
        end
        if #pool == 0 then break end

        local candidate = pickWeighted(pool, rng).candidate
        candidate.copies = candidate.copies + 1
        if candidate.enterable then enterableDrawn = enterableDrawn + 1 end
        local discipline, tier = candidate.discipline, candidate.tier
        local spread = config.priceSpread
        local priceFactor = 1 + rng:uniform(-spread, spread)
        local going = discipline.outdoor and #config.goings > 0 and pickWeighted(config.goings, rng) or nil
        local venue, region = nil, nil
        if tier.venue and #regionWeights > 0 then
            local pick = pickWeighted(regionWeights, rng).region
            venue, region = pickAny(pick.venues, rng), pick.name
        end
        table.insert(events, {
            discipline = discipline.name,
            tier = tier.name,
            going = going ~= nil and going.name or nil,
            fee = math.floor(tier.fee * priceFactor / 10 + 0.5) * 10,
            -- A richer purse costs more to enter, but not in proportion.
            prize = math.floor(tier.prize * (priceFactor * priceFactor) / 50 + 0.5) * 50,
            kind = kind,
            venue = venue,
            region = region,
        })
    end

    return events
end


--- Run one event.
--- @param event table { discipline, tier, going, prize }
--- @param config table EqEventConfig
--- @param entrants table list of { key, rating, condition }
--- @param rng table EqRandom
--- @param field number|nil runners in total, default the tier's field (fewer when some of the
---     field was eliminated before the scoring)
--- @return table results list sorted by place: { key or nil for a rival, place, score, prize }
function EqCompetition.run(event, config, entrants, rng, field)
    local discipline = config.disciplineByName[event.discipline]
    local tier = config.tierByName[event.tier]
    local luck = discipline.racing and EqCompetition.RACING_LUCK_SD or EqCompetition.LUCK_SD

    local runners = {}
    for _, entrant in ipairs(entrants) do
        table.insert(runners, {
            key = entrant.key,
            score = entrant.rating * entrant.condition * (1 + rng:normal(0, luck)),
        })
    end

    for _ = #entrants + 1, field or tier.field do
        local rating = rng:uniform(tier.rivalMin, tier.rivalMax)
        local condition = rng:uniform(0.85, 1)
        table.insert(runners, { score = rating * condition * (1 + rng:normal(0, luck)) })
    end

    table.sort(runners, function(a, b) return a.score > b.score end)

    for place, runner in ipairs(runners) do
        runner.place = place
        local share = EqCompetition.PRIZE_SHARES[place]
        runner.prize = share ~= nil and math.floor(event.prize * share + 0.5) or 0
    end

    return runners
end

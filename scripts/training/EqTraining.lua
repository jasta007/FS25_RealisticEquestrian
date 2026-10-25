--[[
    EqTraining.lua
    The training maths: pure functions with no game or RLRM calls, so they run headless.

    A day's work comes from two places:
    - The player's own riding. EqTrainingHooks records milliseconds spent in each gait and
      jumps taken into a "sheet" per horse. Each gait trains a different mix of stats.
    - Staff. Whatever share of RLRM's riding value the player's sheet does not explain was put
      there by someone else: the base game's animal worker, or RLRM's herdsman horse-care rule.
      Staff train to the horse's focus profile and stop at STAFF_CAP of each ceiling.

    Stamina and speed are focused work. Most of what they learn comes from how the horse is
    worked, not how long: an exertion meter (a short-term one, separate from the riding bar, which
    is the day's energy) rises in canter and gallop and falls at slower gaits and at a halt.
    Stamina comes from runs (full after RUN_FULL seconds) that hold the meter high but not too high; speed comes from
    galloping while the meter is low, so the best speed work is sprints with rests between. Just
    riding the gaits trains them at UNFOCUSED_SHARE of the gait weights below.

    Each stat closes a share of the gap to its cap every month (scaled to the day with the
    game's timeAdjustment), so gains slow as a horse nears its ceiling. Idle horses fade.
    The farm's horse facilities (EqFacility.boosts) and what the horse is fed (EqFeed.dietBoost)
    speed that up per stat, adding together; riding inside a facility speeds the player's own work
    up more. They never add work.
]]

EqTraining = {}

-- Effort each gait gives per full day of training (TRAINING_FULL_MS in that gait), by stat.
EqTraining.GAIT_WEIGHTS = {
    walk = { temperament = 1.0, stamina = 0.3 },
    trot = { temperament = 0.6, stamina = 0.6, agility = 0.3 },
    canter = { stamina = 0.8, agility = 0.8, temperament = 0.3 },
    gallop = { speed = 1.0, stamina = 0.8 },
    -- Backing up is slow, fiddly schooling: a little of it does a lot for balance and manners.
    reverse = { agility = 2.0, temperament = 2.0 },
}

-- Stats trained by focused work (see step); their gait weights count at UNFOCUSED_SHARE.
EqTraining.UNFOCUSED_SHARE = { stamina = 0.1, speed = 0.1 }

-- The most effort a day can give each stat. Good focused work goes past the old full day (1).
EqTraining.EFFORT_CAP = { stamina = 2, speed = 2, agility = 1, temperament = 1 }

-- Exertion meter (0-100) change per second, by gait. "halt" is standing still. Canter is
-- worked out in exertionRate: it levels off rather than climbing for ever.
EqTraining.TIREDNESS_RATE = { halt = -3, walk = -3, reverse = -1, trot = -0.8, canter = 0, gallop = 3 }

-- A canter pulls exertion toward a level set by the horse's trained stamina, at CANTER_PULL per
-- second from zero: 70 for an unfit horse, 85 at stamina 50 (the top of the zone), 100 at 100.
-- So a fit horse can canter in the zone for as long as it likes.
EqTraining.CANTER_PULL = 3
EqTraining.CANTER_LEVEL_BASE = 70
EqTraining.CANTER_LEVEL_PER_STAMINA = 0.3

-- A gallop tires a fit horse more slowly: GALLOP_FIT_SHARE of the rate at stamina 100,
-- GALLOP_UNFIT_SHARE at 0.
EqTraining.GALLOP_UNFIT_SHARE = 1.25
EqTraining.GALLOP_FIT_SHARE = 0.75

-- A run is time spent at canter or gallop. Trotting holds it; walking, backing up or being
-- knocked to a halt wear it down slowly rather than ending it, since FS horses stop easily.
EqTraining.RUN_RATE = { halt = -3, walk = -3, reverse = -3, trot = 0, canter = 1, gallop = 1 }
EqTraining.RUN_START = 0
EqTraining.RUN_FULL = 15

-- Stamina effort per second in each gait at the best tiredness and a long run.
EqTraining.STAMINA_RATE = { trot = 0.0065, canter = 0.0165, gallop = 0.021 }
-- Stamina zone: no stamina work below ZONE_FROM, building to full at ZONE_LOW, full up to
-- ZONE_HIGH, then falling to ZONE_BLOWN_SHARE at 100.
EqTraining.ZONE_FROM = 55
EqTraining.ZONE_LOW = 68
EqTraining.ZONE_HIGH = 85
EqTraining.ZONE_BLOWN_SHARE = 0.2

-- Speed effort per second at a gallop while fresh: full up to FRESH_UNTIL, falling to
-- STALE_SHARE at STALE_FROM and above.
EqTraining.SPEED_RATE = 0.02
EqTraining.FRESH_UNTIL = 25
EqTraining.STALE_FROM = 55
EqTraining.STALE_SHARE = 0

-- How fast each gait fills the riding bar. The base game's factors (Rideable:updateRiding),
-- except backing up: the base game counts it like a walk, and EqTrainingHooks tops it up to
-- this, because it is hard mental work: it tires a horse nearly as fast as a gallop.
EqTraining.GAIT_SPEED_FACTOR = { reverse = 2.5, walk = 1, trot = 1, canter = 2, gallop = 3 }

-- What the base game already credits for backing up; the rest of reverse's factor is ours.
EqTraining.BASE_REVERSE_FACTOR = 1

-- What staff work on, per focus. Set with the eqFocus console command for now.
EqTraining.FOCUS = {
    balanced = { stamina = 0.6, speed = 0.6, agility = 0.6, temperament = 0.6 },
    showJumping = { stamina = 0.3, speed = 0.4, agility = 1.0, temperament = 0.7 },
    dressage = { stamina = 0.2, speed = 0.2, agility = 0.7, temperament = 1.0 },
    crossCountry = { stamina = 1.0, speed = 0.6, agility = 0.6, temperament = 0.5 },
    racing = { stamina = 0.9, speed = 1.0, agility = 0.1, temperament = 0.1 },
}

EqTraining.FOCUS_ORDER = { "balanced", "showJumping", "dressage", "crossCountry", "racing" }


--- @return table sheet One horse's riding since its last daily tick
function EqTraining.newSheet()
    return { ms = { reverse = 0, walk = 0, trot = 0, canter = 0, gallop = 0 }, jumps = 0, inside = {},
        tiredness = 0, run = 0, focused = { stamina = 0, speed = 0 }, quality = { stamina = 0, speed = 0 } }
end


--- How well stamina is training at this tiredness and run length.
--- @param tiredness number 0-100
--- @param run number seconds
--- @return number share 0..1 of STAMINA_RATE
function EqTraining.staminaQuality(tiredness, run)
    local zone
    if tiredness < EqTraining.ZONE_LOW then
        zone = EqStats.clamp((tiredness - EqTraining.ZONE_FROM) / (EqTraining.ZONE_LOW - EqTraining.ZONE_FROM), 0, 1)
    elseif tiredness <= EqTraining.ZONE_HIGH then
        zone = 1
    else
        local over = (tiredness - EqTraining.ZONE_HIGH) / (100 - EqTraining.ZONE_HIGH)
        zone = 1 - over * (1 - EqTraining.ZONE_BLOWN_SHARE)
    end
    local length = EqStats.clamp((run - EqTraining.RUN_START) / (EqTraining.RUN_FULL - EqTraining.RUN_START), 0, 1)
    return zone * length
end


--- How well a gallop trains speed at this tiredness.
--- @param tiredness number 0-100
--- @return number share 0..1 of SPEED_RATE
function EqTraining.speedQuality(tiredness)
    if tiredness <= EqTraining.FRESH_UNTIL then return 1 end
    local stale = EqStats.clamp((tiredness - EqTraining.FRESH_UNTIL) / (EqTraining.STALE_FROM - EqTraining.FRESH_UNTIL), 0, 1)
    return 1 - stale * (1 - EqTraining.STALE_SHARE)
end


--- How fast exertion changes in a gait.
--- @param gait string
--- @param tiredness number 0-100
--- @param stamina number|nil the horse's trained stamina (50 when nil)
--- @return number|nil per second; nil for an unknown gait
function EqTraining.exertionRate(gait, tiredness, stamina)
    local rate = EqTraining.TIREDNESS_RATE[gait]
    if rate == nil then return nil end
    local fitness = EqStats.clamp((stamina or 50) / 100, 0, 1)
    if gait == "canter" then
        local level = EqTraining.CANTER_LEVEL_BASE + EqTraining.CANTER_LEVEL_PER_STAMINA * fitness * 100
        return EqTraining.CANTER_PULL * (1 - tiredness / level)
    elseif gait == "gallop" then
        return rate * (EqTraining.GALLOP_UNFIT_SHARE + (EqTraining.GALLOP_FIT_SHARE - EqTraining.GALLOP_UNFIT_SHARE) * fitness)
    end
    return rate
end


--- One frame of riding for the meters and focused work.
--- @param sheet table
--- @param gait string halt, reverse, walk, trot, canter or gallop
--- @param dt number milliseconds
--- @param worn boolean true when the riding bar is full: the meters move, nothing trains
--- @param stamina number|nil the horse's trained stamina, which slows how fast it tires
function EqTraining.step(sheet, gait, dt, worn, stamina)
    local rate = EqTraining.exertionRate(gait, sheet.tiredness, stamina)
    if rate == nil or dt <= 0 then return end
    local seconds = dt / 1000
    sheet.tiredness = EqStats.clamp(sheet.tiredness + rate * seconds, 0, 100)
    sheet.run = math.max(0, sheet.run + EqTraining.RUN_RATE[gait] * seconds)

    local stamina = EqTraining.STAMINA_RATE[gait] ~= nil and EqTraining.staminaQuality(sheet.tiredness, sheet.run) or 0
    local speed = gait == "gallop" and EqTraining.speedQuality(sheet.tiredness) or 0
    sheet.quality.stamina, sheet.quality.speed = stamina, speed
    if worn then
        sheet.quality.stamina, sheet.quality.speed = 0, 0
        return
    end
    sheet.focused.stamina = sheet.focused.stamina + (EqTraining.STAMINA_RATE[gait] or 0) * stamina * seconds
    sheet.focused.speed = sheet.focused.speed + EqTraining.SPEED_RATE * speed * seconds
end


--- Word for the tiredness meter, for the riding HUD.
--- @param tiredness number 0-100
--- @return string band fresh, warm, zone or blown
function EqTraining.tirednessBand(tiredness)
    if tiredness < EqTraining.ZONE_FROM then return "fresh" end
    if tiredness < EqTraining.ZONE_LOW then return "warm" end
    if tiredness <= EqTraining.ZONE_HIGH then return "zone" end
    return "blown"
end


--- Word for the tiredness meter in the Speed view.
--- @param tiredness number 0-100
--- @return string band fresh, tiring or stale
function EqTraining.sprintBand(tiredness)
    if tiredness <= EqTraining.FRESH_UNTIL then return "fresh" end
    if tiredness < EqTraining.STALE_FROM then return "tiring" end
    return "stale"
end


--- Word for how fast a stat is training this moment.
--- @param quality number 0..1
--- @return string|nil band fast, steady or slow; nil when it is not training
function EqTraining.qualityBand(quality)
    if quality >= 0.75 then return "fast" end
    if quality >= 0.35 then return "steady" end
    if quality > 0 then return "slow" end
    return nil
end


--- Time out of the saddle rests the horse like standing still.
--- @param sheet table
--- @param ms number milliseconds since the sheet was last ridden
function EqTraining.rest(sheet, ms)
    if ms <= 0 then return end
    local seconds = ms / 1000
    sheet.tiredness = EqStats.clamp(sheet.tiredness + EqTraining.TIREDNESS_RATE.halt * seconds, 0, 100)
    sheet.run = math.max(0, sheet.run + EqTraining.RUN_RATE.halt * seconds)
    sheet.quality.stamina, sheet.quality.speed = 0, 0
end


--- @param sheet table
--- @param kind string an EqFacility kind name the horse is being ridden inside
--- @param dt number milliseconds
function EqTraining.addInside(sheet, kind, dt)
    if dt <= 0 then return end
    sheet.inside[kind] = (sheet.inside[kind] or 0) + dt
end


--- @param sheet table
--- @param gait string reverse, walk, trot, canter or gallop; anything else is ignored
--- @param dt number milliseconds
function EqTraining.addRiding(sheet, gait, dt)
    if sheet.ms[gait] == nil or dt <= 0 then return end
    sheet.ms[gait] = sheet.ms[gait] + dt
end


--- Extra riding points for backing up, on top of what the base game credits.
--- @param timer number weighted milliseconds carried over from earlier frames
--- @param dt number milliseconds spent backing up this frame
--- @param fullMs number weighted milliseconds that fill riding from 0 to 100
--- @return number points whole points to add, number timer what is carried to the next frame
function EqTraining.reverseExtraRiding(timer, dt, fullMs)
    local extra = EqTraining.GAIT_SPEED_FACTOR.reverse - EqTraining.BASE_REVERSE_FACTOR
    timer = (timer or 0) + math.max(dt, 0) * extra
    local perPoint = fullMs / 100
    local points = math.floor(timer / perPoint)
    return points, timer - points * perPoint
end


--- @param sheet table
function EqTraining.addJump(sheet)
    sheet.jumps = sheet.jumps + 1
end


--- Riding points (0-100) the base game credited for this sheet, so the rest of RLRM's riding
--- value can be put down to staff.
--- @param sheet table|nil
--- @return number points
function EqTraining.playerRidingPoints(sheet)
    if sheet == nil then return 0 end
    local weighted = 0
    for gait, ms in pairs(sheet.ms) do
        weighted = weighted + ms * EqTraining.GAIT_SPEED_FACTOR[gait]
    end
    return math.min(100, weighted / EqConstants.RIDING_FULL_MS * 100)
end


--- @param sheet table|nil
--- @return table effort stat -> 0..EFFORT_CAP
function EqTraining.playerEffort(sheet)
    local effort = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do effort[stat] = 0 end
    if sheet == nil then return effort end

    for gait, ms in pairs(sheet.ms) do
        local share = ms / EqConstants.TRAINING_FULL_MS
        for stat, weight in pairs(EqTraining.GAIT_WEIGHTS[gait]) do
            effort[stat] = effort[stat] + share * weight * (EqTraining.UNFOCUSED_SHARE[stat] or 1)
        end
    end
    for stat, value in pairs(sheet.focused or {}) do effort[stat] = effort[stat] + value end
    effort.agility = effort.agility + sheet.jumps * EqConstants.JUMP_AGILITY
    effort.temperament = effort.temperament + sheet.jumps * EqConstants.JUMP_TEMPERAMENT

    for _, stat in ipairs(EqConstants.STAT_KEYS) do effort[stat] = EqStats.clamp(effort[stat], 0, EqTraining.EFFORT_CAP[stat]) end
    return effort
end


--- @param riding number RLRM's riding value (0-100) at the day's end
--- @param playerPoints number from playerRidingPoints
--- @param focus string a key of EqTraining.FOCUS
--- @param groomed boolean
--- @return table effort stat -> 0..1
function EqTraining.staffEffort(riding, playerPoints, focus, groomed)
    local share = EqStats.clamp(((riding or 0) - playerPoints) / 100, 0, 1)
    local profile = EqTraining.FOCUS[focus] or EqTraining.FOCUS.balanced

    local effort = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do effort[stat] = share * profile[stat] end
    if groomed then
        effort.temperament = math.min(1, effort.temperament + EqConstants.GROOMED_TEMPERAMENT)
    end
    return effort
end


--- Points gained toward a cap in one day.
--- @param level number
--- @param cap number
--- @param monthly number percent of the gap closed per month at full effort
--- @param effort number 0..1
--- @param ageFactor number
--- @param timeAdjustment number share of a month this day is
--- @return number gain
function EqTraining.gain(level, cap, monthly, effort, ageFactor, timeAdjustment)
    if effort <= 0 or level >= cap then return 0 end
    local share = math.min(1, monthly / 100 * effort * ageFactor * timeAdjustment)
    return (cap - level) * share
end


--- Lower a level by loss, but never below floor, and never raise it to meet the floor.
local function fadeToward(level, loss, floor)
    if level <= floor then return level end
    return math.max(floor, level - loss)
end


--- Apply one day of training to a record.
--- @param record table EqHorseRecord (uses trained, focus, idleDays)
--- @param ceilings table stat -> ceiling
--- @param day table { sheet, riding, dirt, ageMonths, timeAdjustment, facilityOwned, facilityRidden,
---     feedBoost, rate }; each boost table is stat -> share (EqFacility.boosts, EqFeed.dietBoost), or nil;
---     rate is the Training rate setting (1 when nil)
--- @return table deltas stat -> change, for logging
--- @return table detail why: { player, staff (effort stat -> 0..1), groomed, ageFactor, idleDays,
---     fading, old, stats = stat -> { fromPlayer, fromStaff, faded, aged } } for EqStatLog
function EqTraining.applyDay(record, ceilings, day)
    local timeAdjustment = day.timeAdjustment or 1
    local rate = day.rate or 1
    local ageFactor = EqStats.ageTrainingFactor(day.ageMonths or 0)
    local groomed = day.dirt ~= nil and day.dirt <= EqConstants.GROOMED_DIRT

    local player = EqTraining.playerEffort(day.sheet)
    local staff = EqTraining.staffEffort(day.riding, EqTraining.playerRidingPoints(day.sheet), record.focus, groomed)

    local worked = false
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if player[stat] > 0 or staff[stat] > 0 then worked = true end
    end
    record.idleDays = worked and 0 or (record.idleDays or 0) + 1
    local fading = record.idleDays >= EqConstants.FADE_GRACE_DAYS
        and record.idleDays * timeAdjustment >= EqConstants.FADE_GRACE_MONTHS
    local old = (day.ageMonths or 0) > EqConstants.AGE_DECLINE

    local deltas = {}
    local detail = { player = player, staff = staff, groomed = groomed, ageFactor = ageFactor,
        idleDays = record.idleDays, fading = fading, old = old, stats = {} }
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local ceiling = ceilings[stat]
        local before = record.trained[stat] or 0
        local level = before
        local owned = day.facilityOwned ~= nil and day.facilityOwned[stat] or 0
        local ridden = day.facilityRidden ~= nil and day.facilityRidden[stat] or 0
        local fed = day.feedBoost ~= nil and day.feedBoost[stat] or 0
        local monthly = EqConstants.TRAIN_MONTHLY[stat] * (1 + owned + fed) * rate
        local monthlyRidden = EqConstants.TRAIN_MONTHLY[stat] * (1 + owned + fed + ridden) * rate

        local fromPlayer = EqTraining.gain(level, ceiling, monthlyRidden, player[stat], ageFactor, timeAdjustment)
        local fromStaff = EqTraining.gain(level, ceiling * EqConstants.STAFF_CAP, monthly, staff[stat], ageFactor, timeAdjustment)
        level = level + math.max(fromPlayer, fromStaff)

        local trainedTo = level
        if fading then
            level = fadeToward(level, EqConstants.FADE_MONTHLY[stat] * timeAdjustment, ceiling * EqConstants.FADE_FLOOR)
        end
        local fadedTo = level
        if old then
            level = fadeToward(level, EqConstants.OLD_DECLINE_MONTHLY * timeAdjustment, ceiling * EqConstants.OLD_FLOOR)
        end

        record.trained[stat] = EqStats.clamp(level, 0, ceiling)
        deltas[stat] = record.trained[stat] - before
        detail.stats[stat] = { fromPlayer = fromPlayer, fromStaff = fromStaff, faded = fadedTo - trainedTo,
            aged = level - fadedTo }
    end

    return deltas, detail
end


-- Words for how much an event would teach a horse, best first.
EqTraining.BENEFIT_BANDS = {
    { from = 0.5, name = "high" },
    { from = 0.25, name = "medium" },
    { from = 0.08, name = "low" },
    { from = -math.huge, name = "none" },
}


--- How much an event would teach a horse, for the Events tab: the room left below staff level in
--- the discipline's stats, weighted like the boost, times the age factor and the tier's boost.
--- @param trained table
--- @param ceilings table stat -> ceiling (the shown ones, so this tells nothing the words don't)
--- @param weights table stat -> discipline weight
--- @param ageMonths number
--- @param boost number|nil the tier's share of a full day (1 for a young horse class)
--- @return number benefit 0..1
--- @return string band a BENEFIT_BANDS name
function EqTraining.boostBenefit(trained, ceilings, weights, ageMonths, boost)
    local room, total = 0, 0
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local weight = weights[stat] or 0
        local cap = ceilings[stat] * EqConstants.STAFF_CAP
        if weight > 0 and cap > 0 then
            room = room + weight * EqStats.clamp((cap - (trained[stat] or 0)) / cap, 0, 1)
            total = total + weight
        end
    end
    local benefit = total > 0 and room / total * EqStats.ageTrainingFactor(ageMonths) * (boost or 1) or 0
    for _, band in ipairs(EqTraining.BENEFIT_BANDS) do
        if benefit >= band.from then return benefit, band.name end
    end
end


--- An event's training boost: a share of a full day's work spread over the discipline's stats,
--- counted at staff level (it is not the player's own riding).
--- @param record table EqHorseRecord
--- @param ceilings table stat -> ceiling
--- @param weights table stat -> discipline weight
--- @param boost number share of a full day
--- @param ageMonths number
--- @param timeAdjustment number
--- @param rate number|nil the Training rate setting (1 when nil)
--- @return table deltas stat -> change
function EqTraining.applyBoost(record, ceilings, weights, boost, ageMonths, timeAdjustment, rate)
    local maxWeight = 0
    for _, stat in ipairs(EqConstants.STAT_KEYS) do maxWeight = math.max(maxWeight, weights[stat] or 0) end

    local ageFactor = EqStats.ageTrainingFactor(ageMonths)
    local deltas = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local effort = maxWeight > 0 and boost * (weights[stat] or 0) / maxWeight or 0
        local before = record.trained[stat] or 0
        local gained = EqTraining.gain(before, ceilings[stat] * EqConstants.STAFF_CAP, EqConstants.TRAIN_MONTHLY[stat] * (rate or 1),
            effort, ageFactor, timeAdjustment)
        record.trained[stat] = EqStats.clamp(before + gained, 0, ceilings[stat])
        deltas[stat] = record.trained[stat] - before
    end
    return deltas
end

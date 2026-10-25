--[[
    EqTraining.lua
    The training maths: pure functions with no game or RLRM calls, so they run headless.

    A day's work comes from two places:
    - The player's own riding. EqTrainingHooks records milliseconds spent in each gait and
      jumps taken into a "sheet" per horse. Each gait trains a different mix of stats.
    - Staff. Whatever share of RLRM's riding value the player's sheet does not explain was put
      there by someone else: the base game's animal worker, or RLRM's herdsman horse-care rule.
      Staff train to the horse's focus profile and stop at STAFF_CAP of each ceiling.

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
    return { ms = { reverse = 0, walk = 0, trot = 0, canter = 0, gallop = 0 }, jumps = 0, inside = {} }
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
--- @return table effort stat -> 0..1
function EqTraining.playerEffort(sheet)
    local effort = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do effort[stat] = 0 end
    if sheet == nil then return effort end

    for gait, ms in pairs(sheet.ms) do
        local share = ms / EqConstants.TRAINING_FULL_MS
        for stat, weight in pairs(EqTraining.GAIT_WEIGHTS[gait]) do
            effort[stat] = effort[stat] + share * weight
        end
    end
    effort.agility = effort.agility + sheet.jumps * EqConstants.JUMP_AGILITY
    effort.temperament = effort.temperament + sheet.jumps * EqConstants.JUMP_TEMPERAMENT

    for _, stat in ipairs(EqConstants.STAT_KEYS) do effort[stat] = EqStats.clamp(effort[stat], 0, 1) end
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

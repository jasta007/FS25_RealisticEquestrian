--[[
    EqStaff.lua
    Hired staff (James, 2026-10-27): grooms, event trainers, a vet and a broker, each with ten
    randomised skills and a wage. Pure functions with no game or RLRM calls, so they run headless;
    EqStaffManager keeps the farm's staff and candidates and calls these.

    - Every member has all ten skills (0-100): the four stats (permanent training), the four
      event types (temporary bonuses before events; Racing covers steeplechase, Eventing uses the
      other three), Veterinary and Broker. Their job's main skills are high; the rest are low,
      with now and then a talent, so a great groom can know some vet work too.
    - A groom or trainer works on what their "Works on" says: General (every horse a little), a
      role group (every horse with that role), or one horse. Targeted horses get the full work,
      shared out past HORSES_PER_STAFF horses; every other horse gets GENERAL_SHARE of it.
    - Work from several people on one stat has diminishing returns (EqStaff.stack): the best
      counts in full, the second at 40%, the rest at 10%.
    - Each member can train a stat up to CAP_BASE + CAP_SKILL x skill of its ceiling; only the
      player's own riding reaches the top.
    - At most one Vet and one Broker (UNIQUE). They work on every horse without a target.
]]

EqStaff = {}

EqStaff.STATS = { "stamina", "speed", "agility", "temperament" }
EqStaff.EVENTS = { "dressage", "showJumping", "crossCountry", "racing" }
EqStaff.SKILLS = { "stamina", "speed", "agility", "temperament", "dressage", "showJumping", "crossCountry",
    "racing", "veterinary", "broker" }

-- Each job's main skills, the stats it trains at TRAINER_SHARE (every other stat at
-- GROOM_SHARE, by the member's skill in it), and the event type it gives a bonus for.
EqStaff.JOBS = {
    groom = { main = { "stamina", "speed", "agility", "temperament" }, trains = {} },
    dressage = { main = { "dressage", "temperament", "agility" }, trains = { temperament = true, agility = true },
        event = "dressage" },
    showJumping = { main = { "showJumping", "agility", "temperament" }, trains = { agility = true, temperament = true },
        event = "showJumping" },
    crossCountry = { main = { "crossCountry", "stamina", "agility" }, trains = { stamina = true, agility = true },
        event = "crossCountry" },
    racing = { main = { "racing", "speed", "stamina" }, trains = { speed = true, stamina = true }, event = "racing" },
    vet = { main = { "veterinary" }, trains = {} },
    broker = { main = { "broker" }, trains = {} },
}
EqStaff.JOB_ORDER = { "groom", "dressage", "showJumping", "crossCountry", "racing", "vet", "broker" }
-- How often each job turns up among candidates.
EqStaff.JOB_CHANCE = { groom = 0.35, dressage = 0.12, showJumping = 0.12, crossCountry = 0.12, racing = 0.12,
    vet = 0.09, broker = 0.08 }
-- Jobs a farm can have only one of.
EqStaff.UNIQUE = { vet = true, broker = true }

-- Grades, most common first: how often each turns up, the main skills' range and the wage factor.
EqStaff.GRADES = {
    { name = "junior", chance = 0.60, low = 25, high = 45, wage = 1 },
    { name = "experienced", chance = 0.28, low = 40, high = 65, wage = 1.8 },
    { name = "senior", chance = 0.10, low = 60, high = 80, wage = 3 },
    { name = "legendary", chance = 0.02, low = 80, high = 100, wage = 5 },
}

-- Skills outside a member's job: OFF_SKILL of their grade's middle level, or TALENT_SKILL for a
-- talent, which a skill is at TALENT_CHANCE.
EqStaff.OFF_SKILL = { 0, 0.4 }
EqStaff.TALENT_SKILL = { 0.5, 0.9 }
EqStaff.TALENT_CHANCE = 0.15

-- Monthly wage of a junior with average main skills, by job.
EqStaff.BASE_WAGE = { groom = 900, dressage = 1400, showJumping = 1400, crossCountry = 1400, racing = 1400,
    vet = 1800, broker = 1200 }
-- Wages vary by up to this share either way, so a bargain or an overpriced hire turns up.
EqStaff.WAGE_LUCK = 0.15
-- Each talent adds this share to the wage.
EqStaff.TALENT_WAGE = 0.04

-- Candidates on offer at a time, and how many months each stays on offer.
EqStaff.CANDIDATES = 6
EqStaff.CANDIDATE_MONTHS = { 1, 2 }

-- TRAINING. Effort per day is the same unit as the player's riding (EqTraining.playerEffort):
-- a trainer gives TRAINER_SHARE x skill/100 in its stats, every member GROOM_SHARE x skill/100 in
-- the others. Horses they are not set to work on get GENERAL_SHARE of that.
EqStaff.TRAINER_SHARE = 0.5
EqStaff.GROOM_SHARE = 0.35
EqStaff.GENERAL_SHARE = 0.2
-- A groom or trainer looks after this many targeted horses fully; more share the time.
EqStaff.HORSES_PER_STAFF = 4
-- A member trains a stat up to CAP_BASE + CAP_SKILL x skill/100 of its ceiling.
EqStaff.CAP_BASE = 0.6
EqStaff.CAP_SKILL = 0.35
-- Diminishing returns: the biggest share counts in full, the next at the second weight, and so
-- on; past the list, each counts at the last weight.
EqStaff.STACK = { 1, 0.4, 0.1 }

-- Every groom cleans this many horses a day: the ones they work on first, then any others.
EqStaff.CLEAN_PER_GROOM = 8

-- What "Works on" can be.
EqStaff.WORKS_GENERAL = "general"
EqStaff.WORKS_ROLE = "role"
EqStaff.WORKS_HORSE = "horse"


--- @param job string
--- @return boolean true for a groom or a trainer: the jobs that train horses and take a target
function EqStaff.trains(job)
    return job == "groom" or (EqStaff.JOBS[job] ~= nil and EqStaff.JOBS[job].event ~= nil)
end


--- Diminishing returns: sort the values, biggest first, and add them at the STACK weights.
--- @param values table list of numbers (sorted in place)
--- @return number total
function EqStaff.stack(values)
    table.sort(values, function(a, b) return a > b end)
    local total = 0
    for i, value in ipairs(values) do
        total = total + value * (EqStaff.STACK[i] or EqStaff.STACK[#EqStaff.STACK])
    end
    return total
end


--- @param rng table EqRandom
--- @param chances table key -> chance
--- @param order table keys in order
--- @return string key
local function pick(rng, chances, order)
    local roll, total = rng:next(), 0
    for _, key in ipairs(order) do
        total = total + chances[key]
        if roll < total then return key end
    end
    return order[#order]
end


--- @param rng table EqRandom
--- @return number index into GRADES
function EqStaff.rollGrade(rng)
    local roll, total = rng:next(), 0
    for i, grade in ipairs(EqStaff.GRADES) do
        total = total + grade.chance
        if roll < total then return i end
    end
    return 1
end


--- @param job string
--- @return table set skill -> true for the job's main skills
local function mainSet(job)
    local set = {}
    for _, skill in ipairs(EqStaff.JOBS[job].main) do set[skill] = true end
    return set
end


--- @param job string
--- @param gradeIndex number
--- @param skills table skill -> 0..100
--- @param talents number off-job skills that rolled as talents
--- @param luck number -1..1, the wage's luck
--- @return number wage per month, rounded to 10
function EqStaff.wageFor(job, gradeIndex, skills, talents, luck)
    local grade = EqStaff.GRADES[gradeIndex]
    local main, sum = EqStaff.JOBS[job].main, 0
    for _, skill in ipairs(main) do sum = sum + (skills[skill] or 0) end
    local middle = (grade.low + grade.high) / 2
    local skillFactor = 1 + (sum / #main - middle) / 100
    local wage = EqStaff.BASE_WAGE[job] * grade.wage * skillFactor * (1 + EqStaff.TALENT_WAGE * talents)
        * (1 + EqStaff.WAGE_LUCK * luck)
    return math.floor(wage / 10 + 0.5) * 10
end


--- Roll a new candidate.
--- @param rng table EqRandom
--- @param id number the member's id
--- @param month number the month counter now, for how long they stay on offer
--- @param job string|nil a job to roll, else a random one
--- @return table member { id, name, job, grade, skills, wage, worksOn, leavesMonth }
function EqStaff.roll(rng, id, month, job)
    job = job or pick(rng, EqStaff.JOB_CHANCE, EqStaff.JOB_ORDER)
    local gradeIndex = EqStaff.rollGrade(rng)
    local grade = EqStaff.GRADES[gradeIndex]
    local middle = (grade.low + grade.high) / 2
    local main = mainSet(job)

    local skills, talents = {}, 0
    for _, skill in ipairs(EqStaff.SKILLS) do
        local value
        if main[skill] then
            value = rng:uniform(grade.low, grade.high)
        elseif rng:next() < EqStaff.TALENT_CHANCE then
            value = middle * rng:uniform(EqStaff.TALENT_SKILL[1], EqStaff.TALENT_SKILL[2])
            talents = talents + 1
        else
            value = middle * rng:uniform(EqStaff.OFF_SKILL[1], EqStaff.OFF_SKILL[2])
        end
        skills[skill] = math.floor(math.max(0, math.min(100, value)) + 0.5)
    end

    local months = EqStaff.CANDIDATE_MONTHS
    return {
        id = id,
        name = EqStaffNames.roll(rng),
        job = job,
        grade = gradeIndex,
        skills = skills,
        talents = talents,
        wage = EqStaff.wageFor(job, gradeIndex, skills, talents, rng:uniform(-1, 1)),
        worksOn = { kind = EqStaff.WORKS_GENERAL },
        leavesMonth = month + months[1] + math.floor(rng:next() * (months[2] - months[1] + 1)),
    }
end


--- Drop candidates whose time is up and top the list up to CANDIDATES.
--- @param candidates table list of members, changed in place
--- @param month number the month counter now
--- @param rng table EqRandom
--- @param nextId number the next free member id
--- @return number nextId
function EqStaff.refreshCandidates(candidates, month, rng, nextId)
    for i = #candidates, 1, -1 do
        if (candidates[i].leavesMonth or 0) < month then table.remove(candidates, i) end
    end
    while #candidates < EqStaff.CANDIDATES do
        table.insert(candidates, EqStaff.roll(rng, nextId, month))
        nextId = nextId + 1
    end
    return nextId
end


--- @param hired table list of members
--- @param candidate table
--- @return boolean ok false when the farm already has its one of a unique job
function EqStaff.canHire(hired, candidate)
    if not EqStaff.UNIQUE[candidate.job] then return true end
    for _, member in ipairs(hired) do
        if member.job == candidate.job then return false end
    end
    return true
end


--- @param member table
--- @param horse table { id, role, retired }
--- @return boolean true when the member is set to work on this horse
function EqStaff.targets(member, horse)
    local works = member.worksOn
    if works == nil or not EqStaff.trains(member.job) then return false end
    if works.kind == EqStaff.WORKS_ROLE then
        return not horse.retired and horse.role == works.role
    elseif works.kind == EqStaff.WORKS_HORSE then
        return horse.id == works.id
    end
    return false
end


--- How many of the farm's horses each member is set to work on.
--- @param members table list of members
--- @param horses table list of { id, role, retired }
--- @return table counts member id -> horses
function EqStaff.targetCounts(members, horses)
    local counts = {}
    for _, member in ipairs(members) do
        local n = 0
        for _, horse in ipairs(horses) do
            if EqStaff.targets(member, horse) then n = n + 1 end
        end
        counts[member.id] = n
    end
    return counts
end


--- One member's work on one horse's stat.
--- @param member table
--- @param stat string
--- @param targeted boolean
--- @param count number|nil how many horses the member is set to work on
--- @return number effort
--- @return number cap share of the ceiling this member trains up to
function EqStaff.memberEffort(member, stat, targeted, count)
    local skill = (member.skills[stat] or 0) / 100
    local job = EqStaff.JOBS[member.job]
    local share = (job ~= nil and job.trains[stat]) and EqStaff.TRAINER_SHARE or EqStaff.GROOM_SHARE
    local effort = share * skill
    if targeted then
        effort = effort * math.min(1, EqStaff.HORSES_PER_STAFF / math.max(1, count or 1))
    else
        effort = effort * EqStaff.GENERAL_SHARE
    end
    return effort, EqStaff.CAP_BASE + EqStaff.CAP_SKILL * skill
end


--- Everyone's work on one horse, ready for EqTraining.applyDay.
--- @param members table list of hired members
--- @param horse table { id, role, retired }
--- @param counts table from targetCounts
--- @return table work stat -> list of { effort, cap, name, targeted } (only those above 0)
function EqStaff.workOn(members, horse, counts)
    local work = {}
    for _, stat in ipairs(EqStaff.STATS) do work[stat] = {} end
    for _, member in ipairs(members) do
        if EqStaff.trains(member.job) then
            local targeted = EqStaff.targets(member, horse)
            for _, stat in ipairs(EqStaff.STATS) do
                local effort, cap = EqStaff.memberEffort(member, stat, targeted, counts[member.id])
                if effort > 0 then
                    table.insert(work[stat], { effort = effort, cap = cap, name = member.name, targeted = targeted })
                end
            end
        end
    end
    return work
end


--- A skill across all staff, for the passive jobs: the best counts in full, the rest stack.
--- @param members table
--- @param skill string "veterinary" or "broker"
--- @return number strength 0..1
function EqStaff.strength(members, skill)
    local values = {}
    for _, member in ipairs(members) do
        table.insert(values, (member.skills[skill] or 0) / 100)
    end
    return math.min(1, EqStaff.stack(values))
end


--- @param members table
--- @return number wages per month
function EqStaff.monthlyWages(members)
    local total = 0
    for _, member in ipairs(members) do total = total + (member.wage or 0) end
    return total
end


--- Choose which horses the grooms clean today: the ones a groom works on first, then the rest,
--- up to CLEAN_PER_GROOM each.
--- @param members table
--- @param horses table list of { id, role, retired }
--- @return table list of the horses to clean, in order
function EqStaff.toClean(members, horses)
    local grooms = 0
    for _, member in ipairs(members) do
        if member.job == "groom" then grooms = grooms + 1 end
    end
    local room = grooms * EqStaff.CLEAN_PER_GROOM
    local first, rest = {}, {}
    for _, horse in ipairs(horses) do
        local mine = false
        for _, member in ipairs(members) do
            if member.job == "groom" and EqStaff.targets(member, horse) then mine = true end
        end
        table.insert(mine and first or rest, horse)
    end
    local out = {}
    for _, list in ipairs({ first, rest }) do
        for _, horse in ipairs(list) do
            if #out < room then table.insert(out, horse) end
        end
    end
    return out
end

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
-- How often each job turns up among candidates (EqStaff.roll without a job).
EqStaff.JOB_CHANCE = { groom = 0.35, dressage = 0.12, showJumping = 0.12, crossCountry = 0.12, racing = 0.12,
    vet = 0.09, broker = 0.08 }
-- The mix on offer: at least MIX_MIN grooms and trainers (each trainer a different event), at
-- most MIX_MAX of each; a spare place goes to a vet or broker at MIX_PASSIVE, else a groom or a
-- trainer. At most one vet and one broker on offer.
EqStaff.MIX_MIN = 2
EqStaff.MIX_MAX = 3
EqStaff.MIX_PASSIVE = 0.3
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

-- Daily wage of a junior with average main skills, by job. A junior groom is cheap enough to
-- hire just for the cleaning.
EqStaff.BASE_WAGE = { groom = 200, dressage = 450, showJumping = 450, crossCountry = 450, racing = 450,
    vet = 600, broker = 400 }
-- Wages vary by up to this share either way, so a bargain or an overpriced hire turns up.
EqStaff.WAGE_LUCK = 0.15
-- Each talent adds this share to the wage.
EqStaff.TALENT_WAGE = 0.04

-- Candidates on offer at a time, and how many game hours each stays on offer. When one leaves
-- or is hired, a new one turns up each hour at ARRIVAL_CHANCE, so people come and go a few at a
-- time.
EqStaff.CANDIDATES = 6
EqStaff.CANDIDATE_HOURS = { 12, 72 }
EqStaff.ARRIVAL_CHANCE = 0.25

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

-- Who a groom or trainer works on: { mode, stables, roles, horses }. In WORKS_ROLE mode every
-- horse in the chosen stables (nil: all) with one of the chosen roles (nil: all) that isn't
-- retired; in WORKS_HORSE mode the chosen horses. WORKS_GENERAL is only read from old saves.
EqStaff.WORKS_GENERAL = "general"
EqStaff.WORKS_ROLE = "role"
EqStaff.WORKS_HORSE = "horse"
-- A disabled member does no work and is paid this share of their wage. Switching takes effect
-- at ENABLE_HOUR the next morning and holds for a whole day, so it can't be timed around the
-- day's training, the grooms' round or the wages.
EqStaff.DISABLED_WAGE = 0.5
EqStaff.ENABLE_HOUR = 1


--- @return table worksOn every horse in every stable
function EqStaff.defaultWorks()
    return { mode = EqStaff.WORKS_ROLE, horses = {} }
end


--- @param list table|nil
--- @param value any
--- @return boolean
local function contains(list, value)
    if list == nil then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end
EqStaff.contains = contains


--- Bring an old save's Works on ({ kind, role, id }) into the current shape.
--- @param works table|nil
--- @return table works
function EqStaff.normalizeWorks(works)
    if works == nil then return EqStaff.defaultWorks() end
    if works.mode ~= nil then
        works.horses = works.horses or {}
        return works
    end
    if works.kind == EqStaff.WORKS_ROLE and works.role ~= nil then
        return { mode = EqStaff.WORKS_ROLE, roles = { works.role }, horses = {} }
    elseif works.kind == EqStaff.WORKS_HORSE and works.id ~= nil then
        return { mode = EqStaff.WORKS_HORSE, horses = { works.id } }
    end
    return EqStaff.defaultWorks()
end


--- @param members table
--- @return table the members at work (not disabled)
function EqStaff.working(members)
    local out = {}
    for _, member in ipairs(members) do
        if member.enabled ~= false then table.insert(out, member) end
    end
    return out
end


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
--- @return number wage per day, rounded to 5
function EqStaff.wageFor(job, gradeIndex, skills, talents, luck)
    local grade = EqStaff.GRADES[gradeIndex]
    local main, sum = EqStaff.JOBS[job].main, 0
    for _, skill in ipairs(main) do sum = sum + (skills[skill] or 0) end
    local middle = (grade.low + grade.high) / 2
    local skillFactor = 1 + (sum / #main - middle) / 100
    local wage = EqStaff.BASE_WAGE[job] * grade.wage * skillFactor * (1 + EqStaff.TALENT_WAGE * talents)
        * (1 + EqStaff.WAGE_LUCK * luck)
    return math.floor(wage / 5 + 0.5) * 5
end


--- Roll a new candidate.
--- @param rng table EqRandom
--- @param id number the member's id
--- @param hour number the game hour now (EqStaff.gameHour), for how long they stay on offer
--- @param job string|nil a job to roll, else a random one
--- @return table member { id, name, job, grade, skills, wage, worksOn, leavesAt }
function EqStaff.roll(rng, id, hour, job)
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

    local hours = EqStaff.CANDIDATE_HOURS
    local name, gender = EqStaffNames.roll(rng)
    return {
        id = id,
        name = name,
        face = EqStaff.rollFace(rng, gender),
        job = job,
        grade = gradeIndex,
        skills = skills,
        talents = talents,
        wage = EqStaff.wageFor(job, gradeIndex, skills, talents, rng:uniform(-1, 1)),
        worksOn = EqStaff.defaultWorks(),
        leavesAt = hour + hours[1] + math.floor(rng:next() * (hours[2] - hours[1] + 1)),
    }
end


--- The job for the next candidate, keeping the mix on offer (MIX_*).
--- @param candidates table list of members on offer
--- @param rng table EqRandom
--- @return string job
function EqStaff.nextJob(candidates, rng)
    local count, grooms, trainers = {}, 0, 0
    for _, candidate in ipairs(candidates) do
        count[candidate.job] = (count[candidate.job] or 0) + 1
        if candidate.job == "groom" then grooms = grooms + 1 end
        if EqStaff.JOBS[candidate.job].event ~= nil then trainers = trainers + 1 end
    end
    local function trainer()
        local free = {}
        for _, event in ipairs(EqStaff.EVENTS) do
            if count[event] == nil then table.insert(free, event) end
        end
        if #free == 0 then return nil end
        return free[math.min(#free, math.floor(rng:next() * #free) + 1)]
    end
    local function passive()
        local free = {}
        for _, job in ipairs({ "vet", "broker" }) do
            if count[job] == nil then table.insert(free, job) end
        end
        if #free == 0 then return nil end
        return free[math.min(#free, math.floor(rng:next() * #free) + 1)]
    end

    if grooms < EqStaff.MIX_MIN then return "groom" end
    if trainers < EqStaff.MIX_MIN then return trainer() or "groom" end
    if rng:next() < EqStaff.MIX_PASSIVE then
        local job = passive()
        if job ~= nil then return job end
    end
    local canGroom, canTrain = grooms < EqStaff.MIX_MAX, trainers < EqStaff.MIX_MAX
    if canGroom and (not canTrain or rng:next() < 0.5) then return "groom" end
    return (canTrain and trainer()) or passive() or "groom"
end


--- Order people for the lists: by job (JOB_ORDER), then grade, then main skill, best first.
--- @param people table list of members, sorted in place
function EqStaff.sortPeople(people)
    local rank = {}
    for i, job in ipairs(EqStaff.JOB_ORDER) do rank[job] = i end
    local function mainSkill(member)
        local main, sum = EqStaff.JOBS[member.job].main, 0
        for _, skill in ipairs(main) do sum = sum + (member.skills[skill] or 0) end
        return sum / #main
    end
    table.sort(people, function(a, b)
        if a.job ~= b.job then return (rank[a.job] or 99) < (rank[b.job] or 99) end
        if a.grade ~= b.grade then return a.grade > b.grade end
        local sa, sb = mainSkill(a), mainSkill(b)
        if sa ~= sb then return sa > sb end
        return (a.id or 0) < (b.id or 0)
    end)
end


--- @param day number the monotonic day
--- @param hour number the hour of the day
--- @return number hours since the game began
function EqStaff.gameHour(day, hour)
    return (day or 0) * 24 + (hour or 0)
end


--- @param candidate table
--- @param hour number the game hour now
--- @return number hours left on offer, at least 1
function EqStaff.hoursLeft(candidate, hour)
    return math.max(1, (candidate.leavesAt or hour) - hour)
end


--- Drop candidates whose time is up, and let new ones arrive: the whole list at once when fill
--- is true (a new game), else at most one, at ARRIVAL_CHANCE.
--- @param candidates table list of members, changed in place
--- @param hour number the game hour now
--- @param rng table EqRandom
--- @param nextId number the next free member id
--- @param fill boolean|nil
--- @return number nextId
function EqStaff.refreshCandidates(candidates, hour, rng, nextId, fill)
    for i = #candidates, 1, -1 do
        if candidates[i].leavesAt == nil then
            -- From a save before hours: a fresh window.
            candidates[i].leavesAt = hour + EqStaff.CANDIDATE_HOURS[1]
                + math.floor(rng:next() * (EqStaff.CANDIDATE_HOURS[2] - EqStaff.CANDIDATE_HOURS[1] + 1))
        elseif candidates[i].leavesAt <= hour then
            table.remove(candidates, i)
        end
    end
    while #candidates < EqStaff.CANDIDATES and (fill or rng:next() < EqStaff.ARRIVAL_CHANCE) do
        table.insert(candidates, EqStaff.roll(rng, nextId, hour, EqStaff.nextJob(candidates, rng)))
        nextId = nextId + 1
        if not fill then break end
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
    if member.enabled == false or not EqStaff.trains(member.job) then return false end
    local works = EqStaff.normalizeWorks(member.worksOn)
    if works.mode == EqStaff.WORKS_HORSE then return contains(works.horses, horse.id) end
    if horse.retired then return false end
    if works.stables ~= nil and horse.stable ~= nil and not contains(works.stables, horse.stable) then return false end
    return works.roles == nil or contains(works.roles, horse.role)
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
        if member.enabled ~= false and EqStaff.trains(member.job) then
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
        if member.enabled ~= false then table.insert(values, (member.skills[skill] or 0) / 100) end
    end
    return math.min(1, EqStaff.stack(values))
end


--- @param members table
--- @return number wages per day
function EqStaff.dailyWages(members)
    local total = 0
    for _, member in ipairs(members) do
        total = total + (member.wage or 0) * (member.enabled == false and EqStaff.DISABLED_WAGE or 1)
    end
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
        if member.job == "groom" and member.enabled ~= false then grooms = grooms + 1 end
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


--- How many horses have each role, in the chosen stables, for the role checklist.
--- @param horses table list of { id, role, retired, stable }
--- @param stables table|nil stable keys; nil for all
--- @return table counts role -> horses
function EqStaff.roleCounts(horses, stables)
    local counts = {}
    for _, horse in ipairs(horses) do
        if not horse.retired and (stables == nil or horse.stable == nil or contains(stables, horse.stable)) then
            counts[horse.role] = (counts[horse.role] or 0) + 1
        end
    end
    return counts
end


--- The horses in the chosen stables, by name, for the horse checklist.
--- @param horses table list of { id, name, stable }
--- @param stables table|nil stable keys; nil for all
--- @return table horses
function EqStaff.horsesIn(horses, stables)
    local out = {}
    for _, horse in ipairs(horses) do
        if stables == nil or horse.stable == nil or contains(stables, horse.stable) then table.insert(out, horse) end
    end
    table.sort(out, function(a, b) return string.lower(a.name or a.id) < string.lower(b.name or b.id) end)
    return out
end


-- PORTRAITS (gui/eqStaffFaces.xml, faces by kawsar4404). Numbered row by row on the artist's
-- sheet. A person mostly gets a face for their name; FACE_ANY of people get any face.
EqStaff.FACES = {
    male = { 1, 9, 13, 17 },
    either = { 2, 5, 6, 15, 19 },
    female = { 3, 4, 7, 8, 10, 11, 12, 14, 16, 18, 20 },
}
EqStaff.FACE_COUNT = 20
EqStaff.FACE_ANY = 0.1


--- @param rng table EqRandom
--- @param gender string|nil "female" or "male"
--- @return number face 1..FACE_COUNT
function EqStaff.rollFace(rng, gender)
    local pool = {}
    if gender == nil or rng:next() < EqStaff.FACE_ANY then
        for i = 1, EqStaff.FACE_COUNT do table.insert(pool, i) end
    else
        for _, face in ipairs(EqStaff.FACES[gender] or {}) do table.insert(pool, face) end
        for _, face in ipairs(EqStaff.FACES.either) do table.insert(pool, face) end
    end
    return pool[math.min(#pool, math.floor(rng:next() * #pool) + 1)]
end


--- @param member table
--- @return number face 1..FACE_COUNT; people from before portraits get one from their id
function EqStaff.faceOf(member)
    if member.face ~= nil then return member.face end
    member.face = EqStaff.rollFace(EqRandom.new("face " .. tostring(member.id)), EqStaffNames.genderOf(member.name))
    return member.face
end


-- Words for a staff skill, from 0 up, with the RLRM genetics band whose colour they borrow.
EqStaff.LEVELS = {
    { from = 0, word = 1, band = "rl_ui_genetics_extremelyLow" },
    { from = 20, word = 2, band = "rl_ui_genetics_low" },
    { from = 40, word = 3, band = "rl_ui_genetics_average" },
    { from = 60, word = 4, band = "rl_ui_genetics_high" },
    { from = 80, word = 5, band = "rl_ui_genetics_veryHigh" },
    { from = 90, word = 6, band = "rl_ui_genetics_extremelyHigh" },
}


--- @param value number skill 0..100
--- @return table level an entry of LEVELS
function EqStaff.level(value)
    local found = EqStaff.LEVELS[1]
    for _, level in ipairs(EqStaff.LEVELS) do
        if value >= level.from then found = level end
    end
    return found
end


--- A member's best skills, for the Hire table.
--- @param member table
--- @param count number how many
--- @return table skills list of skill keys, best first
function EqStaff.bestSkills(member, count)
    local keys = {}
    for _, skill in ipairs(EqStaff.SKILLS) do table.insert(keys, skill) end
    table.sort(keys, function(a, b)
        local va, vb = member.skills[a] or 0, member.skills[b] or 0
        if va ~= vb then return va > vb end
        return a < b
    end)
    local out = {}
    for i = 1, math.min(count, #keys) do table.insert(out, keys[i]) end
    return out
end


-- THE PASSIVE JOBS AND EVENT BONUSES (EqStaff.strength gives a farm's skill, 0..1)

-- A vet at full strength takes VET_INJURY off the chance of an injury at an event, and VET_CARE
-- off an injury's rest and treatment fee.
EqStaff.VET_INJURY = 0.4
EqStaff.VET_CARE = 0.35
-- A broker at full strength shows the dealer's view BROKER_TRUTH of the way to the real potential,
-- and a bought horse's real potential shows up to BROKER_REVEAL months sooner (never before 1).
EqStaff.BROKER_TRUTH = 0.7
EqStaff.BROKER_REVEAL = 2
-- A broker at full strength buys horses BROKER_DEAL cheaper and sells them BROKER_DEAL dearer;
-- the sale premium only for a horse owned a month or more, so buying to sell back gains nothing.
EqStaff.BROKER_DEAL = 0.05
-- A trainer at skill 100 working on a horse adds EVENT_POINTS to that event type's stats in the
-- month's events (GENERAL_SHARE of that for horses they don't work on). Peak form from the
-- player's riding goes up to 8 (EqTraining.FORM_MAX); together the bigger counts in full, the
-- smaller at half, up to FORM_CAP.
EqStaff.EVENT_POINTS = 4
EqStaff.FORM_CAP = 10


--- @param strength number the farm's Veterinary, 0..1
--- @return number factor on the chance of an injury at an event
function EqStaff.injuryFactor(strength)
    return 1 - EqStaff.VET_INJURY * (strength or 0)
end


--- @param strength number the farm's Veterinary, 0..1
--- @return number factor on an injury's rest and fee
function EqStaff.careFactor(strength)
    return 1 - EqStaff.VET_CARE * (strength or 0)
end


--- The dealer's view as the farm's broker reads it.
--- @param advertised table stat -> the dealer's view
--- @param real table stat -> the real ceiling
--- @param strength number the farm's Broker, 0..1
--- @return table shown stat -> ceiling
function EqStaff.brokerView(advertised, real, strength)
    local truth = EqStaff.BROKER_TRUTH * (strength or 0)
    if truth <= 0 then return advertised end
    local shown = {}
    for _, stat in ipairs(EqStaff.STATS) do
        local said, actual = advertised[stat] or 0, real[stat] or 0
        shown[stat] = math.floor((said + (actual - said) * truth) * 10 + 0.5) / 10
    end
    return shown
end


--- @param strength number the farm's Broker, 0..1
--- @param selling boolean true for the farm's own horse, false for a dealer's
--- @return number factor on the horse's price
function EqStaff.dealFactor(strength, selling)
    local share = EqStaff.BROKER_DEAL * (strength or 0)
    return selling and 1 + share or 1 - share
end


--- @param months number months on the farm before the real potential shows
--- @param strength number the farm's Broker, 0..1
--- @return number months
function EqStaff.revealMonths(months, strength)
    return math.max(1, months - math.floor(EqStaff.BROKER_REVEAL * (strength or 0) + 0.5))
end


--- The event skills that help in a discipline: its own, Racing for any race, the three phases
--- for eventing.
--- @param discipline table events.xml discipline { name, racing, phases }
--- @return table skills list of event skill keys
function EqStaff.eventSkills(discipline)
    if discipline.racing then return { "racing" } end
    if discipline.phases ~= nil then
        local skills = {}
        for _, phase in ipairs(discipline.phases) do
            for _, event in ipairs(EqStaff.EVENTS) do
                if event == phase then table.insert(skills, phase) end
            end
        end
        return skills
    end
    for _, event in ipairs(EqStaff.EVENTS) do
        if event == discipline.name then return { event } end
    end
    return {}
end


--- Staff's bonus to a horse's stats in an event: each event skill stacked over the staff, then
--- averaged over the discipline's skills (eventing needs all three), spread over the stats by the
--- discipline's weights.
--- @param members table
--- @param horse table { id, role, retired }
--- @param counts table from targetCounts
--- @param skills table from eventSkills
--- @param weights table stat -> discipline weight
--- @return table bonus stat -> points
function EqStaff.eventBonus(members, horse, counts, skills, weights)
    local total = 0
    for _, skill in ipairs(skills) do
        local values = {}
        for _, member in ipairs(members) do
            -- Only trainers coach for events; one can help in another event by their skill in it.
            if member.enabled ~= false and EqStaff.JOBS[member.job] ~= nil and EqStaff.JOBS[member.job].event ~= nil then
                local share = EqStaff.GENERAL_SHARE
                if EqStaff.targets(member, horse) then
                    share = math.min(1, EqStaff.HORSES_PER_STAFF / math.max(1, counts[member.id] or 1))
                end
                table.insert(values, EqStaff.EVENT_POINTS * (member.skills[skill] or 0) / 100 * share)
            end
        end
        total = total + EqStaff.stack(values)
    end
    if #skills > 0 then total = total / #skills end

    local maxWeight = 0
    for _, stat in ipairs(EqStaff.STATS) do maxWeight = math.max(maxWeight, weights[stat] or 0) end
    local bonus = {}
    for _, stat in ipairs(EqStaff.STATS) do
        bonus[stat] = maxWeight > 0 and total * (weights[stat] or 0) / maxWeight or 0
    end
    return bonus
end


--- Put the player's peak form and staff's event bonus together.
--- @param form table stat -> points
--- @param bonus table|nil stat -> points
--- @return table form stat -> points
function EqStaff.mixForm(form, bonus)
    if bonus == nil then return form end
    local mixed = {}
    for _, stat in ipairs(EqStaff.STATS) do
        local a, b = form[stat] or 0, bonus[stat] or 0
        mixed[stat] = math.min(EqStaff.FORM_CAP, math.max(a, b) + 0.5 * math.min(a, b))
    end
    return mixed
end

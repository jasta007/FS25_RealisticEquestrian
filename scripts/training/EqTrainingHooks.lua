--[[
    EqTrainingHooks.lua
    Wires EqTraining into the game.

    - Rideable.updateRiding and Rideable.jump (base game) record the player's riding into a sheet
      per horse. Vehicle functions are copied into each vehicle type when types are registered,
      so these two are patched at source time, before that happens; the hook bodies stay idle
      until EqMain is active. Both run on the server only, which is where riding is counted.
    - Rideable.onDraw adds a line showing today's training effort while riding, one naming the
      farm's facility the horse is inside (EqFacilityHooks), if any, and one for the boost the
      horse's feed gives (EqFeedHooks).
    - RLRM's AnimalHorse.processRidingUpdate is the daily horse tick. A prepend runs our day
      just before RLRM grades fitness and zeroes riding, so the day's riding value is still there
      to read.

    Sheets live in memory only: a save and reload mid-day drops that day's player riding (staff
    work is read from RLRM's saved riding value, so it survives).
]]

EqTrainingHooks = {}
EqTrainingHooks.sheets = {}

local Log = EqLog

local gaitNames = nil


--- Map Rideable.GAITTYPES values to EqTraining's gait names. Built on first use.
--- @return table
local function getGaitNames()
    if gaitNames == nil then
        local types = Rideable.GAITTYPES
        gaitNames = {
            [types.WALK] = "walk",
            [types.TROT] = "trot",
            [types.CANTER] = "canter",
            [types.GALLOP] = "gallop",
        }
    end
    return gaitNames
end


--- @param id string
--- @return table sheet, created on first use
function EqTrainingHooks.getSheet(id)
    local sheet = EqTrainingHooks.sheets[id]
    if sheet == nil then
        sheet = EqTraining.newSheet()
        EqTrainingHooks.sheets[id] = sheet
    end
    return sheet
end


function EqTrainingHooks.reset()
    EqTrainingHooks.sheets = {}
end


--- The RLRM identifier of the horse a rideable carries, cached until its cluster changes.
--- @param spec table spec_rideable
--- @return string|nil id
local function getRiddenId(spec)
    local cluster = spec.cluster
    if cluster == nil then return nil end
    if spec.eqCluster ~= cluster then
        spec.eqCluster = cluster
        spec.eqId = (cluster.isHorse ~= nil and cluster:isHorse()) and EqRegistry.getId(cluster) or nil
    end
    return spec.eqId
end


--- Appended to Rideable:updateRiding (server, every frame while ridden).
function EqTrainingHooks.onUpdateRiding(vehicle, dt)
    local spec = vehicle.spec_rideable
    if spec == nil or spec.currentSpeed == 0 then return end

    local gait = getGaitNames()[spec.inputValues.currentGait]
    if gait == nil then return end

    local id = getRiddenId(spec)
    if id == nil then return end

    local sheet = EqTrainingHooks.getSheet(id)
    EqTraining.addRiding(sheet, gait, dt)
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do EqTraining.addInside(sheet, kind, dt) end
end


--- Appended to Rideable:jump (the server branch: in multiplayer a client's JumpEvent calls it
--- on the server).
function EqTrainingHooks.onJump(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil then return end

    local gait = getGaitNames()[spec.inputValues.currentGait]
    if gait ~= "canter" and gait ~= "gallop" then return end

    local id = getRiddenId(spec)
    if id == nil then return end

    EqTraining.addJump(EqTrainingHooks.getSheet(id))
end


--- Appended to Rideable:onDraw: "Training: Sta 34% Spd 10% ...", from the server's sheet. Short
--- names keep the line inside the help panel, which cuts long lines off.
function EqTrainingHooks.onDraw(vehicle, isActiveForInputIgnoreSelection)
    if not isActiveForInputIgnoreSelection then return end
    local spec = vehicle.spec_rideable
    if spec == nil then return end

    local id = getRiddenId(spec)
    local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
    if sheet == nil then return end

    local effort = EqTraining.playerEffort(sheet)
    local parts = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        table.insert(parts, string.format("%s %d%%", g_i18n:getText("eq_stat_short_" .. stat), math.floor(effort[stat] * 100 + 0.5)))
    end
    g_currentMission:addExtraPrintText(g_i18n:getText("eq_training_today") .. ": " .. table.concat(parts, " "))

    local inside = {}
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do table.insert(inside, EqFacilityHooks.kindTitle(kind)) end
    if #inside > 0 then
        table.sort(inside)
        g_currentMission:addExtraPrintText(string.format(g_i18n:getText("eq_facility_inside"), table.concat(inside, ", ")))
    end
    local feedLine = EqFeedHooks.formatBoost(EqFeedHooks.getBoost(spec.cluster))
    if feedLine ~= nil then g_currentMission:addExtraPrintText(feedLine) end
end


--- Prepended to RLRM's AnimalHorse.processRidingUpdate: one day of training for one horse.
--- @param animal table RLRM Animal (a horse, not a sale animal)
function EqTrainingHooks.onHorseDay(animal)
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end

    local record = EqRegistry.getOrCreate(animal)
    if record == nil then return end

    local sheet = EqTrainingHooks.sheets[record.id]
    EqTrainingHooks.sheets[record.id] = nil

    -- On box rest nothing trains: the day counts as idle, so the stats fade as they would.
    local resting = record.injury ~= nil
    local owned, ridden = EqFacilityHooks.boostsFor(EqFacilityHooks.farmOfAnimal(animal), sheet)
    local deltas = EqTraining.applyDay(record, record:getCeilings(), {
        sheet = not resting and sheet or nil,
        riding = not resting and animal.riding or 0,
        dirt = animal.dirt,
        ageMonths = animal.age or 0,
        timeAdjustment = g_currentMission.environment.timeAdjustment or 1,
        facilityOwned = owned,
        facilityRidden = ridden,
        feedBoost = EqFeedHooks.getBoost(animal),
    })

    Log:debug("EqTraining: %s riding=%s dirt=%s idle=%d -> sta %+.2f spd %+.2f agi %+.2f tem %+.2f",
        record.id, tostring(animal.riding), tostring(animal.dirt), record.idleDays,
        deltas.stamina, deltas.speed, deltas.agility, deltas.temperament)
end


--- Patch the base Rideable functions. Call at source time.
--- @param guarded function main.lua's error guard
function EqTrainingHooks.installRideable(guarded)
    Rideable.updateRiding = Utils.appendedFunction(Rideable.updateRiding, function(self, dt)
        if not EqMain.isActive or not self.isServer then return end
        guarded("riding tracker", function() EqTrainingHooks.onUpdateRiding(self, dt) end)
    end)

    Rideable.jump = Utils.appendedFunction(Rideable.jump, function(self)
        if not EqMain.isActive or not self.isServer then return end
        guarded("jump tracker", function() EqTrainingHooks.onJump(self) end)
    end)

    Rideable.onDraw = Utils.appendedFunction(Rideable.onDraw, function(self, isActiveForInput, isActiveForInputIgnoreSelection)
        if not EqMain.isActive then return end
        guarded("training overlay", function() EqTrainingHooks.onDraw(self, isActiveForInputIgnoreSelection) end)
    end)
end


--- Hook RLRM's daily horse tick. Call once, after EqRLRM.init succeeded.
--- @param guarded function main.lua's error guard
function EqTrainingHooks.installDaily(guarded)
    local animalHorse = EqRLRM.get("AnimalHorse")
    animalHorse.processRidingUpdate = Utils.prependedFunction(animalHorse.processRidingUpdate, function(animal)
        guarded("daily training", function() EqTrainingHooks.onHorseDay(animal) end)
    end)
    Log:debug("EqTrainingHooks: hooked AnimalHorse.processRidingUpdate")
end

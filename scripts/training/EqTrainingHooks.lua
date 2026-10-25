--[[
    EqTrainingHooks.lua
    Wires EqTraining into the game.

    - Rideable.updateRiding and Rideable.jump (base game) record the player's riding into a sheet
      per horse. Vehicle functions are copied into each vehicle type when types are registered,
      so these two are patched at source time, before that happens; the hook bodies stay idle
      until EqMain is active. Both run on the server only, which is where riding is counted.
    - Rideable.updateRiding also steps the tiredness meter and the focused stamina and speed work
      (EqTraining.step), at a halt too.
    - Rideable.onDraw shows the training view while riding: the tiredness meter, a line per stat
      for today's training, and in Freestyle the farm's facility the horse is inside
      (EqFacilityHooks) and the boost its feed gives (EqFeedHooks). The training view key (Y,
      Rideable.onRegisterActionEvents) switches to a focused view with tips for one stat.
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


--- @param cluster table|nil RLRM Animal being ridden
--- @return boolean true once its riding bar is full: the horse is tired and trains no more today
local function isTired(cluster)
    return cluster ~= nil and (cluster.riding or 0) >= 100
end


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
        if types.BACKWARDS ~= nil then gaitNames[types.BACKWARDS] = "reverse" end
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


--- Backing up tires a horse faster than the base game counts: add the difference to its riding bar.
--- @param spec table spec_rideable
--- @param dt number milliseconds
local function addReverseTiredness(spec, dt)
    local cluster = spec.cluster
    if cluster.changeRiding == nil then return end
    local fullMs = cluster.getDailyRidingTime ~= nil and cluster:getDailyRidingTime() or EqConstants.RIDING_FULL_MS
    local points
    points, spec.eqReverseTimer = EqTraining.reverseExtraRiding(spec.eqReverseTimer, dt, fullMs)
    if points > 0 then cluster:changeRiding(points) end
end


--- Appended to Rideable:updateRiding (server, every frame while ridden).
function EqTrainingHooks.onUpdateRiding(vehicle, dt)
    local spec = vehicle.spec_rideable
    if spec == nil then return end

    local gait = getGaitNames()[spec.inputValues.currentGait]
    if gait == nil or math.abs(spec.currentSpeed or 0) < 0.05 then gait = "halt" end

    local id = getRiddenId(spec)
    if id == nil then return end

    local sheet = EqTrainingHooks.getSheet(id)
    local now = g_time or 0
    if sheet.clock ~= nil and now - sheet.clock > 1000 then EqTraining.rest(sheet, now - sheet.clock) end
    sheet.clock = now

    local worn = isTired(spec.cluster)
    EqTraining.step(sheet, gait, dt, worn)
    if worn or gait == "halt" then return end

    EqTraining.addRiding(sheet, gait, dt)
    if gait == "reverse" then addReverseTiredness(spec, dt) end
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do EqTraining.addInside(sheet, kind, dt) end
end


--- Appended to Rideable:jump (the server branch: in multiplayer a client's JumpEvent calls it
--- on the server).
function EqTrainingHooks.onJump(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil or isTired(spec.cluster) then return end

    local gait = getGaitNames()[spec.inputValues.currentGait]
    if gait ~= "canter" and gait ~= "gallop" then return end

    local id = getRiddenId(spec)
    if id == nil then return end

    EqTraining.addJump(EqTrainingHooks.getSheet(id))
end


-- Riding HUD views, switched with the training view key (Y). Freestyle shows every meter and
-- stat; a focused view shows what that stat needs, with tips.
EqTrainingHooks.VIEWS = { "freestyle", "stamina", "speed" }
EqTrainingHooks.TIPS = { stamina = 3, speed = 3 }
EqTrainingHooks.viewIndex = 1


--- @return string view a VIEWS name
function EqTrainingHooks.getView()
    return EqTrainingHooks.VIEWS[EqTrainingHooks.viewIndex] or "freestyle"
end


--- @return string text for the action in the help panel
local function viewActionText()
    return string.format(g_i18n:getText("eq_train_viewAction"), g_i18n:getText("eq_train_view_" .. EqTrainingHooks.getView()))
end


--- The training view key was pressed.
function EqTrainingHooks.onViewAction(vehicle)
    EqTrainingHooks.viewIndex = EqTrainingHooks.viewIndex % #EqTrainingHooks.VIEWS + 1
    local spec = vehicle.spec_rideable
    local event = spec ~= nil and spec.eqViewEventId or nil
    if event ~= nil then g_inputBinding:setActionEventText(event, viewActionText()) end
end


--- Appended to Rideable:onRegisterActionEvents: the training view key while riding.
function EqTrainingHooks.onRegisterActionEvents(vehicle, isActiveForInputIgnoreSelection)
    local spec = vehicle.spec_rideable
    if spec == nil or spec.actionEvents == nil or InputAction.EQ_TRAINING_VIEW == nil then return end
    spec.eqViewEventId = nil
    if not isActiveForInputIgnoreSelection then return end
    local _, id = vehicle:addActionEvent(spec.actionEvents, InputAction.EQ_TRAINING_VIEW, vehicle,
        function() EqTrainingHooks.onViewAction(vehicle) end, false, true, false, true, nil)
    if id ~= nil then
        spec.eqViewEventId = id
        g_inputBinding:setActionEventText(id, viewActionText())
        g_inputBinding:setActionEventTextPriority(id, GS_PRIO_NORMAL)
    end
end


--- "[======----]" for a 0-100 meter.
--- @param value number
--- @return string
function EqTrainingHooks.bar(value)
    local filled = math.floor(EqStats.clamp(value, 0, 100) / 10 + 0.5)
    return "[" .. string.rep("=", filled) .. string.rep("-", 10 - filled) .. "]"
end


--- "Stamina: 45% - training fast": a stat's share of its best day so far, and how it is training now.
--- @param stat string
--- @param effort table from EqTraining.playerEffort
--- @param sheet table
--- @return string
local function statLine(stat, effort, sheet)
    local cap = EqTraining.EFFORT_CAP[stat]
    local percent = math.floor(effort[stat] / cap * 100 + 0.5)
    local line = string.format("%s: %d%%", g_i18n:getText("eq_stat_" .. stat), percent)
    local band
    if effort[stat] >= cap then
        band = "full"
    elseif sheet.quality[stat] ~= nil then
        band = EqTraining.qualityBand(sheet.quality[stat])
    end
    if band ~= nil then line = line .. " - " .. g_i18n:getText("eq_train_quality_" .. band) end
    return line
end


--- Appended to Rideable:onDraw: the training view, from the server's sheet. Every line stays
--- short, because the help panel cuts long lines off.
function EqTrainingHooks.onDraw(vehicle, isActiveForInputIgnoreSelection)
    if not isActiveForInputIgnoreSelection then return end
    local spec = vehicle.spec_rideable
    if spec == nil then return end

    local id = getRiddenId(spec)
    local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
    if sheet == nil then return end

    local show = function(text) g_currentMission:addExtraPrintText(text) end
    local view = EqTrainingHooks.getView()
    local effort = EqTraining.playerEffort(sheet)

    local title = string.format(g_i18n:getText("eq_train_title"), g_i18n:getText("eq_train_view_" .. view))
    if isTired(spec.cluster) then title = title .. " - " .. g_i18n:getText("eq_train_worn") end
    show(title)

    local band = view == "speed" and ("sprint_" .. EqTraining.sprintBand(sheet.tiredness))
        or ("tired_" .. EqTraining.tirednessBand(sheet.tiredness))
    show(string.format("%s: %s %d%% - %s", g_i18n:getText("eq_train_tiredness"), EqTrainingHooks.bar(sheet.tiredness),
        math.floor(sheet.tiredness + 0.5), g_i18n:getText("eq_train_" .. band)))
    if view ~= "speed" and sheet.run >= 1 then
        show(string.format(g_i18n:getText("eq_train_run"), math.floor(sheet.run)))
    end

    if view == "freestyle" then
        for _, stat in ipairs(EqConstants.STAT_KEYS) do show(statLine(stat, effort, sheet)) end
    else
        for i = 1, EqTrainingHooks.TIPS[view] do show(g_i18n:getText(string.format("eq_train_tip_%s_%d", view, i))) end
        show(statLine(view, effort, sheet))
        local others = {}
        for _, stat in ipairs(EqConstants.STAT_KEYS) do
            if stat ~= view then
                table.insert(others, string.format("%s %d%%", g_i18n:getText("eq_stat_short_" .. stat),
                    math.floor(effort[stat] / EqTraining.EFFORT_CAP[stat] * 100 + 0.5)))
            end
        end
        show(g_i18n:getText("eq_train_others") .. ": " .. table.concat(others, " "))
        return
    end

    -- "Training in: Outdoor arena", then one line per bonus. Freestyle only, to keep the focused
    -- views short.
    local inside = {}
    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do
        local facilityTitle, bonuses = EqFacilityHooks.insideText(kind, farmId)
        table.insert(inside, {title = facilityTitle, bonuses = bonuses})
    end
    table.sort(inside, function(x, y) return x.title < y.title end)
    for _, facility in ipairs(inside) do
        show(string.format(g_i18n:getText("eq_facility_inside"), facility.title))
        for _, bonus in ipairs(facility.bonuses) do show(bonus) end
    end
    local feedLine = EqFeedHooks.formatBoost(EqFeedHooks.getBoost(spec.cluster))
    if feedLine ~= nil then show(feedLine) end
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
    local day = {
        sheet = not resting and sheet or nil,
        riding = not resting and animal.riding or 0,
        dirt = animal.dirt,
        ageMonths = animal.age or 0,
        timeAdjustment = g_currentMission.environment.timeAdjustment or 1,
        facilityOwned = owned,
        facilityRidden = ridden,
        feedBoost = EqFeedHooks.getBoost(animal),
        rate = EqSettings.trainingRate(EqCompetitionManager.settings),
    }
    local deltas, detail = EqTraining.applyDay(record, record:getCeilings(), day)

    local notes = EqStatLog.explainDay(detail, day, { resting = resting, focus = record.focus, sheet = day.sheet,
        playerPoints = EqTraining.playerRidingPoints(day.sheet) })
    table.insert(notes, string.format("RLRM before its daily update: fitness %s health %s dirt %s riding %s",
        tostring(animal.fitness), tostring(animal.health), tostring(animal.dirt), tostring(animal.riding)))
    EqStatLog.add(record.id, g_currentMission.environment.currentMonotonicDay or 0, "daily training", deltas, notes, record.trained)

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

    if Rideable.onRegisterActionEvents ~= nil then
        Rideable.onRegisterActionEvents = Utils.appendedFunction(Rideable.onRegisterActionEvents,
            function(self, isActiveForInput, isActiveForInputIgnoreSelection)
                if not EqMain.isActive or not self.isClient then return end
                guarded("training view key", function() EqTrainingHooks.onRegisterActionEvents(self, isActiveForInputIgnoreSelection) end)
            end)
    else
        Log:warning("EqTrainingHooks: Rideable.onRegisterActionEvents missing; no training view key")
    end

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

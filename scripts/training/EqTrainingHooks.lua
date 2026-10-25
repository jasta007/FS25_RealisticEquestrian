--[[
    EqTrainingHooks.lua
    Wires EqTraining into the game.

    - Rideable.updateRiding and Rideable.jump (base game) record the player's riding into a sheet
      per horse. Vehicle functions are copied into each vehicle type when types are registered,
      so these two are patched at source time, before that happens; the hook bodies stay idle
      until EqMain is active. Both run on the server only, which is where riding is counted.
    - Rideable.updateRiding also steps the tiredness meter and the focused stamina and speed work
      (EqTraining.step), at a halt too; a fitter horse tires more slowly.
    - Rideable.onDraw shows the training panel while riding (EqTrainingHud): the exertion meter
      and a line per stat for today's training; the farm's facility the horse is
      inside (EqFacilityHooks) and the boost its feed gives (EqFeedHooks) in the help panel. The
      training view key (Y, Rideable.onRegisterActionEvents) switches to a focused view for one
      stat; H, and the first time each view opens, shows its help popups.
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


--- Backing up tires a horse faster than the base game counts, and a fit horse's bar fills more
--- slowly: add the difference to (or take it off) its riding bar.
--- @param spec table spec_rideable
--- @param gait string
--- @param factor number EqTraining.ridingBarFactor
--- @param dt number milliseconds
local function adjustRiding(spec, gait, factor, dt)
    local cluster = spec.cluster
    if cluster.changeRiding == nil then return end
    local fullMs = cluster.getDailyRidingTime ~= nil and cluster:getDailyRidingTime() or EqConstants.RIDING_FULL_MS
    local points
    points, spec.eqReverseTimer = EqTraining.ridingAdjust(spec.eqReverseTimer, dt, gait, factor, fullMs)
    if points ~= 0 then cluster:changeRiding(points) end
end


-- Jumps: while the horse is in the air we look straight down from it for anything with a
-- collision that is not the ground. A jump counts as cleared when something at least
-- JUMP_MIN_HEIGHT tall was under it in the air and it did not land on top of it.
EqTrainingHooks.JUMP_MIN_HEIGHT = 0.25
EqTrainingHooks.JUMP_RAY_UP = 0.3
EqTrainingHooks.JUMP_RAY_LENGTH = 4
EqTrainingHooks.JUMP_TIMEOUT_MS = 3000
-- Without a ground flag a jump is judged this long after take-off.
EqTrainingHooks.JUMP_FALLBACK_MS = 1500

-- A walk or trot counts as a turn while the horse's heading changes faster than TURN_RATE
-- radians a second for TURN_HOLD_MS.
EqTrainingHooks.TURN_RATE = 0.35
EqTrainingHooks.TURN_HOLD_MS = 400

local probe = { vehicle = nil, height = nil, name = nil }


--- raycastAll callback: skip the horse itself, keep the first thing below it.
function EqTrainingHooks:jumpRaycastCallback(hitObjectId, x, y, z, distance)
    if hitObjectId == nil or hitObjectId == 0 then return true end
    if g_currentMission.terrainRootNode ~= nil and hitObjectId == g_currentMission.terrainRootNode then return true end
    local object = g_currentMission.getNodeObject ~= nil and g_currentMission:getNodeObject(hitObjectId) or nil
    if object ~= nil and object == probe.vehicle then return true end
    probe.height = y
    probe.name = getName ~= nil and getName(hitObjectId) or tostring(hitObjectId)
    return false
end


--- @return number collision mask for things a horse can jump: anything but the ground
local function jumpMask()
    local mask = 0
    for _, name in ipairs({ "DEFAULT", "STATIC_OBJECT", "BUILDING", "DYNAMIC_OBJECT", "TREE", "PLACEMENT_BLOCKING" }) do
        if CollisionFlag ~= nil and CollisionFlag[name] ~= nil then mask = mask + CollisionFlag[name] end
    end
    return mask
end


--- How tall the thing straight under the horse is, if there is one.
--- @param vehicle table
--- @return number|nil height above the ground in metres
local function obstacleBelow(vehicle)
    if raycastAll == nil or vehicle.rootNode == nil then return nil end
    local x, y, z = getWorldTranslation(vehicle.rootNode)
    local ground = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, y, z)
    probe.vehicle, probe.height, probe.name = vehicle, nil, nil
    raycastAll(x, y + EqTrainingHooks.JUMP_RAY_UP, z, 0, -1, 0, EqTrainingHooks.JUMP_RAY_LENGTH,
        "jumpRaycastCallback", EqTrainingHooks, jumpMask())
    probe.vehicle = nil
    if probe.height == nil then return nil end
    return probe.height - ground
end


--- Follow a jump through the air and judge it on landing.
--- @param vehicle table
--- @param spec table spec_rideable
--- @param sheet table
--- @param worn boolean
local function trackJump(vehicle, spec, sheet, worn)
    local jump = spec.eqJump
    if jump == nil then return end
    local age = (g_time or 0) - jump.startedAt
    local inAir
    if spec.isOnGround ~= nil then
        inAir = not spec.isOnGround
    else
        inAir = age < EqTrainingHooks.JUMP_FALLBACK_MS
    end

    local height = obstacleBelow(vehicle)
    if inAir then
        jump.airborne = true
        if height ~= nil and height > jump.best then jump.best, jump.over = height, probe.name end
        if age < EqTrainingHooks.JUMP_TIMEOUT_MS then return end
    elseif not jump.airborne and age < 500 then
        return
    end

    spec.eqJump = nil
    local landedOnTop = height ~= nil and height >= EqTrainingHooks.JUMP_MIN_HEIGHT
    local cleared = jump.best >= EqTrainingHooks.JUMP_MIN_HEIGHT and not landedOnTop
    Log:info("Jump: %s (tallest thing under the horse %.2f m '%s'%s, %d ms, ground flag %s)",
        cleared and "cleared" or "nothing cleared", jump.best, tostring(jump.over), landedOnTop and ", landed on top of it" or "",
        age, tostring(spec.isOnGround ~= nil))
    if cleared then
        EqTrainingHud.pop("jump", EqTraining.clearJump(sheet, worn))
    else
        EqTraining.emptyJump(sheet, worn)
    end
end


--- The routine's name for what the horse is doing: a gait, a halt, or a turn at a walk or trot.
--- @param vehicle table
--- @param spec table
--- @param gait string
--- @param dt number
--- @return string move
local function routineMove(vehicle, spec, gait, dt)
    if gait == "canter" or gait == "gallop" then return "fast" end
    local dx, _, dz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
    local heading = math.atan2(dx, dz)
    local turn = 0
    if spec.eqHeading ~= nil and dt > 0 then
        local change = heading - spec.eqHeading
        if change > math.pi then change = change - 2 * math.pi elseif change < -math.pi then change = change + 2 * math.pi end
        turn = change / (dt / 1000)
    end
    spec.eqHeading = heading
    if (gait == "walk" or gait == "trot") and math.abs(turn) > EqTrainingHooks.TURN_RATE then
        local side = turn > 0 and "left" or "right"
        spec.eqTurnMs = spec.eqTurnSide == side and (spec.eqTurnMs or 0) + dt or dt
        spec.eqTurnSide = side
        if spec.eqTurnMs >= EqTrainingHooks.TURN_HOLD_MS then return side end
    else
        spec.eqTurnMs, spec.eqTurnSide = 0, nil
    end
    return gait
end


--- @return boolean true when the routine runs: it only asks for moves where the rider sees them
local function routineShown()
    local view = EqTrainingHooks.getView()
    return view == "freestyle" or view == "temperament"
end


-- A jump (and the stumble after landing) can knock the gait or speed down for a moment. A
-- rider sometimes has to jump to keep the pace, so stamina and speed training (and the jump
-- combo clock) carry on at the
-- gait from before take-off until this long after landing.
EqTrainingHooks.JUMP_PACE_HOLD_MS = 1500

local PACE_GAITS = { trot = true, canter = true, gallop = true }

--- @param spec table
--- @param gait string the gait this frame
--- @param now number g_time
--- @return string gait for stamina and speed training
local function paceGait(spec, gait, now)
    local held = spec.eqJumpGait
    if held == nil or not PACE_GAITS[held] then return gait end
    if spec.eqJump == nil and now > (spec.eqJumpHoldUntil or 0) then
        spec.eqJumpGait = nil
        return gait
    end
    return held
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
    local record = EqRegistry.getById(id)
    local stamina = record ~= nil and record.trained.stamina or nil
    local pace = paceGait(spec, gait, now)
    EqTraining.step(sheet, pace, dt, worn, stamina)
    spec.eqLastGait = gait

    local wasJumping = spec.eqJump ~= nil
    trackJump(vehicle, spec, sheet, worn)
    if wasJumping and spec.eqJump == nil then spec.eqJumpHoldUntil = now + EqTrainingHooks.JUMP_PACE_HOLD_MS end

    -- The base game stops a horse that runs into something and counts its haltTimer down. A
    -- crash ends a jump combo (a refusal) and breaks a routine, but not a stamina run.
    local halted = (spec.haltTimer or 0) > 0
    if halted and not spec.eqHalted then
        local hadCombo, hadRoutine = sheet.combo.count > 0, EqTraining.breakRoutine(sheet)
        sheet.combo.count, sheet.combo.timer = 0, 0
        Log:info("Crash: the horse ran into something at a %s (haltTimer %s)", gait, tostring(spec.haltTimer))
        if hadCombo or hadRoutine then EqTrainingHud.pop("crash") end
    end
    spec.eqHalted = halted
    if EqTraining.comboTick(sheet, pace, dt) then EqTrainingHud.pop("jumpLost") end
    if routineShown() then
        local event = EqTraining.routineStep(sheet, routineMove(vehicle, spec, gait, dt), dt, worn, math.random)
        if event == "done" then EqTrainingHud.pop("routine", sheet.routine.mult)
        elseif event == "lost" then EqTrainingHud.pop("routineLost")
        elseif event == "start" then EqTrainingHud.pop("routineStart") end
    elseif EqTraining.breakRoutine(sheet) then
        EqTrainingHud.pop("routineLost")
    end

    if worn or gait == "halt" then return end

    sheet.barFactor = EqTraining.ridingBarFactor(stamina)
    EqTraining.addRiding(sheet, gait, dt)
    adjustRiding(spec, gait, sheet.barFactor, dt)
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do EqTraining.addInside(sheet, kind, dt) end
end


--- Appended to Rideable:jump (the server branch: in multiplayer a client's JumpEvent calls it
--- on the server). The jump is judged in the air by trackJump; any jump ends a routine, but a
--- stamina run or sprint keeps its pace through it (paceGait).
function EqTrainingHooks.onJump(vehicle)
    local spec = vehicle.spec_rideable
    if spec == nil then return end

    local id = getRiddenId(spec)
    if id == nil then return end

    local sheet = EqTrainingHooks.getSheet(id)
    EqTraining.addJump(sheet)
    if EqTraining.breakRoutine(sheet) then EqTrainingHud.pop("routineLost") end
    spec.eqJump = { startedAt = g_time or 0, best = 0, airborne = false }
    spec.eqJumpGait, spec.eqJumpHoldUntil = spec.eqLastGait, nil
end


-- Riding HUD views, switched with the training view key (Y). Freestyle shows every stat; a
-- focused view shows the one stat it trains. Help popups (H, and the first time a view
-- opens) explain each view in HELP_PAGES pages.
EqTrainingHooks.VIEWS = { "freestyle", "stamina", "speed", "agility", "temperament" }
EqTrainingHooks.HELP_PAGES = { freestyle = 2, stamina = 2, speed = 2, agility = 2, temperament = 2 }
EqTrainingHooks.viewIndex = 1


--- @return string view a VIEWS name
function EqTrainingHooks.getView()
    return EqTrainingHooks.VIEWS[EqTrainingHooks.viewIndex] or "freestyle"
end


--- @return string text for the action in the help panel
local function viewActionText()
    return string.format(g_i18n:getText("eq_train_viewAction"), g_i18n:getText("eq_train_view_" .. EqTrainingHooks.getView()))
end


--- Show a view's help popups.
--- @param view string
function EqTrainingHooks.showHelp(view)
    local pages = {}
    local title = g_i18n:getText("eq_help_" .. view .. "_title")
    for i = 1, EqTrainingHooks.HELP_PAGES[view] or 0 do
        table.insert(pages, { title = title, text = g_i18n:getText(string.format("eq_help_%s_%d", view, i)) })
    end
    EqTrainingHud.showHelp(pages)
end


--- The training view key was pressed.
function EqTrainingHooks.onViewAction(vehicle)
    EqTrainingHooks.viewIndex = EqTrainingHooks.viewIndex % #EqTrainingHooks.VIEWS + 1
    local spec = vehicle.spec_rideable
    local event = spec ~= nil and spec.eqViewEventId or nil
    if event ~= nil then g_inputBinding:setActionEventText(event, viewActionText()) end
    EqTrainingHud.closeHelp()
end


--- Appended to Rideable:onRegisterActionEvents: the training view and help keys while riding.
function EqTrainingHooks.onRegisterActionEvents(vehicle, isActiveForInputIgnoreSelection)
    local spec = vehicle.spec_rideable
    if spec == nil or spec.actionEvents == nil or InputAction.EQ_TRAINING_VIEW == nil then return end
    spec.eqViewEventId = nil
    if not isActiveForInputIgnoreSelection then
        EqTrainingHud.closeHelp()
        return
    end
    local _, id = vehicle:addActionEvent(spec.actionEvents, InputAction.EQ_TRAINING_VIEW, vehicle,
        function() EqTrainingHooks.onViewAction(vehicle) end, false, true, false, true, nil)
    if id ~= nil then
        spec.eqViewEventId = id
        g_inputBinding:setActionEventText(id, viewActionText())
        g_inputBinding:setActionEventTextPriority(id, GS_PRIO_NORMAL)
    end
    if InputAction.EQ_TRAINING_HELP ~= nil then
        local _, helpId = vehicle:addActionEvent(spec.actionEvents, InputAction.EQ_TRAINING_HELP, vehicle,
            function() EqTrainingHooks.showHelp(EqTrainingHooks.getView()) end, false, true, false, true, nil)
        if helpId ~= nil then
            g_inputBinding:setActionEventText(helpId, g_i18n:getText("input_EQ_TRAINING_HELP"))
            g_inputBinding:setActionEventTextPriority(helpId, GS_PRIO_LOW)
        end
    end
end


local COLOR = EqTrainingHud.COLOR
local BAND_COLOR = {
    tired_fresh = COLOR.blue, tired_warm = COLOR.yellow, tired_zone = COLOR.green, tired_blown = COLOR.red,
    sprint_fresh = COLOR.green, sprint_tiring = COLOR.yellow, sprint_stale = COLOR.red,
}
local QUALITY_COLOR = { fast = COLOR.green, steady = COLOR.yellow, slow = COLOR.grey, full = COLOR.green }


--- A panel row for a stat: "Stamina 45%" and how it is training now, in that state's colour.
--- @param stat string
--- @param effort table from EqTraining.playerEffort
--- @param sheet table
--- @return table row
local function statRow(stat, effort, sheet)
    local cap = EqTraining.EFFORT_CAP[stat]
    local band
    if effort[stat] >= cap then
        band = "full"
    elseif sheet.quality[stat] ~= nil then
        band = EqTraining.qualityBand(sheet.quality[stat])
    end
    return {
        left = string.format("%s %d%%", g_i18n:getText("eq_stat_" .. stat), math.floor(effort[stat] / cap * 100 + 0.5)),
        right = band ~= nil and g_i18n:getText("eq_train_quality_" .. band) or nil,
        rightColor = band ~= nil and QUALITY_COLOR[band] or nil,
    }
end


--- Appended to Rideable:onDraw: the training panel, from the server's sheet, and the help popups.
function EqTrainingHooks.onDraw(vehicle, isActiveForInputIgnoreSelection)
    if not isActiveForInputIgnoreSelection then return end
    local spec = vehicle.spec_rideable
    if spec == nil then return end

    local view = EqTrainingHooks.getView()
    if not EqTrainingHud.isHelpShowing() and not EqTrainingHud.hasSeen(view) then
        EqTrainingHud.markSeen(view)
        EqTrainingHooks.showHelp(view)
    end
    EqTrainingHud.drawHelp()

    local id = getRiddenId(spec)
    local sheet = id ~= nil and EqTrainingHooks.sheets[id] or nil
    if sheet == nil then return end

    local effort = EqTraining.playerEffort(sheet)
    local rows = {}
    if view == "freestyle" or view == "stamina" or view == "speed" then
        local band = view == "speed" and ("sprint_" .. EqTraining.sprintBand(sheet.tiredness))
            or ("tired_" .. EqTraining.tirednessBand(sheet.tiredness))
        local bandColor = BAND_COLOR[band]
        table.insert(rows, { left = string.format("%s %d%%", g_i18n:getText("eq_train_tiredness"), math.floor(sheet.tiredness + 0.5)),
            right = g_i18n:getText("eq_train_" .. band), rightColor = bandColor })
        table.insert(rows, { bar = sheet.tiredness / 100, color = bandColor })
    end
    if view == "freestyle" or view == "stamina" then
        local full = sheet.run >= EqTraining.RUN_FULL
        table.insert(rows, { left = string.format(g_i18n:getText("eq_train_run"), math.floor(sheet.run)),
            leftColor = full and COLOR.green or COLOR.white })
    end

    local combo = sheet.combo
    if combo.count > 0 and (view == "freestyle" or view == "agility") then
        local mult = math.min(combo.count, EqTraining.COMBO_MAX)
        local color = EqTrainingHud.multColor(mult)
        table.insert(rows, { left = string.format(g_i18n:getText("eq_train_combo"), mult), leftColor = color,
            right = string.format("%d s", math.ceil(combo.timer)) })
        table.insert(rows, { bar = combo.timer / EqTraining.COMBO_SECONDS, color = color })
    elseif view == "agility" then
        table.insert(rows, { left = g_i18n:getText("eq_train_combo_none"), leftColor = COLOR.grey })
    end

    local routine = sheet.routine
    if routineShown() then
        if routine.active then
            local color = EqTrainingHud.multColor(routine.mult)
            local row = { left = string.format(g_i18n:getText("eq_train_routine"), routine.mult), leftColor = color }
            if routine.request ~= nil then
                local left = math.max(0, routine.deadline - routine.clock)
                row.right = g_i18n:getText("eq_move_" .. routine.request)
                row.rightColor = COLOR.yellow
                table.insert(rows, row)
                table.insert(rows, { bar = left / EqTraining.ROUTINE_REACT_MS, color = COLOR.yellow })
                EqTrainingHud.drawPrompt(g_i18n:getText("eq_move_" .. routine.request), left / EqTraining.ROUTINE_REACT_MS)
            else
                table.insert(rows, row)
            end
        elseif view == "temperament" then
            table.insert(rows, { left = g_i18n:getText("eq_train_routine_none"), leftColor = COLOR.grey })
        end
    end
    EqTrainingHud.drawPops()

    if view == "freestyle" then
        for _, stat in ipairs(EqConstants.STAT_KEYS) do table.insert(rows, statRow(stat, effort, sheet)) end
    else
        table.insert(rows, statRow(view, effort, sheet))
        local others = {}
        for _, stat in ipairs(EqConstants.STAT_KEYS) do
            if stat ~= view then
                table.insert(others, string.format("%s %d%%", g_i18n:getText("eq_stat_short_" .. stat),
                    math.floor(effort[stat] / EqTraining.EFFORT_CAP[stat] * 100 + 0.5)))
            end
        end
        table.insert(rows, { left = table.concat(others, "  "), leftColor = COLOR.grey })
    end
    if isTired(spec.cluster) then table.insert(rows, { left = g_i18n:getText("eq_train_worn"), leftColor = COLOR.orange }) end

    EqTrainingHud.drawPanel(string.format(g_i18n:getText("eq_train_title"), g_i18n:getText("eq_train_view_" .. view)), rows)

    -- "Training in: Outdoor arena", then one line per bonus, in the base game's help panel.
    local inside = {}
    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
    for kind in pairs(EqFacilityHooks.insideKinds(vehicle)) do
        local facilityTitle, bonuses = EqFacilityHooks.insideText(kind, farmId)
        table.insert(inside, {title = facilityTitle, bonuses = bonuses})
    end
    table.sort(inside, function(x, y) return x.title < y.title end)
    for _, facility in ipairs(inside) do
        g_currentMission:addExtraPrintText(string.format(g_i18n:getText("eq_facility_inside"), facility.title))
        for _, bonus in ipairs(facility.bonuses) do g_currentMission:addExtraPrintText(bonus) end
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

--[[
    main.lua
    The mod loader.

    The game sources mods alphabetically, and a modDesc dependency only makes sure RLRM is
    enabled, not that it loads first: FS25_RealisticEquestrian is sourced BEFORE
    FS25_RealisticLivestockRM. So this file only loads our own modules and installs hooks on
    base-game functions. Everything that touches RLRM waits for EqMain.activate, which runs
    once every mod has been sourced: at the first TypeManager.validateTypes call (the point
    mods use to add specializations, and early enough for later Rideable hooks), or at the
    latest when the mission finishes loading.
]]

local modDirectory = g_currentModDirectory

-- SECTION 1: Our own modules. None of them reads RLRM at file scope.
source(modDirectory .. "scripts/core/EqLog.lua")
source(modDirectory .. "scripts/core/EqRLRM.lua")
source(modDirectory .. "scripts/core/EqConstants.lua")
source(modDirectory .. "scripts/core/EqRandom.lua")
source(modDirectory .. "scripts/core/EqStats.lua")
source(modDirectory .. "scripts/core/EqHorseRecord.lua")
source(modDirectory .. "scripts/dealer/EqDealer.lua")
source(modDirectory .. "scripts/core/EqRegistry.lua")
source(modDirectory .. "scripts/training/EqTraining.lua")
source(modDirectory .. "scripts/training/EqTrainingHooks.lua")
source(modDirectory .. "scripts/competition/EqEventConfig.lua")
source(modDirectory .. "scripts/competition/EqCompetition.lua")
source(modDirectory .. "scripts/competition/EqRisk.lua")
source(modDirectory .. "scripts/competition/EqCompetitionManager.lua")
source(modDirectory .. "scripts/dealer/EqDealerHooks.lua")
source(modDirectory .. "scripts/gui/EqInfoDisplay.lua")
source(modDirectory .. "scripts/gui/EqEventsView.lua")
source(modDirectory .. "scripts/gui/EqEventsFrame.lua")
source(modDirectory .. "scripts/console/EqConsole.lua")

local Log = EqLog

EqMain = {}
EqMain.activated = false
EqMain.isActive = false


local failureCounts = {}

--- Every hook body runs under xpcall: these hooks sit inside the game's own load, save and
--- display code, next to RLRM's, so an error here must be logged and swallowed, never allowed
--- to abort the chain and take RLRM down with it. Display hooks run every frame, so each
--- context logs its first failure in full and then only every 1000th.
--- @param context string Name for the log line
--- @param fn function
local function guarded(context, fn)
    -- The game may strip the debug library, so the traceback is optional.
    local ok, err = xpcall(fn, function(e)
        local trace = (debug ~= nil and debug.traceback ~= nil) and ("\n" .. debug.traceback()) or ""
        return tostring(e) .. trace
    end)
    if ok then return end

    local count = (failureCounts[context] or 0) + 1
    failureCounts[context] = count
    if count == 1 then
        Log:error("%s failed: %s", context, err)
    elseif count % 1000 == 0 then
        Log:error("%s has failed %d times", context, count)
    end
end


--- Find RLRM and switch the mod on. Runs once, after every mod has been sourced.
function EqMain.activate()
    if EqMain.activated then return end
    EqMain.activated = true

    guarded("activation", function()
        EqMain.isActive = EqRLRM.init()
    end)

    if EqMain.isActive and EqRLRM.features.infoDisplay then
        guarded("info display hooks", function() EqInfoDisplay.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.eventsTab then
        guarded("events tab hook", function() EqEventsFrame.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.horsePricing then
        guarded("horse pricing hook", function() EqDealerHooks.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.menuLayout then
        guarded("menu layout hooks", function() EqInfoDisplay.installMenu(guarded) end)
    end

    if EqMain.isActive then
        guarded("training hooks", function() EqTrainingHooks.installDaily(guarded) end)
        guarded("competition setup", function()
            MoneyType.EQ_ENTRY_FEES = MoneyType.register("eqEntryFees", "eq_money_entryFees")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            MoneyType.EQ_PRIZE_MONEY = MoneyType.register("eqPrizeMoney", "eq_money_prizeMoney")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            MoneyType.EQ_VET_BILLS = MoneyType.register("eqVetBills", "eq_money_vetBills")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            MoneyType.EQ_TRANSPORT = MoneyType.register("eqTransport", "eq_money_transport")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            EqCompetitionManager.loadConfig(modDirectory)
        end)
    end

    if EqMain.isActive then
        Log:info("Realistic Equestrian active")
    else
        Log:error("Realistic Equestrian is switched off for this session; see the lines above.")
    end
end


-- SECTION 2: Hooks on base-game functions

-- Rideable's functions are copied into vehicle types when types are validated, so they are
-- patched now, at source time. The hook bodies do nothing until EqMain is active.
EqTrainingHooks.installRideable(guarded)


TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, function()
    EqMain.activate()
end)

--- Load the registry once the mission, and RLRM's animals with it, has finished loading.
local function onMissionLoaded(mission)
    EqMain.activate()
    if not EqMain.isActive then return end

    guarded("console registration", EqConsole.register)
    guarded("registry load", function()
        if mission:getIsServer() then
            EqRegistry.loadFromDirectory(mission.missionInfo.savegameDirectory)
        end
    end)

    guarded("competition start", function()
        if not mission:getIsServer() or EqCompetitionManager.config == nil then return end
        EqCompetitionManager.ensureOpen()
        g_messageCenter:subscribe(MessageType.DAY_CHANGED, function()
            guarded("daily events", EqCompetitionManager.onDayChanged)
        end, EqCompetitionManager)
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, function()
            guarded("monthly events", EqCompetitionManager.onPeriodChanged)
        end, EqCompetitionManager)
    end)
end

--- Save beside RLRM's rm_RlAnimalSystem.xml whenever the game saves.
local function onSave(missionInfo)
    if not EqMain.isActive then return end

    guarded("registry save", function()
        if g_currentMission == nil or not g_currentMission:getIsServer() then return end
        if missionInfo.savegameDirectory == nil then return end
        EqRegistry.saveToDirectory(missionInfo.savegameDirectory)
    end)
end

local function onMissionDelete()
    if not EqMain.isActive then return end

    guarded("mission cleanup", function()
        EqConsole.unregister()
        EqRegistry.reset()
        EqTrainingHooks.reset()
        g_messageCenter:unsubscribeAll(EqCompetitionManager)
        local config = EqCompetitionManager.config
        EqCompetitionManager.reset()
        EqCompetitionManager.config = config
    end)
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoaded)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, onSave)
FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, onMissionDelete)

Log:info("Realistic Equestrian sourced; waiting for Realistic Livestock to load")

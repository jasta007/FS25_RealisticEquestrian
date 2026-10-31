--[[
    main.lua
    The mod loader for Realistic Equestrian, by Jasta007.

    The game sources mods alphabetically, and a modDesc dependency only makes sure RLRM is
    enabled, not that it loads first: FS25_RealisticEquestrian is sourced BEFORE
    FS25_RealisticLivestockRM. So this file only loads our own modules and installs hooks on
    base-game functions. Everything that touches RLRM waits for EqMain.activate, which runs
    once every mod has been sourced: at the first TypeManager.validateTypes call (the point
    mods use to add specializations, and early enough for later Rideable hooks), or at the
    latest when the mission finishes loading.
]]

local modDirectory = g_currentModDirectory
local modName = g_currentModName

-- SECTION 1: Our own modules. None of them reads RLRM at file scope.
source(modDirectory .. "scripts/core/EqLog.lua")
source(modDirectory .. "scripts/core/EqI18N.lua")
source(modDirectory .. "scripts/core/EqRLRM.lua")
source(modDirectory .. "scripts/core/EqMessages.lua")
source(modDirectory .. "scripts/core/EqConstants.lua")
source(modDirectory .. "scripts/core/EqSettings.lua")
source(modDirectory .. "scripts/core/EqRandom.lua")
source(modDirectory .. "scripts/core/EqStats.lua")
source(modDirectory .. "scripts/core/EqHorseRecord.lua")
source(modDirectory .. "scripts/core/EqRole.lua")
source(modDirectory .. "scripts/core/EqStatLog.lua")
source(modDirectory .. "scripts/dealer/EqDealer.lua")
source(modDirectory .. "scripts/core/EqRegistry.lua")
source(modDirectory .. "scripts/core/EqFreshStart.lua")
source(modDirectory .. "scripts/training/EqExertion.lua")
source(modDirectory .. "scripts/training/EqJump.lua")
source(modDirectory .. "scripts/training/EqTraining.lua")
source(modDirectory .. "scripts/training/EqDressagePath.lua")
source(modDirectory .. "scripts/training/EqDressage.lua")
source(modDirectory .. "scripts/training/EqDressageHooks.lua")
source(modDirectory .. "scripts/training/EqDressageTests.lua")
source(modDirectory .. "scripts/training/EqCourse.lua")
source(modDirectory .. "scripts/training/EqShowJumping.lua")
source(modDirectory .. "scripts/training/EqCourseGlow.lua")
source(modDirectory .. "scripts/training/EqCourseHooks.lua")
source(modDirectory .. "scripts/training/EqDressageEditor.lua")
source(modDirectory .. "scripts/training/EqPoles.lua")
source(modDirectory .. "scripts/gui/EqTrainingHud.lua")
source(modDirectory .. "scripts/training/EqTrainingHooks.lua")
source(modDirectory .. "scripts/training/EqLateral.lua")
source(modDirectory .. "scripts/training/EqMetabolism.lua")
source(modDirectory .. "scripts/training/EqLooseHorses.lua")
source(modDirectory .. "scripts/staff/EqStaffNames.lua")
source(modDirectory .. "scripts/staff/EqStaff.lua")
source(modDirectory .. "scripts/staff/EqStaffManager.lua")
source(modDirectory .. "scripts/facilities/EqFacility.lua")
source(modDirectory .. "scripts/facilities/EqFacilityHooks.lua")
source(modDirectory .. "scripts/facilities/EqXcFlags.lua")
source(modDirectory .. "scripts/facilities/EqFlagLabels.lua")
source(modDirectory .. "scripts/facilities/EqPlaceAnywhere.lua")
source(modDirectory .. "scripts/facilities/EqXcHide.lua")
source(modDirectory .. "scripts/facilities/EqJumpColours.lua")
source(modDirectory .. "scripts/facilities/EqXcCorners.lua")
source(modDirectory .. "scripts/facilities/EqSponsors.lua")
source(modDirectory .. "scripts/hosting/EqHosting.lua")
source(modDirectory .. "scripts/hosting/EqHostVenue.lua")
source(modDirectory .. "scripts/hosting/EqHostManager.lua")
source(modDirectory .. "scripts/training/EqFeed.lua")
source(modDirectory .. "scripts/training/EqFeedHooks.lua")
source(modDirectory .. "scripts/competition/EqEventConfig.lua")
source(modDirectory .. "scripts/competition/EqPerformance.lua")
source(modDirectory .. "scripts/competition/EqRivals.lua")
source(modDirectory .. "scripts/competition/EqStory.lua")
source(modDirectory .. "scripts/competition/EqCompetition.lua")
source(modDirectory .. "scripts/competition/EqExperience.lua")
source(modDirectory .. "scripts/competition/EqRisk.lua")
source(modDirectory .. "scripts/competition/EqInjury.lua")
source(modDirectory .. "scripts/competition/EqCompetitionManager.lua")
source(modDirectory .. "scripts/competition/EqAway.lua")
source(modDirectory .. "scripts/dealer/EqDealerHooks.lua")
source(modDirectory .. "scripts/dealer/EqDelivery.lua")
source(modDirectory .. "scripts/gui/EqSkillsHudBox.lua")
source(modDirectory .. "scripts/gui/EqInfoDisplay.lua")
source(modDirectory .. "scripts/gui/EqListBadge.lua")
source(modDirectory .. "scripts/gui/EqRoleMenu.lua")
source(modDirectory .. "scripts/gui/EqEventsView.lua")
source(modDirectory .. "scripts/gui/EqHostView.lua")
source(modDirectory .. "scripts/gui/EqEventsFrame.lua")
source(modDirectory .. "scripts/gui/EqStaffFrame.lua")
source(modDirectory .. "scripts/gui/EqMenuPaging.lua")
source(modDirectory .. "scripts/gui/EqMessagesLink.lua")
source(modDirectory .. "scripts/gui/EqAnimalsPageButton.lua")
source(modDirectory .. "scripts/gui/EqRideButton.lua")
source(modDirectory .. "scripts/gui/EqSettingsPage.lua")
source(modDirectory .. "scripts/gui/EqWelcome.lua")
source(modDirectory .. "scripts/console/EqConsole.lua")
source(modDirectory .. "scripts/console/EqProbe.lua")

local Log = EqLog

-- Our money types' Finances rows. Like RLRM, they must be in FinanceStats.statNames before any
-- farm is created. The money popup and the Finances page look their titles up without a mod
-- name (see EqI18N): one key each for the MoneyType title and the "finance_" key the Finances
-- page asks for.
EqMain = {}
EqMain.MONEY_STATS = {
    { name = "eqEntryFees", title = "eq_money_entryFees" },
    { name = "eqPrizeMoney", title = "eq_money_prizeMoney" },
    { name = "eqVetBills", title = "eq_money_vetBills" },
    { name = "eqTransport", title = "eq_money_transport" },
    { name = "eqStaffWages", title = "eq_money_staffWages" },
    { name = "eqHosting", title = "eq_money_hosting" },
}
for _, stat in ipairs(EqMain.MONEY_STATS) do
    if FinanceStats.statNameToIndex[stat.name] == nil then
        table.insert(FinanceStats.statNames, stat.name)
        FinanceStats.statNameToIndex[stat.name] = #FinanceStats.statNames
    end
end

--- Share the money titles with lookups that carry no mod name. Run at source time and again
--- when the money types are registered, in case our texts were not loaded yet the first time.
function EqMain.copyMoneyTexts()
    local keys, aliases = {}, {}
    for _, stat in ipairs(EqMain.MONEY_STATS) do
        table.insert(keys, stat.title)
        aliases["finance_" .. stat.name] = stat.title
    end
    EqI18N.share(keys, aliases)
end
EqI18N.install()
EqMain.copyMoneyTexts()

EqMain.activated = false
EqMain.isActive = false


--- Every hook body runs protected: these hooks sit inside the game's own load, save and
--- display code, next to RLRM's, so an error here must be logged and swallowed, never allowed
--- to abort the chain and take RLRM down with it. EqLog.guard logs each context's first
--- failure in full and then only every 1000th, as display hooks run every frame.
--- @param context string Name for the log line
--- @param fn function
local function guarded(context, fn)
    EqLog.guard(context, fn)
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
        guarded("staff tab hook", function() EqStaffFrame.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.eventsTab and EqRLRM.features.messageLink then
        guarded("message link hooks", function() EqMessagesLink.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.rideButton then
        guarded("ride button hook", function() EqRideButton.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.menuPaging then
        guarded("menu paging hook", function() EqMenuPaging.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.animalsPageButton then
        guarded("animals page button hook", function() EqAnimalsPageButton.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.horsePricing then
        guarded("horse pricing hook", function() EqDealerHooks.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.dealerDelivery then
        guarded("dealer delivery hook", function() EqDelivery.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.listBadge then
        guarded("list badge hook", function() EqListBadge.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.roleMenu then
        guarded("role menu hooks", function() EqRoleMenu.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.metabolismFitness then
        guarded("metabolism hook", function() EqMetabolism.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.looseHorses then
        guarded("loose horses hook", function() EqLooseHorses.install(guarded) end)
    end

    if EqMain.isActive and EqRLRM.features.awayVisuals then
        guarded("away horses hook", function() EqAway.install(guarded) end)
    end

    if EqMain.isActive then
        guarded("welcome popups hooks", function() EqWelcome.install(guarded) end)
        guarded("message log", EqMessages.install)
        guarded("settings page hook", function() EqSettingsPage.install(guarded, EqRLRM.features.settingsTab) end)
    end

    if EqMain.isActive and EqRLRM.features.menuLayout then
        guarded("menu layout hooks", function() EqInfoDisplay.installMenu(guarded) end)
    end

    if EqMain.isActive then
        guarded("training hooks", function() EqTrainingHooks.installDaily(guarded) end)
        guarded("competition setup", function()
            EqMain.copyMoneyTexts()
            MoneyType.EQ_ENTRY_FEES = MoneyType.register("eqEntryFees", "eq_money_entryFees")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            MoneyType.EQ_PRIZE_MONEY = MoneyType.register("eqPrizeMoney", "eq_money_prizeMoney")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            MoneyType.EQ_VET_BILLS = MoneyType.register("eqVetBills", "eq_money_vetBills")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            MoneyType.EQ_TRANSPORT = MoneyType.register("eqTransport", "eq_money_transport")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            MoneyType.EQ_STAFF_WAGES = MoneyType.register("eqStaffWages", "eq_money_staffWages")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            MoneyType.EQ_HOSTING = MoneyType.register("eqHosting", "eq_money_hosting")
            MoneyType.LAST_ID = MoneyType.LAST_ID + 1
            EqCompetitionManager.loadConfig(modDirectory)
            EqInjury.loadConfig(modDirectory)
        end)
        if EqRLRM.features.injuries then
            guarded("injury hooks", function() EqInjury.install(guarded) end)
        end
        guarded("facilities setup", function() EqFacilityHooks.loadConfig(modDirectory) end)
        guarded("hosting setup", function() EqHostVenue.loadConfig(modDirectory) end)
    end

    if EqMain.isActive then
        Log:info("Realistic Equestrian by %s active", EqRandom.mark())
        EqMain.checkMark()
    else
        Log:error("Realistic Equestrian is switched off for this session; see the lines above.")
    end
end


--- Note in the log when this copy no longer names its maker, so a reupload under another name
--- still says where it came from.
function EqMain.checkMark()
    local mark = EqRandom.mark()
    local mod = g_modManager ~= nil and modName ~= nil and g_modManager:getModByName(modName) or nil
    local author = mod ~= nil and tostring(mod.author or "") or mark
    if EqConstants.AUTHOR ~= mark or not string.find(author:lower(), mark:lower(), 1, true) then
        Log:warning("This copy of Realistic Equestrian has been changed (author '%s'); the original is by %s", author, mark)
    end
end


-- SECTION 2: Hooks on base-game functions

-- Rideable's functions are copied into vehicle types when types are validated, so they are
-- patched now, at source time. The hook bodies do nothing until EqMain is active.
EqTrainingHooks.installRideable(guarded)
EqLateral.install()
-- Loading triggers are created as the map loads, so the probe starts listening now.
guarded("probe hook", EqProbe.install)

-- The horse feed list has to be in place before the map's placeables (and their troughs) load,
-- and needs nothing from RLRM, so it is hooked now too.
guarded("horse feed hook", function() EqFeedHooks.install(guarded, modDirectory) end)
-- Cross country flags' guide lines show only in construction mode (and while a course is edited).
guarded("course flag hook", function() EqXcFlags.install(guarded) end)
guarded("flag label hook", function() EqFlagLabels.install(guarded) end)
guarded("place anywhere hook", function() EqPlaceAnywhere.install(guarded) end)
-- Cross country pieces hide outside construction, course editing and rounds; the shop's
-- "Always visible" configuration has to be registered before the store items load.
guarded("cross country pieces hook", function() EqXcHide.install(guarded) end)
-- Show jumps' pole and wing colour options, registered before the store items load too.
guarded("show jump colours hook", function() EqJumpColours.install(guarded) end)
guarded("corner flags hook", function() EqXcCorners.install(guarded) end)
guarded("sponsor boards hook", function() EqSponsors.install(guarded) end)


TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, function()
    EqMain.activate()
end)

--- Load the registry once the mission, and RLRM's animals with it, has finished loading.
local function onMissionLoaded(mission)
    EqMain.activate()
    if not EqMain.isActive then return end

    guarded("console registration", EqConsole.register)
    guarded("facility scan", EqFacilityHooks.scanMap)
    guarded("facility shop text", EqFacilityHooks.addStoreText)
    guarded("feed console registration", EqFeedHooks.register)
    guarded("dealer delivery start", function() EqDelivery.start(mission) end)
    guarded("loose horses start", function()
        if mission:getIsServer() then EqLooseHorses.start(mission) end
    end)
    guarded("registry load", function()
        if mission:getIsServer() then
            EqRegistry.loadFromDirectory(mission.missionInfo.savegameDirectory)
        end
    end)

    guarded("staff start", function()
        if mission:getIsServer() then EqStaffManager.start(guarded) end
    end)

    -- A farm bought with the map's starved horses in its barn: checked hourly, ahead of
    -- RLRM's daily low-health death roll.
    guarded("map horses fresh start", function()
        if not mission:getIsServer() then return end
        EqFreshStart.check()
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, function()
            guarded("map horses fresh start", EqFreshStart.check)
        end, EqFreshStart)
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

    -- Pastures may have drawn their horses before the saved entries loaded.
    guarded("away horses at load", function()
        if mission:getIsServer() then EqCompetitionManager.refreshAway(EqCompetitionManager.enteredAnimals()) end
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
        EqDelivery.stop(g_currentMission)
        EqLooseHorses.stop(g_currentMission)
        EqStaffManager.stop()
        EqHostManager.reset()
        EqFeedHooks.unregister()
        EqRegistry.reset()
        EqTrainingHooks.reset()
        EqTrainingHud.reset()
        EqWelcome.reset()
        EqStatLog.reset()
        EqFacilityHooks.reset()
        g_messageCenter:unsubscribeAll(EqCompetitionManager)
        g_messageCenter:unsubscribeAll(EqFreshStart)
        local config = EqCompetitionManager.config
        EqCompetitionManager.reset()
        EqCompetitionManager.config = config
    end)
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoaded)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, onSave)
FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, onMissionDelete)

Log:info("Realistic Equestrian sourced; waiting for Realistic Livestock to load")

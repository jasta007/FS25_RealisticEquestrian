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
source(modDirectory .. "scripts/core/EqRegistry.lua")
source(modDirectory .. "scripts/console/EqConsole.lua")

local Log = EqLog

EqMain = {}
EqMain.activated = false
EqMain.isActive = false


--- Every hook body runs under xpcall: these hooks sit inside the game's own load and save
--- chain, next to RLRM's, so an error here must be logged and swallowed, never allowed to abort
--- the chain and take RLRM down with it.
--- @param context string Name for the log line
--- @param fn function
local function guarded(context, fn)
    -- The game may strip the debug library, so the traceback is optional.
    local ok, err = xpcall(fn, function(e)
        local trace = (debug ~= nil and debug.traceback ~= nil) and ("\n" .. debug.traceback()) or ""
        return tostring(e) .. trace
    end)
    if not ok then Log:error("%s failed: %s", context, err) end
end


--- Find RLRM and switch the mod on. Runs once, after every mod has been sourced.
function EqMain.activate()
    if EqMain.activated then return end
    EqMain.activated = true

    guarded("activation", function()
        EqMain.isActive = EqRLRM.init()
    end)

    if EqMain.isActive then
        Log:info("Realistic Equestrian active")
    else
        Log:error("Realistic Equestrian is switched off for this session; see the lines above.")
    end
end


-- SECTION 2: Lifecycle hooks on base-game functions

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
    end)
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoaded)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, onSave)
FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, onMissionDelete)

Log:info("Realistic Equestrian sourced; waiting for Realistic Livestock to load")

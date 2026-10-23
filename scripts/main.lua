--[[
    main.lua
    The mod loader. Realistic Livestock (RLRM) is a declared dependency, so it is always loaded
    before this file runs and its RmLogging is already on the real global table.
]]

local modDirectory = g_currentModDirectory

if RmLogging == nil then
    print("Error: Realistic Equestrian needs Realistic Livestock (FS25_RealisticLivestockRM), which did not load. Realistic Equestrian stays disabled.")
    return
end

local Log = RmLogging.getLogger("RLEQ")
Log:info("Realistic Equestrian loading from %s", tostring(modDirectory))

-- SECTION 1: RLRM adapter, checked before anything hooks into RLRM
source(modDirectory .. "scripts/core/EqRLRM.lua")

local initOk, rlrmAvailable = pcall(EqRLRM.init)
if not initOk then
    Log:error("RLRM check failed: %s. Realistic Equestrian stays disabled.", tostring(rlrmAvailable))
    return
end
if not rlrmAvailable then return end

-- SECTION 2: Pure maths and data
source(modDirectory .. "scripts/core/EqConstants.lua")
source(modDirectory .. "scripts/core/EqRandom.lua")
source(modDirectory .. "scripts/core/EqStats.lua")
source(modDirectory .. "scripts/core/EqHorseRecord.lua")
source(modDirectory .. "scripts/core/EqRegistry.lua")

-- SECTION 3: Console
source(modDirectory .. "scripts/console/EqConsole.lua")


-- SECTION 4: Lifecycle hooks
-- Every hook body runs under xpcall: these hooks sit inside the game's own mission load and
-- save chain, next to RLRM's, so an error here must be logged and swallowed, never allowed to
-- abort the chain and take RLRM down with it.

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

--- Load the registry once the mission, and RLRM's animals with it, has finished loading.
local function onMissionLoaded(mission)
    guarded("console registration", EqConsole.register)
    guarded("registry load", function()
        if mission:getIsServer() then
            EqRegistry.loadFromDirectory(mission.missionInfo.savegameDirectory)
        end
    end)
end

--- Save beside RLRM's rm_RlAnimalSystem.xml whenever the game saves.
local function onSave(missionInfo)
    guarded("registry save", function()
        if g_currentMission == nil or not g_currentMission:getIsServer() then return end
        if missionInfo.savegameDirectory == nil then return end
        EqRegistry.saveToDirectory(missionInfo.savegameDirectory)
    end)
end

local function onMissionDelete()
    guarded("mission cleanup", function()
        EqConsole.unregister()
        EqRegistry.reset()
    end)
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoaded)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, onSave)
FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, onMissionDelete)

Log:info("Realistic Equestrian loaded")

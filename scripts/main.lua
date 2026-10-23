--[[
    main.lua
    The mod loader. Realistic Livestock (RLRM) is a declared dependency, so it is always loaded
    before this file runs and its RmLogging is already on the real global table.
]]

local modDirectory = g_currentModDirectory

local Log = RmLogging.getLogger("RLEQ")
Log:info("Realistic Equestrian %s loading", tostring(g_modManager:getModByName(g_currentModName).version))

-- SECTION 1: RLRM adapter, checked before anything hooks into RLRM
source(modDirectory .. "scripts/core/EqRLRM.lua")

if not EqRLRM.init() then return end

-- SECTION 2: Pure maths and data
source(modDirectory .. "scripts/core/EqConstants.lua")
source(modDirectory .. "scripts/core/EqRandom.lua")
source(modDirectory .. "scripts/core/EqStats.lua")
source(modDirectory .. "scripts/core/EqHorseRecord.lua")
source(modDirectory .. "scripts/core/EqRegistry.lua")

-- SECTION 3: Console
source(modDirectory .. "scripts/console/EqConsole.lua")


-- SECTION 4: Lifecycle hooks

--- Load the registry once the mission, and RLRM's animals with it, has finished loading.
local function onMissionLoaded(mission)
    if mission:getIsServer() then
        EqRegistry.loadFromDirectory(mission.missionInfo.savegameDirectory)
    end
    EqConsole.register()
end

--- Save beside RLRM's rm_RlAnimalSystem.xml whenever the game saves.
local function onSave(missionInfo)
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if missionInfo.savegameDirectory == nil then return end
    EqRegistry.saveToDirectory(missionInfo.savegameDirectory)
end

local function onMissionDelete()
    EqConsole.unregister()
    EqRegistry.reset()
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoaded)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, onSave)
FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, onMissionDelete)

Log:info("Realistic Equestrian loaded")

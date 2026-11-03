--[[
    EqRLRMWarning.lua
    A startup popup when Realistic Livestock (RLRM) is too old for this mod. A missing RLRM is
    normally caught by the game's mod selection (modDesc dependency); this covers an RLRM that
    loads but lacks what we need, or is older than EqRLRM.MIN_VERSION. Shown once per save load,
    after the save has loaded and once no other dialog (RLRM's own startup ones) is open.
]]

EqRLRMWarning = {}

EqRLRMWarning.shown = false

-- Popup text per EqRLRM.problem.
EqRLRMWarning.TEXTS = {
    missing = "eq_rlrm_missing",
    incompatible = "eq_rlrm_incompatible",
    old = "eq_rlrm_old",
}


--- @return string|nil text The popup text for the current problem, nil when there is none
function EqRLRMWarning.getText()
    local key = EqRLRMWarning.TEXTS[EqRLRM.problem or ""]
    if key == nil or g_i18n == nil then return nil end
    return string.format(g_i18n:getText(key), tostring(EqRLRM.version or "?"), EqRLRM.MIN_VERSION)
end


function EqRLRMWarning.update()
    if EqRLRMWarning.shown or EqRLRM.problem == nil then return end
    local mission = g_currentMission
    if mission == nil or mission.isMissionStarted == false then return end
    if g_gui == nil or g_gui:getIsGuiVisible() or InfoDialog == nil or InfoDialog.show == nil then return end
    EqRLRMWarning.shown = true
    local text = EqRLRMWarning.getText()
    if text ~= nil then InfoDialog.show(text) end
end


--- @param guarded function main.lua's error guard
function EqRLRMWarning.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if EqRLRMWarning.shown or EqRLRM.problem == nil then return end
        guarded("RLRM version popup", EqRLRMWarning.update)
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        EqRLRMWarning.shown = false
    end)
end

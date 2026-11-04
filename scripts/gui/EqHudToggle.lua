--[[
    EqHudToggle: a key that hides and shows the game HUD, like the gsHudVisibility console
    command, so players can film without turning on the developer controls (James, 2026-11-04).
    Our own drawing already follows the HUD through EqTrainingHud.gameHudHidden().
]]

EqHudToggle = {}


--- Flip the game HUD between shown and hidden.
function EqHudToggle.toggle()
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    if type(hud) ~= "table" then return end
    if hud.getIsVisible ~= nil and hud.setIsVisible ~= nil then
        hud:setIsVisible(not hud:getIsVisible())
    elseif hud.consoleCommandToggleVisibility ~= nil then
        hud:consoleCommandToggleVisibility()
    else
        Log:warning("EqHudToggle: the HUD has no way to change its visibility")
    end
end


--- Register the key in every player context (on foot, in a vehicle, on a horse), the way
--- EqDelivery registers its key. No prompt in the help box: the key works with the HUD hidden.
--- Conflicting bindings stay on, so numpad minus still shifts down in a manual vehicle.
--- @param controlling string|nil input context
local function registerAction(_, controlling)
    local ok, id = g_inputBinding:registerActionEvent(InputAction.EQ_TOGGLE_HUD, EqHudToggle, function()
        EqHudToggle.guarded("hide HUD key", EqHudToggle.toggle)
    end, false, true, false, true, nil, false)
    if id == nil or id == "" then
        Log:info("EqHudToggle: hide HUD key not registered (context %s, ok=%s)", tostring(controlling), tostring(ok))
        return
    end
    g_inputBinding:setActionEventTextVisibility(id, false)
end


--- @param guarded function main.lua's error guard
function EqHudToggle.install(guarded)
    EqHudToggle.guarded = guarded
    if InputAction.EQ_TOGGLE_HUD == nil then
        Log:warning("EqHudToggle: input action EQ_TOGGLE_HUD missing from modDesc; no hide HUD key")
        return
    end
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents, function(component, controlling)
            guarded("hide HUD key registration", function() registerAction(component, controlling) end)
        end)
    Log:debug("EqHudToggle: hooked PlayerInputComponent.registerGlobalPlayerActionEvents")
end

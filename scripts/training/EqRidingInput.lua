--[[
    EqRidingInput.lua
    The held riding modifiers as real input actions, so they can be rebound on the game's
    Controls page and work on a gamepad (James, 2026-11-02):
      EQ_LATERAL (Shift / R1): strafe with the steering, bend the head with the right stick.
      EQ_COLLECT (Ctrl / L1): collect on the spot (piaffe, pirouette), passage with gait up.
      EQ_REIN (right mouse button): mouse steering, and with Lateral the mouse head bend.

    An action reports a held button every frame (triggerAlways); a button is held while it was
    reported within HOLD_MS. Until an action has been seen to fire at all, its default keyboard
    keys are read directly, in case the binding never reaches us (as with the sprint key).

    The steering action's raw value is kept too (right positive), because lateral work zeroes
    the horse's steer: the drift and the pirouette read the stick or A/D from it.

    Part of Realistic Equestrian by Jasta007.
]]

EqRidingInput = {}

EqRidingInput.HOLD_MS = 100
-- How far the stick must go to pick a side for the drift or a pirouette.
EqRidingInput.SIDE_THRESHOLD = 0.5

EqRidingInput.ACTIONS = {
    lateral = { action = "EQ_LATERAL", keys = { "KEY_lshift", "KEY_rshift" } },
    collect = { action = "EQ_COLLECT", keys = { "KEY_lctrl", "KEY_rctrl" } },
    rein = { action = "EQ_REIN", mouse = "MOUSE_BUTTON_RIGHT" },
}

EqRidingInput.heldAt = {}
EqRidingInput.seen = {}
EqRidingInput.steerValue = 0
EqRidingInput.steerAt = nil


--- Whether a button reported at heldAt still counts as held at now (pure).
--- @param heldAt number|nil ms
--- @param now number ms
--- @return boolean
function EqRidingInput.isFresh(heldAt, now)
    return heldAt ~= nil and now - heldAt <= EqRidingInput.HOLD_MS
end


--- The side asked for from the steering value and the A/D keys (pure).
--- @param steer number -1..1, right positive
--- @param keyLeft boolean
--- @param keyRight boolean
--- @return boolean left, boolean right
function EqRidingInput.sides(steer, keyLeft, keyRight)
    local t = EqRidingInput.SIDE_THRESHOLD
    return keyLeft or steer <= -t, keyRight or steer >= t
end


local function now()
    return g_time or 0
end


local function rawDown(entry)
    if Input == nil then return false end
    if entry.mouse ~= nil then
        return Input.isMouseButtonPressed ~= nil and Input[entry.mouse] ~= nil and Input.isMouseButtonPressed(Input[entry.mouse]) == true
    end
    if Input.isKeyPressed == nil then return false end
    for _, name in ipairs(entry.keys) do
        if Input[name] ~= nil and Input.isKeyPressed(Input[name]) == true then return true end
    end
    return false
end


--- @param name string "lateral", "collect" or "rein"
--- @return boolean that riding modifier is held
function EqRidingInput.held(name)
    local entry = EqRidingInput.ACTIONS[name]
    if entry == nil then return false end
    if EqRidingInput.seen[name] then return EqRidingInput.isFresh(EqRidingInput.heldAt[name], now()) end
    return rawDown(entry)
end


function EqRidingInput.lateral() return EqRidingInput.held("lateral") end
function EqRidingInput.collect() return EqRidingInput.held("collect") end
function EqRidingInput.rein() return EqRidingInput.held("rein") end


--- The steering asked for this frame, right positive (stick or keys), 0 when stale.
--- @return number
function EqRidingInput.steer()
    if not EqRidingInput.isFresh(EqRidingInput.steerAt, now()) then return 0 end
    return EqRidingInput.steerValue
end


--- Left and right asked for: the steering action, or A and D read directly.
--- @return boolean left, boolean right
function EqRidingInput.steerSides()
    local function key(k) return Input ~= nil and Input.isKeyPressed ~= nil and Input[k] ~= nil and Input.isKeyPressed(Input[k]) == true end
    return EqRidingInput.sides(EqRidingInput.steer(), key("KEY_a"), key("KEY_d"))
end


--- Appended to Rideable:onRegisterActionEvents (through EqTrainingHooks): the held modifiers.
--- @param vehicle table
--- @param spec table spec_rideable
function EqRidingInput.registerActions(vehicle, spec)
    for name, entry in pairs(EqRidingInput.ACTIONS) do
        local action = InputAction ~= nil and InputAction[entry.action] or nil
        if action ~= nil then
            local _, id = vehicle:addActionEvent(spec.actionEvents, action, vehicle, function(_, _, inputValue)
                if not EqRidingInput.seen[name] then
                    EqRidingInput.seen[name] = true
                    EqLog:info("Riding input: %s action seen", entry.action)
                end
                if (inputValue or 0) ~= 0 then EqRidingInput.heldAt[name] = now() end
            end, false, true, true, true, nil)
            if id ~= nil then
                g_inputBinding:setActionEventText(id, g_i18n:getText("input_" .. entry.action))
                g_inputBinding:setActionEventTextVisibility(id, false)
            end
        end
    end
end


--- Appended to Rideable.actionEventSteer: keep the raw steering value.
function EqRidingInput.onSteer(inputValue)
    EqRidingInput.steerValue = inputValue or 0
    EqRidingInput.steerAt = now()
end

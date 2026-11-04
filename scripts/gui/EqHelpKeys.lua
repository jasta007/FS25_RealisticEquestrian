--[==[
    EqHelpKeys.lua
    Key names in help and popup texts (James, 2026-11-04): a text names an input action as
    [[EQ_TRAINING_VIEW]], and the popup shows the key the player has bound to it now, so a
    rebound key or a gamepad reads right.

    - On a gamepad (the game's input help mode), the pad button from our default bindings.
    - On keyboard and mouse, the game's own name for the bound key when it gives one
      (InputDisplayManager:getKeyboardInputActionKey), else our default key.
    An action we know nothing about shows its name without the brackets, never the raw token.
    Each action's answer is logged once, so a test log shows where every name came from.

    Part of Realistic Equestrian by Jasta007.
]==]

EqHelpKeys = {}

-- Our default keyboard and mouse keys (modDesc.xml), for when the game can't name the binding.
EqHelpKeys.KEYBOARD = {
    EQ_TRAINING_VIEW = "Y",
    EQ_TRAINING_HELP = "H",
    EQ_SPRINT = "LMB",
    EQ_LATERAL = "Shift",
    EQ_COLLECT = "Ctrl",
    EQ_REIN = "RMB",
    EQ_COURSE_RECORD = "Ctrl+J",
    EQ_COURSE_RECORD_XC = "Ctrl+E",
    EQ_COURSE_REWIND = "Ctrl+K",
    EQ_COURSE_DELETE = "Ctrl+Backspace",
    EQ_DRESSAGE_TEST = "Ctrl+L",
    EQ_DT_PREV = "N",
    EQ_DT_NEXT = "M",
    EQ_DT_RANDOM = "R",
    EQ_DT_MODE = "F",
    EQ_DT_ACCEPT = "Enter",
    EQ_DT_UNDO = "Backspace",
    EQ_DT_PREV_LETTER = "Shift+N",
    EQ_DT_NEXT_LETTER = "Shift+M",
    EQ_DT_GAIT = "G",
}

-- Our default gamepad buttons (modDesc.xml), PlayStation / Xbox. Actions without one keep their key.
EqHelpKeys.GAMEPAD = {
    EQ_TRAINING_VIEW = "Triangle/Y",
    EQ_TRAINING_HELP = "R1+Triangle/RB+Y",
    EQ_SPRINT = "Circle/B",
    EQ_LATERAL = "R1/RB",
    EQ_COLLECT = "L1/LB",
}

EqHelpKeys.logged = {}


--- Replace every [[ACTION]] in a text with what lookup(action) returns (pure).
--- @param text string
--- @param lookup function action name -> string|nil
--- @return string
function EqHelpKeys.fill(text, lookup)
    if type(text) ~= "string" then return text end
    return (text:gsub("%[%[([%w_]+)%]%]", function(action)
        return lookup(action) or action
    end))
end


--- @return boolean true while the game shows gamepad buttons in its help
function EqHelpKeys.usingGamepad()
    local binding = g_inputBinding
    if binding == nil or binding.getInputHelpMode == nil or GS_INPUT_HELP_MODE_GAMEPAD == nil then return false end
    local ok, mode = EqLog.try("EqHelpKeys help mode", binding.getInputHelpMode, binding)
    return ok and mode == GS_INPUT_HELP_MODE_GAMEPAD
end


--- The game's name for the key bound to an action, or nil.
--- @param action string
--- @return string|nil
function EqHelpKeys.liveKeyboard(action)
    local display = g_inputDisplayManager
    if display == nil or display.getKeyboardInputActionKey == nil then return nil end
    local ok, key = EqLog.try("EqHelpKeys keyboard key", display.getKeyboardInputActionKey, display, action)
    if ok and type(key) == "string" and key ~= "" then return key end
    return nil
end


--- The name to show for an action now.
--- @param action string
--- @return string|nil
function EqHelpKeys.name(action)
    local name, source
    if EqHelpKeys.usingGamepad() and EqHelpKeys.GAMEPAD[action] ~= nil then
        name, source = EqHelpKeys.GAMEPAD[action], "gamepad default"
    else
        name, source = EqHelpKeys.liveKeyboard(action), "game"
        if name == nil then name, source = EqHelpKeys.KEYBOARD[action], "default" end
    end
    local logKey = action .. "|" .. tostring(name)
    if not EqHelpKeys.logged[logKey] and EqLog ~= nil and EqLog.info ~= nil then
        EqHelpKeys.logged[logKey] = true
        EqLog:info("Help keys: %s shows as '%s' (%s)", action, tostring(name), source)
    end
    return name
end


--- A text with its key tokens filled in for this player.
--- @param text string
--- @return string
function EqHelpKeys.text(text)
    return EqHelpKeys.fill(text, EqHelpKeys.name)
end

--[[
    EqSettings.lua
    The savegame settings the in-game Settings page shows: what each row offers and how a row's
    state maps to a value in EqCompetitionManager.settings (saved in rlEquestrian.xml, and also
    changed by the eqSettings console command). Pure: no game or RLRM calls, so it runs headless.

    The server owns the settings. Until multiplayer sync lands, only the host can change them.
]]

EqSettings = {}

-- Training rate choices: a multiplier on every stat gain from training (riding, staff, events).
EqSettings.TRAINING_RATES = { 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3 }

-- Entry fee and prize money choices: a multiplier on the fee or purse of each newly drawn event.
-- Kept to 0.5x-2x so events stay worth entering without flooding the farm with money.
EqSettings.MONEY_SCALES = { 0.5, 0.75, 1, 1.25, 1.5, 2 }

-- Entry limit choices; 0 means no limit.
EqSettings.ENTRY_LIMITS = { 0, 1, 2, 3, 4, 5, 6, 8, 10 }

-- Choices for the fewest and most events on the calendar at once.
EqSettings.EVENT_COUNTS = { 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15 }

local function onOffTexts()
    return { { key = "eq_settings_off" }, { key = "eq_settings_on" } }
end

local function rateTexts(rates)
    local texts = {}
    for i, rate in ipairs(rates) do
        texts[i] = { text = (string.format("%.2f", rate):gsub("0+$", ""):gsub("%.$", "")) .. "x" }
    end
    return texts
end

local function limitTexts()
    local texts = {}
    for i, limit in ipairs(EqSettings.ENTRY_LIMITS) do
        texts[i] = limit == 0 and { key = "eq_settings_noLimit" } or { text = tostring(limit) }
    end
    return texts
end

local function countTexts()
    local texts = {}
    for i, count in ipairs(EqSettings.EVENT_COUNTS) do texts[i] = { text = tostring(count) } end
    return texts
end

-- Rows in page order. Each has the settings field it edits, the values its states stand for,
-- and the texts shown for them: { key = l10n key } or { text = literal }. Titles and tooltips
-- are eq_settings_<id> and eq_settings_<id>_tooltip.
EqSettings.ROWS = {
    { id = "trainingRate", values = EqSettings.TRAINING_RATES, texts = rateTexts(EqSettings.TRAINING_RATES), default = 1 },
    { id = "cadence", values = { "day", "month" },
        texts = { { key = "eq_settings_cadence_day" }, { key = "eq_settings_cadence_month" } }, default = "day" },
    { id = "eventsMin", values = EqSettings.EVENT_COUNTS, texts = countTexts(), default = 3 },
    { id = "eventsMax", values = EqSettings.EVENT_COUNTS, texts = countTexts(), default = 8 },
    { id = "racing", values = { false, true }, texts = onOffTexts(), default = true },
    { id = "injuries", values = { false, true }, texts = onOffTexts(), default = true },
    { id = "forcedRetirement", values = { false, true }, texts = onOffTexts(), default = false },
    { id = "entriesPerMonth", values = EqSettings.ENTRY_LIMITS, texts = limitTexts(), default = 3 },
    { id = "entryFeeScale", values = EqSettings.MONEY_SCALES, texts = rateTexts(EqSettings.MONEY_SCALES), default = 1 },
    { id = "prizeScale", values = EqSettings.MONEY_SCALES, texts = rateTexts(EqSettings.MONEY_SCALES), default = 1 },
}

EqSettings.BY_ID = {}
for _, row in ipairs(EqSettings.ROWS) do EqSettings.BY_ID[row.id] = row end


--- The state (1-based) that shows a value. A number between the choices (set with the console)
--- shows as the nearest choice; anything else unknown shows as the default.
--- @param row table an EqSettings.ROWS entry
--- @param value any
--- @return number state
function EqSettings.stateOf(row, value)
    local best, bestDistance, defaultState = nil, math.huge, 1
    for i, candidate in ipairs(row.values) do
        if candidate == value then return i end
        if candidate == row.default then defaultState = i end
        if type(candidate) == "number" and type(value) == "number" then
            local distance = math.abs(candidate - value)
            if distance < bestDistance then best, bestDistance = i, distance end
        end
    end
    return best or defaultState
end


--- Set a row's value from a state.
--- @param settings table EqCompetitionManager.settings
--- @param id string row id
--- @param state number
--- @return boolean changed
function EqSettings.apply(settings, id, state)
    local row = EqSettings.BY_ID[id]
    if row == nil or row.values[state] == nil then return false end
    local value = row.values[state]
    if settings[id] == value then return false end
    settings[id] = value
    return true
end


--- A multiplier setting, 1 when unset or not positive.
--- @param settings table|nil EqCompetitionManager.settings
--- @param id string e.g. "trainingRate", "entryFeeScale", "prizeScale"
--- @return number multiplier
function EqSettings.multiplier(settings, id)
    local value = settings ~= nil and tonumber(settings[id]) or nil
    if value == nil or value <= 0 then return 1 end
    return value
end


--- The training rate multiplier, 1 when unset.
--- @param settings table|nil EqCompetitionManager.settings
--- @return number rate
function EqSettings.trainingRate(settings)
    return EqSettings.multiplier(settings, "trainingRate")
end

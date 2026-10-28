--[[
    EqStory.lua
    The few lines that tell a horse's event: how it went (EqPerformance), eventing's scoresheet
    (each phase's place and penalties, then the total), who took the top three, and what the
    horse came home with (stat gains or an injury). Each line short.
]]

EqStory = {}

-- A gain smaller than this is not worth a mention.
EqStory.MIN_GAIN = 0.05
-- Text between two of these is shown bold on the Results tab (horse names, gains).
EqStory.BOLD = "**"


--- @param text string
--- @return string text marked to show bold
function EqStory.bold(text)
    return EqStory.BOLD .. text .. EqStory.BOLD
end


--- Split a line into its plain and bold runs.
--- @param text string
--- @return table runs list of { text, bold }, empty runs left out
function EqStory.runs(text)
    local runs, bold, start = {}, false, 1
    while true do
        local at = text:find(EqStory.BOLD, start, true)
        local piece = text:sub(start, (at or 0) - 1)
        if at == nil then piece = text:sub(start) end
        if piece ~= "" then table.insert(runs, { text = piece, bold = bold }) end
        if at == nil then return runs end
        bold, start = not bold, at + #EqStory.BOLD
    end
end


--- @param text string
--- @return string text without the bold marks
function EqStory.plain(text)
    local parts = {}
    for _, run in ipairs(EqStory.runs(text)) do table.insert(parts, run.text) end
    return table.concat(parts)
end


--- @param place number
--- @return string text such as "1st", "22nd" or "11th" (eq_ord_* texts; German is "1.")
function EqStory.ordinal(place)
    local lastTwo, last = place % 100, place % 10
    local key = "eq_ord_n"
    if lastTwo < 11 or lastTwo > 13 then
        if last == 1 then key = "eq_ord_1" elseif last == 2 then key = "eq_ord_2" elseif last == 3 then key = "eq_ord_3" end
    end
    return string.format(g_i18n:getText(key), place)
end


--- @param names table up to three names, first place first
--- @return string|nil line "Winner: A, 2nd: B, 3rd: C.", the names bold
function EqStory.podiumLine(names)
    if names[1] == nil then return nil end
    if names[2] == nil or names[3] == nil then return string.format(g_i18n:getText("eq_story_winner"), EqStory.bold(names[1])) end
    return string.format(g_i18n:getText("eq_story_podium"), EqStory.bold(names[1]), EqStory.bold(names[2]), EqStory.bold(names[3]))
end


--- @param value number penalties
--- @param decimal boolean always show one decimal (dressage marks)
--- @return string text such as "28.4", "4" or "6.8"
function EqStory.penalties(value, decimal)
    if not decimal and math.abs(value - math.floor(value + 0.5)) < 0.05 then return string.format("%d", math.floor(value + 0.5)) end
    return string.format("%.1f", value)
end


--- What a jumping phase's penalties were for: fences down, refusals, time.
--- @param sheet table from EqPerformance.phaseSheet
--- @return string|nil text such as "1 down, 2 time"
local function sheetReasons(sheet)
    local parts = {}
    if sheet.down > 0 then
        table.insert(parts, sheet.down == 1 and g_i18n:getText("eq_story_down1") or string.format(g_i18n:getText("eq_story_downN"), sheet.down))
    end
    if sheet.refusals > 0 then
        table.insert(parts, sheet.refusals == 1 and g_i18n:getText("eq_story_refusal1") or string.format(g_i18n:getText("eq_story_refusalN"), sheet.refusals))
    end
    if sheet.time > 0 then table.insert(parts, string.format(g_i18n:getText("eq_story_time"), EqStory.penalties(sheet.time))) end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end


--- Eventing's scoresheet: each phase's place and penalties, then the total.
--- @param run table|nil from EqPerformance.run, scored by EqPerformance.scorePenalties
--- @param places table|nil phase -> place
--- @return table|nil lines "Dressage: 4th, 28.4 penalties", "Show Jumping: 2nd, clear",
---     "Cross Country: 6th, 21.2 penalties (1 refusal, 1.2 time)", "Total: 49.6 penalties"
function EqStory.scoreLines(run, places)
    if run == nil or run.phases == nil or run.penalties == nil or places == nil then return nil end
    local lines = {}
    for _, phase in ipairs(run.phases) do
        local sheet, place = phase.sheet, places[phase.name]
        if sheet ~= nil and place ~= nil then
            local name, placeText = g_i18n:getText("eq_discipline_" .. phase.name), EqStory.bold(EqStory.ordinal(place))
            local reasons = sheetReasons(sheet)
            if sheet.penalties == 0 then
                table.insert(lines, string.format(g_i18n:getText("eq_story_phaseClear"), name, placeText))
            elseif reasons ~= nil then
                table.insert(lines, string.format(g_i18n:getText("eq_story_phaseFaults"), name, placeText, EqStory.penalties(sheet.penalties), reasons))
            else
                -- Dressage: marks, always to one decimal.
                table.insert(lines, string.format(g_i18n:getText("eq_story_phaseScore"), name, placeText, EqStory.penalties(sheet.penalties, true)))
            end
        end
    end
    if #lines == 0 then return nil end
    table.insert(lines, string.format(g_i18n:getText("eq_story_total"), EqStory.bold(EqStory.penalties(run.penalties, true))))
    return lines
end


--- @param deltas table|nil stat -> gain from the event's training boost
--- @return string|nil line "Gained Agility +0.4, Temperament +0.2.", the gains bold
function EqStory.gainsLine(deltas)
    if deltas == nil then return nil end
    local parts = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local gain = deltas[stat] or 0
        if gain >= EqStory.MIN_GAIN then
            table.insert(parts, string.format("%s %s", g_i18n:getText("eq_stat_" .. stat), EqStory.bold(string.format("+%.1f", gain))))
        end
    end
    if #parts == 0 then return nil end
    return string.format(g_i18n:getText("eq_story_gains"), table.concat(parts, ", "))
end


--- @param injury table|nil EqRisk.rollInjury outcome
--- @return string|nil line
function EqStory.injuryLine(injury)
    if injury == nil then return nil end
    if injury.careerEnding then return g_i18n:getText("eq_story_careerEnded") end
    return string.format(g_i18n:getText("eq_story_injury"), g_i18n:getText("eq_injury_" .. injury.name))
end


--- @param story table { performance, phases (eventing's scoresheet lines), podium, gains, injury }
---     lines, any of them nil
--- @return table lines in order; the injury replaces the gains
function EqStory.lines(story)
    local lines = {}
    local function add(line)
        if line ~= nil and line ~= "" then table.insert(lines, line) end
    end
    add(story.performance)
    for _, line in ipairs(story.phases or {}) do add(line) end
    add(story.podium)
    add(story.injury or story.gains)
    return lines
end

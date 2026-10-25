--[[
    EqStory.lua
    The few lines that tell a horse's event: how it went (EqPerformance), eventing's phase
    placings, who took the top three, and what the horse came home with (stat gains or an
    injury). At most four lines under the result itself, each one short.
]]

EqStory = {}

-- A gain smaller than this is not worth a mention.
EqStory.MIN_GAIN = 0.05


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
--- @return string|nil line "Winner: A, 2nd: B, 3rd: C."
function EqStory.podiumLine(names)
    if names[1] == nil then return nil end
    if names[2] == nil or names[3] == nil then return string.format(g_i18n:getText("eq_story_winner"), names[1]) end
    return string.format(g_i18n:getText("eq_story_podium"), names[1], names[2], names[3])
end


--- @param phases table phase names, in order
--- @param places table phase -> place
--- @return string|nil line "Dressage 4th, Show Jumping 2nd, Cross Country 6th."
function EqStory.phasesLine(phases, places)
    if phases == nil or places == nil then return nil end
    local parts = {}
    for _, name in ipairs(phases) do
        if places[name] ~= nil then
            table.insert(parts, string.format(g_i18n:getText("eq_story_phase"), g_i18n:getText("eq_discipline_" .. name),
                EqStory.ordinal(places[name])))
        end
    end
    if #parts == 0 then return nil end
    return string.format(g_i18n:getText("eq_story_phases"), table.concat(parts, ", "))
end


--- @param deltas table|nil stat -> gain from the event's training boost
--- @return string|nil line "Gained Agility +0.4, Temperament +0.2."
function EqStory.gainsLine(deltas)
    if deltas == nil then return nil end
    local parts = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local gain = deltas[stat] or 0
        if gain >= EqStory.MIN_GAIN then
            table.insert(parts, string.format("%s +%.1f", g_i18n:getText("eq_stat_" .. stat), gain))
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


--- @param story table { performance, phases, podium, gains, injury } lines, any of them nil
--- @return table lines in order; the injury replaces the gains, keeping it to four
function EqStory.lines(story)
    local lines = {}
    local parts = { story.performance, story.phases, story.podium, story.injury or story.gains }
    for i = 1, 4 do
        if parts[i] ~= nil and parts[i] ~= "" then table.insert(lines, parts[i]) end
    end
    return lines
end

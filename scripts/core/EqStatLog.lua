--[[
    EqStatLog.lua
    Testing aid: what changed each horse's four stats over the last few days, and why. The
    daily training tick, event training boosts and injuries add entries; eqChanges prints them.
    Pure functions with no game or RLRM calls, so they run headless.

    Kept in memory only (server side): a save and reload starts the log again.
]]

EqStatLog = {}

-- Days of entries kept per horse.
EqStatLog.KEEP_DAYS = 7

EqStatLog.entries = {}

local SHORT = { stamina = "sta", speed = "spd", agility = "agi", temperament = "tem" }


function EqStatLog.reset()
    EqStatLog.entries = {}
end


--- @param id string horse identifier
--- @param day number monotonic day
--- @param source string what made the change, such as "daily training" or "event"
--- @param deltas table|nil stat -> change
--- @param notes table|nil list of strings saying why
--- @param after table|nil stat -> level once applied
function EqStatLog.add(id, day, source, deltas, notes, after)
    local list = EqStatLog.entries[id]
    if list == nil then
        list = {}
        EqStatLog.entries[id] = list
    end
    local copy = nil
    if after ~= nil then
        copy = {}
        for _, stat in ipairs(EqConstants.STAT_KEYS) do copy[stat] = after[stat] end
    end
    table.insert(list, { day = day, source = source, deltas = deltas or {}, notes = notes or {}, after = copy })
    while #list > 0 and list[1].day < day - EqStatLog.KEEP_DAYS + 1 do table.remove(list, 1) end
end


--- @param id string
--- @param fromDay number
--- @return table entries on or after fromDay, oldest first
function EqStatLog.since(id, fromDay)
    local found = {}
    for _, entry in ipairs(EqStatLog.entries[id] or {}) do
        if entry.day >= fromDay then table.insert(found, entry) end
    end
    return found
end


--- @param values table stat -> number
--- @param format string such as "%+.2f"
--- @return string "sta +0.31 spd +0.00 agi +0.12 tem +0.40"
function EqStatLog.statLine(values, format)
    local parts = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        table.insert(parts, string.format("%s " .. format, SHORT[stat], values[stat] or 0))
    end
    return table.concat(parts, " ")
end


--- @param boost table|nil stat -> share
--- @return string|nil "sta +10% tem +5%", nil when nothing is boosted
local function boostText(boost)
    if boost == nil then return nil end
    local parts = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if (boost[stat] or 0) > 0 then table.insert(parts, string.format("%s +%.0f%%", SHORT[stat], boost[stat] * 100)) end
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end


--- @param effort table stat -> 0..1
--- @return boolean any stat above zero
local function anyEffort(effort)
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if (effort[stat] or 0) > 0 then return true end
    end
    return false
end


--- Explain one daily training tick.
--- @param detail table second result of EqTraining.applyDay
--- @param day table what was passed to applyDay
--- @param info table { resting, focus, playerPoints, sheet }
--- @return table notes list of strings
function EqStatLog.explainDay(detail, day, info)
    local notes = {}
    if info.resting then table.insert(notes, "On box rest (injured): no training, the day counts as idle") end

    if anyEffort(detail.player) then
        local sheet, gaits = info.sheet, {}
        if sheet ~= nil then
            for _, gait in ipairs({ "walk", "trot", "canter", "gallop", "reverse" }) do
                if (sheet.ms[gait] or 0) > 0 then table.insert(gaits, string.format("%s %.1f min", gait, sheet.ms[gait] / 60000)) end
            end
            if (sheet.jumps or 0) > 0 then table.insert(gaits, string.format("%d jump(s)", sheet.jumps)) end
            local focused = sheet.focused or {}
            local anyFocused = false
            for _, value in pairs(focused) do if value > 0 then anyFocused = true end end
            if anyFocused then
                table.insert(gaits, string.format("focused stamina %.0f%% speed %.0f%% agility %.0f%% temperament %.0f%%",
                    (focused.stamina or 0) * 100, (focused.speed or 0) * 100, (focused.agility or 0) * 100,
                    (focused.temperament or 0) * 100))
            end
            if sheet.combo ~= nil and sheet.combo.best > 0 then
                table.insert(gaits, string.format("best jump combo %d", sheet.combo.best))
            end
        end
        local percent = {}
        for _, stat in ipairs(EqConstants.STAT_KEYS) do percent[stat] = (detail.player[stat] or 0) * 100 end
        table.insert(notes, string.format("Your riding: effort %s (%s)", EqStatLog.statLine(percent, "%.0f%%"),
            #gaits > 0 and table.concat(gaits, ", ") or "no gait times"))
    else
        table.insert(notes, "Your riding: none")
    end

    local staffShare = math.max(0, (day.riding or 0) - (info.playerPoints or 0))
    if anyEffort(detail.staff) then
        local luck = (info.focus ~= nil and info.focus ~= "balanced" and day.staffLuck ~= nil)
            and string.format(" (staff managed %.0f%% of the role's work today)", day.staffLuck * 100) or ""
        table.insert(notes, string.format("Staff: %.0f of the riding bar (bar %.0f, yours %.0f), focus %s%s%s", staffShare,
            day.riding or 0, info.playerPoints or 0, tostring(info.focus), luck, detail.groomed and ", groomed (+temperament)" or ""))
    else
        table.insert(notes, string.format("Staff: none (riding bar %.0f, yours %.0f)%s", day.riding or 0, info.playerPoints or 0,
            detail.groomed and "" or string.format(", not groomed (dirt %s > %d)", tostring(day.dirt), EqConstants.GROOMED_DIRT)))
    end

    local rates = { string.format("age %dm x%.1f", day.ageMonths or 0, detail.ageFactor) }
    local fed, owned, ridden = boostText(day.feedBoost), boostText(day.facilityOwned), boostText(day.facilityRidden)
    table.insert(rates, "feed " .. (fed or "none"))
    table.insert(rates, "facilities " .. (owned or "none"))
    if ridden ~= nil then table.insert(rates, "ridden inside " .. ridden) end
    table.insert(notes, "Training rate: " .. table.concat(rates, ", "))

    local winners = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local s = detail.stats[stat]
        if s.fromPlayer > 0 or s.fromStaff > 0 then
            local own = s.fromPlayer >= s.fromStaff
            table.insert(winners, string.format("%s %+.2f from %s (%s %+.2f)", SHORT[stat], math.max(s.fromPlayer, s.fromStaff),
                own and "you" or "staff", own and "staff" or "you", math.min(s.fromPlayer, s.fromStaff)))
        end
    end
    if #winners > 0 then
        table.insert(notes, "Gains (the better of you or staff counts): " .. table.concat(winners, ", "))
    elseif anyEffort(detail.player) or anyEffort(detail.staff) then
        table.insert(notes, "Gains: none, the stats are at their caps (staff stop at " .. EqConstants.STAFF_CAP * 100 .. "% of the ceiling)")
    end

    local faded, aged = {}, {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        local s = detail.stats[stat]
        if s.faded < 0 then table.insert(faded, string.format("%s %+.2f", SHORT[stat], s.faded)) end
        if s.aged < 0 then table.insert(aged, string.format("%s %+.2f", SHORT[stat], s.aged)) end
    end
    if detail.fading then
        table.insert(notes, string.format("Fading: idle %d day(s)%s", detail.idleDays, #faded > 0 and (": " .. table.concat(faded, ", ")) or ", already at the floor"))
    else
        table.insert(notes, string.format("Not fading: idle %d day(s)", detail.idleDays))
    end
    if detail.old then
        table.insert(notes, string.format("Old age (over %dm)%s", EqConstants.AGE_DECLINE, #aged > 0 and (": " .. table.concat(aged, ", ")) or ", already at the floor"))
    end
    return notes
end

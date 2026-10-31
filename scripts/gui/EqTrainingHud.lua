--[[
    EqTrainingHud.lua
    What the rider sees while training: a small panel on the right of the screen with the
    exertion bar and a line per stat, each in the colour of its state, and help popups at the
    bottom of the screen.

    The base game's help panel (addExtraPrintText) has no colours and cuts long lines off, so
    the panel is drawn here with plain text and a one-pixel texture. Popups never take the mouse:
    a click anywhere moves on to the next page or closes the last one, and a page stays until
    clicked. A series only counts as seen once its last page is clicked away: one closed early
    (Esc out of the menu, getting off the horse) shows again, from its first page. Combo bursts ("x3!") pop up in the middle of the screen, and a
    temperament routine's request shows there with its countdown. Which views' help the player has already seen is kept in
    modSettings, so it only pops up by itself the first time. The welcome popups (EqWelcome)
    use the same popup, in the world and over RLRM's menu.
]]

EqTrainingHud = {}

local Log = EqLog

EqTrainingHud.PIXEL = "dataS/menu/base/graph_pixel.dds"

EqTrainingHud.COLOR = {
    white = { 1, 1, 1, 1 },
    grey = { 0.75, 0.75, 0.75, 1 },
    blue = { 0.55, 0.8, 1, 1 },
    yellow = { 1, 0.82, 0.25, 1 },
    green = { 0.529, 0.706, 0, 1 },
    orange = { 1, 0.55, 0.15, 1 },
    red = { 1, 0.32, 0.25, 1 },
    track = { 1, 1, 1, 0.15 },
    background = { 0, 0, 0, 0.6 },
    -- The exertion bar's dividers and ticks: solid, the shade the old see-through ticks showed.
    barLine = { 0.16, 0.16, 0.15, 1 },
}

-- Screen positions are shares of the screen, from the bottom left.
EqTrainingHud.PANEL = { right = 0.985, top = 0.66, width = 0.2, padding = 0.008, lineHeight = 0.02,
    textSize = 0.0145, titleSize = 0.0165, barHeight = 0.008, markWidth = 0.0012, meterHeight = 0.015 }
EqTrainingHud.POPUP = { centerX = 0.5, bottom = 0.11, width = 0.36, padding = 0.012, lineHeight = 0.019,
    textSize = 0.015, titleSize = 0.0175 }
-- Nearly opaque: over a menu, the panel behind showed through and was hard to read past.
EqTrainingHud.POPUP_BACKGROUND = { 0.04, 0.04, 0.04, 0.96 }
EqTrainingHud.SEEN_FILE = "FS25_RealisticEquestrian.xml"

EqTrainingHud.pages = nil
EqTrainingHud.pageIndex = 0
EqTrainingHud.mouseWasDown = true
EqTrainingHud.seen = nil
EqTrainingHud.place = nil        -- where the popups showing belong: nil (the world), "menu" or "dialog"
EqTrainingHud.drawnAt = nil      -- g_time of the last draw: the riding and world draws share one popup


--- True while the player has hidden the game's HUD (the gsHudVisibility console command, or a
--- HUD hider mod calling hud:consoleCommandToggleVisibility) to film or take screenshots. All
--- our screen text, popups, glow lines and labels stay hidden with it (James, 2026-10-31).
--- @return boolean
function EqTrainingHud.gameHudHidden()
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    if type(hud) ~= "table" then return false end
    if hud.getIsVisible ~= nil then
        local ok, visible = pcall(hud.getIsVisible, hud)
        if ok and visible ~= nil then return visible == false end
    end
    return hud.isVisible == false
end


--- @return table overlay one white pixel, made on first use
local function pixel()
    if EqTrainingHud.overlay == nil then
        EqTrainingHud.overlay = Overlay.new(EqTrainingHud.PIXEL, 0, 0, 1, 1)
    end
    return EqTrainingHud.overlay
end


--- @param x number
--- @param y number
--- @param width number
--- @param height number
--- @param color table
local function fill(x, y, width, height, color)
    if width <= 0 or height <= 0 or EqTrainingHud.gameHudHidden() then return end
    local overlay = pixel()
    overlay:setPosition(x, y)
    overlay:setDimension(width, height)
    overlay:setColor(color[1], color[2], color[3], color[4])
    overlay:render()
end


--- @param text string
--- @param x number
--- @param y number
--- @param size number
--- @param color table
--- @param align number|nil RenderText alignment, left when nil
--- @param bold boolean|nil
local function text(value, x, y, size, color, align, bold)
    if EqTrainingHud.gameHudHidden() then return end
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    setTextBold(bold == true)
    setTextColor(color[1], color[2], color[3], color[4])
    renderText(x, y, size, value)
end


-- Popups float over the world, which can be as bright as snow: a dark shadow keeps them readable.
EqTrainingHud.SHADOW = { share = 0.06, alpha = 0.85 }

--- Text with a dark drop shadow (down and right, plus a soft outline the other way).
local function shadowText(value, x, y, size, color, align, bold)
    local off = size * EqTrainingHud.SHADOW.share
    local shade = { 0, 0, 0, (color[4] or 1) * EqTrainingHud.SHADOW.alpha }
    text(value, x + off, y - off, size, shade, align, bold)
    text(value, x - off * 0.5, y + off * 0.5, size, { 0, 0, 0, shade[4] * 0.5 }, align, bold)
    text(value, x, y, size, color, align, bold)
end


local function resetText()
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end


--- Draw the training panel.
--- @param title string
--- @param rows table list of { left, leftColor, right, rightColor } text rows,
---     { segments = { { text, color, bold, at, tight }, ... } } rows of coloured pieces side by side
---     (at, a share of the row's width, starts a piece in its own column; tight keeps the next piece
---     one space after it, as a name and its number), { bar = 0..1, color } meter rows, and
---     { sections = { { from, to, color }, ... }, lines = { share, ... }, ticks = { share, ... },
---     marker = share } rows: the exertion bar, coloured sections with dark lines, short ticks and a marker
--- @param titleColor table|nil white when nil (a focused view's title is in its stat's colour)
--- @param titleRight string|nil grey text at the right of the title line
--- With no title the panel is just its rows (the Condensed view).
function EqTrainingHud.drawPanel(title, rows, titleColor, titleRight)
    local p = EqTrainingHud.PANEL
    -- Without a title the bar sits with equal room above and below.
    local height = title ~= nil and p.padding * 2 + p.lineHeight or p.padding * 0.5
    for _, row in ipairs(rows) do
        if row.bar ~= nil then
            height = height + p.barHeight + p.padding
        elseif row.sections ~= nil then
            height = height + p.meterHeight + p.padding * 1.5
        else
            height = height + p.lineHeight
        end
    end
    local x = p.right - p.width
    local y = p.top - height
    EqTrainingHud.panelBottom = y
    fill(x, y, p.width, height, EqTrainingHud.COLOR.background)

    local left, right = x + p.padding, p.right - p.padding
    local lineY = p.top - p.padding * 0.25
    if title ~= nil then
        lineY = p.top - p.padding - p.lineHeight * 0.8
        text(title, left, lineY, p.titleSize, titleColor or EqTrainingHud.COLOR.white, nil, true)
        if titleRight ~= nil then text(titleRight, right, lineY, p.textSize, EqTrainingHud.COLOR.grey, RenderText.ALIGN_RIGHT) end
    end
    for _, row in ipairs(rows) do
        if row.bar ~= nil then
            local barY = lineY - p.padding * 0.5 - p.barHeight
            fill(left, barY, right - left, p.barHeight, EqTrainingHud.COLOR.track)
            fill(left, barY, (right - left) * math.min(math.max(row.bar, 0), 1), p.barHeight, row.color or EqTrainingHud.COLOR.white)
            -- A highlighted window (the beat's hit window), then marks: ticks across the bar, a
            -- share or { share, color, width multiple }, such as the edges of the stamina zone.
            if row.window ~= nil then
                local from = math.max(row.window[1], 0)
                local to = math.min(row.window[2], 1)
                fill(left + (right - left) * from, barY, (right - left) * (to - from), p.barHeight, { 1, 0.82, 0.25, 0.35 })
            end
            for _, mark in ipairs(row.marks or {}) do
                local share, color, width = mark, EqTrainingHud.COLOR.white, 1
                if type(mark) == "table" then share, color, width = mark[1], mark[2], mark[3] or 1 end
                if share >= 0 and share <= 1 then
                    fill(left + (right - left) * share - p.markWidth * width / 2, barY - p.barHeight * 0.5,
                        p.markWidth * width, p.barHeight * 2, color)
                end
            end
            lineY = lineY - p.barHeight - p.padding
        elseif row.sections ~= nil then
            local h = p.meterHeight
            local barY = lineY - p.padding * 0.75 - h
            local width = right - left
            for _, section in ipairs(row.sections) do
                fill(left + width * section[1], barY, width * (section[2] - section[1]), h, section[3])
            end
            for _, line in ipairs(row.lines or {}) do
                fill(left + width * line - p.markWidth / 2, barY, p.markWidth, h, EqTrainingHud.COLOR.barLine)
            end
            -- Ticks: short marks from the bottom edge (the gallop's thirds), the same solid grey as
            -- the lines so no section's colour shows through either (James).
            for _, tick in ipairs(row.ticks or {}) do
                fill(left + width * tick - p.markWidth / 2, barY, p.markWidth, h * 0.45, EqTrainingHud.COLOR.barLine)
            end
            if row.marker ~= nil then
                -- A white box with a dark edge, a little taller than the bar.
                local markerX = left + width * math.min(math.max(row.marker, 0), 1)
                local mw, edge = p.markWidth * 3, p.markWidth
                fill(markerX - mw / 2 - edge, barY - h * 0.25 - edge, mw + edge * 2, h * 1.5 + edge * 2, { 0, 0, 0, 0.9 })
                fill(markerX - mw / 2, barY - h * 0.25, mw, h * 1.5, EqTrainingHud.COLOR.white)
            end
            lineY = lineY - h - p.padding * 1.5
        elseif row.segments ~= nil then
            lineY = lineY - p.lineHeight
            local x = left
            for _, segment in ipairs(row.segments) do
                if segment.at ~= nil then x = left + (right - left) * segment.at end
                text(segment[1], x, lineY, p.textSize, segment[2] or EqTrainingHud.COLOR.white, nil, segment.bold)
                x = x + getTextWidth(p.textSize, segment[1] .. (segment.tight and " " or "  "))
            end
        else
            lineY = lineY - p.lineHeight
            if row.left ~= nil then text(row.left, left, lineY, p.textSize, row.leftColor or EqTrainingHud.COLOR.white) end
            if row.right ~= nil then
                text(row.right, right, lineY, p.textSize, row.rightColor or EqTrainingHud.COLOR.white, RenderText.ALIGN_RIGHT)
            end
        end
    end
    resetText()
end


-- Each stat's colour, so a message says at a glance which training it is about.
EqTrainingHud.STAT_COLOR = {
    stamina = { 0.4, 0.7, 1, 1 },
    speed = { 1, 0.55, 0.15, 1 },
    agility = { 0.529, 0.706, 0, 1 },
    temperament = { 0.8, 0.55, 1, 1 },
}

-- Combo multiplier colours, hotter as it climbs.
EqTrainingHud.MULT_COLORS = {
    { 1, 1, 1, 1 },
    { 0.529, 0.706, 0, 1 },
    { 1, 0.82, 0.25, 1 },
    { 1, 0.55, 0.15, 1 },
    { 1, 0.25, 0.3, 1 },
}
EqTrainingHud.POP = { x = 0.5, y = 0.7, size = 0.024, sizePerMult = 0.004, growMs = 150, holdMs = 700, fadeMs = 500 }
-- A dressage movement's mark (James, 2026-10-31): below the horse, where it doesn't cover the line
-- ahead (0.17 never showed in game, under the game's own bottom layer it seems);
-- coloured by the mark (MARK_COLOURS: red to green), held a little longer, and with
-- a gold flourish either side at FLOURISH or better.
-- A mark has its own place, so no other pop can cut it short (James, 2026-10-31: some marks
-- showed far too briefly); one that comes while another is up waits until that one has shown
-- for minMs.
EqTrainingHud.MARK = { y = 0.3, holdMs = 1800, minMs = 1500, flourish = 9, barWidth = 0.035, barHeight = 0.004, barGap = 0.012 }
EqTrainingHud.MARK_COLOURS = { { 0, { 0.9, 0.2, 0.2, 1 } }, { 3, { 0.9, 0.2, 0.2, 1 } }, { 5, { 1, 0.55, 0.1, 1 } },
    { 7, { 1, 0.9, 0.2, 1 } }, { 8.5, { 0.35, 0.9, 0.35, 1 } }, { 10, { 0.35, 0.9, 0.35, 1 } } }


--- The colour of a mark out of 10 (pure): red up to 3, orange at 5, yellow at 7, green from 8.5.
--- @param mark number
--- @return table colour
function EqTrainingHud.markColour(mark)
    local stops = EqTrainingHud.MARK_COLOURS
    mark = math.max(stops[1][1], math.min(stops[#stops][1], mark or 0))
    for i = 2, #stops do
        local a, b = stops[i - 1], stops[i]
        if mark <= b[1] then
            local t = b[1] > a[1] and (mark - a[1]) / (b[1] - a[1]) or 1
            local c = {}
            for k = 1, 4 do c[k] = a[2][k] + (b[2][k] - a[2][k]) * t end
            return c
        end
    end
    return stops[#stops][2]
end
EqTrainingHud.PROMPT = { x = 0.5, y = 0.62, size = 0.021, barWidth = 0.12, barHeight = 0.006 }
-- An arrow after a prompt (James, 2026-10-31: "Gait change" with an up or down arrow, then
-- "Trot!", so the gait word doesn't trigger the key early): drawn as rows, no font glyph needed.
-- Height and gap are shares of the text size, width a share of the height.
EqTrainingHud.ARROW = { height = 0.8, width = 0.75, gap = 0.4, rows = 9, head = 0.55, stem = 0.34 }


--- The rows of an arrow (pure), each { y, h, w } as shares of its height and width, y from the
--- bottom: a pointed head over a narrower stem.
--- @param up boolean
--- @param n number|nil how many rows (ARROW.rows when nil)
--- @return table rows
function EqTrainingHud.arrowRows(up, n)
    local a = EqTrainingHud.ARROW
    local rows = {}
    n = n or a.rows
    local headRows = math.max(2, math.floor(n * a.head + 0.5))
    local h = 1 / n
    for i = 1, n do
        -- k counts from the tip: 1 is the point.
        local k = n - i + 1
        local w = k <= headRows and k / headRows or a.stem
        local y = (i - 1) * h
        if not up then y = 1 - i * h end
        table.insert(rows, { y = y, h = h, w = w })
    end
    return rows
end
EqTrainingHud.popState = nil
EqTrainingHud.sideState = nil
-- A big two-line announcement above the pops, for news that should feel like an occasion: a
-- round in your own event (James, 2026-10-29: "a bit more fanfare").
EqTrainingHud.ANNOUNCE = { x = 0.5, y = 0.8, size = 0.04, subSize = 0.02, growMs = 250, holdMs = 3500, fadeMs = 900 }
EqTrainingHud.GOLD = { 1, 0.78, 0.2, 1 }
EqTrainingHud.announceState = nil
-- The training view being shown (set by EqTrainingHooks while drawing), and the stat each
-- kind of pop is about.
EqTrainingHud.view = nil
EqTrainingHud.POP_STAT = {
    jump = "agility", knock = "agility", jumpLost = "agility",
    routine = "temperament", routineStart = "temperament", routineLost = "temperament", routineTest = "temperament", routineFault = "temperament",
    routineMark = "temperament", routineError = "temperament", routineScore = "temperament",
}
-- The gallop's news (EqExertion) belongs to no stat: it always shows in the middle, in status
-- colours (white good, red bad, grey idle).
EqTrainingHud.EXERTION_POPS = {
    ex_sprint = { "eq_pop_ex_sprint", "white", 4 },
    ex_sprintOver = { "eq_pop_ex_sprintOver", "grey", 1 },
    ex_blown = { "eq_pop_ex_blown", "red", 3 },
    ex_spent = { "eq_pop_ex_spent", "red", 3 },
    ex_fresh = { "eq_pop_ex_fresh", "white", 2 },
}


--- @param mult number 1..COMBO_MAX (ROUTINE_MAX for the routine)
--- @return table color
function EqTrainingHud.multColor(mult)
    local colors = EqTrainingHud.MULT_COLORS
    return colors[math.max(1, math.min(#colors, mult or 1))]
end


--- Show a short burst of text in the middle of the screen.
--- @param kind string jump, jumpLost, knock, routine, routineLost, routineStart, speedBank, courseFence, showJumping or an EXERTION_POPS key
--- @param mult number|string|nil the combo multiplier for jump and routine, the speed multiplier for speedBank, the text for showJumping
function EqTrainingHud.pop(kind, mult)
    local text, color, big
    if kind == "jump" then
        text = mult > 1 and string.format("x%d!", mult) or g_i18n:getText("eq_pop_clear")
        color, big = EqTrainingHud.multColor(mult), mult
    elseif kind == "routine" then
        text, color, big = string.format("x%d!", mult), EqTrainingHud.multColor(mult), mult
    elseif kind == "speedBank" then
        -- A Sprint banked for speed training: "Speed x7.3!", beside the panel (the middle is for
        -- alerts such as SPRINT! and Caution, James).
        text = string.format(g_i18n:getText("eq_pop_speedBank"), mult)
        color, big = EqTrainingHud.STAT_COLOR.speed, math.min(5, 1 + math.floor(mult / 2.5))
    elseif kind == "knock" then
        text, color, big = string.format(g_i18n:getText("eq_pop_knock"), EqTraining.COMBO_KNOCK_SECONDS), EqTrainingHud.COLOR.orange, 1
    elseif EqTrainingHud.EXERTION_POPS[kind] ~= nil then
        local pop = EqTrainingHud.EXERTION_POPS[kind]
        text, color, big = g_i18n:getText(pop[1]), EqTrainingHud.COLOR[pop[2]], pop[3]
    elseif kind == "routineFault" then
        text, color, big = string.format(g_i18n:getText("eq_pop_routineFault"), mult, EqDressage.FAULTS), EqTrainingHud.COLOR.grey, 2
    elseif kind == "routineMark" then
        -- A dressage test's movement marked out of 10 (EqDressagePath).
        text, color, big = string.format("%.1f", mult), EqTrainingHud.markColour(mult), 2
    elseif kind == "routineError" then
        text, color, big = string.format(g_i18n:getText("eq_pop_routineError"), mult, EqDressagePath.ERRORS), EqTrainingHud.COLOR.grey, 2
    elseif kind == "routineScore" then
        text, color, big = string.format(g_i18n:getText("eq_pop_routineScore"), string.format("%.1f", mult or 0)), EqTrainingHud.COLOR.white, 4
    elseif kind == "routineTest" then
        text, color, big = g_i18n:getText("eq_pop_routineTest"), EqTrainingHud.COLOR.white, 4
    elseif kind == "courseFence" then
        -- Recording a show jumping course: the jump just ridden through (EqCourseHooks).
        text, color, big = string.format(g_i18n:getText("eq_pop_courseFence"), mult), EqTrainingHud.COLOR.white, 2
    elseif kind == "showJumping" then
        -- A show jumping round's news (EqCourseHooks): the countdown, faults, the result.
        text, color, big = tostring(mult), EqTrainingHud.COLOR.white, 3
    elseif kind == "routineStart" then
        text, color, big = g_i18n:getText("eq_pop_routineStart"), EqTrainingHud.COLOR.white, 1
    else
        text, color, big = g_i18n:getText(kind == "routineLost" and "eq_pop_routineLost" or "eq_pop_comboLost"), EqTrainingHud.COLOR.grey, 1
    end
    local stat = EqTrainingHud.POP_STAT[kind]
    -- Every pop, good news or a setback, is in its stat's colour.
    if stat ~= nil and kind ~= "routineMark" then color = EqTrainingHud.STAT_COLOR[stat] end
    -- In a focused view, news about another stat goes in a small line above the panel instead.
    local view = EqTrainingHud.view
    -- In Freestyle the middle of the screen is only for what to press now, so all news goes there.
    -- In Condensed all of it does, as the only text on screen.
    local side = view == "condensed" or kind == "speedBank" or (stat ~= nil and view ~= nil and (view == "freestyle" or view ~= stat))
    -- A dressage mark always shows low in the middle, whatever the view (James 2026-10-31: in
    -- other views it went to the small line above the panel and seemed not to show at all).
    if kind == "routineMark" then side = false end
    if side then
        if stat ~= nil then text = string.format("%s: %s", g_i18n:getText("eq_stat_" .. stat), text) end
        EqTrainingHud.sideState = { text = text, color = color, at = g_time or 0 }
        return
    end
    if kind == "routineMark" then
        local m = EqTrainingHud.MARK
        local state = { text = text, color = color, big = big, y = m.y, holdMs = m.holdMs, flourish = (mult or 0) >= m.flourish }
        local now = g_time or 0
        local shown = EqTrainingHud.markState
        if shown ~= nil and now - shown.at < m.minMs then
            state.at = shown.at + m.minMs
            EqTrainingHud.markNext = state
        else
            state.at = now
            EqTrainingHud.markState, EqTrainingHud.markNext = state, nil
        end
        return
    end
    EqTrainingHud.popState = { text = text, color = color, big = big, at = g_time or 0 }
end


--- Draw the small line above the panel for news from another stat's training.
local function drawSidePop()
    local state = EqTrainingHud.sideState
    if state == nil then return end
    local p = EqTrainingHud.POP
    local age = (g_time or 0) - state.at
    local life = p.growMs + p.holdMs * 2 + p.fadeMs
    if age > life then
        EqTrainingHud.sideState = nil
        return
    end
    local alpha = age < life - p.fadeMs and 1 or 1 - (age - life + p.fadeMs) / p.fadeMs
    local c = state.color
    local panel = EqTrainingHud.PANEL
    shadowText(state.text, panel.right, panel.top + panel.padding, panel.titleSize, { c[1], c[2], c[3], alpha }, RenderText.ALIGN_RIGHT, true)
    resetText()
end


--- Show a big announcement in the top middle of the screen.
--- @param title string
--- @param sub string|nil a smaller line under it
--- @param color table|nil gold when nil
function EqTrainingHud.announce(title, sub, color)
    EqTrainingHud.announceState = { title = title, sub = sub, color = color or EqTrainingHud.GOLD, at = g_time or 0 }
end


local function drawAnnounce()
    local state = EqTrainingHud.announceState
    if state == nil then return end
    local a = EqTrainingHud.ANNOUNCE
    local age = (g_time or 0) - state.at
    if age > a.growMs + a.holdMs + a.fadeMs then
        EqTrainingHud.announceState = nil
        return
    end
    local grow = math.min(1, age / a.growMs)
    local scale = grow < 1 and grow * 1.15 or 1 + 0.15 * math.max(0, 1 - (age - a.growMs) / 200)
    local alpha = age < a.growMs + a.holdMs and 1 or 1 - (age - a.growMs - a.holdMs) / a.fadeMs
    local c = state.color
    shadowText(state.title, a.x, a.y, a.size * scale, { c[1], c[2], c[3], alpha }, RenderText.ALIGN_CENTER, true)
    if state.sub ~= nil then
        shadowText(state.sub, a.x, a.y - a.size * 0.9, a.subSize, { 1, 1, 1, alpha }, RenderText.ALIGN_CENTER, false)
    end
    resetText()
end


--- Draw a burst, growing in, holding and fading out.
--- @return boolean false once it is over
local function drawBurst(state)
    local p = EqTrainingHud.POP
    local age = (g_time or 0) - state.at
    local hold = state.holdMs or p.holdMs
    if age > p.growMs + hold + p.fadeMs then return false end
    local grow = math.min(1, age / p.growMs)
    -- Overshoot a little as it grows in, for some bounce.
    local scale = grow < 1 and grow * 1.25 or 1 + 0.25 * math.max(0, 1 - (age - p.growMs) / 120)
    local alpha = age < p.growMs + hold and 1 or 1 - (age - p.growMs - hold) / p.fadeMs
    local size = (p.size + p.sizePerMult * (state.big - 1)) * scale
    local c = state.color
    local y = state.y or p.y
    shadowText(state.text, p.x, y, size, { c[1], c[2], c[3], alpha }, RenderText.ALIGN_CENTER, true)
    if state.flourish then
        -- Gold bars either side that sweep out as it lands.
        local m = EqTrainingHud.MARK
        setTextBold(true)
        local half = getTextWidth(size, state.text) / 2 + m.barGap
        local width = m.barWidth * math.min(1, age / (p.growMs * 2))
        local gold = { EqTrainingHud.GOLD[1], EqTrainingHud.GOLD[2], EqTrainingHud.GOLD[3], alpha }
        for _, row in ipairs({ 0.25, 0.55 }) do
            local w = width * (row == 0.25 and 1 or 0.7)
            fill(p.x + half, y + size * row, w, m.barHeight, gold)
            fill(p.x - half - w, y + size * row, w, m.barHeight, gold)
        end
    end
    resetText()
    return true
end


--- Draw the current burst and the last mark.
function EqTrainingHud.drawPops()
    drawSidePop()
    drawAnnounce()
    local next = EqTrainingHud.markNext
    if next ~= nil and (g_time or 0) >= next.at then
        EqTrainingHud.markState, EqTrainingHud.markNext = next, nil
    end
    if EqTrainingHud.popState ~= nil and not drawBurst(EqTrainingHud.popState) then EqTrainingHud.popState = nil end
    if EqTrainingHud.markState ~= nil and not drawBurst(EqTrainingHud.markState) then EqTrainingHud.markState = nil end
end


--- Draw a routine request in the middle of the screen with the time left to start it.
--- @param value string
--- @param share number 0..1 of the time left
--- @param color table|nil yellow when nil
function EqTrainingHud.drawPrompt(value, share, color, arrow)
    local p = EqTrainingHud.PROMPT
    color = color or EqTrainingHud.COLOR.yellow
    shadowText(value, p.x, p.y, p.size, color, RenderText.ALIGN_CENTER, true)
    if arrow ~= nil then
        setTextBold(true)
        local height = p.size * EqTrainingHud.ARROW.height
        local width = height * EqTrainingHud.ARROW.width / (g_screenAspectRatio or 16 / 9)
        local x = p.x + getTextWidth(p.size, value) / 2 + p.size * EqTrainingHud.ARROW.gap
        -- One row per pixel of its height, so the head is smooth, not stepped (James, 2026-10-31).
        local rows = math.max(EqTrainingHud.ARROW.rows, math.floor(height * (g_screenHeight or 1080) + 0.5))
        local off = p.size * EqTrainingHud.SHADOW.share
        local shade = { 0, 0, 0, (color[4] or 1) * EqTrainingHud.SHADOW.alpha }
        for _, pass in ipairs({ { off, -off, shade }, { 0, 0, color } }) do
            for _, r in ipairs(EqTrainingHud.arrowRows(arrow > 0, rows)) do
                fill(x + pass[1] + width * (1 - r.w) / 2, p.y + pass[2] + height * r.y, width * r.w, height * r.h + 1e-4, pass[3])
            end
        end
    end
    -- No share: an untimed prompt, with no bar under it.
    if share == nil then
        resetText()
        return
    end
    local left = p.x - p.barWidth / 2
    -- A dark edge round the bar, so it shows against snow too.
    local edge = p.barHeight * 0.5
    fill(left - edge, p.y - p.barHeight * 2 - edge, p.barWidth + edge * 2, p.barHeight + edge * 2, { 0, 0, 0, 0.6 })
    fill(left, p.y - p.barHeight * 2, p.barWidth, p.barHeight, EqTrainingHud.COLOR.track)
    fill(left, p.y - p.barHeight * 2, p.barWidth * math.max(0, math.min(1, share)), p.barHeight, color)
    resetText()
end


-- Notes beside the panel, as wide as it and wrapped onto more lines, so the middle of the screen
-- stays for alerts (James, 2026-10-27): one above the panel, one below.
EqTrainingHud.PANEL_NOTE = { gap = 0.006, lineHeight = 0.019, size = 0.0145, aboveSize = 0.0165 }
-- Where the panel's bottom was last drawn (its height changes with its rows).
EqTrainingHud.panelBottom = nil

--- Pieces of one space-separated word, for wrapping. Chinese and Japanese have no spaces, so
--- each of their characters is a piece of its own; any other run of characters stays together.
--- @param word string
--- @return table pieces
local function wordPieces(word)
    local pieces, run = {}, ""
    for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local lead = char:byte(1)
        -- 0xE3-0xE9 lead the CJK blocks (U+3000-U+9FFF), 0xEF the full-width forms.
        if (lead >= 227 and lead <= 233) or lead == 239 then
            if run ~= "" then table.insert(pieces, run) end
            table.insert(pieces, char)
            run = ""
        else
            run = run .. char
        end
    end
    if run ~= "" then table.insert(pieces, run) end
    return pieces
end

--- Split text into lines no wider than width, at spaces or between Chinese and Japanese characters.
--- @param value string
--- @param size number
--- @param width number
--- @param bold boolean|nil
--- @return table lines
function EqTrainingHud.wrap(value, size, width, bold)
    setTextBold(bold == true)
    local lines, line = {}, nil
    for word in string.gmatch(tostring(value), "%S+") do
        for i, piece in ipairs(wordPieces(word)) do
            local candidate = line == nil and piece or line .. (i == 1 and " " or "") .. piece
            if line ~= nil and getTextWidth(size, candidate) > width then
                table.insert(lines, line)
                line = piece
            else
                line = candidate
            end
        end
    end
    if line ~= nil then table.insert(lines, line) end
    setTextBold(false)
    return lines
end

--- Draw a note above or below the panel, wrapped to its width.
--- @param value string
--- @param color table|nil white when nil
--- @param above boolean true above the panel (bold and a little bigger), else below it
function EqTrainingHud.drawPanelNote(value, color, above)
    local p, n = EqTrainingHud.PANEL, EqTrainingHud.PANEL_NOTE
    local size = above and n.aboveSize or n.size
    local lines = EqTrainingHud.wrap(value, size, p.width, above)
    local x = p.right - p.width
    local y
    if above then
        y = p.top + n.gap + (#lines - 1) * n.lineHeight + size * 0.25
    else
        y = (EqTrainingHud.panelBottom or p.top - 0.12) - n.gap - size
    end
    for i, line in ipairs(lines) do
        shadowText(line, x, y - (i - 1) * n.lineHeight, size, color or EqTrainingHud.COLOR.white, RenderText.ALIGN_LEFT, above)
    end
    resetText()
end


-- The bar alone in the middle: a small word above it, and a quick pulse to half brightness.
-- The Condensed view draws it at smallShare of the size.
EqTrainingHud.CENTRE_BAR = { labelSize = 0.013, pulseMs = 250, pulseDepth = 0.5, smallShare = 0.7 }

--- Draw just the prompt's bar in the middle of the screen, with an optional small word above.
--- @param share number 0..1
--- @param color table
--- @param label string|nil
--- @param labelColor table|nil
--- @param pulse boolean|nil true to pulse the bar
--- @param small boolean|nil true for the Condensed view's smaller bar
function EqTrainingHud.drawCentreBar(share, color, label, labelColor, pulse, small)
    local p, c = EqTrainingHud.PROMPT, EqTrainingHud.CENTRE_BAR
    if small then
        p = { x = p.x, y = p.y, barWidth = p.barWidth * c.smallShare, barHeight = p.barHeight * c.smallShare }
    end
    local alpha = 1
    if pulse then
        local phase = ((g_time or 0) % c.pulseMs) / c.pulseMs
        alpha = 1 - c.pulseDepth * (0.5 - 0.5 * math.cos(phase * 2 * math.pi))
    end
    local left = p.x - p.barWidth / 2
    local y = p.y - p.barHeight * 2
    local edge = p.barHeight * 0.5
    fill(left - edge, y - edge, p.barWidth + edge * 2, p.barHeight + edge * 2, { 0, 0, 0, 0.6 })
    fill(left, y, p.barWidth, p.barHeight, EqTrainingHud.COLOR.track)
    fill(left, y, p.barWidth * math.max(0, math.min(1, share)), p.barHeight, { color[1], color[2], color[3], alpha })
    if label ~= nil then
        local lc = labelColor or color
        shadowText(label, p.x, y + p.barHeight * 2, c.labelSize, { lc[1], lc[2], lc[3], pulse and alpha or 1 }, RenderText.ALIGN_CENTER, true)
    end
    resetText()
end


--- Split text into lines that fit a width.
--- @param value string
--- @param width number
--- @param size number
--- @return table lines
local function wrap(value, width, size)
    return EqTrainingHud.wrap(value, size, width, false)
end


--- Start a series of help popups, replacing any showing.
--- @param pages table list of { title, text }
--- @param place string|nil "menu" over RLRM's menu, "dialog" over its Diseases dialog, nil in the world
--- @param seenKey string|nil seen flag set once the last page is clicked away
function EqTrainingHud.showHelp(pages, place, seenKey)
    if pages == nil or #pages == 0 then return end
    EqTrainingHud.pages = pages
    EqTrainingHud.place = place
    EqTrainingHud.seenKey = seenKey
    EqTrainingHud.pageIndex = 1
    -- A click held down when the popup opens does not count.
    EqTrainingHud.mouseWasDown = true
end


--- Close the popups without marking them seen.
function EqTrainingHud.closeHelp()
    EqTrainingHud.pages = nil
    EqTrainingHud.pageIndex = 0
    EqTrainingHud.seenKey = nil
end


--- @return boolean true while a help popup is showing
function EqTrainingHud.isHelpShowing()
    return EqTrainingHud.pages ~= nil
end


--- Move to the next page on a click. Never takes the click from the game.
--- In the menu every click counts, even one on a tab or a list.
local function updateHelp()
    local down = Input ~= nil and Input.isMouseButtonPressed ~= nil and Input.isMouseButtonPressed(Input.MOUSE_BUTTON_LEFT) or false
    local guiOpen = g_gui ~= nil and g_gui:getIsGuiVisible()
    local clicked = down and not EqTrainingHud.mouseWasDown and (EqTrainingHud.place ~= nil or not guiOpen)
    EqTrainingHud.mouseWasDown = down

    if not clicked then return end
    EqTrainingHud.pageIndex = EqTrainingHud.pageIndex + 1
    if EqTrainingHud.pageIndex > #EqTrainingHud.pages then
        local seenKey = EqTrainingHud.seenKey
        EqTrainingHud.closeHelp()
        if seenKey ~= nil then EqTrainingHud.markSeen(seenKey) end
    end
end


--- Draw the help popup, if one is showing. Call every frame while riding, in the world and in
--- RLRM's menu; a popup only draws where it belongs, and only once a frame.
--- @param place string|nil "menu" or "dialog" when called from RLRM's menu or Diseases dialog
function EqTrainingHud.drawHelp(place)
    if EqTrainingHud.pages == nil then return end
    -- A world popup waits while the HUD is hidden (menus keep theirs: the game shows menus anyway).
    if place == nil and EqTrainingHud.gameHudHidden() then return end
    local guiOpen = g_gui ~= nil and g_gui:getIsGuiVisible()
    if EqTrainingHud.place ~= place or (place == nil and guiOpen) then
        -- A menu's popups go with the menu; world popups wait until every menu is closed.
        if EqTrainingHud.place ~= nil and not guiOpen then EqTrainingHud.closeHelp() end
        return
    end
    if g_time ~= nil and EqTrainingHud.drawnAt == g_time then return end
    EqTrainingHud.drawnAt = g_time
    updateHelp()
    if EqTrainingHud.pages == nil then return end

    -- The engine draws every text of a 2D layer after its images, so over a menu the menu's own
    -- text showed through the popup's background. A layer of its own puts the popup on top, the
    -- way the GUI stacks a dialog over its screen.
    if new2DLayer ~= nil then new2DLayer() end
    if not EqTrainingHud.layerLogged then
        EqTrainingHud.layerLogged = true
        Log:info("EqTrainingHud: popups on their own layer: %s", tostring(new2DLayer ~= nil))
    end

    local p = EqTrainingHud.POPUP
    local page = EqTrainingHud.pages[EqTrainingHud.pageIndex]
    local inner = p.width - p.padding * 2
    local lines = wrap(page.text, inner, p.textSize)
    local count = #EqTrainingHud.pages
    local footer = EqTrainingHud.pageIndex < count
        and string.format(g_i18n:getText("eq_help_next"), EqTrainingHud.pageIndex, count)
        or g_i18n:getText("eq_help_close")

    local height = p.padding * 2 + p.lineHeight * (#lines + 2.4)
    local x = p.centerX - p.width / 2
    fill(x, p.bottom, p.width, height, EqTrainingHud.POPUP_BACKGROUND)
    local accent = page.color or EqTrainingHud.COLOR.green
    fill(x + p.padding, p.bottom + height - p.padding - p.lineHeight * 1.4, inner, 0.0012, accent)

    local y = p.bottom + height - p.padding - p.lineHeight
    text(page.title, p.centerX, y, p.titleSize, accent, RenderText.ALIGN_CENTER, true)
    y = y - p.lineHeight * 0.4
    for _, line in ipairs(lines) do
        y = y - p.lineHeight
        text(line, p.centerX, y, p.textSize, EqTrainingHud.COLOR.white, RenderText.ALIGN_CENTER)
    end
    text(footer, p.centerX, p.bottom + p.padding, p.textSize * 0.9, EqTrainingHud.COLOR.grey, RenderText.ALIGN_CENTER)
    resetText()
end


--- @return string|nil path of the file that remembers which help was seen
local function seenPath()
    if g_modSettingsDirectory == nil then return nil end
    return g_modSettingsDirectory .. EqTrainingHud.SEEN_FILE
end


--- @param key string a training view name
--- @return boolean true once that view's help has popped up by itself
function EqTrainingHud.hasSeen(key)
    if EqTrainingHud.seen == nil then
        EqTrainingHud.seen = {}
        local path = seenPath()
        local xmlFile = path ~= nil and XMLFile.loadIfExists("eqHelpSeen", path) or nil
        if xmlFile ~= nil then
            xmlFile:iterate("realisticEquestrian.helpSeen.view", function(_, viewKey)
                local name = xmlFile:getString(viewKey .. "#name")
                if name ~= nil then EqTrainingHud.seen[name] = true end
            end)
            xmlFile:delete()
        end
    end
    return EqTrainingHud.seen[key] == true
end


--- Remember that a view's help has been seen, in modSettings.
--- @param key string
function EqTrainingHud.markSeen(key)
    EqTrainingHud.hasSeen(key)
    EqTrainingHud.seen[key] = true
    EqTrainingHud.saveSeen()
end


--- Forget every help popup seen, so each shows again the next time (the Help popups setting).
function EqTrainingHud.resetSeen()
    EqTrainingHud.seen = {}
    EqTrainingHud.saveSeen()
end


--- @return boolean true when any help popup has been seen
function EqTrainingHud.anySeen()
    EqTrainingHud.hasSeen("")
    return next(EqTrainingHud.seen) ~= nil
end


--- Write the seen list to modSettings.
function EqTrainingHud.saveSeen()
    local path = seenPath()
    if path == nil then return end
    if createFolder ~= nil then createFolder(g_modSettingsDirectory) end
    local xmlFile = XMLFile.create("eqHelpSeen", path, "realisticEquestrian")
    if xmlFile == nil then
        Log:warning("EqTrainingHud: could not write %s", path)
        return
    end
    local i = 0
    for name in pairs(EqTrainingHud.seen) do
        xmlFile:setString(string.format("realisticEquestrian.helpSeen.view(%d)#name", i), name)
        i = i + 1
    end
    xmlFile:save()
    xmlFile:delete()
end


function EqTrainingHud.reset()
    EqTrainingHud.closeHelp()
    EqTrainingHud.popState = nil
    EqTrainingHud.announceState = nil
    if EqTrainingHud.overlay ~= nil then
        EqTrainingHud.overlay:delete()
        EqTrainingHud.overlay = nil
    end
end

--[[
    EqTrainingHud.lua
    What the rider sees while training: a small panel on the right of the screen with the
    exertion meter and a line per stat, each in the colour of its state, and help popups at the
    bottom of the screen.

    The base game's help panel (addExtraPrintText) has no colours and cuts long lines off, so
    the panel is drawn here with plain text and a one-pixel texture. Popups never take the mouse:
    a click anywhere moves on to the next page or closes the last one, and each page closes by
    itself after HELP_TIMEOUT_MS. Which views' help the player has already seen is kept in
    modSettings, so it only pops up by itself the first time.
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
}

-- Screen positions are shares of the screen, from the bottom left.
EqTrainingHud.PANEL = { right = 0.985, top = 0.66, width = 0.2, padding = 0.008, lineHeight = 0.02,
    textSize = 0.0145, titleSize = 0.0165, barHeight = 0.008 }
EqTrainingHud.POPUP = { centerX = 0.5, bottom = 0.11, width = 0.36, padding = 0.012, lineHeight = 0.019,
    textSize = 0.015, titleSize = 0.0175 }
EqTrainingHud.HELP_TIMEOUT_MS = 45000
EqTrainingHud.SEEN_FILE = "FS25_RealisticEquestrian.xml"

EqTrainingHud.pages = nil
EqTrainingHud.pageIndex = 0
EqTrainingHud.pageShownAt = 0
EqTrainingHud.mouseWasDown = true
EqTrainingHud.seen = nil


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
    if width <= 0 or height <= 0 then return end
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
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    setTextBold(bold == true)
    setTextColor(color[1], color[2], color[3], color[4])
    renderText(x, y, size, value)
end


local function resetText()
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end


--- Draw the training panel.
--- @param title string
--- @param rows table list of { left, leftColor, right, rightColor } text rows and
---     { bar = 0..1, color } meter rows
function EqTrainingHud.drawPanel(title, rows)
    local p = EqTrainingHud.PANEL
    local height = p.padding * 2 + p.lineHeight
    for _, row in ipairs(rows) do
        height = height + (row.bar ~= nil and (p.barHeight + p.padding) or p.lineHeight)
    end
    local x = p.right - p.width
    local y = p.top - height
    fill(x, y, p.width, height, EqTrainingHud.COLOR.background)

    local left, right = x + p.padding, p.right - p.padding
    local lineY = p.top - p.padding - p.lineHeight * 0.8
    text(title, left, lineY, p.titleSize, EqTrainingHud.COLOR.white, nil, true)
    for _, row in ipairs(rows) do
        if row.bar ~= nil then
            local barY = lineY - p.padding * 0.5 - p.barHeight
            fill(left, barY, right - left, p.barHeight, EqTrainingHud.COLOR.track)
            fill(left, barY, (right - left) * math.min(math.max(row.bar, 0), 1), p.barHeight, row.color or EqTrainingHud.COLOR.white)
            lineY = lineY - p.barHeight - p.padding
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


--- Split text into lines that fit a width.
--- @param value string
--- @param width number
--- @param size number
--- @return table lines
local function wrap(value, width, size)
    local lines, line = {}, ""
    for word in tostring(value):gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if line == "" or getTextWidth(size, candidate) <= width then
            line = candidate
        else
            table.insert(lines, line)
            line = word
        end
    end
    if line ~= "" then table.insert(lines, line) end
    return lines
end


--- Start a series of help popups, replacing any showing.
--- @param pages table list of { title, text }
function EqTrainingHud.showHelp(pages)
    if pages == nil or #pages == 0 then return end
    EqTrainingHud.pages = pages
    EqTrainingHud.pageIndex = 1
    EqTrainingHud.pageShownAt = g_time or 0
    -- A click held down when the popup opens does not count.
    EqTrainingHud.mouseWasDown = true
end


function EqTrainingHud.closeHelp()
    EqTrainingHud.pages = nil
    EqTrainingHud.pageIndex = 0
end


--- @return boolean true while a help popup is showing
function EqTrainingHud.isHelpShowing()
    return EqTrainingHud.pages ~= nil
end


--- Move to the next page on a click or after the timeout. Never takes the click from the game.
local function updateHelp()
    local down = Input ~= nil and Input.isMouseButtonPressed ~= nil and Input.isMouseButtonPressed(Input.MOUSE_BUTTON_LEFT) or false
    local guiOpen = g_gui ~= nil and g_gui:getIsGuiVisible()
    local clicked = down and not EqTrainingHud.mouseWasDown and not guiOpen
    EqTrainingHud.mouseWasDown = down

    local timedOut = (g_time or 0) - EqTrainingHud.pageShownAt > EqTrainingHud.HELP_TIMEOUT_MS
    if not clicked and not timedOut then return end
    EqTrainingHud.pageIndex = EqTrainingHud.pageIndex + 1
    EqTrainingHud.pageShownAt = g_time or 0
    if EqTrainingHud.pageIndex > #EqTrainingHud.pages then EqTrainingHud.closeHelp() end
end


--- Draw the help popup, if one is showing. Call every frame while riding.
function EqTrainingHud.drawHelp()
    if EqTrainingHud.pages == nil then return end
    updateHelp()
    if EqTrainingHud.pages == nil then return end

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
    fill(x, p.bottom, p.width, height, { 0, 0, 0, 0.72 })
    fill(x + p.padding, p.bottom + height - p.padding - p.lineHeight * 1.25, inner, 0.0012, EqTrainingHud.COLOR.green)

    local y = p.bottom + height - p.padding - p.lineHeight
    text(page.title, p.centerX, y, p.titleSize, EqTrainingHud.COLOR.green, RenderText.ALIGN_CENTER, true)
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
    if EqTrainingHud.overlay ~= nil then
        EqTrainingHud.overlay:delete()
        EqTrainingHud.overlay = nil
    end
end

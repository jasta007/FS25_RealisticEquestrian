--[[
    EqSkillsHudBox.lua
    The look-at Skills box, drawn like RLRM's Genetics box but with a colour per line.

    RLRM's RL_InfoDisplayKeyValueBox colours a line only when its value is one of RLRM's own
    genetics keys, so our lines came out white. This box inherits its size and background and
    replaces draw: each line has a colour for its title and value, and an optional suffix in a
    colour of its own, so "72 - Competitor" takes the skill colour and "(Very high)" the
    potential colour, and the title can take a colour of its own (each stat's colour). A line
    without a colour is drawn white. When the lines are wider than RLRM's box (a recent gain makes
    "72 - Competitor (+2.8) (Very high)"), the box grows to the left to fit them.
]]

EqSkillsHudBox = {}

local WHITE = { 1, 1, 1, 1 }


--- @return table|nil class RLRM's genetics box class, nil when RLRM no longer has it
local function baseClass()
    return EqRLRM.get("RL_InfoDisplayKeyValueBox")
end


--- @return boolean true when the coloured box can be made
function EqSkillsHudBox.isAvailable()
    local base = baseClass()
    return base ~= nil and type(base.new) == "function" and type(base.storeScaledValues) == "function"
end


--- Called by InfoDisplay:createBox.
--- @param infoDisplay table
--- @param uiScale number
--- @return table box
function EqSkillsHudBox.new(infoDisplay, uiScale)
    local base = baseClass()
    local self = base.new(infoDisplay, uiScale)
    -- The game's Class() metatables are protected, so the box keeps RLRM's and our two
    -- methods are set on the instance, where they win over the class's.
    self.addLine = EqSkillsHudBox.addLine
    self.draw = EqSkillsHudBox.draw
    return self
end


--- @param key string title
--- @param value string|nil
--- @param color table|nil { r, g, b, a } for the value, and the title when keyColor is nil
--- @param suffix string|nil drawn after the value, such as "(High)"
--- @param suffixColor table|nil
--- @param keyColor table|nil for the title, the value's colour when nil
function EqSkillsHudBox:addLine(key, value, color, suffix, suffixColor, keyColor)
    self.currentLineIndex = (self.currentLineIndex or 0) + 1
    local line = self.lines[self.currentLineIndex]
    if line == nil then
        line = {}
        table.insert(self.lines, line)
    end
    line.key = key
    line.value = value or ""
    line.color = color or WHITE
    line.suffix = suffix
    line.suffixColor = suffixColor or line.color
    line.keyColor = keyColor or line.color
    line.isWarning = false
    line.isActive = true
end


--- Same layout as RL_InfoDisplayKeyValueBox:draw, with each line's own colours.
--- @param posX number
--- @param posY number
--- @return number posX
--- @return number newPosY
function EqSkillsHudBox:draw(posX, posY)
    local height = self.titleAndBoxHeight
    local width = self.boxWidth
    local gap = 12 * g_pixelSizeX
    for _, line in ipairs(self.lines) do
        if line.isActive then
            height = height + self.lineHeight
            local text = line.value .. ((line.suffix ~= nil and line.suffix ~= "") and (" " .. line.suffix) or "")
            local needed = self.keyOffsetX - self.valueOffsetX + getTextWidth(self.keyTextSize, line.key)
                + getTextWidth(self.valueTextSize, text) + gap
            width = math.max(width, needed)
        end
    end
    local leftX = posX - width
    -- RLRM sizes the background pieces to boxWidth; stretch them when the lines need more.
    for _, overlay in ipairs({ self.bgBottom, self.bgScale, self.bgTop }) do overlay:setDimension(width, nil) end

    self.bgScale:setDimension(nil, height - self.bgBottom.height - self.bgTop.height)
    self.bgBottom:setPosition(leftX, posY)
    self.bgBottom:render()
    self.bgScale:setPosition(leftX, self.bgBottom.y + self.bgBottom.height)
    self.bgScale:render()
    self.bgTop:setPosition(leftX, self.bgScale.y + self.bgScale.height)
    self.bgTop:render()

    local titleY = self.bgTop.y + self.bgTop.height + self.titleOffsetY
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    setTextBold(true)
    renderText(leftX + self.titleOffsetX, titleY, self.titleTextSize, self.title)
    setTextBold(false)

    local keyX = leftX + self.keyOffsetX
    local valueX = posX + self.valueOffsetX
    local y = titleY + self.titleToLineOffsetY
    local dash = HUD.COLOR.INACTIVE

    for _, line in ipairs(self.lines) do
        if line.isActive then
            local color, keyColor = line.color, line.keyColor or line.color
            setTextColor(keyColor[1], keyColor[2], keyColor[3], keyColor[4])
            setTextAlignment(RenderText.ALIGN_LEFT)
            renderText(keyX, y, self.keyTextSize, line.key)
            setTextColor(color[1], color[2], color[3], color[4])
            local keyWidth = getTextWidth(self.keyTextSize, line.key)

            setTextAlignment(RenderText.ALIGN_RIGHT)
            local right = valueX
            local valueWidth = 0
            if line.suffix ~= nil and line.suffix ~= "" then
                local suffix = " " .. line.suffix
                local sc = line.suffixColor
                setTextColor(sc[1], sc[2], sc[3], sc[4])
                renderText(right, y, self.valueTextSize, suffix)
                local width = getTextWidth(self.valueTextSize, suffix)
                right = right - width
                valueWidth = valueWidth + width
                setTextColor(color[1], color[2], color[3], color[4])
            end
            renderText(right, y, self.valueTextSize, line.value)
            valueWidth = valueWidth + getTextWidth(self.valueTextSize, line.value)

            local dashStart = keyX + keyWidth + 3 * g_pixelSizeX
            local dashLength = valueX - valueWidth - dashStart - 3 * g_pixelSizeX
            drawDashedLine(dashStart, y, dashLength, self.dashedLineHeight, self.dashWidth, self.dashGapWidth,
                dash[1], dash[2], dash[3], dash[4], true)

            y = y + self.lineToLineOffsetY
        end
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    self.doShowNextFrame = false
    return posX, self.bgTop.y + self.bgTop.height
end

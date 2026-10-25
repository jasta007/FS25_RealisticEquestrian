--[[
    EqListBadge.lua
    Marks a horse waiting for Manual Transport delivery in RLRM's animal lists (Transfer, Move,
    Sell, Animals and the rest), so the player can see which horse to load at the stable without
    remembering it. Wraps RLAnimalQuery.formatAnimalRow, which every RLRM list frame builds its
    rows through, and fills the row's descriptor badge, the same corner RLRM uses for its marks.
    The badge sits bottom right by default, where RLRM's status icons (pregnant, sick) also go,
    so it is moved to the card's top right corner, above the checkbox, a little smaller.
    No RLRM file changes.
]]

EqListBadge = {}

local Log = EqLog


--- @param row table RLRM's formatted row
--- @param item table|nil the list item, with .cluster the RLRM Animal
function EqListBadge.apply(row, item)
    local animal = item ~= nil and item.cluster or nil
    if animal == nil or animal.isHorse == nil or not animal:isHorse() then return end
    if not EqCompetitionManager.awaitingDelivery(animal) then return end

    -- Ours beats RLRM's mark text: a delivery has a deadline, a mark does not.
    row.descriptorVisible = true
    row.descriptorText = g_i18n:getText("eq_ui_status_awaitingDelivery")
end


-- RLRM's list frames that show the badge, each with a populateCellForItemInSection.
EqListBadge.FRAMES = { "RLMenuBuyFrame", "RLMenuInfoFrame", "RLMenuMoveFrame", "RLMenuSellFrame", "RLMenuTransferFrame" }

-- Gap from the card's top edge to the badge, and the badge's text scale.
EqListBadge.TOP_GAP_PX = 5
EqListBadge.TEXT_SCALE = 0.85


--- Move a card's badge from the bottom right to the top right corner. Done once per card;
--- the list reuses its cards, so the badge stays there for every row (RLRM's marks too).
--- @param cell table the list card
function EqListBadge.moveToTop(cell)
    local badge = cell.getAttribute ~= nil and cell:getAttribute("herdsmanPurchase") or nil
    if badge == nil or badge.eqTopRight or badge.position == nil or badge.absPosition == nil
        or cell.absPosition == nil or cell.absSize == nil then
        return
    end
    badge.eqTopRight = true

    if badge.setTextSize ~= nil and badge.textSize ~= nil then
        badge:setTextSize(badge.textSize * EqListBadge.TEXT_SCALE)
    end
    local height = badge.textSize or 0
    local gap = EqListBadge.TOP_GAP_PX / (g_screenHeight or 1080)
    if g_pixelSizeScaledY ~= nil then gap = EqListBadge.TOP_GAP_PX * g_pixelSizeScaledY end

    -- Offsets inside the card, so it doesn't matter where the list has put the card yet.
    local currentY = badge.absPosition[2] - cell.absPosition[2]
    local targetY = cell.absSize[2] - gap - height
    badge:setPosition(badge.position[1], badge.position[2] + targetY - currentY)
end


--- @param guarded function main.lua's error guard
function EqListBadge.install(guarded)
    local query = EqRLRM.get("RLAnimalQuery")
    local original = query.formatAnimalRow
    query.formatAnimalRow = function(item, ...)
        local row = original(item, ...)
        if type(row) == "table" then
            guarded("list delivery badge", function() EqListBadge.apply(row, item) end)
        end
        return row
    end
    Log:debug("EqListBadge: hooked RLAnimalQuery.formatAnimalRow")

    for _, name in ipairs(EqListBadge.FRAMES) do
        local frame = EqRLRM.get(name)
        if frame ~= nil and type(frame.populateCellForItemInSection) == "function" then
            local populate = frame.populateCellForItemInSection
            frame.populateCellForItemInSection = function(self, list, section, index, cell, ...)
                local result = populate(self, list, section, index, cell, ...)
                if type(cell) == "table" then
                    guarded("list badge position", function() EqListBadge.moveToTop(cell) end)
                end
                return result
            end
        end
    end
end

--[[
    EqListBadge.lua
    Marks a horse waiting for Manual Transport delivery in RLRM's animal lists (Transfer, Move,
    Sell, Animals and the rest), so the player can see which horse to load at the stable without
    remembering it. Wraps RLAnimalQuery.formatAnimalRow, which every RLRM list frame builds its
    rows through, and fills the row's descriptor badge, the same corner RLRM uses for its marks.
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
end

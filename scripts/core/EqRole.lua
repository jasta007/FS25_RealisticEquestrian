--[[
    EqRole.lua
    A role per horse: what the player plans it for ("Dressage", "Breeding"), so seven or eight
    horses stay easy to tell apart. A role is the horse's staff focus (record.focus): hired
    staff train a horse to its role's profile (EqTraining.FOCUS).

    Set with the Set role button in RLRM's Info tab (EqRoleMenu), which then groups horses by
    role. The role also shows on the look-at Skills box, in RLRM's animal lists and on the riding
    panel. "No role" is the old balanced focus.
]]

EqRole = {}

EqRole.NONE = "balanced"
-- The order the Set role button cycles through, and the order of the Info tab's role groups
-- (No role last there).
EqRole.ORDER = { "balanced", "dressage", "showJumping", "crossCountry", "eventing", "racing", "breeding", "sale" }

-- A soft gold, so the role reads as a note of the player's, apart from the stat colours.
EqRole.COLOR = { 1, 0.85, 0.45, 1 }


--- @param role string|nil
--- @return boolean
function EqRole.isKnown(role)
    for _, known in ipairs(EqRole.ORDER) do
        if known == role then return true end
    end
    return false
end


--- @param record table|nil EqHorseRecord
--- @return string role a role of ORDER, NONE when unset or unknown
function EqRole.get(record)
    local role = record ~= nil and record.focus or nil
    return EqRole.isKnown(role) and role or EqRole.NONE
end


--- @param record table|nil
--- @return boolean true when the player gave the horse a role
function EqRole.has(record)
    return EqRole.get(record) ~= EqRole.NONE
end


--- @param role string|nil
--- @return string role the one after it in ORDER, back to NONE after the last
function EqRole.next(role)
    for i, known in ipairs(EqRole.ORDER) do
        if known == role then return EqRole.ORDER[i % #EqRole.ORDER + 1] end
    end
    return EqRole.ORDER[2]
end


--- @param role string
--- @return string text "Dressage", "No role"
function EqRole.text(role)
    return g_i18n:getText("eq_role_" .. (EqRole.isKnown(role) and role or EqRole.NONE))
end


--- Regroup RLRM's Info tab sections by role: diseased horses stay first, then one section per
--- role in ORDER, horses without one last. Left as RLRM made them when the pen holds anything
--- but horses, or no horse has a role.
--- @param items table RLRM's sorted list items, each with .cluster
--- @param sectionOrder table RLRM's section keys
--- @param itemsBySection table
--- @param titlesBySection table
--- @param roleOf function(cluster) -> role|nil, nil when it isn't a horse
--- @return table sectionOrder, table itemsBySection, table titlesBySection
function EqRole.groupSections(items, sectionOrder, itemsBySection, titlesBySection, roleOf)
    if items == nil or #items == 0 then return sectionOrder, itemsBySection, titlesBySection end

    local roles, anyRole = {}, false
    for i, item in ipairs(items) do
        local role = item.cluster ~= nil and roleOf(item.cluster) or nil
        if role == nil then return sectionOrder, itemsBySection, titlesBySection end
        roles[i] = role
        if role ~= EqRole.NONE then anyRole = true end
    end
    if not anyRole then return sectionOrder, itemsBySection, titlesBySection end

    local order, byKey, titles = {}, {}, {}
    -- RLRM's diseased section first, as it was.
    local diseased, sick = sectionOrder[1], {}
    if diseased ~= nil and diseased:sub(1, 2) == "__" then
        table.insert(order, diseased)
        byKey[diseased] = itemsBySection[diseased]
        titles[diseased] = titlesBySection[diseased]
        for _, item in ipairs(itemsBySection[diseased] or {}) do sick[item] = true end
    end

    local grouped = {}
    for i, item in ipairs(items) do
        if not sick[item] then
            grouped[roles[i]] = grouped[roles[i]] or {}
            table.insert(grouped[roles[i]], item)
        end
    end
    local roleOrder = {}
    for i = 2, #EqRole.ORDER do table.insert(roleOrder, EqRole.ORDER[i]) end
    table.insert(roleOrder, EqRole.NONE)
    for _, role in ipairs(roleOrder) do
        if grouped[role] ~= nil then
            local key = "eqRole_" .. role
            table.insert(order, key)
            byKey[key] = grouped[role]
            titles[key] = EqRole.text(role)
        end
    end
    return order, byKey, titles
end

--[[
    EqFeed.lua
    Horse feeds: which fill types horses eat, and the training boost each gives. Pure functions
    over fill type names, so they run headless; EqFeedHooks turns the game's indices into names.

    - planGroups rewrites the map's HORSE food groups: banned feeds out, every known feed in,
      each joining the map group that already holds most of its kind.
    - dietBoost reads a trough: every feed in it gives its full boost and the boosts add up,
      except that feeds sharing a stack name (carrots and apples) count once, the best of them.
]]

EqFeed = {}

EqFeed.GROUP_ORDER = { "hay", "grain", "treat" }

local Log = EqLog


--- @param text string|nil space-separated names
--- @return table names
local function splitNames(text)
    local names = {}
    for name in string.gmatch(text or "", "%S+") do table.insert(names, string.upper(name)) end
    return names
end


--- @param xmlFile table An open XMLFile on feeds.xml
--- @return table config { banned, groups, groupByName, feeds, feedByFillType }
function EqFeed.read(xmlFile)
    local config = { banned = {}, groups = {}, groupByName = {}, feeds = {}, feedByFillType = {} }

    for _, name in ipairs(splitNames(xmlFile:getString("feeds.banned#fillTypes"))) do
        config.banned[name] = true
    end

    local i = 0
    while true do
        local key = string.format("feeds.group(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local group = {
            name = xmlFile:getString(key .. "#name"),
            title = xmlFile:getString(key .. "#title"),
            otherTitle = xmlFile:getString(key .. "#otherTitle"),
            productionWeight = xmlFile:getFloat(key .. "#productionWeight", 0.1),
            eatWeight = xmlFile:getFloat(key .. "#eatWeight", 0.1),
        }
        table.insert(config.groups, group)
        config.groupByName[group.name] = group
        i = i + 1
    end

    i = 0
    while true do
        local key = string.format("feeds.feed(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local boost = {}
        for _, stat in ipairs(EqConstants.STAT_KEYS) do boost[stat] = xmlFile:getFloat(key .. "#" .. stat, 0) end
        local group = xmlFile:getString(key .. "#group", "hay")
        if config.groupByName[group] == nil then
            Log:warning("EqFeed: feed %d names unknown group '%s', using hay", i, group)
            group = "hay"
        end
        for _, name in ipairs(splitNames(xmlFile:getString(key .. "#fillTypes"))) do
            local feed = { fillType = name, group = group, boost = boost, stack = xmlFile:getString(key .. "#stack"),
                row = xmlFile:getString(key .. "#row") }
            table.insert(config.feeds, feed)
            config.feedByFillType[name] = feed
        end
        i = i + 1
    end

    return config
end


--- @param path string
--- @return table|nil config
function EqFeed.load(path)
    local xmlFile = XMLFile.load("eqFeeds", path)
    if xmlFile == nil then
        Log:error("EqFeed: could not open %s", path)
        return nil
    end
    local config = EqFeed.read(xmlFile)
    xmlFile:delete()
    Log:info("EqFeed: %d feeds in %d groups", #config.feeds, #config.groups)
    return config
end


--- Rewrite a map's horse food groups. Groups are edited in place and new ones appended.
--- @param groups table list of { names = { fill type names } }; a created group also gets
---     isNew = true and group = the config group it was made from
--- @param config table from EqFeed.read
--- @param exists function name -> boolean, whether the game knows this fill type
--- @return table groups the same list, without groups left empty
function EqFeed.planGroups(groups, config, exists)
    local present = {}
    for _, group in ipairs(groups) do
        local kept = {}
        for _, name in ipairs(group.names) do
            if not config.banned[name] and not present[name] then
                table.insert(kept, name)
                present[name] = true
            end
        end
        group.names = kept
    end

    for _, groupName in ipairs(EqFeed.GROUP_ORDER) do
        local missing = {}
        for _, feed in ipairs(config.feeds) do
            if feed.group == groupName and not present[feed.fillType] and not config.banned[feed.fillType]
                and exists(feed.fillType) then
                table.insert(missing, feed.fillType)
                present[feed.fillType] = true
            end
        end

        if #missing > 0 then
            local home, homeCount = nil, 0
            for _, group in ipairs(groups) do
                local count = 0
                for _, name in ipairs(group.names) do
                    local feed = config.feedByFillType[name]
                    if feed ~= nil and feed.group == groupName then count = count + 1 end
                end
                if count > homeCount then home, homeCount = group, count end
            end
            if home == nil then
                home = { names = {}, isNew = true, group = config.groupByName[groupName] }
                table.insert(groups, home)
            end
            for _, name in ipairs(missing) do table.insert(home.names, name) end
        end
    end

    local result = {}
    for _, group in ipairs(groups) do
        if #group.names > 0 then table.insert(result, group) end
    end
    return result
end


--- Which of our groups (hay, grain, treat) a food group mostly holds.
--- @param names table fill type names
--- @param config table from EqFeed.read
--- @return string|nil group name, nil when it holds none of our feeds
function EqFeed.groupKind(names, config)
    local counts, best, bestCount = {}, nil, 0
    for _, name in ipairs(names) do
        local feed = config.feedByFillType[name]
        if feed ~= nil then
            counts[feed.group] = (counts[feed.group] or 0) + 1
            if counts[feed.group] > bestCount then best, bestCount = feed.group, counts[feed.group] end
        end
    end
    return best
end


--- The best boost any of these feeds gives each stat, on its own.
--- @param names table fill type names
--- @param config table from EqFeed.read
--- @return table boost stat -> share
function EqFeed.bestBoost(names, config)
    local best = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do best[stat] = 0 end
    for _, name in ipairs(names) do
        local feed = config.feedByFillType[name]
        if feed ~= nil then
            for stat, value in pairs(feed.boost) do best[stat] = math.max(best[stat] or 0, value) end
        end
    end
    return best
end


--- The stats any of these feeds can boost, in STAT_KEYS order.
--- @param names table fill type names
--- @param config table from EqFeed.read
--- @return table stats
function EqFeed.boostedStats(names, config)
    local best = EqFeed.bestBoost(names, config)
    local stats = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do
        if best[stat] > 0 then table.insert(stats, stat) end
    end
    return stats
end


--- Upper bounds (exclusive) of the "+" and "++" bands; anything stronger is "+++".
--- feeds.xml uses 0.10 (small), 0.20 (moderate) and 0.30 (strong).
EqFeed.STRENGTH_BANDS = { 0.15, 0.25 }


--- How strong a boost is, as "+", "++" or "+++" ("" for none).
--- @param share number 0.1 = 10% faster training
--- @return string
function EqFeed.strengthMarks(share)
    if share == nil or share <= 0 then return "" end
    local marks = 1
    for _, bound in ipairs(EqFeed.STRENGTH_BANDS) do
        if share >= bound - 1e-9 then marks = marks + 1 end
    end
    return string.rep("+", marks)
end


--- A food group's rows in a pen's food list. Feeds with a row name get a row each (feeds sharing
--- a name share it), in feeds.xml order; the rest of the group stays one row, which is left out
--- when the group has rows of its own and nothing else in it is in the trough.
--- @param names table the group's fill type names
--- @param levels table fill type name -> litres in the trough
--- @param config table from EqFeed.read
--- @return table rows list of { row = row name or nil for the rest, names, value }
function EqFeed.splitRows(names, levels, config)
    local inGroup = {}
    for _, name in ipairs(names) do inGroup[name] = true end

    local rows, rowByName = {}, {}
    local rest = { names = {}, value = 0 }
    local placed = {}
    for _, feed in ipairs(config.feeds) do
        if inGroup[feed.fillType] and feed.row ~= nil then
            local row = rowByName[feed.row]
            if row == nil then
                row = { row = feed.row, names = {}, value = 0 }
                rowByName[feed.row] = row
                table.insert(rows, row)
            end
            table.insert(row.names, feed.fillType)
            row.value = row.value + (levels[feed.fillType] or 0)
            placed[feed.fillType] = true
        end
    end
    for _, name in ipairs(names) do
        if not placed[name] then
            table.insert(rest.names, name)
            rest.value = rest.value + (levels[name] or 0)
        end
    end

    if #rest.names > 0 and (#rows == 0 or rest.value > 0) then table.insert(rows, rest) end
    return rows
end


--- The training boost a trough gives.
--- @param levels table fill type name -> litres in the trough
--- @param config table from EqFeed.read
--- @return table boost stat -> share (0.1 = 10% faster training)
function EqFeed.dietBoost(levels, config)
    local boost = {}
    for _, stat in ipairs(EqConstants.STAT_KEYS) do boost[stat] = 0 end
    if config == nil or levels == nil then return boost end

    -- Feeds without a stack name each count on their own; feeds sharing one count as their best.
    local stacks = {}
    for name, level in pairs(levels) do
        local feed = config.feedByFillType[name]
        if feed ~= nil and level > 0 then
            local key = feed.stack or name
            local best = stacks[key]
            if best == nil then
                best = {}
                stacks[key] = best
            end
            for _, stat in ipairs(EqConstants.STAT_KEYS) do
                best[stat] = math.max(best[stat] or 0, feed.boost[stat])
            end
        end
    end

    for _, best in pairs(stacks) do
        for _, stat in ipairs(EqConstants.STAT_KEYS) do boost[stat] = boost[stat] + best[stat] end
    end

    return boost
end

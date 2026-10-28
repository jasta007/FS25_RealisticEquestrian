--[[
    EqSponsors.lua
    Sponsor boards on our bleachers (placeables/bleachers/, art/source/bleachers.py): each board's
    face, a shape named "eqSponsor_<n>", shows a brand logo from the game itself, read at run
    time and never shipped (James, 2026-10-28: the game is full of sponsors, use them).

    A farm's sponsors are the brands of the machines it owns, most first, then the rest of the
    game's brands in an order fixed for the farm. Each bleacher carries on down the list where the
    one before stopped, so neighbouring stands show different logos. Boards are set once, when a
    bleacher is first seen; a board whose logo can't be loaded keeps our own.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsors = {}

local Log = EqLog

-- Bleachers are looked for this often (newly placed ones too).
EqSponsors.SCAN_MS = 2000
EqSponsors.XML = "placeables/bleachers/"
EqSponsors.NODE = "^eqSponsor_(%d+)$"
-- Brands never shown: the game's placeholder.
EqSponsors.SKIP = { NONE = true }

EqSponsors.scannedAt = nil
EqSponsors.failed = false


--- The farm's sponsors, in order. Pure.
--- @param counts table brand name -> machines the farm owns
--- @param names table every brand name the game has
--- @param seed number fixes the order of the brands the farm doesn't own
--- @return table names
function EqSponsors.order(counts, names, seed)
    local owned, rest = {}, {}
    for _, name in ipairs(names) do
        if not EqSponsors.SKIP[name] then
            if (counts[name] or 0) > 0 then table.insert(owned, name) else table.insert(rest, name) end
        end
    end
    table.sort(owned, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return a < b
    end)
    table.sort(rest)
    local rng = EqRandom.new("sponsors " .. tostring(seed))
    for i = #rest, 2, -1 do
        local j = math.floor(rng:next() * i) + 1
        rest[i], rest[j] = rest[j], rest[i]
    end
    for _, name in ipairs(rest) do table.insert(owned, name) end
    return owned
end


--- @param filename string|nil
--- @return boolean true for one of our bleachers
function EqSponsors.isBleacherXml(filename)
    if type(filename) ~= "string" then return false end
    return string.find(string.lower(string.gsub(filename, "\\", "/")), EqSponsors.XML, 1, true) ~= nil
end


--- @return table brand name -> brand, and the names in a list
local function brands()
    local byName, names = {}, {}
    local manager = g_brandManager
    local list = manager ~= nil and (manager.indexToBrand or manager.nameToBrand) or {}
    for _, brand in pairs(list) do
        if type(brand) == "table" and brand.name ~= nil and type(brand.image) == "string" and brand.image ~= "" then
            byName[brand.name] = brand
            table.insert(names, brand.name)
        end
    end
    table.sort(names)
    return byName, names
end


--- @param farmId number
--- @return table brand name -> how many of the farm's machines carry it
local function ownedCounts(farmId)
    local counts = {}
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, vehicle in ipairs(system ~= nil and system.vehicles or {}) do
        if vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farmId and vehicle.configFileName ~= nil then
            local item = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
            local brand = item ~= nil and item.brandIndex ~= nil and g_brandManager:getBrandByIndex(item.brandIndex) or nil
            if brand ~= nil and brand.name ~= nil then counts[brand.name] = (counts[brand.name] or 0) + 1 end
        end
    end
    return counts
end


--- @param node number
--- @param found table board number -> node, filled in
local function findBoards(node, found)
    local count = getNumOfChildren(node)
    for i = 0, count - 1 do
        local child = getChildAt(node, i)
        local number = string.match(getName(child) or "", EqSponsors.NODE)
        if number ~= nil then found[tonumber(number)] = child else findBoards(child, found) end
    end
end


--- Put a brand's logo on a board's face.
--- @param node number the board's logo shape
--- @param brand table
--- @return boolean ok
local function showLogo(node, brand)
    if brand == nil or setMaterialDiffuseMapFromFile == nil or getMaterial == nil or setMaterial == nil then return false end
    local material = getMaterial(node, 0)
    if material == nil or material == 0 then return false end
    local logo = setMaterialDiffuseMapFromFile(material, brand.image, true, true, false)
    if logo == nil or logo == 0 then return false end
    setMaterial(node, logo, 0)
    return true
end


--- Set the boards of every bleacher not done yet.
function EqSponsors.update()
    if EqSponsors.failed then return end
    local now = g_time or 0
    if EqSponsors.scannedAt ~= nil and now - EqSponsors.scannedAt < EqSponsors.SCAN_MS and now >= EqSponsors.scannedAt then return end
    EqSponsors.scannedAt = now
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    local byFarm = {}
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        if EqSponsors.isBleacherXml(placeable.configFileName) and type(placeable.rootNode) == "number" and placeable.rootNode ~= 0 then
            local farmId = placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() or 0
            byFarm[farmId] = byFarm[farmId] or {}
            table.insert(byFarm[farmId], placeable)
        end
    end
    local byName, names = nil, nil
    for farmId, stands in pairs(byFarm) do
        local sponsors = nil
        local offset = 0
        for _, placeable in ipairs(stands) do
            local boards = {}
            findBoards(placeable.rootNode, boards)
            if not placeable.eqSponsored then
                placeable.eqSponsored = true
                if byName == nil then byName, names = brands() end
                sponsors = sponsors or EqSponsors.order(ownedCounts(farmId), names, farmId)
                local shown = 0
                for number, node in pairs(boards) do
                    local name = #sponsors > 0 and sponsors[(offset + number - 1) % #sponsors + 1] or nil
                    local ok, done = EqLog.try("EqSponsors logo", showLogo, node, name ~= nil and byName[name] or nil)
                    if ok and done then shown = shown + 1 end
                end
                if shown == 0 and next(boards) ~= nil and #sponsors > 0 then
                    EqSponsors.failed = true
                    Log:warning("EqSponsors: no logo could be put on a bleacher's boards; they keep our own")
                    return
                end
                Log:info("EqSponsors: farm %d's bleacher shows %d sponsor(s)", farmId, shown)
            end
            offset = offset + #boards
        end
    end
end


--- @param guarded function main.lua's error guard
function EqSponsors.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("sponsor boards", EqSponsors.update)
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        EqSponsors.scannedAt, EqSponsors.failed = nil, false
    end)
end

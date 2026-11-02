--[[
    EqSponsors.lua
    Sponsor boards on our bleachers (placeables/bleachers/, art/source/bleachers.py) and on the
    cross country table's front (James, 2026-10-29): each board's
    face, a shape named "eqSponsor_<n>", shows a brand logo from the game itself, read at run
    time and never shipped (James, 2026-10-28: the game is full of sponsors, use them).

    A farm's sponsors are the brands of the machines it owns, most first, then the rest of the
    game's brands in an order fixed for the farm. A farm with a sponsor (EqSponsorManager) shows
    that sponsor on every board, and its boards count towards the sponsor's fee. Each bleacher carries on down the list where the
    one before stopped, so neighbouring stands show different logos. Boards are set once, when a
    bleacher is first seen; a board whose logo can't be loaded keeps our own.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsors = {}

local Log = EqLog

-- Bleachers are looked for this often (newly placed ones too).
EqSponsors.SCAN_MS = 2000
-- Our placeables with sponsor boards: the bleachers and the cross country table's front board.
EqSponsors.XMLS = { "placeables/bleachers/", "placeables/xcjumps/xctable", "placeables/xcjumps/xccornerplank",
    "placeables/xcjumps/xcdropwall16", "placeables/showjumps/", "placeables/xcjumps/xcgate", "placeables/xcjumps/xcrope",
    "placeables/sponsorplinths/" }
-- The rope fence's hanging signs are a TINY bit of branding, so ropes can't be strung everywhere for
-- it (James, 2026-10-31): each sign counts a tenth of a board, all ropes together one board at most.
EqSponsors.ROPE = "placeables/xcjumps/xcrope"
EqSponsors.ROPE_SIGN = 0.1
EqSponsors.ROPE_CAP = 1
-- A board's face; "eqSponsor_<n>b" is the same board's back (show jump boards seen both ways) and
-- "eqSponsor_<n>f<k>" a piece of it (the wall's logo, cut along its falling blocks).
EqSponsors.NODE = "^eqSponsor_(%d+)b?f?%d*$"
-- Boards under this group count only when the jump's Sponsor boards choice is bought (EqSponsorBoards).
EqSponsors.OPTIONAL = "eqSponsorOn"
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
--- @return boolean true for one of our bleachers (or another piece with sponsor boards)
function EqSponsors.isBleacherXml(filename)
    if type(filename) ~= "string" then return false end
    local path = string.lower(string.gsub(filename, "\\", "/"))
    for _, prefix in ipairs(EqSponsors.XMLS) do
        if string.find(path, prefix, 1, true) ~= nil then return true end
    end
    return false
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
--- @param found table board number -> its face nodes (front, and back if it has one), filled in
--- @param optional boolean|nil true to count the boards bought as a jump's Sponsor boards choice
local function findBoards(node, found, optional)
    local count = getNumOfChildren(node)
    for i = 0, count - 1 do
        local child = getChildAt(node, i)
        local name = getName(child) or ""
        local number = string.match(name, EqSponsors.NODE)
        if number ~= nil then
            number = tonumber(number)
            found[number] = found[number] or {}
            table.insert(found[number], child)
        elseif name ~= EqSponsors.OPTIONAL or optional then
            findBoards(child, found, optional)
        end
    end
end


--- @param placeable table
--- @return table board number -> face nodes: the placeable's boards that are there
local function boardsOf(placeable)
    local boards = {}
    findBoards(placeable.rootNode, boards, EqSponsorBoards ~= nil and EqSponsorBoards.isOn(placeable))
    return boards
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


--- Every board is set again on the next scan: a farm's sponsor has changed.
function EqSponsors.refresh()
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do placeable.eqSponsored = nil end
    EqSponsors.scannedAt = nil
    EqSponsors.failed = false
end


--- @param filename string|nil
--- @return boolean true for the rope fence, whose signs count a little
function EqSponsors.isRope(filename)
    if type(filename) ~= "string" then return false end
    return string.find(string.lower(string.gsub(filename, "\\", "/")), EqSponsors.ROPE, 1, true) ~= nil
end


--- The farm a sponsor piece belongs to. A Rope Marker is a fence, and the game doesn't give a
--- fence the farm that drew it (James 2026-11-02: the rope's sign showed a brand that wasn't
--- his sponsor, and spectators found no rope "of his"): a rope with no real farm is the local
--- player's.
--- @param placeable table
--- @return number|nil farmId
function EqSponsors.ownerOf(placeable)
    local owner = placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() or nil
    if EqSponsors.isRope(placeable.configFileName) then
        local spectator = FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID or 15
        if owner == nil or owner == 0 or owner == spectator then
            local mission = g_currentMission
            local mine = mission ~= nil and mission.getFarmId ~= nil and mission:getFarmId() or nil
            if not EqSponsors.loggedRopeOwner then
                EqSponsors.loggedRopeOwner = true
                Log:info("EqSponsors: Rope Marker owner farm %s, counted as farm %s", tostring(owner), tostring(mine))
            end
            if mine ~= nil and mine ~= 0 and mine ~= spectator then return mine end
        end
    end
    return owner
end


--- @param boards table board number -> face nodes
--- @return number signs the front faces (a rope's signs all share one number)
local function frontFaces(boards)
    local count = 0
    for _, nodes in pairs(boards) do
        for _, node in ipairs(nodes) do
            local name = getName(node) or ""
            if string.sub(name, -1) ~= "b" then count = count + 1 end
        end
    end
    return count
end


--- @param boards number whole boards
--- @param signs number rope signs
--- @return number the branding they make together
function EqSponsors.total(boards, signs)
    return boards + math.min(EqSponsors.ROPE_CAP, signs * EqSponsors.ROPE_SIGN)
end


--- @param farmId number
--- @return table brands the farm's signed sponsors, the lead first (empty for none): one contract
--- per farm now, a list of them once several sponsors at once (PR #137) are in
function EqSponsors.signedBrands(farmId)
    local list = EqSponsors.contractBrands(farmId)
    -- Lizard's one-off deal (EqLizard) counts its machines on plinths too, while it lasts
    if EqLizard ~= nil and EqLizard.active(farmId) then
        local copy = {}
        for _, brand in ipairs(list) do
            if brand ~= EqLizard.BRAND then table.insert(copy, brand) end
        end
        table.insert(copy, EqLizard.BRAND)
        return copy
    end
    return list
end


--- @param farmId number
--- @return table brands the farm's yearly sponsors' brands, the lead first
function EqSponsors.contractBrands(farmId)
    if EqSponsorManager == nil then return {} end
    if EqSponsorManager.sponsorBrands ~= nil then return EqSponsorManager.sponsorBrands(farmId) or {} end
    local contracts = EqSponsorManager.contracts ~= nil and EqSponsorManager.contracts[farmId] or nil
    if type(contracts) ~= "table" then return {} end
    if contracts.brand ~= nil then return { contracts.brand } end
    local list = {}
    for _, contract in ipairs(contracts) do
        if type(contract) == "table" and contract.brand ~= nil then table.insert(list, contract.brand) end
    end
    return list
end


--- @param farmId number
--- @return number boards sponsor boards on the farm's placeables, anywhere on the map (rope
--- signs as a fraction)
function EqSponsors.countBoards(farmId)
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    local count, signs = 0, 0
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local owner = EqSponsors.ownerOf(placeable)
        if owner == farmId and EqSponsors.isBleacherXml(placeable.configFileName) and type(placeable.rootNode) == "number" and placeable.rootNode ~= 0 then
            local boards = boardsOf(placeable)
            if EqSponsors.isRope(placeable.configFileName) then
                signs = signs + frontFaces(boards)
            else
                for _ in pairs(boards) do count = count + 1 end
            end
        end
    end
    -- and the sponsors' machines parked on the farm's plinths (EqPlinths)
    local machines = EqPlinths ~= nil and (EqPlinths.count(farmId, EqSponsors.signedBrands(farmId))) or 0
    return EqSponsors.total(count, signs) + machines
end


--- @param farmId number
--- @return table brands the farm's sponsors, the lead first (empty for none)
local function sponsorsOf(farmId)
    local brands = (EqSponsorManager ~= nil and EqSponsorManager.sponsorBrands ~= nil) and EqSponsorManager.sponsorBrands(farmId) or {}
    -- no yearly sponsor: Lizard's one-off deal shows on the boards while it lasts
    if #brands == 0 and EqLizard ~= nil and EqLizard.active(farmId) then return { EqLizard.BRAND } end
    return brands
end


--- The one brand a piece shows (James, 2026-11-01): a sponsor whose machine is parked on it, else
--- the brand it shows already while that's still on the list (a new sponsor doesn't take over the
--- pieces), else the list in turn by the piece's place among the farm's.
--- @param sponsors table brands, in order
--- @param offset number the piece's place among the farm's pieces with boards
--- @param parked string|nil brand of a machine parked on it (plinths)
--- @param current string|nil brand it shows now
--- @return string|nil
function EqSponsors.pickBrand(sponsors, offset, parked, current)
    if #sponsors == 0 then return nil end
    local listed = {}
    for _, name in ipairs(sponsors) do listed[name] = true end
    if parked ~= nil and listed[parked] then return parked end
    if current ~= nil and listed[current] then return current end
    return sponsors[offset % #sponsors + 1]
end


--- Set the boards of every bleacher not done yet.
function EqSponsors.update()
    if EqSponsors.failed then return end
    local now = g_time or 0
    if EqSponsors.scannedAt ~= nil and now - EqSponsors.scannedAt < EqSponsors.SCAN_MS and now >= EqSponsors.scannedAt then return end
    EqSponsors.scannedAt = now
    EqLog.try("EqSponsors shop text", EqSponsors.updateShopText)
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    local byFarm = {}
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        if EqSponsors.isBleacherXml(placeable.configFileName) and type(placeable.rootNode) == "number" and placeable.rootNode ~= 0 then
            local farmId = EqSponsors.ownerOf(placeable) or 0
            byFarm[farmId] = byFarm[farmId] or {}
            table.insert(byFarm[farmId], placeable)
        end
    end
    local byName, names = nil, nil
    for farmId, stands in pairs(byFarm) do
        local sponsors = nil
        local offset = 0
        for _, placeable in ipairs(stands) do
            local boards = boardsOf(placeable)
            if EqSponsors.isRope(placeable.configFileName) then
                -- a rope grows and loses segments: sign the new ones
                local faces = 0
                for _, nodes in pairs(boards) do faces = faces + #nodes end
                if placeable.eqRopeFaces ~= faces then placeable.eqSponsored, placeable.eqRopeFaces = nil, faces end
            end
            if EqPlinths ~= nil and EqPlinths.areasFor(placeable.configFileName) ~= nil then
                -- a plinth shows the brand parked on it: look again when that changes
                local ok, parked = EqLog.try("EqSponsors parked brand", EqPlinths.parkedBrand, placeable)
                parked = ok and parked or nil
                if parked ~= placeable.eqParked then placeable.eqParked, placeable.eqSponsored = parked, nil end
            end
            if not placeable.eqSponsored and next(boards) ~= nil then
                placeable.eqSponsored = true
                if byName == nil then byName, names = brands() end
                -- The farm's sponsors take turns on the boards; with none, the brands it owns most.
                local signed = {}
                for _, brand in ipairs(sponsorsOf(farmId)) do
                    if byName[brand] ~= nil then table.insert(signed, brand) end
                end
                if #signed > 0 then
                    sponsors = signed
                else
                    sponsors = sponsors or EqSponsors.order(ownedCounts(farmId), names, farmId)
                end
                local shown = 0
                -- one brand per piece (James, 2026-11-01: never two sponsors' logos or colours on
                -- one object); the farm's pieces take turns down the list
                local name = EqSponsors.pickBrand(sponsors, offset, placeable.eqParked, placeable.eqBrand)
                -- the Lizard plinth always shows Lizard's logo
                if EqLizard ~= nil and EqLizard.isPlinthXml(placeable.configFileName) and byName[EqLizard.BRAND] ~= nil then
                    name = EqLizard.BRAND
                end
                if placeable.eqBrand ~= name then
                    placeable.eqBrand = name
                    placeable.eqColourKey = nil    -- EqJumpColours paints it again in that brand's colour
                end
                if EqJumpColours ~= nil and EqJumpColours.paintFaces ~= nil then
                    EqLog.try("EqSponsors board faces", EqJumpColours.paintFaces, placeable)
                end
                for _, nodes in pairs(boards) do
                    local any = false
                    for _, node in ipairs(nodes) do
                        local ok, done = EqLog.try("EqSponsors logo", showLogo, node, name ~= nil and byName[name] or nil)
                        if ok and done then any = true end
                    end
                    if any then shown = shown + 1 end
                end
                if shown == 0 and next(boards) ~= nil and #sponsors > 0 then
                    EqSponsors.failed = true
                    Log:warning("EqSponsors: no logo could be put on a bleacher's boards; they keep our own")
                    return
                end
                Log:info("EqSponsors: farm %d's bleacher shows %d sponsor(s)", farmId, shown)
            end
            if next(boards) ~= nil then offset = offset + 1 end
        end
    end
end


-- Sponsor boards on each of our shop items (matched by the end of the xml path), for the shop
-- line that shows the farm's branding now and with one more (James, 2026-10-31).
EqSponsors.SHOP_BOARDS = {
    ["placeables/bleachers/bleachers3x6.xml"] = 3,
    ["placeables/bleachers/bleachers5x10.xml"] = 5,
    ["placeables/bleachers/bleachers8x16.xml"] = 8,
    ["placeables/xcjumps/xctable.xml"] = 1,
    ["placeables/xcjumps/xccornerplank.xml"] = 2,
    ["placeables/xcjumps/xcdropwall16.xml"] = 1,
    ["placeables/showjumps/showjumpwall.xml"] = 2,
    ["placeables/xcjumps/xcgatearch.xml"] = 3,
    ["placeables/xcjumps/xcgatesimple.xml"] = 1,
    ["placeables/sponsorplinths/plinthdrive.xml"] = 1,
    ["placeables/sponsorplinths/plinthramp.xml"] = 1,
    ["placeables/sponsorplinths/plinthramplarge.xml"] = 1,
    ["placeables/sponsorplinths/plinthproductramp.xml"] = 1,
    ["placeables/sponsorplinths/plinthturntable.xml"] = 1,
    ["placeables/sponsorplinths/lizardplinthstone.xml"] = 1,
    ["placeables/sponsorplinths/lizardplinthwoodchips.xml"] = 1,
    ["placeables/sponsorplinths/lizardplinthstraw.xml"] = 1,
}
-- Boards that come with a show jump's Sponsor boards choice (EqSponsorBoards): the shop line says
-- what they would add, after the jump's own lines.
EqSponsors.SHOP_OPTION_BOARDS = {
    ["placeables/showjumps/showjumpupright.xml"] = 2,
    ["placeables/showjumps/showjumpoxer.xml"] = 2,
    ["placeables/showjumps/showjumptriplebar.xml"] = 2,
    ["placeables/showjumps/showjumphogsback.xml"] = 2,
    ["placeables/showjumps/showjumpfan3.xml"] = 2,
    ["placeables/showjumps/showjumpliverpool.xml"] = 3,
}
EqSponsors.shopItems = nil
EqSponsors.shopText = nil


--- @param filename string|nil
--- @return number boards an item of ours carries, 0 for any other
function EqSponsors.shopBoards(filename)
    if type(filename) ~= "string" then return 0 end
    local path = string.lower(string.gsub(filename, "\\", "/"))
    for suffix, boards in pairs(EqSponsors.SHOP_BOARDS) do
        if string.sub(path, -#suffix) == suffix then return boards end
    end
    for suffix, boards in pairs(EqSponsors.SHOP_OPTION_BOARDS) do
        if string.sub(path, -#suffix) == suffix then return boards, true end
    end
    return 0
end


--- Keep the shop's function line on our boarded items up to date: the farm's branding now and
--- with that item bought. Cheap; runs with the board scan.
function EqSponsors.updateShopText()
    if g_storeManager == nil or g_currentMission == nil or EqSponsorManager == nil or EqSponsorManager.config == nil then return end
    if EqSponsors.shopItems == nil then
        EqSponsors.shopItems = {}
        for _, storeItem in ipairs(g_storeManager:getItems() or {}) do
            local boards, optional = EqSponsors.shopBoards(storeItem.xmlFilename)
            if boards > 0 then
                local base = {}
                for _, line in ipairs(storeItem.functions or {}) do table.insert(base, line) end
                -- plinths keep their own lines (what to park on them) above the branding line
                local keep = optional or (EqPlinths ~= nil and EqPlinths.areasFor(storeItem.xmlFilename) ~= nil)
                table.insert(EqSponsors.shopItems, { item = storeItem, boards = boards, optional = optional, keep = keep, base = base })
            end
        end
    end
    local farmId = g_currentMission:getFarmId()
    local have = EqSponsors.countBoards(farmId)
    local config = EqSponsorManager.config
    for _, entry in ipairs(EqSponsors.shopItems) do
        local now = EqSponsorView.brandingWord(EqSponsorship.brandingLevel(config, have))
        local with = EqSponsorView.brandingWord(EqSponsorship.brandingLevel(config, have + entry.boards))
        local text = string.format(g_i18n:getText(entry.optional and "eq_shop_brandingOption" or "eq_shop_branding"), now, with)
        if entry.text ~= text then
            entry.text = text
            if entry.keep then
                local lines = {}
                for _, line in ipairs(entry.base) do table.insert(lines, line) end
                table.insert(lines, text)
                entry.item.functions = lines
            else
                entry.item.functions = { text }
            end
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
        EqSponsors.scannedAt, EqSponsors.failed, EqSponsors.shopItems = nil, false, nil
    end)
end

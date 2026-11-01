--[[
    EqLizard.lua
    Lizard's free one-off sponsorship (James, 2026-10-29 and 2026-11-01). Lizard, the game's own
    brand, is never one of the yearly sponsors (data/sponsors.xml skipBrands). Instead:

    - A hosted event no sponsor backs has a CHANCE (25%) of a Lizard offer, rolled once, the month
      before the event (or when it is booked, if that is for next month).
    - A popup offers the deal: the branding level Lizard wants by the end of the event, and its
      special Lizard plinth built at the venue. The plinth is a constructible bought in the shop
      for next to nothing and built from what the farm delivers: planks, logs and one bulk
      material Lizard picks (stone, wood chips or straw, data/sponsors.xml). Accept or decline.
    - Accepted: the event carries Lizard's name and popularity, Lizard shows on the farm's boards
      and its machines on plinths count, and Lizard lends a vehicle for the event month (the
      sponsor vehicle loans, another thread: they read EqLizard.isLizardEvent).
    - When the results come in, Lizard pays its fee if the plinth is built and the branding is
      there. Otherwise nothing, and no penalty (James: "no penalty if you accept but don't
      achieve it"). Either way the plinth then collapses and is gone.

    Pure parts (read, roll, pay) are tested in tests/run.lua.

    Part of Realistic Equestrian by Jasta007.
]]

EqLizard = {}

local Log = EqLog

EqLizard.BRAND = "LIZARD"
-- The plinths, one per bulk material (art/source/lizard_plinth.py), matched by the end of the path.
EqLizard.XML_PREFIX = "placeables/sponsorplinths/lizardplinth"
EqLizard.CHECK_MS = 1000
EqLizard.COLLAPSE_MS = 3500

EqLizard.config = nil


function EqLizard.reset()
    EqLizard.deals = {}         -- farmId -> { month, type, rating, material, state, eventId }
    EqLizard.collapsing = {}    -- list of { placeable, started }
    EqLizard.asked = {}         -- farmId -> month already asked this session
end

EqLizard.reset()


-- CONFIG

--- @param xmlFile table data/sponsors.xml
--- @return table config { chance, popularity, ratings = name -> { fee, branding }, materials = list }
function EqLizard.read(xmlFile)
    local key = "sponsors.lizard"
    local config = { chance = xmlFile:getFloat(key .. "#chance", 0.25), popularity = xmlFile:getInt(key .. "#popularity", 5),
        ratings = {}, materials = {} }
    local i = 0
    while xmlFile:hasProperty(string.format("%s.rating(%d)", key, i)) do
        local ratingKey = string.format("%s.rating(%d)", key, i)
        local name = xmlFile:getString(ratingKey .. "#name")
        if name ~= nil then
            config.ratings[name] = { fee = xmlFile:getFloat(ratingKey .. "#fee", 0), branding = xmlFile:getInt(ratingKey .. "#branding", 1) }
        end
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("%s.material(%d)", key, i)) do
        local materialKey = string.format("%s.material(%d)", key, i)
        local fillType = xmlFile:getString(materialKey .. "#fillType")
        local xml = xmlFile:getString(materialKey .. "#xml")
        if fillType ~= nil and xml ~= nil then
            table.insert(config.materials, { fillType = fillType, xml = xml, amount = xmlFile:getFloat(materialKey .. "#amount", 0),
                weight = xmlFile:getFloat(materialKey .. "#weight", 1) })
        end
        i = i + 1
    end
    i = 0
    config.parts = {}
    while xmlFile:hasProperty(string.format("%s.part(%d)", key, i)) do
        local partKey = string.format("%s.part(%d)", key, i)
        table.insert(config.parts, { fillType = xmlFile:getString(partKey .. "#fillType"), amount = xmlFile:getFloat(partKey .. "#amount", 0) })
        i = i + 1
    end
    return config
end


--- @param modDirectory string
function EqLizard.loadConfig(modDirectory)
    local xmlFile = XMLFile.load("eqLizard", modDirectory .. "data/sponsors.xml")
    if xmlFile == nil then return end
    EqLizard.config = EqLizard.read(xmlFile)
    xmlFile:delete()
    Log:info("EqLizard: chance %.2f, %d materials", EqLizard.config.chance, #EqLizard.config.materials)
end


-- PURE RULES

--- Does Lizard make an offer? Pure.
--- @param config table
--- @param roll number 0..1, the chance roll
--- @param pick number 0..1, which material
--- @return table|nil material the bulk material it asks for, nil for no offer
function EqLizard.roll(config, roll, pick)
    if config == nil or #config.materials == 0 or roll >= config.chance then return nil end
    local total = 0
    for _, material in ipairs(config.materials) do total = total + material.weight end
    local at = pick * total
    for _, material in ipairs(config.materials) do
        at = at - material.weight
        if at < 0 then return material end
    end
    return config.materials[#config.materials]
end


--- What Lizard pays when the results come in. Pure.
--- @param config table
--- @param rating string
--- @param built boolean the farm's Lizard plinth is finished
--- @param level number the farm's branding level now
--- @return number fee
--- @return string|nil why nothing: "plinth" or "branding"
function EqLizard.payFor(config, rating, built, level)
    local terms = config ~= nil and config.ratings[rating] or nil
    if terms == nil then return 0, "rating" end
    if not built then return 0, "plinth" end
    if (level or 0) < terms.branding then return 0, "branding" end
    return terms.fee, nil
end


--- @param config table
--- @param fillType string
--- @return table|nil material
function EqLizard.material(config, fillType)
    for _, material in ipairs(config ~= nil and config.materials or {}) do
        if material.fillType == fillType then return material end
    end
    return nil
end


-- THE GAME

--- @param farmId number
--- @param kind string EqMessages type
--- @param text string
--- @param level number|nil
local function tell(farmId, kind, text, level)
    if g_currentMission ~= nil and g_currentMission:getFarmId() == farmId then
        g_currentMission:addIngameNotification(level or FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
    EqMessages.post(farmId, kind, text)
end


--- @param amount number
--- @return string
local function money(amount)
    return g_i18n:formatMoney(amount or 0, 0, true, true)
end


--- @return string Lizard as the shop shows it
function EqLizard.title()
    return EqSponsorManager ~= nil and EqSponsorManager.brandTitle(EqLizard.BRAND) or "Lizard"
end


--- @param farmId number
--- @param rating string
--- @return boolean true when one of the farm's sponsors backs this rating
local function sponsored(farmId, rating)
    return EqSponsorManager ~= nil and EqSponsorManager.popularityFor ~= nil and EqSponsorManager.popularityFor(farmId, rating) > 0
end


--- @param farmId number
--- @return boolean true while the farm has an accepted Lizard deal not yet settled
function EqLizard.active(farmId)
    local deal = EqLizard.deals[farmId]
    return deal ~= nil and deal.state == "accepted"
end


--- @param event table
--- @return boolean true for a hosted event Lizard sponsors (for the sponsor vehicle loans too)
function EqLizard.isLizardEvent(event)
    if event == nil or event.hosted == nil then return false end
    local deal = EqLizard.deals[event.hosted.farmId]
    return deal ~= nil and deal.state == "accepted" and deal.eventId ~= nil and deal.eventId == event.id
end


--- Roll for an offer on a booking, once.
--- @param farmId number
--- @param booking table EqHostManager booking { type, rating, month }
function EqLizard.consider(farmId, booking)
    local config = EqLizard.config
    if config == nil or booking == nil then return end
    local deal = EqLizard.deals[farmId]
    -- (with eqLizard's 100% switched on, a booking that rolled no offer rolls again)
    if deal ~= nil and deal.month == booking.month and not (EqLizard.testAlways and deal.state == "none") then return end
    if sponsored(farmId, booking.rating) then
        EqLizard.deals[farmId] = { month = booking.month, type = booking.type, rating = booking.rating, state = "none" }
        return
    end
    local material = EqLizard.roll(config, EqLizard.testAlways and 0 or math.random(), math.random())
    if material == nil then
        EqLizard.deals[farmId] = { month = booking.month, type = booking.type, rating = booking.rating, state = "none" }
        Log:info("EqLizard: no Lizard offer for farm %d's %s %s", farmId, booking.rating, booking.type)
        return
    end
    EqLizard.deals[farmId] = { month = booking.month, type = booking.type, rating = booking.rating, material = material.fillType,
        state = "offered" }
    Log:info("EqLizard: Lizard offers to sponsor farm %d's %s %s (%s)", farmId, booking.rating, booking.type, material.fillType)
    EqMessages.post(farmId, "EQ_SPONSOR_OFFERS", string.format(g_i18n:getText("eq_lizard_offerNote"), EqLizard.title(),
        EqHostManager.title(booking.type, booking.rating)))
end


--- A booking made (or still waiting) for next month gets its roll.
--- @param month number the month now
function EqLizard.considerAll(month)
    local farmIds = {}
    for farmId, booking in pairs(EqHostManager.bookings or {}) do
        if booking.month == month + 1 then table.insert(farmIds, farmId) end
    end
    table.sort(farmIds)
    for _, farmId in ipairs(farmIds) do EqLizard.consider(farmId, EqHostManager.bookings[farmId]) end
end


--- @param fillType string
--- @return string its name in the game
local function fillTypeTitle(fillType)
    local manager = g_fillTypeManager
    local entry = manager ~= nil and manager.getFillTypeByName ~= nil and manager:getFillTypeByName(fillType) or nil
    return entry ~= nil and entry.title or fillType
end


--- @param config table
--- @param deal table
--- @return string what the plinth is built from, such as "1,000 l Planks, 2,000 l Wood, 1,000 l Stones"
function EqLizard.needsText(config, deal)
    local parts = {}
    local function add(fillType, amount)
        table.insert(parts, string.format("%s %s", g_i18n:formatVolume(amount, 0), fillTypeTitle(fillType)))
    end
    local material = EqLizard.material(config, deal.material)
    if material ~= nil then add(material.fillType, material.amount) end
    for _, part in ipairs(config.parts or {}) do
        if part.fillType ~= nil then add(part.fillType, part.amount) end
    end
    return table.concat(parts, ", ")
end


--- The offer's popup text.
--- @param farmId number
--- @param deal table
--- @return string
function EqLizard.offerText(farmId, deal)
    local config = EqLizard.config
    local terms = config.ratings[deal.rating] or { fee = 0, branding = 1 }
    return string.format(g_i18n:getText("eq_lizard_offer"), EqLizard.title(), EqHostManager.title(deal.type, deal.rating),
        EqHostManager.monthText(deal.month), EqSponsorView.brandingWord(terms.branding), EqLizard.needsText(config, deal),
        money(terms.fee))
end


--- The player's answer.
--- @param farmId number
--- @param yes boolean
function EqLizard.answer(farmId, yes)
    local deal = EqLizard.deals[farmId]
    if deal == nil or deal.state ~= "offered" then return end
    deal.state = yes and "accepted" or "declined"
    Log:info("EqLizard: farm %d %s Lizard's offer", farmId, deal.state)
    if yes then
        tell(farmId, "EQ_SPONSOR_SIGNED", string.format(g_i18n:getText("eq_lizard_accepted"), EqLizard.title(), fillTypeTitle(deal.material)))
        if EqSponsors ~= nil and EqSponsors.refresh ~= nil then EqSponsors.refresh() end
    end
    EqLizard.updateShop()
end


-- THE SHOP

--- @param filename string|nil
--- @return boolean true for one of the Lizard plinths
function EqLizard.isPlinthXml(filename)
    if type(filename) ~= "string" then return false end
    local path = string.lower(string.gsub(filename, "\\", "/"))
    return string.find(path, EqLizard.XML_PREFIX, 1, true) ~= nil
end


--- Only the Lizard plinth a farm's accepted deal asks for is in the shop, and only while the deal lasts.
function EqLizard.updateShop()
    if g_storeManager == nil or g_currentMission == nil or EqLizard.config == nil then return end
    local deal = EqLizard.deals[g_currentMission:getFarmId()]
    local want = nil
    if deal ~= nil and deal.state == "accepted" then
        local material = EqLizard.material(EqLizard.config, deal.material)
        want = material ~= nil and string.lower(material.xml) or nil
    end
    for _, storeItem in ipairs(g_storeManager:getItems() or {}) do
        if EqLizard.isPlinthXml(storeItem.xmlFilename) then
            local path = string.lower(string.gsub(storeItem.xmlFilename, "\\", "/"))
            local show = want ~= nil and string.sub(path, -#want) == want
            storeItem.showInStore = show
            -- The game gives a placeable its construction brush only when it loads shown in the
            -- shop (StoreManager.loadItem), so ours, hidden at load, have none and never show in the
            -- construction menu (James, 2026-11-01): give it one while it is offered, take it away after.
            if show and storeItem.brush == nil then
                storeItem.brush = EqLizard.brushFor()
            elseif not show then
                storeItem.brush = nil
            end
        end
    end
end


--- @return table|nil brush the construction brush our plinths would have had: Buildings,
---     Constructibles tab, like the game's rental houses (James, 2026-11-01)
function EqLizard.brushFor()
    if g_storeManager.getConstructionCategoryByName == nil then return nil end
    local category = g_storeManager:getConstructionCategoryByName("buildings")
    local tab = category ~= nil and g_storeManager:getConstructionTabByName("constructibles", category.name) or nil
    if tab == nil then
        -- a map without that tab: the Horses tab, with our other horse pieces
        category = g_storeManager:getConstructionCategoryByName("animals")
        tab = category ~= nil and g_storeManager:getConstructionTabByName("horses", category.name) or nil
    end
    if tab == nil then
        Log:warning("EqLizard: no Constructibles or Horses tab in the construction menu for the Lizard plinth")
        return nil
    end
    return { type = "placeable", parameters = {}, category = category, tab = tab }
end


-- THE PLINTH

--- @param placeable table
--- @return boolean true once its construction is finished
function EqLizard.isBuilt(placeable)
    local spec = placeable ~= nil and placeable.spec_constructible or nil
    if spec == nil then return true end
    local index = spec.stateIndex
    if placeable.getConstructibleStateIndex ~= nil then
        local ok, value = pcall(placeable.getConstructibleStateIndex, placeable)
        if ok and value ~= nil then index = value end
    end
    local names = spec.stateNameToIndex or {}
    local finish = names.FINALIZE or names.DONE
    if index == nil or finish == nil then return false end
    if index >= finish then return true end
    -- James (2026-11-01): everything delivered but still being built counts as built
    local ok, ready = pcall(EqLizard.materialsReady, spec, index, finish)
    return ok and ready == true
end


--- Is everything still to be built already in the plinth's storage? Building states use their
--- inputs' remainingAmount from the storage (FS25 ConstructibleStateBuilding).
--- @param spec table spec_constructible
--- @param index number the state now
--- @param finish number the first finished state
--- @return boolean
function EqLizard.materialsReady(spec, index, finish)
    if spec.storage == nil or spec.stateMachine == nil then return false end
    local need = {}
    for i = math.max(index, 1), finish - 1 do
        local state = spec.stateMachine[i]
        for _, input in ipairs(state ~= nil and state.inputs or {}) do
            local fillType = type(input.fillType) == "table" and input.fillType.index or input.fillType or input.fillTypeIndex
            local amount = input.remainingAmount or input.amount or 0
            if fillType ~= nil and amount > 0 then need[fillType] = (need[fillType] or 0) + amount end
        end
    end
    for fillType, amount in pairs(need) do
        if (spec.storage:getFillLevel(fillType) or 0) < amount - 1 then return false end
    end
    return true
end


--- @param farmId number
--- @return table placeables the farm's Lizard plinths
function EqLizard.plinths(farmId)
    local list = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local owner = placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() or nil
        if owner == farmId and EqLizard.isPlinthXml(placeable.configFileName) then table.insert(list, placeable) end
    end
    return list
end


--- @param farmId number
--- @return boolean true when the farm has a finished Lizard plinth
function EqLizard.hasBuilt(farmId)
    for _, placeable in ipairs(EqLizard.plinths(farmId)) do
        if EqLizard.isBuilt(placeable) then return true end
    end
    return false
end


--- @param node number
--- @param name string
--- @return number|nil the first node below with that name
local function findNode(node, name)
    for i = 0, getNumOfChildren(node) - 1 do
        local child = getChildAt(node, i)
        if getName(child) == name then return child end
        local found = findNode(child, name)
        if found ~= nil then return found end
    end
    return nil
end


--- The fill type a Lizard plinth's mound is made of, from its xml ("lizardPlinthStone.xml" -> STONE).
--- @param filename string|nil
--- @return string|nil
function EqLizard.moundFillType(filename)
    if not EqLizard.isPlinthXml(filename) then return nil end
    local path = string.lower(string.gsub(filename, "\\", "/"))
    for _, material in ipairs(EqLizard.config ~= nil and EqLizard.config.materials or {}) do
        local xml = string.lower(string.gsub(material.xml or "", "\\", "/"))
        if xml ~= "" and string.sub(path, -#xml) == xml then return material.fillType end
    end
    return nil
end


--- Give a plinth's mound the game's own heap material (the fill plane shader with its texture arrays:
--- world projected, height map depth, the fill type's own smoothness), as a real heap of that
--- material looks. The i3d's plain stone/chips/straw texture stays if the game has no such material.
--- @param placeable table
function EqLizard.dressMound(placeable)
    placeable.eqMoundDressed = true
    local fillTypeName = EqLizard.moundFillType(placeable.configFileName)
    local node = placeable.rootNode ~= nil and findNode(placeable.rootNode, "moundSurface") or nil
    if fillTypeName == nil or node == nil or g_materialManager == nil or g_fillTypeManager == nil then return end
    local material = g_materialManager.getBaseMaterialByName ~= nil and g_materialManager:getBaseMaterialByName("fillPlane") or nil
    local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
    local arrayIndex = fillTypeIndex ~= nil and g_fillTypeManager.getTextureArrayIndexByFillTypeIndex ~= nil
        and g_fillTypeManager:getTextureArrayIndexByFillTypeIndex(fillTypeIndex) or nil
    if material == nil or arrayIndex == nil or g_terrainNode == nil or g_fillTypeManager.assignFillTypeTextureArraysFromTerrain == nil then return end
    setMaterial(node, material, 0)
    g_fillTypeManager:assignFillTypeTextureArraysFromTerrain(node, g_terrainNode, true, true, true)
    setShaderParameter(node, "fillTypeId", arrayIndex - 1, 0, 0, 0, false)
end


--- Dress any Lizard plinth that isn't yet (new ones, and ones loaded with the savegame).
function EqLizard.dressMounds()
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        if not placeable.eqMoundDressed and placeable.rootNode ~= nil and EqLizard.isPlinthXml(placeable.configFileName) then
            EqLog.try("EqLizard mound", EqLizard.dressMound, placeable)
        end
    end
end


--- Start the farm's Lizard plinths collapsing: the lizard tips over, the lot sinks, then it's gone.
--- @param farmId number
function EqLizard.collapse(farmId)
    for _, placeable in ipairs(EqLizard.plinths(farmId)) do
        if not placeable.eqCollapsing then
            placeable.eqCollapsing = true
            local root = placeable.rootNode
            local entry = { placeable = placeable, started = g_time or 0 }
            if type(root) == "number" and root ~= 0 then
                entry.lizard = findNode(root, "lizard")
                entry.y = select(2, getTranslation(root))
            end
            table.insert(EqLizard.collapsing, entry)
        end
    end
end


--- @param entry table
--- @return boolean true when the collapse is over
local function collapseStep(entry)
    local placeable = entry.placeable
    local t = ((g_time or 0) - entry.started) / EqLizard.COLLAPSE_MS
    local root = placeable.rootNode
    if t < 1 and type(root) == "number" and root ~= 0 and entry.y ~= nil then
        if entry.lizard ~= nil then setRotation(entry.lizard, math.min(1, t * 2) ^ 2 * math.rad(80), 0, 0) end
        local x, _, z = getTranslation(root)
        setTranslation(root, x, entry.y - math.max(0, t - 0.4) / 0.6 * 1.6, z)
        return false
    end
    if g_currentMission ~= nil and g_currentMission:getIsServer() and placeable.delete ~= nil and not placeable.isDeleted then
        local ok, err = pcall(placeable.delete, placeable)
        if not ok then Log:warning("EqLizard: could not remove a Lizard plinth: %s", tostring(err)) end
    end
    return true
end


--- Testing (eqLizard, James 2026-11-01): Lizard's chance of an offer is 100% for this session,
--- so the whole flow can be tested: the roll, the popup, the plinth and the results. A booking
--- for next month that already rolled no offer is rolled again now.
--- @param on boolean|nil nil toggles
--- @return string what happened
function EqLizard.setTestAlways(on)
    if on == nil then on = not EqLizard.testAlways end
    EqLizard.testAlways = on or nil
    if not on then return "Lizard's offer chance is back to normal" end
    if EqCompetitionManager ~= nil and EqHostManager ~= nil then EqLizard.considerAll(EqCompetitionManager.month or 0) end
    return "Lizard now offers to sponsor every unsponsored hosted event (100%) until you restart or run eqLizard off. "
        .. "Offers come the month before the event (or when you book for next month); close the console for the popup."
end


--- Testing (eqLizard now): Lizard sponsors the farm's event for sure, even over a yearly sponsor.
--- A booked event gets the offer popup now (or is accepted straight away with accept);
--- an event already open on the calendar becomes Lizard's at once.
--- @param farmId number
--- @param materialName string|nil stone, woodchips or straw, random when nil
--- @param accept boolean skip the popup
--- @return string what happened
function EqLizard.force(farmId, materialName, accept)
    local config = EqLizard.config
    if config == nil then return "Lizard is not loaded" end
    local material
    if materialName ~= nil and materialName ~= "" then
        material = EqLizard.material(config, string.upper(materialName))
        if material == nil then return "Material must be stone, woodchips or straw" end
    else
        material = EqLizard.roll(config, 0, math.random())
    end
    local event = EqHostManager.openEvent(farmId)
    if event ~= nil then
        local hosted = event.hosted
        if EqLizard.isLizardEvent(event) then return "Lizard already sponsors your event" end
        local month = EqCompetitionManager.month
        EqLizard.deals[farmId] = { month = month, type = event.discipline, rating = hosted.rating,
            material = material.fillType, state = "accepted", forced = true }
        hosted.sponsor = nil
        EqLizard.onEventOpened(event)
        EqLizard.updateShop()
        if EqSponsors ~= nil and EqSponsors.refresh ~= nil then EqSponsors.refresh() end
        return string.format("Lizard now sponsors %s: build the %s Lizard plinth (shop, Sponsor plinths) before the results",
            EqCompetitionManager.eventTitle(event), material.fillType)
    end
    local booking = EqHostManager.bookings[farmId]
    if booking == nil then return "Book a hosted event first (Events, Host), then run eqLizard again" end
    EqLizard.deals[farmId] = { month = booking.month, type = booking.type, rating = booking.rating, material = material.fillType,
        state = "offered", forced = true }
    EqLizard.asked[farmId] = nil
    if accept then
        EqLizard.answer(farmId, true)
        return string.format("Lizard will sponsor your %s (%s plinth)", EqHostManager.title(booking.type, booking.rating), material.fillType)
    end
    EqLizard.updateShop()
    return string.format("Lizard offers to sponsor your %s (%s plinth): close the console for the popup",
        EqHostManager.title(booking.type, booking.rating), material.fillType)
end


-- HOOKS

--- A hosted event opens: an accepted deal makes it Lizard's; an unanswered offer lapses.
--- @param event table
function EqLizard.onEventOpened(event)
    local hosted = event ~= nil and event.hosted or nil
    if hosted == nil then return end
    local farmId = hosted.farmId
    local deal = EqLizard.deals[farmId]
    if deal == nil or deal.month ~= EqCompetitionManager.month then return end
    if deal.state == "offered" then
        EqLizard.deals[farmId] = nil
        EqLizard.updateShop()
        return
    end
    if deal.state ~= "accepted" then return end
    if hosted.sponsor ~= nil and not deal.forced then
        -- a yearly sponsor signed since: Lizard steps aside, with no hard feelings
        tell(farmId, "EQ_SPONSOR_ENDED", string.format(g_i18n:getText("eq_lizard_stepAside"), EqLizard.title(), hosted.sponsor))
        EqLizard.deals[farmId] = nil
        EqLizard.updateShop()
        if EqSponsors ~= nil and EqSponsors.refresh ~= nil then EqSponsors.refresh() end
        return
    end
    deal.eventId = event.id
    hosted.sponsor = EqLizard.title()
    hosted.lizard = true
    hosted.sponsorPopularity = EqLizard.config.popularity
    Log:info("EqLizard: farm %d's event %d is Lizard's", farmId, event.id)
end


--- The results are in: pay if the plinth is built and the branding is there, then the plinth goes.
--- @param event table
--- @param report table
--- @param fee number what the yearly sponsors paid
--- @return number fee with Lizard's
function EqLizard.afterEvent(event, report, fee)
    if not EqLizard.isLizardEvent(event) then return fee end
    local farmId = event.hosted.farmId
    local deal = EqLizard.deals[farmId]
    local built = EqLizard.hasBuilt(farmId)
    local boards = EqSponsorManager.boards(farmId)
    local level = EqSponsorship.brandingLevel(EqSponsorManager.config, boards)
    local paid, why = EqLizard.payFor(EqLizard.config, deal.rating, built, level)
    local title = EqLizard.title()
    if paid > 0 then
        g_currentMission:addMoney(paid, farmId, MoneyType.EQ_SPONSORSHIP or MoneyType.OTHER, true, true)
        tell(farmId, "EQ_SPONSOR_PAID", string.format(g_i18n:getText("eq_lizard_paid"), title, money(paid)))
    else
        tell(farmId, "EQ_SPONSOR_WARNING", string.format(g_i18n:getText("eq_lizard_unpaid_" .. (why or "plinth")), title))
    end
    if report ~= nil then
        report.sponsor = title
        report.sponsorFee = (report.sponsorFee or 0) + paid
    end
    Log:info("EqLizard: farm %d's Lizard event paid %d (built %s, branding %d)", farmId, paid, tostring(built), level)
    EqLizard.deals[farmId] = nil
    EqLizard.collapse(farmId)
    EqLizard.updateShop()
    if EqSponsors ~= nil and EqSponsors.refresh ~= nil then EqSponsors.refresh() end
    return (fee or 0) + paid
end


--- Every CHECK_MS: ask the player about an offer, keep the shop right, and run collapses.
function EqLizard.update()
    for i = #EqLizard.collapsing, 1, -1 do
        local ok, done = EqLog.try("EqLizard collapse", collapseStep, EqLizard.collapsing[i])
        if not ok or done then table.remove(EqLizard.collapsing, i) end
    end
    if g_currentMission == nil or EqLizard.config == nil then return end
    local now = g_time or 0
    if EqLizard.checkedAt ~= nil and now - EqLizard.checkedAt < EqLizard.CHECK_MS and now >= EqLizard.checkedAt then return end
    EqLizard.checkedAt = now
    if not EqLizard.shopSet then
        EqLizard.shopSet = true
        EqLizard.updateShop()
    end
    EqLizard.dressMounds()
    local farmId = g_currentMission:getFarmId()
    local deal = EqLizard.deals[farmId]
    if deal == nil or deal.state ~= "offered" or EqLizard.asked[farmId] == deal.month then return end
    if (g_gui ~= nil and g_gui:getIsGuiVisible()) or YesNoDialog == nil or YesNoDialog.show == nil then return end
    EqLizard.asked[farmId] = deal.month
    YesNoDialog.show(function(yes)
        EqLog.try("EqLizard answer", EqLizard.answer, farmId, yes)
    end, nil, EqLizard.offerText(farmId, deal), string.format(g_i18n:getText("eq_lizard_title"), EqLizard.title()),
        g_i18n:getText("eq_lizard_accept"), g_i18n:getText("eq_lizard_decline"))
end


--- @param guarded function main.lua's error guard
function EqLizard.install(guarded)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("lizard sponsorship", EqLizard.update)
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        EqLizard.collapsing, EqLizard.shopSet, EqLizard.checkedAt = {}, nil, nil
    end)
    if EqSponsorManager ~= nil then
        local opened = EqSponsorManager.onEventOpened
        EqSponsorManager.onEventOpened = function(event)
            opened(event)
            EqLog.try("EqLizard event opened", EqLizard.onEventOpened, event)
        end
        local paid = EqSponsorManager.afterEvent
        EqSponsorManager.afterEvent = function(event, report)
            local fee = paid(event, report)
            local ok, after = EqLog.try("EqLizard pay", EqLizard.afterEvent, event, report, fee)
            if ok and after ~= nil then return after end
            return fee
        end
        local month = EqSponsorManager.onMonthStarted
        EqSponsorManager.onMonthStarted = function(m)
            month(m)
            EqLog.try("EqLizard month", EqLizard.onMonthStarted, m)
        end
    end
    if EqHostManager ~= nil then
        local book = EqHostManager.book
        EqHostManager.book = function(farmId, typeName, ratingName, m)
            local ok, text = book(farmId, typeName, ratingName, m)
            if ok then EqLog.try("EqLizard booking", EqLizard.considerAll, EqCompetitionManager.month or 0) end
            return ok, text
        end
        local cancel = EqHostManager.cancel
        EqHostManager.cancel = function(farmId)
            local ok, text = cancel(farmId)
            if ok and EqLizard.deals[farmId] ~= nil and EqLizard.deals[farmId].eventId == nil then
                EqLizard.deals[farmId] = nil
                EqLog.try("EqLizard shop", EqLizard.updateShop)
            end
            return ok, text
        end
    end
end


--- A new month: deals for months gone by are dropped, and next month's bookings get their roll.
--- @param month number
function EqLizard.onMonthStarted(month)
    for farmId, deal in pairs(EqLizard.deals) do
        if deal.month < month or (deal.month == month and deal.eventId == nil) then EqLizard.deals[farmId] = nil end
    end
    EqLizard.considerAll(month)
    EqLizard.updateShop()
end


-- SAVE AND LOAD (inside rlEquestrian.xml)

--- @param xmlFile table
--- @param key string such as "rlEquestrian.lizard"
function EqLizard.saveToXMLFile(xmlFile, key)
    local farmIds = {}
    for farmId in pairs(EqLizard.deals) do table.insert(farmIds, farmId) end
    table.sort(farmIds)
    for i, farmId in ipairs(farmIds) do
        local deal = EqLizard.deals[farmId]
        local dealKey = string.format("%s.deal(%d)", key, i - 1)
        xmlFile:setInt(dealKey .. "#farmId", farmId)
        xmlFile:setInt(dealKey .. "#month", deal.month)
        xmlFile:setString(dealKey .. "#type", deal.type or "")
        xmlFile:setString(dealKey .. "#rating", deal.rating or "")
        xmlFile:setString(dealKey .. "#state", deal.state)
        if deal.material ~= nil then xmlFile:setString(dealKey .. "#material", deal.material) end
        if deal.eventId ~= nil then xmlFile:setInt(dealKey .. "#eventId", deal.eventId) end
        if deal.forced then xmlFile:setBool(dealKey .. "#forced", true) end
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqLizard.loadFromXMLFile(xmlFile, key)
    EqLizard.reset()
    EqLizard.shopSet = nil
    if xmlFile == nil then return end
    local i = 0
    while xmlFile:hasProperty(string.format("%s.deal(%d)", key, i)) do
        local dealKey = string.format("%s.deal(%d)", key, i)
        local farmId = xmlFile:getInt(dealKey .. "#farmId")
        local state = xmlFile:getString(dealKey .. "#state")
        if farmId ~= nil and state ~= nil then
            EqLizard.deals[farmId] = { month = xmlFile:getInt(dealKey .. "#month", 0), type = xmlFile:getString(dealKey .. "#type"),
                rating = xmlFile:getString(dealKey .. "#rating"), state = state, material = xmlFile:getString(dealKey .. "#material"),
                eventId = xmlFile:getInt(dealKey .. "#eventId"), forced = xmlFile:getBool(dealKey .. "#forced", false) or nil }
        end
        i = i + 1
    end
end

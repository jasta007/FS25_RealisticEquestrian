--[[
    EqSponsorship.lua
    The rules of sponsorship for the events a farm hosts (James, 2026-10-29), read from
    data/sponsors.xml. Pure functions with no game calls, so they run in the tests; the game
    side (the shop, the farm's machines, contracts and money) is EqSponsorManager.

    - Sponsors are brands from the player's own shop. A brand's size comes from what it sells:
      shop categories first, then how many price bands its machines span, then how many machines.
      The biggest share of brands are big, the next moderate, the rest small.
    - Each year a farm is offered a few of each size. Every offer rolls a strictness, from
      Relaxed to Hard bargain: stricter sponsors ask more (machines to own, a wider competitor
      clause, a higher popularity target, more sponsor boards) and pay more (fee and discounts).
    - To sign: own enough of the sponsor's machines, none from a rival that clashes, some sponsor
      boards, and no other sponsor. Signed, each hosted event at a rating the sponsor backs is
      named after it, draws more visitors and pays its fee, more with more boards on show.
    - Each contract year the farm must host an event at the sponsor's rating that ends at its
      popularity target (and a top 3 finish for the strictest). A miss cuts next year's fee;
      missing twice in a row, the sponsor walks away. Cancelling early costs a share of a fee
      for each year left.

    Part of Realistic Equestrian by Jasta007.
]]

EqSponsorship = {}

local Log = EqLog

EqSponsorship.SIZES = { "big", "moderate", "small" }


--- @param xmlFile table
--- @return table config
function EqSponsorship.read(xmlFile)
    local config = {
        offerMonths = xmlFile:getInt("sponsors#offerMonths", 6),
        cancelShare = xmlFile:getFloat("sponsors#cancelShare", 0.15),
        missFactor = xmlFile:getFloat("sponsors#missFactor", 0.75),
        missesToLeave = xmlFile:getInt("sponsors#missesToLeave", 2),
        signsMin = xmlFile:getInt("sponsors#signsMin", 1),
        categoryTypes = {}, skipBrands = {}, bands = {}, sizes = {}, sizeByName = {},
        words = {}, terms = {}, wobble = xmlFile:getFloat("sponsors.strictness#wobble", 0.1),
    }
    local i = 0
    while xmlFile:hasProperty(string.format("sponsors.categoryTypes.type(%d)", i)) do
        local name = xmlFile:getString(string.format("sponsors.categoryTypes.type(%d)#name", i))
        if name ~= nil then config.categoryTypes[string.upper(name)] = true end
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("sponsors.skipBrands.brand(%d)", i)) do
        local name = xmlFile:getString(string.format("sponsors.skipBrands.brand(%d)#name", i))
        if name ~= nil then config.skipBrands[string.upper(name)] = true end
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("sponsors.priceBands.band(%d)", i)) do
        table.insert(config.bands, xmlFile:getFloat(string.format("sponsors.priceBands.band(%d)#max", i), 0))
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("sponsors.sizes.size(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local size = {
            name = xmlFile:getString(key .. "#name", "small"),
            share = xmlFile:getFloat(key .. "#share", 0),
            offers = xmlFile:getInt(key .. "#offers", 0),
            yearsMin = xmlFile:getInt(key .. "#yearsMin", 1),
            yearsMax = xmlFile:getInt(key .. "#yearsMax", 1),
            feeMin = xmlFile:getFloat(key .. "#feeMin", 0),
            feeMax = xmlFile:getFloat(key .. "#feeMax", 0),
            popularity = xmlFile:getInt(key .. "#popularity", 0),
            target = xmlFile:getInt(key .. "#target", 50),
            minRating = xmlFile:getString(key .. "#minRating", "novice"),
            lowerShare = xmlFile:getFloat(key .. "#lowerShare", 0),
            lowerRating = xmlFile:getString(key .. "#lowerRating"),
        }
        table.insert(config.sizes, size)
        config.sizeByName[size.name] = size
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("sponsors.strictness.word(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        table.insert(config.words, { name = xmlFile:getString(key .. "#name", "fair"), from = xmlFile:getFloat(key .. "#from", 0) })
        i = i + 1
    end
    table.sort(config.words, function(a, b) return a.from < b.from end)
    i = 0
    while true do
        local key = string.format("sponsors.strictness.term(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local name = xmlFile:getString(key .. "#name")
        if name ~= nil then
            config.terms[name] = { relaxed = xmlFile:getFloat(key .. "#relaxed", 0), strict = xmlFile:getFloat(key .. "#strict", 0),
                from = xmlFile:getFloat(key .. "#from") }
        end
        i = i + 1
    end
    return config
end


--- @param path string
--- @return table|nil config
function EqSponsorship.load(path)
    local xmlFile = XMLFile.load("eqSponsors", path)
    if xmlFile == nil then
        Log:warning("EqSponsorship: could not read %s; no sponsors this session", path)
        return nil
    end
    local config = EqSponsorship.read(xmlFile)
    xmlFile:delete()
    Log:info("EqSponsorship: %d sizes, %d price bands", #config.sizes, #config.bands)
    return config
end


--- @param config table
--- @param price number
--- @return number band 1.. (#bands + 1 above the last edge)
function EqSponsorship.bandOf(config, price)
    for i, max in ipairs(config.bands) do
        if price <= max then return i end
    end
    return #config.bands + 1
end


--- What each brand sells. Pure.
--- @param config table
--- @param items table list of { brand, categories = list of names, price, name }, the shop's machines
--- @return table profiles brand -> { brand, categories (count), bands (count), items (count),
---     byCategory = category -> list of prices }
function EqSponsorship.profiles(config, items)
    local profiles = {}
    for _, item in ipairs(items) do
        if item.brand ~= nil and not config.skipBrands[string.upper(item.brand)] and #(item.categories or {}) > 0 then
            local profile = profiles[item.brand]
            if profile == nil then
                profile = { brand = item.brand, categories = 0, bands = 0, items = 0, byCategory = {}, bandSeen = {} }
                profiles[item.brand] = profile
            end
            profile.items = profile.items + 1
            local band = EqSponsorship.bandOf(config, item.price or 0)
            if not profile.bandSeen[band] then
                profile.bandSeen[band] = true
                profile.bands = profile.bands + 1
            end
            for _, category in ipairs(item.categories) do
                if profile.byCategory[category] == nil then
                    profile.byCategory[category] = {}
                    profile.categories = profile.categories + 1
                end
                table.insert(profile.byCategory[category], item.price or 0)
            end
        end
    end
    return profiles
end


--- Rank the brands by size and give each one its size (James's order: categories, then price
--- bands, then machines). Pure.
--- @param config table
--- @param profiles table from EqSponsorship.profiles
--- @return table ranked list of profiles, biggest first, each with .size and .rank
function EqSponsorship.rank(config, profiles)
    local ranked = {}
    for _, profile in pairs(profiles) do table.insert(ranked, profile) end
    table.sort(ranked, function(a, b)
        if a.categories ~= b.categories then return a.categories > b.categories end
        if a.bands ~= b.bands then return a.bands > b.bands end
        if a.items ~= b.items then return a.items > b.items end
        return a.brand < b.brand
    end)
    local count = #ranked
    local edge, sizeIndex = 0, 1
    local limits = {}
    for i, size in ipairs(config.sizes) do
        edge = edge + size.share
        -- The last size takes the rest, whatever its share says.
        limits[i] = i == #config.sizes and count or math.max(1, math.floor(count * edge + 0.5))
    end
    for i, profile in ipairs(ranked) do
        while sizeIndex < #config.sizes and i > limits[sizeIndex] do sizeIndex = sizeIndex + 1 end
        profile.rank = i
        profile.size = config.sizes[sizeIndex] ~= nil and config.sizes[sizeIndex].name or "small"
    end
    return ranked
end


--- @param config table
--- @param strictness number 0..1
--- @return string word "relaxed", "fair", "demanding" or "hardBargain"
function EqSponsorship.word(config, strictness)
    local word = config.words[1] ~= nil and config.words[1].name or "fair"
    for _, entry in ipairs(config.words) do
        if strictness >= entry.from then word = entry.name end
    end
    return word
end


--- A term at this strictness, with a little wobble.
--- @param config table
--- @param name string
--- @param strictness number 0..1
--- @param rng table|nil EqRandom for the wobble, none without
--- @return number
function EqSponsorship.term(config, name, strictness, rng)
    local term = config.terms[name]
    if term == nil then return 0 end
    local value = term.relaxed + (term.strict - term.relaxed) * strictness
    if rng ~= nil and config.wobble > 0 then value = value * (1 + (rng:next() * 2 - 1) * config.wobble) end
    return value
end


--- @param categories number how many categories the sponsor makes
--- @param perMachine number categories per machine to own
--- @return number machines of the sponsor's to own
function EqSponsorship.machinesNeeded(categories, perMachine)
    return math.max(1, math.ceil((categories or 1) / math.max(1, perMachine or 3)))
end


--- @param value number
--- @param step number
--- @return number value rounded to the step
local function roundTo(value, step)
    return math.floor(value / step + 0.5) * step
end


--- One sponsor's offer. Pure.
--- @param config table
--- @param profile table a ranked profile (with .size)
--- @param rng table EqRandom
--- @return table offer
function EqSponsorship.makeOffer(config, profile, rng)
    local size = config.sizeByName[profile.size] or config.sizes[#config.sizes]
    local strictness = rng:next()
    local perMachine = math.max(1, math.floor(EqSponsorship.term(config, "categoriesPerMachine", strictness, rng) + 0.5))
    local top3 = config.terms.top3 ~= nil and config.terms.top3.from ~= nil and strictness >= config.terms.top3.from
    local years = size.yearsMin + math.floor(rng:next() * (size.yearsMax - size.yearsMin + 1))
    local feeBase = size.feeMin + (size.feeMax - size.feeMin) * rng:next()
    return {
        brand = profile.brand,
        size = size.name,
        strictness = strictness,
        word = EqSponsorship.word(config, strictness),
        years = math.min(size.yearsMax, years),
        fee = roundTo(feeBase * EqSponsorship.term(config, "fee", strictness, rng), 500),
        popularity = size.popularity,
        target = math.min(100, math.max(0, math.floor(size.target + EqSponsorship.term(config, "target", strictness, rng) + 0.5))),
        top3 = top3,
        signsFull = math.max(config.signsMin, math.floor(EqSponsorship.term(config, "signsFull", strictness, rng) + 0.5)),
        categories = profile.categories,
        perMachine = perMachine,
        machines = EqSponsorship.machinesNeeded(profile.categories, perMachine),
        window = math.floor(EqSponsorship.term(config, "window", strictness, rng) * 100 + 0.5) / 100,
        repair = math.floor(EqSponsorship.term(config, "repair", strictness, rng) * 100 + 0.5) / 100,
        repaint = math.floor(EqSponsorship.term(config, "repaint", strictness, rng) * 100 + 0.5) / 100,
        purchase = math.floor(EqSponsorship.term(config, "purchase", strictness, rng) * 100 + 0.5) / 100,
    }
end


--- The year's offers: a few brands of each size, picked at random. Pure.
--- @param config table
--- @param ranked table from EqSponsorship.rank
--- @param seed string|number
--- @return table offers biggest first
function EqSponsorship.makeOffers(config, ranked, seed)
    local rng = EqRandom.new(seed)
    local offers = {}
    for _, size in ipairs(config.sizes) do
        local pool = {}
        for _, profile in ipairs(ranked) do
            if profile.size == size.name then table.insert(pool, profile) end
        end
        for _ = 1, math.min(size.offers, #pool) do
            local index = math.floor(rng:next() * #pool) + 1
            local profile = table.remove(pool, index)
            table.insert(offers, EqSponsorship.makeOffer(config, profile, rng))
        end
    end
    return offers
end


--- The farm's machines that break the offer's competitor clause: another brand's machine in a
--- category the sponsor makes, priced within the window of one of the sponsor's machines there.
--- Pure.
--- @param offer table
--- @param profile table the sponsor's profile (byCategory)
--- @param owned table list of { brand, categories, price, name }
--- @return table clashes list of owned machines
function EqSponsorship.clashes(offer, profile, owned)
    local found = {}
    for _, machine in ipairs(owned) do
        if machine.brand ~= offer.brand then
            local clash = false
            for _, category in ipairs(machine.categories or {}) do
                for _, price in ipairs(profile ~= nil and profile.byCategory[category] or {}) do
                    if price > 0 and math.abs((machine.price or 0) - price) <= offer.window * price then clash = true end
                end
            end
            if clash then table.insert(found, machine) end
        end
    end
    return found
end


--- @param brand string
--- @param owned table list of { brand }
--- @return number how many of the farm's machines are the brand's
function EqSponsorship.ownedOf(brand, owned)
    local count = 0
    for _, machine in ipairs(owned) do
        if machine.brand == brand then count = count + 1 end
    end
    return count
end


--- What signing needs, each with what the farm has. Pure.
--- @param config table
--- @param offer table
--- @param state table { owned, profile, boards, contract (the farm's, or nil) }
--- @return table checks list of { id, ok, have, need }, ok
--- @return table clashes the machines breaking the competitor clause
function EqSponsorship.signChecks(config, offer, state)
    local checks, allOk = {}, true
    local function add(id, ok, have, need)
        table.insert(checks, { id = id, ok = ok, have = have, need = need })
        if not ok then allOk = false end
    end
    local mine = EqSponsorship.ownedOf(offer.brand, state.owned or {})
    add("machines", mine >= offer.machines, mine, offer.machines)
    local clashes = EqSponsorship.clashes(offer, state.profile, state.owned or {})
    add("rivals", #clashes == 0, #clashes, 0)
    add("boards", (state.boards or 0) >= config.signsMin, state.boards or 0, config.signsMin)
    add("exclusive", state.contract == nil, state.contract ~= nil and 1 or 0, 0)
    checks.ok = allOk
    return checks, clashes
end


--- @param ratingOrder table rating name -> index (novice 1, intermediate 2, ...)
--- @param name string|nil
--- @return number index, 0 when unknown
local function indexOf(ratingOrder, name)
    return name ~= nil and ratingOrder[name] or 0
end


--- How much of its fee a sponsor pays for an event at this rating. Pure.
--- @param config table
--- @param offer table
--- @param ratingName string
--- @param ratingOrder table rating name -> index
--- @return number share 0..1
function EqSponsorship.feeShare(config, offer, ratingName, ratingOrder)
    local size = config.sizeByName[offer.size]
    if size == nil then return 0 end
    local rating = indexOf(ratingOrder, ratingName)
    if rating >= indexOf(ratingOrder, size.minRating) then return 1 end
    if size.lowerShare > 0 and size.lowerRating ~= nil and rating >= indexOf(ratingOrder, size.lowerRating) then return size.lowerShare end
    return 0
end


--- @param offer table
--- @param boards number sponsor boards on show
--- @param signsMin number
--- @return number factor 0 below signsMin, then from half up to 1 at offer.signsFull
function EqSponsorship.boardsFactor(offer, boards, signsMin)
    if (boards or 0) < math.max(1, signsMin or 1) then return 0 end
    local full = math.max(1, offer.signsFull or 1)
    return 0.5 + 0.5 * math.min(1, boards / full)
end


--- What a hosted event earns from the farm's sponsor. Pure.
--- @param config table
--- @param contract table
--- @param ratingName string
--- @param ratingOrder table
--- @param boards number
--- @param machinesOk boolean the farm still owns enough of the sponsor's machines
--- @return number fee
--- @return string|nil why nothing: "rating", "boards" or "machines"
function EqSponsorship.eventFee(config, contract, ratingName, ratingOrder, boards, machinesOk)
    local share = EqSponsorship.feeShare(config, contract, ratingName, ratingOrder)
    if share <= 0 then return 0, "rating" end
    if not machinesOk then return 0, "machines" end
    local factor = EqSponsorship.boardsFactor(contract, boards, config.signsMin)
    if factor <= 0 then return 0, "boards" end
    return roundTo(contract.fee * share * factor * (contract.feeFactor or 1), 100), nil
end


--- Does this hosted event meet the contract's yearly target? Pure.
--- @param config table
--- @param contract table
--- @param ratingName string
--- @param ratingOrder table
--- @param popularity number the event's final popularity
--- @param bestPlace number|nil the farm's best finish in it
--- @return boolean
function EqSponsorship.meetsTarget(config, contract, ratingName, ratingOrder, popularity, bestPlace)
    local size = config.sizeByName[contract.size]
    if size == nil then return false end
    local lowest = size.lowerShare > 0 and size.lowerRating or size.minRating
    if indexOf(ratingOrder, ratingName) < indexOf(ratingOrder, lowest) then return false end
    if (popularity or 0) < (contract.target or 0) then return false end
    if contract.top3 and (bestPlace == nil or bestPlace < 1 or bestPlace > 3) then return false end
    return true
end


--- A contract year is over: a met target keeps the full fee, a miss cuts the next year's, and
--- too many misses in a row end it. Pure: changes the contract.
--- @param config table
--- @param contract table { met, misses, feeFactor }
--- @return boolean leaves the sponsor walks away
function EqSponsorship.closeYear(config, contract)
    if contract.met then
        contract.misses = 0
        contract.feeFactor = 1
    else
        contract.misses = (contract.misses or 0) + 1
        contract.feeFactor = config.missFactor
    end
    contract.met = false
    return contract.misses >= config.missesToLeave
end


--- What cancelling costs now. Pure.
--- @param config table
--- @param contract table { fee, endMonth }
--- @param now number the month now
--- @return number cost
--- @return number yearsLeft (a part year counted whole)
function EqSponsorship.cancelCost(config, contract, now)
    local monthsLeft = math.max(0, (contract.endMonth or now) - now)
    local yearsLeft = math.ceil(monthsLeft / 12)
    return roundTo(contract.fee * config.cancelShare * yearsLeft, 100), yearsLeft
end


--- A signed contract from an offer. Pure.
--- @param offer table
--- @param month number the month it is signed in
--- @return table contract
function EqSponsorship.contractFrom(offer, month)
    local contract = {}
    for key, value in pairs(offer) do contract[key] = value end
    contract.signedMonth = month
    contract.endMonth = month + 12 * (offer.years or 1)
    contract.yearEnd = month + 12
    contract.met = false
    contract.misses = 0
    contract.feeFactor = 1
    contract.paid = 0
    return contract
end


-- Offer and contract fields kept in the save.
EqSponsorship.NUMBER_FIELDS = { "strictness", "years", "fee", "popularity", "target", "signsFull", "categories", "perMachine",
    "machines", "window", "repair", "repaint", "purchase", "signedMonth", "endMonth", "yearEnd", "misses", "feeFactor", "paid" }
EqSponsorship.STRING_FIELDS = { "brand", "size", "word" }
EqSponsorship.BOOL_FIELDS = { "top3", "met" }


--- @param xmlFile table
--- @param key string
--- @param offer table an offer or contract
function EqSponsorship.saveOffer(xmlFile, key, offer)
    for _, name in ipairs(EqSponsorship.STRING_FIELDS) do
        if offer[name] ~= nil then xmlFile:setString(key .. "#" .. name, offer[name]) end
    end
    for _, name in ipairs(EqSponsorship.NUMBER_FIELDS) do
        if offer[name] ~= nil then xmlFile:setFloat(key .. "#" .. name, offer[name]) end
    end
    for _, name in ipairs(EqSponsorship.BOOL_FIELDS) do
        if offer[name] then xmlFile:setBool(key .. "#" .. name, true) end
    end
end


--- @param xmlFile table
--- @param key string
--- @return table|nil offer
function EqSponsorship.loadOffer(xmlFile, key)
    local offer = {}
    for _, name in ipairs(EqSponsorship.STRING_FIELDS) do offer[name] = xmlFile:getString(key .. "#" .. name) end
    for _, name in ipairs(EqSponsorship.NUMBER_FIELDS) do offer[name] = xmlFile:getFloat(key .. "#" .. name) end
    for _, name in ipairs(EqSponsorship.BOOL_FIELDS) do offer[name] = xmlFile:getBool(key .. "#" .. name, false) end
    if offer.brand == nil or offer.size == nil then return nil end
    return offer
end

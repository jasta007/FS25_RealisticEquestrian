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
    - To sign: own enough of the sponsor's machines, none from a rival that clashes, and some
      sponsor boards. A farm can have up to three sponsors at once (James, 2026-10-31), each with
      all its rules met: big sponsors are always exclusive (no one else), moderate ones may be,
      small ones never are, and no two sponsors may make machines in the same shop category. Signed, each hosted event at a rating the sponsor backs is
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
        branding = {},
        machinesMax = xmlFile:getInt("sponsors#machinesMax", 5),
        maxSponsors = xmlFile:getInt("sponsors#maxSponsors", 1),
        attachmentWeight = xmlFile:getFloat("sponsors#attachmentWeight", 1),
        easyCategories = {},
        skipCategoryTypes = {}, skipBrands = {}, bands = {}, sizes = {}, sizeByName = {},
        words = {}, terms = {}, wobble = xmlFile:getFloat("sponsors.strictness#wobble", 0.1),
    }
    local i = 0
    while xmlFile:hasProperty(string.format("sponsors.skipCategoryTypes.type(%d)", i)) do
        local name = xmlFile:getString(string.format("sponsors.skipCategoryTypes.type(%d)#name", i))
        if name ~= nil then config.skipCategoryTypes[string.upper(name)] = true end
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("sponsors.skipBrands.brand(%d)", i)) do
        local name = xmlFile:getString(string.format("sponsors.skipBrands.brand(%d)#name", i))
        if name ~= nil then config.skipBrands[string.upper(name)] = true end
        i = i + 1
    end
    i = 0
    while xmlFile:hasProperty(string.format("sponsors.easyCategories.category(%d)", i)) do
        local name = xmlFile:getString(string.format("sponsors.easyCategories.category(%d)#name", i))
        if name ~= nil then config.easyCategories[string.upper(name)] = true end
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
            minItems = xmlFile:getInt(key .. "#minItems", 0),
            machinesMax = xmlFile:getInt(key .. "#machinesMax", 0),
            exclusive = xmlFile:getFloat(key .. "#exclusive", 1),
        }
        size.minItemsEasy = xmlFile:getInt(key .. "#minItemsEasy", size.minItems)
        table.insert(config.sizes, size)
        config.sizeByName[size.name] = size
        i = i + 1
    end
    -- Branding levels (James, 2026-10-31): sponsor boards on the farm's placeables make Low,
    -- Medium or High branding; the player sees the word, never the board count.
    i = 0
    while true do
        local key = string.format("sponsors.branding.level(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        table.insert(config.branding, { name = xmlFile:getString(key .. "#name", "low"), boards = xmlFile:getInt(key .. "#boards", 1),
            pay = xmlFile:getFloat(key .. "#pay", 1) })
        i = i + 1
    end
    table.sort(config.branding, function(a, b) return a.boards < b.boards end)
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
                profile = { brand = item.brand, categories = 0, bands = 0, items = 0, byCategory = {}, bandSeen = {}, easy = false }
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
                    if (config.easyCategories or {})[string.upper(category)] then profile.easy = true end
                end
                table.insert(profile.byCategory[category], item.price or 0)
            end
        end
    end
    return profiles
end


--- @param size table a sponsor size
--- @param profile table a brand's profile
--- @return number the fewest shop machines the brand needs for that size: fewer when it makes
---     something easy to get, such as a tractor or a car (James, 2026-10-31)
function EqSponsorship.minItemsFor(size, profile)
    if profile.easy and size.minItemsEasy ~= nil then return math.min(size.minItems, size.minItemsEasy) end
    return size.minItems
end


--- Rank the brands by size and give each one its size (James's order: categories, then price
--- bands, then machines). Pure.
--- @param config table
--- @param profiles table from EqSponsorship.profiles
--- @return table ranked list of profiles, biggest first, each with .size and .rank
function EqSponsorship.rank(config, profiles)
    -- A brand with fewer machines than the smallest size asks for is no sponsor at all (James,
    -- 2026-10-31: one tree cutter nobody buys is not a sponsor), unless what it makes is easy to
    -- get, such as a tractor, a car or a telehandler.
    local ranked = {}
    for _, profile in pairs(profiles) do
        profile.size, profile.rank = nil, nil
        local fewest = nil
        for _, size in ipairs(config.sizes) do
            local need = EqSponsorship.minItemsFor(size, profile)
            if fewest == nil or need < fewest then fewest = need end
        end
        if profile.items >= (fewest or 0) then table.insert(ranked, profile) end
    end
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
        -- Too few machines for its place: down to the biggest size it has enough for.
        local index = sizeIndex
        while index < #config.sizes and profile.items < EqSponsorship.minItemsFor(config.sizes[index], profile) do index = index + 1 end
        profile.size = config.sizes[index] ~= nil and config.sizes[index].name or "small"
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
--- @param max number|nil the most a sponsor asks for (James 2026-10-31: about 5)
--- @return number machines of the sponsor's to own
function EqSponsorship.machinesNeeded(categories, perMachine, max)
    local needed = math.max(1, math.ceil((categories or 1) / math.max(1, perMachine or 3)))
    if max ~= nil and max > 0 then needed = math.min(needed, max) end
    return needed
end


--- @param config table
--- @param size table|nil a sponsor size
--- @return number the most machines a sponsor of that size asks for (James, 2026-10-31: a
---     moderate brand with 13 products asking for 5 is too much)
function EqSponsorship.machinesMaxFor(config, size)
    local max = config.machinesMax
    if size ~= nil and size.machinesMax > 0 then max = math.min(max, size.machinesMax) end
    return max
end


--- @param share number
--- @return number the share rounded to the nearest 5% (James 2026-10-31)
function EqSponsorship.round5(share)
    return math.floor(share * 20 + 0.5) / 20
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
    local offer = {
        brand = profile.brand,
        size = size.name,
        strictness = strictness,
        word = EqSponsorship.word(config, strictness),
        years = math.min(size.yearsMax, years),
        fee = roundTo(feeBase * EqSponsorship.term(config, "fee", strictness, rng), 500),
        popularity = size.popularity,
        target = math.min(100, math.max(0, math.floor(size.target + EqSponsorship.term(config, "target", strictness, rng) + 0.5))),
        top3 = top3,
        brandingNeed = EqSponsorship.brandingNeed(config, EqSponsorship.term(config, "branding", strictness, rng)),
        categories = profile.categories,
        perMachine = perMachine,
        machines = EqSponsorship.machinesNeeded(profile.categories, perMachine, EqSponsorship.machinesMaxFor(config, size)),
        window = EqSponsorship.round5(EqSponsorship.term(config, "window", strictness, rng)),
        repair = EqSponsorship.round5(EqSponsorship.term(config, "repair", strictness, rng)),
        repaint = EqSponsorship.round5(EqSponsorship.term(config, "repaint", strictness, rng)),
        purchase = EqSponsorship.round5(EqSponsorship.term(config, "purchase", strictness, rng)),
    }
    offer.exclusive = EqSponsorship.rollExclusive(size, rng)
    return offer
end


--- @param size table a sponsor size
--- @param rng table|nil EqRandom; nil gives a moderate chance as not exclusive
--- @return boolean the offer allows no other sponsor (James, 2026-10-31: big always, moderate
---     maybe, small never)
function EqSponsorship.rollExclusive(size, rng)
    local chance = size ~= nil and size.exclusive or 1
    if chance >= 1 then return true end
    if chance <= 0 or rng == nil then return false end
    return rng:next() < chance
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
--- The farm's other sponsors' machines never count (their categories can't overlap anyway).
--- @param offer table
--- @param profile table the sponsor's profile (byCategory)
--- @param owned table list of { brand, categories, price, name }
--- @param allowed table|nil brand -> true for the farm's other sponsors
--- @return table clashes list of owned machines
function EqSponsorship.clashes(offer, profile, owned, allowed)
    local found = {}
    for _, machine in ipairs(owned) do
        if machine.brand ~= offer.brand and not (allowed ~= nil and allowed[machine.brand]) then
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
--- @param owned table list of { brand, attachment (true for an attachment or trailer) }
--- @param attachmentWeight number|nil what an attachment counts (James, 2026-11-01: half); 1 without
--- @return number how many of the farm's machines are the brand's, attachments weighted
function EqSponsorship.ownedOf(brand, owned, attachmentWeight)
    local count = 0
    for _, machine in ipairs(owned) do
        if machine.brand == brand then count = count + (machine.attachment and (attachmentWeight or 1) or 1) end
    end
    return count
end


--- @param a table|nil a brand's profile (byCategory)
--- @param b table|nil another's
--- @return table categories the shop categories both make, sorted
function EqSponsorship.sharedCategories(a, b)
    local shared = {}
    if a == nil or b == nil then return shared end
    for category in pairs(a.byCategory or {}) do
        if (b.byCategory or {})[category] ~= nil then table.insert(shared, category) end
    end
    table.sort(shared)
    return shared
end


--- @param contracts table|nil the farm's contracts
--- @return boolean one of them is exclusive
function EqSponsorship.hasExclusive(contracts)
    for _, contract in ipairs(contracts or {}) do
        if contract.exclusive then return true end
    end
    return false
end


local SIZE_ORDER = { big = 1, moderate = 2, small = 3 }

--- The sponsor the farm's events are named after: the biggest, then the best paid, then the
--- first signed. Pure.
--- @param contracts table|nil
--- @return table|nil contract
function EqSponsorship.lead(contracts)
    local best = nil
    for _, contract in ipairs(contracts or {}) do
        if best == nil then
            best = contract
        else
            local a, b = SIZE_ORDER[contract.size] or 9, SIZE_ORDER[best.size] or 9
            if a < b or (a == b and (contract.fee or 0) > (best.fee or 0)) then best = contract end
        end
    end
    return best
end


--- What signing needs, each with what the farm has. Pure.
--- @param config table
--- @param offer table
--- @param state table { owned, profile, boards, contracts (the farm's, a list), profiles (brand ->
---     profile, for the other sponsors' categories) }; an older contract = one contract works too
--- @return table checks list of { id, ok, have, need, brands (for "overlap") }, ok
--- @return table clashes the machines breaking the competitor clause
function EqSponsorship.signChecks(config, offer, state)
    local checks, allOk = {}, true
    local function add(id, ok, have, need)
        table.insert(checks, { id = id, ok = ok, have = have, need = need })
        if not ok then allOk = false end
    end
    local contracts = state.contracts or (state.contract ~= nil and { state.contract } or {})
    local allowed = {}
    for _, contract in ipairs(contracts) do allowed[contract.brand] = true end
    local mine = EqSponsorship.ownedOf(offer.brand, state.owned or {}, config.attachmentWeight)
    add("machines", mine >= offer.machines, mine, offer.machines)
    local clashes = EqSponsorship.clashes(offer, state.profile, state.owned or {}, allowed)
    add("rivals", #clashes == 0, #clashes, 0)
    local level = EqSponsorship.brandingLevel(config, state.boards or 0)
    add("branding", level >= (offer.brandingNeed or 1), level, offer.brandingNeed or 1)
    -- An exclusive offer wants no other sponsor; an exclusive sponsor allows no new one.
    local exclusiveOk = #contracts == 0 or (not offer.exclusive and not EqSponsorship.hasExclusive(contracts))
    add("exclusive", exclusiveOk, #contracts, 0)
    local max = math.max(1, config.maxSponsors or 1)
    add("slots", #contracts < max, #contracts, max)
    -- No two sponsors in the same shop category (James: no Steyr medium tractor next to Zetor's).
    local overlap = {}
    for _, contract in ipairs(contracts) do
        local shared = contract.brand == offer.brand and { offer.brand }
            or EqSponsorship.sharedCategories(state.profile, state.profiles ~= nil and state.profiles[contract.brand] or nil)
        if #shared > 0 then table.insert(overlap, { brand = contract.brand, categories = shared }) end
    end
    add("overlap", #overlap == 0, #overlap, 0)
    checks[#checks].brands = overlap
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


--- @param config table
--- @param boards number sponsor boards on the farm's placeables
--- @return number level 0 for none, then the index of the highest branding level reached
function EqSponsorship.brandingLevel(config, boards)
    local level = 0
    for i, entry in ipairs(config.branding) do
        if (boards or 0) >= entry.boards then level = i end
    end
    return level
end


--- @param config table
--- @param value number a level from the strictness term, 1 (Low) up
--- @return number level the branding an offer requires, 1 .. the number of levels
function EqSponsorship.brandingNeed(config, value)
    return math.max(1, math.min(#config.branding, math.floor((value or 1) + 0.5)))
end


--- @param config table
--- @param offer table
--- @param boards number
--- @return number factor 0 below the offer's required branding, else the reached level's pay share
function EqSponsorship.brandingFactor(config, offer, boards)
    local level = EqSponsorship.brandingLevel(config, boards)
    if level < (offer.brandingNeed or 1) or level == 0 then return 0 end
    return config.branding[level].pay
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
    local factor = EqSponsorship.brandingFactor(config, contract, boards)
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
EqSponsorship.NUMBER_FIELDS = { "strictness", "years", "fee", "popularity", "target", "brandingNeed", "categories", "perMachine",
    "machines", "window", "repair", "repaint", "purchase", "signedMonth", "endMonth", "yearEnd", "misses", "feeFactor", "paid" }
EqSponsorship.STRING_FIELDS = { "brand", "size", "word" }
EqSponsorship.BOOL_FIELDS = { "top3", "met", "exclusive" }


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


--- Bring an offer saved by an older version up to today's rules: at most machinesMax machines,
--- shares on 5% steps. Pure: changes the offer.
--- @param config table|nil
--- @param offer table
--- @return table offer
function EqSponsorship.tidy(config, offer)
    if config ~= nil and offer.machines ~= nil then
        offer.machines = math.min(offer.machines, EqSponsorship.machinesMaxFor(config, config.sizeByName[offer.size]))
    end
    -- Saved before sponsors could share (James, 2026-10-31): big ones are always exclusive,
    -- small ones never; a moderate one keeps what it was saved with (not exclusive before).
    local size = config ~= nil and config.sizeByName[offer.size] or nil
    if size ~= nil and size.exclusive >= 1 then offer.exclusive = true end
    if size ~= nil and size.exclusive <= 0 then offer.exclusive = false end
    if config ~= nil and offer.brandingNeed == nil then
        offer.brandingNeed = EqSponsorship.brandingNeed(config, EqSponsorship.term(config, "branding", offer.strictness or 0))
    end
    for _, name in ipairs({ "window", "repair", "repaint", "purchase" }) do
        if offer[name] ~= nil then offer[name] = EqSponsorship.round5(offer[name]) end
    end
    return offer
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

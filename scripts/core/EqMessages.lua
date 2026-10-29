--[[
    EqMessages.lua
    Realistic Equestrian's lines in RLRM's message log (the Messages tab of the Shift+O menu).

    RLRM keeps a log per husbandry: each line is a message id from its RLMessage table, the
    animal it names, a date and a list of text arguments. The tab looks the id up in RLMessage
    for a title and severity, then fills "rl_message_<text>" with the arguments. RLRM splits that
    template on spaces and only fills a bare %s, so our one template is just "%s" and the whole
    sentence, already written by us, is its one argument. RLRM saves, loads and syncs the lines.
    A result line carries a second argument the template never shows, "eqHorse:<horse id>", so
    the Messages tab can open that horse's results (see EqMessagesLink).

    RLRM throws away saved lines whose id it doesn't know, so our ids go into RLMessage at
    activation, before the savegame's husbandries load.
]]

EqMessages = {}

local Log = EqLog

-- Our ids in RLMessage: { title (rl_messageTitle_<title>), RLConstants.SEVERITY key }.
EqMessages.TYPES = {
    EQ_PLACED = { title = "eqCompetition", severity = "SUCCESS" },
    EQ_FINISHED = { title = "eqCompetition", severity = "INFO" },
    EQ_ELIMINATED = { title = "eqCompetition", severity = "NOTICE" },
    EQ_SCRATCHED = { title = "eqCompetition", severity = "NOTICE" },
    EQ_NOT_DELIVERED = { title = "eqCompetition", severity = "WARNING" },
    EQ_GONE = { title = "eqCompetition", severity = "NOTICE" },
    EQ_INJURED = { title = "eqInjury", severity = "WARNING" },
    EQ_RECOVERED = { title = "eqInjury", severity = "SUCCESS" },
    EQ_ILL = { title = "eqInjury", severity = "WARNING" },
    EQ_CAREER_ENDED = { title = "eqRetirement", severity = "NOTICE" },
    EQ_REVEAL_BETTER = { title = "eqDealer", severity = "SUCCESS" },
    EQ_REVEAL_FAIR = { title = "eqDealer", severity = "INFO" },
    EQ_REVEAL_WORSE = { title = "eqDealer", severity = "NOTICE" },
    EQ_DELIVERED = { title = "eqTransport", severity = "INFO" },
    EQ_HOST_OPENED = { title = "eqHosting", severity = "INFO" },
}

-- The one body template, and the texts RLRM looks up without our mod name.
EqMessages.TEXT = "eqText"
EqMessages.TEXT_KEYS = {
    "rl_message_eqText",
    "rl_messageTitle_eqCompetition",
    "rl_messageTitle_eqInjury",
    "rl_messageTitle_eqRetirement",
    "rl_messageTitle_eqDealer",
    "rl_messageTitle_eqTransport",
    "rl_messageTitle_eqHosting",
}

EqMessages.isInstalled = false


--- Add our ids to RLRM's RLMessage and our texts to the global table RLRM reads them from.
--- Run once RLRM is found.
--- @return boolean ok
function EqMessages.install()
    local messages = EqRLRM.get("RLMessage")
    local constants = EqRLRM.get("RLConstants")
    local severity = constants ~= nil and constants.SEVERITY or nil
    if type(messages) ~= "table" or type(severity) ~= "table" then
        Log:warning("RLRM's message log was not found; horse events won't be logged there.")
        return false
    end

    for id, kind in pairs(EqMessages.TYPES) do
        messages[id] = { text = EqMessages.TEXT, title = kind.title, severity = severity[kind.severity] or severity.INFO }
    end
    EqMessages.copyTexts()
    EqMessages.isInstalled = true
    return true
end


--- Share our message texts with RLRM, which looks them up without a mod name (see EqI18N).
function EqMessages.copyTexts()
    EqI18N.share(EqMessages.TEXT_KEYS)
end


--- @param placeable table|nil
--- @return boolean true for a husbandry that keeps an RLRM message log
local function hasLog(placeable)
    return type(placeable) == "table" and placeable.addRLMessage ~= nil
end


--- The husbandry whose log a line goes in: the horse's own, else the farm's first with horses,
--- else the farm's first of any kind.
--- @param farmId number
--- @param animal table|nil RLRM Animal
--- @return table|nil husbandry placeable
function EqMessages.husbandryFor(farmId, animal)
    local cluster = animal ~= nil and animal.clusterSystem or nil
    if cluster ~= nil and hasLog(cluster.owner) then return cluster.owner end

    local query = EqRLRM.get("RLAnimalQuery")
    if query == nil or query.listHusbandriesForFarm == nil then return nil end

    local first = nil
    for _, husbandry in ipairs(query.listHusbandriesForFarm(farmId) or {}) do
        if hasLog(husbandry) then
            first = first or husbandry
            local spec = husbandry.spec_husbandryAnimals
            for _, other in pairs(spec ~= nil and spec.getClusters ~= nil and spec:getClusters() or {}) do
                if other.isHorse ~= nil and other:isHorse() then return husbandry end
            end
        end
    end
    return first
end


--- Write one line in a farm's message log. Server only: RLRM sends the line on to the clients.
--- @param farmId number
--- @param id string one of EqMessages.TYPES
--- @param text string the finished sentence
--- @param animal table|nil RLRM Animal the line is about
--- @param horseId string|nil the horse whose results the line links to
function EqMessages.post(farmId, id, text, animal, horseId)
    if not EqMessages.isInstalled or EqMessages.TYPES[id] == nil or text == nil then return end
    if g_currentMission == nil or (g_currentMission.getIsServer ~= nil and not g_currentMission:getIsServer()) then return end

    local husbandry = EqMessages.husbandryFor(farmId, animal)
    if husbandry == nil then return end

    local identifiers = nil
    if animal ~= nil and animal.getIdentifiers ~= nil then
        local ok, value = EqLog.try("EqMessages.post getIdentifiers", animal.getIdentifiers, animal)
        if ok then identifiers = value end
    end
    local args = { text }
    if horseId ~= nil then args[2] = EqMessages.linkFor(horseId) end
    husbandry:addRLMessage(id, identifiers, args)
end


EqMessages.LINK_PREFIX = "eqHorse:"


--- @param horseId string
--- @return string link the hidden argument a result line carries
function EqMessages.linkFor(horseId)
    return EqMessages.LINK_PREFIX .. horseId
end


--- @param args table|nil a logged line's arguments
--- @return string|nil horseId the horse the line links to
function EqMessages.linkedHorse(args)
    local link = type(args) == "table" and args[2] or nil
    if type(link) ~= "string" or link:sub(1, #EqMessages.LINK_PREFIX) ~= EqMessages.LINK_PREFIX then return nil end
    local id = link:sub(#EqMessages.LINK_PREFIX + 1)
    return id ~= "" and id or nil
end

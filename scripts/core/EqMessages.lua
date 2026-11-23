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
    EQ_QUARANTINE_DONE = { title = "eqTransport", severity = "SUCCESS" },
    EQ_HOST_OPENED = { title = "eqHosting", severity = "INFO" },
    EQ_HOST_WARNING = { title = "eqHosting", severity = "WARNING" },
    EQ_HOST_CANCELLED = { title = "eqHosting", severity = "WARNING" },
    EQ_HOST_DONE = { title = "eqHosting", severity = "SUCCESS" },
    EQ_HOST_WEATHER = { title = "eqHosting", severity = "WARNING" },
    EQ_HOST_RIDDEN = { title = "eqHosting", severity = "INFO" },
    EQ_SPONSOR_OFFERS = { title = "eqSponsor", severity = "INFO" },
    EQ_SPONSOR_SIGNED = { title = "eqSponsor", severity = "SUCCESS" },
    EQ_SPONSOR_PAID = { title = "eqSponsor", severity = "SUCCESS" },
    EQ_SPONSOR_WARNING = { title = "eqSponsor", severity = "WARNING" },
    EQ_SPONSOR_ENDED = { title = "eqSponsor", severity = "NOTICE" },
    EQ_SPONSOR_LOAN = { title = "eqSponsor", severity = "SUCCESS" },
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
    "rl_messageTitle_eqSponsor",
}

EqMessages.isInstalled = false
--- Without RLRM: our own log, newest last, shown on the Messages tab of our menu (EqMenu) and
--- as the game's notifications. Saved in rlEquestrian.xml.
EqMessages.ownLog = false
EqMessages.lines = {}
EqMessages.MAX_LINES = 200
EqMessages.NOTIFICATION = { SUCCESS = "INGAME_NOTIFICATION_OK", INFO = "INGAME_NOTIFICATION_INFO",
    NOTICE = "INGAME_NOTIFICATION_INFO", WARNING = "INGAME_NOTIFICATION_CRITICAL" }


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


--- Keep our own log instead of RLRM's. Run once, without RLRM.
function EqMessages.installOwn()
    EqMessages.ownLog = true
    EqMessages.isInstalled = true
    EqMessages.lines = {}
end


--- @return string text the l10n title of a message id
function EqMessages.titleOf(id)
    local kind = EqMessages.TYPES[id]
    return kind ~= nil and g_i18n:getText("rl_messageTitle_" .. kind.title) or ""
end


--- Add a line to our own log and show it as a notification.
--- @param farmId number
--- @param id string
--- @param text string
--- @param horseId string|nil
function EqMessages.addOwn(farmId, id, text, horseId)
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    table.insert(EqMessages.lines, { farmId = farmId, id = id, text = text, horseId = horseId,
        day = environment ~= nil and environment.currentMonotonicDay or 0,
        period = environment ~= nil and environment.currentPeriod or nil,
        dayInPeriod = environment ~= nil and environment.currentDayInPeriod or nil,
        year = environment ~= nil and environment.currentYear or nil })
    while #EqMessages.lines > EqMessages.MAX_LINES do table.remove(EqMessages.lines, 1) end

    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil
        and (g_currentMission.getFarmId == nil or g_currentMission:getFarmId() == farmId) then
        local kind = EqMessages.TYPES[id]
        local field = EqMessages.NOTIFICATION[kind ~= nil and kind.severity or "INFO"]
        local notification = FSBaseMission ~= nil and FSBaseMission[field] or nil
        if notification ~= nil then g_currentMission:addIngameNotification(notification, text) end
    end
end


--- @param farmId number
--- @return table lines the farm's lines, newest first
function EqMessages.linesFor(farmId)
    local out = {}
    for i = #EqMessages.lines, 1, -1 do
        local line = EqMessages.lines[i]
        if line.farmId == farmId then table.insert(out, line) end
    end
    return out
end


--- @param xmlFile table
--- @param key string
function EqMessages.saveToXMLFile(xmlFile, key)
    if not EqMessages.ownLog then return end
    for i, line in ipairs(EqMessages.lines) do
        local lineKey = string.format("%s.line(%d)", key, i - 1)
        xmlFile:setInt(lineKey .. "#farmId", line.farmId or 1)
        xmlFile:setString(lineKey .. "#id", line.id)
        xmlFile:setString(lineKey .. "#text", line.text)
        xmlFile:setInt(lineKey .. "#day", line.day or 0)
        if line.horseId ~= nil then xmlFile:setString(lineKey .. "#horse", line.horseId) end
        if line.period ~= nil then xmlFile:setInt(lineKey .. "#period", line.period) end
        if line.dayInPeriod ~= nil then xmlFile:setInt(lineKey .. "#dayInPeriod", line.dayInPeriod) end
        if line.year ~= nil then xmlFile:setInt(lineKey .. "#year", line.year) end
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqMessages.loadFromXMLFile(xmlFile, key)
    EqMessages.lines = {}
    if xmlFile == nil then return end
    local i = 0
    while true do
        local lineKey = string.format("%s.line(%d)", key, i)
        if not xmlFile:hasProperty(lineKey) then break end
        local id, text = xmlFile:getString(lineKey .. "#id"), xmlFile:getString(lineKey .. "#text")
        if id ~= nil and text ~= nil then
            table.insert(EqMessages.lines, { farmId = xmlFile:getInt(lineKey .. "#farmId", 1), id = id, text = text,
                day = xmlFile:getInt(lineKey .. "#day", 0), horseId = xmlFile:getString(lineKey .. "#horse"),
                period = xmlFile:getInt(lineKey .. "#period"), dayInPeriod = xmlFile:getInt(lineKey .. "#dayInPeriod"),
                year = xmlFile:getInt(lineKey .. "#year") })
        end
        i = i + 1
    end
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
    if EqMessages.ownLog then
        EqMessages.addOwn(farmId, id, text, horseId)
        return
    end

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

--[[
    EqInjury.lua
    Competition injuries as Realistic Livestock conditions.

    An injury is a disease from data/injuries.xml added to RLRM's own disease registry, so it
    shows on the horse's Diseases page. There the player starts treatment (heals sooner, billed
    monthly by RLRM as medicine), leaves it to heal untreated (free, slower) or culls the horse.
    The injuries are written so they cannot spread, never kill and never start on their own:
    only an event hands one out. RLRM counts the time in daily ticks, so an injury lasts its
    months whatever day of the month it happened.

    record.injury stays the "this horse is hurt" marker the rest of the mod reads:
        { name, rlrm = true }       RLRM's record holds the clock
        { name, untilDay = n }      our own day clock: RLRM's diseases are switched off (its
                                    disease setting is "Off"), so there is no Diseases page and
                                    no bill, just rest
    The daily check moves an injury between the two when the setting changes, and clears the
    marker once the horse has healed.

    Retiring a hurt horse cuts its treatment fee to RETIRED_FEE_SHARE: while RLRM bills, shows
    or confirms a course for a retired horse, the model's treatment block is swapped for a
    cheaper copy. The Diseases dialog also gets a Retire button. A farm vet (EqStaff.careFactor)
    cuts the fee the same way, and shortens the rest from the day of the injury.
]]

EqInjury = {}

local Log = EqLog

EqInjury.TITLE_PREFIX = "eqInjury"
--- A retired horse's treatment costs this share of the full fee.
EqInjury.RETIRED_FEE_SHARE = 0.4
--- A start at an event carries this many months' worth of an RLRM horse disease's own
--- monthly chance (colic, in RLRM 1.4.2), times the trip's injury factor.
EqInjury.EVENT_ILLNESS_MONTHS = 3
--- Resting an injury always takes at least this many days, so at one day a month treatment
--- (a day) still beats resting a one-month injury.
EqInjury.MIN_REST_DAYS = 2

--- name -> { title, restMonths, treatMonths, cost, treatDays }, read from data/injuries.xml.
--- treatDays (nil for most) makes the course that many days at a flat fee of cost.
EqInjury.info = {}
--- name -> RLRM's parsed model, once registered
EqInjury.models = {}
EqInjury.xmlPath = nil
EqInjury.installed = false
--- True while an event hands out an illness (see rollIllness)
EqInjury.catching = false


--- @param name string injury name from events.xml, e.g. "soreBack"
--- @return string title RLRM disease title, e.g. "eqInjurySoreBack"
function EqInjury.titleFor(name)
    return EqInjury.TITLE_PREFIX .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end


--- @param title string|nil an RLRM disease title
--- @return string|nil name the injury name, nil for a disease that is not one of ours
function EqInjury.nameFor(title)
    if type(title) ~= "string" or string.sub(title, 1, #EqInjury.TITLE_PREFIX) ~= EqInjury.TITLE_PREFIX then return nil end
    local rest = string.sub(title, #EqInjury.TITLE_PREFIX + 1)
    if rest == "" then return nil end
    return string.lower(string.sub(rest, 1, 1)) .. string.sub(rest, 2)
end


--- Read the injuries' healing times and fees. Works on the game's XMLFile and the tests' stand-in.
--- @param xmlFile table open data/injuries.xml
--- @return table info name -> { title, restMonths, treatMonths, cost, treatDays }
function EqInjury.readInfo(xmlFile)
    local info = {}
    local i = 0
    while true do
        local key = string.format("diseases.disease(%d)", i)
        if not xmlFile:hasProperty(key) then break end
        local title = xmlFile:getString(key .. "#title")
        local name = EqInjury.nameFor(title)
        if name ~= nil then
            info[name] = {
                title = title,
                restMonths = xmlFile:getFloat(key .. ".model#durationMonths", 1),
                treatMonths = xmlFile:getFloat(key .. ".model.treatment#months", 1),
                cost = xmlFile:getFloat(key .. ".model.treatment#cost", 0),
                treatDays = xmlFile:getInt(key .. ".model.treatment#days"),
            }
        end
        i = i + 1
    end
    return info
end


--- @param modDirectory string
function EqInjury.loadConfig(modDirectory)
    EqInjury.xmlPath = modDirectory .. "data/injuries.xml"
    local xmlFile = XMLFile.load("eqInjuries", EqInjury.xmlPath)
    if xmlFile == nil then
        Log:error("EqInjury: could not read %s", EqInjury.xmlPath)
        return
    end
    EqInjury.info = EqInjury.readInfo(xmlFile)
    xmlFile:delete()
end


-- SECTION: the clock maths. Pure, so the tests can reach it.

--- Whole months left, as the status lines show them (at least 1 while hurt).
--- @param months number
--- @return number
function EqInjury.wholeMonths(months)
    return math.max(1, math.ceil(months - 1e-3))
end


--- Months left on an RLRM record: the course when one is running, the rest otherwise.
--- @param disease table RLRM disease record
--- @param restMonths number the model's durationMonths
--- @return number months
function EqInjury.monthsLeftOnRecord(disease, restMonths)
    if disease.treatmentRunning and (disease.treatmentMonthsRemaining or 0) > 0 then
        return disease.treatmentMonthsRemaining
    end
    return math.max(restMonths - (disease.monthsElapsed or 0), 0)
end


--- @param months number untreated healing time from data/injuries.xml
--- @param daysPerPeriod number
--- @return number months the rest, at least MIN_REST_DAYS long
function EqInjury.restFor(months, daysPerPeriod)
    return math.max(months, EqInjury.MIN_REST_DAYS / math.max(daysPerPeriod, 1))
end


--- @param untilDay number
--- @param today number
--- @param daysPerPeriod number
--- @return number months left on our own clock
function EqInjury.monthsLeftOnClock(untilDay, today, daysPerPeriod)
    return math.max(untilDay - today, 0) / math.max(daysPerPeriod, 1)
end


--- @param months number
--- @param today number
--- @param daysPerPeriod number
--- @return number untilDay the day the rest is over
function EqInjury.clockFor(months, today, daysPerPeriod)
    return today + math.max(1, math.ceil(months * math.max(daysPerPeriod, 1) - 1e-6))
end


--- @param cost number the full monthly fee
--- @param retired boolean
--- @param care number|nil the farm vet's factor (EqStaff.careFactor), 1 without a vet
--- @return number fee
function EqInjury.fee(cost, retired, care)
    local share = (retired and EqInjury.RETIRED_FEE_SHARE or 1) * (care or 1)
    if share >= 1 then return cost end
    return math.floor(cost * share + 0.5)
end


--- The farm vet's factor on this horse's rest and fees.
--- @param animal table|nil
--- @return number care 1 without a vet
function EqInjury.careOf(animal)
    if EqStaffManager == nil or animal == nil then return 1 end
    return EqStaff.careFactor(EqStaffManager.strength(EqFacilityHooks.farmOfAnimal(animal), "veterinary"))
end


-- SECTION: RLRM access

local function env() return EqRLRM.env end

--- @return table|nil manager RLRM's disease manager, once its map has loaded
local function manager()
    local e = env()
    return e ~= nil and e.g_diseaseManager or nil
end


local function today()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    return environment ~= nil and (environment.currentMonotonicDay or 0) or 0
end


local function daysPerPeriod()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    return environment ~= nil and (environment.daysPerPeriod or 1) or 1
end


--- @param name string injury name
--- @return number months its untreated rest at the current days per month
function EqInjury.restMonths(name)
    local info = EqInjury.info[name]
    return EqInjury.restFor(info ~= nil and info.restMonths or 1, daysPerPeriod())
end


--- @return boolean on true when RLRM's diseases are on and our injuries are in its registry
function EqInjury.rlrmReady()
    local m = manager()
    return m ~= nil and m.diseasesEnabled == true and next(EqInjury.models) ~= nil
end


--- Add our injuries to RLRM's registry. Builds a new registry table rather than adding to
--- RLRM's in place: RLRM caches its sorted title list and spread entries by the table's
--- identity, so an in-place add would leave those stale.
--- @param m table RLRM's DiseaseManager
function EqInjury.register(m)
    local e = env()
    if m == nil or e == nil or e.RLDiseaseDefinition == nil or EqInjury.xmlPath == nil then return end

    local xmlFile = XMLFile.loadIfExists("eqInjuries", EqInjury.xmlPath)
    if xmlFile == nil then
        Log:error("EqInjury: could not read %s; injuries stay on our own clock", EqInjury.xmlPath)
        return
    end
    local parsed, warnings = e.RLDiseaseDefinition.parse(xmlFile, { animalTypes = AnimalType, i18n = g_i18n })
    xmlFile:delete()
    for _, warning in ipairs(warnings or {}) do
        Log:warning("EqInjury: %s (%s) - %s", tostring(warning.rule), tostring(warning.title), tostring(warning.detail))
    end

    local registry, count = {}, 0
    for title, model in pairs(m.diseases or {}) do registry[title] = model end
    EqInjury.models = {}
    for title, model in pairs(parsed or {}) do
        local name = EqInjury.nameFor(title)
        if name ~= nil then
            -- RLRM's own screens read model.name, and some look texts up globally, so the
            -- display names are copied into the global table as well.
            if g_i18n:hasText(model.key) then
                model.name = g_i18n:getText(model.key)
                _G.g_i18n.texts[model.key] = model.name
            end
            registry[title] = model
            EqInjury.models[name] = model
            count = count + 1
        end
    end
    m.diseases = registry
    Log:info("EqInjury: %d injuries added to Realistic Livestock's diseases", count)
end


--- @param text any a disease's display name, as RLRM's messages carry it
--- @return boolean true for one of our injuries
function EqInjury.isInjuryName(text)
    if type(text) ~= "string" then return false end
    for _, model in pairs(EqInjury.models) do
        if model.name == text then return true end
    end
    return false
end


--- @param animal table RLRM Animal
--- @param name string injury name
--- @return table|nil disease the RLRM record of that injury
function EqInjury.findRecord(animal, name)
    if animal == nil or animal.diseases == nil then return nil end
    local title = EqInjury.titleFor(name)
    for _, disease in ipairs(animal.diseases) do
        if disease.title == title then return disease end
    end
    return nil
end


local function removeRecord(animal, disease)
    for i, other in ipairs(animal.diseases or {}) do
        if other == disease then
            if animal.setDirty ~= nil then animal:setDirty() end
            table.remove(animal.diseases, i)
            return
        end
    end
end


local function isHurt(disease)
    local state = disease.state
    return state == "INFECTIOUS" or state == "EXPOSED"
end


--- Put the injury on RLRM's books.
--- @param animal table
--- @param name string
--- @param monthsLeft number|nil rest still to serve; nil for a fresh injury
--- @return boolean ok
local function contract(animal, name, monthsLeft)
    local m, model = manager(), EqInjury.models[name]
    if m == nil or model == nil or animal == nil or animal.diseases == nil then return false end

    -- A healed record waits a day before RLRM clears it, and would block a new one.
    local old = EqInjury.findRecord(animal, name)
    if old ~= nil then removeRecord(animal, old) end

    m:contractDisease(animal, model)
    local disease = EqInjury.findRecord(animal, name)
    if disease == nil then return false end
    -- Not ticked on the day it happened (see the Disease.onDayChanged hook).
    disease.eqStartDay = today()
    if monthsLeft ~= nil then
        disease.monthsElapsed = math.max(EqInjury.restMonths(name) - monthsLeft, 0)
    end
    return true
end


--- A horse was hurt at an event: give it the injury.
--- @param record table EqHorseRecord
--- @param animal table RLRM Animal
--- @param name string injury name
--- @return boolean onRLRM true when it is on the Diseases page, false when it rests on our clock
function EqInjury.start(record, animal, name)
    -- The farm's vet shortens the rest; on RLRM's books that is a head start on the months.
    local care = EqInjury.careOf(animal)
    local rest = EqInjury.restMonths(name) * care
    if EqInjury.rlrmReady() and contract(animal, name, care < 1 and rest or nil) then
        record.injury = { name = name, rlrm = true }
        return true
    end
    record.injury = { name = name, untilDay = EqInjury.clockFor(rest, today(), daysPerPeriod()) }
    return false
end


--- @param record table EqHorseRecord
--- @param animal table|nil RLRM Animal
--- @return number|nil months whole months left, nil when the horse is not hurt
function EqInjury.monthsLeft(record, animal)
    local injury = record.injury
    if injury == nil then return nil end
    if injury.rlrm then
        local disease = EqInjury.findRecord(animal, injury.name)
        if disease == nil then return 1 end
        return EqInjury.wholeMonths(EqInjury.monthsLeftOnRecord(disease, EqInjury.restMonths(injury.name)))
    end
    if injury.untilDay == nil then return EqInjury.wholeMonths(injury.monthsLeft or 1) end
    return EqInjury.wholeMonths(EqInjury.monthsLeftOnClock(injury.untilDay, today(), daysPerPeriod()))
end


--- The daily check for one horse: keep its injury on the right clock, and say when it healed.
--- @param record table EqHorseRecord
--- @param animal table RLRM Animal
--- @return boolean healed true on the day the injury is over
function EqInjury.daily(record, animal)
    local injury = record.injury
    if injury == nil then return false end
    local day, dpp = today(), daysPerPeriod()
    local ready = EqInjury.rlrmReady()

    if injury.rlrm then
        local disease = EqInjury.findRecord(animal, injury.name)
        if disease == nil or not isHurt(disease) then
            record.injury = nil
            return true
        end
        if not ready then
            -- RLRM's diseases were switched off: its records stop ticking, so carry on resting.
            local months = EqInjury.monthsLeftOnRecord(disease, EqInjury.restMonths(injury.name))
            removeRecord(animal, disease)
            record.injury = { name = injury.name, untilDay = EqInjury.clockFor(months, day, dpp) }
        end
        return false
    end

    -- Saves from before this clock kept whole months left.
    if injury.untilDay == nil then injury.untilDay = EqInjury.clockFor(injury.monthsLeft or 1, day, dpp) end
    injury.monthsLeft = nil

    if day >= injury.untilDay then
        record.injury = nil
        return true
    end
    if ready and contract(animal, injury.name, EqInjury.monthsLeftOnClock(injury.untilDay, day, dpp)) then
        record.injury = { name = injury.name, rlrm = true }
    end
    return false
end


-- SECTION: illness at events

--- @param animal table|nil RLRM Animal
--- @return boolean true while it shows one of RLRM's diseases (our injuries don't count: the
---         horse's record says when it is hurt)
function EqInjury.isSick(animal)
    local m, e = manager(), env()
    if m == nil or e == nil or not m.diseasesEnabled or animal == nil or type(animal.diseases) ~= "table" then return false end
    for _, disease in ipairs(animal.diseases) do
        if EqInjury.nameFor(disease.title) == nil and disease.archetype ~= "genetic" then
            if e.RLDiseaseStatus ~= nil and e.RLDiseaseStatus.isDiseased ~= nil then
                if e.RLDiseaseStatus.isDiseased(disease) then return true end
            elseif disease.state == "INFECTIOUS" then
                return true
            end
        end
    end
    return false
end


--- RLRM's monthly chance for an age, from a model's <infection> keys (each key's ageMonths is
--- the top of its band; the last key covers every age after it).
--- @param infection table|nil array of { ageMonths, perMonth }
--- @param ageMonths number
--- @return number perMonth
function EqInjury.monthlyChance(infection, ageMonths)
    if type(infection) ~= "table" or #infection == 0 then return 0 end
    for _, key in ipairs(infection) do
        if ageMonths <= key.ageMonths then return key.perMonth end
    end
    return infection[#infection].perMonth
end


--- @param model table RLRM disease model
--- @return boolean true for one of RLRM's own horse diseases an event can pass on
local function isHorseIllness(model)
    if model.archetype == "genetic" or EqInjury.nameFor(model.title) ~= nil then return false end
    for _, typeName in ipairs(model.animals or {}) do
        if typeName == "HORSE" then return true end
    end
    return false
end


--- Roll RLRM's horse diseases for one start: the travel, the crowd and the stress of a show.
--- @param animal table RLRM Animal
--- @param travel number the trip's injury factor (1 at home)
--- @param rng table EqRandom
--- @return table names display names of what it caught (usually none)
function EqInjury.rollIllness(animal, travel, rng)
    local caught = {}
    local m, e = manager(), env()
    if m == nil or e == nil or not m.diseasesEnabled or animal == nil or animal.diseases == nil then return caught end

    local scale = 1
    if e.RLDiseaseDifficulty ~= nil then
        local preset = e.RLDiseaseDifficulty.getPreset(m.diseaseDifficulty)
        scale = preset ~= nil and preset.infection or 1
    end

    local titles = {}
    for title, model in pairs(m.diseases) do
        if isHorseIllness(model) then table.insert(titles, title) end
    end
    table.sort(titles)

    for _, title in ipairs(titles) do
        local model = m.diseases[title]
        -- Drawn for every title, so whether one is switched off never shifts the others.
        local roll = rng:next()
        local enabled = m.isTitleEnabled == nil or m:isTitleEnabled(title)
        local eligible = e.RLDiseaseSpread == nil or e.RLDiseaseSpread.isEligible(animal, title, model)
        local chance = math.min(EqInjury.monthlyChance(model.infection, animal.age or 0) * scale
            * EqInjury.EVENT_ILLNESS_MONTHS * (travel or 1), 1)
        if enabled and eligible and roll < chance then
            EqInjury.catching = true
            local ok, err = EqLog.try("EqInjury.rollIllness contractDisease", m.contractDisease, m, animal, model)
            EqInjury.catching = false
            if not ok then error(err, 0) end
            table.insert(caught, model.name or title)
            Log:debug("EqInjury: %s caught %s at an event (chance %.4f)", tostring(animal.uniqueId), title, chance)
        end
    end
    return caught
end


-- SECTION: hooks on RLRM

--- @param animal table|nil
--- @return table|nil record the horse's record, nil for anything that is not one of our horses
local function recordOf(animal)
    return EqRegistry.getOrCreate(animal)
end


--- @param model table|nil RLRM disease model
--- @return table|nil info our info for an injury model, nil for any other disease
local function infoOf(model)
    local name = model ~= nil and EqInjury.nameFor(model.title) or nil
    return name ~= nil and EqInjury.info[name] or nil
end


--- The fee a horse pays for a course of this injury: per month, or flat for a day course.
--- @param model table RLRM injury model
--- @param animal table|nil
--- @return number fee
local function feeFor(model, animal)
    local record = recordOf(animal)
    return EqInjury.fee(model.treatment.cost, record ~= nil and record.retired, EqInjury.careOf(animal))
end


--- Run fn with this horse's terms on the model's treatment block, then put it back: a retired
--- horse's cheaper fee, and for a day course (when billing) the monthly cost that bills its flat
--- fee over its days. The model is shared by every horse with that injury, so the swap lasts
--- only for the call.
--- @param model table|nil RLRM disease model
--- @param animal table|nil the animal the call is about
--- @param billing boolean true for RLRM's daily tick
local function withHorseTerms(model, animal, billing, fn, ...)
    local info = infoOf(model)
    if info == nil or model.treatment == nil then return fn(...) end
    local record = recordOf(animal)
    local retired = record ~= nil and record.retired
    local care = EqInjury.careOf(animal)
    if not retired and care >= 1 and not (billing and info.treatDays ~= nil) then return fn(...) end

    local full = model.treatment
    local terms = {}
    for key, value in pairs(full) do terms[key] = value end
    terms.cost = EqInjury.fee(full.cost, retired, care)
    if billing and info.treatDays ~= nil then terms.cost = terms.cost / info.treatDays * daysPerPeriod() end
    model.treatment = terms
    return EqLog.finally(function() model.treatment = full end, fn, ...)
end


--- A day course is seeded by RLRM as its one-month minimum; cut it to its days.
--- @param disease table RLRM disease record
local function shortenDayCourse(disease)
    local info = infoOf(disease.model)
    if info == nil or info.treatDays == nil or not disease.treatmentRunning then return end
    local days = info.treatDays / daysPerPeriod()
    if (disease.treatmentMonthsRemaining or 0) > days + 1e-6 then disease.treatmentMonthsRemaining = days end
end


--- @param days number
--- @return string text "1 day", "3 days"
local function daysText(days)
    return string.format(g_i18n:getText(days == 1 and "eq_ui_dayCount" or "eq_ui_days"), days)
end


--- The Diseases dialog's extra button: Retire. Retirement is for good, so a retired horse has no
--- button (only the eqRetire undo debug command brings one back).
local function updateRetireButton(dialog)
    local button = dialog.eqRetireButton
    if button == nil then return end
    local record = recordOf(dialog.animal)
    local shown = record ~= nil and not record.retired
    button:setVisible(shown)
    if dialog.eqRetireSeparator ~= nil then dialog.eqRetireSeparator:setVisible(shown) end
    if shown then button:setText(g_i18n:getText("eq_ui_retire")) end
    if button.parent ~= nil and button.parent.invalidateLayout ~= nil then button.parent:invalidateLayout() end
end


local function addRetireButton(dialog)
    if dialog.eqRetireButton ~= nil or dialog.cullButton == nil then return end
    local box = dialog.cullButton.parent
    if box == nil then return end

    -- A separator like the ones between RLRM's buttons, then the button, at the end of the row.
    for _, element in ipairs(box.elements or {}) do
        if element ~= dialog.cullButton and element.profile == "fs25_dialogButtonBoxSeparator" then
            dialog.eqRetireSeparator = element:clone(box, false, true)
            break
        end
    end
    local button = dialog.cullButton:clone(box, false, true)
    -- Its own key (not Cull's), so one press can't do both.
    if button.applyProfile ~= nil then button:applyProfile("buttonExtra1") end
    button.onClickCallback = EqInjury.onClickRetire
    button.target = dialog
    button:setDisabled(false)
    dialog.eqRetireButton = button
end


--- The Retire button: warn that it is permanent, then retire the horse.
--- @param dialog table RLRM's DiseaseDialog
function EqInjury.onClickRetire(dialog)
    local record = recordOf(dialog.animal)
    if record == nil or record.retired then return end
    local name = dialog.animal.getName ~= nil and dialog.animal:getName() or record.id
    local text = string.format(g_i18n:getText(record.injury ~= nil and "eq_ui_retireConfirmInjured" or "eq_ui_retireConfirm"),
        name, math.floor((1 - EqInjury.RETIRED_FEE_SHARE) * 100 + 0.5))
    YesNoDialog.show(EqInjury.onRetireConfirmed, dialog, text, g_i18n:getText("eq_ui_retire"), nil, nil,
        DialogElement.TYPE_QUESTION)
end


--- @param dialog table RLRM's DiseaseDialog
--- @param yes boolean
function EqInjury.onRetireConfirmed(dialog, yes)
    if not yes then return end
    local record = recordOf(dialog.animal)
    if record == nil or record.retired then return end
    local _, message = EqCompetitionManager.setRetired(record, true)
    if message ~= nil then g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, message) end
    -- The fees on the rows follow the retirement.
    if dialog.rebuildRows ~= nil then dialog:rebuildRows() end
    updateRetireButton(dialog)
end


--- Hook RLRM: our injuries in its registry, the retired fee, and the dialog's Retire button.
--- @param guarded function main.lua's error guard
function EqInjury.install(guarded)
    if EqInjury.installed then return end
    local e = env()
    if e == nil or e.DiseaseManager == nil or e.Disease == nil then
        Log:warning("EqInjury: Realistic Livestock's disease system is missing; injuries rest on our own clock")
        return
    end
    EqInjury.installed = true

    -- RLRM builds its manager, and loads its registry, when its map loads: after us.
    e.DiseaseManager.loadDiseases = Utils.appendedFunction(e.DiseaseManager.loadDiseases, function(m)
        guarded("injury registry", function() EqInjury.register(m) end)
    end)
    if e.g_diseaseManager ~= nil then EqInjury.register(e.g_diseaseManager) end

    -- RLRM's daily tick of one record. For our injuries:
    -- - none on the day it happened: an event can run before or after the pen's tick that day,
    --   and at one day a month that tick alone would heal a one-month injury before the player
    --   ever saw it;
    -- - a day course is cut to its days, and a retired horse pays less (RLRM bills each served
    --   day model.treatment.cost / daysPerPeriod);
    -- - a healed injury is removed at once, rather than sitting on the page as "Immune";
    -- - resting takes at least MIN_REST_DAYS.
    local original = e.Disease.onDayChanged
    -- The rest's minimum days go on the shared model for the call only, like withHorseTerms.
    local function onDayChanged(disease, ...)
        local name = EqInjury.nameFor(disease.title)
        local model = disease.model
        if name == nil or model == nil or model.durationMonths == nil then return original(disease, ...) end
        local authored = model.durationMonths
        model.durationMonths = EqInjury.restMonths(name)
        return EqLog.finally(function() model.durationMonths = authored end, original, disease, ...)
    end
    local INSTRUCTION = e.RLDiseaseProgression ~= nil and e.RLDiseaseProgression.INSTRUCTION or nil
    local NO_TREATMENT = e.RLDiseaseRecord ~= nil and e.RLDiseaseRecord.TREATMENT_RESULT.NONE or nil
    e.Disease.onDayChanged = function(disease, animal, ...)
        local ours = EqInjury.nameFor(disease.title) ~= nil
        if ours and INSTRUCTION ~= nil and disease.eqStartDay == today() then
            return INSTRUCTION.KEEP, 0, NO_TREATMENT
        end
        shortenDayCourse(disease)
        local instruction, cost, result = withHorseTerms(disease.model, animal, true, onDayChanged, disease, animal, ...)
        if ours and INSTRUCTION ~= nil and instruction == INSTRUCTION.KEEP and disease.state == "RECOVERED" then
            instruction = INSTRUCTION.REMOVE
        end
        return instruction, cost, result
    end

    -- RLRM logs "Contracted" and "Cured" for every disease; ours already log the injury (with
    -- what treatment costs) and the recovery, and where an illness was caught, so RLRM's
    -- matching lines are dropped. Its "Cured" line for an illness stays: we don't post one.
    if e.Animal ~= nil and e.Animal.addMessage ~= nil then
        local addMessage = e.Animal.addMessage
        local quiet = { DISEASE_CONTRACTED = true, DISEASE_CURED = true }
        e.Animal.addMessage = function(animal, id, args, ...)
            if quiet[id] and type(args) == "table" and EqInjury.isInjuryName(args[1]) then return end
            -- An illness from an event: our own line says where it was caught.
            if id == "DISEASE_CONTRACTED" and EqInjury.catching then return end
            return addMessage(animal, id, args, ...)
        end
    end

    local dialog = e.DiseaseDialog
    if dialog == nil then return end

    -- The Fee column, the start and resume confirms, and the start message all read the cost.
    local populate = dialog.populateCellForItemInSection
    dialog.populateCellForItemInSection = function(self, list, section, index, cell)
        local row = self.rows ~= nil and self.rows[index] or nil
        local model = row ~= nil and row.model or nil
        withHorseTerms(model, self.animal, false, populate, self, list, section, index, cell)
        -- A day course shows its days and its flat fee, not RLRM's month.
        local info = infoOf(model)
        local disease = row ~= nil and row.record or nil
        if info ~= nil and info.treatDays ~= nil and disease ~= nil and disease.state == "INFECTIOUS" then
            guarded("diseases dialog day course", function()
                cell:getAttribute("duration"):setText(daysText(info.treatDays))
                cell:getAttribute("fee"):setText(g_i18n:formatMoney(feeFor(model, self.animal), 0, true, true))
            end)
        end
    end
    local confirmTreatment = dialog.confirmTreatment
    dialog.confirmTreatment = function(self, disease, action)
        local model = disease ~= nil and disease.model or nil
        local info = infoOf(model)
        if info ~= nil and info.treatDays ~= nil and action ~= "stop" then
            local name = self.animal ~= nil and self.animal.getName ~= nil and self.animal:getName() or ""
            local text = string.format(g_i18n:getText("eq_ui_dayTreatmentConfirm"), name, model.name,
                daysText(info.treatDays), g_i18n:formatMoney(feeFor(model, self.animal), 0, true, true))
            YesNoDialog.show(self.onTreatmentConfirmed, self, text, g_i18n:getText("rl_ui_startTreatment"), nil, nil,
                DialogElement.TYPE_QUESTION, nil, nil, { title = disease.title, action = action })
            return
        end
        return withHorseTerms(model, self.animal, false, confirmTreatment, self, disease, action)
    end
    local onTreatmentConfirmed = dialog.onTreatmentConfirmed
    dialog.onTreatmentConfirmed = function(self, yes, args)
        local m = manager()
        local model = (m ~= nil and args ~= nil) and m:getDiseaseByTitle(args.title) or nil
        withHorseTerms(model, self.animal, false, onTreatmentConfirmed, self, yes, args)
        local disease = (self.animal ~= nil and args ~= nil and self.animal.getDisease ~= nil)
            and self.animal:getDisease(args.title) or nil
        if disease ~= nil then shortenDayCourse(disease) end
    end

    dialog.onOpen = Utils.appendedFunction(dialog.onOpen, function(self)
        guarded("diseases dialog retire button", function()
            addRetireButton(self)
            updateRetireButton(self)
        end)
    end)
end

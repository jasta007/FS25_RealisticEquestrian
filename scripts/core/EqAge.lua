--[[
    EqAge.lua
    Horse ages as years and months instead of a bare month count (James, 2026-11-22).

    Panels, messages and RLRM's screens read "3 years, 4 months"; tight columns read "3y 4m".
    Under a year it is months only, and on a birthday years only. RLRM and the base game keep
    showing months for every other animal: the hooks below only touch a horse's age line.
]]

EqAge = {}


--- @param months number|nil age in months
--- @return number years
--- @return number months the months past the last birthday
function EqAge.split(months)
    local total = math.max(0, math.floor((tonumber(months) or 0) + 1e-6))
    return math.floor(total / 12), total % 12
end


--- The years text key for a count. Czech, Polish, Russian and Ukrainian use a separate form
--- for 2-4 (but not 12-14); every other language gives eq_age_yearsFew the same text as
--- eq_age_years.
--- @param years number
--- @return string key
function EqAge.yearsKey(years)
    if years == 1 then return "eq_age_year" end
    local ones, hundreds = years % 10, years % 100
    if ones >= 2 and ones <= 4 and (hundreds < 12 or hundreds > 14) then return "eq_age_yearsFew" end
    return "eq_age_years"
end


--- @param months number|nil
--- @return string such as "3 years, 4 months", "3 years" or "8 months"
function EqAge.long(months)
    local years, rest = EqAge.split(months)
    local monthsText = string.format(g_i18n:getText(rest == 1 and "eq_ui_time_month" or "eq_ui_time_months"), rest)
    if years == 0 then return monthsText end
    local yearsText = string.format(g_i18n:getText(EqAge.yearsKey(years)), years)
    if rest == 0 then return yearsText end
    return string.format(g_i18n:getText("eq_age_join"), yearsText, monthsText)
end


--- @param months number|nil
--- @return string such as "3y 4m", "3y" or "8m"
function EqAge.short(months)
    local years, rest = EqAge.split(months)
    if years == 0 then return string.format(g_i18n:getText("eq_ui_ageMonths"), rest) end
    if rest == 0 then return string.format(g_i18n:getText("eq_age_shortYears"), years) end
    return string.format(g_i18n:getText("eq_age_short"), years, rest)
end


--- An event tier's ages. A range that runs from one birthday to just before another reads in
--- whole years ("ages 2 to 3 years" for 24-35 months).
--- @param minAge number months
--- @param maxAge number months; 0 means no upper limit
--- @return string
function EqAge.range(minAge, maxAge)
    minAge = math.max(0, math.floor(minAge or 0))
    maxAge = math.floor(maxAge or 0)
    if maxAge <= 0 then return string.format(g_i18n:getText("eq_ui_ages_from"), EqAge.long(minAge)) end
    if minAge % 12 == 0 and (maxAge + 1) % 12 == 0 and maxAge > minAge then
        return string.format(g_i18n:getText("eq_ui_ages_rangeYears"), minAge / 12, (maxAge + 1) / 12)
    end
    return string.format(g_i18n:getText("eq_ui_ages_range"), EqAge.long(minAge), EqAge.long(maxAge))
end


--- @param animal table|nil RLRM Animal, base game cluster or anything with an age
--- @return boolean
function EqAge.isHorse(animal)
    if type(animal) ~= "table" then return false end
    if type(animal.isHorse) == "function" then
        local ok, horse = pcall(animal.isHorse, animal)
        if ok then return horse == true end
    end
    local horseType = AnimalType ~= nil and AnimalType.HORSE or nil
    if horseType == nil then return false end
    if animal.animalTypeIndex ~= nil then return animal.animalTypeIndex == horseType end
    local subType
    if type(animal.getSubType) == "function" then
        local ok, found = pcall(animal.getSubType, animal)
        if ok then subType = found end
    end
    if subType == nil and animal.subTypeIndex ~= nil and g_currentMission ~= nil and g_currentMission.animalSystem ~= nil then
        subType = g_currentMission.animalSystem:getSubTypeByIndex(animal.subTypeIndex)
    end
    return subType ~= nil and subType.typeIndex == horseType
end


--- @param animal table
--- @return number|nil months
function EqAge.of(animal)
    local age = animal.age
    if age == nil and type(animal.getAge) == "function" then age = animal:getAge() end
    return tonumber(age)
end


--- Rewrite the "Age" row of an info list for a horse, wherever its value lives.
--- @param rows table|nil list of { title, value | valueText }
--- @param animal table
--- @param field string "value" or "valueText"
function EqAge.relabelRows(rows, animal, field)
    if type(rows) ~= "table" or not EqAge.isHorse(animal) then return end
    local age = EqAge.of(animal)
    if age == nil then return end
    local title = g_i18n:getText("ui_age")
    for _, row in ipairs(rows) do
        if type(row) == "table" and row.title == title then
            row[field] = EqAge.long(age)
            return
        end
    end
end


--- Hook the screens that print a horse's age as months: the Animals page in the ESC menu, the
--- list of your own animals on the trade screen, and RLRM's own menu (which also shows the
--- dealer's horses). Call once, after every mod is sourced, as RLRM replaces AnimalItemStock.new
--- outright. RLRM's look-at-an-animal box already shows years and months, so it is left alone.
--- @param guarded function main.lua's error guard
function EqAge.install(guarded)
    if InGameMenuAnimalsFrame ~= nil and InGameMenuAnimalsFrame.displayCluster ~= nil then
        InGameMenuAnimalsFrame.displayCluster = Utils.appendedFunction(InGameMenuAnimalsFrame.displayCluster,
            function(frame, animal)
                guarded("animals page age", function()
                    if frame.animalAgeText == nil or not EqAge.isHorse(animal) then return end
                    local age = EqAge.of(animal)
                    if age ~= nil then frame.animalAgeText:setText(EqAge.long(age)) end
                end)
            end)
    end

    if AnimalItemStock ~= nil and AnimalItemStock.new ~= nil then
        local new = AnimalItemStock.new
        AnimalItemStock.new = function(animal, ...)
            local item = new(animal, ...)
            guarded("trade screen age", function()
                if item ~= nil then EqAge.relabelRows(item.infos, animal, "value") end
            end)
            return item
        end
    end

    local infoService = EqRLRM.get("RLAnimalInfoService")
    if infoService ~= nil and type(infoService.getAnimalDisplay) == "function" then
        local getAnimalDisplay = infoService.getAnimalDisplay
        infoService.getAnimalDisplay = function(animal, ...)
            local display = getAnimalDisplay(animal, ...)
            guarded("menu age", function()
                if display ~= nil then EqAge.relabelRows(display.statRows, animal, "valueText") end
            end)
            return display
        end
    end
end

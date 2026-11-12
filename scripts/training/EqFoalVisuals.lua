--[[
    EqFoalVisuals.lua
    Horses too young to ride (EqFoals.rideAge: 6 months accelerated, 12 realistic) show as foals in the pen. The base game gives every horse
    coat one visual from birth, all on $dataS horse.i3d; this swaps the HORSE type's husbandry
    config for data/foals/horseAnimals.xml (the 8 base adults unchanged, then 8 foals in the same
    coat order) and gives each horse subtype a foal visual from 0 months, its adult one after.

    Off until data/foals/foal.i3d exists, and left alone when a map or another mod has already
    replaced the horse config (anything not from dataS), so their horses are never broken.
    Runs once the animal system has loaded, before any husbandry is built, so it works the same
    with or without RLRM.
]]

EqFoalVisuals = {}
EqFoalVisuals.CONFIG = "data/foals/horseAnimals.xml"
EqFoalVisuals.MODEL = "data/foals/foal.i3d"
EqFoalVisuals.ADULTS = 8
EqFoalVisuals.applied = false
-- The adult visual of each horse subtype, whose minAge follows the Horse maturing setting (sync).
EqFoalVisuals.adults = {}

local Log = EqLog


function EqFoalVisuals.install(guarded, modDirectory)
    if not fileExists(modDirectory .. EqFoalVisuals.MODEL) then
        Log:info("Foal visuals: no foal model yet, horses keep the base look at every age")
        return
    end
    if AnimalSystem == nil or AnimalSystem.loadMapData == nil then
        Log:warning("Foal visuals: AnimalSystem.loadMapData not found")
        return
    end
    AnimalSystem.loadMapData = Utils.appendedFunction(AnimalSystem.loadMapData, function(system)
        guarded("foal visuals", function() EqFoalVisuals.apply(system, modDirectory) end)
    end)
end


--- Swap in the foal config and add the foal stage to every horse subtype.
function EqFoalVisuals.apply(system, modDirectory)
    local horse = system.nameToType ~= nil and system.nameToType.HORSE or nil
    if horse == nil then return end
    local current = tostring(horse.configFilename or "")
    if not string.startsWith(current, "dataS") then
        Log:info("Foal visuals: horse config is '%s' (a map or mod's own), foals left off", current)
        return
    end

    local previous = horse.animals
    horse.animals = {}
    local config = modDirectory .. EqFoalVisuals.CONFIG
    local ok = system:loadAnimalConfig(horse, modDirectory, config)
    if not ok or #horse.animals < EqFoalVisuals.ADULTS * 2 then
        Log:warning("Foal visuals: could not load '%s' (%d models), foals left off", config, #horse.animals)
        horse.animals = previous
        return
    end
    horse.configFilename = config

    local age = EqFoals.rideAge()
    EqFoalVisuals.adults = {}
    for _, subTypeIndex in ipairs(horse.subTypes) do
        local subType = system.subTypes[subTypeIndex]
        if subType ~= nil and subType.visuals ~= nil then
            -- the reload made new model tables, so every visual points at its new one
            for _, visual in ipairs(subType.visuals) do
                visual.visualAnimal = horse.animals[visual.visualAnimalIndex] or visual.visualAnimal
            end
            local first = subType.visuals[1]
            local index = first ~= nil and first.visualAnimalIndex or nil
            if index ~= nil and index <= EqFoalVisuals.ADULTS and (first.minAge or 0) < age then
                local foal = {}
                for k, v in pairs(first) do foal[k] = v end
                foal.minAge = 0
                foal.visualAnimalIndex = index + EqFoalVisuals.ADULTS
                foal.visualAnimal = horse.animals[foal.visualAnimalIndex]
                first.minAge = age
                table.insert(subType.visuals, 1, foal)
                table.insert(EqFoalVisuals.adults, first)
            end
        end
    end
    EqFoalVisuals.applied = true
    Log:info("Foal visuals: horses under %d months show as foals", age)
end


--- Move the foal-to-adult switch to the Horse maturing setting's age. Pens pick it up when
--- RLRM next refreshes their visuals (a horse's age changes monthly).
function EqFoalVisuals.sync()
    local age = EqFoals.rideAge()
    for _, visual in ipairs(EqFoalVisuals.adults) do visual.minAge = age end
end

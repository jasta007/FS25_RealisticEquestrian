--[[
    EqBreath.lua
    The horse's breath shows while the stamina band waits at the bottom of the bar (James,
    2026-11-03): a hit in the top band and it starts blowing, a hit in the bottom band and it
    stops, so the rider can watch the horse instead of the bar. A miss leaves it as the band's
    side says (EqTraining.staminaStep moves the band to the other end).

    The puffs are the base game's slow horse step dust (HORSE_STEP_SLOW), cloned onto each ridden
    horse the way FS25 mods clone particle systems, placed just in front of the head bone every
    frame and pulsed on and off for breaths. Emitted in world space, so at a gallop they stream
    away behind the head. Everything is wrapped so a missing node or a changed game file only
    logs a line.
]]

EqBreath = {}

local Log = EqLog

EqBreath.FILE = "$data/effects/horse/horseStepParticleSystem.i3d"
-- The slow step emitter (the second Dynamic in the file).
EqBreath.NODE = "1"
-- Bones to look for, in order; the first found carries the breath.
EqBreath.BONES = { "head", "head_jnt", "headbone", "skull", "neck2", "neck" }
-- Metres in front of the head bone along the horse's heading, and up.
EqBreath.FORWARD = 0.45
EqBreath.UP = -0.1
-- A breath: emitting on, then off, by how hard the horse is blowing: "band" while the stamina
-- band waits at the bottom, "hard" while Fatigued or Blown (James, 2026-11-03: it would be weird
-- not to), heavier and quicker.
EqBreath.STYLE = {
    band = { onMs = 380, offMs = 420, lifespan = 900, count = 1 },
    hard = { onMs = 320, offMs = 220, lifespan = 1300, count = 2.5 },
}
-- eqBreath console override: nil follows the gallop, false forces it off, a STYLE key forces it.
EqBreath.force = nil

EqBreath.reference = nil
EqBreath.failed = false
EqBreath.byVehicle = {}


local function findBone(root)
    local found = {}
    local stack = { root }
    while #stack > 0 do
        local node = table.remove(stack)
        local name = string.lower(getName(node) or "")
        if found[name] == nil then found[name] = node end
        for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
    end
    for _, wanted in ipairs(EqBreath.BONES) do
        if found[wanted] ~= nil then return found[wanted], wanted end
    end
    -- Anything with "head" in its name, else nothing.
    for name, node in pairs(found) do
        if string.find(name, "head", 1, true) then return node, name end
    end
    return nil, nil
end


--- Load the base game's step dust once, to clone from.
--- @return table|nil { root, node }
function EqBreath.ensureReference()
    if EqBreath.reference ~= nil or EqBreath.failed then return EqBreath.reference end
    local file = Utils.getFilename(EqBreath.FILE, "")
    local root = loadI3DFile(file, false, false, false)
    if root == nil or root == 0 then
        EqBreath.failed = true
        Log:info("Breath: could not load %s", tostring(file))
        return nil
    end
    local node = I3DUtil.indexToObject(root, EqBreath.NODE)
    if node == nil or node == 0 then
        EqBreath.failed = true
        Log:info("Breath: no emitter at index %s in %s", EqBreath.NODE, tostring(file))
        delete(root)
        return nil
    end
    EqBreath.reference = { root = root, node = node }
    return EqBreath.reference
end


local function attach(vehicle)
    local ref = EqBreath.ensureReference()
    if ref == nil or vehicle.rootNode == nil or vehicle.rootNode == 0 then return nil end
    local bone, boneName = findBone(vehicle.rootNode)
    local holder = createTransformGroup("eqBreath")
    link(vehicle.rootNode, holder)
    local psClone = clone(ref.node, true, false, true)
    link(holder, psClone)
    local ps = {}
    ParticleUtil.loadParticleSystemFromNode(psClone, ps, false, true, false)
    if getNumOfChildren(psClone) > 0 then ParticleUtil.setEmitterShape(ps, getChildAt(psClone, 0)) end
    ParticleUtil.setEmittingState(ps, false)
    local entry = { holder = holder, ps = ps, bone = bone, emitting = false, clock = 0 }
    Log:info("Breath: attached to %s", bone ~= nil and ("bone " .. tostring(boneName)) or "the horse's root (no head bone found)")
    return entry
end


local function place(vehicle, entry)
    local root = vehicle.rootNode
    local fx, fy, fz = localDirectionToWorld(root, 0, 0, 1)
    local x, y, z
    if entry.bone ~= nil and entityExists(entry.bone) then
        x, y, z = getWorldTranslation(entry.bone)
    else
        x, y, z = localToWorld(root, 0, 1.6, 1.1)
    end
    x, y, z = x + fx * EqBreath.FORWARD, y + fy * EqBreath.FORWARD + EqBreath.UP, z + fz * EqBreath.FORWARD
    local lx, ly, lz = worldToLocal(root, x, y, z)
    setTranslation(entry.holder, lx, ly, lz)
end


local function setEmitting(entry, on)
    if entry.emitting == on then return end
    entry.emitting = on
    ParticleUtil.setEmittingState(entry.ps, on)
end


--- One frame for a ridden horse.
--- @param vehicle table the Rideable
--- @param style string|nil "band", "hard" or nil for no breath
--- @param dt number milliseconds
function EqBreath.update(vehicle, style, dt)
    if EqBreath.force ~= nil then style = EqBreath.force or nil end
    local look = style ~= nil and EqBreath.STYLE[style] or nil
    local entry = EqBreath.byVehicle[vehicle]
    if entry ~= nil and not entityExists(entry.holder) then
        EqBreath.byVehicle[vehicle], entry = nil, nil
    end
    if entry == nil then
        if look == nil or EqBreath.failed then return end
        local ok, made = pcall(attach, vehicle)
        if not ok then
            EqBreath.failed = true
            Log:info("Breath: could not attach (%s), breath is off for this session", tostring(made))
            return
        end
        entry = made
        if entry == nil then return end
        EqBreath.byVehicle[vehicle] = entry
    end
    if look == nil then
        entry.clock = 0
        setEmitting(entry, false)
        return
    end
    if entry.style ~= style then
        entry.style = style
        ParticleUtil.setParticleLifespan(entry.ps, look.lifespan)
        ParticleUtil.setEmitCountScale(entry.ps, look.count)
    end
    place(vehicle, entry)
    -- Breaths: on, then off, round again.
    entry.clock = (entry.clock + dt) % (look.onMs + look.offMs)
    setEmitting(entry, entry.clock < look.onMs)
end


--- Stop a horse's breath (rider off).
--- @param vehicle table
function EqBreath.stop(vehicle)
    local entry = EqBreath.byVehicle[vehicle]
    if entry ~= nil and entityExists(entry.holder) then setEmitting(entry, false) end
end


--- Remove everything (mission end).
function EqBreath.reset()
    for _, entry in pairs(EqBreath.byVehicle) do
        if entityExists(entry.holder) then
            ParticleUtil.setEmittingState(entry.ps, false)
            ParticleUtil.deleteParticleSystem(entry.ps)
            delete(entry.holder)
        end
    end
    EqBreath.byVehicle = {}
    if EqBreath.reference ~= nil and entityExists(EqBreath.reference.root) then delete(EqBreath.reference.root) end
    EqBreath.reference, EqBreath.failed = nil, false
end

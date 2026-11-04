--[[
    EqBreath.lua
    The horse's breath shows while the stamina band waits at the bottom of the bar (James,
    2026-11-03): a hit in the top band and it starts blowing, a hit in the bottom band and it
    stops, so the rider can watch the horse instead of the bar. A miss leaves it as the band's
    side says (EqTraining.staminaStep moves the band to the other end). Fatigued or Blown, it
    blows hard: bigger puffs, a little quicker, blown out faster.

    The nostrils follow the head (James, 2026-11-04: they lagged the nose when it bent): where
    they sit and which way they blow are worked out once in the head bone's own space, then
    carried round with it every frame. The upper lip bone (lipmidup_m) anchors them when there is
    one, since it sits right under the nostrils.

    The puffs are the base game's slow horse step dust (HORSE_STEP_SLOW), cloned twice (one per
    nostril) onto the ridden horse, under the nostrils and aimed down, forwards and a little out
    to each side so they show from the saddle too. They live in the horse's space, so they travel
    with it instead of streaming off behind at a gallop. Everything is wrapped so a missing node
    or a changed game file only logs a line.
]]

EqBreath = {}

local Log = EqLog

EqBreath.FILE = "$data/effects/horse/horseStepParticleSystem.i3d"
-- The slow step emitter (the second Dynamic in the file).
EqBreath.NODE = "1"
-- Bones to look for in the horse's own skeleton, in order, with where the nostrils are from them:
-- FORWARD metres along the horse's heading and UP metres up. The base horse's head is head_m;
-- James placed the breath under its nostrils at 0.48 / -0.5 (2026-11-04).
EqBreath.BONES = {
    { names = { "head_m", "head", "head_jnt", "headbone", "skull" }, forward = 0.48, up = -0.5 },
    { names = { "neck4_m", "neck2_m", "neck_m", "neck2", "neck" }, forward = 1.1, up = -0.5 },
}
-- The upper lip, just under the nostrils: the breath is anchored to it when the horse has one.
EqBreath.LIP_BONES = { "lipmidup_m", "lipmid_up", "lip_up", "upperlip" }
-- Set by eqBreath forward/up: overrides the bone's offsets.
EqBreath.FORWARD = nil
EqBreath.UP = nil
-- The nostrils sit this far either side of the middle, and each blows along this direction in
-- the horse's space (x out to its side, y up, z forward): down, forwards and a little out.
EqBreath.NOSTRIL_GAP = 0.05
EqBreath.BLOW = { 0.3, -0.6, 0.75 }
-- A tight cone per nostril (James, 2026-11-04: it looked shotgunned): the dust's emitter shape is
-- shrunk to this and its speed randomness cut to this share.
EqBreath.EMITTER_SCALE = 0.15
EqBreath.SPEED_RANDOM = 0.15
-- How the puffs come out, by how hard the horse is blowing: on for onMs, off for offMs, each puff
-- living lifespan ms, count times the dust's particles, size times its sprite size (the holder is
-- scaled) and speed times its speed. "band" while the stamina band waits at the bottom, "hard"
-- while Fatigued or Blown (James, 2026-11-04: noticeably bigger, only slightly quicker, blown out
-- harder). Then a quarter smaller, slower breathing for both and hard blown half as fast
-- (James, 2026-11-04 02:00).
EqBreath.STYLE = {
    band = { onMs = 450, offMs = 750, lifespan = 1000, count = 1, size = 1.125, speed = 1.5 },
    hard = { onMs = 420, offMs = 560, lifespan = 1100, count = 1.6, size = 1.725, speed = 1.75 },
}
-- eqBreath size/speed: extra multipliers for tuning in game.
EqBreath.SIZE = 1
EqBreath.SPEED = 1
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
    local lip = nil
    for _, wanted in ipairs(EqBreath.LIP_BONES) do
        if found[wanted] ~= nil then lip = found[wanted] break end
    end
    for _, group in ipairs(EqBreath.BONES) do
        for _, wanted in ipairs(group.names) do
            if found[wanted] ~= nil then return found[wanted], wanted, group, lip end
        end
    end
    -- Not the base horse: log its head bones once, for placing the breath by hand.
    local named = {}
    for name in pairs(found) do
        for _, part in ipairs({ "head", "jaw", "nose", "mouth", "muzzle", "lip", "neck" }) do
            if string.find(name, part, 1, true) then table.insert(named, name) break end
        end
    end
    table.sort(named)
    Log:info("Breath: no known head bone; head bones %s", #named > 0 and table.concat(named, ", ") or "none")
    for name, node in pairs(found) do
        if string.find(name, "head", 1, true) then return node, name, EqBreath.BONES[1], lip end
    end
    return nil, nil, nil, nil
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


--- One nostril: a holder on the horse's root with its own copy of the dust, aimed out to side.
local function nostril(vehicle, ref, side)
    local holder = createTransformGroup("eqBreath")
    link(vehicle.rootNode, holder)
    local psClone = clone(ref.node, true, false, true)
    link(holder, psClone)
    -- The emitter shape sits on the holder with the particle system, both in the holder's space.
    local emitter = nil
    if getNumOfChildren(psClone) > 0 then
        emitter = getChildAt(psClone, 0)
        link(holder, emitter)
        setTranslation(emitter, 0, 0, 0)
        local e = EqBreath.EMITTER_SCALE
        setScale(emitter, e, e, e)
    end
    local ps = {}
    ParticleUtil.loadParticleSystemFromNode(psClone, ps, false, false, false)
    if emitter ~= nil then ParticleUtil.setEmitterShape(ps, emitter) end
    ParticleUtil.setEmittingState(ps, false)
    if ParticleUtil.getParticleSystemSpeedRandom ~= nil and ParticleUtil.setParticleSystemSpeedRandom ~= nil then
        local random = ParticleUtil.getParticleSystemSpeedRandom(ps)
        if random ~= nil then ParticleUtil.setParticleSystemSpeedRandom(ps, random * EqBreath.SPEED_RANDOM) end
    end
    local baseSpeed = ParticleUtil.getParticleSystemSpeed ~= nil and ParticleUtil.getParticleSystemSpeed(ps) or nil
    return { holder = holder, ps = ps, side = side, baseSpeed = baseSpeed }
end


local function attach(vehicle)
    local ref = EqBreath.ensureReference()
    if ref == nil or vehicle.rootNode == nil or vehicle.rootNode == 0 then return nil end
    -- Only the horse's own skeleton: the rider (a character with a "head" of its own) rides under
    -- the same root (James, 2026-11-03: the first breath came out of the rider's face).
    local spec = vehicle.spec_rideable
    local skeleton = spec ~= nil and spec.animationNode or nil
    if skeleton == nil or skeleton == 0 or not entityExists(skeleton) then skeleton = spec ~= nil and spec.meshNode or nil end
    local bone, boneName, group, lip = nil, nil, nil, nil
    if skeleton ~= nil and skeleton ~= 0 and entityExists(skeleton) then
        bone, boneName, group, lip = findBone(skeleton)
    end
    local entry = { bone = bone, lip = lip, emitting = false, clock = 0, logged = false,
        forward = group ~= nil and group.forward or 0, up = group ~= nil and group.up or 0,
        nostrils = { nostril(vehicle, ref, -1), nostril(vehicle, ref, 1) } }
    Log:info("Breath: attached to %s%s", bone ~= nil and ("bone " .. tostring(boneName)) or "the horse's root (no head bone found)",
        lip ~= nil and ", anchored on the upper lip" or "")
    return entry
end


local function alive(entry)
    for _, n in ipairs(entry.nostrils) do
        if not entityExists(n.holder) then return false end
    end
    return true
end


local function aim(holder, dx, dy, dz)
    -- The dust blows along the holder's -z (it went straight back at the rider unturned, James
    -- 2026-11-04), so the holder's z points the opposite way to where the nostril should blow.
    setDirection(holder, -dx, -dy, -dz, 0, 1, 0)
end


--- Where each nostril sits and blows, in the head bone's space: worked out from the offsets in
--- the horse's space with the head as it is now, so it follows the head from then on.
local function calibrate(vehicle, entry)
    local root, head = vehicle.rootNode, entry.bone
    local forward, up = EqBreath.FORWARD or entry.forward, EqBreath.UP or entry.up
    local hx, hy, hz = worldToLocal(root, getWorldTranslation(head))
    local b = EqBreath.BLOW
    for _, n in ipairs(entry.nostrils) do
        local wx, wy, wz = localToWorld(root, hx + n.side * EqBreath.NOSTRIL_GAP, hy + up, hz + forward)
        local px, py, pz = worldToLocal(head, wx, wy, wz)
        if entry.lip ~= nil and entityExists(entry.lip) then
            -- Kept relative to the upper lip, so it stays under the nostrils if the lip moves.
            local lx, ly, lz = worldToLocal(head, getWorldTranslation(entry.lip))
            px, py, pz = px - lx, py - ly, pz - lz
        end
        n.offset = { px, py, pz }
        local dx, dy, dz = localDirectionToWorld(root, b[1] * n.side, b[2], b[3])
        n.blow = { worldDirectionToLocal(head, dx, dy, dz) }
    end
    entry.calibrated = forward .. "/" .. up
end


local function place(vehicle, entry)
    local root = vehicle.rootNode
    local forward, up = EqBreath.FORWARD or entry.forward, EqBreath.UP or entry.up
    local b = EqBreath.BLOW
    if entry.bone == nil or not entityExists(entry.bone) then
        -- No head bone: roughly where a standing horse's muzzle is, blowing the plain way.
        for _, n in ipairs(entry.nostrils) do
            setTranslation(n.holder, n.side * EqBreath.NOSTRIL_GAP, 1.4 + up, 1.3 + forward)
            aim(n.holder, b[1] * n.side, b[2], b[3])
        end
        return
    end
    local head = entry.bone
    if entry.calibrated ~= forward .. "/" .. up then calibrate(vehicle, entry) end
    local lx, ly, lz = 0, 0, 0
    if entry.lip ~= nil and entityExists(entry.lip) then lx, ly, lz = worldToLocal(head, getWorldTranslation(entry.lip)) end
    for _, n in ipairs(entry.nostrils) do
        local o = n.offset
        local x, y, z = worldToLocal(root, localToWorld(head, lx + o[1], ly + o[2], lz + o[3]))
        setTranslation(n.holder, x, y, z)
        aim(n.holder, worldDirectionToLocal(root, localDirectionToWorld(head, n.blow[1], n.blow[2], n.blow[3])))
    end
end


local function setEmitting(entry, on)
    if entry.emitting == on then return end
    entry.emitting = on
    for _, n in ipairs(entry.nostrils) do
        -- The step dust stops after a few particles (maxEmit), so each breath starts the count again.
        if on and ParticleUtil.resetNumOfEmittedParticles ~= nil then ParticleUtil.resetNumOfEmittedParticles(n.ps) end
        ParticleUtil.setEmittingState(n.ps, on)
    end
end


local function setLook(entry, look)
    for _, n in ipairs(entry.nostrils) do
        ParticleUtil.setParticleLifespan(n.ps, look.lifespan)
        ParticleUtil.setEmitCountScale(n.ps, look.count)
        local size = look.size * EqBreath.SIZE
        setScale(n.holder, size, size, size)
        if n.baseSpeed ~= nil and ParticleUtil.setParticleSystemSpeed ~= nil then
            ParticleUtil.setParticleSystemSpeed(n.ps, n.baseSpeed * look.speed * EqBreath.SPEED)
        end
    end
end


--- One frame for a ridden horse.
--- @param vehicle table the Rideable
--- @param style string|nil "band", "hard" or nil for no breath
--- @param dt number milliseconds
function EqBreath.update(vehicle, style, dt)
    if EqBreath.force ~= nil then style = EqBreath.force or nil end
    local look = style ~= nil and EqBreath.STYLE[style] or nil
    local entry = EqBreath.byVehicle[vehicle]
    if entry ~= nil and not alive(entry) then
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
    local lookKey = style .. "/" .. EqBreath.SIZE .. "/" .. EqBreath.SPEED
    if entry.lookKey ~= lookKey then
        entry.lookKey = lookKey
        setLook(entry, look)
    end
    place(vehicle, entry)
    if not entry.logged then
        -- Once, where it is: for checking a breath that doesn't show.
        entry.logged = true
        local hx, hy, hz = getWorldTranslation(entry.nostrils[1].holder)
        local rx, ry, rz = getWorldTranslation(vehicle.rootNode)
        Log:info("Breath: %s at %.1f %.1f %.1f (horse at %.1f %.1f %.1f)", style, hx, hy, hz, rx, ry, rz)
    end
    -- Breaths: on, then off, round again.
    entry.clock = (entry.clock + dt) % (look.onMs + look.offMs)
    setEmitting(entry, entry.clock < look.onMs)
end


--- Stop a horse's breath (rider off).
--- @param vehicle table
function EqBreath.stop(vehicle)
    local entry = EqBreath.byVehicle[vehicle]
    if entry ~= nil and alive(entry) then setEmitting(entry, false) end
end


--- Remove everything (mission end).
function EqBreath.reset()
    for _, entry in pairs(EqBreath.byVehicle) do
        for _, n in ipairs(entry.nostrils) do
            if entityExists(n.holder) then
                ParticleUtil.setEmittingState(n.ps, false)
                ParticleUtil.deleteParticleSystem(n.ps)
                delete(n.holder)
            end
        end
    end
    EqBreath.byVehicle = {}
    if EqBreath.reference ~= nil and entityExists(EqBreath.reference.root) then delete(EqBreath.reference.root) end
    EqBreath.reference, EqBreath.failed = nil, false
end

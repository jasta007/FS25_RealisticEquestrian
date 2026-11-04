--[[
    EqXcHide.lua
    Our cross country pieces (placeables/xcJumps/: flag fences, log piles, drop walls) are hidden,
    with no collision, while the player just rides or drives around (James, 2026-10-27): a course
    can cross the whole map without leaving flags and logs all over it. They are back:

    - in construction mode, with collision, so they can be picked, moved and sold (the Rope
      Marker's collision is only there for this: it is ridden through everywhere else);
    - while a course is edited, seen but ridden through (the course editor takes show jumps'
      collision off for the same reason);
    - in a round, from its countdown (the horse right at the start line) to the result, solid
      for the horse in the round only (James, 2026-11-03): each piece's collision filter mask is
      set to one bit of our own (RIDER_BIT), and only that horse's movement collision group gets
      the bit. Players on foot, vehicles and other horses pass through. This is the groundwork for
      multiplayer, where a friend nearby sees the pieces but doesn't hit them. The flag fence only seen, so its flags and guide line never stop a horse or count
      as hitting a fence: faults come from the jump itself (James, 2026-10-28). Not before: riding
      past a start line no longer makes a course pop up (James, 2026-10-29).

    Each piece has a "Disappearing" shop configuration. Log piles and drop walls disappear by
    default (stored as EqXcHide.CONFIG, eqAlwaysVisible: 1 = disappearing, 2 = always visible, as
    saved before it was renamed); our show jumps stay by default (DISAPPEAR_CONFIG, 1 = No, 2 =
    Yes). The flag fence has no choice and always hides (James). Everything is left alone in
    multiplayer, where rounds don't run yet and collision is the server's. Other mods' show jumps
    are never touched.

    A vehicle parked on a hidden piece can be thrown when its collision comes back. James is
    fine with that: the game's reset handles it.

    During a cross country round (start line to finish) road traffic is switched off, and back
    on after, so cars don't get in the way of riders on roads (James). Only the running traffic
    system is touched, never the savegame's traffic setting.

    Part of Realistic Equestrian by Jasta007.
]]

EqXcHide = {}

local Log = EqLog

-- Cross country pieces' configuration: 1 = Disappearing: Yes (hidden outside rounds), 2 = No.
EqXcHide.CONFIG = "eqAlwaysVisible"
EqXcHide.ALWAYS = 2
-- Our show jumps' configuration: 1 = Disappearing: No, 2 = Yes.
EqXcHide.DISAPPEAR_CONFIG = "eqDisappearing"
EqXcHide.DISAPPEAR = 2
-- Pieces are listed again this often, to catch newly placed ones.
EqXcHide.SCAN_MS = 1000
-- Most nodes searched under one piece (a long flag fence has many).
EqXcHide.MAX_NODES = 20000

-- Modes: "shown" (as built), "rider" (seen, solid for the horse in a round only), "ghost" (seen,
-- no collision), "hidden" (unseen, no collision).
EqXcHide.SHOWN, EqXcHide.RIDER, EqXcHide.GHOST, EqXcHide.HIDDEN = "shown", "rider", "ghost", "hidden"
-- Collision bits we try for the rider group, highest first: the first no CollisionFlag uses.
-- Bit 31 last: an engine taking masks as signed numbers could get it wrong.
EqXcHide.RIDER_BITS = { 30, 29, 28, 27, 26, 25, 24, 31 }
EqXcHide.riderBit = nil
-- The horse given the rider bit, and its movement collision group before.
EqXcHide.riderVehicle = nil
EqXcHide.riderGroup = nil

EqXcHide.mode = nil
EqXcHide.scannedAt = nil
-- Pieces put in a mode, by root node.
EqXcHide.byRoot = {}
EqXcHide.trafficOff = false
EqXcHide.loggedTraffic = false


--- What every disappearing piece should be now.
--- @param state table { construction, editing, round, multiplayer }
--- @return string EqXcHide.SHOWN, GHOST or HIDDEN
function EqXcHide.wantMode(state)
    if state.multiplayer or state.construction then return EqXcHide.SHOWN end
    if state.editing then return EqXcHide.GHOST end
    if state.round then return EqXcHide.RIDER end
    return EqXcHide.HIDDEN
end


--- The mode for one piece: the flag fence and the Rope Marker are ridden through wherever the
--- others would be solid, except in construction mode (picked to move or sell) and multiplayer
--- (left alone).
--- @param mode string from wantMode
--- @param rideThrough boolean the flag fence or the Rope Marker
--- @param state table as for wantMode
--- @return string
function EqXcHide.modeFor(mode, rideThrough, state)
    if rideThrough and (mode == EqXcHide.SHOWN or mode == EqXcHide.RIDER) and not state.construction and not state.multiplayer then return EqXcHide.GHOST end
    return mode
end


--- Is a round on, as far as showing the pieces goes: from its countdown to the result.
--- @param sjState string|nil the round's EqShowJumping state, nil for no round
--- @return boolean
function EqXcHide.roundShows(sjState)
    return sjState ~= nil and sjState ~= "approach"
end


--- Is road traffic kept off: a cross country round from crossing the start line to the finish,
--- not while riding up to it or counting down (James, 2026-10-27).
--- @param kind string|nil the round's course kind
--- @param sjState string|nil the round's EqShowJumping state
--- @return boolean
function EqXcHide.wantsTrafficOff(kind, sjState)
    if kind ~= EqCourse.CROSS_COUNTRY then return false end
    return sjState == "running"
end


--- @param configurations table|nil a placeable's configurations (name -> index)
--- @return boolean true when a cross country piece was bought Disappearing: No (always visible)
function EqXcHide.isAlwaysVisible(configurations)
    return type(configurations) == "table" and configurations[EqXcHide.CONFIG] == EqXcHide.ALWAYS
end


--- @param configFileName string|nil
--- @param configurations table|nil
--- @return boolean true for a piece EqXcHide hides: the flag fence always, a cross country piece
--- unless bought Disappearing: No, one of our show jumps only if bought Disappearing: Yes
function EqXcHide.disappears(configFileName, configurations)
    if EqXcFlags.isFlagFence(configFileName) then return true end
    if EqPoles.isOurs(configFileName) then
        return type(configurations) == "table" and configurations[EqXcHide.DISAPPEAR_CONFIG] == EqXcHide.DISAPPEAR
    end
    return not EqXcHide.isAlwaysVisible(configurations)
end


--- Register the configuration, so the shop offers it on our log piles and drop walls (their xmls
--- carry <eqAlwaysVisible><eqAlwaysVisibleConfigurations>, like a shed's solar panels). Runs
--- at source time, before the store items load.
function EqXcHide.registerConfiguration()
    local manager = g_placeableConfigurationManager
    if manager == nil or manager.addConfigurationType == nil or PlaceableConfigurationItem == nil then
        Log:warning("EqXcHide: no placeable configurations, cross country pieces can't be made always visible")
        return
    end
    local title = "Disappearing"
    if g_i18n ~= nil and g_i18n:hasText("eq_config_disappearing") then title = g_i18n:getText("eq_config_disappearing") end
    for _, name in ipairs({ EqXcHide.CONFIG, EqXcHide.DISAPPEAR_CONFIG }) do
        if manager.configurations == nil or manager.configurations[name] == nil then
            manager:addConfigurationType(name, title, name, PlaceableConfigurationItem)
        end
    end
end


--- @return table the pieces EqXcHide looks after (disappearing ones)
function EqXcHide.pieces()
    local list = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return list end
    for _, placeable in ipairs(system.placeables) do
        if placeable.rootNode ~= nil and (EqPlaceAnywhere.isOurs(placeable.configFileName) or EqPoles.isOurs(placeable.configFileName))
            and EqXcHide.disappears(placeable.configFileName, placeable.configurations) then
            table.insert(list, placeable)
        end
    end
    return list
end


--- Take the collision off every rigid body under a piece, keeping it to put back. Looks again
--- each time, adding to what it keeps: the course editor gives back the collision it took
--- (EqCourseHooks), and a fence grows new segments.
--- @param placeable table
local function collisionOff(placeable)
    if setRigidBodyType == nil or getRigidBodyType == nil then return end
    local none = RigidBodyType ~= nil and RigidBodyType.NONE or "NoRigidBody"
    local bodies, stack, seen = placeable.eqXcBodies or {}, { placeable.rootNode }, 0
    while #stack > 0 and seen < EqXcHide.MAX_NODES do
        local node = table.remove(stack)
        seen = seen + 1
        local kind = getRigidBodyType(node)
        if kind ~= nil and kind ~= none and kind ~= "NoRigidBody" then
            setRigidBodyType(node, none)
            table.insert(bodies, { node = node, kind = kind })
        end
        for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
    end
    placeable.eqXcBodies = bodies
end


--- Give a piece back the collision collisionOff took.
--- @param placeable table
local function collisionOn(placeable)
    local bodies = placeable.eqXcBodies
    if bodies == nil then return end
    placeable.eqXcBodies = nil
    for _, body in ipairs(bodies) do
        if entityExists == nil or entityExists(body.node) then setRigidBodyType(body.node, body.kind) end
    end
end


--- @param value number
--- @param bit number 0 to 31
--- @return boolean true when the bit is set in value
function EqXcHide.hasBit(value, bit)
    return type(value) == "number" and math.floor(value / 2 ^ bit) % 2 == 1
end


--- The collision bit for "the horse in a round": the first of RIDER_BITS that no CollisionFlag
--- uses (FS25's flags aren't documented, so we look at the table the game has).
--- @param flags table|nil CollisionFlag
--- @return number|nil the bit, nil when all are taken
function EqXcHide.pickRiderBit(flags)
    for _, bit in ipairs(EqXcHide.RIDER_BITS) do
        local used = false
        for _, value in pairs(flags or {}) do
            if type(value) == "number" and value ~= 0 and value < 2 ^ 32 - 1 and EqXcHide.hasBit(value, bit) then used = true break end
        end
        if not used then return bit end
    end
    return nil
end


--- @return number|nil the rider collision bit's value (2 ^ bit), worked out once
function EqXcHide.riderValue()
    if EqXcHide.riderBit == nil then
        EqXcHide.riderBit = EqXcHide.pickRiderBit(CollisionFlag) or false
        if EqXcHide.riderBit then
            Log:info("EqXcHide: collision bit %d is the horse in a round's", EqXcHide.riderBit)
        else
            Log:warning("EqXcHide: no free collision bit, pieces in a round are solid for everyone")
        end
    end
    return EqXcHide.riderBit and 2 ^ EqXcHide.riderBit or nil
end


--- Solid for the horse in a round only: every rigid body under a piece gets the rider bit as its
--- collision mask, keeping its own mask to put back. Looks again each time, for a show jump
--- pole put back up meanwhile.
--- @param placeable table
local function masksRider(placeable)
    local rider = EqXcHide.riderValue()
    if rider == nil or getCollisionFilterMask == nil or setCollisionFilterMask == nil or getRigidBodyType == nil then return end
    local none = RigidBodyType ~= nil and RigidBodyType.NONE or "NoRigidBody"
    local masks, stack, seen = placeable.eqXcMasks or {}, { placeable.rootNode }, 0
    while #stack > 0 and seen < EqXcHide.MAX_NODES do
        local node = table.remove(stack)
        seen = seen + 1
        local kind = getRigidBodyType(node)
        if kind ~= nil and kind ~= none and kind ~= "NoRigidBody" then
            local mask = getCollisionFilterMask(node)
            if mask ~= rider then
                masks[node] = mask
                setCollisionFilterMask(node, rider)
            end
        end
        for i = 0, getNumOfChildren(node) - 1 do table.insert(stack, getChildAt(node, i)) end
    end
    placeable.eqXcMasks = masks
end


--- Give a piece back the collision masks masksRider took.
--- @param placeable table
local function masksBack(placeable)
    local masks = placeable.eqXcMasks
    if masks == nil then return end
    placeable.eqXcMasks = nil
    for node, mask in pairs(masks) do
        if entityExists == nil or entityExists(node) then setCollisionFilterMask(node, mask) end
    end
end


--- Put one piece in a mode.
--- @param placeable table
--- @param mode string
function EqXcHide.apply(placeable, mode)
    if placeable.eqXcMode == mode and mode ~= EqXcHide.RIDER then return end
    if entityExists ~= nil and not entityExists(placeable.rootNode) then return end
    if mode == EqXcHide.RIDER then
        collisionOn(placeable)
        masksRider(placeable)
    elseif mode == EqXcHide.SHOWN then
        masksBack(placeable)
        collisionOn(placeable)
    else
        masksBack(placeable)
        collisionOff(placeable)
    end
    setVisibility(placeable.rootNode, mode ~= EqXcHide.HIDDEN)
    placeable.eqXcMode = mode
    EqXcHide.byRoot[placeable.rootNode] = placeable
end


--- Where a piece keeps the collision it took, while it is hidden or ghost: a show jump pole put
--- back up then hands its collision over here instead of turning it on (EqPoles.raise).
--- @param root number a placeable's root node
--- @return table|nil the list to add { node, kind } to, nil when the piece has its collision
function EqXcHide.heldBodies(root)
    local placeable = EqXcHide.byRoot[root]
    if placeable == nil or placeable.eqXcMode == nil or placeable.eqXcMode == EqXcHide.SHOWN or placeable.eqXcMode == EqXcHide.RIDER then return nil end
    placeable.eqXcBodies = placeable.eqXcBodies or {}
    return placeable.eqXcBodies
end


--- A drop wall with a machine parked on its deck (EqPlinths, horses count) stays while it is
--- shown (or solid for the horse in a round): never pull the floor away. It only HOLDS a piece that is already there (or just loaded,
--- shown as built); a hidden piece never comes back for one, or riding over a hidden drop wall
--- made its deck pop up under the horse (James's video, 2026-11-03).
--- @param placeable table
--- @return boolean true when the piece must stay shown
function EqXcHide.keepsForMachine(placeable)
    if placeable.eqXcMode ~= nil and placeable.eqXcMode ~= EqXcHide.SHOWN and placeable.eqXcMode ~= EqXcHide.RIDER then return false end
    return EqPlinths ~= nil and EqPlinths.holdsMachine ~= nil and EqPlinths.holdsMachine(placeable) == true
end


--- @return boolean true in a multiplayer game
local function isMultiplayer()
    local mission = g_currentMission
    local info = mission ~= nil and mission.missionDynamicInfo or nil
    return info ~= nil and info.isMultiplayer == true
end


--- The round under way, if any: its course kind, state and the rider's distance to its start line.
--- @return string|nil kind, string|nil state, number|nil distance, table|nil the horse
local function roundState()
    local round = EqCourseHooks ~= nil and EqCourseHooks.round or nil
    if round == nil or round.sj == nil then return nil end
    local sj = round.sj
    local distance = nil
    if sj.start ~= nil and round.last ~= nil then
        distance = math.sqrt((round.last[1] - sj.start.x) ^ 2 + (round.last[2] - sj.start.z) ^ 2)
    end
    return round.course ~= nil and round.course.kind or nil, sj.state, distance, round.vehicle
end


--- @param vehicle table|nil
--- @return table|nil the horse's CCTDrivable spec (the game names it spec_cctdrivable)
local function cctSpec(vehicle)
    if vehicle == nil then return nil end
    local spec = vehicle.spec_cctdrivable or vehicle.spec_cctDrivable
    if spec == nil or type(spec.movementCollisionGroup) ~= "number" then return nil end
    return spec
end


--- Give the horse in a round the rider bit in its movement collision group, so it hits the
--- pieces, and take it back from a horse no longer in one. CCTDrivable passes
--- spec.movementCollisionGroup to moveCCT each frame on the server.
--- @param vehicle table|nil the horse in the round, nil for none
--- @return boolean true when the horse (if any) has the bit, false when it couldn't be given
function EqXcHide.setRider(vehicle)
    local rider = EqXcHide.riderValue()
    if rider == nil then return vehicle == nil end
    if vehicle == EqXcHide.riderVehicle then return true end
    local oldSpec = cctSpec(EqXcHide.riderVehicle)
    if oldSpec ~= nil and EqXcHide.riderGroup ~= nil then oldSpec.movementCollisionGroup = EqXcHide.riderGroup end
    EqXcHide.riderVehicle, EqXcHide.riderGroup = nil, nil
    if vehicle == nil then return true end
    local spec = cctSpec(vehicle)
    if spec == nil then
        if not EqXcHide.loggedRider then
            EqXcHide.loggedRider = true
            Log:warning("EqXcHide: the horse has no CCT movement group, pieces in a round stay solid for everyone")
        end
        return false
    end
    EqXcHide.riderVehicle, EqXcHide.riderGroup = vehicle, spec.movementCollisionGroup
    if not EqXcHide.hasBit(spec.movementCollisionGroup, EqXcHide.riderBit) then
        spec.movementCollisionGroup = spec.movementCollisionGroup + rider
    end
    Log:info("EqXcHide: horse in the round collides with the pieces (group 0x%x)", spec.movementCollisionGroup)
    return true
end


--- Switch road traffic off or back on as the savegame has it.
--- @param off boolean
function EqXcHide.setTrafficOff(off)
    if off == EqXcHide.trafficOff then return end
    local mission = g_currentMission
    local traffic = mission ~= nil and mission.trafficSystem or nil
    local info = mission ~= nil and mission.missionInfo or nil
    local enabled = info == nil or info.trafficEnabled ~= false
    EqXcHide.trafficOff = off
    -- Traffic switched off in the settings stays off; nothing to put back either.
    if not enabled then return end
    local on = not off
    if traffic ~= nil and traffic.setEnabled ~= nil then
        traffic:setEnabled(on)
    elseif traffic ~= nil and setTrafficSystemEnabled ~= nil and traffic.trafficSystemId ~= nil then
        setTrafficSystemEnabled(traffic.trafficSystemId, on)
    elseif not EqXcHide.loggedTraffic then
        EqXcHide.loggedTraffic = true
        Log:warning("EqXcHide: no traffic system to switch off during cross country rounds")
        return
    end
    Log:info("EqXcHide: road traffic %s", off and "off for a cross country round" or "back on")
end


--- Each frame: follow construction mode, course editing and rounds at once, and put newly
--- placed pieces in the mode every SCAN_MS.
function EqXcHide.update()
    local kind, sjState, _, vehicle = roundState()
    local state = {
        construction = EqXcFlags.inConstruction(),
        editing = EqCourseHooks ~= nil and EqCourseHooks.editing ~= nil,
        round = EqXcHide.roundShows(sjState),
        multiplayer = isMultiplayer(),
    }
    local mode = EqXcHide.wantMode(state)
    EqXcHide.setTrafficOff(not isMultiplayer() and EqXcHide.wantsTrafficOff(kind, sjState))
    -- A horse that can't take the rider bit would go through the pieces: solid for everyone then.
    if not EqXcHide.setRider(mode == EqXcHide.RIDER and vehicle or nil) and mode == EqXcHide.RIDER then mode = EqXcHide.SHOWN end

    local now = g_time or 0
    local due = EqXcHide.scannedAt == nil or now - EqXcHide.scannedAt >= EqXcHide.SCAN_MS or now < EqXcHide.scannedAt
    if mode == EqXcHide.mode and not due then return end
    local pieces = EqXcHide.pieces()
    -- Rope Markers are the crowd's barrier at your hosted events: seen (ridden through) then
    local ropes = EqSpectators ~= nil and EqSponsors ~= nil and not state.multiplayer and EqSpectators.ropesShown()
    for _, placeable in ipairs(pieces) do
        local rope = EqSponsors ~= nil and EqSponsors.isRope(placeable.configFileName)
        local want = EqXcHide.modeFor(mode, EqXcFlags.isFlagFence(placeable.configFileName) or rope, state)
        if ropes and want == EqXcHide.HIDDEN and rope then want = EqXcHide.GHOST end
        -- a drop wall with a machine parked on its deck stays (EqPlinths): never pull the floor away
        if want ~= EqXcHide.SHOWN and want ~= EqXcHide.RIDER and EqXcHide.keepsForMachine(placeable) then want = EqXcHide.SHOWN end
        EqXcHide.apply(placeable, want)
    end
    if mode ~= EqXcHide.mode and #pieces > 0 then
        Log:info("EqXcHide: %d cross country piece(s) %s", #pieces, mode)
    end
    EqXcHide.mode = mode
    EqXcHide.scannedAt = now
end


--- Leaving the game puts traffic back and the horse's group. Pieces need nothing: only their
--- live nodes change.
function EqXcHide.reset()
    EqXcHide.setTrafficOff(false)
    EqXcHide.setRider(nil)
    EqXcHide.mode, EqXcHide.scannedAt, EqXcHide.byRoot = nil, nil, {}
end


--- @param guarded function main.lua's error guard
function EqXcHide.install(guarded)
    guarded("cross country piece configuration", EqXcHide.registerConfiguration)
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function()
        if not EqMain.isActive then return end
        guarded("cross country pieces", EqXcHide.update)
    end)
    FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, function()
        guarded("cross country pieces reset", EqXcHide.reset)
    end)
end

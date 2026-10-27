--[[
    EqXcHide.lua
    Our cross country pieces (placeables/xcJumps/: flag fences, log piles, drop walls) are hidden,
    with no collision, while the player just rides or drives around (James, 2026-10-27): a course
    can cross the whole map without leaving flags and logs all over it. They are back:

    - in construction mode, with collision, so they can be picked, moved and sold;
    - while a course is edited, seen but ridden through (the course editor takes show jumps'
      collision off for the same reason);
    - in a round, from the start line's approach (SHOW_NEAR) to the end, with collision.

    A log pile or drop wall bought with the "Always visible" configuration (EqXcHide.CONFIG, No by
    default) is left alone; the flag fence has no such choice and always hides (James). Everything
    is left alone in multiplayer, where rounds don't run yet and collision is the server's. Show jumps are never touched: they are mostly other mods' (James).

    A vehicle parked on a hidden piece can be thrown when its collision comes back. James is
    fine with that: the game's reset handles it.

    During a cross country round (start line to finish) road traffic is switched off, and back
    on after, so cars don't get in the way of riders on roads (James). Only the running traffic
    system is touched, never the savegame's traffic setting.

    Part of Realistic Equestrian by Jasta007.
]]

EqXcHide = {}

local Log = EqLog

-- The placeable configuration: 1 = No (hidden outside rounds), 2 = Yes (always visible).
EqXcHide.CONFIG = "eqAlwaysVisible"
EqXcHide.ALWAYS = 2
-- Pieces show once the rider is this near the start line before a round (metres).
EqXcHide.SHOW_NEAR = 60
-- Pieces are listed again this often, to catch newly placed ones.
EqXcHide.SCAN_MS = 1000
-- Most nodes searched under one piece (a long flag fence has many).
EqXcHide.MAX_NODES = 20000

-- Modes: "shown" (as built), "ghost" (seen, no collision), "hidden" (unseen, no collision).
EqXcHide.SHOWN, EqXcHide.GHOST, EqXcHide.HIDDEN = "shown", "ghost", "hidden"

EqXcHide.mode = nil
EqXcHide.scannedAt = nil
EqXcHide.trafficOff = false
EqXcHide.loggedTraffic = false


--- What every piece without the "Always visible" configuration should be now.
--- @param state table { construction, editing, round, multiplayer }
--- @return string EqXcHide.SHOWN, GHOST or HIDDEN
function EqXcHide.wantMode(state)
    if state.multiplayer or state.construction then return EqXcHide.SHOWN end
    if state.editing then return EqXcHide.GHOST end
    if state.round then return EqXcHide.SHOWN end
    return EqXcHide.HIDDEN
end


--- Is a round on, as far as showing the pieces goes: from SHOW_NEAR before the start line to
--- the result.
--- @param sjState string|nil the round's EqShowJumping state, nil for no round
--- @param startDistance number|nil metres from the rider to the start line
--- @return boolean
function EqXcHide.roundShows(sjState, startDistance)
    if sjState == nil then return false end
    if sjState ~= "approach" then return true end
    return startDistance ~= nil and startDistance <= EqXcHide.SHOW_NEAR
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
--- @return boolean true when bought "Always visible"
function EqXcHide.isAlwaysVisible(configurations)
    return type(configurations) == "table" and configurations[EqXcHide.CONFIG] == EqXcHide.ALWAYS
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
    if manager.configurations ~= nil and manager.configurations[EqXcHide.CONFIG] ~= nil then return end
    local title = "Always visible"
    if g_i18n ~= nil and g_i18n:hasText("eq_config_alwaysVisible") then title = g_i18n:getText("eq_config_alwaysVisible") end
    manager:addConfigurationType(EqXcHide.CONFIG, title, EqXcHide.CONFIG, PlaceableConfigurationItem)
end


--- @return table the cross country pieces EqXcHide looks after (Always visible ones left out)
function EqXcHide.pieces()
    local list = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then return list end
    for _, placeable in ipairs(system.placeables) do
        -- The flag fence always hides (James): Always visible is for the solid pieces.
        if placeable.rootNode ~= nil and EqPlaceAnywhere.isOurs(placeable.configFileName)
            and (EqXcFlags.isFlagFence(placeable.configFileName) or not EqXcHide.isAlwaysVisible(placeable.configurations)) then
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


--- Put one piece in a mode.
--- @param placeable table
--- @param mode string
function EqXcHide.apply(placeable, mode)
    if placeable.eqXcMode == mode then return end
    if entityExists ~= nil and not entityExists(placeable.rootNode) then return end
    if mode == EqXcHide.SHOWN then
        collisionOn(placeable)
    else
        collisionOff(placeable)
    end
    setVisibility(placeable.rootNode, mode ~= EqXcHide.HIDDEN)
    placeable.eqXcMode = mode
end


--- @return boolean true in a multiplayer game
local function isMultiplayer()
    local mission = g_currentMission
    local info = mission ~= nil and mission.missionDynamicInfo or nil
    return info ~= nil and info.isMultiplayer == true
end


--- The round under way, if any: its course kind, state and the rider's distance to its start line.
--- @return string|nil kind, string|nil state, number|nil distance
local function roundState()
    local round = EqCourseHooks ~= nil and EqCourseHooks.round or nil
    if round == nil or round.sj == nil then return nil end
    local sj = round.sj
    local distance = nil
    if sj.start ~= nil and round.last ~= nil then
        distance = math.sqrt((round.last[1] - sj.start.x) ^ 2 + (round.last[2] - sj.start.z) ^ 2)
    end
    return round.course ~= nil and round.course.kind or nil, sj.state, distance
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
    local kind, sjState, distance = roundState()
    local mode = EqXcHide.wantMode({
        construction = EqXcFlags.inConstruction(),
        editing = EqCourseHooks ~= nil and EqCourseHooks.editing ~= nil,
        round = EqXcHide.roundShows(sjState, distance),
        multiplayer = isMultiplayer(),
    })
    EqXcHide.setTrafficOff(not isMultiplayer() and EqXcHide.wantsTrafficOff(kind, sjState))

    local now = g_time or 0
    local due = EqXcHide.scannedAt == nil or now - EqXcHide.scannedAt >= EqXcHide.SCAN_MS or now < EqXcHide.scannedAt
    if mode == EqXcHide.mode and not due then return end
    local pieces = EqXcHide.pieces()
    for _, placeable in ipairs(pieces) do EqXcHide.apply(placeable, mode) end
    if mode ~= EqXcHide.mode and #pieces > 0 then
        Log:info("EqXcHide: %d cross country piece(s) %s", #pieces, mode)
    end
    EqXcHide.mode = mode
    EqXcHide.scannedAt = now
end


--- Leaving the game puts traffic back. Pieces need nothing: only their live nodes change.
function EqXcHide.reset()
    EqXcHide.setTrafficOff(false)
    EqXcHide.mode, EqXcHide.scannedAt = nil, nil
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

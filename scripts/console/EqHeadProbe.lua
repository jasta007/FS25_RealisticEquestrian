--[[
    EqHeadProbe.lua
    Testing aid for a relaxed dressage head (James, 2026-11-04: the forehead near vertical in a
    test, more so with temperament). Nothing in the mod poses a horse bone yet, and the spectators
    showed a clip can win over a joint set by hand, so this finds out what works before any of it
    is built. eqHeadProbe, while riding:
      bones                     writes the ridden horse's bone tree (names, local rotations) to log.txt
      clips                     writes its animation clips (names and lengths) to log.txt
      tracks <n>                writes what animation tracks 0..n-1 play now (asking for a track the
                                horse doesn't have crashed the game, 2026-11-04, so start small)
      watch [seconds]           logs those tracks every half second (stand still to catch the idles)
      tilt <bone> <deg> [x|y|z] [update|draw|both]   adds a turn to a bone every frame (axis z by
                                default: the rig's bones run along x and bend about z)
      tilt <bone> <deg> ... + <bone2> <deg2> ...     several bones at once (e.g. neck and head)
      mute <clip>               holds every known track playing that clip (name part or number) at weight 0
      hold <clip> <time 0-1> <weight 0-1> <track>    freezes that clip at a point on that track, blended in
      off                       stops tilt, mute and hold
    Bones and clips are matched by a part of their name, any case, first match; a number is an index.
    Dev only: not wired into anything else.
]]

EqHeadProbe = {}
EqHeadProbe.tilts = {}       -- { node, name, rad, axis }
EqHeadProbe.where = "both"
EqHeadProbe.mute = nil       -- clip index
EqHeadProbe.hold = nil       -- { clip, time, weight, track }
EqHeadProbe.watchUntil = nil
EqHeadProbe.watchNext = 0
EqHeadProbe.readback = 0     -- frames left to log the bone before and after the animation
EqHeadProbe.trackCount = 0  -- tracks known to exist (eqHeadProbe tracks n); none read before that

local Log = EqLog


local function say(fmt, ...)
    return "eqHeadProbe: " .. string.format(fmt, ...)
end


local function deg(r) return math.deg(r or 0) end


--- The horse the player rides now, or nil.
function EqHeadProbe.horse()
    local vehicle = EqLateral ~= nil and EqLateral.vehicle or nil
    if vehicle ~= nil and vehicle.getIsEntered ~= nil and vehicle:getIsEntered() and vehicle.spec_rideable ~= nil then
        return vehicle
    end
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        local current = g_localPlayer:getCurrentVehicle()
        if current ~= nil and current.spec_rideable ~= nil then return current end
    end
    return nil
end


local function walk(node, depth, fn)
    fn(node, depth)
    for i = 0, getNumOfChildren(node) - 1 do walk(getChildAt(node, i), depth + 1, fn) end
end


--- A bone under the horse's animation node, by name part (any case) or by its number in the dump.
local function findBone(spec, key)
    local want, number = string.lower(tostring(key)), tonumber(key)
    local found, count = nil, 0
    walk(spec.animationNode, 0, function(node)
        if found ~= nil then return end
        if number ~= nil then
            if count == number then found = node end
        elseif string.find(string.lower(getName(node)), want, 1, true) ~= nil then
            found = node
        end
        count = count + 1
    end)
    return found
end


local function clipCount(charset)
    local ok, n = pcall(getAnimNumOfClips, charset)
    return ok and n or 0
end


local function clipName(charset, index)
    local ok, name = pcall(getAnimClipName, charset, index)
    return ok and tostring(name) or "?"
end


local function findClip(charset, key)
    local number = tonumber(key)
    if number ~= nil then return number end
    local want = string.lower(tostring(key))
    for i = 0, clipCount(charset) - 1 do
        if string.find(string.lower(clipName(charset, i)), want, 1, true) ~= nil then return i end
    end
    return nil
end


--- One track's state as text, or nil when the charset has no such track.
local function trackText(charset, track)
    local ok, clip = pcall(getAnimTrackAssignedClip, charset, track)
    if not ok then return nil end
    local _, enabled = pcall(isAnimTrackEnabled, charset, track)
    local _, weight = pcall(getAnimTrackBlendWeight, charset, track)
    local _, time = pcall(getAnimTrackTime, charset, track)
    local name = (type(clip) == "number" and clip >= 0) and clipName(charset, clip) or "-"
    return string.format("track %d: clip %s (%s) enabled %s weight %.2f time %.0f", track, tostring(clip), name,
        tostring(enabled), tonumber(weight) or -1, tonumber(time) or -1)
end


local function tracks(charset)
    local lines = {}
    for t = 0, EqHeadProbe.trackCount - 1 do
        local text = trackText(charset, t)
        if text == nil then break end
        table.insert(lines, text)
    end
    return lines
end


function EqHeadProbe.dumpBones(spec)
    local lines, count = {}, 0
    walk(spec.animationNode, 0, function(node, depth)
        local rx, ry, rz = getRotation(node)
        local x, y, z = getTranslation(node)
        table.insert(lines, string.format("%3d %s%s  rot %.1f %.1f %.1f  pos %.2f %.2f %.2f", count,
            string.rep("  ", depth), getName(node), deg(rx), deg(ry), deg(rz), x, y, z))
        count = count + 1
    end)
    Log:info("eqHeadProbe bones under %s (%d):\n%s", getName(spec.animationNode), count, table.concat(lines, "\n"))
    return say("%d bones under '%s' written to log.txt", count, getName(spec.animationNode))
end


function EqHeadProbe.dumpClips(spec)
    local charset = spec.charsetId
    -- One line at a time, so a crash leaves the last good one in log.txt.
    local count = clipCount(charset)
    Log:info("eqHeadProbe charset %s: %d clips", tostring(charset), count)
    for i = 0, count - 1 do
        local name = clipName(charset, i)
        local ok, length = pcall(getAnimClipDuration, charset, i)
        Log:info("eqHeadProbe clip %d %s (%.0f ms)", i, name, ok and tonumber(length) or -1)
    end
    return say("%d clips written to log.txt", count)
end


function EqHeadProbe.dumpTracks(spec, count)
    local charset = spec.charsetId
    for t = 0, count - 1 do
        Log:info("eqHeadProbe reading track %d", t)
        local text = trackText(charset, t)
        Log:info("eqHeadProbe %s", text or ("track " .. t .. ": none"))
        if text == nil then return say("tracks 0-%d read, %d isn't there", t - 1, t) end
        EqHeadProbe.trackCount = math.max(EqHeadProbe.trackCount, t + 1)
    end
    return say("tracks 0-%d written to log.txt", count - 1)
end


local function applyTilts(spec, stage)
    if #EqHeadProbe.tilts == 0 then return end
    if EqHeadProbe.where ~= "both" and EqHeadProbe.where ~= stage then return end
    for _, tilt in ipairs(EqHeadProbe.tilts) do
        if entityExists(tilt.node) then
            local r = { getRotation(tilt.node) }
            if EqHeadProbe.readback > 0 then
                Log:info("eqHeadProbe %s %s before set: %.2f %.2f %.2f (last set %s)", stage, tilt.name,
                    deg(r[1]), deg(r[2]), deg(r[3]), tilt.lastSet ~= nil and string.format("%.2f", deg(tilt.lastSet)) or "-")
            end
            -- The clip rewrites the bone each frame, so the turn goes on top of its pose. If the
            -- bone still holds what we set (the clip left it alone, or update then draw), take the
            -- turn off first so it doesn't add up and spin.
            local base = r[tilt.axis]
            local kept = tilt.lastSet ~= nil and math.abs(base - tilt.lastSet) < 1e-5
            if kept then base = base - tilt.rad end
            if stage == "update" then
                if kept then tilt.kept = (tilt.kept or 0) + 1 else tilt.rewritten = (tilt.rewritten or 0) + 1 end
            end
            r[tilt.axis] = base + tilt.rad
            setRotation(tilt.node, r[1], r[2], r[3])
            tilt.lastSet = r[tilt.axis]
        end
    end
end


local function applyTracks(spec)
    local charset = spec.charsetId
    if EqHeadProbe.mute ~= nil then
        for t = 0, EqHeadProbe.trackCount - 1 do
            local ok, clip = pcall(getAnimTrackAssignedClip, charset, t)
            if not ok then break end
            if clip == EqHeadProbe.mute then pcall(setAnimTrackBlendWeight, charset, t, 0) end
        end
    end
    local hold = EqHeadProbe.hold
    if hold ~= nil and hold.track ~= nil then
        pcall(setAnimTrackSpeedScale, charset, hold.track, 0)
        pcall(setAnimTrackTime, charset, hold.track, hold.time, true)
        pcall(setAnimTrackBlendWeight, charset, hold.track, hold.weight)
        pcall(enableAnimTrack, charset, hold.track)
    end
end


--- After the base game's animation update (and at draw): the probe's changes.
function EqHeadProbe.after(vehicle, dt, stage)
    if vehicle ~= EqHeadProbe.horse() then return end
    local spec = vehicle.spec_rideable
    if spec == nil or spec.animationNode == nil then return end
    if stage == "update" then applyTracks(spec) end
    applyTilts(spec, stage)
    if stage == "draw" and EqHeadProbe.readback > 0 then EqHeadProbe.readback = EqHeadProbe.readback - 1 end
    if stage == "update" and EqHeadProbe.watchUntil ~= nil and (g_time or 0) >= EqHeadProbe.watchNext then
        EqHeadProbe.watchNext = (g_time or 0) + 500
        local speed = (vehicle.lastSignedSpeedReal or 0) * 3600
        Log:info("eqHeadProbe watch %.1f km/h halted %s:\n%s", speed, tostring((spec.haltTimer or 0) > 0), table.concat(tracks(spec.charsetId), "\n"))
        if (g_time or 0) >= EqHeadProbe.watchUntil then
            EqHeadProbe.watchUntil = nil
            say("watch done, see log.txt")
        end
    end
end


--- Before the base game's animation update: where the tilted bones were left.
function EqHeadProbe.before(vehicle)
    if EqHeadProbe.readback <= 0 or vehicle ~= EqHeadProbe.horse() then return end
    for _, tilt in ipairs(EqHeadProbe.tilts) do
        if entityExists(tilt.node) then
            local rx, ry, rz = getRotation(tilt.node)
            Log:info("eqHeadProbe frame start %s: %.2f %.2f %.2f", tilt.name, deg(rx), deg(ry), deg(rz))
        end
    end
end


function EqHeadProbe.install()
    if Rideable == nil or type(Rideable.updateAnimation) ~= "function" then
        Log:warning("EqHeadProbe: Rideable.updateAnimation not found; eqHeadProbe tilt/mute/hold won't work")
        return
    end
    Rideable.updateAnimation = Utils.overwrittenFunction(Rideable.updateAnimation, function(self, superFunc, dt)
        if EqHeadProbe.active() then EqLog.try("EqHeadProbe before", EqHeadProbe.before, self) end
        local result = { superFunc(self, dt) }
        if EqHeadProbe.active() then EqLog.try("EqHeadProbe after", EqHeadProbe.after, self, dt, "update") end
        return unpack(result)
    end)
    if type(Rideable.onDraw) == "function" then
        Rideable.onDraw = Utils.appendedFunction(Rideable.onDraw, function(self)
            if #EqHeadProbe.tilts > 0 then EqLog.try("EqHeadProbe draw", EqHeadProbe.after, self, 0, "draw") end
        end)
    end
end


function EqHeadProbe.active()
    return #EqHeadProbe.tilts > 0 or EqHeadProbe.mute ~= nil or EqHeadProbe.hold ~= nil or EqHeadProbe.watchUntil ~= nil
end


local function stopHold(spec)
    local hold = EqHeadProbe.hold
    if hold ~= nil and hold.track ~= nil and spec ~= nil then
        pcall(setAnimTrackBlendWeight, spec.charsetId, hold.track, 0)
        pcall(disableAnimTrack, spec.charsetId, hold.track)
        pcall(clearAnimTrackClip, spec.charsetId, hold.track)
    end
    EqHeadProbe.hold = nil
end


--- @param args string[] the words after eqHeadProbe
function EqHeadProbe.console(args)
    local vehicle = EqHeadProbe.horse()
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    local command = string.lower(args[1] or "bones")
    if command == "off" then
        for _, tilt in ipairs(EqHeadProbe.tilts) do
            Log:info("eqHeadProbe %s: clip rewrote it on %d frames, left it on %d", tilt.name, tilt.rewritten or 0, tilt.kept or 0)
        end
        EqHeadProbe.tilts = {}
        EqHeadProbe.mute = nil
        stopHold(spec)
        EqHeadProbe.watchUntil = nil
        return say("off")
    end
    if spec == nil or spec.animationNode == nil then return say("ride a horse first") end
    if command == "bones" then return EqHeadProbe.dumpBones(spec) end
    if command == "clips" then return EqHeadProbe.dumpClips(spec) end
    if command == "tracks" then
        local count = math.floor(tonumber(args[2]) or 0)
        if count < 1 or count > 32 then return say("tracks <n>, 1-32: try 1, then more") end
        return EqHeadProbe.dumpTracks(spec, count)
    end
    if command == "watch" then
        if EqHeadProbe.trackCount == 0 then return say("run eqHeadProbe tracks <n> first") end
        local seconds = tonumber(args[2]) or 20
        EqHeadProbe.watchUntil, EqHeadProbe.watchNext = (g_time or 0) + seconds * 1000, 0
        return say("logging the tracks for %d s", seconds)
    end
    if command == "tilt" then
        local tilts, i, where = {}, 2, "both"
        while args[i] ~= nil do
            local word = string.lower(args[i])
            if word == "update" or word == "draw" or word == "both" then
                where, i = word, i + 1
            elseif word == "+" then
                i = i + 1
            else
                local node = findBone(spec, args[i])
                if node == nil then return say("no bone matching '%s' (eqHeadProbe bones lists them)", args[i]) end
                local degrees = tonumber(args[i + 1])
                if degrees == nil then return say("tilt <bone> <degrees> [x|y|z]") end
                local axisWord = string.lower(args[i + 2] or "")
                local axis = ({ x = 1, y = 2, z = 3 })[axisWord]
                i = i + (axis ~= nil and 3 or 2)
                table.insert(tilts, { node = node, name = getName(node), rad = math.rad(degrees), axis = axis or 3 })
            end
        end
        if #tilts == 0 then return say("tilt <bone> <degrees> [x|y|z] [update|draw|both]") end
        EqHeadProbe.tilts, EqHeadProbe.where, EqHeadProbe.readback = tilts, where, 4
        local names = {}
        for _, t in ipairs(tilts) do table.insert(names, string.format("%s %.0f %s", t.name, deg(t.rad), ({ "x", "y", "z" })[t.axis])) end
        return say("tilting %s at %s; bone readback for 4 frames in log.txt", table.concat(names, ", "), where)
    end
    if command == "mute" then
        local clip = args[2] ~= nil and findClip(spec.charsetId, args[2]) or nil
        if clip == nil then return say("mute <clip name part or number> (eqHeadProbe clips lists them)") end
        if EqHeadProbe.trackCount == 0 then return say("run eqHeadProbe tracks <n> first") end
        EqHeadProbe.mute = clip
        return say("muting clip %d (%s)", clip, clipName(spec.charsetId, clip))
    end
    if command == "hold" then
        local clip = args[2] ~= nil and findClip(spec.charsetId, args[2]) or nil
        if clip == nil then return say("hold <clip> <time 0-1> <weight 0-1> <track>") end
        local share = math.max(0, math.min(1, tonumber(args[3]) or 0.5))
        local weight = math.max(0, math.min(1, tonumber(args[4]) or 0.5))
        stopHold(spec)
        local track = tonumber(args[5])
        if track == nil then return say("hold <clip> <time 0-1> <weight 0-1> <track>: pick a track eqHeadProbe tracks showed") end
        local okDuration, length = pcall(getAnimClipDuration, spec.charsetId, clip)
        local ok, err = pcall(assignAnimTrackClip, spec.charsetId, track, clip)
        if not ok then return say("couldn't put the clip on track %d: %s", track, tostring(err)) end
        pcall(setAnimTrackLoopState, spec.charsetId, track, false)
        EqHeadProbe.hold = { clip = clip, track = track, weight = weight,
            time = share * ((okDuration and length) or 0) }
        return say("holding clip %d (%s) at %.0f ms, weight %.2f, on track %d", clip, clipName(spec.charsetId, clip),
            EqHeadProbe.hold.time, weight, track)
    end
    return say("eqHeadProbe bones | clips | tracks <n> | watch [s] | tilt <bone> <deg> [x|y|z] [update|draw|both] | mute <clip> | hold <clip> <time 0-1> <weight 0-1> | off")
end

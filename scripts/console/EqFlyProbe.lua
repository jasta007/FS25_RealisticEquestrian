--[[
    EqFlyProbe.lua
    Testing aid for a flying change (James, 2026-11-23). The base horse's canter left/right clips
    turned out to be turn variants on one lead (only the head moved), so this tries two other
    ways, picked with `mode`:
      blip    James's "ping pong": for a moment the animation is told the horse is going at a
              trot while it keeps its canter speed, so the legs show a beat of trot, like a skip.
      mirror  the horse's skeleton is flipped left to right, which turns a left-lead canter into
              a right-lead one. Each change flips it. May render inside-out or swap markings.
    Nothing about the horse's movement changes. eqFlyProbe, while riding (R works once on):
      demo [blip|mirror]    on, a change every 3 s: type it, close the console, canter straight
      on | off              R makes a change; off puts everything back
      mode blip|mirror|reverse  which kind of change R makes (default blip); reverse plays the canter
                            backwards through the blip (James 2026-11-23: a reversed video looked like it might work)
      reverse <0.1-3>       how fast it plays backwards (default 1)
      mirror [0-4]          flips the horse now, to look at it standing still (again to flip back); the
                            number picks the node: 0 the skeleton, 1 its parent (default), 2 above that
      blip <ms>             how long the legs show trot (default 350)
      speed <0-1.5>         the speed the legs are shown at, as a share of the trot's top (default 1)
      delay <ms>            how long after R the change starts (default 0)
      phase <0-1>|off       the blip waits for this point in the canter stride (default 0; off = at once)
      trotphase <0-1>|off   the trot clip is set to this point as the blip starts (default off)
      outphase <0-1>|off    the canter clip is set to this point as it picks up again (default off)
      auto [seconds|off]    a change by itself every few seconds (default 3), hands free
      slow <0.1-1>          plays the leg animation slower (1 = normal)
      watch [seconds]       logs animation tracks 0-3 (clip, weight, time) every 250 ms
      clips                 writes the horse's animation clips (names and lengths) to log.txt
    Each change logs where the canter clip was in its stride, for the timing.
    Dev only: not wired into anything else, keep out of release builds.
]]

EqFlyProbe = {}
EqFlyProbe.on = false
EqFlyProbe.mode = "blip"
EqFlyProbe.blipMs = 350
EqFlyProbe.speedShare = 1
EqFlyProbe.delayMs = 0
EqFlyProbe.blip = nil       -- { from, to } ms: the legs show trot in between
-- Locked to the stride (James 2026-11-23: "looked weird but we can try it better timed"). A canter
-- stride is 533 ms, trot 767 ms (log). Shares of a clip's length, nil = left alone.
EqFlyProbe.phase = 0        -- the blip starts when the canter clip reaches this share
EqFlyProbe.trotPhase = nil  -- the trot clip starts the blip here
EqFlyProbe.outPhase = nil   -- the canter clip picks up here after it
EqFlyProbe.pending = nil    -- { since, last }: a change waiting for its point in the stride
EqFlyProbe.WAIT_MS = 1500   -- no canter seen this long: the blip goes anyway
EqFlyProbe.wasBlip = false
EqFlyProbe.reverseScale = 1 -- reverse mode: the canter plays backwards at this speed through the blip
EqFlyProbe.flipAt = nil     -- ms: the mirror flips then
EqFlyProbe.mirrored = false
EqFlyProbe.mirrorNode = nil -- the node scaled, to put back
EqFlyProbe.mirrorUp = 1     -- which node: 0 the skeleton's root (no effect, James 2026-11-23), 1 its parent, 2 the one above
EqFlyProbe.count = 0
EqFlyProbe.rDown = false
EqFlyProbe.autoMs = nil
EqFlyProbe.nextAuto = 0
EqFlyProbe.slow = 1
EqFlyProbe.slowSet = false
EqFlyProbe.watchUntil = nil
EqFlyProbe.watchNext = 0
EqFlyProbe.TRACKS = 4       -- tracks 0-3 exist on the horse (eqHeadProbe, 2026-11-04); more crashed the game

local Log = EqLog


local function say(fmt, ...)
    local text = "eqFlyProbe: " .. string.format(fmt, ...)
    Log:info(text)
    return text
end


--- The horse the player rides now, or nil.
function EqFlyProbe.horse()
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


local function clipName(charset, index)
    local ok, name = pcall(getAnimClipName, charset, index)
    return ok and tostring(name) or "?"
end


--- What tracks 0-3 play now, one line each.
local function tracks(charset)
    local lines = {}
    for t = 0, EqFlyProbe.TRACKS - 1 do
        local ok, clip = pcall(getAnimTrackAssignedClip, charset, t)
        local _, weight = pcall(getAnimTrackBlendWeight, charset, t)
        local _, time = pcall(getAnimTrackTime, charset, t)
        local length = nil
        if ok and type(clip) == "number" and clip >= 0 then
            local okLength, l = pcall(getAnimClipDuration, charset, clip)
            if okLength then length = tonumber(l) end
        end
        local name = (ok and type(clip) == "number" and clip >= 0) and clipName(charset, clip) or "-"
        local share = (length ~= nil and length > 0 and type(time) == "number") and string.format(" (%.2f of %.0f ms)", (time % length) / length, length) or ""
        table.insert(lines, string.format("  track %d: %s weight %.2f time %.0f%s", t, name, tonumber(weight) or -1, tonumber(time) or -1, share))
    end
    return lines
end


local function gaitName(spec)
    if Rideable == nil or Rideable.GAITTYPES == nil or spec.inputValues == nil then return "?" end
    for name, value in pairs(Rideable.GAITTYPES) do
        if value == spec.inputValues.currentGait and name ~= "MAX" then return name end
    end
    return "?"
end


--- Whether the legs show trot at this time (pure).
--- @param now number ms
function EqFlyProbe.inBlip(now)
    local blip = EqFlyProbe.blip
    if blip == nil then return false end
    if now >= blip.to then
        EqFlyProbe.blip = nil
        return false
    end
    return now >= blip.from
end


--- The horse flipped left to right, or put back. Its skeleton's root is scaled -1 across.
local function setMirror(vehicle, mirrored)
    local spec = vehicle.spec_rideable
    local node = spec.animationNode
    if node == nil or not entityExists(node) then return end
    for _ = 1, EqFlyProbe.mirrorUp do
        local parent = getParent(node)
        if parent == nil or parent == 0 or parent == vehicle.rootNode then break end
        node = parent
    end
    if mirrored then
        Log:info("eqFlyProbe mirror: scaling '%s' (%d up from the skeleton)", getName(node), EqFlyProbe.mirrorUp)
        EqFlyProbe.mirrorNode = node
        setScale(node, -1, 1, 1)
    elseif EqFlyProbe.mirrorNode ~= nil and entityExists(EqFlyProbe.mirrorNode) then
        setScale(EqFlyProbe.mirrorNode, 1, 1, 1)
        EqFlyProbe.mirrorNode = nil
    end
    EqFlyProbe.mirrored = mirrored
end


--- The tracks playing a clip whose name has `part`, with weight: { track, length, time }.
local function clipTracks(charset, part)
    local list = {}
    for t = 0, EqFlyProbe.TRACKS - 1 do
        local ok, clip = pcall(getAnimTrackAssignedClip, charset, t)
        if ok and type(clip) == "number" and clip >= 0 and string.find(string.lower(clipName(charset, clip)), part, 1, true) ~= nil then
            local _, length = pcall(getAnimClipDuration, charset, clip)
            local _, time = pcall(getAnimTrackTime, charset, t)
            local _, weight = pcall(getAnimTrackBlendWeight, charset, t)
            table.insert(list, { track = t, length = tonumber(length) or 0, time = tonumber(time) or 0, weight = tonumber(weight) or 0 })
        end
    end
    return list
end


--- Every track playing `part` set to `share` of its clip.
local function setShare(charset, part, share)
    for _, entry in ipairs(clipTracks(charset, part)) do
        if entry.length > 0 then pcall(setAnimTrackTime, charset, entry.track, share * entry.length, true) end
    end
end


--- Whether the canter has just passed `phase` (pure): from last to now, shares 0..1, wrapping.
function EqFlyProbe.crossed(last, now, phase)
    if last == nil or now == nil then return false end
    if now >= last then return last < phase and phase <= now end
    return phase > last or phase <= now
end


--- R (or auto): a change.
local function change(vehicle)
    local spec = vehicle.spec_rideable
    local now = g_time or 0
    if EqFlyProbe.mode == "mirror" then
        EqFlyProbe.flipAt = now + EqFlyProbe.delayMs
    else
        if EqFlyProbe.phase ~= nil then
            EqFlyProbe.pending = { since = now }
        else
            EqFlyProbe.blip = { from = now + EqFlyProbe.delayMs, to = now + EqFlyProbe.delayMs + EqFlyProbe.blipMs }
        end
    end
    EqFlyProbe.count = EqFlyProbe.count + 1
    local where = spec.charsetId ~= nil and table.concat(tracks(spec.charsetId), "\n") or ""
    Log:info("eqFlyProbe change %d (%s) at %s %.1f km/h (blip %d ms at %.2f of trot, delay %d ms)\n%s", EqFlyProbe.count, EqFlyProbe.mode,
        gaitName(spec), (vehicle.lastSignedSpeedReal or 0) * 3600, EqFlyProbe.blipMs, EqFlyProbe.speedShare, EqFlyProbe.delayMs, where)
end


function EqFlyProbe.active()
    return EqFlyProbe.on or EqFlyProbe.watchUntil ~= nil or EqFlyProbe.slow ~= 1 or EqFlyProbe.slowSet or EqFlyProbe.mirrored
end


--- Tracks 0-3 at the slow speed, or back to normal once (slowSet).
local function applySlow(spec)
    if spec.charsetId == nil then return end
    if EqFlyProbe.slow ~= 1 then
        for t = 0, EqFlyProbe.TRACKS - 1 do pcall(setAnimTrackSpeedScale, spec.charsetId, t, EqFlyProbe.slow) end
        EqFlyProbe.slowSet = true
    elseif EqFlyProbe.slowSet then
        for t = 0, EqFlyProbe.TRACKS - 1 do pcall(setAnimTrackSpeedScale, spec.charsetId, t, 1) end
        EqFlyProbe.slowSet = false
    end
end


--- What the probe is doing, big in the middle of the screen.
function EqFlyProbe.draw(vehicle)
    if not EqFlyProbe.on or vehicle ~= EqFlyProbe.horse() then return end
    local text
    if EqFlyProbe.inBlip(g_time or 0) then
        text = string.format("CHANGE %d", EqFlyProbe.count)
    elseif EqFlyProbe.mode == "reverse" then
        local function share(v) return v ~= nil and string.format("%.2f", v) or "-" end
        text = string.format("Flying change test (reverse): R  (blip %d ms, reverse x%.2f, phase %s)", EqFlyProbe.blipMs,
            EqFlyProbe.reverseScale, share(EqFlyProbe.phase))
    elseif EqFlyProbe.mode == "mirror" then
        text = string.format("Flying change test (mirror): R  - now %s", EqFlyProbe.mirrored and "MIRRORED" or "normal")
    else
        local function share(v) return v ~= nil and string.format("%.2f", v) or "-" end
        text = string.format("Flying change test (blip): R  (blip %d ms, speed %.2f, phase %s, trot %s, out %s)", EqFlyProbe.blipMs,
            EqFlyProbe.speedShare, share(EqFlyProbe.phase), share(EqFlyProbe.trotPhase), share(EqFlyProbe.outPhase))
    end
    if EqFlyProbe.autoMs ~= nil then text = text .. string.format("  - auto every %.1f s", EqFlyProbe.autoMs / 1000) end
    if EqFlyProbe.slow ~= 1 then text = text .. string.format("  - slow x%.2f", EqFlyProbe.slow) end
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 0.85, 0.2, 1)
    renderText(0.5, 0.82, 0.025, text)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end


function EqFlyProbe.install()
    if Rideable == nil or type(Rideable.updateAnimation) ~= "function" then
        Log:warning("EqFlyProbe: Rideable.updateAnimation not found; eqFlyProbe won't work")
        return
    end
    Rideable.updateAnimation = Utils.overwrittenFunction(Rideable.updateAnimation, function(self, superFunc, dt)
        if not EqFlyProbe.active() or self ~= EqFlyProbe.horse() then return superFunc(self, dt) end
        local spec = self.spec_rideable
        local now = g_time or 0
        if EqFlyProbe.on then
            local down = Input ~= nil and Input.KEY_r ~= nil and Input.isKeyPressed ~= nil and Input.isKeyPressed(Input.KEY_r) == true
            if down and not EqFlyProbe.rDown then EqLog.try("EqFlyProbe R", change, self) end
            EqFlyProbe.rDown = down
            if EqFlyProbe.autoMs ~= nil and now >= EqFlyProbe.nextAuto then
                EqFlyProbe.nextAuto = now + EqFlyProbe.autoMs
                EqLog.try("EqFlyProbe auto", change, self)
            end
            if EqFlyProbe.flipAt ~= nil and now >= EqFlyProbe.flipAt then
                EqFlyProbe.flipAt = nil
                EqLog.try("EqFlyProbe flip", setMirror, self, not EqFlyProbe.mirrored)
            end
        end
        -- A change waiting for its point in the canter's stride.
        local pending = EqFlyProbe.pending
        if pending ~= nil and spec.charsetId ~= nil and now >= pending.since + EqFlyProbe.delayMs then
            local canter = clipTracks(spec.charsetId, "canter")
            local share = nil
            for _, entry in ipairs(canter) do
                if entry.weight > 0.01 and entry.length > 0 then share = (entry.time % entry.length) / entry.length break end
            end
            if EqFlyProbe.crossed(pending.last, share, EqFlyProbe.phase) or now > pending.since + EqFlyProbe.delayMs + EqFlyProbe.WAIT_MS then
                EqFlyProbe.pending = nil
                EqFlyProbe.blip = { from = now, to = now + EqFlyProbe.blipMs }
                Log:info("eqFlyProbe blip starts at canter %s", share ~= nil and string.format("%.2f", share) or "(none, waited too long)")
            else
                pending.last = share
            end
        end
        -- In a blip the animation sees the trot's speed; the horse keeps its own.
        local real, smooth = self.lastSignedSpeedReal, self.lastSignedSpeed
        local shown = nil
        local blipping = EqFlyProbe.on and EqFlyProbe.inBlip(now)
        if blipping and EqFlyProbe.mode == "blip" and type(real) == "number" and spec.topSpeeds ~= nil
            and Rideable.GAITTYPES ~= nil and type(spec.topSpeeds[Rideable.GAITTYPES.TROT]) == "number" then
            shown = spec.topSpeeds[Rideable.GAITTYPES.TROT] * EqFlyProbe.speedShare / 1000
            if real < 0 then shown = -shown end
            self.lastSignedSpeedReal = shown
            if type(smooth) == "number" then self.lastSignedSpeed = shown end
        end
        local result = { EqLog.finally(function()
            if shown ~= nil then self.lastSignedSpeedReal, self.lastSignedSpeed = real, smooth end
        end, superFunc, self, dt) }
        EqLog.try("EqFlyProbe slow", applySlow, spec)
        -- Line the clips up as the blip starts and ends (after the base game's update, which is
        -- what the engine draws).
        local inBlip = blipping
        if spec.charsetId ~= nil and EqFlyProbe.mode == "reverse" then
            -- Backwards through the blip, forwards again after (the slow setting, or normal).
            if inBlip then
                for t = 0, EqFlyProbe.TRACKS - 1 do pcall(setAnimTrackSpeedScale, spec.charsetId, t, -EqFlyProbe.reverseScale * EqFlyProbe.slow) end
            elseif EqFlyProbe.wasBlip then
                for t = 0, EqFlyProbe.TRACKS - 1 do pcall(setAnimTrackSpeedScale, spec.charsetId, t, EqFlyProbe.slow) end
            end
        end
        if spec.charsetId ~= nil and EqFlyProbe.mode == "blip" then
            if inBlip and not EqFlyProbe.wasBlip and EqFlyProbe.trotPhase ~= nil then
                EqLog.try("EqFlyProbe trot phase", setShare, spec.charsetId, "trot", EqFlyProbe.trotPhase)
            elseif not inBlip and EqFlyProbe.wasBlip and EqFlyProbe.outPhase ~= nil then
                EqLog.try("EqFlyProbe out phase", setShare, spec.charsetId, "canter", EqFlyProbe.outPhase)
            end
        end
        EqFlyProbe.wasBlip = inBlip
        -- Kept flipped every frame, in case anything sets the node's scale back.
        if EqFlyProbe.mirrored and EqFlyProbe.mirrorNode ~= nil and entityExists(EqFlyProbe.mirrorNode) then
            setScale(EqFlyProbe.mirrorNode, -1, 1, 1)
        end
        if EqFlyProbe.watchUntil ~= nil and now >= EqFlyProbe.watchNext and spec.charsetId ~= nil then
            EqFlyProbe.watchNext = now + 250
            Log:info("eqFlyProbe watch %s %.1f km/h%s:\n%s", gaitName(spec), (real or 0) * 3600, shown ~= nil and " (blip)" or "",
                table.concat(tracks(spec.charsetId), "\n"))
            if now >= EqFlyProbe.watchUntil then EqFlyProbe.watchUntil = nil end
        end
        return unpack(result, 1, table.maxn(result))
    end)
    if type(Rideable.onDraw) == "function" then
        Rideable.onDraw = Utils.appendedFunction(Rideable.onDraw, function(self)
            if EqFlyProbe.on then EqLog.try("EqFlyProbe draw", EqFlyProbe.draw, self) end
        end)
    end
end


--- @param args string[] the words after eqFlyProbe
function EqFlyProbe.console(args)
    local command = string.lower(args[1] or "")
    local word = string.lower(args[2] or "")
    local number = tonumber(args[2])
    local vehicle = EqFlyProbe.horse()
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    if command == "off" then
        EqFlyProbe.on, EqFlyProbe.blip, EqFlyProbe.flipAt, EqFlyProbe.watchUntil, EqFlyProbe.autoMs = false, nil, nil, nil, nil
        EqFlyProbe.slow = 1
        if EqFlyProbe.mirrored then
            if vehicle ~= nil then setMirror(vehicle, false) else EqFlyProbe.mirrored = false end
        end
        return say("off")
    end
    if command == "on" then
        EqFlyProbe.on = true
        return say("on (%s): R makes a change", EqFlyProbe.mode)
    end
    if command == "mode" then
        if word ~= "blip" and word ~= "mirror" and word ~= "reverse" then return say("mode blip|mirror|reverse") end
        EqFlyProbe.mode = word
        return say("mode %s", word)
    end
    if command == "demo" then
        if word == "blip" or word == "mirror" or word == "reverse" then EqFlyProbe.mode = word end
        EqFlyProbe.on, EqFlyProbe.autoMs = true, 3000
        EqFlyProbe.nextAuto = (g_time or 0) + EqFlyProbe.autoMs
        return say("%s change every 3 s (R too): close the console and canter straight", EqFlyProbe.mode)
    end
    if command == "mirror" then
        if spec == nil then return say("ride a horse first") end
        if number ~= nil then
            if EqFlyProbe.mirrored then setMirror(vehicle, false) end
            EqFlyProbe.mirrorUp = math.max(0, math.min(4, math.floor(number)))
        end
        setMirror(vehicle, not EqFlyProbe.mirrored)
        return say(EqFlyProbe.mirrored and "mirrored" or "normal")
    end
    if command == "auto" then
        if word == "off" then
            EqFlyProbe.autoMs = nil
            return say("auto off")
        end
        EqFlyProbe.on = true
        EqFlyProbe.autoMs = math.max(500, math.floor((number or 3) * 1000))
        EqFlyProbe.nextAuto = (g_time or 0) + EqFlyProbe.autoMs
        return say("a change every %.1f s", EqFlyProbe.autoMs / 1000)
    end
    if command == "blip" and number ~= nil then
        EqFlyProbe.blipMs = math.max(0, math.floor(number))
        return say("blip %d ms", EqFlyProbe.blipMs)
    end
    if command == "phase" or command == "trotphase" or command == "outphase" then
        local value = (word == "off" or word == "") and nil or (number ~= nil and math.max(0, math.min(1, number)) or nil)
        if word ~= "off" and word ~= "" and value == nil then return say("%s <0-1>|off", command) end
        if command == "phase" then EqFlyProbe.phase = value elseif command == "trotphase" then EqFlyProbe.trotPhase = value else EqFlyProbe.outPhase = value end
        return say("%s %s", command, value ~= nil and string.format("%.2f", value) or "off")
    end
    if command == "reverse" and number ~= nil then
        EqFlyProbe.reverseScale = math.max(0.1, math.min(3, number))
        return say("reverse at x%.2f", EqFlyProbe.reverseScale)
    end
    if command == "speed" and number ~= nil then
        EqFlyProbe.speedShare = math.max(0, math.min(1.5, number))
        return say("speed %.2f of the trot's top", EqFlyProbe.speedShare)
    end
    if command == "delay" and number ~= nil then
        EqFlyProbe.delayMs = math.max(0, math.floor(number))
        return say("delay %d ms", EqFlyProbe.delayMs)
    end
    if command == "slow" and number ~= nil then
        EqFlyProbe.slow = math.max(0.1, math.min(1, number))
        return say("animation speed x%.2f", EqFlyProbe.slow)
    end
    if command == "watch" then
        if spec == nil then return say("ride a horse first") end
        local seconds = number or 10
        EqFlyProbe.watchUntil, EqFlyProbe.watchNext = (g_time or 0) + seconds * 1000, 0
        return say("logging tracks 0-3 for %d s", seconds)
    end
    if command == "clips" then
        if spec == nil or spec.charsetId == nil then return say("ride a horse first") end
        local ok, count = pcall(getAnimNumOfClips, spec.charsetId)
        count = ok and tonumber(count) or 0
        for i = 0, count - 1 do
            local okLength, length = pcall(getAnimClipDuration, spec.charsetId, i)
            Log:info("eqFlyProbe clip %d %s (%.0f ms)", i, clipName(spec.charsetId, i), okLength and tonumber(length) or -1)
        end
        return say("%d clips written to log.txt", count)
    end
    return say("eqFlyProbe demo [blip|mirror|reverse] | on | off | mode blip|mirror|reverse | reverse <x> | mirror [0-4] | blip <ms> | speed <0-1.5> | delay <ms> | phase/trotphase/outphase <0-1>|off | auto [s|off] | slow <0.1-1> | watch [s] | clips")
end

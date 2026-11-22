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
      mode blip|mirror      which kind of change R makes (default blip)
      mirror                flips the horse now, to look at it standing still (again to flip back)
      blip <ms>             how long the legs show trot (default 350)
      speed <0-1.5>         the speed the legs are shown at, as a share of the trot's top (default 1)
      delay <ms>            how long after R the change starts (default 0)
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
EqFlyProbe.flipAt = nil     -- ms: the mirror flips then
EqFlyProbe.mirrored = false
EqFlyProbe.mirrorNode = nil -- the node scaled, to put back
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
local function setMirror(spec, mirrored)
    local node = spec.animationNode
    if node == nil or not entityExists(node) then return end
    if mirrored then
        EqFlyProbe.mirrorNode = node
        setScale(node, -1, 1, 1)
    elseif EqFlyProbe.mirrorNode ~= nil and entityExists(EqFlyProbe.mirrorNode) then
        setScale(EqFlyProbe.mirrorNode, 1, 1, 1)
        EqFlyProbe.mirrorNode = nil
    end
    EqFlyProbe.mirrored = mirrored
end


--- R (or auto): a change.
local function change(vehicle)
    local spec = vehicle.spec_rideable
    local now = g_time or 0
    if EqFlyProbe.mode == "mirror" then
        EqFlyProbe.flipAt = now + EqFlyProbe.delayMs
    else
        EqFlyProbe.blip = { from = now + EqFlyProbe.delayMs, to = now + EqFlyProbe.delayMs + EqFlyProbe.blipMs }
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
    elseif EqFlyProbe.mode == "mirror" then
        text = string.format("Flying change test (mirror): R  - now %s", EqFlyProbe.mirrored and "MIRRORED" or "normal")
    else
        text = string.format("Flying change test (blip): R  (blip %d ms, speed %.2f, delay %d ms)", EqFlyProbe.blipMs, EqFlyProbe.speedShare, EqFlyProbe.delayMs)
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
                EqLog.try("EqFlyProbe flip", setMirror, spec, not EqFlyProbe.mirrored)
            end
        end
        -- In a blip the animation sees the trot's speed; the horse keeps its own.
        local real, smooth = self.lastSignedSpeedReal, self.lastSignedSpeed
        local shown = nil
        if EqFlyProbe.on and EqFlyProbe.inBlip(now) and type(real) == "number" and spec.topSpeeds ~= nil
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
            if spec ~= nil then setMirror(spec, false) else EqFlyProbe.mirrored = false end
        end
        return say("off")
    end
    if command == "on" then
        EqFlyProbe.on = true
        return say("on (%s): R makes a change", EqFlyProbe.mode)
    end
    if command == "mode" then
        if word ~= "blip" and word ~= "mirror" then return say("mode blip|mirror") end
        EqFlyProbe.mode = word
        return say("mode %s", word)
    end
    if command == "demo" then
        if word == "blip" or word == "mirror" then EqFlyProbe.mode = word end
        EqFlyProbe.on, EqFlyProbe.autoMs = true, 3000
        EqFlyProbe.nextAuto = (g_time or 0) + EqFlyProbe.autoMs
        return say("%s change every 3 s (R too): close the console and canter straight", EqFlyProbe.mode)
    end
    if command == "mirror" then
        if spec == nil then return say("ride a horse first") end
        setMirror(spec, not EqFlyProbe.mirrored)
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
    return say("eqFlyProbe demo [blip|mirror] | on | off | mode blip|mirror | mirror | blip <ms> | speed <0-1.5> | delay <ms> | auto [s|off] | slow <0.1-1> | watch [s] | clips")
end

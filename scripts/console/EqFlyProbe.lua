--[[
    EqFlyProbe.lua
    Testing aid for a flying change (James, 2026-11-23). The ridden horse has a canter left and a
    canter right clip, which the base game blends by the turn (the leftRightWeight animation
    parameter). If they are the two leads, a flying change is a quick swap from one to the other
    at the moment of suspension. This holds the blend on one side while riding straight, and R
    swaps it, so James can watch the front legs and tune the timing. eqFlyProbe, while riding:
      left | right          holds the canter on that side's clip (any gait; watch it at a canter)
      off                   lets the turn drive the blend again
      weight <0-1>          how far to the side the hold goes (default 1)
      blend <ms>            how long R's swap takes (default 150)
      delay <ms>            how long after R the swap starts (default 0)
      auto [seconds|off]    swaps sides by itself every few seconds (default 3), hands free
      slow <0.1-1>          plays the leg animation slower (1 = normal) so the legs are easy to see
      demo                  left + auto 3 + slow 0.4 in one go: type it, close the console, canter
      watch [seconds]       logs animation tracks 0-3 (clip, weight, time) every 250 ms
      clips                 writes the horse's animation clips (names and lengths) to log.txt
    R (keyboard): swaps the held side, logging where the canter clip was in its stride.
    Dev only: not wired into anything else, keep out of release builds.
]]

EqFlyProbe = {}
EqFlyProbe.side = nil       -- -1 left, 1 right, nil off
EqFlyProbe.weight = 1
EqFlyProbe.blendMs = 150
EqFlyProbe.delayMs = 0
EqFlyProbe.swap = nil       -- { from, to, at } the swap under way
EqFlyProbe.rDown = false
EqFlyProbe.autoMs = nil     -- swap by itself this often
EqFlyProbe.nextAuto = 0
EqFlyProbe.slow = 1         -- animation speed scale on tracks 0-3
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


--- The held blend value now (pure): the side times the weight, or part way through a swap.
--- @param now number ms
--- @return number|nil
function EqFlyProbe.valueAt(now)
    if EqFlyProbe.side == nil then return nil end
    local swap = EqFlyProbe.swap
    if swap == nil then return EqFlyProbe.side * EqFlyProbe.weight end
    if now < swap.at then return swap.from end
    local t = EqFlyProbe.blendMs > 0 and math.min(1, (now - swap.at) / EqFlyProbe.blendMs) or 1
    if t >= 1 then
        EqFlyProbe.swap = nil
        return swap.to
    end
    return swap.from + (swap.to - swap.from) * t
end


local function gaitName(spec)
    if Rideable == nil or Rideable.GAITTYPES == nil or spec.inputValues == nil then return "?" end
    for name, value in pairs(Rideable.GAITTYPES) do
        if value == spec.inputValues.currentGait and name ~= "MAX" then return name end
    end
    return "?"
end


--- R (or auto): swap to the other side.
local function onR(vehicle)
    if EqFlyProbe.side == nil then return end
    local spec = vehicle.spec_rideable
    local now = g_time or 0
    local from = EqFlyProbe.valueAt(now) or 0
    EqFlyProbe.side = -EqFlyProbe.side
    EqFlyProbe.swap = { from = from, to = EqFlyProbe.side * EqFlyProbe.weight, at = now + EqFlyProbe.delayMs }
    local where = spec.charsetId ~= nil and table.concat(tracks(spec.charsetId), "\n") or ""
    Log:info("eqFlyProbe R at %s %.1f km/h: now %s (blend %d ms, delay %d ms)\n%s", gaitName(spec),
        (vehicle.lastSignedSpeedReal or 0) * 3600, EqFlyProbe.side < 0 and "left" or "right", EqFlyProbe.blendMs, EqFlyProbe.delayMs, where)
    if g_currentMission ~= nil and g_currentMission.showBlinkingWarning ~= nil then
        pcall(g_currentMission.showBlinkingWarning, g_currentMission, EqFlyProbe.side < 0 and "Change: left" or "Change: right", 800)
    end
end


function EqFlyProbe.active()
    return EqFlyProbe.side ~= nil or EqFlyProbe.watchUntil ~= nil or EqFlyProbe.slow ~= 1 or EqFlyProbe.slowSet
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


--- The side held now, big in the middle of the screen, so it can be read while watching the legs.
function EqFlyProbe.draw(vehicle)
    if EqFlyProbe.side == nil or vehicle ~= EqFlyProbe.horse() then return end
    local text = EqFlyProbe.side < 0 and "LEFT clip" or "RIGHT clip"
    if EqFlyProbe.swap ~= nil then text = text .. " (swapping)" end
    if EqFlyProbe.autoMs ~= nil then text = text .. string.format("  - auto every %.1f s", EqFlyProbe.autoMs / 1000) end
    if EqFlyProbe.slow ~= 1 then text = text .. string.format("  - slow x%.2f", EqFlyProbe.slow) end
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 0.85, 0.2, 1)
    renderText(0.5, 0.82, 0.03, text)
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
        -- R, on the way down.
        local down = Input ~= nil and Input.KEY_r ~= nil and Input.isKeyPressed ~= nil and Input.isKeyPressed(Input.KEY_r) == true
        if down and not EqFlyProbe.rDown then EqLog.try("EqFlyProbe R", onR, self) end
        local now = g_time or 0
        if EqFlyProbe.autoMs ~= nil and EqFlyProbe.side ~= nil and now >= EqFlyProbe.nextAuto then
            EqFlyProbe.nextAuto = now + EqFlyProbe.autoMs
            EqLog.try("EqFlyProbe auto", onR, self)
        end
        EqFlyProbe.rDown = down
        -- The base game eases its blend from where it was left towards the turn's by at most
        -- dt/500: start it from the held value, and put its own back after.
        local value = EqFlyProbe.valueAt(g_time or 0)
        local own = spec.smoothedLeftRightWeight
        if value ~= nil then spec.smoothedLeftRightWeight = value end
        local result = { EqLog.finally(function() if value ~= nil then spec.smoothedLeftRightWeight = own end end, superFunc, self, dt) }
        EqLog.try("EqFlyProbe slow", applySlow, spec)
        if EqFlyProbe.watchUntil ~= nil and (g_time or 0) >= EqFlyProbe.watchNext and spec.charsetId ~= nil then
            EqFlyProbe.watchNext = (g_time or 0) + 250
            Log:info("eqFlyProbe watch %s %.1f km/h blend %.2f:\n%s", gaitName(spec), (self.lastSignedSpeedReal or 0) * 3600,
                value or own or 0, table.concat(tracks(spec.charsetId), "\n"))
            if (g_time or 0) >= EqFlyProbe.watchUntil then EqFlyProbe.watchUntil = nil end
        end
        return unpack(result, 1, table.maxn(result))
    end)
    if type(Rideable.onDraw) == "function" then
        Rideable.onDraw = Utils.appendedFunction(Rideable.onDraw, function(self)
            if EqFlyProbe.side ~= nil then EqLog.try("EqFlyProbe draw", EqFlyProbe.draw, self) end
        end)
    end
end


--- @param args string[] the words after eqFlyProbe
function EqFlyProbe.console(args)
    local command = string.lower(args[1] or "")
    local number = tonumber(args[2])
    if command == "off" then
        EqFlyProbe.side, EqFlyProbe.swap, EqFlyProbe.watchUntil, EqFlyProbe.autoMs = nil, nil, nil, nil
        EqFlyProbe.slow = 1
        return say("off")
    end
    if command == "auto" then
        if string.lower(args[2] or "") == "off" then
            EqFlyProbe.autoMs = nil
            return say("auto off")
        end
        EqFlyProbe.autoMs = math.max(500, math.floor((number or 3) * 1000))
        EqFlyProbe.nextAuto = (g_time or 0) + EqFlyProbe.autoMs
        EqFlyProbe.side = EqFlyProbe.side or -1
        return say("swapping every %.1f s", EqFlyProbe.autoMs / 1000)
    end
    if command == "slow" and number ~= nil then
        EqFlyProbe.slow = math.max(0.1, math.min(1, number))
        return say("animation speed x%.2f", EqFlyProbe.slow)
    end
    if command == "demo" then
        EqFlyProbe.side, EqFlyProbe.swap, EqFlyProbe.slow = -1, nil, 0.4
        EqFlyProbe.autoMs = 3000
        EqFlyProbe.nextAuto = (g_time or 0) + EqFlyProbe.autoMs
        return say("left clip, swapping every 3 s, animation x0.4: close the console and canter straight")
    end
    if command == "left" or command == "right" then
        EqFlyProbe.side, EqFlyProbe.swap = command == "left" and -1 or 1, nil
        return say("holding the %s clip at weight %.2f; R swaps (blend %d ms, delay %d ms)", command, EqFlyProbe.weight, EqFlyProbe.blendMs, EqFlyProbe.delayMs)
    end
    if command == "weight" and number ~= nil then
        EqFlyProbe.weight = math.max(0, math.min(1, number))
        return say("weight %.2f", EqFlyProbe.weight)
    end
    if command == "blend" and number ~= nil then
        EqFlyProbe.blendMs = math.max(0, math.floor(number))
        return say("blend %d ms", EqFlyProbe.blendMs)
    end
    if command == "delay" and number ~= nil then
        EqFlyProbe.delayMs = math.max(0, math.floor(number))
        return say("delay %d ms", EqFlyProbe.delayMs)
    end
    local vehicle = EqFlyProbe.horse()
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
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
    return say("eqFlyProbe demo | left | right | off | auto [s|off] | slow <0.1-1> | weight <0-1> | blend <ms> | delay <ms> | watch [s] | clips  (R swaps while holding)")
end

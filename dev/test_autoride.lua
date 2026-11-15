--[[
    Headless tests for the dev autopilot. From the repo root:  luajit dev/test_autoride.lua
    The horse is simulated like Rideable:updateKinematic: turn speed eased towards
    maxTurnSpeed * axisSteer, speed eased towards the gait's top speed, moved along the heading.
]]

dofile("scripts/training/EqCourse.lua")
dofile("dev/EqAutoRide.lua")

local A = EqAutoRide
local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. (detail and (": " .. detail) or "")) end
end

local TOP = { walk = 1.6, trot = 3.6, canter = 6, gallop = 11, halt = 0 }

-- Ride play from (x, z, heading); returns the worst distance off the route, gaits seen in order,
-- whether it finished, and the horse.
local function simulate(points, x, z, heading, loop, seconds)
    local play = A.newPlay(points, x, z, loop)
    local horse = { x = x, z = z, a = heading, speed = 0, turn = 0 }
    local worst, gaits, done = 0, {}, false
    local dt = 1 / 60
    local maxTurn = 1.2
    for _ = 1, math.floor((seconds or 120) / dt) do
        local steer, gait, finished = A.drive(play, horse.x, horse.z, horse.a, horse.speed, maxTurn)
        if gaits[#gaits] ~= gait then table.insert(gaits, gait) end
        if finished then done = true break end
        local want = TOP[gait]
        horse.speed = horse.speed + math.max(-4 * dt, math.min(4 * dt, want - horse.speed))
        local wantTurn = maxTurn * steer
        horse.turn = horse.turn + math.max(-1.2 * dt, math.min(1.2 * dt, wantTurn - horse.turn))
        horse.a = horse.a + horse.turn * dt
        horse.x = horse.x + math.sin(horse.a) * horse.speed * dt
        horse.z = horse.z + math.cos(horse.a) * horse.speed * dt
        local i = A.nearestIndex(play.path, horse.x, horse.z)
        local p = play.path[i]
        local off = math.sqrt((p.x - horse.x) ^ 2 + (p.z - horse.z) ^ 2)
        if horse.speed > 1 and off > worst then worst = off end
    end
    return worst, gaits, done, horse, play
end

-- Angles.
check("wrap: 3pi is pi", math.abs(math.abs(A.wrap(3 * math.pi)) - math.pi) < 1e-9)
check("heading: +z is 0", math.abs(A.headingTo(0, 0, 0, 5)) < 1e-9)
check("heading: +x is pi/2 (left turn from +z)", math.abs(A.headingTo(0, 0, 5, 0) - math.pi / 2) < 1e-9)

-- A straight then a wide right-hand bend, trot then canter.
local route = {}
for i = 0, 6 do table.insert(route, { x = 0, y = 0, z = i * 10, gait = "trot" }) end
for k = 1, 12 do
    local t = k / 12 * math.pi / 2
    table.insert(route, { x = -20 + 20 * math.cos(t), y = 0, z = 60 + 20 * math.sin(t), gait = "canter" })
end
for i = 1, 4 do table.insert(route, { x = -20 - i * 10, y = 0, z = 80, gait = "canter" }) end
local worst, gaits, done = simulate(route, 0, 0, 0, false, 120)
check("route: stays on the line", worst < 1.0, string.format("%.2f m off", worst))
check("route: trot then canter then halt", gaits[1] == "trot" and gaits[2] == "canter" and gaits[#gaits] == "halt", table.concat(gaits, ","))
check("route: finishes", done)

-- Starting off the line and facing the wrong way still gets onto it.
worst, gaits, done = simulate(route, 6, 5, math.pi, false, 120)
check("route: rides back onto the line from 6 m off, facing away", done)

-- A 20 m circle at a canter, looped: never finishes, stays close.
local circle = {}
for k = 0, 36 do
    local t = k / 36 * 2 * math.pi
    table.insert(circle, { x = 20 * math.sin(t), y = 0, z = -20 + 20 * math.cos(t), gait = "canter" })
end
local _, _, finished, horse, play = simulate(circle, 0, 0, math.pi / 2, true, 60)
check("loop: never ends", not finished)
worst = simulate(circle, 0, 0, math.pi / 2, true, 60)
check("loop: holds a 20 m circle at a canter", worst < 1.2, string.format("%.2f m off", worst))

-- A figure of eight crosses itself: ridden in order, not cut short at the crossing.
local eight = {}
for k = 0, 48 do
    local t = k / 48 * 2 * math.pi
    table.insert(eight, { x = 15 * math.sin(t), y = 0, z = 15 * math.sin(t) * math.cos(t), gait = "trot" })
end
local w8, _, done8, _, play8 = simulate(eight, 0, 0, math.atan2(15, 15), false, 120)
check("eight: finishes in order", done8 and play8.index >= #play8.path - 1)
check("eight: on the line", w8 < 1.2, string.format("%.2f m off", w8))

-- Recording keeps gaits and drops a point at each change.
local rec = EqCourse.newRecording(0, 0, 0)
rec.points[1].gait = nil
for z = 1, 30 do A.recordStep(rec, 0, 0, z, "trot") end
A.recordStep(rec, 0, 0, 30.5, "canter")
for z = 31, 60 do A.recordStep(rec, 0, 0, z, "canter") end
A.recordStep(rec, 0, 0, 61, "halt")
check("record: first point gets the first gait", rec.points[1].gait == "trot")
local changeAt
for i, p in ipairs(rec.points) do if p.gait == "canter" and changeAt == nil then changeAt = p.z end end
check("record: point dropped where the gait changed", changeAt == 30.5, tostring(changeAt))
check("record: halts are not recorded", rec.points[#rec.points].gait ~= "halt")

-- Save format.
local back = A.decode(A.encode(rec.points))
check("encode/decode round trip", #back == #rec.points and back[2].gait == rec.points[2].gait
    and math.abs(back[#back].z - rec.points[#rec.points].z) < 0.01)
check("decode: negative coordinates", A.decode("-1.50,2.00,-3.25,walk")[1].x == -1.5)

-- Courses without gaits ride at a canter.
check("densify: no gait is canter", A.densify({ { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 5 } })[1].gait == "canter")

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

--[[
    EqRandom.lua
    A small seeded random generator, so a horse seen for the first time always rolls the same
    stats from its RLRM identifier: a dealer horse shows the same numbers every time you look,
    and every peer would roll the same ones.

    It never touches math.random or math.randomseed, which RLRM and the game share.
]]

EqRandom = {}
EqRandom.__index = EqRandom

local MODULUS = 2147483647 -- 2^31 - 1, the Park-Miller prime
local MULTIPLIER = 48271

EqRandom.WARM_UP = 4


--- a * b mod MODULUS without going past the 2^53 a double holds exactly.
local function mulMod(a, b)
    local high, low = math.floor(b / 65536), b % 65536
    return ((a * high) % MODULUS * 65536 + a * low) % MODULUS
end


--- Hash a string to a seed in [1, MODULUS - 1]. Plain arithmetic, no bit library, so it gives
--- the same value on every Lua build the game might run. A djb2 pass, then a few non-linear
--- rounds: without them "result 11" and "result 12" hash a fixed step apart, and a linear
--- generator keeps that step in every draw, so near-identical seeds gave near-identical luck.
--- @param text string
--- @return number seed
function EqRandom.hashString(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + string.byte(text, i)) % MODULUS
    end
    for round = 1, 3 do
        h = (mulMod(h, h) + mulMod(h, 40692) + 1013904223 * round) % MODULUS
    end
    if h == 0 then h = 1 end
    return h
end


--- @param seed number|string A number, or a string hashed with hashString
--- @return table rng
function EqRandom.new(seed)
    if type(seed) == "string" then seed = EqRandom.hashString(seed) end
    seed = math.floor(tonumber(seed) or 1) % MODULUS
    if seed <= 0 then seed = seed + MODULUS - 1 end

    local self = setmetatable({}, EqRandom)
    self.state = seed
    -- Seeds from similar strings ("result 11", "result 12") sit close together, and the first
    -- draws of a Park-Miller generator stay close with them. A few discarded steps spread them.
    for _ = 1, EqRandom.WARM_UP do self:next() end
    return self
end


--- @return number value Uniform in (0, 1)
function EqRandom:next()
    self.state = (self.state * MULTIPLIER) % MODULUS
    return self.state / MODULUS
end


--- @param lo number
--- @param hi number
--- @return number value Uniform in (lo, hi)
function EqRandom:uniform(lo, hi)
    return lo + (hi - lo) * self:next()
end


--- Box-Muller normal draw.
--- @param mean number
--- @param sd number
--- @return number value
function EqRandom:normal(mean, sd)
    local u1, u2 = self:next(), self:next()
    return mean + sd * math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
end

--[[
    EqLog.lua
    Logging that is safe at source time.

    The game sources mods in alphabetical order, whatever modDesc dependencies say, so
    FS25_RealisticEquestrian runs before FS25_RealisticLivestockRM and RLRM's RmLogging does
    not exist yet when our files load. EqLog looks RmLogging up on each call and uses it once
    RLRM has loaded ("[RLEQ|H]" lines next to RLRM's); before that it prints plainly.
]]

EqLog = {}

EqLog.NAME = "RLEQ"

local logger = nil


--- @return table|nil logger RLRM's RmLogging logger for RLEQ, once RLRM has loaded
local function getLogger()
    if logger == nil and RmLogging ~= nil and RmLogging.getLogger ~= nil then
        logger = RmLogging.getLogger(EqLog.NAME)
    end
    return logger
end


--- @param level string RmLogging method name
--- @param prefix string|nil Printed prefix when RmLogging is missing; nil drops the line
local function emit(level, prefix, fmt, ...)
    local target = getLogger()
    if target ~= nil then
        target[level](target, fmt, ...)
    elseif prefix ~= nil then
        print(string.format("%s[%s] %s", prefix, EqLog.NAME, string.format(fmt, ...)))
    end
end


function EqLog:error(fmt, ...) emit("error", "Error: ", fmt, ...) end
function EqLog:warning(fmt, ...) emit("warning", "Warning: ", fmt, ...) end
function EqLog:info(fmt, ...) emit("info", "Info: ", fmt, ...) end
function EqLog:debug(fmt, ...) emit("debug", nil, fmt, ...) end
function EqLog:trace(fmt, ...) emit("trace", nil, fmt, ...) end


--[[
    Protected calls. Every pcall in the mod goes through here, so an error that is caught is
    always logged: GIANTS' TestRunner flags a bare pcall as hiding errors, and rightly so. Some
    callers run every frame, so each context logs its first failure in full and then only every
    1000th.
]]

local failureCounts = {}


--- The mod's one pcall.
local function protected(fn, ...)
    return pcall(fn, ...)
end


--- @param level string "warning" or "error"
local function report(level, context, err)
    local count = (failureCounts[context] or 0) + 1
    failureCounts[context] = count
    if count == 1 then
        EqLog[level](EqLog, "%s failed: %s", context, tostring(err))
    elseif count % 1000 == 0 then
        EqLog[level](EqLog, "%s has failed %d times", context, count)
    end
end


local function finish(level, context, ok, ...)
    if not ok then report(level, context, (...)) end
    return ok, ...
end


--- Call fn(...) and log a failure as a warning instead of raising it. Use it where the game or
--- RLRM may not have what we reach for, and carrying on without it is right.
--- @param context string Name for the log line
--- @return boolean ok, ... fn's results, as pcall returns them
function EqLog.try(context, fn, ...)
    return finish("warning", context, protected(fn, ...))
end


--- As EqLog.try, but logged as an error: for hook bodies that must never break the game's chain.
function EqLog.guard(context, fn, ...)
    return finish("error", context, protected(fn, ...))
end


local function restoreThen(restore, ok, ...)
    restore()
    if not ok then error((...), 0) end
    return ...
end


--- Call fn(...), run restore() whether it fails or not, then pass fn's results or error on.
--- Nothing is swallowed: an error is raised again after restore.
--- @param restore function
--- @param fn function
--- @return ... fn's results
function EqLog.finally(restore, fn, ...)
    return restoreThen(restore, protected(fn, ...))
end

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

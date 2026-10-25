--[[
    EqI18N.lua
    Our texts for code that looks them up without a mod name.

    The money popup, the Finances page and RLRM's message log call the game's I18N with no mod
    name, so they only see the global texts table. Inside a mod, g_i18n is a proxy holding only
    that mod's texts, and _G is the mod's own environment (its metatable's __index is the real
    global table), so _G.g_i18n is that same proxy: writing to its texts changes nothing global.

    Two things make our keys resolve, either of which is enough:
    - I18N.getText and I18N.hasText are hooked, as RLRM does for its money titles, to route a
      lookup without a mod name for one of our keys through our mod name.
    - Our texts are copied into the real global table.
]]

EqI18N = {}

EqI18N.MOD_NAME = g_currentModName
EqI18N.routed = {}
EqI18N.isInstalled = false


--- The game's own I18N, not this mod's proxy.
--- @return table|nil
function EqI18N.globalI18N()
    local mt = getmetatable(_G)
    local realG = mt ~= nil and type(mt.__index) == "table" and mt.__index or nil
    if realG ~= nil and realG.g_i18n ~= nil then return realG.g_i18n end
    return _G.g_i18n
end


--- Make these keys resolve in lookups without a mod name, and copy them into the global table.
--- Safe to call again: a text we don't have yet is skipped, so a "Missing" text can't stick.
--- @param keys table list of l10n keys
--- @param aliases table|nil map of extra key -> our key with its text (e.g. "finance_" rows)
function EqI18N.share(keys, aliases)
    for _, key in ipairs(keys) do EqI18N.routed[key] = key end
    for alias, key in pairs(aliases or {}) do EqI18N.routed[alias] = key end

    local global = EqI18N.globalI18N()
    if global == nil or type(global.texts) ~= "table" or g_i18n == nil then return end
    for name, key in pairs(EqI18N.routed) do
        if g_i18n:hasText(key) then global.texts[name] = g_i18n:getText(key) end
    end
end


--- Hook I18N so a lookup without a mod name finds our routed keys. Run once, at source time.
--- @return boolean ok
function EqI18N.install()
    if EqI18N.isInstalled then return true end
    if I18N == nil or I18N.getText == nil or Utils == nil or Utils.overwrittenFunction == nil then return false end
    local modName = EqI18N.MOD_NAME
    if modName == nil then return false end

    --- The key to look up in our texts, or nil to leave the lookup alone.
    local function ours(self, text, modEnv)
        if modEnv ~= nil or text == nil then return nil end
        local key = EqI18N.routed[text]
        if key == nil or (type(self.texts) == "table" and self.texts[text] ~= nil) then return nil end
        return key
    end

    I18N.getText = Utils.overwrittenFunction(I18N.getText, function(self, superFunc, text, modEnv)
        local key = ours(self, text, modEnv)
        if key ~= nil then return superFunc(self, key, modName) end
        return superFunc(self, text, modEnv)
    end)

    if I18N.hasText ~= nil then
        I18N.hasText = Utils.overwrittenFunction(I18N.hasText, function(self, superFunc, text, modEnv)
            local key = ours(self, text, modEnv)
            if key ~= nil and superFunc(self, key, modName) then return true end
            return superFunc(self, text, modEnv)
        end)
    end

    EqI18N.isInstalled = true
    return true
end

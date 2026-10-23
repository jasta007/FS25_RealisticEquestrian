--[[
    A small stand-in for the game's XMLFile, read-only, for headless tests of the XML config.
    Understands elements, attributes and "a.b.c(0)#attr" paths; nothing more.
]]

local TestXML = {}
TestXML.__index = TestXML

local function parse(text)
    text = text:gsub("<%?.-%?>", ""):gsub("<!%-%-.-%-%->", "")
    local root = { name = "#root", attrs = {}, children = {} }
    local stack = { root }
    for closing, name, attrText, selfClosing in text:gmatch("<(/?)([%w_]+)(.-)(/?)>") do
        if closing == "/" then
            table.remove(stack)
        else
            local node = { name = name, attrs = {}, children = {} }
            for key, value in attrText:gmatch('([%w_]+)="(.-)"') do node.attrs[key] = value end
            table.insert(stack[#stack].children, node)
            if selfClosing ~= "/" then table.insert(stack, node) end
        end
    end
    return root
end

function TestXML.load(path)
    local file = io.open(path, "r")
    if file == nil then return nil end
    local self = setmetatable({ root = parse(file:read("*a")) }, TestXML)
    file:close()
    return self
end

function TestXML:find(path)
    local elementPath, attr = path:match("^([^#]*)#?(.*)$")
    local node = self.root
    for part in elementPath:gmatch("[^%.]+") do
        local name, index = part:match("^([%w_]+)%((%d+)%)$")
        name = name or part
        index = tonumber(index) or 0
        local found, seen = nil, 0
        for _, child in ipairs(node.children) do
            if child.name == name then
                if seen == index then found = child break end
                seen = seen + 1
            end
        end
        if found == nil then return nil end
        node = found
    end
    if attr ~= "" then return node.attrs[attr] end
    return node
end

function TestXML:hasProperty(path) return self:find(path) ~= nil end
function TestXML:getString(path, default) local v = self:find(path); return type(v) == "string" and v or default end
function TestXML:getFloat(path, default) local v = tonumber(self:getString(path)); if v == nil then return default end return v end
function TestXML:getInt(path, default) local v = self:getFloat(path); if v == nil then return default end return math.floor(v) end
function TestXML:getBool(path, default) local v = self:getString(path); if v == nil then return default end return v == "true" end
function TestXML:delete() end

return TestXML

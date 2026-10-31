--[[
    EqDressageTests.lua
    Dressage tests the player puts together on one of our arenas (James, 2026-10-31), and the
    editor's state while they do. Pure functions with no game calls, so they run headless; the
    keys, camera and drawing are in EqDressageEditor.

    A test is a plan for EqDressagePath.build: the way the horse tracks at C after the opening
    halt, then the steps in order, each a figure or a movement on the spot at a letter. The
    editor shows the options for the next step from where the last one ended, nearest first:
    the player steps through them, or rolls a random one, keeps one and gets the options from
    its end. Saving adds the final centre line to a halt at X. A saved test is kept with its
    arena (by where the arena stands, so moving one loses it) until the player deletes it, and
    that arena rides it instead of a random test, in training and in your own events.

    Part of Realistic Equestrian by Jasta007.
]]

EqDressageTests = {}

-- A saved test belongs to the arena whose middle is within this many metres of where it was saved.
EqDressageTests.NEAR = 1.5
-- ... and whose length and width are within this many metres of the saved arena's.
EqDressageTests.SIZE_NEAR = 1
-- Seeds for the steps (what is left to chance inside a figure) are rolled from 1 to this.
EqDressageTests.SEED_MAX = 1000000

EqDressageTests.list = {}


function EqDressageTests.reset()
    EqDressageTests.list = {}
end


--- @param frame table EqDressagePath.frameFor
--- @return number|nil index, table|nil entry { x, z, length, width, plan } the arena's saved test
function EqDressageTests.find(frame)
    for i, entry in ipairs(EqDressageTests.list) do
        local d = math.sqrt((entry.x - frame.cx) ^ 2 + (entry.z - frame.cz) ^ 2)
        if d <= EqDressageTests.NEAR and math.abs(entry.length - frame.halfL * 2) <= EqDressageTests.SIZE_NEAR
            and math.abs(entry.width - frame.halfW * 2) <= EqDressageTests.SIZE_NEAR then
            return i, entry
        end
    end
    return nil, nil
end


--- @param frame table|nil
--- @return table|nil plan the arena's saved test
function EqDressageTests.planFor(frame)
    if frame == nil then return nil end
    local _, entry = EqDressageTests.find(frame)
    return entry ~= nil and entry.plan or nil
end


--- Keep a test for an arena, or delete the arena's test (plan nil).
--- @param frame table
--- @param plan table|nil
function EqDressageTests.set(frame, plan)
    local index = EqDressageTests.find(frame)
    if index ~= nil then table.remove(EqDressageTests.list, index) end
    if plan ~= nil then
        table.insert(EqDressageTests.list, { x = frame.cx, z = frame.cz, length = frame.halfL * 2, width = frame.halfW * 2, plan = plan })
    end
end


-- SAVING -------------------------------------------------------------------------------------

--- A plan as one line: "1 seed;f id seed;s style letter seed".
--- @param plan table
--- @return string
function EqDressageTests.encode(plan)
    local parts = { string.format("%d %d", plan.turn or 1, plan.seed or 1) }
    for _, step in ipairs(plan.steps) do
        if step.kind == "spot" then
            table.insert(parts, string.format("s %s %s %d", step.style, step.letter, step.seed or 1))
        else
            table.insert(parts, string.format("f %s %d", step.id, step.seed or 1))
        end
    end
    return table.concat(parts, ";")
end


--- @param text string|nil from encode
--- @return table|nil plan
function EqDressageTests.decode(text)
    if text == nil or text == "" then return nil end
    local plan = { steps = {} }
    for part in string.gmatch(text, "[^;]+") do
        local words = {}
        for word in string.gmatch(part, "%S+") do table.insert(words, word) end
        if plan.turn == nil then
            plan.turn = tonumber(words[1]) == -1 and -1 or 1
            plan.seed = tonumber(words[2]) or 1
        elseif words[1] == "s" and #words >= 4 then
            table.insert(plan.steps, { kind = "spot", style = words[2], letter = words[3], seed = tonumber(words[4]) or 1 })
        elseif words[1] == "f" and #words >= 3 then
            table.insert(plan.steps, { kind = "figure", id = words[2], seed = tonumber(words[3]) or 1 })
        end
    end
    if plan.turn == nil or #plan.steps == 0 then return nil end
    return plan
end


--- @param xmlFile table
--- @param key string
function EqDressageTests.saveToXMLFile(xmlFile, key)
    for i, entry in ipairs(EqDressageTests.list) do
        local testKey = string.format("%s.test(%d)", key, i - 1)
        xmlFile:setFloat(testKey .. "#x", entry.x)
        xmlFile:setFloat(testKey .. "#z", entry.z)
        xmlFile:setFloat(testKey .. "#length", entry.length)
        xmlFile:setFloat(testKey .. "#width", entry.width)
        xmlFile:setString(testKey .. "#plan", EqDressageTests.encode(entry.plan))
    end
end


--- @param xmlFile table|nil nil for a new game
--- @param key string
function EqDressageTests.loadFromXMLFile(xmlFile, key)
    EqDressageTests.reset()
    if xmlFile == nil then return end
    local i = 0
    while true do
        local testKey = string.format("%s.test(%d)", key, i)
        if not xmlFile:hasProperty(testKey) then break end
        local plan = EqDressageTests.decode(xmlFile:getString(testKey .. "#plan"))
        if plan ~= nil then
            table.insert(EqDressageTests.list, { x = xmlFile:getFloat(testKey .. "#x", 0), z = xmlFile:getFloat(testKey .. "#z", 0),
                length = xmlFile:getFloat(testKey .. "#length", 0), width = xmlFile:getFloat(testKey .. "#width", 0), plan = plan })
        end
        i = i + 1
    end
end


-- THE EDITOR ---------------------------------------------------------------------------------

local function copyPlan(plan)
    local steps = {}
    for i, step in ipairs(plan ~= nil and plan.steps or {}) do
        local copy = {}
        for k, v in pairs(step) do copy[k] = v end
        steps[i] = copy
    end
    return { turn = plan ~= nil and plan.turn or nil, seed = plan ~= nil and plan.seed or nil, steps = steps }
end


--- Start editing an arena's test: a new one, or the saved one carried on from its last step.
--- @param frame table
--- @param plan table|nil the saved test
--- @param rng function (n) -> 1..n
--- @return table editor
function EqDressageTests.newEditor(frame, plan, rng)
    local ed = { frame = frame, plan = copyPlan(plan), rng = rng, mode = "figure", index = 1, saved = plan ~= nil }
    ed.plan.seed = ed.plan.seed or rng(EqDressageTests.SEED_MAX)
    ed.seed = rng(EqDressageTests.SEED_MAX)
    EqDressageTests.refresh(ed)
    return ed
end


--- Work out the options for the next step from the plan so far. A test with no steps yet may
--- still track left or right at C: both ways' options are offered, each with its turn.
--- @param ed table
function EqDressageTests.refresh(ed)
    local plan = ed.plan
    local turns = (#plan.steps == 0) and { 1, -1 } or { plan.turn }
    local options = { figure = {}, spot = {} }
    for _, turn in ipairs(turns) do
        local test = EqDressagePath.build(ed.frame, nil, nil, { turn = turn, seed = plan.seed, steps = plan.steps }, true)
        if test.broken ~= nil then
            -- A saved step that no longer fits this arena: drop it and the ones after.
            for k = #plan.steps, test.broken, -1 do table.remove(plan.steps, k) end
            return EqDressageTests.refresh(ed)
        end
        for _, mode in ipairs({ "figure", "spot" }) do
            for _, option in ipairs(test.options[mode]) do
                option.turn = turn
                table.insert(options[mode], option)
            end
        end
        if turn == turns[1] then ed.base = test end
    end
    ed.options = options
    if #options[ed.mode] == 0 then ed.mode = ed.mode == "figure" and "spot" or "figure" end
    ed.index = math.max(1, math.min(ed.index, #options[ed.mode]))
    ed.preview = nil
end


--- @param ed table
--- @return table|nil option the one showing, number index, number count
function EqDressageTests.current(ed)
    local list = ed.options[ed.mode]
    return list[ed.index], ed.index, #list
end


--- Step through the options (N back, M on), round at the ends.
--- @param ed table
--- @param delta number
function EqDressageTests.cycle(ed, delta)
    local n = #ed.options[ed.mode]
    if n == 0 then return end
    ed.index = (ed.index - 1 + delta) % n + 1
    ed.preview = nil
end


--- A random option, weighted like a random test's figures, and a new roll for what is left to
--- chance inside it.
--- @param ed table
function EqDressageTests.random(ed)
    local list = ed.options[ed.mode]
    if #list == 0 then return end
    local total = 0
    for _, option in ipairs(list) do total = total + (option.weight or 1) end
    local roll = (ed.rng(1000) - 0.5) / 1000 * total
    local pick = #list
    for i, option in ipairs(list) do
        roll = roll - (option.weight or 1)
        if roll <= 0 then
            pick = i
            break
        end
    end
    -- Not the one already showing, when there is a choice.
    if pick == ed.index and #list > 1 then pick = pick % #list + 1 end
    ed.index = pick
    ed.seed = ed.rng(EqDressageTests.SEED_MAX)
    ed.preview = nil
end


--- Swap between figures and movements on the spot.
--- @param ed table
function EqDressageTests.toggle(ed)
    local other = ed.mode == "figure" and "spot" or "figure"
    if #ed.options[other] == 0 then return false end
    ed.mode, ed.index, ed.preview = other, 1, nil
    return true
end


--- @param option table
--- @param seed number
--- @return table step
local function stepOf(option, seed)
    if option.kind == "spot" then return { kind = "spot", style = option.style, letter = option.letter, seed = seed } end
    return { kind = "figure", id = option.id, seed = seed }
end


--- The test with the option showing as its next step, for drawing. preview.fromS is where the
--- option starts (the end of the last step kept).
--- @param ed table
--- @return table|nil test
function EqDressageTests.preview(ed)
    if ed.preview ~= nil then return ed.preview end
    local option = EqDressageTests.current(ed)
    if option == nil then return nil end
    local steps = {}
    for i, step in ipairs(ed.plan.steps) do steps[i] = step end
    table.insert(steps, stepOf(option, ed.seed))
    local test = EqDressagePath.build(ed.frame, nil, nil, { turn = option.turn, seed = ed.plan.seed, steps = steps }, true)
    test.fromS = test.moves[#test.moves].s0
    ed.preview = test
    return test
end


--- Keep the option showing and move on to the options from its end.
--- @param ed table
--- @return table|nil step the step kept
function EqDressageTests.accept(ed)
    local option = EqDressageTests.current(ed)
    if option == nil then return nil end
    local step = stepOf(option, ed.seed)
    ed.plan.turn = option.turn
    table.insert(ed.plan.steps, step)
    ed.seed = ed.rng(EqDressageTests.SEED_MAX)
    ed.mode, ed.index = "figure", 1
    EqDressageTests.refresh(ed)
    return step
end


--- Take the last step kept back off; it shows again as the option.
--- @param ed table
--- @return boolean false when there was nothing to undo
function EqDressageTests.undo(ed)
    local step = table.remove(ed.plan.steps)
    if step == nil then return false end
    ed.seed = step.seed
    ed.mode = step.kind == "spot" and "spot" or "figure"
    ed.index = 1
    EqDressageTests.refresh(ed)
    for i, option in ipairs(ed.options[ed.mode]) do
        if (option.kind == "figure" and option.id == step.id) or (option.kind == "spot" and option.style == step.style and option.letter == step.letter) then
            if #ed.plan.steps > 0 or option.turn == ed.plan.turn then
                ed.index = i
                break
            end
        end
    end
    if #ed.plan.steps == 0 then ed.plan.turn = nil end
    return true
end


--- @param ed table
--- @return table|nil plan the test to save (nil when it has no steps: delete the arena's test),
--- table|nil test the whole test built from it, with the final centre line
function EqDressageTests.finished(ed)
    if #ed.plan.steps == 0 then return nil, nil end
    local plan = copyPlan(ed.plan)
    return plan, EqDressagePath.build(ed.frame, nil, nil, plan)
end

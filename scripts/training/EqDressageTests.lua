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


EqDressageTests.GAITS = { "walk", "trot", "canter" }


--- Start editing an arena's test: a new one, or the saved one carried on from its last step.
--- @param frame table
--- @param plan table|nil the saved test
--- @param rng function (n) -> 1..n
--- @return table editor
function EqDressageTests.newEditor(frame, plan, rng)
    local ed = { frame = frame, plan = copyPlan(plan), rng = rng, mode = "figure", index = 1, group = 1, saved = plan ~= nil }
    ed.plan.seed = ed.plan.seed or rng(EqDressageTests.SEED_MAX)
    ed.seed = rng(EqDressageTests.SEED_MAX)
    EqDressageTests.refresh(ed)
    return ed
end


--- The gait the figures on show are ridden at: the one the player picked (G), else the gait the
--- test has got to.
--- @param ed table
--- @return string gait
function EqDressageTests.gaitOf(ed)
    return ed.gait or (ed.base ~= nil and ed.base.gait) or "trot"
end


--- The options on show now. Figures: those at the gait on show. On the spot: the movements at
--- one letter (ed.group), so N and M step through the movements and Shift+N/M through the letters.
--- @param ed table
--- @return table list, table groups { key } for the spot mode's letters
function EqDressageTests.view(ed)
    local list, groups = {}, {}
    if ed.mode == "figure" then
        local gait = EqDressageTests.gaitOf(ed)
        for _, option in ipairs(ed.options.figure) do
            if option.figure.gait == gait then table.insert(list, option) end
        end
        return list, groups
    end
    local seen = {}
    for _, option in ipairs(ed.options.spot) do
        local key = string.format("%d %s %.1f", option.turn or 0, option.letter, option.d or 0)
        if not seen[key] then
            seen[key] = true
            table.insert(groups, key)
        end
        option.group = #groups
    end
    local group = math.max(1, math.min(ed.group or 1, #groups))
    for _, option in ipairs(ed.options.spot) do
        if option.group == group then table.insert(list, option) end
    end
    return list, groups
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
    local list, groups = EqDressageTests.view(ed)
    ed.group = math.max(1, math.min(ed.group or 1, math.max(1, #groups)))
    list = EqDressageTests.view(ed)
    ed.index = math.max(1, math.min(ed.index, #list))
    ed.preview = nil
end


--- @param ed table
--- @return table|nil option the one showing, number index, number count
function EqDressageTests.current(ed)
    local list = EqDressageTests.view(ed)
    return list[ed.index], ed.index, #list
end


--- Step through the options on show (N back, M on), round at the ends.
--- @param ed table
--- @param delta number
function EqDressageTests.cycle(ed, delta)
    local n = #EqDressageTests.view(ed)
    if n == 0 then return end
    ed.index = (ed.index - 1 + delta) % n + 1
    ed.preview = nil
end


--- On the spot: the same movement at the letter before or after (Shift+N, Shift+M).
--- @param ed table
--- @param delta number
function EqDressageTests.cycleLetter(ed, delta)
    if ed.mode ~= "spot" then return end
    local option = EqDressageTests.current(ed)
    local _, groups = EqDressageTests.view(ed)
    if #groups == 0 then return end
    ed.group = (ed.group - 1 + delta) % #groups + 1
    ed.index = 1
    for i, other in ipairs((EqDressageTests.view(ed))) do
        if option ~= nil and other.style == option.style then ed.index = i end
    end
    ed.preview = nil
end


--- The gait the figures are shown at, round walk, trot, canter (G).
--- @param ed table
function EqDressageTests.cycleGait(ed)
    local gait = EqDressageTests.gaitOf(ed)
    for i, g in ipairs(EqDressageTests.GAITS) do
        if g == gait then
            ed.gait = EqDressageTests.GAITS[i % #EqDressageTests.GAITS + 1]
            break
        end
    end
    ed.mode, ed.index, ed.preview = "figure", 1, nil
end


--- A random option, weighted like a random test's figures, and a new roll for what is left to
--- chance inside it. Figures at the gait on show; on the spot, any movement at any letter.
--- @param ed table
function EqDressageTests.random(ed)
    local list = ed.mode == "figure" and EqDressageTests.view(ed) or ed.options.spot
    if #list == 0 then return end
    local showing = EqDressageTests.current(ed)
    local total = 0
    for _, option in ipairs(list) do total = total + (option.weight or 1) end
    local roll = (ed.rng(1000) - 0.5) / 1000 * total
    local pick = list[#list]
    for _, option in ipairs(list) do
        roll = roll - (option.weight or 1)
        if roll <= 0 then
            pick = option
            break
        end
    end
    -- Not the one already showing, when there is a choice.
    if pick == showing and #list > 1 then
        for i, option in ipairs(list) do
            if option == pick then
                pick = list[i % #list + 1]
                break
            end
        end
    end
    if ed.mode == "spot" then ed.group = pick.group or 1 end
    for i, option in ipairs((EqDressageTests.view(ed))) do
        if option == pick then ed.index = i end
    end
    ed.seed = ed.rng(EqDressageTests.SEED_MAX)
    ed.preview = nil
end


--- Swap between figures and movements on the spot.
--- @param ed table
function EqDressageTests.toggle(ed)
    local other = ed.mode == "figure" and "spot" or "figure"
    if #ed.options[other] == 0 then return false end
    ed.mode, ed.index, ed.group, ed.preview = other, 1, 1, nil
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
--- option starts (the end of the last step kept), preview.lastS where that last step started.
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
    -- The step before: the last one kept, or the opening (both its movements) on the first.
    local before = #ed.plan.steps > 0 and test.moves[#test.moves - 1] or test.moves[1]
    test.lastS = before ~= nil and before.s0 or 0
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
    -- The figures go on at the gait the test is now in, unless the player picks another.
    ed.mode, ed.index, ed.group, ed.gait = "figure", 1, 1, nil
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
    ed.mode, ed.index, ed.group, ed.gait = step.kind == "spot" and "spot" or "figure", 1, 1, nil
    EqDressageTests.refresh(ed)
    local function matches(option)
        if #ed.plan.steps == 0 and option.turn ~= ed.plan.turn then return false end
        if option.kind == "figure" then return option.id == step.id end
        return option.style == step.style and option.letter == step.letter
    end
    if ed.mode == "figure" then
        for _, option in ipairs(ed.options.figure) do
            if matches(option) then ed.gait = option.figure.gait end
        end
    else
        for _, option in ipairs(ed.options.spot) do
            if matches(option) then ed.group = option.group or 1 end
        end
    end
    for i, option in ipairs((EqDressageTests.view(ed))) do
        if matches(option) then ed.index = i end
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

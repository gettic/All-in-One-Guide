-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Step-type registry. Each type: the bus events that can complete it (only the visible steps listen),
-- its done test, its default text key and the route-test driver name. All state comes from the shared
-- game-state reader and the geo service, never from the game directly.
--   ns.StepTypes.Get(type) -> def;  def.Done(step, guide) -> true / false
local _, ns = ...
local ST = { types = {} }
ns.StepTypes = ST

local GS, Geo = ns.GameState, ns.Geo

function ST.Register(name, def)
    assert(not ST.types[name], "step type registered twice: " .. name)
    def.name = name
    ST.types[name] = def
end

function ST.Get(name) return ST.types[name] or ST.types.manual end

-- Objective step: the listed objectives (or all), "any N", or an item count.
local function ObjectivesDone(step)
    if step.item then return GS.ItemCount(step.item) >= (step.count or 1) end
    local q = step.quest
    if not q then return false end
    if GS.IsDone(q) then return true end
    local qs = GS.Quest(q)
    if not qs then return false end
    if qs.complete then return true end
    local list = step.obj
    local done, total = 0, 0
    if ns.Packs.Len(list) > 0 then
        for _, i in ns.Packs.Each(list) do   -- step lists are frozen proxies (no # / ipairs)
            total = total + 1
            local need = qs.need[i]
            if need and qs.have[i] >= need then done = done + 1 end
        end
    else
        for i, need in ipairs(qs.need) do
            total = total + 1
            if qs.have[i] >= need then done = done + 1 end
        end
    end
    if step.any then return done >= step.any end
    return total > 0 and done == total
end
ST.ObjectivesDone = ObjectivesDone

ST.Register("accept", {
    events = { "QuestsChanged", "QuestTurnedIn" }, text = "STEP_ACCEPT", driver = "accept", needsQuest = true,
    Done = function(step) return GS.InLog(step.quest) or GS.IsDone(step.quest) end,
})
ST.Register("turnin", {
    events = { "QuestsChanged", "QuestTurnedIn" }, text = "STEP_TURNIN", driver = "turnin", needsQuest = true,
    Done = function(step) return GS.IsDone(step.quest) end,
})
ST.Register("objective", {
    events = { "QuestsChanged", "QuestTurnedIn", "ItemsChanged" }, text = "STEP_OBJECTIVE", driver = "objective",
    needsQuest = true,
    Done = function(step) return ObjectivesDone(step) end,
})
ST.Register("goto", {
    events = { "Position", "ZoneChanged" }, text = "STEP_GOTO", driver = "goto", travel = true, position = true,
    Done = function(step, guide)
        if guide and guide.reached[step.id] then return true end
        local r = step.r or ns.Format.DEFAULT_RADIUS
        -- no spot (or r = 0): the player moves past it by hand
        if r <= 0 or not step.map or not step.x or not step.y then return false end
        local d = Geo.PlayerDistance(step.map, step.x, step.y)
        if not d then return false end
        local ok
        if step.flags.leaveArea then ok = d > r else ok = d <= r end
        if ok and guide then guide.reached[step.id] = true end
        return ok
    end,
})
ST.Register("level", {
    events = { "LevelChanged" }, text = "STEP_LEVEL", driver = "level",
    Done = function(step)
        local lv = GS.level or ns.Compat.Player().level or 0
        return lv >= (step.level or 0)
    end,
})
-- Unknown types from newer packs: shown as a plain step the player moves past by hand.
ST.Register("manual", {
    events = {}, text = "STEP_MANUAL", driver = "manual",
    Done = function() return false end,
})

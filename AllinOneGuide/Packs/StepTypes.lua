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
-- Travel arrival: within r yards of the spot (or outside it with leaveArea); latched once reached.
-- While dead / a ghost nothing arrives (v0.2: running back as a ghost doesn't tick goto steps).
local function Arrived(step, guide, defaultR)
    if guide and guide.reached[step.id] then return true end
    local r = step.r or defaultR or ns.Format.DEFAULT_RADIUS
    -- no spot (or r = 0): the player moves past it by hand
    if r <= 0 or not step.map or not step.x or not step.y then return false end
    if GS.dead then return false end
    local d = Geo.PlayerDistance(step.map, step.x, step.y)
    if not d then return false end
    local ok
    if step.flags.leaveArea then ok = d > r else ok = d <= r end
    if ok and guide then guide.reached[step.id] = true end
    return ok
end
ST.Arrived = Arrived

-- Ticked by the player (the window's "next" on these types marks them done, not skipped).
local function ByHand(step, guide)
    return guide ~= nil and type(guide.save.done) == "table" and guide.save.done[step.id] == true
end
ST.ByHand = ByHand

ST.Register("goto", {
    events = { "Position", "ZoneChanged", "DeadChanged" }, text = "STEP_GOTO", driver = "goto", travel = true,
    position = true,
    Done = function(step, guide) return Arrived(step, guide) end,
})
ST.Register("level", {
    events = { "LevelChanged" }, text = "STEP_LEVEL", driver = "level",
    Done = function(step)
        local lv = GS.level or ns.Compat.Player().level or 0
        return lv >= (step.level or 0)
    end,
})
-- ------------------------------------------------------------------ format 2 (v0.2)
-- Steps the game can't confirm: the player ticks them ("Done").
ST.Register("learn", { events = {}, text = "STEP_LEARN", driver = "byhand", manualDone = true, Done = ByHand })
ST.Register("train", { events = {}, text = "STEP_TRAIN", driver = "byhand", manualDone = true, Done = ByHand })
ST.Register("note", { events = {}, text = "STEP_NOTE", driver = "byhand", manualDone = true, Done = ByHand })
-- Use a quest item: done by its quest objective when it has one, else by the player.
ST.Register("useitem", {
    events = { "QuestsChanged", "QuestTurnedIn", "ItemsChanged" }, text = "STEP_USEITEM", driver = "useitem",
    manualDone = true,
    Done = function(step, guide)
        if step.quest and ObjectivesDone(step) then return true end
        return ByHand(step, guide)
    end,
})
-- A grind step (last resort, needs a why): a level, shown with a live XP bar.
ST.Register("grind", {
    events = { "LevelChanged", "XPChanged" }, text = "STEP_GRIND", driver = "grind",
    Done = function(step)
        local lv = GS.level or ns.Compat.Player().level or 0
        return lv >= (step.level or 0)
    end,
})
-- Flights and the hearthstone: arrival at the spot (bigger default radius), never while on the taxi.
ST.Register("fly", {
    events = { "Position", "ZoneChanged", "PauseChanged", "DeadChanged" }, text = "STEP_FLY", driver = "fly",
    travel = true, position = true, manualDone = true,
    Done = function(step, guide)
        if ByHand(step, guide) then return true end
        if GS.taxi then return false end
        return Arrived(step, guide, 80)
    end,
})
ST.Register("hearth", {
    events = { "Position", "ZoneChanged", "PauseChanged", "DeadChanged" }, text = "STEP_HEARTH", driver = "hearth",
    travel = true, position = true, manualDone = true,
    Done = function(step, guide) return ByHand(step, guide) or Arrived(step, guide, 100) end,
})
-- Learn a flight path: known from the taxi reader (v0.2 M2), else by the player.
ST.Register("getfp", {
    events = { "TaxiChanged" }, text = "STEP_GETFP", driver = "getfp", manualDone = true,
    Done = function(step, guide)
        if ByHand(step, guide) then return true end
        local T = ns.Taxi
        return T ~= nil and step.node ~= nil and T.Known(step.node) == true
    end,
})
-- Set the hearthstone: the bind location is the route's inn, or it changed while this step was up
-- (names come in the client's language, so the change counts too); else by the player.
ST.Register("sethearth", {
    events = { "BindChanged" }, text = "STEP_SETHEARTH", driver = "sethearth", manualDone = true,
    Done = function(step, guide)
        if ByHand(step, guide) then return true end
        local bind = GS.bind
        if step.inn and bind == step.inn then return true end
        if not guide then return false end
        guide.marks = guide.marks or {}
        local seen = guide.marks[step.id]
        if seen == nil then
            guide.marks[step.id] = bind or false
            return false
        end
        return bind ~= nil and bind ~= seen
    end,
})

-- Unknown types from newer packs: shown as a plain step the player moves past by hand.
ST.Register("manual", {
    events = {}, text = "STEP_MANUAL", driver = "manual",
    Done = function() return false end,
})

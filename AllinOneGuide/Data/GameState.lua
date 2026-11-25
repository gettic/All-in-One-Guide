-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The one shared game-state reader. It alone listens to the quest log and bag events, reads the
-- state once per debounced burst and tells the rest "these quest ids / item ids changed" on the bus.
-- No other module registers QUEST_LOG_UPDATE or BAG_UPDATE itself.
-- Readiness gate: nothing may tick (complete, auto-skip, "abandoned") before the first full snapshot
-- after login; ticking also pauses during loading screens and taxi flights.
--   bus: Ready, QuestsChanged(changed), QuestTurnedIn(id), ItemsChanged(changed), LevelChanged(level),
--        ZoneChanged, CombatStarted, CombatEnded, PauseChanged(paused)
local _, ns = ...
local Co = ns.Compat
local GS = { quests = {}, count = 0, ready = false, loading = false, taxi = false, items = {}, watched = {},
    turnedIn = {}, snapshots = 0, level = nil }
ns.GameState = GS

local QUEST_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED" }
local DEBOUNCE = 0.1

-- ------------------------------------------------------------------ quests
local function ReadQuest(id, old)
    local q = { complete = Co.QuestComplete(id), failed = Co.QuestFailed(id), have = {}, need = {}, text = {} }
    local objs = Co.Objectives(id)
    local changed = old == nil or old.complete ~= q.complete or old.failed ~= q.failed
    if objs then
        for i, o in ipairs(objs) do
            local have, need = tonumber(o.numFulfilled) or 0, tonumber(o.numRequired) or 0
            if o.finished and have < need then have = need end
            q.have[i], q.need[i] = have, need
            -- the game's objective text without its "3/8" count (the window shows its own count)
            local t = type(o.text) == "string" and o.text or ""
            q.text[i] = t:gsub("[:%s]*%d+%s*/%s*%d+%s*$", "")
            if old and (old.have[i] ~= have or old.need[i] ~= need) then changed = true end
        end
    end
    if old and #old.have ~= #q.have then changed = true end
    return q, changed
end

function GS.Snapshot()
    if not ns.Feature.IsOn("questlog") then
        GS.MarkReady()
        return
    end
    local new, changed, count = {}, {}, 0
    local entries = Co.NumQuestEntries()
    for i = 1, entries do
        local id, isHeader = Co.QuestAt(i)
        if id and id > 0 and not isHeader then
            local q, diff = ReadQuest(id, GS.quests[id])
            new[id] = q
            count = count + 1
            if diff then changed[id] = true end
        end
    end
    for id in pairs(GS.quests) do
        if not new[id] then changed[id] = true end
    end
    GS.quests, GS.count = new, count
    GS.snapshots = GS.snapshots + 1
    GS.MarkReady()
    if next(changed) then ns.Bus.Fire("QuestsChanged", changed) end
end

local function QueueSnapshot() ns.Events.Debounce("quests", DEBOUNCE, GS.Snapshot, "gamestate") end

-- Reads for other modules (from the snapshot; never from the game directly)
function GS.InLog(id) return GS.quests[id] ~= nil end
function GS.Quest(id) return GS.quests[id] end
function GS.IsDone(id) return GS.turnedIn[id] == true or Co.QuestFlagged(id) end
function GS.LogCount() return GS.count end
function GS.LogMax() return Co.QuestMax() end

-- ------------------------------------------------------------------ items (only ids someone watches)
function GS.WatchItem(id) GS.watched[id] = (GS.watched[id] or 0) + 1 GS.items[id] = Co.ItemCount(id) end
function GS.UnwatchItem(id)
    local n = (GS.watched[id] or 0) - 1
    if n <= 0 then GS.watched[id], GS.items[id] = nil, nil else GS.watched[id] = n end
end
function GS.ItemCount(id) return GS.items[id] or 0 end

local function ReadItems()
    local changed
    for id in pairs(GS.watched) do
        local n = Co.ItemCount(id)
        if n ~= GS.items[id] then
            GS.items[id] = n
            changed = changed or {}
            changed[id] = true
        end
    end
    if changed then ns.Bus.Fire("ItemsChanged", changed) end
end

-- ------------------------------------------------------------------ readiness and pauses
function GS.MarkReady()
    if GS.ready then return end
    GS.ready = true
    ns.Bus.Fire("Ready")
end

function GS.Paused() return GS.loading or GS.taxi end
function GS.CanTick() return GS.ready and not GS.loading and not GS.taxi end

local function SetPause(loading, taxi)
    local was = GS.Paused()
    GS.loading, GS.taxi = loading, taxi
    if was ~= GS.Paused() then ns.Bus.Fire("PauseChanged", GS.Paused()) end
end

-- ------------------------------------------------------------------ start (PLAYER_LOGIN)
function GS.Start()
    local E = ns.Events
    for _, ev in ipairs(QUEST_EVENTS) do
        E.On(ev, GS, function(event, unit)
            if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
            QueueSnapshot()
        end, "questlog")
    end
    E.On("QUEST_TURNED_IN", GS, function(_, id)
        if type(id) == "number" then
            GS.turnedIn[id] = true
            ns.Bus.Fire("QuestTurnedIn", id)
        end
        QueueSnapshot()
    end, "questlog")
    E.On("BAG_UPDATE_DELAYED", GS, function() E.Debounce("items", DEBOUNCE, ReadItems, "bags") end, "bags")
    E.On("PLAYER_LEVEL_UP", GS, function(_, level)
        GS.level = tonumber(level) or GS.level
        ns.Bus.Fire("LevelChanged", GS.level)
    end, "player")
    E.On("LOADING_SCREEN_ENABLED", GS, function() SetPause(true, GS.taxi) end, "core")
    E.On("LOADING_SCREEN_DISABLED", GS, function()
        SetPause(false, Co.OnTaxi())
        QueueSnapshot()
    end, "core")
    E.On("PLAYER_CONTROL_LOST", GS, function() SetPause(GS.loading, Co.OnTaxi()) end, "core")
    E.On("PLAYER_CONTROL_GAINED", GS, function() SetPause(GS.loading, Co.OnTaxi()) end, "core")
    E.On("ZONE_CHANGED_NEW_AREA", GS, function() ns.Bus.Fire("ZoneChanged") end, "core")
    E.On("PLAYER_REGEN_DISABLED", GS, function() ns.Bus.Fire("CombatStarted") end, "core")
    E.On("PLAYER_REGEN_ENABLED", GS, function() ns.Bus.Fire("CombatEnded") end, "core")
    GS.level = Co.Player().level
    GS.taxi = Co.OnTaxi()
    -- the client sends QUEST_LOG_UPDATE after login; if it doesn't come, read once anyway
    Co.After(3, function() if not GS.ready then ns.Errors.Call("gamestate", GS.Snapshot) end end)
end

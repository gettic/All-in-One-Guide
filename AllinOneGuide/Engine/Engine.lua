-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The engine: opens guides, keeps the condition context, and re-evaluates on the bus events that the
-- visible steps (current + background goals) need. Only those events are listened to; the position is
-- polled every 0.25 s only while a visible step needs it. Nothing ticks before the game-state reader is
-- ready, or during loading screens and taxi flights.
--   ns.Engine.Open(packId, routeId) -> guide;  Focused();  Current();  Skip(), SetCurrent(id), Back(), Next()
--   bus: StepChanged(guide)
local _, ns = ...
local P, ST, GS, Co = ns.Packs, ns.StepTypes, ns.GameState, ns.Compat
local E = { guides = {}, focus = nil, listening = {}, ticker = nil, detourSources = {}, refreshes = 0, items = {},
    restored = false }
ns.Engine = E

local ALWAYS = { Ready = true, PauseChanged = true, LevelChanged = true, Login = true }

-- The condition context (one table, refreshed before each evaluation round).
local ctx = { flags = {} }
E.ctx = ctx
ctx.done = function(q) return GS.IsDone(q) end
ctx.inlog = function(q) return GS.InLog(q) end
ctx.ready = function(q) local s = GS.Quest(q) return s ~= nil and s.complete end
ctx.itemCount = function(id)
    if GS.watched[id] then return GS.ItemCount(id) end
    return Co.ItemCount(id) or 0
end

function E.UpdateCtx()
    local p = Co.Player()
    ctx.level = GS.level or p.level
    ctx.class, ctx.race, ctx.faction, ctx.sex = p.class, p.race, p.faction, p.sex
end

function E.Key(packId, routeId) return packId .. "/" .. routeId end

-- Opens (or returns) a guide and focuses it. Returns guide or nil, reason.
function E.Open(packId, routeId)
    local route, err = P.Open(packId, routeId)
    if not route then return nil, err end
    local key = E.Key(packId, route.id)
    local g = E.guides[key]
    if not g then
        g = ns.Guide.New(key, route, ns.DB.Guide(key))
        E.guides[key] = g
        E.RestoreDetours(g)
    end
    E.focus = key
    E.SaveActive()
    E.RefreshAll()
    return g
end

-- Detours saved on a guide's stack come back (nested ones too) if their kind is known; unknown kinds
-- stay saved, parked, and the ones after them wait too (a detour always sits on the one before it).
function E.RestoreDetours(g)
    for _, entry in ipairs(g.save.stack) do
        local src = type(entry) == "table" and type(entry.kind) == "string" and E.detourSources[entry.kind]
        local steps = src and src(entry.id)
        if not steps then return end
        E.RestoreDetours(g:PushDetour(entry.kind, entry.id, steps, entry))
    end
end

-- The active list keeps guides whose pack is not installed right now (never dropped from the save).
function E.SaveActive()
    local list, seen = {}, {}
    for _, k in ipairs(ns.DB.char.active or {}) do
        if type(k) == "string" and not seen[k] and (E.guides[k] or not P.packs[k:match("^([^/]+)")]) then
            list[#list + 1], seen[k] = k, true
        end
    end
    local open = {}
    for k in pairs(E.guides) do if not seen[k] then open[#open + 1] = k end end
    table.sort(open)
    for _, k in ipairs(open) do list[#list + 1] = k end
    ns.DB.SetActive(list, E.focus)
end

-- After the first full game-state snapshot: reopen the saved active guides (the focused one last).
function E.Restore()
    E.restored = true
    local focus = ns.DB.char.focus
    for _, k in ipairs(ns.DB.char.active or {}) do
        local packId, routeId = tostring(k):match("^([^/]+)/(.+)$")
        if packId and P.packs[packId] and k ~= focus then E.Open(packId, routeId) end
    end
    local fp, fr = tostring(focus or ""):match("^([^/]+)/(.+)$")
    if fp and P.packs[fp] then E.Open(fp, fr) end
    E.RefreshAll()
    if not ns.Test.quietFirstRun then ns.Errors.Call("engine", E.FirstPick) end
end

-- ------------------------------------------------------------------ picking a guide
-- The first route pack whose header conditions fit this character and whose level range isn't
-- behind it (pack order = id order, so the pick never depends on load order). nil when none fits.
function E.Suggest()
    E.UpdateCtx()
    local ids = {}
    for _, id in ipairs(P.List()) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local h = P.Header(id)
        local cond = h and h.conditions
        local fits = h and h.kind == "route"
        if fits and type(cond) == "string" and cond ~= "" then fits = ns.Conditions.Check(ns.Conditions.Get(cond), ctx) end
        local top = h and type(h.levels) == "table" and tonumber(h.levels[2])
        if fits and top and type(ctx.level) == "number" and ctx.level > top then fits = false end
        if fits then return id end
    end
    return nil
end

local function GuideTitle(packId)
    local h = P.Header(packId) or {}
    return (ns.Locale.code == "daDK" and h.da) or h.title or packId
end

-- The very first login of a character with no guide open: open the fitting guide (Alliance gets
-- Elwynn, Horde Durotar) and say so in one chat line; or say how to pick one. Only once per character.
function E.FirstPick()
    if ns.safeMode or E.Focused() then return end
    local flags = ns.DB.char.flags
    if type(flags) ~= "table" or flags.guidePicked then return end
    if not ns.DB.readOnly.char then flags.guidePicked = true end
    local id = E.Suggest()
    local g = id and E.Open(id)
    if g then
        ns.Bus.Fire("StepChanged", g)
        ns.Print(ns.U.Fill(ns.L.GUIDE_OPENED, { guide = GuideTitle(id) }))
    else
        ns.Print(ns.L.GUIDE_NONE)
    end
end

-- "/aog guide elwynn": a pack id, or the id without its "demo-" part.
function E.FindPack(word)
    word = tostring(word or ""):lower()
    if word == "" then return nil end
    for _, id in ipairs(P.List()) do
        local l = id:lower()
        if l == word or l == "demo-" .. word then return id end
    end
    return nil
end

ns.Slash.Add("guide", function(arg)
    arg = strtrim(tostring(arg or ""))
    if arg == "" then ns.Print(ns.L.GUIDE_USAGE) return end
    local id = E.FindPack(arg)
    if not id then ns.Print(ns.U.Fill(ns.L.GUIDE_UNKNOWN, { word = arg })) return end
    local g = E.Open(id)
    if not g then ns.Print(ns.U.Fill(ns.L.GUIDE_UNKNOWN, { word = arg })) return end
    ns.Bus.Fire("StepChanged", g)
    ns.Print(ns.U.Fill(ns.L.GUIDE_OPENED, { guide = GuideTitle(id) }))
    if ns.UI and not ns.UI.IsShown() then ns.UI.Show() end
end, "HELP_GUIDE", { main = true })

function E.Close(key)
    local g = E.guides[key]
    if not g then return end
    P.Close(g.route)
    E.guides[key] = nil
    if E.focus == key then E.focus = next(E.guides) end
    local list = {}
    for _, k in ipairs(ns.DB.char.active or {}) do if k ~= key then list[#list + 1] = k end end
    ns.DB.SetActive(list, E.focus)
    E.Rewire()
end

function E.Focused() return E.focus and E.guides[E.focus] or nil end

-- The step shown for the focused guide (its deepest detour first).
function E.Current()
    local g = E.Focused()
    if not g then return nil end
    local top = g:Top()
    return top:Current(), top
end

-- ------------------------------------------------------------------ evaluation
function E.RefreshAll()
    if not GS.CanTick() then return end
    E.refreshes = E.refreshes + 1
    E.UpdateCtx()
    for _, g in pairs(E.guides) do
        -- one broken guide (e.g. a corrupt row) is caught and reported; the others keep going
        local ok, changed = ns.Errors.Call("engine", g.RefreshTree, g)
        if ok and changed then ns.Bus.Fire("StepChanged", g) end
    end
    E.Rewire()
end

local function Visible(g)
    local top = g:Top()
    local list = top:Background()
    local cur = top:Current()
    if cur then list[#list + 1] = cur end
    return list
end

-- Travel steps can complete by themselves only when both the player's map position and world
-- positions (for yards) can be read; otherwise the player moves past them by hand.
function E.CanTrack() return ns.Feature.IsOn("position") and ns.Feature.IsOn("worldpos") end

-- Listens only to what the visible steps need; watches only their items.
function E.Rewire()
    local want, items = {}, {}
    for ev in pairs(ALWAYS) do want[ev] = true end
    for _, g in pairs(E.guides) do
        for _, s in ipairs(Visible(g)) do
            local def = ST.Get(s.type)
            for _, ev in ipairs(def.events) do want[ev] = true end
            -- a travel step auto-skips when its target gets done; an override goal reads quests and items
            if def.travel then want.QuestsChanged, want.QuestTurnedIn = true, true end
            if s.overrideAst then want.QuestsChanged, want.QuestTurnedIn, want.ItemsChanged = true, true, true end
            if s.item then items[s.item] = true end
        end
    end
    for id in pairs(E.items) do
        if not items[id] then
            GS.UnwatchItem(id)
            E.items[id] = nil
        end
    end
    -- an item that's newly watched and already in the bags may finish a step at once (e.g. after a
    -- /reload, or loot picked up before the step came up): evaluate again once it's read
    local again = false
    for id in pairs(items) do
        if not E.items[id] then
            GS.WatchItem(id)
            E.items[id] = true
            if GS.ItemCount(id) > 0 then again = true end
        end
    end
    for ev in pairs(E.listening) do
        if not want[ev] then
            if ev ~= "Position" then ns.Bus.Off(ev, E) end
            E.listening[ev] = nil
        end
    end
    for ev in pairs(want) do
        if not E.listening[ev] then
            if ev ~= "Position" then ns.Bus.On(ev, E, E.OnBus, "engine", 60) end
            E.listening[ev] = true
        end
    end
    local poll = want.Position and E.CanTrack()
    if poll and not E.ticker then
        E.ticker = Co.Ticker(0.25, function() ns.Errors.Call("engine", E.RefreshAll) end)
    elseif not poll and E.ticker then
        E.ticker:Cancel()
        E.ticker = nil
    end
    if again then E.RefreshAll() end   -- ends: the next round watches nothing new
end

function E.OnBus()
    if not E.restored and GS.ready then return E.Restore() end
    E.RefreshAll()
end
for ev in pairs(ALWAYS) do
    ns.Bus.On(ev, E, E.OnBus, "engine", 60)
    E.listening[ev] = true
end

-- ------------------------------------------------------------------ the player's actions (focused guide)
local function Act(method, ...)
    local g = E.Focused()
    if not g then return false end
    local top = g:Top()
    local ok = top[method](top, ...)
    if ok then
        E.RefreshAll()
        ns.Bus.Fire("StepChanged", g)
    end
    return ok
end
function E.Skip(id) return Act("Skip", id) end
function E.SetCurrent(id) return Act("SetCurrent", id) end
function E.Back() return Act("Back") end
function E.Next() return Act("Next") end

-- Detours: a module registers how to rebuild a kind's steps (so an active detour survives /reload).
function E.RegisterDetour(kind, fn) E.detourSources[kind] = fn end

function E.PushDetour(kind, id)
    local g = E.Focused()
    local src = E.detourSources[kind]
    local steps = g and src and src(id)
    if not steps then return false end
    g:Top():PushDetour(kind, id, steps)
    E.RefreshAll()
    ns.Bus.Fire("StepChanged", g)
    return true
end

-- Slash words for moving by hand (the window gets buttons in M3).
ns.Slash.Add("skip", function() E.Skip() end, "HELP_SKIP")
ns.Slash.Add("back", function() E.Back() end, "HELP_BACK")

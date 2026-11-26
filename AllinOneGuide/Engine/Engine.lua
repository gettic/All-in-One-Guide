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

local ALWAYS = { Ready = true, PauseChanged = true, LevelChanged = true, Login = true, QuestNotAvailable = true,
    SkillChanged = true }   -- v0.2: skill= conditions (rare: a skill point or a new rank)

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

-- v0.2: skill=<name>>=<n> reads the First Aid module's last (debounced) read; nil = unknown
ctx.skill = function(name)
    local r = ns.FirstAid and ns.FirstAid.Rank(name)
    return type(r) == "number" and r or nil
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
local function Reopen()
    local focus = ns.DB.char.focus
    for _, k in ipairs(ns.DB.char.active or {}) do
        local packId, routeId = tostring(k):match("^([^/]+)/(.+)$")
        if packId and P.packs[packId] and k ~= focus then E.Open(packId, routeId) end
    end
    local fp, fr = tostring(focus or ""):match("^([^/]+)/(.+)$")
    if fp and P.packs[fp] then E.Open(fp, fr) end
    E.RefreshAll()
    -- beta.4 tester: after a /reload with the window open nothing else said "the step is there", so the window,
    -- arrow, pins and path line waited for some later event. Once here, with the reopened guide.
    local g = E.Focused()
    if g then ns.Bus.Fire("StepChanged", g) end
end

function E.Restore()
    E.restored = true
    Reopen()
    if not ns.Test.quietFirstRun then
        -- a renamed character: ask "move data?" first; the first-login pick only runs when there is nothing to move
        local _, asked = ns.Errors.Call("engine", E.OfferMove)
        if not asked then
            ns.Errors.Call("engine", E.FixWrongStart)   -- a v0.1 pick for another start (bug-first-step cause 2)
            ns.Errors.Call("engine", E.FirstPick)
        end
        ns.Errors.Call("engine", E.OfferUpgrade)
    end
end

-- ------------------------------------------------------------------ "move data?" after a rename
-- DB.FindMoveCandidate (at login) found exactly one known character with the same class, race, faction and
-- level under another name, and this character's save is new. Ask once; yes copies its guide progress here
-- (the old entry is kept), no goes on with the normal first-login pick. Returns true when the dialog is queued.
function E.OfferMove()
    local cand = ns.DB.moveCandidate
    if type(cand) ~= "string" or ns.safeMode or ns.DB.readOnly.char or ns.DB.readOnly.account then return false end
    if E.Focused() then return false end
    local name = ns.DisplayName(cand:match("^([^%-]+)") or cand)
    return ns.Popups.Confirm({ kind = "move", text = ns.U.Fill(ns.L.DIALOG_MOVE, { name = name }),
        acceptText = ns.L.POPUP_MOVE, cancelText = ns.L.POPUP_FRESH,
        accept = function() E.MoveIn(cand) end,
        cancel = function()
            ns.DB.moveCandidate = nil
            E.FirstPick()
        end }) == true
end

function E.MoveIn(cand)
    local open = {}
    for k in pairs(E.guides) do open[#open + 1] = k end
    for _, k in ipairs(open) do E.Close(k) end
    if not ns.DB.MoveFrom(cand) then return false end
    local flags = ns.DB.char.flags
    if type(flags) == "table" then flags.guidePicked = true end
    Reopen()
    local g = E.Focused()
    if g then ns.Bus.Fire("StepChanged", g) end
    ns.Print(ns.L.MOVE_DONE)
    return true
end

-- ------------------------------------------------------------------ picking a guide
-- Does a route pack fit this character? Header conditions (faction ...) and a level range that isn't
-- behind it; with needEntry also the pack's `entry` (race / start area): a guide is only picked by
-- itself where the character really starts (beta.2 fix: a night elf no longer gets Elwynn).
-- An unknown race never matches an entry (then nothing is picked by itself).
function E.Fits(id, needEntry)
    local h = P.Header(id)
    if not (h and h.kind == "route") then return false end
    local cond = h.conditions
    if type(cond) == "string" and cond ~= "" and not ns.Conditions.Check(ns.Conditions.Get(cond), ctx) then return false end
    local top = type(h.levels) == "table" and tonumber(h.levels[2])
    if top and type(ctx.level) == "number" and ctx.level > top then return false end
    if needEntry then
        local entry = h.entry
        if type(entry) ~= "string" or entry == "" then return false end
        if ctx.race == nil then return false end
        if not ns.Conditions.Check(ns.Conditions.Get(entry), ctx) then return false end
    end
    return true
end

local function IsDemo(id) return id:match("^demo%-") ~= nil end
E.IsDemo = IsDemo

-- Fitting route packs, best first: real routes before demo packs, then by id (never load order).
function E.Fitting(needEntry)
    E.UpdateCtx()
    local ids = {}
    for _, id in ipairs(P.List()) do if E.Fits(id, needEntry) then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b)
        if IsDemo(a) ~= IsDemo(b) then return not IsDemo(a) end
        return a < b
    end)
    return ids
end

-- The guide to open by itself on a first login, or nil (then the "none" state and the guide list).
function E.Suggest() return E.Fitting(true)[1] end

-- The short name the player types: the pack id without "demo-".
function E.ShortName(id) return (id:gsub("^demo%-", "")) end

-- "elwynn, durotar": the guides for this character (faction / level fit), or every installed route pack.
function E.GuideList()
    local ids = E.Fitting(false)
    if #ids == 0 then
        for _, id in ipairs(P.List()) do
            local h = P.Header(id)
            if h and h.kind == "route" then ids[#ids + 1] = id end
        end
        table.sort(ids)
    end
    local names = {}
    for _, id in ipairs(ids) do names[#names + 1] = E.ShortName(id) end
    return table.concat(names, ", "), ids
end

local function GuideTitle(packId)
    local h = P.Header(packId) or {}
    return (ns.Locale.code == "daDK" and h.da) or h.title or packId
end

-- The very first login of a character with no guide open: open the fitting guide (Alliance gets
-- Elwynn, Horde Durotar) and say so in one chat line; or say how to pick one. Only once per character.
function E.FirstPick()
    if ns.safeMode or E.Focused() then return end
    if not ns.Settings.Get("useOnChar") then return end   -- v0.2 M4: "Use the guide on this character" off
    local flags = ns.DB.char.flags
    if type(flags) ~= "table" or flags.guidePicked then return end
    -- v0.2 picks by start (entry), so FixWrongStart has nothing to undo for this character
    if not ns.DB.readOnly.char then flags.guidePicked, flags.startChecked = true, true end
    local id = E.Suggest()
    local g = id and E.Open(id)
    if g then
        ns.Bus.Fire("StepChanged", g)
        ns.Print(ns.U.Fill(ns.L.GUIDE_OPENED, { guide = GuideTitle(id) }))
    else
        ns.Print(ns.U.Fill(ns.L.GUIDE_NONE, { list = (E.GuideList()) }))
    end
end

-- bug-first-step cause 2: v0.1 picked by faction only, so a v0.1 character may sit on a guide for another
-- start (a gnome on Elwynn) and keep it (flags.guidePicked). Once per character, at login: when the focused
-- guide's pack has an `entry` that doesn't fit this character's race, and the character is still on that
-- guide's first step with nothing skipped or done, close it, say so, and open the fitting guide (or print
-- the guide list). Never touches a guide the player has moved on in. Returns true when it closed one.
function E.FixWrongStart()
    if ns.safeMode or ns.DB.readOnly.char then return false end
    if not ns.Settings.Get("useOnChar") then return false end
    local flags = ns.DB.char.flags
    if type(flags) ~= "table" or flags.startChecked then return false end
    local g = E.Focused()
    if not g then return false end
    local packId = g.key:match("^([^/]+)/")
    local h = packId and P.Header(packId)
    if not (h and type(h.entry) == "string" and h.entry ~= "") then return false end
    E.UpdateCtx()
    if ctx.race == nil then return false end   -- an unknown race: can't judge, ask again next login
    flags.startChecked = true
    if E.Fits(packId, true) then return false end
    -- still at the very start: no detour, nothing skipped / done / dropped, current = first step that applies
    if g:Top() ~= g then return false end
    local save = g.save or {}
    for _, t in ipairs({ save.skips, save.done, save.notDoing }) do
        if type(t) == "table" and next(t) ~= nil then return false end
    end
    local cur = g:Current()
    if not cur then return false end
    local first
    for i = 1, g:Count() do
        local s = g:Step(i)
        if s and g:Applicable(s, true) then first = s break end
    end
    if not (first and first.id == cur.id) then return false end
    E.Close(g.key)
    E.SaveActive()
    ns.Print(ns.U.Fill(ns.L.GUIDE_WRONG_START, { guide = GuideTitle(packId) }))
    local id = E.Suggest()
    local ng = id and E.Open(id)
    if ng then
        E.SaveActive()
        ns.Bus.Fire("StepChanged", ng)
        ns.Print(ns.U.Fill(ns.L.GUIDE_OPENED, { guide = GuideTitle(id) }))
    else
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end   -- the "none" state
        ns.Print(ns.U.Fill(ns.L.GUIDE_NONE, { list = (E.GuideList()) }))
    end
    return true
end

-- A character on a demo pack gets one offer of a real route for the same start, once one is installed.
-- Yes copies the demo's progress (the real routes keep the demo step ids) and opens the route.
function E.OfferUpgrade()
    if ns.safeMode or ns.DB.readOnly.char then return false end
    local g = E.Focused()
    if not g then return false end
    local packId, routeId = g.key:match("^([^/]+)/(.+)$")
    if not (packId and IsDemo(packId)) then return false end
    local flags = ns.DB.char.flags
    if type(flags) ~= "table" or flags.routeOffered then return false end
    local newId
    for _, id in ipairs(E.Fitting(true)) do if not IsDemo(id) then newId = id break end end
    if not newId then return false end
    flags.routeOffered = true
    return ns.Popups.Confirm({ kind = "route", text = ns.U.Fill(ns.L.DIALOG_ROUTE, { guide = GuideTitle(newId) }),
        accept = function() E.Upgrade(g.key, newId, routeId) end })
end

function E.Upgrade(oldKey, newId, routeId)
    local route = P.Open(newId, routeId) or P.Open(newId)
    if not route then return false end
    local newKey = E.Key(newId, route.id)
    local guides = ns.DB.char.guides
    if type(guides[newKey]) ~= "table" and type(guides[oldKey]) == "table" then
        guides[newKey] = ns.U.Copy(guides[oldKey])
    end
    E.Close(oldKey)
    local g = E.Open(newId, route.id)
    if g then
        E.SaveActive()
        ns.Bus.Fire("StepChanged", g)
        ns.Print(ns.U.Fill(ns.L.GUIDE_OPENED, { guide = GuideTitle(newId) }))
    end
    return g ~= nil
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

-- Opens a guide by pack id (the slash command and the title menu's guide rows).
function E.OpenGuide(id)
    local g = E.Open(id)
    if not g then return nil end
    -- picked by hand: FixWrongStart never undoes the player's own choice
    local flags = ns.DB.char and ns.DB.char.flags
    if type(flags) == "table" and not ns.DB.readOnly.char then flags.startChecked = true end
    E.SaveActive()
    ns.Bus.Fire("StepChanged", g)
    ns.Print(ns.U.Fill(ns.L.GUIDE_OPENED, { guide = GuideTitle(id) }))
    if ns.UI and not ns.UI.IsShown() then ns.UI.Show() end
    return g
end
E.GuideTitle = GuideTitle

ns.Slash.Add("guide", function(arg)
    arg = strtrim(tostring(arg or ""))
    if arg == "" then ns.Print(ns.U.Fill(ns.L.GUIDE_LIST, { list = (E.GuideList()) })) return end
    local id = E.FindPack(arg)
    if not id or not E.OpenGuide(id) then
        ns.Print(ns.U.Fill(ns.L.GUIDE_UNKNOWN, { word = arg, list = (E.GuideList()) }))
    end
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
    ns.Errors.Call("engine", E.AfterRefresh)
end

-- After each round (v0.2): ask about the quests of the shown steps (rate-limited, tos R2), and the
-- "quest log full" hint with the log quests this route doesn't use.
-- Optimizer #5: the 0.25 s ticker runs this round while a travel step shows, so its lists are reused
-- tables (wiped each round; nobody keeps them).
local function Wipe(t) for k in pairs(t) do t[k] = nil end return t end
local idsBuf, wantBuf, itemsBuf, visBuf = {}, {}, {}, {}

function E.AfterRefresh()
    local g = E.Focused()
    if not g then return end
    local top = g:Top()
    local ids, n, j = Wipe(idsBuf), top:Count(), top.pos
    while j <= n and #ids < 6 do
        local s = top:Step(j)
        if s and s.quest and top:Applicable(s) and not top.save.skips[s.id] then ids[#ids + 1] = s.quest end
        j = j + 1
    end
    if ns.QuestData then ns.QuestData.Check(ids) end
    local Nt = ns.Notice
    if not Nt then return end
    if top.status == "logfull" then
        local names = {}
        for _, id in ipairs(top:UnneededLogQuests()) do
            if #names >= 5 then break end
            names[#names + 1] = ns.Names.Quest(id, "#" .. id)
        end
        local L = ns.L
        local text = #names > 0 and ns.U.Fill(L.LOGFULL_LIST, { list = table.concat(names, ", ") }) or L.LOGFULL
        Nt.Push({ id = "logfull", kind = "tip", priority = 70, icon = "notice.tip", text = text })
        E.logfullShown = true
    elseif E.logfullShown then
        E.logfullShown = false
        Nt.Remove("logfull")
    end
end

-- The visible steps of a guide (its background goals, then the current step), into `list` (appended).
local function Visible(g, list)
    local top = g:Top()
    for _, b in ipairs(top.bg) do
        local s = top:Step(b)
        if s and top:IsStop(s, b) then list[#list + 1] = s end
    end
    local cur = top:Current()
    if cur then list[#list + 1] = cur end
    return list
end

-- Travel steps can complete by themselves only when both the player's map position and world
-- positions (for yards) can be read; otherwise the player moves past them by hand.
function E.CanTrack() return ns.Feature.IsOn("position") and ns.Feature.IsOn("worldpos") end

-- Listens only to what the visible steps need; watches only their items.
function E.Rewire()
    -- (a nested round, which nothing here causes today, would get its own tables)
    local nested = E.rewiring
    E.rewiring = true
    local want = nested and {} or Wipe(wantBuf)
    local items = nested and {} or Wipe(itemsBuf)
    local vis = nested and {} or Wipe(visBuf)
    for ev in pairs(ALWAYS) do want[ev] = true end
    for _, g in pairs(E.guides) do
        Visible(g, vis)
        -- v0.2: optional steps that show only while an item is in the bags (cond item=<id>)
        for id in pairs(g:Top():CondItems()) do
            items[id] = true
            want.ItemsChanged = true
        end
    end
    do
        for _, s in ipairs(vis) do
            local def = ST.Get(s.type)
            for _, ev in ipairs(def.events) do want[ev] = true end
            -- a travel step auto-skips when its target gets done; an override goal reads quests and items
            if def.travel then want.QuestsChanged, want.QuestTurnedIn = true, true end
            if s.overrideAst then want.QuestsChanged, want.QuestTurnedIn, want.ItemsChanged = true, true, true end
            if s.item then items[s.item] = true end
            if s.useItem then items[s.useItem] = true end   -- v0.2: the step button and "use it now"
            -- an any-order group picks the nearest step, so it follows the player's position
            if s.anyOrder then want.Position = true end
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
    E.rewiring = nested
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
-- Undo (v0.2): the last 10 of the player's skip / next / not doing / set current actions, this session.
-- An "Undo" button shows on the notice line for 10 s after a skip or "not doing"; /aog undo works later too.
E.undo = {}
E.UNDO_MAX, E.UNDO_SECONDS = 10, 10
local undoToken = 0

local function UndoNotice(kind)
    local Nt = ns.Notice
    if not Nt then return end
    undoToken = undoToken + 1
    local token = undoToken
    local L = ns.L
    Nt.Push({ id = "undo", kind = "tip", priority = 60, icon = "notice.tip",
        text = kind == "NotDoing" and L.UNDO_NOTDOING or L.UNDO_SKIPPED,
        button = { text = L.UNDO, fn = function() E.Undo() end } }, true)   -- quiet: Act's StepChanged redraws it
    Co.After(E.UNDO_SECONDS, function()
        if token == undoToken and ns.Notice then ns.Notice.Remove("undo") end
    end)
end

local function Act(method, ...)
    local g = E.Focused()
    if not g then return false end
    local top = g:Top()
    local before = top:Snapshot()
    local cur = top:Current()
    local wasDone = cur and top:Done(cur)
    local ok = top[method](top, ...)
    if ok then
        if method ~= "Back" then
            table.insert(E.undo, { guide = top, snap = before })
            if #E.undo > E.UNDO_MAX then table.remove(E.undo, 1) end
        end
        if method == "Skip" or method == "NotDoing" or (method == "Next" and cur and not wasDone
            and not ST.Get(cur.type).manualDone) then
            UndoNotice(method)
        end
        E.RefreshAll()
        ns.Bus.Fire("StepChanged", g)
        -- v0.3 game data recording (Data\Gather.lua): what the player did on which step (the guide + step id only)
        -- (a Next on a step that isn't done counts as a skip; NotDoing with on = false is taking it back)
        if cur then
            local what = method
            if method == "Next" and not wasDone and not ST.Get(cur.type).manualDone then what = "Skip" end
            if method == "NotDoing" and select(2, ...) == false then what = "Doing" end
            ns.Bus.Fire("StepAction", what, top.key, cur.id)
        end
    end
    return ok
end
function E.Skip(id) return Act("Skip", id) end
function E.SetCurrent(id) return Act("SetCurrent", id) end
function E.Back() return Act("Back") end
function E.Next() return Act("Next") end
-- "Not doing this quest": its steps and its follow-ups (through `pre`) drop out; on = false takes it back.
function E.NotDoing(questID, on) return Act("NotDoing", questID, on) end

function E.Undo()
    local u = table.remove(E.undo)
    if not u then return false end
    u.guide:Restore(u.snap)
    undoToken = undoToken + 1
    if ns.Notice then ns.Notice.Remove("undo") end
    E.RefreshAll()
    local g = E.Focused()
    if g then ns.Bus.Fire("StepChanged", g) end
    local s = u.guide:Current()
    if s then ns.Bus.Fire("StepAction", "Undo", u.guide.key, s.id) end
    return true
end

-- Self-test line (beta.11 bug: later steps' "Optional:" lines after going back): how many optional lines the
-- current step shows and where they come from: "behind" (steps before it, the normal case), "group" (its any-order
-- group), "ahead" (a step after it: a bug), "waiting" (riding along unseen until their quest is in the log).
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "optional", fn = function(h)
    h.Count()
    local g = E.Focused()
    local top = g and g:Top()
    local cur = top and top:Current()
    if not cur then h.Info("optional: no current step") return end
    local shown, behind, group, ahead, waiting = 0, 0, 0, {}, 0
    for _, s in ipairs(top:Background()) do
        if s.flags.optional then
            shown = shown + 1
            if s.index < cur.index then behind = behind + 1
            elseif s.anyOrder and s.anyOrder == cur.anyOrder then group = group + 1
            else ahead[#ahead + 1] = s.id end
        end
    end
    for _, b in ipairs(top.bg) do
        local s = top:Step(b)
        if s and s.flags.optional and top:WaitsForQuest(s) then waiting = waiting + 1 end
    end
    h.Info(("optional: %d lines at %s (behind %d, group %d, ahead %d, waiting %d)"):format(shown, tostring(cur.id),
        behind, group, #ahead, waiting))
    if #ahead > 0 then h.Problem("optional: lines from later steps: " .. table.concat(ahead, ",", 1, math.min(#ahead, 3))) end
end }

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
ns.Slash.Add("undo", function()
    if not E.Undo() then ns.Print(ns.L.UNDO_NONE) end
end, "HELP_UNDO")
ns.Slash.Add("back", function() E.Back() end, "HELP_BACK")

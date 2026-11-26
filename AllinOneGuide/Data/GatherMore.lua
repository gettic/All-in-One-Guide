-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.3 game data recording, revision 6 (plans\data-gathering\plan.md "rev 6", CHANGED: tos re-check): the more kinds,
-- hung on Data\Gather.lua's points (G.On_), its bus list (G.BUS) and event list. Loads after Gather.lua, only
-- while that file loads (both are out of the .toc until v0.3; the scenarios load them). Same rules as Gather.lua:
-- own character only, NPC / object ids only from Creature / Vehicle / GameObject GUIDs, no names, no other players,
-- no money total, no health or power (tos R1), spots rounded to whole map percent, nothing read at login (the
-- session parts wait for the first step change), every handler cheap (no OnUpdate; one 5 s ticker that returns at
-- once unless the arrow is shown).
-- Kinds: sact, step (expected time, stuck), leg (XP per stretch), trav, mv, rest, mount, spec, set, guide, perf,
-- use, err, miss, chain, pmiss, qstart, rdrop, grp, abandon, qfail, qtime, obj, ostk, death, crun, gy, ctype, tap,
-- pull, ttk, cast, eat, rew, gear, stat, bagfull, repair, fpl, expl, ammo, earn
local _, ns = ...
local G = ns.Gather
if not G then return end
local Co = ns.Compat
local Bump, Cell, Level = G.Bump, G.Cell, G.Level
local M = { LEG = 10, LEG_MIN = 120, STUCK = 3, FOE_AGE = 60, OFFER = 20, OBJ_STUCK = 600, CHAIN_WAIT = 15,
    SAMPLE = 5, OFFPATH = 1.4, PERF_KEEP = 64, LOW_DUR = 0.2, EAT_MIN = 15, EAT_MAX = 35, HEARTH = 6948,
    HEARTH_SPELL = 8690, RIDING = 762, CASTS = 20, QACC = 40 }
G.More = M

for _, ev in ipairs({ "MERCHANT_CLOSED", "UPDATE_INVENTORY_DURABILITY", "ZONE_CHANGED" }) do
    G.EVENTS[#G.EVENTS + 1] = ev
end

local S = {}            -- this session's in-memory state (G.Start makes a fresh one)
M.S = function() return S end

-- ------------------------------------------------------------------ small helpers
local function Now() return Co.Now() end
local function Cur()
    local E = ns.Engine
    if not (E and E.Current) then return nil end
    return E.Current()
end
local function Id(v) return v ~= nil and tostring(v) or nil end
local function Num(f, ...)
    if not f then return nil end
    local ok, v = pcall(f, ...)
    return ok and Co.Num(v) or nil
end
local function Text(v)
    if type(v) ~= "string" or Co.IsSecret(v) or v == "" then return nil end
    return (v:gsub("[%c=;|]", " "):sub(1, 30))
end
local function Spec() local v = Num(Co.fn.Spec) return v and v > 0 and v or nil end
local function Square()
    local m, x, y = G.Where()
    return m, Cell(x, y, G.CELL)
end
local function R10(v) return math.floor(v / 10 + 0.5) * 10 end
local function StepCtx()
    local s, top = Cur()
    if not (s and top) then return {} end
    return { s = Id(s.id), pk = top.key }
end
-- active minutes of the session (gaps of G.PAUSE or more left out)
local function Touch()
    local t = Now()
    if S.lastAct and t - S.lastAct < G.PAUSE then S.active = (S.active or 0) + (t - S.lastAct) end
    S.lastAct = t
end

-- ------------------------------------------------------------------ guide use (step actions, stuck, stretches)
G.BUS.StepAction = function(_, what, pk, id)
    local field = ({ Skip = "skp", Undo = "und", NotDoing = "nd", Back = "bk" })[what]
    if not field or type(pk) ~= "string" or id == nil then return end
    id = Id(id)
    Bump(G.Add("sact:" .. pk .. ":" .. id, { k = "sact", pk = pk, s = id }), field)
end

G.BUS.StepTimed = function(_, guide, step, seconds, est)
    seconds, est = Co.Num(seconds), Co.Num(est)
    step = Id(step)
    if type(guide) ~= "string" or type(step) ~= "string" or not seconds then return end
    local r = G.Add("step:" .. guide .. ":" .. step, { k = "step", pk = guide, s = step, t = 0 })
    if not r then return end
    if est and est > 0 then r.e = R10(est) end
    if est and est > 0 and seconds > est * M.STUCK and seconds > 120 then
        Bump(r, "st")                      -- stuck (or away): counted, its time left out
    else
        Bump(r, "t", R10(seconds))
    end
end

local function XPGain()
    local xp, max = Co.XP()
    local lvl = Level()
    if not xp then return 0 end
    local o = S.xp
    S.xp = { xp, max, lvl }
    if not o then return 0 end
    local gain = (lvl and o[3] and lvl > o[3]) and ((o[2] or 0) - o[1] + xp) or (xp - o[1])
    return gain > 0 and gain or 0
end

local function FinishLeg(L)
    local t = Now()
    local gap = t - L.last
    if gap < G.PAUSE then L.sec = L.sec + gap end
    if L.sec < M.LEG_MIN or L.steps < 3 then return end
    local hi = Level()
    local r = G.Add("leg:" .. L.pk .. ":" .. L.s, { k = "leg", pk = L.pk, s = L.s, lo = L.lo, hi = hi, spc = Spec(), ns = 0,
        xp = 0, sec = 0 })
    if not r then return end
    Bump(r, "ns", L.steps)
    Bump(r, "xp", L.xp)
    Bump(r, "sec", R10(L.sec))
    if L.dd > 0 then Bump(r, "dd", L.dd) end
    if L.lo and (not r.lo or L.lo < r.lo) then r.lo = L.lo end
    if hi and (not r.hi or hi > r.hi) then r.hi = hi end
end

local function Leg(s, top)
    local L, t = S.leg, Now()
    if not (s and top) then return end
    local map = Co.PlayerMap()
    local idx = s.index or 0
    if L and (L.pk ~= top.key or idx < L.idx or (map and L.m and map ~= L.m)) then
        FinishLeg(L)
        L = nil
    end
    if L then
        local gap = t - L.last
        if gap < G.PAUSE then L.sec = L.sec + gap end
        L.last = t
        if idx > L.idx then L.steps, L.idx = L.steps + (idx - L.idx), idx end
        if L.steps >= M.LEG then FinishLeg(L) L = nil end
    end
    if not L then L = { pk = top.key, s = Id(s.id), idx = idx, steps = 0, sec = 0, last = t, lo = Level(), xp = 0, m = map, dd = 0 } end
    S.leg = L
end

local function HearthReady()
    local st, d = Co.ItemCooldown(M.HEARTH)
    return d == 0 or st + d - Now() <= 0
end

local function FinishStep(p, s, top)
    local fwd = s and top and top.key == p.pk and (s.index or 0) > p.idx
    if p.type == "fly" or p.type == "hearth" or p.hs > 0 or p.fl > 0 then
        local r = G.Add("trav:" .. p.pk .. ":" .. p.id, { k = "trav", pk = p.pk, s = p.id, hs = 0, fl = 0, wk = 0 })
        Bump(r, "hs", p.hs)
        Bump(r, "fl", p.fl)
        if fwd and p.type == "fly" and p.fl == 0 then Bump(r, "wk") end
    end
    if fwd then
        local r = G.Add("mv:" .. p.pk .. ":" .. p.id, { k = "mv", pk = p.pk, s = p.id, hr = 0 })
        if r then
            if p.hr then Bump(r, "hr") end
            if p.mt > 0 then Bump(r, "mt", p.mt) end
            if p.sw > 0 then Bump(r, "sw", p.sw) end
            if p.ft > 0 then Bump(r, "ft", p.ft) end
            if p.dev > 0 then
                Bump(r, "dev", p.dev)
                if not r.c then r.m, r.c = p.devm, p.devc end
            end
        end
    end
    if p.q and (p.type == "objective" or p.type == "grind") and not p.prog and Now() - p.t > M.OBJ_STUCK then
        local r = G.Add("ostk:" .. p.q .. ":" .. p.id, { k = "ostk", q = p.q, pk = p.pk, s = p.id, min = 0 })
        Bump(r, "min", math.floor((Now() - p.t) / 60 + 0.5))
    end
end

-- ------------------------------------------------------------------ the session parts (first step change)
local function Settings()
    local kv = {}
    for _, d in ipairs(ns.Settings.schema or {}) do
        local kind = d.kind
        if d.key ~= "gatherData" and (kind == "bool" or kind == "number" or kind == "choice") then
            local v = ns.Settings.Get(d.key)
            if v ~= nil and v ~= d.default then
                if type(v) == "number" then v = math.floor(v * 100 + 0.5) / 100 end
                if type(v) == "boolean" or type(v) == "number" or (type(v) == "string" and v:match("^[%w_]+$")) then
                    kv[#kv + 1] = d.key .. ":" .. tostring(v)
                end
            end
        end
    end
    table.sort(kv)
    return table.concat(kv, ",")
end

local function SessionOnce(top)
    if S.once then return end
    S.once = true
    local pl = Level()
    if not pl then return end
    local pct = Co.RestedPct()
    if pct then G.Add("rest:" .. pl .. ":" .. pct, { k = "rest", pl = pl, pct = pct }) end
    if Co.fn.SkillLineByID or Co.fn.SkillLines then
        local rd = Co.SkillRank(M.RIDING) or 0
        G.Add("mount:" .. pl .. ":" .. rd, { k = "mount", pl = pl, rd = rd })
    end
    local spc = Spec()
    if spc then G.Add("spec:" .. pl .. ":" .. spc, { k = "spec", pl = pl, spc = spc }) end
    local kv = Settings()
    if kv ~= "" then
        G.Add("set:" .. ns.Format.Adler32(kv), { k = "set", kv = kv:sub(1, 600) })
    end
    if top then G.Add("guide:" .. top.key, { k = "guide", pk = top.key, pl = pl }) end
    S.loginMs = ns.Perf and Co.Num(ns.Perf.loginMs)
end

-- feature use: the item / target buttons (PostClick hooks, out of combat only)
local function HookButtons()
    if S.hookedButtons or Co.InCombat() then return end
    local done = true
    for _, e in ipairs({ { ns.StepButton, "itembtn" }, { ns.TargetButton, "targetbtn" } }) do
        local mod, name = e[1], e[2]
        local b = mod and mod.NAME and rawget(_G, mod.NAME)
        if b and b.HookScript and not M["hooked_" .. name] then
            M["hooked_" .. name] = true
            b:HookScript("PostClick", function()
                if G.on then G.Add("use:" .. name, { k = "use", uk = name }) end
            end)
        elseif not M["hooked_" .. name] then
            done = false
        end
    end
    S.hookedButtons = done
end

G.BUS.StepChanged = function()
    local s, top = Cur()
    local t = Now()
    SessionOnce(top)
    HookButtons()
    if not M.arrowHooked then M.HookArrow() end
    Touch()
    local p = S.step
    local same = p and s and top and p.id == Id(s.id) and p.pk == top.key
    if p and not same then FinishStep(p, s, top) end
    if s and top and not same then
        S.prevSpot = p and p.map and { p.map, p.x, p.y } or S.prevSpot
        S.step = { id = Id(s.id), pk = top.key, type = s.type, idx = s.index or 0, q = s.quest, npc = s.npc, map = s.map,
            x = s.x, y = s.y, t = t, hs = 0, fl = 0, mt = 0, sw = 0, ft = 0, dev = 0, hr = HearthReady() }
    elseif not s then
        S.step = nil
    end
    Leg(s, top)
end

-- per-step refresh time (our own engine function, wrapped while recording; 2 timer reads per refresh)
local function WrapRefresh(on)
    local E = ns.Engine
    if not E then return end
    if on and not M.realRefresh then
        local real = E.RefreshAll
        M.realRefresh = real
        E.RefreshAll = function(...)
            local t0 = Co.Ms()
            real(...)
            local list = S.rf
            if list then
                list[#list % M.PERF_KEEP + 1] = Co.Ms() - t0
            end
        end
    elseif not on and M.realRefresh then
        E.RefreshAll = M.realRefresh
        M.realRefresh = nil
    end
end

local function Median(list)
    local t = {}
    for _, v in ipairs(list or {}) do t[#t + 1] = v end
    if #t == 0 then return nil end
    table.sort(t)
    return t[math.floor((#t + 1) / 2)]
end

-- ------------------------------------------------------------------ addon errors (our own path only)
local function Short(path) return (path:gsub("\\", "/"):gsub("^.-AllinOneGuide/", "")) end
function M.OnError(feature, text)
    if not G.on or type(text) ~= "string" then return end
    local first = text:match("^[^\n]*") or ""
    local loc = first:match("AllinOneGuide[\\/][%w_\\/]+%.lua:%d+")
    local msg = ns.U.StripNames(first):gsub("^.-%.lua:%d+: ", ""):gsub('"[^"]*"', '"?"'):gsub("'[^']*'", "'?'"):gsub("[%c=;|]", " "):sub(1, 120)
    local stk = {}
    for line in text:gmatch("[^\n]+") do
        local at = line:match("AllinOneGuide[\\/][%w_\\/]+%.lua:%d+")
        if at and at ~= loc and #stk < 3 then stk[#stk + 1] = Short(at) end
    end
    loc = loc and Short(loc) or nil
    local c = StepCtx()
    local r = G.Add("err:" .. ns.Format.Adler32(msg .. (loc or "")), { k = "err", fe = Text(feature), msg = msg, at = loc,
        stk = #stk > 0 and table.concat(stk, ",") or nil, s = c.s, pk = c.pk })
    return r
end
if ns.Errors then ns.Errors.onRecord = M.OnError end

-- ------------------------------------------------------------------ quests: offers, chains, prerequisites, times
G.On_("talk", function(event)
    if event == "QUEST_COMPLETE" then return M.RewardList() end
    if event ~= "GOSSIP_SHOW" and event ~= "QUEST_GREETING" then return end
    local id, kind = Co.UnitNpcId("npc")
    if not (id and kind == "npc") then return end
    local list = Co.OfferedQuests(event == "GOSSIP_SHOW" and "gossip" or "greeting", M.OFFER)
    if not list then return end
    local s, top = Cur()
    local route = top and top.RouteQuests and top:RouteQuests()
    local offered = {}
    for _, o in ipairs(list) do
        if o.q then
            offered[o.q] = true
            if route and not route[o.q] then
                G.Add("miss:" .. id .. ":" .. o.q, { k = "miss", npc = id, q = o.q, ql = o.lvl, pk = top.key, m = Co.PlayerMap() })
            end
        elseif o.t and route then
            local tt = o.t:gsub("[%c=;|]", " "):sub(1, 40)
            G.Add("miss:" .. id .. ":t:" .. tt, { k = "miss", npc = id, tt = tt, pk = top.key })
        end
    end
    local ti = S.turnin
    if ti and ti.npc == id and Now() - ti.t <= M.CHAIN_WAIT then
        local seen, new = S.offerSeen[id] or {}, {}
        for q in pairs(offered) do if not seen[q] then new[#new + 1] = q end end
        if #new > 0 then
            table.sort(new)
            G.Add("chain:" .. ti.q .. ":" .. id, { k = "chain", q = ti.q, npc = id, nq = table.concat(new, ",", 1, math.min(#new, 10)) })
        end
        S.turnin = nil
    end
    S.offerN = (S.offerN or 0) + 1
    if S.offerN > 60 then S.offerSeen, S.offerN = {}, 0 end
    S.offerSeen[id] = offered
    if s and s.type == "accept" and s.npc == id and s.quest and not offered[s.quest] and not Co.OnQuest(s.quest)
        and not Co.QuestFlagged(s.quest) then
        G.Add("pmiss:" .. s.quest .. ":" .. id, { k = "pmiss", q = s.quest, npc = id, pl = Level(), pk = top.key, s = Id(s.id) })
    end
end)

G.On_("accept", function(q)
    Touch()
    local ti, tk = S.turnin, G.talk
    if ti and ti.npc and tk and tk.id == ti.npc and Now() - ti.t <= M.CHAIN_WAIT and not (S.offerSeen[ti.npc] or {})[q] then
        G.Add("chain:" .. ti.q .. ":" .. ti.npc, { k = "chain", q = ti.q, npc = ti.npc, nq = tostring(q) })
        S.turnin = nil
    end
    local qa = G.db.qacc
    local n = 0
    for _ in pairs(qa) do n = n + 1 end
    if n < M.QACC then qa[q] = Now() end
end)

G.On_("turnin", function(q, _, money)
    Touch()
    local t = Now()
    S.turnin = { q = q, npc = G.talk and G.talk.id, t = t }
    S.turned[q] = t
    local gs = Co.GroupSize() or 1
    G.Add("grp:q:" .. q .. ":" .. gs, { k = "grp", q = q, gs = gs })
    local at = G.db.qacc[q]
    if at and t >= at then
        local r = G.Add("qtime:" .. q, { k = "qtime", q = q, min = 0 })
        Bump(r, "min", math.min(600, math.floor((t - at) / 60 + 0.5)))
    end
    G.db.qacc[q] = nil
    if money and money > 0 then S.earn.q = S.earn.q + money end
end)

-- an abandoned quest: QUEST_REMOVED without a turn-in just before or after
local removed = G.HANDLERS.QUEST_REMOVED
G.HANDLERS.QUEST_REMOVED = function(ev, q, ...)
    removed(ev, q, ...)
    q = Co.Num(q)
    if not q then return end
    local c, pl, gs = StepCtx(), Level(), Co.GroupSize() or 1
    Co.After(1, function()
        ns.Errors.Call("gather", function()
            local t = S.turned and S.turned[q]
            if t and math.abs(Now() - t) <= 3 then return end
            G.db.qacc[q] = nil
            G.Add("abandon:" .. q, { k = "abandon", q = q, pl = pl, s = c.s, pk = c.pk, gs = gs })
        end)
    end)
end

-- objectives done (time since accept, coarse square), progress at the step, failed quests (escorts)
G.BUS.QuestsChanged = function(_, changed)
    if type(changed) ~= "table" then return end
    local t = Now()
    for q in pairs(changed) do
        if type(q) == "number" then
            local objs = Co.Objectives(q)
            if objs then
                local old = S.obj[q]
                local now = {}
                for i, o in ipairs(objs) do
                    if type(o) == "table" then
                        local fin = Co.IsTrue(o.finished) == true
                        now[i] = fin
                        if old and fin and not old[i] then
                            local m, c = Square()
                            local at = G.db.qacc[q]
                            G.Add("obj:" .. q .. ":" .. i, { k = "obj", q = q, oi = i, m = m, c = c,
                                sec = at and R10(t - at) or nil })
                        end
                        if S.step and S.step.q == q and (Co.Num(o.numFulfilled) or 0) > 0 then S.step.prog = true end
                    end
                end
                S.obj[q] = now
            end
            if Co.QuestFailed(q) and not S.failed[q] then
                S.failed[q] = true
                local c = StepCtx()
                local why = (S.died and t - S.died.t <= 30) and "d" or "o"
                G.Add("qfail:" .. q .. ":" .. why, { k = "qfail", q = q, why = why, s = c.s, pk = c.pk })
            end
        end
    end
end

-- ------------------------------------------------------------------ rewards (the list offered, the one picked)
function M.RewardList()
    local q = Num(Co.fn.QuestID)
    local n = Num(Co.fn.NumChoices)
    S.rew = nil
    if not (q and n and n > 1 and Co.fn.QuestItemLink) then return end
    local ids = {}
    for i = 1, math.min(n, 10) do
        local ok, link = pcall(Co.fn.QuestItemLink, "choice", i)
        local id = ok and type(link) == "string" and not Co.IsSecret(link) and tonumber(link:match("item:(%d+)"))
        ids[i] = id or 0
    end
    S.rew = { q = q, ids = ids }
end
function M.OnReward(choice)
    local rw = S.rew
    S.rew = nil
    choice = Co.Num(choice)
    if not (G.on and rw and choice and rw.ids[choice]) then return end
    G.Add("rew:" .. rw.q, { k = "rew", q = rw.q, ch = table.concat(rw.ids, ","), it = rw.ids[choice], spc = Spec() })
end

-- ------------------------------------------------------------------ loot: quest starters, recipes, group, camps, money
G.On_("loot", function(slots, npcs, objs, m)
    Touch()
    for _, e in ipairs(slots) do
        if e.item then
            local recipe = (Co.ItemClass(e.item)) == 9
            for _, src in ipairs(e.sources) do
                local f = src[2] == "object" and { obj = src[1] } or { npc = src[1] }
                if e.starts then
                    f.k, f.it, f.q = "qstart", e.item, e.starts
                    G.Add("qstart:" .. e.item .. ":" .. src[1], f)
                elseif recipe then
                    f.k, f.it = "rdrop", e.item
                    G.Add("rdrop:" .. e.item .. ":" .. src[1], f)
                end
            end
        end
    end
    local gs = Co.GroupSize() or 1
    for _, id in ipairs(npcs) do
        G.Add("grp:n:" .. id .. ":" .. gs, { k = "grp", npc = id, gs = gs })
        -- kills per minute at a camp: the time between this NPC's loots (gaps of 5 min or more left out)
        local key = id .. ":" .. (m or "")
        local t, last = Now(), S.camp[key]
        if last and t - last < 300 and m then Bump(G.db.live.recs["camp:" .. id .. ":" .. m], "sec", math.floor(t - last + 0.5)) end
        S.camp[key] = t
    end
    S.lastObjLoot = #npcs == 0 and #objs > 0 or nil
end)

G.On_("lootClosed", function(w)
    if #w.npcs == 0 then S.earn.g = S.earn.g + (w.value or 0) return end
    if Co.InInstance() then S.earn.d = S.earn.d + (w.cu or 0) else S.earn.m = S.earn.m + (w.cu or 0) end
end)

-- vendor sales: money going up while a merchant window is open (spending is left out)
local MV = {}
local merchant = G.HANDLERS.MERCHANT_SHOW
G.HANDLERS.MERCHANT_SHOW = function(...)
    merchant(...)
    S.vendMoney = Co.Money()
    if S.vendMoney then
        ns.Events.On("PLAYER_MONEY", MV, function()
            local now = Co.Money()
            if now and S.vendMoney and now > S.vendMoney then S.earn.v = S.earn.v + (now - S.vendMoney) end
            S.vendMoney = now or S.vendMoney
        end, "gather")
    end
end
G.HANDLERS.MERCHANT_CLOSED = function()
    ns.Events.Off("PLAYER_MONEY", MV)
    S.vendMoney = nil
end
M.MV = MV

-- ------------------------------------------------------------------ targets, fights, deaths
G.On_("target", function(id)
    local m, c = Square()
    if not S.ctSeen[id] then
        S.ctSeen[id] = true
        local ct, cf = Text(Co.fn.CreatureType and Co.fn.CreatureType("target")), Text(Co.fn.CreatureFamily and Co.fn.CreatureFamily("target"))
        if ct or cf then G.Add("ctype:" .. id, { k = "ctype", npc = id, ct = ct, cf = cf }) end
    end
    local td = Co.fn.TapDenied and Co.fn.TapDenied("target")
    if Co.IsTrue(td) and m then          -- secret first (tos T16): IsTrue checks it before comparing
        G.Add("tap:" .. id .. ":" .. m, { k = "tap", npc = id, m = m, c = c })
    end
    if Co.CanAttack("target") then S.foe = { npc = id, lvl = Co.UnitLevelOf("target"), t = Now() } end
end)

G.On_("combat", function(on)
    local t = Now()
    if on then
        local id, kind = Co.UnitNpcId("target")
        if id and kind == "npc" and Co.CanAttack("target") then
            local lvl = Co.UnitLevelOf("target")
            S.fight = { npc = id, lvl = lvl, t = t }
            local st = S.step
            if not (st and st.npc == id) then
                local m, c = Square()
                if m then G.Add("pull:" .. id .. ":" .. m, { k = "pull", npc = id, ml = lvl, m = m, c = c, s = st and st.id, pk = st and st.pk }) end
            end
        else
            S.fight = { t = t }
        end
        S.casts, S.nCasts = {}, 0
        return
    end
    local f = S.fight
    S.fight = nil
    S.fightEnd = t
    local pl = Level()
    if f and f.npc and pl and Co.UnitDead("target") and Co.UnitNpcId("target") == f.npc then
        local r = G.Add("ttk:" .. f.npc .. ":" .. pl, { k = "ttk", npc = f.npc, ml = f.lvl, pl = pl, spc = Spec(), sec = 0 })
        Bump(r, "sec", math.floor(t - f.t + 0.5))
    end
    if pl then
        for sp, n in pairs(S.casts or {}) do
            local r = G.Add("cast:" .. sp .. ":" .. pl, { k = "cast", sp = sp, pl = pl, cn = 0, cb = 0 })
            Bump(r, "cn", n)
            Bump(r, "cb")
        end
    end
    S.casts = nil
    M.Ammo()
    if S.statWait then S.statWait = nil M.Stats(S.statWhy or "lvl") end
end)

G.On_("dead", function()
    local t = Now()
    local pl = Level()
    local m, c = Square()
    local npc, ml
    local id, kind = Co.UnitNpcId("target")
    if id and kind == "npc" and Co.CanAttack("target") then
        npc, ml = id, Co.UnitLevelOf("target")
    elseif S.foe and t - S.foe.t <= M.FOE_AGE then
        npc, ml = S.foe.npc, S.foe.lvl
    end
    local hc = Co.Hardcore()
    local st = S.step
    G.Add(table.concat({ "death", m or "", c or "", pl or "", npc or "" }, ":"), { k = "death", m = m, c = c, pl = pl, npc = npc,
        ml = ml, s = st and st.id, pk = st and st.pk, spc = Spec(), hc = hc == nil and nil or (hc and 1 or 0) })
    S.died = { t = t, m = m }
    if S.leg then S.leg.dd = S.leg.dd + 1 end
end)

-- the release (graveyard spot) and the way back (corpse run seconds)
G.BUS.DeadChanged = function(_, dead, ghost)
    local d = S.died
    if not d then return end
    if ghost and not d.gy then
        d.gy = true
        local m, c = Square()
        if m then G.Add("gy:" .. m .. ":" .. (c or ""), { k = "gy", m = m, c = c }) end
    elseif not dead and not ghost then
        S.died = nil
        if d.gy and d.m then
            local r = G.Add("crun:" .. d.m, { k = "crun", m = d.m, pl = Level(), sec = 0 })
            Bump(r, "sec", R10(Now() - d.t))
        end
    end
end

-- ------------------------------------------------------------------ spells: hearth, casts per fight, eating
local function EatCheck(e)
    if not (G.on and S.eat == e) then return end
    local aura = Co.fn.PlayerAura and select(2, pcall(Co.fn.PlayerAura, e.sp))
    local over = type(aura) ~= "table" or Co.IsSecret(aura) or Co.InCombat() or Now() - e.t > M.EAT_MAX + 5
    if not over then
        Co.After(1, function() ns.Errors.Call("gather", EatCheck, e) end)
        return
    end
    S.eat = nil
    local pl = Level()
    if pl then
        local r = G.Add("eat:" .. pl, { k = "eat", pl = pl, sec = 0 })
        Bump(r, "sec", math.floor(Now() - e.t + 0.5))
    end
end

G.On_("spell", function(spell)
    if spell == M.HEARTH_SPELL and S.step then S.step.hs = 1 end
    if Co.InCombat() then
        local c = S.casts
        if c and (c[spell] or (S.nCasts or 0) < M.CASTS) then
            if not c[spell] then S.nCasts = (S.nCasts or 0) + 1 end
            c[spell] = (c[spell] or 0) + 1
        end
        return
    end
    if not Co.fn.PlayerAura or S.eat then return end
    local ok, aura = pcall(Co.fn.PlayerAura, spell)
    if not ok or type(aura) ~= "table" or Co.IsSecret(aura) then return end
    local dur = Co.Num(aura.duration)
    if dur and dur >= M.EAT_MIN and dur <= M.EAT_MAX then
        S.eat = { sp = spell, t = Now() }
        local e = S.eat
        Co.After(1, function() ns.Errors.Call("gather", EatCheck, e) end)
    end
end)

G.On_("takeTaxi", function() if S.step then S.step.fl = 1 end end)

-- flight paths learned: open-map nodes not known at the start of the session
G.On_("taxiOpen", function()
    for _, map in ipairs(ns.Taxi and ns.Taxi.CONTINENTS or {}) do
        for _, n in ipairs(Co.TaxiOpenNodes(map)) do
            if n.id and not S.taxi[n.id] then
                S.taxi[n.id] = true
                G.Add("fpl:" .. n.id, { k = "fpl", fn = n.id, pl = Level() })
            end
        end
    end
end)

-- ------------------------------------------------------------------ level-ups: gear ranges, stats, ammo
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
function M.Gear(pl)
    local get, lvl = Co.fn.InvItemID, Co.fn.ItemLevel
    if not (get and lvl) then return end
    local out = {}
    for _, slot in ipairs(SLOTS) do
        local id = Num(get, "player", slot)
        local il = id and Num(lvl, id)
        if il and il > 0 then
            local lo = math.floor(il / 5) * 5
            out[#out + 1] = slot .. ":" .. lo .. "-" .. (lo + 4)
        end
    end
    if #out > 0 then G.Add("gear:" .. pl, { k = "gear", pl = pl, eq = table.concat(out, ","), spc = Spec() }) end
end

-- own stat totals (out of combat only; any secret or missing value is left out)
function M.Stats(why)
    if Co.InCombat() then S.statWait, S.statWhy = true, why return end
    local pl = Level()
    if not pl then return end
    local F, v = Co.fn, {}
    local function Add(x) v[#v + 1] = x and tostring(math.floor(x * 10 + 0.5) / 10) or "" end
    for i = 1, 5 do Add(Num(F.UnitStat, "player", i)) end
    Add(Num(F.UnitArmor, "player"))
    Add(Num(F.UnitAP, "player"))
    Add(Num(F.Crit))
    Add(Num(F.SpellCrit, 2))
    Add(Num(F.SpellDmg, 2))
    Add(Num(F.ManaRegen))
    local text = table.concat(v, ",")
    if text:gsub(",", "") == "" then return end
    G.Add("stat:" .. why .. ":" .. pl, { k = "stat", pl = pl, why = why, stt = text, spc = Spec() })
end

function M.Ammo()
    if Co.Player().class ~= "HUNTER" or not Co.fn.InvCount then return end
    local n = Num(Co.fn.InvCount, "player", 0)
    if not n then return end
    if S.ammo and n < S.ammo then S.ammoUsed = (S.ammoUsed or 0) + (S.ammo - n) end
    S.ammo = n
end

G.BUS.LevelChanged = function()
    local pl = Level()
    if not pl then return end
    if S.ammoUsed and S.ammoUsed > 0 then
        G.Add("ammo:" .. (pl - 1), { k = "ammo", pl = pl - 1, am = S.ammoUsed })
        S.ammoUsed = 0
    end
    M.Gear(pl)
    M.Stats("lvl")
end

-- dungeon start: stats once per run
local world = G.HANDLERS.PLAYER_ENTERING_WORLD
G.HANDLERS.PLAYER_ENTERING_WORLD = function(...)
    world(...)
    local run = G.db and G.db.run
    if run and not run.st then
        run.st = 1
        M.Stats("dun")
    end
end

-- ------------------------------------------------------------------ bags full, repair needed, exploration
G.BUS.BagsChanged = function()
    ns.Events.Debounce("gather.bags", 2, function()
        local f = Co.fn.FreeSlots
        if not (G.on and f) then return end
        local free = 0
        for bag = 0, 4 do free = free + (Num(f, bag) or 0) end
        if free == 0 and not S.full then
            S.full = true
            local st = S.step
            G.Add("bagfull:" .. Level() .. ":" .. (st and st.id or ""), { k = "bagfull", pl = Level(), s = st and st.id, pk = st and st.pk })
        elseif free > 0 then
            S.full = false
        end
    end, "gather")
end

G.HANDLERS.UPDATE_INVENTORY_DURABILITY = function()
    local f = Co.fn.Durability
    if not f then return end
    local low = 1
    for _, slot in ipairs(SLOTS) do
        local ok, cur, max = pcall(f, slot)
        cur, max = ok and Co.Num(cur), ok and Co.Num(max)
        if cur and max and max > 0 then low = math.min(low, cur / max) end
    end
    if low < M.LOW_DUR and not S.lowDur then
        S.lowDur = true
        local st = S.step
        G.Add("repair:" .. (Level() or 0) .. ":" .. (st and st.id or ""), { k = "repair", pl = Level(), s = st and st.id, pk = st and st.pk })
    elseif low >= M.LOW_DUR then
        S.lowDur = false
    end
end

G.HANDLERS.ZONE_CHANGED = function() S.subAt = Now() end

G.BUS.XPChanged = function()
    local gain = XPGain()
    if gain <= 0 then return end
    if S.leg then S.leg.xp = S.leg.xp + gain end
    local t = Now()
    local lt, ll = G.lastTurnIn, G.lastLoot
    if Co.InCombat() or (lt and t - lt.t <= 3) or (ll and t - ll.t <= 5) or (S.fightEnd and t - S.fightEnd <= 5) then return end
    if not (S.subAt and t - S.subAt <= 5) then return end
    local m, c = Square()
    if m then G.Add("expl:" .. m .. ":" .. (G.Sub() or c or ""), { k = "expl", m = m, c = c, xp = gain, pl = Level() }, nil) end
end

-- ------------------------------------------------------------------ feature use (our own settings switched)
G.BUS.SettingsChanged = function(_, key, value)
    if type(key) ~= "string" or key == "gatherData" or type(value) ~= "boolean" then return end
    G.Add("use:" .. key .. ":" .. (value and 1 or 0), { k = "use", uk = key, on = value and 1 or 0 })
end

-- ------------------------------------------------------------------ travel samples (every 5 s, only while the arrow shows)
local function Sample()
    if not G.on then return end
    local st = S.step
    local A = ns.Arrow
    if not (st and A and A.frame and A.frame:IsShown()) then return end
    local F = Co.fn
    if F.Mounted and Co.IsTrue(F.Mounted()) then st.mt = st.mt + 1
    elseif F.Swimming and Co.IsTrue(F.Swimming()) then st.sw = st.sw + 1
    else st.ft = st.ft + 1 end
    local p = S.prevSpot
    if not (p and p[1] and p[2] and st.map and st.x and ns.Geo) then return end
    local x, y = Co.PlayerPos(st.map)
    if not x then return end
    local Gd = ns.Geo.Distance
    local d = Gd(p[1], p[2], p[3], st.map, st.x, st.y)
    local d1, d2 = Gd(p[1], p[2], p[3], st.map, x, y), Gd(st.map, x, y, st.map, st.x, st.y)
    if d and d1 and d2 and d1 + d2 > d * M.OFFPATH + 50 then
        st.dev = st.dev + 1
        if not st.devc then st.devm, st.devc = st.map, Cell(x * 100, y * 100, G.CELL) end
    end
end

-- the ticker runs only while the arrow is shown (tos T22): started / stopped by the arrow frame's own show / hide
function M.TickerOn()
    if G.on and not M.ticker then M.ticker = Co.Ticker(M.SAMPLE, function() ns.Errors.Call("gather", Sample) end) end
end
function M.TickerOff()
    if M.ticker and M.ticker.Cancel then M.ticker:Cancel() end
    M.ticker = nil
end
function M.HookArrow()
    local f = ns.Arrow and ns.Arrow.frame
    if not f then return end
    if not M.arrowHooked and f.HookScript then
        M.arrowHooked = true
        f:HookScript("OnShow", function() ns.Errors.Call("gather", M.TickerOn) end)
        f:HookScript("OnHide", function() ns.Errors.Call("gather", M.TickerOff) end)
    end
    if f:IsShown() then M.TickerOn() else M.TickerOff() end
end

-- ------------------------------------------------------------------ start, stop, logout
G.On_("start", function()
    S = { offerSeen = {}, obj = {}, failed = {}, ctSeen = {}, camp = {}, turned = {}, taxi = {}, rf = {},
        earn = { q = 0, v = 0, d = 0, m = 0, g = 0 }, t0 = Now() }
    G.db.qacc = type(G.db.qacc) == "table" and G.db.qacc or {}
    for q, t in pairs(G.db.qacc) do if type(t) ~= "number" or t > Now() then G.db.qacc[q] = nil end end
    G.db.sess = (tonumber(G.db.sess) or 0) + 1
    for _, map in ipairs(ns.Taxi and ns.Taxi.CONTINENTS or {}) do
        for _, n in ipairs(Co.TaxiNodesForMap(map)) do if n.known then S.taxi[n.id] = true end end
    end
    XPGain()
    WrapRefresh(true)
    M.HookArrow()
    -- tos T4-like: hooked only if it exists, never called; once (the hook checks G.on)
    if not M.rewardHooked and type(rawget(_G, "GetQuestReward")) == "function" and type(rawget(_G, "hooksecurefunc")) == "function" then
        M.rewardHooked = true
        hooksecurefunc("GetQuestReward", function(choice) ns.Errors.Call("gather", M.OnReward, choice) end)
    end
end)

function M.SessionEnd()
    if S.leg then FinishLeg(S.leg) S.leg = nil end
    local db = G.db
    if not db then return end
    local rf = Median(S.rf)
    if S.loginMs or rf then
        G.Add("perf:" .. (db.sess or 0), { k = "perf", ms = S.loginMs and math.floor(S.loginMs + 0.5), rf = rf and math.floor(rf * 10 + 0.5),
            n = 0 })
    end
    local e = S.earn
    local min = math.floor((S.active or 0) / 60 + 0.5)
    if e and min >= 5 and (e.q + e.v + e.d + e.m + e.g) > 0 then
        local sk = {}
        for _, id in ipairs({ 164, 165, 171, 182, 186, 197, 202, 333, 393 }) do
            if G.known and (G.known[id] or G.known["p" .. id]) then sk[#sk + 1] = id end
        end
        G.Add("earn:" .. db.sess, { k = "earn", qcu = e.q, vcu = e.v, dcu = e.d, mcu = e.m, gv = e.g, min = min, pl = Level(),
            sks = #sk > 0 and table.concat(sk, ",") or nil })
    end
end

G.On_("logout", M.SessionEnd)
G.On_("stop", function()
    WrapRefresh(false)
    ns.Events.Off("PLAYER_MONEY", MV)
    M.TickerOff()
end)

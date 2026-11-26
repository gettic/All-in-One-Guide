-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.3 game data recording (plans\data-gathering\plan.md, tos plans\data-gathering\tos.md T2-T14).
-- Records game facts while you play, ON YOUR PC ONLY, in the account module `gather` of AllinOneGuideDB: quest XP and
-- money, quest giver / turn-in spots, quest item drops, coin and sell values of what you loot, loot mix per spot,
-- professions, reputation gains, dungeon runs, flight times, step times, mob levels. The addon never sends anything
-- (no network, no addon / chat messages): the Addon Manager may read the sealed pages after the game is closed,
-- and only when the player said yes there.
-- Rules (hard):
--   * no character name, guild, account, BattleTag, gender, chat, times of day; race, realm, client language, the UTC
--     day, screen size and UI scale only once in each page header (rev 5, the user's OK 2026-11-26); no other players (NPC / object ids
--     only from Creature- / Vehicle- / GameObject- GUIDs, Co.GuidNpcId; Player- and Pet- give nothing; no unit name
--     is ever read; group size is a number only); gold, reputation and skills as gains only (GetMoney / standings are
--     read in memory for a difference and never saved); no stable player id (a fresh random id per page)
--   * a secret or nil value skips the record (tos T2); nothing is called for the player (traps in the tests)
--   * "Don't record" (setting gatherData off): no event registered, nothing new saved (tos T3a, T5)
--   * caps: G.LIVE records, then sealed into pages of G.PAGE characters; a ring of G.PAGES pages
--   ns.Gather: Start/Stop/On, Add, Seal, Pages, Live, Text, Lines, Counts, Clear, WireOk, Verify, FarmStart/FarmStop
local _, ns = ...
-- THE switch (until v0.3): false = nothing of this runs (no events, no Hub page, no notice, no save section, no
-- command). The offline scenarios turn it on for their own runs (ns.GATHER = true, then ns.Gather.Enable()).
ns.GATHER = false
local Co = ns.Compat
local G = { on = false, LIVE = 120, PAGES = 30, PAGE = 3000, POS = 3, FINE = 2, CELL = 5, NPC_AGE = 30, TIE = 2,
    PAUSE = 600, REENTRY = 900, GPH_MIN = 15, GPH_MAX = 240, LIST = 30, CLEAR_WAIT = 10, SEAL_MIN = 20 }
ns.Gather = G

-- the events while recording (dungeon events only inside an instance, PLAYER_MONEY only inside a loot window)
G.EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "QUEST_REMOVED", "LOOT_OPENED", "LOOT_CLOSED", "MERCHANT_SHOW", "TRAINER_SHOW", "CONFIRM_BINDER", "TAXIMAP_OPENED",
    "PLAYER_CONTROL_GAINED", "LOADING_SCREEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UPDATE_FACTION",
    "CHAT_MSG_COMBAT_FACTION_CHANGE", "PLAYER_LOGOUT", "QUEST_GREETING", "PLAYER_DEAD", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED" }
G.RUN_EVENTS = { "PLAYER_XP_UPDATE", "ENCOUNTER_END", "BOSS_KILL" }
-- gathering spells -> skill line (Herbalism 182, Mining 186, Skinning 393; the classic spell ids, not checked on Forever)
G.GATHER = { [2366] = 182, [2368] = 182, [3570] = 182, [11993] = 182, [2575] = 186, [2576] = 186, [3564] = 186,
    [10248] = 186, [8613] = 393, [8617] = 393, [8618] = 393, [10768] = 393 }
-- trade goods (classID 7) subclasses counted per farm spot
G.TRADE = { [5] = "cloth", [9] = "herb", [7] = "ore" }

-- ------------------------------------------------------------------ the saved table
local function Store()
    if not ns.GATHER or ns.safeMode or not ns.DB or not ns.DB.account or ns.DB.readOnly.account then return nil end
    local t = ns.DB.Module("gather", "account", 1)
    if type(t.live) ~= "table" or type(t.live.order) ~= "table" or type(t.live.recs) ~= "table" then
        if t.live ~= nil then t._bad = { live = t.live, old = t._bad } end
        t.live = { order = {}, recs = {} }
    end
    if type(t.pages) ~= "table" then
        if t.pages ~= nil then t._badPages = t.pages end
        t.pages = {}
    end
    if t.run ~= nil and type(t.run) ~= "table" then t.run = nil end
    G.db = t
    return t
end
G.Store = Store

function G.Count() return G.db and #G.db.live.order or 0 end

-- rev 6: the more kinds (Data\GatherMore.lua) hang on these points: G.On_(name, fn) adds, Fire calls them in order.
-- Points: loot(slots, npcs, objs, m, x, y), lootClosed(win), accept(q), turnin(q, xp, money), talk(event),
-- target(id, kind), spell(spell), takeTaxi(slot), taxiOpen(), dead(), combat(on), logout(), start(), stop()
G.hooks = {}
function G.On_(name, fn)
    G.hooks[name] = G.hooks[name] or {}
    table.insert(G.hooks[name], fn)
end
local function Fire(name, ...)
    local list = G.hooks[name]
    if not list then return end
    for _, fn in ipairs(list) do fn(...) end
end
G.Fire = Fire
-- bus events while recording: name -> handler(_, ...) (StepTimed here; GatherMore adds its own)
G.BUS = {}

-- ------------------------------------------------------------------ where
local function Coord(v) return math.floor(v * 10000 + 0.5) / 100 end
-- the subzone text (game text, never the player's) that goes with every spot (rev 6); nil when unknown
function G.Sub()
    local f = Co.fn.SubZone
    local s = f and f()
    if type(s) ~= "string" or Co.IsSecret(s) or s == "" then return nil end
    return (s:gsub("[%c=;|]", " "):sub(1, 40))
end
-- map, x, y (0-100) of the player now; nil when unknown or secret
function G.Where()
    local map = Co.PlayerMap()
    if not map then return nil end
    local x, y = Co.PlayerPos(map)
    if not x then return map end
    return map, Coord(x), Coord(y)
end
local function Cell(x, y, size)
    if not x then return nil end
    return math.floor(x / size) .. "," .. math.floor(y / size)
end

-- ------------------------------------------------------------------ records
-- Adds to / makes the record `key`. f = the record's wire fields when new; pos = { x, y } to remember (capped).
-- Returns the record or nil (off, no save, or the live part was full and couldn't be sealed).
function G.Add(key, f, pos)
    local db = G.db
    if not (G.on and db) then return nil end
    local live = db.live
    local r = live.recs[key]
    if not r then
        if #live.order >= G.LIVE then
            G.Seal()
            if #live.order >= G.LIVE then return nil end
        end
        r = {}
        for k, v in pairs(f) do r[k] = v end
        r.n = 0
        live.recs[key] = r
        live.order[#live.order + 1] = key
    end
    r.n = r.n + 1
    if pos and pos[1] then
        if not r.sz then r.sz = G.Sub() end
        r.pos = r.pos or {}
        if #r.pos < G.POS then r.pos[#r.pos + 1] = { pos[1], pos[2] } end
    end
    return r
end

local function Bump(r, field, by) if r then r[field] = (r[field] or 0) + (by or 1) end end
G.Bump, G.Cell = Bump, Cell

-- ------------------------------------------------------------------ talk, quests
local function Talk(startItem)
    local id, kind = Co.UnitNpcId("npc")
    G.talk = { id = id, kind = kind, item = startItem, t = Co.Now() }
end
local function Giver()
    local tk = G.talk
    if not tk or Co.Now() - tk.t > G.NPC_AGE then return {} end
    if tk.item then return { from = tk.item } end
    if tk.kind == "object" then return { obj = tk.id } end
    if tk.id then return { npc = tk.id } end
    return {}
end

local function Level() local p = Co.Player() return Co.Num(p.level) end
G.Level = Level

local function QuestSpot(kind, q)
    local f = Giver()
    f.k, f.q = kind, q
    local m, x, y = G.Where()
    f.m = m
    G.Add(table.concat({ kind, q, f.npc or "", f.obj or "", f.from or "", m or "" }, ":"), f, { x, y })
end

local function OnDetail(_, startItem)
    Talk(type(startItem) == "number" and not Co.IsSecret(startItem) and startItem > 0 and startItem or nil)
    local q, pl = Co.OfferQuestID(), Level()
    if q and pl then
        local r = G.Add("offer:" .. q, { k = "offer", q = q, pl = pl })
        if r and pl < r.pl then r.pl = pl end
    end
end

local function OnAccept(_, q)
    q = Co.Num(q)
    if not q then return end
    G.qlevel[q] = Co.QuestLevel(q) or G.qlevel[q]
    QuestSpot("accept", q)
    Fire("accept", q)
end

local function OnTurnIn(_, q, xp, money)
    q, xp, money = Co.Num(q), Co.Num(xp), Co.Num(money)
    if not q then return end
    QuestSpot("turnin", q)
    local pl, ql = Level(), G.qlevel[q]
    if xp and money and pl then
        local r = G.Add(table.concat({ "qxp", q, pl, ql or "" }, ":"), { k = "qxp", q = q, xp = xp, mo = money, pl = pl, ql = ql })
        if r then r.xp, r.mo = xp, money end
    end
    G.lastTurnIn = { q = q, t = Co.Now() }
    local run = G.db and G.db.run
    if run and not run.left and Co.InInstance() then
        if money then run.cu = (run.cu or 0) + money end
        local qs = run.qs and run.qs .. "," .. q or tostring(q)
        if #qs < 200 then run.qs = qs end
        G.Act()
    end
    Fire("turnin", q, xp, money)
    G.drops = {}   -- a quest left the log: drop counting starts again at the next drop (quest items stop dropping)
end

-- ------------------------------------------------------------------ loot (spots, drops, coin, sell values, farm)
local function ItemFacts(e, farm)
    local id = e.item
    if not id then return 0 end
    local qty = e.qty or 1
    if e.quality == 0 then Bump(farm, "gray", qty) end
    local class, sub = Co.ItemClass(id)
    if class == 7 and G.TRADE[sub] then Bump(farm, G.TRADE[sub], qty) end
    local price = G.sell[id]
    if price == nil then
        price = Co.SellPrice(id)
        if price then
            G.sell[id] = price
            if price > 0 then G.Add("sell:" .. id, { k = "sell", it = id, cu = price }) end
        end
    end
    return (price or 0) * qty
end

local function OnLoot(_, _, fromItem)
    if fromItem == true then return end          -- lockboxes, bags: no place in the world
    local slots = Co.LootSlots()
    if not slots then return end
    local m, x, y = G.Where()
    local npcs, objs, seen = {}, {}, {}
    for _, e in ipairs(slots) do
        for _, s in ipairs(e.sources) do
            local key = s[2] .. s[1]
            if not seen[key] then
                seen[key] = true
                if s[2] == "object" then objs[#objs + 1] = s[1] else npcs[#npcs + 1] = s[1] end
            end
        end
    end
    -- the node of a gathering cast in the last 3 s (skinning: the NPC)
    local pg = G.pendGather
    if pg and not pg.node and Co.Now() - pg.t <= 3 then pg.node = objs[1] and ("o" .. objs[1]) or (npcs[1] and ("n" .. npcs[1])) end
    for _, id in ipairs(objs) do
        G.Add(table.concat({ "gather", id, m or "", Cell(x, y, G.FINE) or "" }, ":"), { k = "gather", obj = id, m = m }, { x, y })
    end
    local cell = Cell(x, y, G.CELL)
    local farm
    if m and cell and #npcs > 0 then
        farm = G.Add("farm:" .. npcs[1] .. ":" .. m, { k = "farm", npc = npcs[1], m = m, c = cell })
        Bump(farm, "loot")
    end
    local value = 0
    for _, e in ipairs(slots) do value = value + ItemFacts(e, farm) end
    for _, id in ipairs(npcs) do
        G.Add("coin:" .. id, { k = "coin", npc = id })      -- the loot counter (n) of this NPC; coin comes at LOOT_CLOSED
        if m and cell then G.Add("camp:" .. id .. ":" .. m, { k = "camp", npc = id, m = m, c = cell }, { x, y }) end
    end
    -- quest item drops: per NPC and item, loots (since the first drop this session) and drops
    for _, e in ipairs(slots) do
        if e.item and e.quest then
            for _, s in ipairs(e.sources) do
                if s[2] == "npc" then
                    G.drops[s[1]] = G.drops[s[1]] or {}
                    G.drops[s[1]][e.item] = G.drops[s[1]][e.item] or "new"
                end
            end
        end
    end
    for _, id in ipairs(npcs) do
        for item, state in pairs(G.drops[id] or {}) do
            local got = false
            for _, e in ipairs(slots) do
                if e.item == item then
                    for _, s in ipairs(e.sources) do if s[1] == id and s[2] == "npc" then got = true end end
                end
            end
            local r = G.Add("drop:" .. id .. ":" .. item, { k = "drop", npc = id, it = item, loot = 0, got = 0 })
            Bump(r, "loot")
            if got then Bump(r, "got") end
            G.drops[id][item] = state == "new" and "on" or state
        end
    end
    -- coin: the money difference inside this loot window (GetMoney read in memory, never saved; tos T7)
    G.win = { npcs = npcs, money = Co.Money(), cu = 0, value = value, farm = farm }
    if G.win.money then ns.Events.On("PLAYER_MONEY", G, G.OnMoney, "gather") end
    G.lastLoot = { npc = npcs[1], t = Co.Now() }
    Fire("loot", slots, npcs, objs, m, x, y)
    G.FarmTouch(value)
    G.Act()
end

function G.OnMoney()
    local w = G.win
    if not (w and w.money) then return end
    local now = Co.Money()
    if now and now > w.money then w.cu = w.cu + (now - w.money) end
    w.money = now or w.money
end

local function OnLootClosed()
    local w = G.win
    G.win = nil
    ns.Events.Off("PLAYER_MONEY", G)                  -- tos T5: only inside the loot window
    if not w then return end
    Fire("lootClosed", w)
    if w.money then
        local now = Co.Money()
        if now and now > w.money then w.cu = w.cu + (now - w.money) end
    end
    if w.cu <= 0 then return end
    local n = #w.npcs
    if n > 0 then
        local share = math.floor(w.cu / n)
        for _, id in ipairs(w.npcs) do
            local r = G.db and G.db.live.recs["coin:" .. id]
            if r then
                r.cu = (r.cu or 0) + share
                if n > 1 then r.sh = 1 end
            end
        end
    end
    Bump(w.farm, "cu", w.cu)
    local run = G.db and G.db.run
    if run and not run.left then run.cu = (run.cu or 0) + w.cu end
    G.FarmTouch(w.cu)
end

-- ------------------------------------------------------------------ vendors, trainers, inns, flights
local function NpcSpot(kind, extra)
    local id, what = Co.UnitNpcId("npc")
    if not (id and what == "npc") then return nil end
    local m, x, y = G.Where()
    local f = { k = kind, npc = id, m = m }
    for k, v in pairs(extra or {}) do f[k] = v end
    return G.Add(kind .. ":" .. id .. ":" .. (m or ""), f, { x, y }), id
end

local function OnMerchant()
    local r = NpcSpot("merchant")
    if not r then return end
    local items = Co.MerchantItems(80)
    if not items then return end
    local rc, sup = {}, {}
    for _, it in ipairs(items) do
        local class, sub = Co.ItemClass(it.id)
        local part = it.id .. ":" .. it.price .. (it.limited and ":l" or "")
        if class == 9 then rc[#rc + 1] = part
        elseif (class == 0 and sub == 5) or class == 6 or class == 5 then sup[#sup + 1] = part end
    end
    if #rc == 0 and #sup == 0 then return end
    local v = NpcSpot("vend")
    if v then
        v.rc = #rc > 0 and table.concat(rc, ",", 1, math.min(#rc, G.LIST)) or nil
        v.sup = #sup > 0 and table.concat(sup, ",", 1, math.min(#sup, G.LIST)) or nil
    end
end

local function OnTrainer()
    local r = NpcSpot("trainer")
    if not r then return end
    local list = Co.TrainerServices(60)
    if list and #list > 0 then
        local t = NpcSpot("train")
        if t then t.sv = table.concat(list, ",") end
    end
end

local function OnBinder() NpcSpot("inn") end

-- flights: the open map's nodes by slot (the origin is state 0 = current), the slot the player clicked (hook only),
-- the landing (control back, off the taxi)
local function OnTaxiOpen()
    G.slots, G.origin = {}, nil
    for _, map in ipairs(ns.Taxi and ns.Taxi.CONTINENTS or {}) do
        for _, n in ipairs(Co.TaxiOpenNodes(map)) do
            if n.slot then G.slots[n.slot] = n.id end
            if n.state == 0 then G.origin = n.id end
        end
    end
    if G.origin then NpcSpot("fm", { fn = G.origin }) end
    Fire("taxiOpen")
end

function G.OnTakeTaxi(slot)
    if not G.on or type(slot) ~= "number" or Co.IsSecret(slot) then return end
    local to = G.slots and G.slots[slot]
    if G.origin and to and to ~= G.origin then G.flight = { fn = G.origin, tn = to, t = Co.Now() } end
    Fire("takeTaxi", slot)
end

local function OnControl()
    local fl = G.flight
    if not fl or Co.OnTaxi() then return end
    G.flight = nil
    local sec = Co.Now() - fl.t
    if sec < 20 or sec > 1800 then return end
    local r = G.Add("fly:" .. fl.fn .. ":" .. fl.tn, { k = "fly", fn = fl.fn, tn = fl.tn, sec = 0 })
    Bump(r, "sec", math.floor(sec / 5 + 0.5) * 5)
end

-- ------------------------------------------------------------------ mob levels (your own target only; tos T11)
local function OnTarget()
    local id, kind = Co.UnitNpcId("target")
    if not (id and kind == "npc") then return end
    Fire("target", id, kind)
    local lvl = Co.UnitLevelOf("target")
    local m, x, y = G.Where()
    local cell = Cell(x, y, G.CELL)
    if not (lvl and m and cell) then return end
    local r = G.Add(table.concat({ "mlvl", id, m, cell }, ":"), { k = "mlvl", npc = id, m = m, c = cell, lo = lvl, hi = lvl,
        cl = Co.Classification("target") })
    if r then
        if lvl < r.lo then r.lo = lvl end
        if lvl > r.hi then r.hi = lvl end
    end
end

-- ------------------------------------------------------------------ reputation (gains only; tos T12)
-- The chat line is never read: both events only start the in-memory difference of the standings.
local function RepDiff()
    if not G.on then return end
    local now = Co.FactionStandings()
    if not now then return end
    local base = G.rep
    G.rep = now
    if not base then return end
    local t = Co.Now()
    for id, cur in pairs(now) do
        local old = base[id]
        if old and cur ~= old then
            local gain = cur - old
            local lt, ll = G.lastTurnIn, G.lastLoot
            local r
            if lt and t - lt.t <= G.TIE then
                r = G.Add("repq:" .. lt.q .. ":" .. id, { k = "repq", q = lt.q, fa = id, gain = 0 })
            else
                local npc = Co.UnitDead("target") and (Co.UnitNpcId("target")) or nil
                if not npc and ll and ll.npc and t - ll.t <= G.TIE then npc = ll.npc end
                if npc then r = G.Add("repk:" .. npc .. ":" .. id, { k = "repk", npc = npc, fa = id, gain = 0 })
                else r = G.Add("repo:" .. id, { k = "repo", fa = id, gain = 0 }) end
            end
            Bump(r, "gain", gain)
        end
    end
end
local function OnRep() ns.Events.Debounce("gather.rep", 0.2, RepDiff, "gather") end

-- ------------------------------------------------------------------ professions (tos T9)
local function CheckSkill(p)
    if not G.on then return end
    local after
    if p.sk then after = Co.SkillRank(p.sk) else after = select(2, Co.RecipeSkill(p.sp)) end
    if type(after) ~= "number" then return end
    local up = after > p.lv and 1 or 0
    if p.sk then
        G.known[p.sk] = after
        local node = p.node
        if not node then return end
        local m, x, y = G.Where()
        local cell = Cell(x, y, G.CELL) or ""
        local f = { k = "gskill", sk = p.sk, lv = p.lv, m = m, c = cell ~= "" and cell or nil, tries = 0, ups = 0 }
        if node:sub(1, 1) == "o" then f.obj = tonumber(node:sub(2)) else f.npc = tonumber(node:sub(2)) end
        local r = G.Add(table.concat({ "gskill", node, p.sk, p.lv, m or "", cell }, ":"), f)
        Bump(r, "tries")
        Bump(r, "ups", up)
    else
        G.known["p" .. p.prof] = after
        local r = G.Add(table.concat({ "craft", p.sp, p.lv }, ":"), { k = "craft", sp = p.sp, lv = p.lv, dif = p.dif, tries = 0, ups = 0 })
        Bump(r, "tries")
        Bump(r, "ups", up)
    end
end

function G.OnSpell(unit, _, spell)
    if not G.on or unit ~= "player" then return end
    spell = Co.Num(spell)
    if not spell then return end
    Fire("spell", spell)
    if Co.InCombat() then return end
    local sk = G.GATHER[spell]
    local p
    if sk then
        local lv = G.known[sk] or Co.SkillRank(sk)
        if type(lv) ~= "number" then return end
        p = { sk = sk, lv = lv, t = Co.Now() }
        G.pendGather = p
    else
        local prof, lvl = Co.RecipeSkill(spell)
        if not prof then return end
        p = { sp = spell, prof = prof, lv = G.known["p" .. prof] or lvl, dif = Co.RecipeColor(spell) }
    end
    Co.After(1, function() ns.Errors.Call("gather", CheckSkill, p) end)
end

-- ------------------------------------------------------------------ dungeon runs (own run; group size a number only)
local function RunOn(on)
    for _, ev in ipairs(G.RUN_EVENTS) do
        if on then ns.Events.On(ev, G, G.RUN_HANDLERS[ev], "gather") else ns.Events.Off(ev, G) end
    end
end

-- active time: a gap of G.PAUSE or more counts as a pause (AFK, a long run back)
function G.Act()
    local run = G.db and G.db.run
    if not run or run.left then return end
    local now = Co.Now()
    local gap = now - (run.last or now)
    if gap >= G.PAUSE then
        run.pz = (run.pz or 0) + gap
        run.pn = (run.pn or 0) + 1
    elseif gap > 0 then
        run.sec = (run.sec or 0) + gap
    end
    run.last = now
end

function G.FinishRun()
    local db = G.db
    local run = db and db.run
    if not run then return end
    db.run = nil
    RunOn(false)
    local min = math.floor((run.sec or 0) / 60 + 0.5)
    if min < 2 then return end
    db.runs = (tonumber(db.runs) or 0) + 1
    G.Add("dun:" .. db.runs, { k = "dun", ins = run.ins, pl = run.pl, gs = run.gs, gx = run.gx, min = min, boss = run.boss,
        xp = run.xp or 0, cu = run.cu or 0, qs = run.qs, pz = run.pz and math.floor(run.pz / 60 + 0.5) or nil, pn = run.pn,
        dd = run.dd })
end

local function StartRun(ins)
    local xp, max = Co.XP()
    local gs = Co.GroupSize()
    G.db.run = { ins = ins, pl = Level(), gs = gs, gx = gs, sec = 0, last = Co.Now(), x0 = xp, m0 = max, l0 = Level(), xp = 0,
        cu = 0 }
    RunOn(true)
end

local function OnWorld()
    local out = G.out
    G.out = nil
    local db = G.db
    if not db then return end
    if Co.InInstance() then
        local ins = Co.InstanceId()
        if out then G.Add(table.concat({ "entrance", ins or "", out[1] }, ":"), { k = "entrance", ins = ins, m = out[1] }, { out[2], out[3] }) end
        local kind = Co.InstanceType()
        if not ins or (kind ~= "party" and kind ~= "raid") then return end
        local run = db.run
        if run and run.ins == ins and run.left and Co.Now() - run.left <= G.REENTRY then
            run.left, run.last = nil, Co.Now()        -- a run back (ghost) continues the same run
            RunOn(true)
        else
            if run then G.FinishRun() end
            StartRun(ins)
        end
    elseif db.run and not db.run.left then
        G.Act()
        db.run.left = Co.Now()
        RunOn(false)
        Co.After(G.REENTRY + 1, function()
            local r = G.db and G.db.run
            if r and r.left and Co.Now() - r.left >= G.REENTRY then ns.Errors.Call("gather", G.FinishRun) end
        end)
    end
end

G.RUN_HANDLERS = {
    PLAYER_XP_UPDATE = function()
        local run = G.db and G.db.run
        local xp, max = Co.XP()
        local lvl = Level()
        if not (run and xp) then return end
        if run.x0 then
            -- a level-up in between: the rest of the old level plus the new XP
            local up = lvl and run.l0 and lvl > run.l0
            local gain = up and ((run.m0 or 0) - run.x0 + xp) or (xp - run.x0)
            if gain > 0 then run.xp = (run.xp or 0) + gain end
        end
        run.x0, run.m0, run.l0 = xp, max, lvl
        G.Act()
    end,
    ENCOUNTER_END = function(_, enc, _, _, _, success)
        if Co.Num(success) == 1 then G.Boss(enc) end
    end,
    BOSS_KILL = function(_, enc) G.Boss(enc) end,
}

function G.Boss(enc)
    enc = Co.Num(enc)
    local run = G.db and G.db.run
    if not (enc and run) or run.left then return end
    G.Act()
    local part = enc .. ":" .. math.floor((run.sec or 0) / 60 + 0.5)
    if run.boss then
        for p in run.boss:gmatch("[^,]+") do if p:match("^(%d+)") == tostring(enc) then return end end
        if #run.boss < 200 then run.boss = run.boss .. "," .. part end
    else
        run.boss = part
    end
end

-- ------------------------------------------------------------------ step times (Data\Pace.lua) and farm routes
local function OnStepTimed(_, guide, step, seconds)
    seconds = Co.Num(seconds)
    if type(step) == "number" then step = tostring(step) end
    if type(guide) ~= "string" or type(step) ~= "string" or not seconds then return end
    local r = G.Add("step:" .. guide .. ":" .. step, { k = "step", pk = guide, s = step, t = 0 })
    Bump(r, "t", math.floor(seconds / 10 + 0.5) * 10)
end

-- For the farm planner (later): gold per hour on a farm route, a rounded rate with no times (tos T7)
function G.FarmStart(route)
    if not G.on or type(route) ~= "string" then return false end
    G.farm = { rt = route, earn = 0, sec = 0, last = Co.Now() }
    return true
end
function G.FarmTouch(copper)
    local f = G.farm
    if not f then return end
    local now = Co.Now()
    local gap = now - f.last
    if gap < 300 then f.sec = f.sec + gap end          -- pauses of 5 min or more are cut out
    f.last = now
    f.earn = f.earn + (copper or 0)
end
function G.FarmStop()
    local f = G.farm
    G.farm = nil
    if not (f and G.db) then return nil end
    G.FarmTouch(0)
    local min = math.min(G.GPH_MAX, math.floor(f.sec / 300 + 0.5) * 5)
    if min < G.GPH_MIN then return nil end
    local gph = math.floor(f.earn / 10000 / (min / 60) * 2 + 0.5) / 2
    G.db.farms = (tonumber(G.db.farms) or 0) + 1
    return G.Add("gph:" .. f.rt .. ":" .. G.db.farms, { k = "gph", rt = f.rt, gph = gph, min = min })
end

-- ------------------------------------------------------------------ handlers, start / stop
local HANDLERS = {
    QUEST_DETAIL = OnDetail,
    QUEST_PROGRESS = function() Talk() Fire("talk", "QUEST_PROGRESS") end,
    QUEST_COMPLETE = function() Talk() Fire("talk", "QUEST_COMPLETE") end,
    GOSSIP_SHOW = function() Talk() Fire("talk", "GOSSIP_SHOW") end,
    QUEST_GREETING = function() Talk() Fire("talk", "QUEST_GREETING") end,
    -- in a dungeon run: deaths, the biggest group (both events stay on all the time for rev 6's kinds)
    PLAYER_DEAD = function()
        local run = G.db and G.db.run
        if run and not run.left then run.dd = (run.dd or 0) + 1 end
        Fire("dead")
    end,
    PLAYER_REGEN_DISABLED = function()
        local run, gs = G.db and G.db.run, Co.GroupSize()
        if run and not run.left then
            G.Act()
            if gs and gs > (run.gx or 0) then run.gx = gs end
        end
        Fire("combat", true)
    end,
    PLAYER_REGEN_ENABLED = function() Fire("combat", false) end,
    QUEST_ACCEPTED = OnAccept,
    QUEST_TURNED_IN = OnTurnIn,
    QUEST_REMOVED = function() G.drops = {} end,
    LOOT_OPENED = OnLoot,
    LOOT_CLOSED = OnLootClosed,
    MERCHANT_SHOW = OnMerchant,
    TRAINER_SHOW = OnTrainer,
    CONFIRM_BINDER = OnBinder,
    TAXIMAP_OPENED = OnTaxiOpen,
    PLAYER_CONTROL_GAINED = OnControl,
    LOADING_SCREEN_ENABLED = function()
        if Co.InInstance() then G.out = nil return end
        local m, x, y = G.Where()
        G.out = x and { m, x, y } or nil
    end,
    PLAYER_ENTERING_WORLD = OnWorld,
    PLAYER_TARGET_CHANGED = OnTarget,
    UPDATE_FACTION = OnRep,
    CHAT_MSG_COMBAT_FACTION_CHANGE = OnRep,
    -- logout / reload: seal only a worthwhile batch (G.SEAL_MIN), so reloads don't fill the ring with tiny pages;
    -- a smaller live part simply carries on next time
    PLAYER_LOGOUT = function()
        Fire("logout")
        if G.Count() >= G.SEAL_MIN then G.Seal() end
    end,
}
G.HANDLERS = HANDLERS

-- UNIT_SPELLCAST_SUCCEEDED on its own frame, for the player only (tos T9: RegisterUnitEvent)
local spellFrame
local function SpellEvents(on)
    if on and not spellFrame then
        spellFrame = CreateFrame("Frame")
        spellFrame:SetScript("OnEvent", function(_, _, ...) ns.Errors.Call("gather", G.OnSpell, ...) end)
        G.spellFrame = spellFrame
    end
    if not spellFrame then return end
    if on then
        if spellFrame.RegisterUnitEvent then spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end
    else
        spellFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

function G.On() return ns.Settings.Get("gatherData") == true end

function G.Start()
    if G.on or not G.On() or not Store() then return false end
    G.on = true
    G.talk, G.drops, G.sell, G.qlevel, G.known = nil, {}, {}, {}, {}
    for _, ev in ipairs(G.EVENTS) do ns.Events.On(ev, G, HANDLERS[ev], "gather") end
    G.BUS.StepTimed = G.BUS.StepTimed or OnStepTimed
    for name, fn in pairs(G.BUS) do ns.Bus.On(name, G.BUS, fn, "gather") end   -- own owner: the switch listener stays
    SpellEvents(true)
    -- tos T4: hooked only if it exists, never called; once (a hook can't be removed: it checks G.on)
    if not G.hooked and type(rawget(_G, "TakeTaxiNode")) == "function" and type(rawget(_G, "hooksecurefunc")) == "function" then
        G.hooked = true
        hooksecurefunc("TakeTaxiNode", function(slot) ns.Errors.Call("gather", G.OnTakeTaxi, slot) end)
    end
    -- in-memory baselines (never saved): faction standings, the levels of quests already in the log
    G.rep = Co.FactionStandings()
    for i = 1, math.min(Co.NumQuestEntries(), 60) do
        local q, header = Co.QuestAt(i)
        if q and not header and q > 0 then G.qlevel[q] = Co.QuestLevel(q) end
    end
    -- a dungeon run saved before a /reload carries on; one from another session (the clock went back) ends
    local run = G.db.run
    if run then
        if (run.last or 0) > Co.Now() then
            run.last = Co.Now()
            G.FinishRun()
        elseif not run.left and Co.InInstance() then
            RunOn(true)
        elseif not run.left then
            run.left = Co.Now()
        end
    end
    Fire("start")
    return true
end

function G.Stop()
    G.on = false
    for _, ev in ipairs(G.EVENTS) do ns.Events.Off(ev, G) end
    ns.Events.Off("PLAYER_MONEY", G)
    RunOn(false)
    for name in pairs(G.BUS) do ns.Bus.Off(name, G.BUS) end
    Fire("stop")
    SpellEvents(false)
    G.talk, G.win, G.rep, G.flight, G.pendGather, G.farm = nil, nil, nil, nil, nil, nil
end

-- Events this file has on the event hub (the self-check and the tests: 0 while off).
function G.Listening()
    local n = 0
    for _, list in pairs(ns.Events.listeners) do
        for _, l in ipairs(list) do if l.owner == G and not l.removed then n = n + 1 end end
    end
    if spellFrame and spellFrame.IsEventRegistered and spellFrame:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED") then n = n + 1 end
    return n
end

-- ------------------------------------------------------------------ pages (what the Addon Manager may read)
local WIRE_HEAD = "^AOGD1 rid=[%l%d]+;h=1;"
G.WIRE = WIRE_HEAD .. "[%w %.,:_/%+%(%)'!%?%-%%=;]+ AOGD1 ck=%x%x%x%x%x%x%x%x$"

local function Median(list, i)
    local t = {}
    for _, p in ipairs(list) do if type(p) == "table" and type(p[i]) == "number" then t[#t + 1] = p[i] end end
    if #t == 0 then return nil end
    table.sort(t)
    local mid = math.floor((#t + 1) / 2)
    if #t % 2 == 0 then return math.floor((t[mid] + t[mid + 1]) * 50 + 0.5) / 100 end
    return t[mid]
end

-- One live record as an "AOGD1 k=...;..." line (nil for a broken one).
function G.Line(r)
    if type(r) ~= "table" or type(r.k) ~= "string" then return nil end
    local f = {}
    for _, k in ipairs(ns.Serializer.kinds.D1) do
        local v = r[k]
        if v ~= nil and k ~= "rid" and k ~= "h" and k ~= "ck" and (type(v) == "number" or type(v) == "string") then f[k] = v end
    end
    -- rev 6: every spot rounded down to whole map percent (coarse squares)
    if type(r.pos) == "table" then
        local x, y = Median(r.pos, 1), Median(r.pos, 2)
        f.x, f.y = x and math.floor(x), y and math.floor(y)
    end
    local ok, line = pcall(ns.Serializer.Build, "D1", f)
    return ok and line or nil
end

local function RandomId()
    local s = {}
    for i = 1, 8 do
        local n = math.random(0, 35)
        s[i] = n < 10 and string.char(48 + n) or string.char(87 + n)
    end
    return table.concat(s)
end

local function Header(cnt)
    local p = Co.Player()
    local version, build = Co.Build()
    local fac = p.faction == "Alliance" and "A" or (p.faction == "Horde" and "H" or nil)
    local function Plain(v) return type(v) == "string" and not Co.IsSecret(v) and v ~= "" and v or nil end
    -- rev 5 (the user's OK, 2026-11-26): race, realm, client language, the UTC day (rev 6: no screen size, no UI scale).
    -- Never the character name, account, BattleTag or guild.
    local realm = Co.fn.RealmName and Plain(Co.fn.RealmName()) or nil
    return ns.Serializer.Build("D1", { rid = RandomId(), h = 1, v = ns.version, b = version .. "." .. build, fac = fac,
        cls = Plain(p.class), race = Plain(p.race), realm = realm, loc = Plain(Co.Locale()), day = Co.UTCDay(), cnt = cnt })
end

local function Finish(lines)
    local core = Header(#lines) .. " " .. table.concat(lines, " ")
    return core .. " " .. ns.Serializer.Build("D1", { ck = ns.Format.Adler32(core) })
end

-- The live records as pages (each at most G.PAGE characters), without touching the save.
function G.Build(live)
    live = live or (G.db and G.db.live)
    if not live then return {} end
    local pages, cur, len = {}, {}, 0
    for _, key in ipairs(live.order) do
        local line = G.Line(live.recs[key])
        if line and #line < G.PAGE - 200 then
            if #cur > 0 and len + #line + 1 > G.PAGE - 200 then
                pages[#pages + 1] = Finish(cur)
                cur, len = {}, 0
            end
            cur[#cur + 1] = line
            len = len + #line + 1
        end
    end
    if #cur > 0 then pages[#pages + 1] = Finish(cur) end
    return pages
end

-- Seals the live records into pages (the ring keeps the newest G.PAGES) and starts an empty live part.
function G.Seal()
    local db = G.db
    if not db or #db.live.order == 0 then return 0 end
    local pages = G.Build(db.live)
    for _, p in ipairs(pages) do db.pages[#db.pages + 1] = p end
    while #db.pages > G.PAGES do table.remove(db.pages, 1) end
    db.live = { order = {}, recs = {} }
    return #pages
end

function G.Verify(s)
    if type(s) ~= "string" then return false end
    local core, ck = s:match("^(.*) AOGD1 ck=(%x+)$")
    return core ~= nil and ns.Format.Adler32(core) == ck
end
function G.WireOk(s)
    return type(s) == "string" and #s <= G.PAGE and s:find(G.WIRE) ~= nil and G.Verify(s)
end

-- The sealed pages (strings only, a copy).
function G.Pages()
    local db = G.db or Store()
    local out = {}
    for _, s in ipairs(db and db.pages or {}) do if type(s) == "string" then out[#out + 1] = s end end
    return out
end

-- Everything as it would be read: the sealed pages, then the live part as pages (not saved as pages yet).
function G.Text()
    local all = G.Pages()
    for _, p in ipairs(G.Build()) do all[#all + 1] = p end
    return table.concat(all, "\n")
end

-- Counts per kind over the live part and the sealed pages: { kind = n }, total.
function G.Counts()
    local c, total = {}, 0
    local db = G.db or Store()
    if not db then return c, 0 end
    for _, key in ipairs(db.live.order) do
        local r = db.live.recs[key]
        if type(r) == "table" and r.k then c[r.k] = (c[r.k] or 0) + 1 total = total + 1 end
    end
    for _, s in ipairs(db.pages) do
        if type(s) == "string" then
            for k in s:gmatch("AOGD1 k=(%a+)") do c[k] = (c[k] or 0) + 1 total = total + 1 end
        end
    end
    return c, total
end

-- "Delete recorded data": the first call asks (returns false), a second within G.CLEAR_WAIT seconds deletes.
function G.Clear()
    local now = Co.Now()
    if not (G.clearAsked and now - G.clearAsked <= G.CLEAR_WAIT) then
        G.clearAsked = now
        return false
    end
    G.clearAsked = nil
    local db = G.db or Store()
    if db then
        db.live, db.pages, db.run = { order = {}, recs = {} }, {}, nil
        RunOn(false)
    end
    return true
end

-- ------------------------------------------------------------------ switch, setting, login, notice, self-check
-- Turns the recording part of the addon on (only while ns.GATHER is true): the Hub page, /aog data, the one-time
-- notice (tos T3b / T14, through ns.Print = the coloured addon prefix; it names every kind of data) and the start a
-- little later (outside the login time). Runs at login; the offline scenarios call it after setting ns.GATHER.
function G.Enable()
    if not ns.GATHER then return false end
    if not G.enabled then
        G.enabled = true
        ns.Slash.Add("data", function() if ns.HubData then ns.HubData.Open() end end, "HELP_DATA")
        if ns.HubData then ns.HubData.Register() end
    end
    local db = Store()
    if not db then return false end
    if G.On() and not db.noticed then
        db.noticed = true
        ns.Print(ns.L.GATHER_NOTICE)
        ns.Print(ns.L.GATHER_NOTICE_WHAT)
        ns.Print(ns.L.GATHER_NOTICE_ALSO)
    end
    if G.On() then Co.After(3, function() ns.Errors.Call("gather", G.Start) end) end
    return true
end

ns.Bus.On("SettingsChanged", G, function(_, key)
    if key ~= "gatherData" or not G.enabled then return end
    if G.On() then G.Start() else G.Stop() end
end, "gather")

ns.Bus.On("Login", G, function() if ns.GATHER then G.Enable() end end, "gather", 92)

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "gather", fn = function(h)
    h.Count()
    local n = G.Listening()
    if not G.on and n > 0 then h.Problem(("gather: %d events while off"):format(n)) end
    if G.on and n < #G.EVENTS + 1 then h.Problem(("gather: %d of %d events"):format(n, #G.EVENTS + 1)) end
    if not ns.GATHER then
        h.Info("gather: switched off until v0.3")
        return
    end
    -- a scratch page (never the saved one): builds, fits, passes the line check, holds no name / realm
    local scratch = { order = { "a" }, recs = { a = { k = "qxp", q = 783, xp = 85, mo = 0, pl = 1, ql = 1, n = 1 } } }
    local page = G.Build(scratch)[1]
    if not (page and G.WireOk(page)) then h.Problem("gather: a test page fails the line check") end
    local name = (Co.CharacterKey() or ""):match("^[^%-]+")
    if page and name and #name >= 3 and page:find(name, 1, true) then h.Problem("gather: a page holds the character name") end
    local db = G.db
    if db and #db.pages > G.PAGES then h.Problem(("gather: %d pages, cap %d"):format(#db.pages, G.PAGES)) end
    if db and #db.live.order > G.LIVE then h.Problem(("gather: %d live records, cap %d"):format(#db.live.order, G.LIVE)) end
    local _, total = G.Counts()
    h.Info(("gather: %s, %d records, %d pages"):format(G.on and "on" or "off", total, db and #db.pages or 0))
end }
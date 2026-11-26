-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Quest giver check (plans\quest-giver-check\plan.md, tos plans\quest-giver-check\tos.md). Display only: when the
-- player opens an NPC's quest list (gossip or quest greeting), a route accept step at that NPC whose quest isn't
-- in the list is marked "not offered yet" and passed over (with its follow-ups, Guide:Held). It comes back when
-- the reason may have changed (level up, a hand-in), but behind the current step only when the NPC is near
-- (least travel); otherwise when a later visit to that NPC offers it.
-- Reads only the public lists (Co.NpcQuestLists) and the NPC-id field of the "npc" unit's GUID; never picks,
-- accepts, declines or closes anything, never opens a gossip option. Any secret / odd value = unknown.
--   ns.QuestGiver.On() / Marked(q) / Mark / Release / ShowAgain / Judge / Read(kind) / Report(q) / Problem()
--   saved: char module "questgiver" { marks = { [quest] = { npc, lvl, at, waiting } } }
local _, ns = ...
local Co, GS, P = ns.Compat, ns.GameState, ns.Packs
local FEATURE = "questgiver"

local QG = { any = false, NEAR = 200, AHEAD = 10, CAP = 200, LOOK = 15, DELAY = 0.1, visit = 0, open = false,
    mem = {}, stats = { reads = 0, judged = 0, unknown = 0, marks = 0, cleared = 0, back = 0 } }
ns.QuestGiver = QG

function QG.On()
    return ns.Settings.Get("questGiverCheck") == true and ns.Feature.IsOn(FEATURE) and not ns.safeMode
end

-- ------------------------------------------------------------------ the marks (saved per character)
-- The marks table; create = make the saved module. Read-only saves / safe mode: this session only.
local function Marks(create)
    local root = ns.DB.char
    if not root or type(root.modules) ~= "table" or ns.DB.readOnly.char or ns.safeMode then return QG.mem end
    local m = root.modules.questgiver
    if type(m) ~= "table" then
        if not create then return nil end
        m = ns.DB.Module("questgiver", "char", 1)
    end
    if type(m.marks) ~= "table" then
        if not create then return nil end
        m.marks = {}
    end
    return m.marks
end
QG.Marks = Marks

-- QG.any = at least one mark that holds a quest back (the guide's quick way out).
local function Recount()
    local m = Marks(false)
    QG.any = false
    for q, e in pairs(m or {}) do
        if type(q) == "number" and type(e) == "table" and not e.waiting then QG.any = true return end
    end
end
QG.Recount = Recount

function QG.Marked(q)
    if not QG.any or not QG.On() then return false end
    local m = Marks(false)
    local e = m and m[q]
    return type(e) == "table" and not e.waiting and not GS.InLog(q)
end

local function NoticeId(q) return "qg:" .. q end
local function Level() return ns.Engine.ctx and ns.Engine.ctx.level end

local function Guides()
    local out = {}
    for _, g in pairs(ns.Engine.guides or {}) do out[#out + 1] = g:Top() end
    return out
end

-- The step text of quest q's accept step (for the notice), from the first guide that has one.
local function AcceptStep(q)
    for _, top in ipairs(Guides()) do
        local list = top:AcceptsOf()[q]
        local s = list and top:Step(list[1])
        if s then return s, top end
    end
end

function QG.Report(q)
    local m = Marks(false)
    local e = m and m[q]
    local HR = ns.HubReport
    if not (HR and HR.Prefill) then return false end
    local note = ns.U.Fill(ns.L.QG_REPORT_NOTE, { quest = q, npc = e and e.npc or "?", level = e and e.lvl or "?" })
    return HR.Prefill({ about = "missing", note = note })
end

local function PushNotice(q)
    local Nt = ns.Notice
    if not Nt then return end
    local s, top = AcceptStep(q)
    local name = ns.Names.Quest(q, (s and top and ns.U.Plain(top:Text(s))) or ("#" .. q))
    local L = ns.L
    Nt.Push({ id = NoticeId(q), kind = "notoffered", source = "questgiver", priority = 30, icon = "notice.tip",
        text = ns.U.Fill(L.QG_NOTICE, { quest = name }),
        button = { text = L.QG_REPORT, fn = function() QG.Report(q) end },
        menu = { { text = L.QG_SHOW_AGAIN, fn = function() ns.Errors.Call(FEATURE, QG.ShowAgain, q) end } } })
end

-- Drops the oldest marks over the cap.
local function Trim(m)
    local n, list = 0, {}
    for q, e in pairs(m) do
        n = n + 1
        list[#list + 1] = { q = q, at = type(e) == "table" and tonumber(e.at) or 0 }
    end
    if n <= QG.CAP then return end
    table.sort(list, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.q < b.q end)
    for k = 1, n - QG.CAP do m[list[k].q] = nil end
end

function QG.Mark(q, npc)
    local m = Marks(true)
    if not m then return false end
    m[q] = { npc = npc, lvl = Level(), at = Co.ServerTime() or 0 }
    Trim(m)
    QG.stats.marks = QG.stats.marks + 1
    QG.any = true
    PushNotice(q)
    ns.Errors.Debug("quest %d: not offered by %d", q, npc)
    return true
end

-- near(step) for a guide: the NPC is within NEAR yards of the player or of one of the next AHEAD stops.
local function NearFn(top)
    return function(s)
        if not (s.map and s.x and s.y) then return false end
        local d = ns.Geo.PlayerDistance(s.map, s.x, s.y)
        if d and d <= QG.NEAR then return true end
        local seen, i, n = 0, top.pos, top:Count()
        while i <= n and seen < QG.AHEAD do
            local t = top:Step(i)
            if t and t.map and t.x and t.y and top:IsStop(t, i) then
                seen = seen + 1
                local dd = ns.Geo.Distance(s.map, s.x, s.y, t.map, t.x, t.y)
                if dd and dd <= QG.NEAR then return true end
            end
            i = i + 1
        end
        return false
    end
end
local function Always() return true end

-- Takes a mark away. how: "offered" (a visit offers it: back as a goal wherever it is), "show" (the player
-- asked), "release" (level / hand-in: back only when near, else it waits quietly for a visit), "gone" (in the
-- log or done). Returns true when something changed.
local function Clear(q, how)
    local m = Marks(false)
    local e = m and m[q]
    if type(e) ~= "table" then return false end
    if how == "release" and e.waiting then return false end
    if ns.Notice then ns.Notice.Remove(NoticeId(q)) end
    QG.stats.cleared = QG.stats.cleared + 1
    if how == "gone" then
        m[q] = nil
        -- taken anyway: its objective / turn-in steps that were held behind the current step come back
        if GS.InLog(q) then
            for _, top in ipairs(Guides()) do
                top.backQuests = top.backQuests or {}
                top.backQuests[q] = true
            end
        end
        return true
    end
    e.waiting = true   -- not held any more while it comes back
    local back = false
    for _, top in ipairs(Guides()) do
        if top:BringBack(q, how == "release" and NearFn(top) or Always) then back = true end
    end
    if back then QG.stats.back = QG.stats.back + 1 end
    if back or how ~= "release" then m[q] = nil end
    return true
end

local function Changed()
    Recount()
    if ns.Engine.RefreshAll then ns.Engine.RefreshAll() end
    if ns.NpcHelper and ns.NpcHelper.Redraw then ns.NpcHelper.Redraw() end
end

function QG.ShowAgain(q)
    if Clear(q, "show") then
        Changed()
        local g = ns.Engine.Focused and ns.Engine.Focused()
        if g then ns.Bus.Fire("StepChanged", g) end
        return true
    end
    return false
end

-- Every held mark (or those `want(q, e)` picks) may be ready again.
function QG.Release(want)
    local m = Marks(false)
    if not m then return false end
    local list = {}
    for q, e in pairs(m) do
        if type(e) == "table" and not e.waiting and (not want or want(q, e)) then list[#list + 1] = q end
    end
    local changed = false
    for _, q in ipairs(list) do
        if Clear(q, "release") then changed = true end
    end
    if changed then Changed() end
    return changed
end

-- ------------------------------------------------------------------ judging a visit
-- The accept steps the player does at this NPC now: from the current step's group on, past travel steps before
-- the NPC's first step, until the route leaves the NPC (a stop at another NPC). A pending hand-in at the NPC
-- stops the list (it may unlock what follows; the window opens again after it).
function QG.Candidates(top, npc)
    local out = {}
    local i, n = top:GroupStart(top.pos), top:Count()
    local last, seen = i + QG.LOOK, false
    local cur = top:Step(top.pos)
    local group = cur and cur.anyOrder
    while i <= n and i <= last do
        local s = top:Step(i)
        if s and top:IsStop(s, i) and not s.whileUntil and not s.flags.optional then
            if s.npc == npc then
                seen = true
                if s.type == "turnin" then break end
                if s.type == "accept" then out[#out + 1] = s end
            elseif not ((not seen and ns.StepTypes.Get(s.type).travel) or (group and s.anyOrder == group)) then
                break
            end
        end
        i = i + 1
    end
    return out
end

-- The quest's level: the step's own `level=`, else the quest data (Data\QuestLevels.lua, cmangos QuestLevel);
-- nil = unknown (then no grey guard).
function QG.QuestLevel(s)
    if type(s.level) == "number" then return s.level end
    local t = ns.QuestLevels
    local v = type(t) == "table" and t[s.quest]
    return type(v) == "number" and v or nil
end

-- May this accept step be judged from a list? (Our data says the NPC should offer it right now.)
function QG.Judgeable(top, s, kind)
    local q = s.quest
    if type(q) ~= "number" or s.type ~= "accept" or s.item then return false end
    if s.from == "item" then return false end
    if (s.from == "object") ~= (kind == "object") then return false end
    if not top:Applicable(s) then return false end
    if GS.InLog(q) or GS.IsDone(q) then return false end
    for _, p in P.Each(s.pre) do
        if not GS.IsDone(p) then return false end
    end
    local lv, BQ, ql = Level(), ns.BagQuests, QG.QuestLevel(s)
    if ql and type(lv) == "number" and BQ and BQ.GreyLevel and ql <= BQ.GreyLevel(lv) then
        return false   -- grey for the player: the client may leave it out of the list
    end
    return true
end

-- One clean read of the open NPC: avail / active sets, gossip option count, quest rows in all.
function QG.Judge(npc, kind, avail, active, opts, n)
    QG.stats.judged = QG.stats.judged + 1
    if n == 0 and opts > 0 then
        QG.stats.unknown = QG.stats.unknown + 1   -- quests may sit behind a gossip option: never opened
        return false
    end
    local changed = false
    local m = Marks(false)
    if m then
        for q in pairs(avail) do
            if m[q] and Clear(q, "offered") then changed = true end
        end
    end
    for _, top in ipairs(Guides()) do
        for _, s in ipairs(QG.Candidates(top, npc)) do
            local q = s.quest
            if not avail[q] and not active[q] and QG.Judgeable(top, s, kind) and not QG.Marked(q) then
                if QG.Mark(q, npc) then changed = true end
            end
        end
    end
    if changed then Changed() end
    return changed
end

local function Same(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

-- GOSSIP_SHOW / QUEST_GREETING: read now and once more a moment later; judged only when both reads agree.
function QG.Read(kind)
    QG.open = true
    QG.visit = QG.visit + 1
    QG.npc, QG.npcKind = nil, nil
    if not QG.On() then return end
    QG.stats.reads = QG.stats.reads + 1
    local npc, what = Co.UnitNpcId("npc")
    if not npc then QG.stats.unknown = QG.stats.unknown + 1 return end
    QG.npc, QG.npcKind = npc, what
    local a1, c1, o1, n1 = Co.NpcQuestLists(kind)
    if not a1 then QG.stats.unknown = QG.stats.unknown + 1 return end
    local v = QG.visit
    Co.After(QG.DELAY, function()
        ns.Errors.Call(FEATURE, function()
            if QG.visit ~= v or not QG.open or not QG.On() then return end
            local a2, c2, o2, n2 = Co.NpcQuestLists(kind)
            if not a2 or n1 ~= n2 or o1 ~= o2 or not Same(a1, a2) or not Same(c1, c2) then
                QG.stats.unknown = QG.stats.unknown + 1
                return
            end
            QG.Judge(npc, what, a2, c2, o2, n2)
        end)
    end)
end

function QG.Closed()
    QG.open = false
    QG.visit = QG.visit + 1
end

-- ------------------------------------------------------------------ coming back
local function OnLevel() QG.Release() end

local function OnTurnedIn(_, id)
    if type(id) ~= "number" then return end
    local npcs = {}
    if QG.open and QG.npc then npcs[QG.npc] = true end
    local pre = {}
    for _, top in ipairs(Guides()) do
        local e = top:QuestSteps()[id]
        for _, i in ipairs(e and e.turnin or {}) do
            local s = top:Step(i)
            if s and s.npc then npcs[s.npc] = true end
        end
        for q, list in pairs(top:PreMap()) do
            for _, p in ipairs(list) do if p == id then pre[q] = true end end
        end
    end
    QG.Release(function(q, e) return pre[q] or npcs[e.npc] == true end)
end

local function OnQuests()
    local m = Marks(false)
    if not m then return end
    local changed = false
    for q in pairs(m) do
        if type(q) ~= "number" then
            m[q] = nil
            changed = true
        elseif GS.InLog(q) and Clear(q, "gone") then
            changed = true
        end
    end
    if changed then Recount() end
end

-- Login: drop marks of quests already done (or broken entries), then count.
local function Tidy()
    local m = Marks(false)
    for q, e in pairs(m or {}) do
        if type(q) ~= "number" or type(e) ~= "table" or GS.IsDone(q) then m[q] = nil end
    end
    Recount()
end
QG.Tidy = Tidy

-- ------------------------------------------------------------------ self-check
function QG.Problem()
    local m = Marks(false)
    local n = 0
    for q, e in pairs(m or {}) do
        n = n + 1
        if type(q) ~= "number" or type(e) ~= "table" or type(e.npc) ~= "number" then return "a mark has the wrong shape" end
    end
    if n > QG.CAP then return ("%d marks (cap %d)"):format(n, QG.CAP) end
    return nil
end

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "questgiver", fn = function(h)
    h.Count()
    local p = QG.Problem()
    if p then h.Problem("questgiver: " .. p) end
    local st = QG.stats
    h.Info(("questgiver %s, reads %d, marks %d, back %d, unknown %d"):format(QG.On() and "on" or "off",
        st.reads, st.marks, st.back, st.unknown))
end }

-- ------------------------------------------------------------------ wiring
ns.Bus.On("Login", QG, function()
    Tidy()
    local Ev = ns.Events
    Ev.On("GOSSIP_SHOW", QG, function() QG.Read("gossip") end, FEATURE)
    Ev.On("QUEST_GREETING", QG, function() QG.Read("greeting") end, FEATURE)
    Ev.On("GOSSIP_CLOSED", QG, QG.Closed, FEATURE)
    Ev.On("QUEST_FINISHED", QG, QG.Closed, FEATURE)
end, FEATURE, 45)
ns.Bus.On("Ready", QG, Tidy, FEATURE, 40)   -- the quest log is read: done quests can be told apart now
ns.Bus.On("LevelChanged", QG, OnLevel, FEATURE, 40)
ns.Bus.On("QuestTurnedIn", QG, OnTurnedIn, FEATURE, 40)
ns.Bus.On("QuestsChanged", QG, OnQuests, FEATURE, 40)
ns.Bus.On("SettingsChanged", QG, function(_, key)
    if key == "questGiverCheck" then Changed() end
end, FEATURE, 40)

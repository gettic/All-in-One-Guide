-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 quest items in the bags: read-only advice for items that start a quest or belong to one.
--   * reads only: C_Container.GetContainerItemQuestInfo / GetContainerItemID / GetContainerNumSlots
--     (plain numbers, AllowedWhenUntainted, from our own code) and C_QuestLog.IsQuestFlaggedCompleted.
--     It never uses, moves, deletes or banks an item and never accepts a quest (tos: plans\quest-items).
--   * after login: all bags 0..GS.LAST_BAG once, one bag per frame, out of combat; then only the bags
--     that changed (GameState's BagsChanged, after BAG_UPDATE_DELAYED); combat waits until it ends
--   * ONE advice per item: "now" (do it now), "later" (keep for later, too high), "bank" (one-time item),
--     "delete" (safe to delete: done, or grey and it drops again), "keep" (unknown: keep it)
--   * the notice line: a new quest-starting item once per item and character ("This starts a quest:
--     right-click it" + where to hand it in and whether it's worth it); after login / level-up one line
--     when an item's advice changed. The Hub page "Quest items" lists them all.
--   * data: our pack rows (accept / turnin steps: place, level, minLevel, xp, which route) and
--     ns.QuestItems (Data\QuestItems.lua, made by the data agent; read if present):
--       [itemID] = { q = quest id or a list, again = true|false (can be got again) }  (the full rows are a local audit file)
--     (`quest` / `repeatable` are read too). No entry = "unknown, keep it" unless the quest is done.
--   ns.BagQuests.Advise(entry) -> advice, .List() (sorted advice), .Text(advice), .Scan(bags), .StartScan()
--   bus: BagQuestsChanged
local _, ns = ...
local Co, GS = ns.Compat, ns.GameState
local BQ = { bags = {}, items = {}, advice = {}, ready = false, scanning = false, waiting = nil, session = {},
    stats = { scans = 0, slots = 0, notices = 0 }, info = {}, infoFocus = nil }
ns.BagQuests = BQ

BQ.ORDER = { now = 1, bank = 2, later = 3, keep = 4, delete = 5 }
BQ.COLOR = { now = "accent", bank = "icon.accept", later = "upcoming", keep = "text", delete = "text.dim" }
BQ.LABEL = { now = "QI_NOW", bank = "QI_BANK", later = "QI_LATER", keep = "QI_KEEP", delete = "QI_DELETE" }
BQ.RED = 5   -- a quest this many levels above you is red: too hard for now

local function L() return ns.L end

-- ------------------------------------------------------------------ saved (char module "questitems")
-- { seen = { [itemID] = true } (the new-item notice was shown), said = { [itemID] = advice kind } }
-- written only when there is something to remember; safe mode / read-only saves use this session only.
local function Saved()
    if ns.safeMode or not ns.DB.char or ns.DB.readOnly.char then return BQ.session end
    local m = ns.DB.Module("questitems", "char", 1)
    return m or BQ.session
end
local function Field(m, k)
    if type(m[k]) ~= "table" then m[k] = {} end
    return m[k]
end

-- ------------------------------------------------------------------ data
function BQ.Data(itemID)
    local t = ns.QuestItems
    if type(t) ~= "table" then return nil end
    local d = t[itemID]
    if d == nil and type(t.items) == "table" then d = t.items[itemID] end
    return type(d) == "table" and d or nil
end

-- Is the quest in the player's quest log? (GameState's C_QuestLog snapshot, else C_QuestLog.IsOnQuest)
function BQ.InLog(q)
    if type(q) ~= "number" then return false end
    return GS.InLog(q) or Co.OnQuest(q)
end

-- The quest an item is for, from the data (q = id or a list: the first one not done yet; else the first).
function BQ.DataQuest(itemID)
    local d = BQ.Data(itemID)
    if not d then return nil end
    local q = d.q or d.quest
    if type(q) == "number" then return q end
    if type(q) ~= "table" then return nil end
    for _, id in ipairs(q) do
        if type(id) == "number" and BQ.InLog(id) then return id end
    end
    for _, id in ipairs(q) do
        if type(id) == "number" and not GS.IsDone(id) then return id end
    end
    return type(q[1]) == "number" and q[1] or nil
end

-- true / false / nil (unknown): can the item be got again?
function BQ.Again(itemID)
    local d = BQ.Data(itemID)
    if not d then return nil end
    local v = d.repeatable
    if v == nil then v = d.again end
    if v == nil then return nil end
    return v == true
end

local function FocusRoute()
    local g = ns.Engine and ns.Engine.Focused and ns.Engine.Focused()
    return g and g.route or nil
end

-- What our packs know about a quest: { accept = step, acceptRoute, turnin = step, route (the turn-in's), onRoute
-- (in the focused guide's route), level, minLevel, xp }. Only the rows of accept / turnin steps for this
-- quest are decoded. Cached per quest until the focused route changes.
function BQ.QuestInfo(q)
    local focus = FocusRoute()
    if BQ.infoFocus ~= focus then BQ.info, BQ.infoFocus = {}, focus end
    local hit = BQ.info[q]
    if hit ~= nil then return hit or nil end
    local info
    local P, Fm = ns.Packs, ns.Format
    local function Scan(r)
        for _, row in ipairs(r.rows or {}) do
            if type(row) == "string" then
                local typ, qs = row:match("^[^|]*|(%a+)|(%d+)|")
                if qs and tonumber(qs) == q and (typ == "accept" or typ == "turnin") then
                    local s = Fm.DecodeRow(row)
                    if s then
                        info = info or { quest = q }
                        if typ == "accept" and not info.accept then info.accept, info.acceptRoute = s, r end
                        if typ == "turnin" and not info.turnin then info.turnin, info.route = s, r end
                        if r == focus then info.onRoute = true end
                    end
                end
            end
        end
    end
    if focus and focus.rows then Scan(focus) end
    for _, pid in ipairs(P.List()) do
        local pack = P.packs[pid]
        for _, rid in ipairs(pack and pack.routeOrder or {}) do
            local r = pack.routes[rid]
            if r ~= focus and not (info and info.turnin and info.accept) then Scan(r) end
        end
    end
    if info then
        local a, t = info.accept or {}, info.turnin or {}
        info.level = a.level or t.level
        info.minLevel = a.minLevel or t.minLevel
        info.xp = t.xp or a.xp
        info.route = info.route or focus
    end
    BQ.info[q] = info or false
    return info
end

-- The highest level that is grey (no XP worth having) for a player level (Classic's grey rule).
function BQ.GreyLevel(pl)
    if pl <= 5 then return 0 end
    if pl <= 39 then return pl - math.floor(pl / 10) - 5 end
    if pl <= 59 then return pl - math.floor(pl / 5) - 1 end
    return pl - 9
end

local function PlayerLevel()
    local lv = GS.level or Co.Player().level
    return type(lv) == "number" and lv or 1
end

-- ------------------------------------------------------------------ advice
-- entry = { item, quest, active, questItem, starter }. Returns { kind, item, quest, reason (locale key),
-- level, place, xp, route, starter }.
function BQ.Advise(e)
    local a = { item = e.item, quest = e.quest, starter = e.starter }
    local q = e.quest
    local again = BQ.Again(e.item)
    if q and GS.IsDone(q) then
        a.kind, a.reason = "delete", "QI_WHY_DONE"
        return a
    end
    if not q then
        a.kind, a.reason = "keep", "QI_WHY_UNKNOWN"
        return a
    end
    -- in the log: the bag API's isActive (starters), or the quest log for items known from ns.QuestItems
    if e.active or BQ.InLog(q) then
        a.kind, a.reason = "keep", "QI_WHY_INLOG"
        return a
    end
    local info = BQ.QuestInfo(q)
    local pl = PlayerLevel()
    if info then
        a.level, a.xp = info.level or info.minLevel, info.xp
        local t = info.turnin or info.accept
        if t and t.map and t.x and t.y then a.place = { map = t.map, x = t.x, y = t.y } end
        local r = info.route
        if r then a.route = ns.Locale.code == "daDK" and r.da or r.title end
    else
        local d = BQ.Data(e.item)
        if d then a.level = tonumber(d.level) or tonumber(d.minLevel) end
    end
    local minLevel = (info and info.minLevel) or (BQ.Data(e.item) or {}).minLevel
    local tooHigh = (type(minLevel) == "number" and pl < minLevel) or (a.level and a.level >= pl + BQ.RED)
    if tooHigh then
        if again == false then
            a.kind, a.reason = "bank", "QI_WHY_BANK_LATER"
        else
            a.kind, a.reason = "later", "QI_WHY_LATER"
        end
        return a
    end
    if a.level and a.level <= BQ.GreyLevel(pl) then
        if again == true then a.kind, a.reason = "delete", "QI_WHY_GREY"
        elseif again == false then a.kind, a.reason = "bank", "QI_WHY_BANK"
        else a.kind, a.reason = "keep", "QI_WHY_GREYKEEP" end
        return a
    end
    local near = info and (info.onRoute or (a.place and a.place.map == Co.PlayerMap()))
    if near then
        a.kind, a.reason = "now", "QI_WHY_NOW"
        return a
    end
    if again == false then
        a.kind, a.reason = "bank", "QI_WHY_BANK"
    else
        a.kind, a.reason = "keep", info and "QI_WHY_OFFROUTE" or "QI_WHY_UNKNOWN"
    end
    return a
end

local function ItemName(id) return Co.ItemName(id) or ("#" .. id) end

local function Place(p)
    if not p then return nil end
    return ns.U.Fill(L().QI_PLACE, { zone = Co.MapName(p.map) or ("#" .. p.map),
        x = ("%.1f"):format(p.x * 100), y = ("%.1f"):format(p.y * 100) })   -- decoded steps hold 0-1
end

-- The advice's reason as one sentence ("Hand it in at Elwynn Forest 48.9, 41.6 (450 XP)").
function BQ.Why(a)
    local quest = a.quest and ns.Names and ns.Names.Quest(a.quest) or L().QI_A_QUEST
    local fill = { quest = quest, level = a.level or "?", place = Place(a.place) or L().QI_UNKNOWN_PLACE,
        route = a.route or L().QI_THIS_GUIDE, xp = a.xp or "?" }
    local text = ns.U.Fill(L()[a.reason] or a.reason, fill)
    if a.kind == "now" and a.xp then text = text .. " " .. ns.U.Fill(L().QI_XP, fill) end
    return text
end

-- "Do it now: hand it in at ..."
function BQ.Text(a) return L()[BQ.LABEL[a.kind]] .. ": " .. BQ.Why(a) end

-- All items with advice, best first (now, bank, later, keep, delete; then by name).
function BQ.List()
    local out = {}
    for _, a in pairs(BQ.advice) do out[#out + 1] = a end
    table.sort(out, function(x, y)
        local ox, oy = BQ.ORDER[x.kind], BQ.ORDER[y.kind]
        if ox ~= oy then return ox < oy end
        return x.item < y.item
    end)
    return out
end

-- ------------------------------------------------------------------ the notice line
local function OpenHub()
    ns.Notice.Remove("questitems")
    if ns.Hub then ns.Hub.Open("questitems") end
end

local function Notify(text)
    BQ.stats.notices = BQ.stats.notices + 1
    ns.Notice.Push({ id = "questitems", kind = "questitem", source = "questitems", priority = 20,
        icon = "badge.accept", text = text, button = { text = L().QI_SHOW, fn = OpenHub } })
end
BQ.Notify = Notify

-- Works out every item's advice; tells the player once about new quest-starting items (why = "bags")
-- and, after login or a level-up, about items whose advice changed.
function BQ.Evaluate(why)
    local m = Saved()
    local seen, said = Field(m, "seen"), Field(m, "said")
    local fresh, changed = {}, {}
    BQ.advice = {}
    for id, e in pairs(BQ.items) do
        local a = BQ.Advise(e)
        BQ.advice[id] = a
        if e.starter and not seen[id] then
            fresh[#fresh + 1] = a
            seen[id] = true
        elseif said[id] ~= a.kind then
            changed[#changed + 1] = a
        end
        said[id] = a.kind
    end
    for id in pairs(said) do if not BQ.items[id] then said[id] = nil end end
    local function Best(list)
        table.sort(list, function(x, y) return BQ.ORDER[x.kind] < BQ.ORDER[y.kind] end)
        return list[1]
    end
    if #fresh == 1 and #changed == 0 then
        local a = fresh[1]
        Notify(L().QI_NOTICE_NEW .. ". " .. BQ.Text(a))
    elseif #fresh + #changed == 1 then
        local a = Best(changed)
        Notify(ItemName(a.item) .. ": " .. BQ.Text(a))
    elseif #fresh + #changed > 1 then
        local list = {}
        for _, a in ipairs(fresh) do list[#list + 1] = a end
        for _, a in ipairs(changed) do list[#list + 1] = a end
        local a = Best(list)
        Notify(ns.U.Fill(L().QI_NOTICE_MANY, { n = #list }) .. " " .. ItemName(a.item) .. ": " .. BQ.Text(a))
    end
    if not next(BQ.items) then ns.Notice.Remove("questitems") end
    BQ.lastWhy = why
    ns.Bus.Fire("BagQuestsChanged")
end

-- ------------------------------------------------------------------ scanning
-- Reads one bag into BQ.bags[bag] (item id -> entry); only quest-related items are kept.
function BQ.ScanBag(bag)
    local found = {}
    local n = Co.BagSlots(bag)
    BQ.stats.slots = BQ.stats.slots + n
    for slot = 1, n do
        local id = Co.BagItemID(bag, slot)
        if id then
            local q, active, isQ = Co.BagQuestInfo(bag, slot)
            if q or isQ or BQ.Data(id) then
                local e = found[id] or { item = id }
                e.quest = e.quest or q or BQ.DataQuest(id)
                e.active = e.active or active
                e.questItem = e.questItem or isQ
                e.starter = e.starter or (q ~= nil and not active)
                found[id] = e
            end
        end
    end
    BQ.bags[bag] = found
end

local function Merge()
    local items = {}
    for _, found in pairs(BQ.bags) do
        for id, e in pairs(found) do
            local o = items[id]
            if o then
                o.active, o.questItem, o.starter = o.active or e.active, o.questItem or e.questItem, o.starter or e.starter
                o.quest = o.quest or e.quest
            else
                items[id] = { item = id, quest = e.quest, active = e.active, questItem = e.questItem, starter = e.starter }
            end
        end
    end
    BQ.items = items
end

-- Scans the given bags now (a set of bag ids) and evaluates. Out of combat only.
function BQ.Scan(bags, why)
    if Co.InCombat() then
        BQ.waiting = BQ.waiting or {}
        for b in pairs(bags) do BQ.waiting[b] = true end
        return false
    end
    for b in pairs(bags) do BQ.ScanBag(b) end
    Merge()
    BQ.stats.scans = BQ.stats.scans + 1
    BQ.Evaluate(why or "bags")
    return true
end

-- The first scan after login: one bag per frame, out of combat.
function BQ.StartScan()
    if BQ.scanning or BQ.ready then return false end
    if not ns.Compat.has.BagQuestInfo then return false end
    if Co.InCombat() then
        BQ.waitLogin = true
        return false
    end
    BQ.scanning = true
    local bag = 0
    local function Next()
        if Co.InCombat() then
            BQ.scanning, BQ.waitLogin = false, true
            return
        end
        BQ.ScanBag(bag)
        bag = bag + 1
        if bag <= GS.LAST_BAG then return Co.After(0, function() ns.Errors.Call("questitems", Next) end) end
        BQ.scanning, BQ.ready = false, true
        Merge()
        BQ.stats.scans = BQ.stats.scans + 1
        BQ.Evaluate("login")
        if BQ.waiting then
            local w = BQ.waiting
            BQ.waiting = nil
            BQ.Scan(w, "bags")
        end
    end
    Next()
    return true
end

ns.Bus.On("Ready", BQ, function() ns.Errors.Call("questitems", BQ.StartScan) end, "questitems", 90)
ns.Bus.On("BagsChanged", BQ, function(_, bags)
    if not ns.Compat.has.BagQuestInfo then return end
    if not BQ.ready then
        -- the login scan reads them anyway; a bag it already read is read again after it
        BQ.waiting = BQ.waiting or {}
        for b in pairs(bags) do BQ.waiting[b] = true end
        return
    end
    ns.Errors.Call("questitems", BQ.Scan, bags, "bags")
end, "questitems")
ns.Bus.On("CombatEnded", BQ, function()
    local why = BQ.againWhy
    BQ.againWhy = nil
    if BQ.waitLogin then
        BQ.waitLogin = false
        ns.Errors.Call("questitems", BQ.StartScan)
    elseif BQ.ready and BQ.waiting then
        local w = BQ.waiting
        BQ.waiting = nil
        ns.Errors.Call("questitems", BQ.Scan, w, why or "bags")
    elseif BQ.ready and why then
        ns.Errors.Call("questitems", BQ.Evaluate, why)
    end
end, "questitems")
-- Re-works the advice (level-up, quest turned in / accepted); in combat it waits for CombatEnded
-- (most level-ups happen in combat). "level" wins over "quest" for the waiting reason.
local function Again(why)
    if not BQ.ready then return end
    if Co.InCombat() then
        if BQ.againWhy ~= "level" then BQ.againWhy = why end
        return
    end
    ns.Errors.Call("questitems", BQ.Evaluate, why)
end
ns.Bus.On("LevelChanged", BQ, function() Again("level") end, "questitems")
ns.Bus.On("PackLoaded", BQ, function() BQ.info = {} end, "questitems")
ns.Bus.On("QuestTurnedIn", BQ, function() Again("quest") end, "questitems")
-- a quest of an item in the bags came into / left the log: its advice changes (keep / delete)
ns.Bus.On("QuestsChanged", BQ, function(_, changed)
    if type(changed) ~= "table" then return end
    for _, e in pairs(BQ.items) do
        if e.quest and changed[e.quest] ~= nil then
            Again("quest")
            return
        end
    end
end, "questitems")

-- In-game self-test (/aog selftest): the API is there, and the numbers of the last scan.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "questitems", fn = function(h)
    h.Count()
    if not ns.Compat.has.BagQuestInfo then
        h.Skip("questitems", "(no GetContainerItemQuestInfo)")
        return
    end
    local n = 0
    for _ in pairs(BQ.items) do n = n + 1 end
    for _, a in pairs(BQ.advice) do
        h.Count()
        if not BQ.LABEL[a.kind] or not L()[a.reason] then h.Problem("QITEM", "advice", tostring(a.kind) .. " " .. tostring(a.reason)) end
    end
    h.Info(("questitems %d, scans %d, slots %d, notices %d, data %s"):format(n, BQ.stats.scans, BQ.stats.slots,
        BQ.stats.notices, type(ns.QuestItems) == "table" and "yes" or "none"))
end }

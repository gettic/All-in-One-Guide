-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- All game reads go through here (the offline tests swap the game, not our code).
-- Every API comes from ns.ApiList (see plans\api-16001.md for where each was checked). Each one is
-- looked up once when this file loads; a missing one switches its feature off quietly (Compat.Init),
-- and the reads below then return nil. Values that can be secret are checked with issecretvalue and
-- treated as "unknown" (nil), never compared. Only the player's own position is read, and only through
-- C_Map; when that gives nothing there is no other way around it.
local _, ns = ...
local G = _G
local Co = { fn = {}, has = {}, missingByFeature = {} }
ns.Compat = Co

-- Looks up "C_QuestLog.GetInfo" without touching anything else (rawget on the top level).
local function Resolve(path)
    local v = G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = rawget(v, part)
        if v == nil then return nil end
    end
    return v
end
Co.Resolve = Resolve

local function KindOk(v, kind)
    if kind == "function" then return type(v) == "function" end
    if kind == "table" then return type(v) == "table" end
    return v ~= nil
end
Co.KindOk = KindOk

for _, e in ipairs(ns.ApiList) do
    local v = Resolve(e.path)
    local ok = KindOk(v, e.kind)
    Co.has[e.id] = ok
    if ok then Co.fn[e.id] = v end
end
local F = Co.fn

-- Sets the feature states from what is missing (called at ADDON_LOADED).
function Co.Init()
    Co.missingByFeature = {}
    for _, e in ipairs(ns.ApiList) do
        if e.feature and not Co.has[e.id] then
            local list = Co.missingByFeature[e.feature] or {}
            list[#list + 1] = e.id
            Co.missingByFeature[e.feature] = list
        end
    end
    for _, e in ipairs(ns.ApiList) do
        local feat = e.feature
        if feat then
            local missing = Co.missingByFeature[feat]
            if missing then
                ns.Feature.Set(feat, "api", "missing " .. table.concat(missing, ","))
            elseif ns.Feature.Get(feat) == "on" then
                ns.Feature.Set(feat, "on")
            end
        end
    end
end

local function Secret(v)
    local f = F.issecretvalue
    return f ~= nil and f(v) == true
end
Co.IsSecret = Secret
-- A number / a true flag from the game, never compared or converted while secret (beta.3 robustness: a
-- secret value counts as unknown = nil / false, so tonumber or "<" on it can't error)
function Co.Num(v)
    if Secret(v) then return nil end
    return type(v) == "number" and v or (type(v) == "string" and tonumber(v)) or nil
end
function Co.IsTrue(v)
    if Secret(v) then return false end
    return v == true
end

-- ------------------------------------------------------------------ time, combat, client
function Co.Now() return F.GetTime() end
function Co.Ms() return F.debugprofilestop() end
function Co.After(seconds, fn) F.TimerAfter(seconds, fn) end
function Co.Ticker(seconds, fn) return F.TimerTicker(seconds, fn) end

function Co.InCombat()
    local f = F.InCombatLockdown
    return f ~= nil and f() == true
end

function Co.Build()
    local f = F.GetBuildInfo
    if not f then return "?", "?", 0 end
    local version, build, _, interface = f()
    return tostring(version), tostring(build), tonumber(interface) or 0
end

function Co.IsForever()
    local id, camelot = Resolve("WOW_PROJECT_ID"), Resolve("WOW_PROJECT_CAMELOT")
    return id ~= nil and id == camelot
end

function Co.Locale()
    local f = F.GetLocale
    return f and f() or "enUS"
end

-- v0.3 page header (rev 5): the UTC day "2026-11-26" (rev 6: no screen size or UI scale).
function Co.UTCDay()
    local f = F.Date
    local d = f and f("!%Y-%m-%d")
    return type(d) == "string" and d:match("^%d%d%d%d%-%d%d%-%d%d$") and d or nil
end

function Co.IsLoggedIn()
    local f = F.IsLoggedIn
    return f ~= nil and f() == true
end

-- "16001 1.60.1.70959 forever enUS": no names, safe to share.
function Co.ClientLine()
    local version, build, interface = Co.Build()
    return ("%d %s.%s %s %s"):format(interface, version, build, Co.IsForever() and "forever" or "other", Co.Locale())
end

-- ------------------------------------------------------------------ add-ons
function Co.AddOnMeta(name, field)
    local f = F.AddOnMetadata
    return f and f(name, field) or nil
end
function Co.IsAddOnLoaded(name)
    local f = F.IsAddOnLoaded
    return f ~= nil and (f(name)) == true
end
function Co.LoadAddOn(name)
    local f = F.LoadAddOn
    if not f then return false, "MISSING_API" end
    return f(name)
end

-- Our own memory in KB (self-test only: UpdateAddOnMemoryUsage walks every addon, so never on a timer).
function Co.MemoryKB(name)
    local up, get = F.UpdateMemory, F.AddOnMemory
    if not (up and get) then return nil end
    up()
    local kb = get(name)
    if Secret(kb) or type(kb) ~= "number" then return nil end
    return kb
end

-- ------------------------------------------------------------------ the player
local player = {}
-- Returns one reused table { level, class, race, faction, sex }; values are nil when unknown.
function Co.Player()
    player.level = F.UnitLevel and F.UnitLevel("player") or nil
    player.class = F.UnitClass and select(2, F.UnitClass("player")) or nil
    player.race = F.UnitRace and select(2, F.UnitRace("player")) or nil
    player.faction = F.UnitFactionGroup and (F.UnitFactionGroup("player")) or nil
    player.sex = F.UnitSex and F.UnitSex("player") or nil
    return player
end

-- Only for the character key in the saves. Never shown (UI code uses ns.DisplayName).
function Co.CharacterKey()
    local name = F.UnitName and (F.UnitName("player")) or nil
    local realm = F.RealmName and F.RealmName() or nil
    if type(name) ~= "string" or Secret(name) or name == "" then return nil end
    return name .. "-" .. tostring(realm or "?")
end

function Co.OnTaxi()
    local f = F.UnitOnTaxi
    return f ~= nil and f("player") == true
end

-- Smart arrow: is the player in an indoor area? true / false, nil when unknown (API missing or secret).
-- Only a hint next to our room outlines, never used alone.
function Co.Indoors()
    local f = F.IsIndoors
    if not f then return nil end
    local v = f()
    if Secret(v) or type(v) ~= "boolean" then return nil end
    return v
end

-- 3D viewer (UI\ModelView.lua): does the account show the classic (SD) character models? true / false, nil
-- when unknown (API missing, secret, or the game has no SD / HD switch). Read on every viewer update; a change
-- reloads the model.
function Co.SDModels()
    local toggle, sd = F.SDHDToggle, F.SDEnabled
    if not (toggle and sd) then return nil end
    local on = toggle()
    if Secret(on) or on ~= true then return nil end
    local v = sd()
    if Secret(v) or type(v) ~= "boolean" then return nil end
    return v
end

-- XP and XP to the next level (nil, nil when unknown).
function Co.XP()
    local a, b = F.UnitXP, F.UnitXPMax
    if not (a and b) then return nil end
    local xp, max = a("player"), b("player")
    if Secret(xp) or Secret(max) or type(xp) ~= "number" or type(max) ~= "number" then return nil end
    return xp, max
end

function Co.Dead()
    local f = F.DeadOrGhost
    if not f then return false end
    local v = f("player")
    if Secret(v) then return false end
    return v == true
end

-- Released and running as a ghost (v0.2 M3: the corpse arrow).
function Co.Ghost()
    local f = F.UnitIsGhost
    if not f then return false end
    local v = f("player")
    if Secret(v) then return false end
    return v == true
end

-- The corpse on a map, as 0-1 fractions (nil when it isn't on that map).
function Co.CorpsePosition(uiMapID)
    local f = F.CorpsePos
    if not f or type(uiMapID) ~= "number" then return nil end
    local ok, pos = pcall(f, uiMapID)
    if not ok or pos == nil or Secret(pos) then return nil end
    local x, y
    if type(pos) == "table" and pos.GetXY then x, y = pos:GetXY() elseif type(pos) == "table" then x, y = pos.x, pos.y end
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return x, y
end

-- true inside a dungeon / raid / battleground (no map position there).
function Co.InInstance()
    local f = F.InInstance
    if not f then return false end
    local v = f()
    if Secret(v) then return false end
    return v == true
end

-- v0.2 M5 (report evidence) / M6 (recorder, tos R3): the NPC / object id of a unit, only from a
-- Creature- / Vehicle- / GameObject- GUID that isn't secret; Player- and Pet- give nil. The GUID itself is
-- never kept. Returns id, kind ("npc" / "object") or nil.
local NPC_KINDS = { Creature = "npc", Vehicle = "npc", GameObject = "object" }
function Co.UnitNpcId(unit)
    local f = F.UnitGUID
    if not f then return nil end
    return Co.GuidNpcId(f(unit or "target"))
end

-- The same rule for a GUID we were handed (loot sources, M6 recorder): id, kind or nil.
function Co.GuidNpcId(g)
    if g == nil or Secret(g) or type(g) ~= "string" then return nil end
    local kind = g:match("^(%a+)%-")
    if not NPC_KINDS[kind] then return nil end
    -- [unitType]-0-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]
    local n, id = 0, nil
    for part in g:gmatch("[^%-]+") do
        n = n + 1
        if n == 6 then id = tonumber(part) break end
    end
    if not id or id <= 0 then return nil end
    return id, NPC_KINDS[kind]
end

-- Quest giver check (Engine\QuestGiver.lua; read only, never picks anything): the quest lists of the open NPC
-- window. kind "gossip" (C_GossipInfo) or "greeting" (the quest greeting's index reads). Returns
-- available = { [questID] = true }, active = { [questID] = true }, options (gossip option count, 0 for a
-- greeting), quests (how many quest rows in all); or nil when anything is missing, secret, odd, or the counts
-- don't match the lists (= unknown: nothing is judged from it).
local function QuestIdOk(q) return not Secret(q) and type(q) == "number" and q > 0 end
function Co.NpcQuestLists(kind)
    local avail, active, n = {}, {}, 0
    if kind == "gossip" then
        local fa, fc, fna, fnc, fo = F.GossipAvail, F.GossipActive, F.GossipNumAvail, F.GossipNumActive, F.GossipOptions
        if not (fa and fc and fna and fnc) then return nil end
        local la, lc, na, nc = fa(), fc(), fna(), fnc()
        if Secret(la) or Secret(lc) or type(la) ~= "table" or type(lc) ~= "table" then return nil end
        na, nc = Co.Num(na), Co.Num(nc)
        if na ~= #la or nc ~= #lc then return nil end
        for _, pair in ipairs({ { la, avail }, { lc, active } }) do
            for _, info in ipairs(pair[1]) do
                local q = type(info) == "table" and info.questID
                if not QuestIdOk(q) then return nil end
                pair[2][q] = true
                n = n + 1
            end
        end
        local opts = 0
        if fo then
            local lo = fo()
            if Secret(lo) or type(lo) ~= "table" then return nil end
            opts = #lo
        end
        return avail, active, opts, n
    elseif kind == "greeting" then
        local fna, fnc, fi, fa = F.GreetNumAvail, F.GreetNumActive, F.AvailQuestInfo, F.ActiveQuestID
        if not (fna and fnc and fi and fa) then return nil end
        local na, nc = Co.Num(fna()), Co.Num(fnc())
        if not na or not nc or na < 0 or nc < 0 or na > 40 or nc > 40 then return nil end
        for i = 1, na do
            local q = select(5, fi(i))
            if not QuestIdOk(q) then return nil end
            avail[q] = true
            n = n + 1
        end
        for i = 1, nc do
            local q = fa(i)
            if not QuestIdOk(q) then return nil end
            active[q] = true
            n = n + 1
        end
        return avail, active, 0, n
    end
    return nil
end

-- v0.2 M6 (dev recorder, /aog where): the open loot window. Returns a list of
-- { item = itemID or nil, sources = { { id, kind }, ... } } (sources only from Creature / Vehicle /
-- GameObject GUIDs, see GuidNpcId), or nil when the loot API is missing.
function Co.LootSources()
    local num, src, link = F.LootNum, F.LootSource, F.LootLink
    if not (num and src) then return nil end
    local n = num()
    if Secret(n) or type(n) ~= "number" then return nil end
    local out = {}
    for slot = 1, math.min(n, 20) do
        local e = { sources = {} }
        local l = link and link(slot)
        if type(l) == "string" and not Secret(l) then e.item = tonumber(l:match("item:(%d+)")) end
        local res = { pcall(src, slot) }
        if res[1] then
            for i = 2, #res, 2 do
                local id, kind = Co.GuidNpcId(res[i])
                if id then e.sources[#e.sources + 1] = { id, kind } end
            end
        end
        out[#out + 1] = e
    end
    return out
end

-- The instance map id (GetInstanceInfo's 8th return, read in Blizzard_FrameXML\InstanceDifficulty.lua),
-- or nil outside / when unknown.
function Co.InstanceId()
    local f = F.InstanceInfo
    if not f or not Co.InInstance() then return nil end
    local id = select(8, f())
    if Secret(id) or type(id) ~= "number" or id <= 0 then return nil end
    return id
end

-- The quest selected in the quest log (C_QuestLog.GetSelectedQuest), or nil.
function Co.SelectedQuest()
    local f = F.QuestSelected
    if not f then return nil end
    local id = f()
    if Secret(id) or type(id) ~= "number" or id <= 0 then return nil end
    return id
end

-- ------------------------------------------------------------------ v0.3 game data recording (Data\Gather.lua)
-- All read only. A secret or odd value is "unknown" (nil): the record is skipped, never worked around (tos T2).
local function Plain(v) if Secret(v) then return nil end return v end

-- The open loot window, slot by slot: { item, qty, quality, quest (isQuestItem), coin, sources = { { id, kind } } }
-- (sources only from Creature / Vehicle / GameObject GUIDs, Co.GuidNpcId); nil when the loot API is missing.
function Co.LootSlots()
    local list = Co.LootSources()
    if not list then return nil end
    local info = F.LootSlotInfo
    for slot, e in ipairs(list) do
        if info then
            local ok, _, _, qty, _, quality, _, quest, qid, _, coin = pcall(info, slot)
            if ok then
                e.qty = Co.Num(qty)
                e.quality = Co.Num(quality)
                e.quest = Co.IsTrue(quest)
                e.coin = Co.IsTrue(coin)
                qid = Co.Num(qid)
                e.starts = qid and qid > 0 and qid or nil      -- the quest this item starts (LootFrame.lua:228)
            end
        end
    end
    return list
end

-- v0.3 rev 6: the quests the open NPC window offers (available only): { { q = id or nil, lvl = level or nil,
-- t = title when there is no id } }, at most `cap`; nil when the API is missing or secret.
function Co.OfferedQuests(kind, cap)
    local out = {}
    cap = cap or 20
    if kind == "gossip" then
        local f = F.GossipAvail
        if not f then return nil end
        local list = f()
        if Secret(list) or type(list) ~= "table" then return nil end
        for _, info in ipairs(list) do
            if #out >= cap then break end
            if type(info) == "table" then
                local q, lvl, t = Co.Num(info.questID), Co.Num(info.questLevel), Plain(info.title)
                if q and q > 0 then out[#out + 1] = { q = q, lvl = lvl and lvl > 0 and lvl or nil }
                elseif type(t) == "string" and t ~= "" then out[#out + 1] = { t = t:sub(1, 60), lvl = lvl } end
            end
        end
        return out
    elseif kind == "greeting" then
        local fn, fi, ft = F.GreetNumAvail, F.AvailQuestInfo, F.AvailTitle
        if not fn then return nil end
        local n = Co.Num(fn())
        if not n or n < 0 or n > 40 then return nil end
        for i = 1, math.min(n, cap) do
            local q = fi and Co.Num(select(5, fi(i)))
            if q and q > 0 then out[#out + 1] = { q = q }
            else
                local t = ft and Plain(ft(i))
                if type(t) == "string" and t ~= "" then out[#out + 1] = { t = t:sub(1, 60) } end
            end
        end
        return out
    end
    return nil
end

-- Rested XP as a % of this level's bar, rounded to 5 (0 = none, capped at 150); nil when unknown.
function Co.RestedPct()
    local f = F.XPRested
    local _, max = Co.XP()
    if not (f and max and max > 0) then return nil end
    local r = f()
    if Secret(r) then return nil end
    r = type(r) == "number" and r or 0
    return math.min(150, math.floor(r / max * 20 + 0.5) * 5)
end

-- Can the player attack this unit (true / false; false when unknown).
function Co.CanAttack(unit)
    local f = F.CanAttack
    if not f then return false end
    local v = f("player", unit)
    if Secret(v) then return false end
    return v == true
end

-- The player's money (copper) right now, only for a difference inside one loot window (never saved).
function Co.Money()
    local f = F.Money
    if not f then return nil end
    return Co.Num(f())
end

-- classID, subClassID of an item (nil when unknown).
function Co.ItemClass(itemID)
    local f = F.ItemInstant
    if not f or type(itemID) ~= "number" then return nil end
    local ok, id, _, _, _, _, class, sub = pcall(f, itemID)
    if not ok or Co.Num(id) == nil then return nil end
    return Co.Num(class), Co.Num(sub)
end

-- An item's vendor sell price (copper), nil while it isn't cached / unknown.
function Co.SellPrice(itemID)
    local f = F.ItemInfo
    if not f or type(itemID) ~= "number" then return nil end
    local ok, name, _, _, _, _, _, _, _, _, _, price = pcall(f, itemID)
    if not ok or name == nil then return nil end
    return Co.Num(price)
end

-- A unit's level (-1 = skull) and classification code ("n", "e", "r", "re", "b"), nil when unknown.
local CLASSIF = { normal = "n", trivial = "n", minus = "n", elite = "e", rare = "r", rareelite = "re", worldboss = "b" }
function Co.UnitLevelOf(unit)
    local f = F.UnitLevel
    if not f then return nil end
    return Co.Num(f(unit))
end
function Co.Classification(unit)
    local f = F.UnitClassif
    if not f then return nil end
    local v = Plain(f(unit))
    return type(v) == "string" and CLASSIF[v] or nil
end
function Co.UnitDead(unit)
    local f = F.UnitIsDead
    return f ~= nil and Co.IsTrue(f(unit))
end

-- How many are in the group (1 when alone). A count only: no names, classes or GUIDs.
function Co.GroupSize()
    local f = F.GroupMembers
    if not f then return nil end
    local n = Co.Num(f())
    if not n then return nil end
    return math.max(1, n)
end

-- { [factionID] = currentStanding } for the factions the list shows (in memory only; never saved).
function Co.FactionStandings()
    local num, get = F.RepNum, F.RepByIndex
    if not (num and get) then return nil end
    local ok, n = pcall(num)
    n = ok and Co.Num(n)
    if not n then return nil end
    local out = {}
    for i = 1, math.min(n, 300) do
        local ok2, d = pcall(get, i)
        if ok2 and type(d) == "table" and not Secret(d) then
            local id, cur = Co.Num(d.factionID), Co.Num(d.currentStanding)
            if id and id > 0 and cur and (d.isHeader ~= true or d.isHeaderWithRep == true) then out[id] = cur end
        end
    end
    return out
end

-- A recipe spell's profession id and skill level (nil when it isn't a recipe / unknown), and its colour
-- (relativeDifficulty 0 optimal .. 3 trivial, nil when unknown).
function Co.RecipeSkill(spellID)
    local f = F.RecipeProf
    if not f or type(spellID) ~= "number" then return nil end
    local ok, info = pcall(f, spellID)
    if not ok or type(info) ~= "table" or Secret(info) then return nil end
    local prof, lvl = Co.Num(info.professionID), Co.Num(info.skillLevel)
    if not prof or prof <= 0 or not lvl or lvl <= 0 then return nil end
    return prof, lvl
end
function Co.RecipeColor(spellID)
    local f = F.RecipeInfo
    if not f or type(spellID) ~= "number" then return nil end
    local ok, info = pcall(f, spellID)
    if not ok or type(info) ~= "table" or Secret(info) then return nil end
    return Co.Num(info.relativeDifficulty)
end

-- The open trainer's services as "icon:level:rank:cost" (the name is never read; this client gives no spell
-- id). Capped at `cap`.
function Co.TrainerServices(cap)
    local num, info, skill, cost = F.TrainerNum, F.TrainerInfo, F.TrainerSkill, F.TrainerCost
    if not (num and info) then return nil end
    local ok, n = pcall(num)
    n = ok and Co.Num(n)
    if not n then return nil end
    local out = {}
    for i = 1, math.min(n, cap or 60) do
        local ok2, _, kind, icon, lvl = pcall(info, i)
        if ok2 and Plain(kind) ~= "header" then
            local rank = skill and select(3, pcall(skill, i)) or nil
            local c = cost and select(2, pcall(cost, i)) or nil
            out[#out + 1] = ("%d:%d:%d:%d"):format(Co.Num(icon) or 0, Co.Num(lvl) or 0, Co.Num(rank) or 0, Co.Num(c) or 0)
        end
    end
    return out
end

-- The open merchant's items: { { id, price, limited } } (names never read), capped at `cap`.
function Co.MerchantItems(cap)
    local num, idf, info = F.MerchantNum, F.MerchantItemID, F.MerchantInfo
    if not (num and idf) then return nil end
    local ok, n = pcall(num)
    n = ok and Co.Num(n)
    if not n then return nil end
    local out = {}
    for i = 1, math.min(n, cap or 80) do
        local ok2, id = pcall(idf, i)
        id = ok2 and Co.Num(id)
        if id and id > 0 then
            local price, avail
            if info then
                local ok3, _, _, p, _, a = pcall(info, i)
                if ok3 then price, avail = Co.Num(p), Co.Num(a) end
            end
            out[#out + 1] = { id = id, price = price or 0, limited = avail ~= nil and avail >= 0 }
        end
    end
    return out
end

-- The quest of the open quest dialog (GetQuestID), or nil.
function Co.OfferQuestID()
    local f = F.QuestID
    if not f then return nil end
    local q = Co.Num(f())
    if not q or q <= 0 then return nil end
    return q
end

-- A quest's level from the log (nil when it isn't in the log / unknown).
function Co.QuestLevel(questID)
    local idx, get = F.QuestLogIndex, F.QuestInfo
    if not (idx and get) or type(questID) ~= "number" then return nil end
    local i = Co.Num(idx(questID))
    if not i then return nil end
    local info = get(i)
    if type(info) ~= "table" then return nil end
    local lv = Co.Num(info.level)
    return lv and lv > 0 and lv or nil
end

-- v0.2 M4: the instance kind ("none", "party", "raid", "pvp", "arena", "scenario"); "none" when unknown.
function Co.InstanceType()
    local f = F.InInstance
    if not f then return "none" end
    local _, kind = f()
    if Secret(kind) or type(kind) ~= "string" then return "none" end
    return kind
end

-- The hearthstone's bind location name (client language), or nil.
function Co.BindLocation()
    local f = F.BindLocation
    if not f then return nil end
    local v = f()
    if Secret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

function Co.Hardcore()
    local f = F.Hardcore
    if not f then return nil end
    local v = f()
    if Secret(v) then return nil end
    return v == true
end

-- ------------------------------------------------------------------ quest log
function Co.NumQuestEntries()
    local f = F.QuestNumEntries
    if not f then return 0 end
    return f() or 0
end

-- questID, isHeader for a log index (nil when there's nothing there).
function Co.QuestAt(index)
    local f = F.QuestInfo
    if not f then return nil end
    local info = f(index)
    if type(info) ~= "table" then return nil end
    return info.questID, info.isHeader == true, info.isHidden == true
end

-- The objectives table from the game (do not keep it: read what you need).
function Co.Objectives(questID)
    local f = F.QuestObjectives
    if not f then return nil end
    local t = f(questID)
    if type(t) ~= "table" then return nil end
    return t
end

function Co.QuestComplete(questID) local f = F.QuestIsComplete return f ~= nil and Co.IsTrue(f(questID)) end
function Co.QuestReady(questID) local f = F.QuestReady return f ~= nil and Co.IsTrue(f(questID)) end
function Co.OnQuest(questID) local f = F.QuestOnQuest return f ~= nil and Co.IsTrue(f(questID)) end
function Co.QuestFlagged(questID) local f = F.QuestFlagged return f ~= nil and Co.IsTrue(f(questID)) end
function Co.QuestFailed(questID) local f = F.QuestFailed return f ~= nil and Co.IsTrue(f(questID)) end

-- The quest log limit from the game; nil when the API is missing (then no limit checks).
function Co.QuestMax()
    local f = F.QuestMax
    if not f then return nil end
    local n = f()
    return type(n) == "number" and n > 0 and n or nil
end

function Co.QuestTitle(questID)
    local f = F.QuestTitle
    if not f then return nil end
    local t = f(questID)
    if type(t) ~= "string" or t == "" then return nil end
    return t
end

function Co.RequestQuest(questID)
    local f = F.QuestRequest
    if f then f(questID) return true end
    return false
end

-- ------------------------------------------------------------------ position (player only)
function Co.PlayerMap()
    local f = F.MapForUnit
    if not f then return nil end
    local map = f("player")
    if Secret(map) or type(map) ~= "number" then return nil end
    return map
end

-- x, y (0-1) on `map`, or nil (no position, hidden or secret).
function Co.PlayerPos(map)
    local f = F.MapPlayerPos
    if not f or not map then return nil end
    local pos = f(map, "player")
    if pos == nil or Secret(pos) then return nil end
    local x, y = pos:GetXY()
    if Secret(x) or Secret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
    if x == 0 and y == 0 then return nil end
    return x, y
end

-- continentID, worldX, worldY (yards) for a map point, or nil.
function Co.WorldPos(map, x, y)
    local f, vec = F.MapWorldPos, F.Vector2D
    if not f or not vec or not map or not x or not y then return nil end
    local continent, pos = f(map, vec(x, y))
    if continent == nil or pos == nil or Secret(pos) then return nil end
    local wx, wy = pos:GetXY()
    if Secret(wx) or Secret(wy) then return nil end
    return continent, wx, wy
end

function Co.Facing()
    local f = F.PlayerFacing
    if not f then return nil end
    local v = f()
    if v == nil or Secret(v) or type(v) ~= "number" then return nil end
    return v
end

-- ------------------------------------------------------------------ UI (M3)
function Co.UIParent() return F.UIParent end
function Co.Tooltip() return F.GameTooltip end
-- A colour object for Texture:SetGradient, or nil (then no gradient: flat colour).
function Co.Color(r, g, b, a)
    local f = F.CreateColor
    return f and f(r, g, b, a or 1) or nil
end
-- No Co.Reload: ReloadUI / C_UI.Reload are protected on 16001 (ADDON_ACTION_BLOCKED in v0.1.0-beta.1, even
-- from our own dialog's button). The addon never calls them; it tells the player to type /reload.

-- Atlas info (width, height ...) or nil when the client doesn't have that atlas / the API is missing.
function Co.AtlasInfo(name)
    local f = F.AtlasInfo
    if not f or type(name) ~= "string" then return nil end
    local ok, info = pcall(f, name)
    if not ok or type(info) ~= "table" then return nil end
    return info
end

-- ------------------------------------------------------------------ v0.2 M3 part 2: maps, clicks, time
-- The name of a uiMapID in the client's language, or nil.
function Co.MapName(uiMapID)
    local f = F.MapInfo
    if not f or type(uiMapID) ~= "number" then return nil end
    local ok, info = pcall(f, uiMapID)
    if not ok or type(info) ~= "table" or Secret(info.name) or type(info.name) ~= "string" or info.name == "" then return nil end
    return info.name
end

-- The parent map of a zone / dungeon / micro map, up to the continent (Enum.UIMapType: 2 = Continent;
-- warcraft.wiki.gg API_C_Map.GetMapInfo, parentMapID 0 = none). nil at a continent or above, or on no data.
function Co.MapParent(uiMapID)
    local f = F.MapInfo
    if not f or type(uiMapID) ~= "number" then return nil end
    local ok, info = pcall(f, uiMapID)
    if not ok or type(info) ~= "table" then return nil end
    local kind, parent = info.mapType, info.parentMapID
    if Secret(kind) or Secret(parent) or type(kind) ~= "number" or kind <= 2 then return nil end
    if type(parent) ~= "number" or parent <= 0 then return nil end
    return parent
end

function Co.Modifier(which)
    local f = F[which == "shift" and "IsShiftKeyDown" or which == "ctrl" and "IsControlKeyDown" or "IsAltKeyDown"]
    return f ~= nil and f() == true
end

-- Cursor x, y in screen units of `frame` (nil when unknown).
function Co.Cursor(frame)
    local f = F.GetCursorPosition
    if not f then return nil end
    local x, y = f()
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local s = frame and frame:GetEffectiveScale() or 1
    if not s or s == 0 then s = 1 end
    return x / s, y / s
end

-- Seconds of server time (for snoozes that last past a /reload); nil when the API is missing.
function Co.ServerTime()
    local f = F.GetServerTime
    if not f then return nil end
    local v = f()
    if Secret(v) or type(v) ~= "number" then return nil end
    return v
end

-- Puts a quest link into the chat box the player has open. Never opens or sends chat: false when
-- no chat box is open or the client gives no link.
function Co.InsertQuestLink(questID)
    local link, active, insert = F.QuestLink, F.ChatActiveWindow, F.ChatInsertLink
    if not (link and active and insert) or type(questID) ~= "number" then return false end
    if not active() then return false end
    local ok, text = pcall(link, questID)
    if not ok or type(text) ~= "string" or text == "" then return false end
    return insert(text) ~= false
end

-- Opens the world map at a map (the same Lua function Blizzard's own buttons use). Never in combat.
function Co.OpenMap(uiMapID)
    local f = F.OpenWorldMap
    if not f or Co.InCombat() or type(uiMapID) ~= "number" then return false end
    f(uiMapID)
    return true
end

function Co.CVarBool(name)
    local f = F.CVarBool
    if not f then return false end
    local ok, v = pcall(f, name)
    return ok and v == true
end

-- The minimap's view radius in yards (nil when unknown).
function Co.MinimapRadius()
    local f = F.MinimapRadius
    if not f then return nil end
    local ok, v = pcall(f)
    if not ok or Secret(v) or type(v) ~= "number" or v <= 0 then return nil end
    return v
end

-- A built-in sound kit number by name (SOUNDKIT table), or nil.
function Co.SoundKit(name)
    local t = Resolve("SOUNDKIT")
    local v = type(t) == "table" and t[name] or nil
    return type(v) == "number" and v or nil
end

-- ------------------------------------------------------------------ bags
function Co.ItemCount(itemID)
    local f = F.ItemCount or F.ItemCountOld   -- v0.2: the old global when C_Item.GetItemCount is missing
    if not f then return 0 end
    local n = f(itemID)
    if Secret(n) or type(n) ~= "number" then return 0 end
    return n
end

-- v0.2 First Aid: a skill line's rank, max rank (the current cap) by skill line id; scan only.
-- Returns rank, maxRank, or nil when not learned / unknown; "hidden" when it may sit under a collapsed
-- header (only the index scan is there): the caller then shows its text without a number.
local function SkillFields(info, id)
    if type(info) ~= "table" or Secret(info.skillID) or info.skillID ~= id then return nil end
    local r, m = info.rank, info.maxRank
    if Secret(r) or Secret(m) or type(r) ~= "number" then return nil end
    return r, type(m) == "number" and m or nil
end
function Co.SkillRank(skillLineID)
    local by = F.SkillLineByID
    if by then
        local ok, info = pcall(by, skillLineID)
        if ok and type(info) == "table" then
            local r, m = SkillFields(info, skillLineID)
            if r and r > 0 then return r, m end
            return nil
        end
    end
    local num, get = F.SkillLines, F.SkillLineInfo
    if not (num and get) then return nil end
    local ok, n = pcall(num)
    if not ok or type(n) ~= "number" or Secret(n) then return nil end
    local collapsed = false
    for i = 1, n do
        local ok2, info = pcall(get, i)
        if ok2 and type(info) == "table" then
            if info.isHeader and info.isCollapsed == true then collapsed = true end
            local r, m = SkillFields(info, skillLineID)
            if r and r > 0 then return r, m end
        end
    end
    if collapsed then return "hidden" end
    return nil
end

-- v0.2 quest items: bag slots (plain numbers only; AllowedWhenUntainted, called from our own code).
function Co.BagSlots(bag)
    local f = F.BagSlots
    if not f then return 0 end
    local ok, n = pcall(f, bag)
    if not ok or Secret(n) or type(n) ~= "number" then return 0 end
    return n
end

function Co.BagItemID(bag, slot)
    local f = F.BagItemID
    if not f then return nil end
    local ok, id = pcall(f, bag, slot)
    if not ok or Secret(id) or type(id) ~= "number" then return nil end
    return id
end

-- questID (nil when the item starts / belongs to no quest), isActive (that quest is in the log), isQuestItem.
function Co.BagQuestInfo(bag, slot)
    local f = F.BagQuestInfo
    if not f then return nil, false, false end
    local ok, info = pcall(f, bag, slot)
    if not ok or type(info) ~= "table" then return nil, false, false end
    local q, active, item = info.questID, info.isActive, info.isQuestItem
    if Secret(q) or type(q) ~= "number" or q <= 0 then q = nil end
    return q, (not Secret(active)) and active == true, (not Secret(item)) and item == true
end

-- ------------------------------------------------------------------ v0.2 M2: items, taxi, bindings, sound
-- Icon file id of an item (nil while unknown).
function Co.ItemIcon(itemID)
    local f = F.ItemIcon
    if not f then return nil end
    local v = f(itemID)
    if Secret(v) then return nil end
    return v
end

function Co.ItemName(itemID)
    local f = F.ItemName
    if not f then return nil end
    local v = f(itemID)
    if Secret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

-- start, duration (seconds) of an item's cooldown; 0, 0 when ready or unknown.
function Co.ItemCooldown(itemID)
    local f = F.ItemCooldown
    if not f then return 0, 0 end
    local s, d = f(itemID)
    if Secret(s) or Secret(d) or type(s) ~= "number" or type(d) ~= "number" then return 0, 0 end
    return s, d
end

-- true / false when the game says, nil when it can't (no target, protected, secret or no API).
function Co.ItemInRange(itemID, unit)
    local f = F.ItemInRange
    if not f then return nil end
    local ok, v = pcall(f, itemID, unit or "target")
    if not ok or Secret(v) or type(v) ~= "boolean" then return nil end
    return v
end

-- Taxi nodes the client lists for a map: { { id, name, known } }; known = not undiscovered.
function Co.TaxiNodesForMap(uiMapID)
    local f = F.TaxiForMap
    if not f then return {} end
    local ok, list = pcall(f, uiMapID)
    if not ok or type(list) ~= "table" or Secret(list) then return {} end
    local out = {}
    for _, n in ipairs(list) do
        if type(n) == "table" and type(n.nodeID) == "number" then
            out[#out + 1] = { id = n.nodeID, name = n.name, known = n.isUndiscovered ~= true }
        end
    end
    return out
end

-- The nodes on the open flight master's map (all of them are known to the player): { { id, name, state } }.
function Co.TaxiOpenNodes(uiMapID)
    local f = F.TaxiAllNodes
    if not f then return {} end
    local ok, list = pcall(f, uiMapID)
    if not ok or type(list) ~= "table" or Secret(list) then return {} end
    local out = {}
    for _, n in ipairs(list) do
        if type(n) == "table" and type(n.nodeID) == "number" then
            out[#out + 1] = { id = n.nodeID, name = n.name, state = n.state, slot = n.slotIndex }
        end
    end
    return out
end

-- The key bound to a binding command (e.g. "CLICK AllinOneGuideStepButton:LeftButton"), or nil.
function Co.BindingKey(command)
    local f = F.BindingKey
    if not f then return nil end
    local v = f(command)
    if Secret(v) or type(v) ~= "string" then return nil end
    return v
end

-- Plays a built-in sound kit (only ever when the player turned reminder sounds on).
function Co.PlaySound(kit)
    local f = F.PlaySound
    if not f or type(kit) ~= "number" then return false end
    pcall(f, kit, "Master")
    return true
end

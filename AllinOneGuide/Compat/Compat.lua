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

function Co.QuestComplete(questID) local f = F.QuestIsComplete return f ~= nil and f(questID) == true end
function Co.QuestReady(questID) local f = F.QuestReady return f ~= nil and f(questID) == true end
function Co.OnQuest(questID) local f = F.QuestOnQuest return f ~= nil and f(questID) == true end
function Co.QuestFlagged(questID) local f = F.QuestFlagged return f ~= nil and f(questID) == true end
function Co.QuestFailed(questID) local f = F.QuestFailed return f ~= nil and f(questID) == true end

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
-- Reloads the UI (only ever after the player's click). false when the API is missing.
function Co.Reload()
    local f = F.ReloadUI
    if not f then return false end
    f()
    return true
end

-- ------------------------------------------------------------------ bags
function Co.ItemCount(itemID)
    local f = F.ItemCount
    if not f then return 0 end
    local n = f(itemID)
    if Secret(n) or type(n) ~= "number" then return 0 end
    return n
end

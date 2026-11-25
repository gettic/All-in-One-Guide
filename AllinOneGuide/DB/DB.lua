-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Saved data. Two SavedVariables: AllinOneGuideDB (account) and AllinOneGuideCharDB (this character).
-- Rules: a dbVersion with a migration chain that never drops data (unknown keys are kept; a value of
-- the wrong type is moved to `_bad` instead of thrown away); defaults are never copied into the save
-- (Settings.lua reads them through a metatable); a save from a newer version is used as a read-only
-- copy and never migrated down; personal things (the alt index with character names) live in
-- account.personal, which no export, report or status code reads.
-- Progress is saved per guide: char.guides["pack/route"] = { current, skips, keeps, mode, stack }, plus
-- char.active (list of guide keys) and char.focus. No step history: progress comes from the game.
local _, ns = ...
local U = ns.U
local DB = { CURRENT = 1, readOnly = {}, repaired = false, moveCandidate = nil }
ns.DB = DB

local ACC, CHAR = "AllinOneGuideDB", "AllinOneGuideCharDB"
local MAX_ALTS = 50

-- Expected types of the top-level fields (anything else is left alone).
local ACC_SHAPE = { dbVersion = "number", boot = "table", settings = "table", personal = "table", modules = "table", selftest = "table" }
local CHAR_SHAPE = { dbVersion = "number", guides = "table", active = "table", settings = "table", window = "table", modules = "table", flags = "table" }

-- The tables every version needs. Runs after the migration chain every time (also after a repair
-- moved a wrong-typed table aside), so migrations only add or move their own fields.
local ENSURE = {
    account = { "settings", "personal", "modules" },
    char = { "guides", "active", "settings", "window", "modules", "flags" },
}
local function Ensure(t, kind)
    for _, k in ipairs(ENSURE[kind]) do
        if t[k] == nil then t[k] = {} end
    end
    if kind == "account" and type(t.personal) == "table" and t.personal.alts == nil then t.personal.alts = {} end
end
DB.Ensure = Ensure

-- Migrations: MIG.account[n] turns version n-1 into n. They may add and move, never delete.
local MIG = { account = {}, char = {} }
DB.MIG = MIG
MIG.account[1] = function(t) Ensure(t, "account") end
MIG.char[1] = function(t) Ensure(t, "char") end

local function KeepAside(t, key, value)
    t._bad = type(t._bad) == "table" and t._bad or {}
    local slot, n = key, 1
    while t._bad[slot] ~= nil do
        n = n + 1
        slot = key .. "#" .. n
    end
    t._bad[slot] = value
end

local function Repair(t, shape)
    local fixed = false
    for key, kind in pairs(shape) do
        local v = t[key]
        if v ~= nil and type(v) ~= kind then
            KeepAside(t, key, v)
            t[key] = nil
            fixed = true
        end
    end
    return fixed
end

-- A dbVersion must be a whole number >= 0 (a hand-edited or damaged save may hold -1, 0.5, NaN, inf):
-- anything else is kept aside like any wrong value and the save is treated as unversioned.
local function FixVersion(t)
    local v = t.dbVersion
    if v == nil then return false end
    if type(v) == "number" and v == v and v >= 0 and v < math.huge and v % 1 == 0 then return false end
    KeepAside(t, "dbVersion", v)
    t.dbVersion = nil
    return true
end

-- Repair, then the migration chain, then Ensure. A newer save isn't migrated: it gets a working
-- copy (Ensure on the copy only). Returns the table to use and whether it's a read-only copy.
local function Prepare(t, kind)
    local shape, mig = ACC_SHAPE, MIG.account
    if kind == "char" then shape, mig = CHAR_SHAPE, MIG.char end
    local fixed = Repair(t, shape)
    fixed = FixVersion(t) or fixed
    if fixed then DB.repaired = true end
    local version = t.dbVersion or 0
    if version > DB.CURRENT then
        local copy = U.Copy(t)
        Ensure(copy, kind)
        return copy, true
    end
    for v = version + 1, DB.CURRENT do
        mig[v](t)
        t.dbVersion = v
    end
    Ensure(t, kind)
    return t, false
end

-- Returns the table to work with for one SavedVariable (may be a read-only copy).
local function Open(name, kind)
    local raw = _G[name]
    if raw ~= nil and type(raw) ~= "table" then
        raw = { _bad = { root = raw } }
        DB.repaired = true
    end
    raw = raw or {}
    _G[name] = raw
    local use, ro = Prepare(raw, kind)
    if ro then DB.readOnly[kind] = true end
    return raw, use
end

-- The same repair + migration as at load, on a table the caller owns (the self-test passes a deep
-- copy; the real SavedVariables are never touched). Returns the prepared table.
function DB.PrepareCopy(t, kind)
    if type(t) ~= "table" then t = { _bad = { root = t } } end
    local repaired = DB.repaired
    local use = Prepare(t, kind == "char" and "char" or "account")
    DB.repaired = repaired   -- a check on a copy never marks the real save as repaired
    return use
end

-- Called at ADDON_LOADED. Returns true when this session runs in safe mode.
function DB.Init()
    DB.readOnly, DB.repaired = {}, false
    DB.freshChar = _G[CHAR] == nil
    -- 1. the boot record first (crash-during-load check), before anything else touches the saves
    local raw = _G[ACC]
    local boot = (type(raw) == "table" and type(raw.boot) == "table") and raw.boot or {}
    DB.boot = boot
    if ns.Errors.BootStart(boot) then
        -- safe mode: defaults in memory only; the saves stay as they are (only the boot record is written)
        if raw == nil then _G[ACC] = { boot = boot }
        elseif type(raw) == "table" and raw.boot == nil then raw.boot = boot end
        local a, c = {}, {}
        Ensure(a, "account")
        Ensure(c, "char")
        a.dbVersion, c.dbVersion = DB.CURRENT, DB.CURRENT
        DB.account, DB.char = a, c
        DB.readOnly.account, DB.readOnly.char = true, true
        return true
    end
    -- 2. open, repair and migrate both saves
    local rawAcc, acc = Open(ACC, "account")
    local _, char = Open(CHAR, "char")
    if type(rawAcc.boot) ~= "table" then rawAcc.boot = boot end   -- the boot record always lives in the real save
    DB.account, DB.char = acc, char
    return false
end

function DB.BootDone() ns.Errors.BootDone(DB.boot) end

-- ------------------------------------------------------------------ per guide
-- Guide key "packId/routeId". Created on first use.
function DB.Guide(key)
    local g = DB.char.guides[key]
    if type(g) ~= "table" then
        if g ~= nil then KeepAside(DB.char, "guide:" .. key, g) end
        g = { skips = {}, keeps = {}, mode = "normal", stack = {} }
        DB.char.guides[key] = g
    end
    g.skips = type(g.skips) == "table" and g.skips or {}
    g.keeps = type(g.keeps) == "table" and g.keeps or {}
    g.stack = type(g.stack) == "table" and g.stack or {}
    if type(g.mode) ~= "string" then g.mode = "normal" end
    return g
end

function DB.SetActive(keys, focus)
    local list = {}
    for i, k in ipairs(keys) do list[i] = k end
    DB.char.active = list
    DB.char.focus = focus or list[1]
end

-- ------------------------------------------------------------------ per module
-- A module's own save: root.modules[name] with its own schemaVersion and migrations.
-- A newer schema than this code knows opens as a read-only copy.
function DB.Module(name, scope, schemaVersion, migrations)
    local root = scope == "char" and DB.char or DB.account
    local t = root.modules[name]
    if type(t) ~= "table" then
        if t ~= nil then KeepAside(root.modules, name, t) end
        t = {}
        root.modules[name] = t
    end
    local v = tonumber(t.schemaVersion) or 0
    if v > schemaVersion then return U.Copy(t), true end
    for n = v + 1, schemaVersion do
        if migrations and migrations[n] then migrations[n](t) end
        t.schemaVersion = n
    end
    return t, false
end

-- ------------------------------------------------------------------ self-test line
function DB.SelfTestLine()
    local s = DB.account and DB.account.selftest
    return type(s) == "table" and s.line or nil
end

function DB.SetSelfTest(version, build, line)
    if not DB.account then return end
    DB.account.selftest = { version = version, build = build, line = line }
end

-- ------------------------------------------------------------------ alt index and "move data?"
local function Alts()
    local p = DB.account.personal
    if type(p.alts) ~= "table" then
        if p.alts ~= nil then KeepAside(p, "alts", p.alts) end
        p.alts = {}
    end
    return p.alts
end

-- At login: is this a fresh character save that looks like a renamed character we know?
-- Same class, race, faction and level, with guide progress, under another name. Only one match counts.
function DB.FindMoveCandidate(key, fresh)
    DB.moveCandidate = nil
    if not fresh or not key or DB.readOnly.account then return nil end
    local me = ns.Compat.Player()
    local found
    for altKey, a in pairs(Alts()) do
        if altKey ~= key and type(a) == "table" and a.class == me.class and a.race == me.race
            and a.faction == me.faction and a.level == me.level and (a.level or 0) > 1
            and type(a.guides) == "table" and next(a.guides) ~= nil then
            if found then return nil end   -- more than one: don't guess
            found = altKey
        end
    end
    DB.moveCandidate = found
    return found
end

-- The player said yes: copy the old character's guide progress here (the old entry is kept).
function DB.MoveFrom(altKey)
    local a = Alts()[altKey]
    if type(a) ~= "table" or DB.readOnly.char then return false end
    DB.char.guides = U.Copy(a.guides or {})
    DB.char.active = U.Copy(a.active or {})
    DB.char.focus = a.focus
    a.movedTo = true
    DB.moveCandidate = nil
    return true
end

-- At logout: remember this character (for "move data?" after a rename). Capped, oldest dropped first.
function DB.UpdateAlt(key)
    if not key or DB.readOnly.account or DB.readOnly.char then return end
    local alts = Alts()
    local me = ns.Compat.Player()
    local a = type(alts[key]) == "table" and alts[key] or {}
    a.class, a.race, a.faction, a.level = me.class, me.race, me.faction, me.level
    a.stamp = (tonumber(DB.account.personal.altStamp) or 0) + 1
    DB.account.personal.altStamp = a.stamp
    a.guides = U.Copy(DB.char.guides)
    a.active = U.Copy(DB.char.active)
    a.focus = DB.char.focus
    alts[key] = a
    -- cap
    local keys = {}
    for k, v in pairs(alts) do if type(v) == "table" then keys[#keys + 1] = k end end
    if #keys > MAX_ALTS then
        table.sort(keys, function(x, y) return (alts[x].stamp or 0) < (alts[y].stamp or 0) end)
        for i = 1, #keys - MAX_ALTS do alts[keys[i]] = nil end
    end
end

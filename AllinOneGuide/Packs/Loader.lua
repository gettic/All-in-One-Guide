-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Pack-addon loader (v0.2.5 C3, plans\v0.2.5-code\plan.md; tos T27 / T28 in plans\roadmap-1-60\tos.md).
-- The routes live in LoadOnDemand guide pack addons (AllinOneGuide_Alliance, AllinOneGuide_Horde). Data\KnownPacks.lua
-- (written by tools\build.lua) says which pack is in which folder, so nothing has to load to know that.
-- Rules: only the folders this character needs load (the ones holding its open guides, else its faction's one for
-- the first pick), never all; never from an ADDON_LOADED handler (Engine.Restore runs on the bus Ready, and the
-- other callers are clicks); out of combat (CombatQueue); EnableAddOn only after the player's click. Packs refused
-- for a newer format stay listed as "needs a newer All-in-One Guide".
--   ns.PackLoader.Folders()            -> list of { folder, faction, title } (KnownPacks order)
--   .FolderOf(packId) -> folder | nil   .FolderForFaction(faction) -> folder | nil   .Title(folder)
--   .State(folder) -> "loaded" | "ready" | "disabled" | "missing" | "old" | "broken" | "unknown"
--   .Ensure(folder, after) -> true (loaded now) | false (failed) | "queued" (waits for the end of combat);
--     after(ok, reason) runs when it's done.   .EnsurePack(packId, after)
--   .Needed() -> folders to load at login   .LoadNeeded(after) (Engine.Restore)
--   .Enable(folder) (a click) -> true | "reload" | false   .Registered(packId) (from AllinOneGuide.RegisterPack)
--   .PackState(packId) -> state, folder   .StatusLine()   bus: PacksChanged
local _, ns = ...
local Co = ns.Compat
local PL = { loading = nil, registered = {}, results = {}, queued = {}, loads = 0, needsReload = {} }
ns.PackLoader = PL

local function Known()
    local k = ns.KnownPacks
    if type(k) ~= "table" then return { folders = {}, packs = {} } end
    return { folders = type(k.folders) == "table" and k.folders or {}, packs = type(k.packs) == "table" and k.packs or {} }
end

function PL.Folders() return Known().folders end

function PL.Title(folder)
    for _, f in ipairs(Known().folders) do if f.folder == folder then return f.title end end
    return folder
end

local function IsKnownFolder(folder)
    for _, f in ipairs(Known().folders) do if f.folder == folder then return true end end
    return false
end

-- Which folder holds a pack: the index, else a loaded pack's folder, else the X-AOG-Packs line of a known folder's
-- .toc (readable without loading it; covers packs added in a newer pack release).
function PL.FolderOf(packId)
    if type(packId) ~= "string" then return nil end
    local p = Known().packs[packId]
    if type(p) == "table" and type(p.folder) == "string" then return p.folder end
    if PL.registered[packId] and PL.registered[packId] ~= "main" then return PL.registered[packId] end
    for _, f in ipairs(Known().folders) do
        local list = Co.AddOnMeta(f.folder, "X-AOG-Packs")
        if type(list) == "string" then
            for id in list:gmatch("[^,%s]+") do if id == packId then return f.folder end end
        end
    end
    return nil
end

function PL.FolderForFaction(faction)
    for _, f in ipairs(Known().folders) do if f.faction == faction then return f.folder end end
    return nil
end

local function CharName()
    local key = Co.CharacterKey()
    return key and key:match("^([^%-]+)") or nil
end

-- The folder's state for this character (read each time: cheap, a few API calls).
function PL.State(folder)
    if Co.IsAddOnLoaded(folder) then return "loaded" end
    local loadable, reason = Co.AddOnInfo(folder)
    if reason == "MISSING_API" then return "unknown" end
    if reason == "MISSING" then return "missing" end
    if reason == "DISABLED" or Co.AddOnEnabled(folder, CharName()) == false then return "disabled" end
    if reason == "INTERFACE_VERSION" then return "old" end
    if loadable == false then
        if type(reason) == "string" and reason:match("^DEP_") then return "broken" end
        return reason and "broken" or "unknown"
    end
    if PL.results[folder] and PL.results[folder] ~= true then return "broken" end
    return "ready"
end

-- A pack's state: "loaded" (registered), "refused" (needs a newer guide), or its folder's state; and the folder.
function PL.PackState(packId)
    if ns.Packs.packs[packId] then return "loaded", PL.registered[packId] end
    if ns.Packs.refused[packId] then return "refused", PL.FolderOf(packId) end
    local folder = PL.FolderOf(packId)
    if not folder then return "unknown", nil end
    local st = PL.State(folder)
    if st == "loaded" then st = "absent" end   -- the folder is loaded but this pack isn't in it
    return st, folder
end

function PL.Registered(packId)
    PL.registered[packId] = PL.loading or "main"
end

local function Done(folder, ok, reason, after)
    PL.results[folder] = ok and true or (reason or "failed")
    ns.Bus.Fire("PacksChanged", folder, ok)
    if after then after(ok, reason) end
end

-- The load itself (out of combat). Only known folders, only once per session when it failed.
local function Load(folder, after)
    PL.queued[folder] = nil
    if Co.IsAddOnLoaded(folder) then
        if PL.results[folder] == nil then PL.results[folder] = true end
        if after then after(true) end
        return true
    end
    if Co.InCombat() then return false end
    PL.loading = folder
    PL.loads = PL.loads + 1
    local ok, res, reason = pcall(Co.LoadAddOn, folder)
    PL.loading = nil
    local loaded = ok and res == true
    if not ok then reason = "error" end
    if not loaded and ns.Errors then ns.Errors.Debug("pack folder %s didn't load: %s", folder, tostring(reason)) end
    Done(folder, loaded, reason, after)
    return loaded
end

function PL.Ensure(folder, after)
    if type(folder) ~= "string" or not IsKnownFolder(folder) then
        if after then after(false, "unknown") end
        return false
    end
    if Co.IsAddOnLoaded(folder) then return Load(folder, after) end
    local st = PL.State(folder)
    if st ~= "ready" then
        if after then after(false, st) end
        return false
    end
    if Co.InCombat() then
        PL.queued[folder] = true
        ns.CombatQueue.Run("packload." .. folder, Load, folder, after)
        return "queued"
    end
    return Load(folder, after)
end

function PL.EnsurePack(packId, after)
    if ns.Packs.packs[packId] then
        if after then after(true) end
        return true
    end
    return PL.Ensure(PL.FolderOf(packId), after)
end

-- The folders this character needs now: the ones holding its saved guides (active list), else the folder of its
-- faction (for the first pick). Never the other faction's folder unless a saved guide is in it.
function PL.Needed()
    local out, seen = {}, {}
    local char = ns.DB and ns.DB.char
    for _, k in ipairs(type(char) == "table" and type(char.active) == "table" and char.active or {}) do
        local packId = tostring(k):match("^([^/]+)/")
        if packId and not ns.Packs.packs[packId] then
            local folder = PL.FolderOf(packId)
            if folder and not seen[folder] then out[#out + 1], seen[folder] = folder, true end
        end
    end
    if #out == 0 and not (type(char) == "table" and type(char.active) == "table" and #char.active > 0) then
        local folder = PL.FolderForFaction(Co.Player().faction)
        if folder and not Co.IsAddOnLoaded(folder) then out[1] = folder end
    end
    return out
end

-- At the Ready point (Engine.Restore, before the guides reopen): loads the needed folders that are installed.
-- after() runs once every needed folder is done (at once, or after combat for a queued one).
function PL.LoadNeeded(after)
    local list = PL.Needed()
    local waiting = 0
    local function One()
        waiting = waiting - 1
        if waiting == 0 and after then after() end
    end
    for _, folder in ipairs(list) do
        if PL.State(folder) == "ready" then
            waiting = waiting + 1
            local r = PL.Ensure(folder, function() One() end)
            if r == false and PL.results[folder] == nil then One() end
        end
    end
    if waiting == 0 and after then after() end
    return list
end

-- "Turn on" (a click only, tos T27): enable for this character, then load. "reload" when the game needs a /reload.
function PL.Enable(folder)
    if not IsKnownFolder(folder) then return false end
    if not Co.EnableAddOn(folder, CharName()) then return false end
    local st = PL.State(folder)
    -- (needsReload: the window's end / missing card says "type /reload" instead of showing Turn on again)
    if st == "disabled" then PL.needsReload[folder] = true return "reload" end
    local r = PL.Ensure(folder)
    if r == false then PL.needsReload[folder] = true return "reload" end
    return true
end

-- Self-test: the index is there, each known folder has a state, a loaded folder's packs registered from it, and the
-- other faction's folder isn't loaded unless a guide of it is open (tos T27).
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "packs", fn = function(h)
    h.Count()
    if type(ns.KnownPacks) ~= "table" then h.Problem("packs: Data\\KnownPacks.lua missing") return end
    local parts = {}
    for _, f in ipairs(Known().folders) do
        local st = PL.State(f.folder)
        parts[#parts + 1] = f.folder:gsub("^AllinOneGuide_", "") .. "=" .. st
        if st == "loaded" then
            local any = false
            for _, folder in pairs(PL.registered) do if folder == f.folder then any = true end end
            if not any and PL.results[f.folder] == true then h.Problem("packs: " .. f.folder .. " loaded but no pack registered") end
        end
    end
    h.Info("packs: " .. table.concat(parts, ", "))
end }

-- "packs: 1 loaded, 1 not installed" (/aog status)
function PL.StatusLine()
    local n = { loaded = 0, missing = 0, other = 0 }
    for _, f in ipairs(Known().folders) do
        local st = PL.State(f.folder)
        if st == "loaded" then n.loaded = n.loaded + 1
        elseif st == "missing" then n.missing = n.missing + 1
        else n.other = n.other + 1 end
    end
    return ns.U.Fill(ns.L.PACKS_STATUS, n)
end

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Namespace, the one code global, the addon colour and the chat line helper.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.TITLE = "All-in-One Guide"
ns.COLOR = "2fc4a8"          -- the Dark theme's accent (plans\default-theme\theme-notes.md)
ns.version = "?"             -- read from the .toc at ADDON_LOADED (Core\Boot.lua)
ns.Perf = { loadStart = debugprofilestop() }
ns.Test = {}                 -- private test hooks for the offline tests; never on the public global
-- Extra self-test checks from later modules: { label, fn(h) } with h = { Count, Problem, Skip, Info }
-- (run by SelfTest\SelfTest.lua, which loads last).
ns.SelfChecks = {}

-- The one code global. Kept tiny on purpose: .name, .version and the public API (Core\API.lua).
AllinOneGuide = AllinOneGuide or {}
AllinOneGuide.name = ns.TITLE

-- v0.2.5: the guide pack addons (AllinOneGuide_Alliance / _Horde, LoadOnDemand) can't see this private namespace,
-- so their compiled pack files register through these two (data only, tos T29). Set on every load, so the newest
-- guide code always receives them. Returns true, or false + reason (like ns.Packs.Register).
function AllinOneGuide.RegisterPack(header, routes)
    if not (ns.Packs and ns.Packs.Register) then return false, "not ready" end
    local ok, res, why = pcall(ns.Packs.Register, header, routes)
    if not ok then
        if ns.Errors then ns.Errors.Debug("RegisterPack: %s", tostring(res)) end
        return false, "bad pack"
    end
    if res and ns.PackLoader and ns.PackLoader.Registered then ns.PackLoader.Registered(header.id) end
    return res, why
end
function AllinOneGuide.RegisterSpots(packId, targets)
    if not (ns.Spots and ns.Spots.Register) then return false end
    local ok, res = pcall(ns.Spots.Register, packId, targets)
    return ok and res or false
end

-- Every chat line we write starts with "All-in-One Guide:" in the addon's colour.
-- v0.2 M4: the chat tab from the setting chatTab (ChatFrame1..10); the default chat frame when that tab
-- doesn't exist (or before the settings are read).
function ns.ChatFrame()
    local n = 1
    if ns.Settings and ns.DB and type(ns.DB.account) == "table" and type(ns.DB.account.settings) == "table" then
        n = ns.Settings.Get("chatTab")
    end
    local f = n > 1 and rawget(_G, "ChatFrame" .. n)
    if type(f) == "table" and type(f.AddMessage) == "function" then return f end
    return rawget(_G, "DEFAULT_CHAT_FRAME")
end

function ns.Print(text)
    local line = "|cff" .. ns.COLOR .. ns.TITLE .. ":|r " .. tostring(text)
    local frame = ns.ChatFrame()
    if type(frame) == "table" and type(frame.AddMessage) == "function" then
        frame:AddMessage(line)
    else
        print(line)
    end
end

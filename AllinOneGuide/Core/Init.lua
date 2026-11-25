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

-- The one code global. Kept tiny on purpose; the public API comes in v0.1.1.
AllinOneGuide = AllinOneGuide or {}
AllinOneGuide.name = ns.TITLE

-- Every chat line we write starts with "All-in-One Guide:" in the addon's colour.
function ns.Print(text)
    local line = "|cff" .. ns.COLOR .. ns.TITLE .. ":|r " .. tostring(text)
    local frame = _G.DEFAULT_CHAT_FRAME
    if type(frame) == "table" and type(frame.AddMessage) == "function" then
        frame:AddMessage(line)
    else
        print(line)
    end
end

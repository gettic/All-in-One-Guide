-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Start-up order and the M1 slash commands.
--   ADDON_LOADED: version, Compat feature switches, saves (+ safe mode check), settings, language
--   PLAYER_LOGIN: game-state reader, names, character key, "move data?" check, login time, boot done
--   PLAYER_LOGOUT: remember this character in the alt index
local _, ns = ...
local Co, U, L = ns.Compat, ns.U, ns.L
local B = {}
ns.Boot = B

local function Notices()
    if ns.safeMode then
        ns.Print(L.SAFE_MODE)
        return
    end
    if ns.DB.readOnly.account or ns.DB.readOnly.char then ns.Print(L.SAVE_NEWER) end
    if ns.DB.repaired then ns.Print(L.SAVE_REPAIRED) end
end

function B.AddonLoaded(_, name)
    if name ~= ns.ADDON then return end
    ns.Events.Off("ADDON_LOADED", B)
    ns.version = Co.AddOnMeta(ns.ADDON, "Version") or "?"
    AllinOneGuide.version = ns.version
    Co.Init()
    local safe = ns.DB.Init()
    ns.Settings.Init()
    ns.Errors.debug = ns.Settings.Get("debug")
    ns.Locale.Choose(ns.Settings.Get("lang"), Co.Locale())
    if safe then ns.Feature.Set("modules", "safe", "safe mode") end
    Notices()
    ns.Perf.loadMs = Co.Ms() - ns.Perf.loadStart
end

function B.Login()
    local t0 = Co.Ms()
    ns.Events.Off("PLAYER_LOGIN", B)
    ns.GameState.Start()
    ns.Names.Start()
    ns.charKey = Co.CharacterKey()
    ns.DB.FindMoveCandidate(ns.charKey, ns.DB.freshChar)
    ns.Bus.Fire("Login")
    ns.Perf.loginMs = (ns.Perf.loadMs or 0) + (Co.Ms() - t0)
    ns.Perf.loadedAtLogin = ns.Modules.CountLoaded()   -- load-on-demand modules up at login (budget 0)
    ns.DB.BootDone()
end

function B.Logout()
    ns.DB.UpdateAlt(ns.charKey)
end

ns.Events.On("ADDON_LOADED", B, B.AddonLoaded, "core")
ns.Events.On("PLAYER_LOGIN", B, B.Login, "core")
ns.Events.On("PLAYER_LOGOUT", B, B.Logout, "core")

-- ------------------------------------------------------------------ /aog status, debug, error
-- One English line, built by the allowlisted serializer: no names, nothing personal.
function B.StatusLine()
    local onCount, off = ns.Feature.Summary()
    local errors = 0
    for _, n in pairs(ns.Errors.counts) do errors = errors + n end
    return ns.Serializer.Build("status", {
        v = ns.version,
        client = Co.ClientLine(),
        st = ns.DB.SelfTestLine() or "not run",
        on = onCount,
        off = #off > 0 and table.concat(off, ",") or nil,
        safe = ns.safeMode and true or nil,
        ro = (ns.DB.readOnly.account or ns.DB.readOnly.char) and true or nil,
        err = errors,
        login = U.Whole(ns.Perf.loginMs or 0),
    })
end
ns.Test.StatusLine = B.StatusLine

ns.Slash.Add("status", function()
    ns.Print(L.STATUS_HEAD)
    ns.Print(B.StatusLine())
end, "HELP_STATUS", { main = true })

ns.Slash.Add("debug", function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.Settings.Set("debug", arg == "on")
        ns.Errors.debug = arg == "on"
        ns.Print(arg == "on" and L.DEBUG_ON or L.DEBUG_OFF)
        return
    end
    local lines = ns.Errors.DebugLines(20)
    if #lines == 0 then ns.Print(L.DEBUG_EMPTY) return end
    for i = #lines, 1, -1 do ns.Print(lines[i]) end
end, "HELP_DEBUG")

ns.Slash.Add("error", function()
    if not ns.Errors.last then ns.Print(L.ERROR_NONE) return end
    ns.Print(L.ERROR_DETAILS)
    ns.Print(ns.Errors.CopyText())
end, "HELP_ERROR")

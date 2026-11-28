-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Our texts: stable keys, English as the fallback for any missing key. Our own language setting
-- (English / Dansk; WoW has no Danish client) is applied at ADDON_LOADED; a change takes effect
-- after /reload. Both tables stay loaded until then; afterwards the unused one is dropped.
-- Rules: sentences are one key with named fields ("{count} done"), never glued together; game names
-- come from the client and stay in the client's language.
local _, ns = ...
local U = ns.U
local Lo = { tables = {}, current = nil, en = nil, code = "enUS", missing = {} }
ns.Locale = Lo

local function Missing(k)
    if not Lo.missing[k] then
        Lo.missing[k] = true
        ns.Errors.Debug("missing text key %s (%s)", tostring(k), Lo.code)
    end
end

ns.L = setmetatable({}, {
    __index = function(_, k)
        local cur = Lo.current or Lo.en
        local v = cur and cur[k]
        if v == nil then
            v = Lo.en and Lo.en[k]
            Missing(k)
            if v == nil then return tostring(k) end
        end
        return v
    end,
    __newindex = function() error("ns.L is read-only; add texts to Locale\\<code>.lua") end,
})

function Lo.Add(code, t)
    Lo.tables[code] = t
    if code == "enUS" then Lo.en = t end
end

-- setting: "en", "da" or "auto" (follow the client if we have its language, else English).
function Lo.Choose(setting, clientLocale)
    local code
    if setting == "da" then code = "daDK"
    elseif setting == "en" then code = "enUS"
    else code = clientLocale end
    if not code or not Lo.tables[code] then code = "enUS" end
    Lo.code, Lo.current = code, Lo.tables[code]
    for c in pairs(Lo.tables) do
        if c ~= code and c ~= "enUS" then Lo.tables[c] = nil end
    end
    return code
end

-- The language a setting stands for, without changing anything (tables may be dropped already).
Lo.SHIPPED = { enUS = true, daDK = true }
function Lo.CodeFor(setting, clientLocale)
    if setting == "da" then return "daDK" end
    if setting == "en" then return "enUS" end
    if clientLocale and Lo.SHIPPED[clientLocale] then return clientLocale end
    return "enUS"
end

-- The player picks a language ("en", "da", "auto"): saved now, used after a reload (one dialog).
function Lo.Switch(setting)
    local L = ns.L
    setting = tostring(setting or ""):lower()
    if setting ~= "en" and setting ~= "da" and setting ~= "auto" then
        ns.Print(L.LANG_USAGE)
        return false
    end
    -- the choice only takes effect after a reload, so it must be saved: not possible in safe mode or
    -- with a save from a newer version (kept read-only); say why instead of a dialog that does nothing
    if ns.safeMode then ns.Print(L.SAFE_MODE) return false end
    if ns.DB.readOnly.account then ns.Print(L.SAVE_NEWER) return false end
    ns.Settings.Set("lang", setting)
    if Lo.CodeFor(setting, ns.Compat.Locale()) == Lo.code then
        ns.Print(L.LANG_SAME)
        return true
    end
    -- ReloadUI is protected on 16001 (ADDON_ACTION_BLOCKED, beta.1): the dialog only says to type /reload
    -- (one OK button); the chat line stays as a reminder after it closes
    ns.Popups.Confirm({ kind = "lang", text = L.LANG_RELOAD, acceptText = L.POPUP_OK, noCancel = true,
        accept = function() ns.Print(L.LANG_LATER) end })
    return true
end

-- First run on an English UI: one chat line "Dansk? Skriv /aog lang da." (in Danish on purpose; once per account).
function Lo.Hint()
    if ns.safeMode or ns.DB.readOnly.account or ns.Test.quietFirstRun then return end
    if ns.Settings.Get("hintLang") or ns.Settings.Get("lang") ~= "auto" or Lo.code ~= "enUS" then return end
    ns.Settings.Set("hintLang", true)
    -- one chat line (not the notice line: that slot is for the guide; player review, beta.2)
    ns.Print("Dansk? Skriv /aog lang da.")
end
-- a few seconds after login, once the window and the guide have settled
ns.Bus.On("Login", Lo, function() ns.Compat.After(3, function() ns.Errors.Call("ui", Lo.Hint) end) end, "ui", 85)

ns.Slash.Add("lang", function(arg) Lo.Switch(strtrim(tostring(arg or ""))) end, "HELP_LANG")

-- L-text with named fields.
function Lo.F(key, fields) return U.Fill(ns.L[key], fields) end

-- Plural helper: KEY_ONE / KEY_MANY, both with {n}.
function Lo.Plural(n, key)
    return U.Fill(ns.L[key .. ((n == 1) and "_ONE" or "_MANY")], { n = n })
end

-- Number, time and date formats per language (v0.2 M4). English: 1,234.5 and 2026-11-25; Danish:
-- 1.234,5 and 25.11.2026; both use a 24-hour clock. Coordinates (/way lines) stay with a dot on purpose:
-- the /way command reads them back.
Lo.FORMATS = {
    enUS = { dec = ".", group = ",", date = "{y}-{m}-{d}" },
    daDK = { dec = ",", group = ".", date = "{d}.{m}.{y}" },
}
local function Fmt() return Lo.FORMATS[Lo.code or "enUS"] or Lo.FORMATS.enUS end

function Lo.Number(n, decimals)
    n = tonumber(n) or 0
    local f = Fmt()
    local s = ("%." .. (decimals or 0) .. "f"):format(math.abs(n))
    local int, frac = s:match("^(%d+)%.?(%d*)$")
    int = int:reverse():gsub("(%d%d%d)", "%1" .. f.group):reverse()
    if int:sub(1, 1) == f.group then int = int:sub(2) end
    local out = int .. ((frac ~= "" and (f.dec .. frac)) or "")
    if n < 0 and tonumber(s) ~= 0 then out = "-" .. out end
    return out
end

-- v0.2.9 (the user: "change yards to meters, im in the eu"): a distance (the game's yards; all maths stays in
-- yards) as the player reads it. Setting distUnit "meters" (default): "35 m", from 1000 m "1.2 km"; "yards": "35 yd".
Lo.METERS_PER_YARD = 0.9144
function Lo.Distance(yards)
    local y = math.max(0, tonumber(yards) or 0)
    local S = ns.Settings
    if S and S.Get and S.Get("distUnit") == "yards" then
        return U.Fill(ns.L.YARDS, { n = math.floor(y + 0.5) })
    end
    local m = math.floor(y * Lo.METERS_PER_YARD + 0.5)
    if m >= 1000 then
        local km = math.floor(m / 100 + 0.5) / 10   -- one decimal, rounded
        return U.Fill(ns.L.KILOMETERS, { n = Lo.Number(km, 1) })
    end
    return U.Fill(ns.L.METERS, { n = m })
end

-- Seconds -> "1:05" (under an hour) or "1:02:05".
function Lo.Duration(seconds)
    local s = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
    local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s % 60) end
    return ("%d:%02d"):format(m, s % 60)
end

-- Hours and minutes -> "14:05" (24-hour in both languages).
function Lo.Clock(hour, minute) return ("%02d:%02d"):format((tonumber(hour) or 0) % 24, (tonumber(minute) or 0) % 60) end

function Lo.Date(y, m, d)
    return U.Fill(Fmt().date, { y = ("%04d"):format(tonumber(y) or 0), m = ("%02d"):format(tonumber(m) or 0), d = ("%02d"):format(tonumber(d) or 0) })
end

-- Test hook: a pseudo-long locale (+40 %, with æøå) built from English, placeholders kept.
function ns.Test.PseudoLocale()
    local t = {}
    for k, v in pairs(Lo.en or {}) do
        if type(v) == "string" then
            local n = math.ceil(U.Utf8Len(v) * 0.4)
            local pad = string.rep("æøå", math.ceil(n / 3))
            t[k] = v .. " " .. U.Utf8Sub(pad, 1, math.max(1, n - 1))
        else
            t[k] = v
        end
    end
    Lo.tables.xxPS = t
    Lo.code, Lo.current = "xxPS", t
end

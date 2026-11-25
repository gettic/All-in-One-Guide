-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- One declarative settings schema. It feeds the title menu and slash commands now, and the settings
-- panel, search, profiles, reset and export allowlist later. Defaults are read through a metatable,
-- so only values the player changed are written to the save.
--   key, scope ("account" | "char"), kind ("bool" | "number" | "choice"), default, min / max / choices,
--   export (may go into a settings export later; never for personal things)
local _, ns = ...
local S = {}
ns.Settings = S

S.schema = {
    { key = "lang", scope = "account", kind = "choice", default = "auto", choices = { "auto", "en", "da" }, export = true },
    { key = "quiet", scope = "account", kind = "bool", default = false, export = true },
    { key = "debug", scope = "account", kind = "bool", default = false, export = false },
    { key = "locked", scope = "char", kind = "bool", default = false, export = true },
    { key = "small", scope = "char", kind = "bool", default = false, export = true },
    { key = "opacity", scope = "char", kind = "number", default = 0.8, min = 0.2, max = 1, export = true },
    { key = "hintLang", scope = "account", kind = "bool", default = false, export = false },   -- first-run "Dansk?" hint shown
    { key = "shown", scope = "char", kind = "bool", default = true, export = false },          -- guide window open
    { key = "arrow", scope = "char", kind = "bool", default = true, export = true },           -- waypoint arrow on
    { key = "theme", scope = "account", kind = "choice", default = "Dark", choices = { "Dark" }, export = true },
    { key = "reducedMotion", scope = "account", kind = "bool", default = false, export = true },
}
local byKey = {}
for _, d in ipairs(S.schema) do byKey[d.key] = d end
S.byKey = byKey

local function Valid(d, v)
    if d.kind == "bool" then return type(v) == "boolean" end
    if d.kind == "number" then return type(v) == "number" and v == v and v >= d.min and v <= d.max end
    if d.kind == "choice" then
        for _, c in ipairs(d.choices) do if c == v then return true end end
        return false
    end
    return false
end
S.Valid = Valid

local function Store(scope)
    local root = scope == "char" and ns.DB.char or ns.DB.account
    return root.settings
end

-- Called after DB.Init: defaults by metatable; saved values of the wrong form are ignored (kept as they are).
function S.Init()
    for _, scope in ipairs({ "account", "char" }) do
        local t = Store(scope)
        setmetatable(t, nil)
        local defaults = {}
        for _, d in ipairs(S.schema) do
            if d.scope == scope then defaults[d.key] = d.default end
        end
        setmetatable(t, { __index = defaults })
    end
end

function S.Get(key)
    local d = byKey[key]
    if not d then error("unknown setting " .. tostring(key), 2) end
    local v = Store(d.scope)[key]
    if not Valid(d, v) then return d.default end
    return v
end

function S.Set(key, value)
    local d = byKey[key]
    if not d then error("unknown setting " .. tostring(key), 2) end
    if not Valid(d, value) then return false end
    local t = Store(d.scope)
    if value == d.default then rawset(t, key, nil) else rawset(t, key, value) end
    ns.Bus.Fire("SettingsChanged", key, value)
    return true
end

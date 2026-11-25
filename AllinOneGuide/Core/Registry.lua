-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Feature-state service and module registry.
--   ns.Feature.Set(name, state, reason)  state: "on", "off" (by the player), "api" (game API missing),
--                                         "errors" (turned itself off), "safe" (safe mode), "addon" (needs an addon)
--   ns.Feature.IsOn(name)                 unknown features count as on
-- Modules (advisors later) register name, layer, needs, events and Load / Unload. "Unload" frees data
-- only: WoW can't unload code. Load runs only out of combat (queued until combat ends).
local _, ns = ...

local F = { states = {}, reasons = {} }
ns.Feature = F

function F.Set(name, state, reason)
    if F.states[name] == state and F.reasons[name] == reason then return end
    F.states[name], F.reasons[name] = state, reason
    if ns.Bus then ns.Bus.Fire("FeatureChanged", name, state) end
end

function F.Get(name)
    return F.states[name] or "on", F.reasons[name]
end

function F.IsOn(name)
    local s = F.states[name]
    return s == nil or s == "on"
end

-- "questlog=on facing=api ..." sorted, for /aog status (only the ones that are not on, plus a count).
function F.Summary()
    local names, off = {}, {}
    for n in pairs(F.states) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        if F.states[n] ~= "on" then off[#off + 1] = n .. "=" .. F.states[n] end
    end
    return #names - #off, off
end

-- ------------------------------------------------------------------ module registry
-- Layers: a module may only need modules of a lower or equal layer.
local LAYERS = { core = 1, data = 2, engine = 3, ui = 4, module = 5 }
local R = { modules = {}, order = {}, pending = {} }
ns.Modules = R
R.LAYERS = LAYERS

function R.Register(def)
    assert(type(def) == "table" and type(def.name) == "string", "module needs a name")
    assert(not R.modules[def.name], "module registered twice: " .. def.name)
    local layer = LAYERS[def.layer or "module"]
    assert(layer, "unknown layer for " .. def.name)
    for _, need in ipairs(def.needs or {}) do
        local other = R.modules[need]
        assert(other, def.name .. " needs " .. need .. ", which isn't registered before it")
        assert(LAYERS[other.layer or "module"] <= layer, def.name .. " may not need the higher layer module " .. need)
    end
    def.loaded = false
    R.modules[def.name] = def
    R.order[#R.order + 1] = def.name
    return def
end

-- Loads a module (its data). Out of combat only; in combat it waits for PLAYER_REGEN_ENABLED.
function R.Load(name)
    local m = R.modules[name]
    if not m or m.loaded then return m ~= nil end
    if ns.safeMode then F.Set(name, "safe", "safe mode") return false end
    if ns.Compat.InCombat() then
        R.pending[name] = true
        ns.Events.On("PLAYER_REGEN_ENABLED", R, R.RunPending, "core")
        return false
    end
    for _, need in ipairs(m.needs or {}) do R.Load(need) end
    local ok = true
    if m.Load then ok = ns.Errors.Call(name, m.Load, m) end
    m.loaded = ok and true or false
    return m.loaded
end

function R.RunPending()
    ns.Events.Off("PLAYER_REGEN_ENABLED", R)
    local list = {}
    for n in pairs(R.pending) do list[#list + 1] = n end
    table.sort(list)
    R.pending = {}
    for _, n in ipairs(list) do R.Load(n) end
end

function R.Unload(name)
    local m = R.modules[name]
    if not m or not m.loaded then return end
    if m.Unload then ns.Errors.Call(name, m.Unload, m) end
    m.loaded = false
end

function R.CountLoaded()
    local n = 0
    for _, m in pairs(R.modules) do if m.loaded then n = n + 1 end end
    return n
end

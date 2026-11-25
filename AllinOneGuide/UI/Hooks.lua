-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Every hook on Blizzard code lives here (v0.2 M3). We only ever add to Blizzard's functions and
-- scripts: hooksecurefunc (runs after the original, never replaces it) and HookScript. Nothing here
-- assigns to a Blizzard global or a Blizzard frame's method; an offline test fails if anything in the
-- addon does. Each hook body runs under ns.Errors.Call, so an error in ours never reaches Blizzard's code.
--   ns.Hooks.Func(table or nil, name, fn, feature)   hooksecurefunc on a table's function (nil = global)
--   ns.Hooks.Script(frame, script, fn, feature)       frame:HookScript
--   ns.Hooks.TooltipPost(tooltipType, fn, feature)    TooltipDataProcessor.AddTooltipPostCall
--   ns.Hooks.mapOpen: the world map is shown (bus WorldMapShown / WorldMapHidden)
local _, ns = ...
local Co = ns.Compat
local H = { list = {}, mapOpen = false }
ns.Hooks = H

local function Key(target, name) return tostring(target) .. "." .. tostring(name) end

-- Hooks a function once (a second call with the same target and name does nothing). false when it can't.
function H.Func(tbl, name, fn, feature)
    local hook = Co.fn.hooksecurefunc
    if not hook or type(name) ~= "string" or type(fn) ~= "function" then return false end
    local target = tbl or _G
    if type(target) ~= "table" or type(target[name]) ~= "function" then return false end
    local key = Key(target, name)
    if H.list[key] then return true end
    local body = function(...) ns.Errors.Call(feature or "ui", fn, ...) end
    if tbl then hook(tbl, name, body) else hook(name, body) end
    H.list[key] = { kind = "func", name = name }
    return true
end

-- Adds to a frame's script once. false when it can't.
function H.Script(frame, script, fn, feature)
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" or type(fn) ~= "function" then return false end
    local key = Key(frame, script)
    if H.list[key] then return true end
    frame:HookScript(script, function(...) ns.Errors.Call(feature or "ui", fn, ...) end)
    H.list[key] = { kind = "script", name = script }
    return true
end

-- Adds a post-call for one tooltip data type (TooltipDataProcessor.AddTooltipPostCall, the public way to add
-- to Blizzard's tooltips; insecure callers are forced insecure by Blizzard's delegate, TooltipDataHandler.lua
-- 181-193). Once per type; post-calls can't be removed, so fn must check its own switch. false when it can't.
function H.TooltipPost(tooltipType, fn, feature)
    local add = Co.fn.TipPostCall
    if not add or tooltipType == nil or type(fn) ~= "function" then return false end
    local key = "TooltipDataProcessor.post." .. tostring(tooltipType)
    if H.list[key] then return true end
    add(tooltipType, function(...) ns.Errors.Call(feature or "ui", fn, ...) end)
    H.list[key] = { kind = "tooltip", name = key }
    return true
end

function H.Count()
    local n = 0
    for _ in pairs(H.list) do n = n + 1 end
    return n
end

-- ------------------------------------------------------------------ the hooks we use
-- The world map: the arrow hides while it's open; the map pins refresh when it opens.
local function HookWorldMap()
    local wm = Co.fn.WorldMapFrame or Co.Resolve("WorldMapFrame")
    if type(wm) ~= "table" then return false end
    H.mapOpen = wm.IsShown and wm:IsShown() == true or false
    H.Script(wm, "OnShow", function()
        H.mapOpen = true
        ns.Bus.Fire("WorldMapShown")
    end, "ui")
    H.Script(wm, "OnHide", function()
        H.mapOpen = false
        ns.Bus.Fire("WorldMapHidden")
    end, "ui")
    return true
end
H.HookWorldMap = HookWorldMap

ns.Bus.On("Login", H, function() HookWorldMap() end, "ui", 50)

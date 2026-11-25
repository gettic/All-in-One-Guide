-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Link with Gear Set (the user's other addon, folder "GearSet"), base part (v0.1.1, T124 / T125):
--   * checked at PLAYER_LOGIN only (Gear Set is in the .toc's OptionalDeps, so it has loaded by then)
--   * the "Link with Gear Set" setting shows in the title menu only when Gear Set is loaded
--   * missing Gear Set = nothing shows, nothing breaks; the state is in the self-test info
-- Gear Set talks to us through AllinOneGuide.API (Core\API.lua); "Guide me to this piece" (PointTo)
-- comes in v0.2 M3. Nothing here reads Gear Set's data or calls into it.
local _, ns = ...
local GSL = { FOLDER = "GearSet", present = false }
ns.GearSet = GSL

function GSL.Present() return GSL.present end

-- "missing" | "on" | "off"
function GSL.State()
    if not GSL.present then return "missing" end
    return ns.Settings.Get("gearSetLink") and "on" or "off"
end

function GSL.Linked() return GSL.State() == "on" end

local function Update()
    if not GSL.present then return end
    ns.Feature.Set("gearset", GSL.Linked() and "on" or "off", not GSL.Linked() and "turned off" or nil)
end

ns.Bus.On("Login", GSL, function()
    GSL.present = ns.Compat.IsAddOnLoaded(GSL.FOLDER)
    Update()
end, "gearset", 50)

ns.Bus.On("SettingsChanged", GSL, function(_, key)
    if key == "gearSetLink" then Update() end
end, "gearset")

-- title-menu entry (nil when Gear Set isn't loaded)
function GSL.MenuItem()
    if not GSL.present then return nil end
    local S = ns.Settings
    return { text = ns.L.MENU_GEARSET, checked = S.Get("gearSetLink"),
        fn = function() S.Set("gearSetLink", not S.Get("gearSetLink")) end }
end

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "gearset", fn = function(h)
    h.Count()
    h.Info("gear set link: " .. GSL.State())
end }

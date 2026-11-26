-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Key bindings (Bindings.xml): the names Blizzard's key binding page shows come from BINDING_HEADER_* /
-- BINDING_NAME_* globals (the binding format: Blizzard_Commentator\Bindings.xml and the BINDING_HEADER_
-- globals in the 1.60.1 UI source). The addon never sets a key itself; the player picks them.
-- The XML bodies call AllinOneGuide.Binding("<action>"); the step item key clicks the secure step button
-- directly (CLICK AllinOneGuideStepButton:LeftButton), so it works in combat.
local _, ns = ...
local Ky = {}
ns.Keys = Ky

Ky.ACTIONS = {
    toggle = function() ns.UI.Toggle() end,
    next = function() ns.Engine.Next() end,
    back = function() ns.Engine.Back() end,
    skip = function() ns.Engine.Skip() end,
    arrow = function() ns.Settings.Set("arrow", not ns.Settings.Get("arrow")) end,
    menu = function()
        if not ns.UI.IsShown() then ns.UI.Show() end
        local tb = ns.UI.title
        if tb and tb.menu then
            if ns.Menu.IsOpen() then ns.Menu.Close() else ns.Menu.Open(tb.menu, ns.UI.MenuItems(), { right = true }) end
        end
    end,
}

-- binding name (without BINDING_NAME_) -> locale key
Ky.NAMES = {
    ALLINONEGUIDE_TOGGLE = "KEY_TOGGLE",
    ALLINONEGUIDE_NEXT = "KEY_NEXT",
    ALLINONEGUIDE_BACK = "KEY_BACK",
    ALLINONEGUIDE_SKIP = "KEY_SKIP",
    ALLINONEGUIDE_ARROW = "KEY_ARROW",
    ALLINONEGUIDE_MENU = "KEY_MENU",
    ["CLICK AllinOneGuideStepButton:LeftButton"] = "KEY_ITEM",
    ["CLICK AllinOneGuideTargetButton:LeftButton"] = "KEY_TARGET",
}

function Ky.Run(action)
    local fn = Ky.ACTIONS[action]
    if not fn or ns.safeMode then return false end
    ns.Errors.Call("ui", fn)
    return true
end

-- The binding globals (in the chosen language). Set at load, before Blizzard's key binding page reads them.
function Ky.SetNames()
    _G.BINDING_HEADER_ALLINONEGUIDE = ns.TITLE
    for name, key in pairs(Ky.NAMES) do _G["BINDING_NAME_" .. name] = ns.L[key] end
end
Ky.SetNames()
ns.Bus.On("Login", Ky, Ky.SetNames, "ui", 10)

AllinOneGuide.Binding = Ky.Run

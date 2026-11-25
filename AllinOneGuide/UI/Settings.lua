-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Settings entry points (2026-11-25, main window plan): every setting lives on the main window's Settings
-- pages (UI\HubSettings.lua). Blizzard's Options > AddOns keeps one entry for us with a single button "Open
-- All-in-One Guide" that only shows our window (tos: registered once at Login; its click never touches
-- Blizzard's frames: no HideUIPanel, no SettingsPanel:Close()). No proxy settings any more.
-- Settings API checked in the UI source 1.60.1.70959: Blizzard_Settings_Shared\Blizzard_Settings.lua
-- (RegisterVerticalLayoutCategory, RegisterAddOnCategory), Blizzard_SettingControls.lua
-- (CreateSettingsButtonInitializer: addSearchTags must not be nil).
-- Missing API: no entry there; /aog config and the menus open the main window all the same.
--   ns.SettingsUI.Build(), .Open(page), .Available(), .SetFromPanel(d, v), .Tooltip(d), .category / .button
local _, ns = ...
local Co = ns.Compat
local SU = { built = false }
ns.SettingsUI = SU

local function L() return ns.L end
local F = Co.fn

-- Our settings can be shown (the main window works here).
function SU.Available()
    return ns.Hub ~= nil and ns.Hub.Available()
end

-- The tooltip: the setting's line and its default ("Default: on").
function SU.Tooltip(d)
    return (L()[d.tip] or "") .. "\n" .. ns.U.Fill(L().SET_DEFAULT, { value = ns.Settings.DefaultText(d) })
end

-- A value from a control: rounded to the slider step, the language through /aog lang (asks to reload).
function SU.SetFromPanel(d, v)
    local S = ns.Settings
    if d.kind == "number" then
        v = tonumber(v)
        if not v then return end
        local step = d.step or 1
        v = math.floor((v - d.min) / step + 0.5) * step + d.min
        v = math.max(d.min, math.min(d.max, tonumber(("%.4f"):format(v))))
    end
    if d.key == "lang" then
        if v ~= S.Get("lang") then ns.Locale.Switch(v) end
    else
        S.Set(d.key, v)
    end
end

-- Registers our one entry in Options > AddOns (once per session, at Login). true when it's there.
function SU.Build()
    if SU.built then return SU.category ~= nil end
    SU.built = true
    if ns.safeMode or not ns.Feature.IsOn("settings") then return false end
    local cat, layout = F.SetRegCat(ns.TITLE)
    if not cat then return false end
    SU.category = cat
    local make = F.SetButtonInit
    if make and layout and layout.AddInitializer then
        -- addSearchTags = false: not in the options search
        SU.button = make(L().SETTINGS_OPEN_LABEL, L().SETTINGS_OPEN_BUTTON,
            function() ns.Errors.Call("ui", SU.Open) end, L().TIP_SETTINGS_OPEN, false)
        layout:AddInitializer(SU.button)
    end
    F.SetRegAddOn(cat)
    return true
end

-- /aog config, the menus, Blizzard's button: the main window on a Settings page (General by default).
-- Without the main window (safe mode, feature off): the title menu, which has the switches.
function SU.Open(page)
    if SU.Available() then
        return ns.Hub.Open("set." .. (page or "general"))
    end
    ns.UI.Show()
    ns.Menu.Open(ns.UI.title.menu, ns.UI.MenuItems(), { right = true })
    ns.Print(L().SETTINGS_FALLBACK)
    return false
end

-- Self-test: every setting on a page that's built has its control showing the saved value; names and tips.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "settings", fn = function(h)
    h.Count()
    local HS, Hub = ns.HubSettings, ns.Hub
    local missing, wrong, n, built = 0, 0, 0, 0
    for _, d in ipairs(ns.Settings.schema) do
        if d.page then
            n = n + 1
            if type(ns.L[d.label]) ~= "string" or type(ns.L[d.tip]) ~= "string" then missing = missing + 1 end
            local p = Hub and Hub.pages["set." .. d.page]
            if not p then
                h.Problem("settings: no page for " .. d.key)
            elseif p.child then
                built = built + 1
                local c = HS and HS.controls[d.key]
                if not c then
                    h.Problem("settings: no control for " .. d.key)
                elseif c.ctl.on ~= nil or c.ctl.v ~= nil then
                    local shown = c.ctl.on
                    if shown == nil then shown = c.ctl.v end
                    if shown ~= ns.Settings.Shown(d.key) then wrong = wrong + 1 end
                end
            end
        end
    end
    if missing > 0 then h.Problem("settings: " .. missing .. " names or tips missing") end
    if wrong > 0 then h.Problem("settings: " .. wrong .. " controls show another value") end
    h.Info(("settings: %d on %d pages (%d on built pages)%s"):format(n, #ns.Settings.PAGES, built,
        SU.category and ", Options button" or ""))
end }

ns.Bus.On("Login", SU, function() ns.Errors.Call("ui", SU.Build) end, "ui", 90)
ns.Slash.Add("config", function() SU.Open() end, "HELP_CONFIG", { main = true })

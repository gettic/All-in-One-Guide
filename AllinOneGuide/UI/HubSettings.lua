-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The main window's Settings pages (2026-11-25; they replace the settings in Blizzard's Options > AddOns, which
-- keeps one button that opens them: UI\Settings.lua). One page per ns.Settings.PAGES entry ("set.<page>",
-- in the "settings" group), built from the schema: a tick box, slider or drop-down per setting with its name,
-- a dim help line (SETTIP_*) and the default in the tooltip; "Reset this page" at the end; Advanced also
-- "Reset window positions" (asks first). All our own plain controls (UI\Kit.lua; tos: no Blizzard templates).
--   ns.HubSettings.Set(d, v), .Refresh(page), .Build(page, parent, width), .controls[key], .resets[page]
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local HS = { controls = {}, resets = {}, ORDER = 21 }
ns.HubSettings = HS

local function L() return ns.L end

-- A value from a control: sliders round to their step, the language goes through /aog lang (asks to reload).
function HS.Set(d, v)
    ns.SettingsUI.SetFromPanel(d, v)
    HS.Show(d)
end

-- One control shows the saved value.
function HS.Show(d)
    local c = HS.controls[d.key]
    if not c then return end
    -- (a change waiting for the end of combat shows its new value, not the old one)
    c.ctl:Set(ns.Settings.Shown(d.key))
end

local function HelpLine(parent, width, text)
    local fs = K.Text(parent, "goal", "text.dim")
    fs:SetWordWrap(true)
    fs:SetWidth(width)
    fs:SetText(text or "")
    return fs
end

-- One setting's row; returns its height.
local function Row(parent, width, y, d)
    local tip = ns.SettingsUI.Tooltip(d)
    local c = { kind = d.kind, d = d }
    local labelText = L()[d.label] or d.key
    local helpX = 0
    if d.kind == "bool" then
        c.ctl = K.Choice(parent, labelText, function(self) HS.Set(d, not self.on) end, false, "hub")
        c.ctl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        c.ctl:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        helpX = Th.Size("box") + 8
    else
        c.label = K.Text(parent, "step", "text")
        c.label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + 4))
        c.label:SetText(labelText)
        if d.kind == "number" then
            c.ctl = K.Slider(parent, d, function(v) HS.Set(d, v) end, "hub")
        else
            c.ctl = K.Dropdown(parent, d, function(v) HS.Set(d, v) end, "hub")
        end
        c.ctl:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
        c.label:SetPoint("RIGHT", c.ctl, "LEFT", -8, 0)
    end
    c.ctl:HookScript("OnEnter", function(self) K.Tooltip(self, labelText, { tip }) end)
    c.ctl:HookScript("OnLeave", K.HideTooltip)
    local rowH = math.max(c.ctl:GetHeight() or 0, Th.LineHeight("step") + 4)
    c.help = HelpLine(parent, width - helpX, L()[d.tip] or "")
    c.help:SetPoint("TOPLEFT", parent, "TOPLEFT", helpX, -(y + rowH))
    local helpH = math.max(Th.LineHeight("goal"), c.help:GetStringHeight() or 0)
    HS.controls[d.key] = c
    HS.Show(d)
    return rowH + helpH + 10
end

local function ResetRow(parent, y, label, fn)
    local t = K.Text(parent, "step", "text")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + 6))
    t:SetText(label)
    local b = K.Button(parent, L().SET_RESET_BUTTON, fn, { feature = "hub" })
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
    t:SetPoint("RIGHT", b, "LEFT", -8, 0)
    return b, (b:GetHeight() or 24) + 8
end

function HS.Build(page, parent, width)
    local y = 0
    for _, d in ipairs(ns.Settings.Page(page)) do y = y + Row(parent, width, y, d) end
    -- a hair line, then the reset row(s)
    local line = K.Fill(parent, "ARTWORK", "divider")
    line:SetHeight(K.Hair(1))
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
    y = y + 8
    local resets = {}
    local b, h = ResetRow(parent, y, L().SET_RESET_PAGE, function()
        ns.Settings.ResetPage(page)
        HS.Refresh(page)
    end)
    resets[1] = b
    y = y + h
    if page == "advanced" then
        b, h = ResetRow(parent, y, L().SET_RESETPOS, function()
            ns.Popups.Confirm({ kind = "resetpos", text = L().DIALOG_RESETPOS, accept = function() ns.UI.ResetPos() end })
        end)
        resets[2] = b
        y = y + h
    end
    HS.resets[page] = resets
    return y + 4
end

-- Every control on a page shows its saved value again.
function HS.Refresh(page)
    for _, d in ipairs(ns.Settings.Page(page)) do HS.Show(d) end
end

for i, page in ipairs(ns.Settings.PAGES) do
    ns.Hub.AddPage("set." .. page, { title = "PAGE_" .. page:upper(), group = "settings", order = HS.ORDER + i,
        build = function(parent, width) return HS.Build(page, parent, width) end,
        refresh = function() HS.Refresh(page) end })
end

-- A value changed somewhere else (title menu, a key, a reset): the open page shows it.
ns.Bus.On("SettingsChanged", HS, function(_, key)
    local d = ns.Settings.byKey[key]
    if d then HS.Show(d) end
end, "hub", 90)
-- a rebuilt page (look change) makes new controls
ns.Bus.On("LookChanged", HS, function() HS.controls, HS.resets = {}, {} end, "hub", 79)

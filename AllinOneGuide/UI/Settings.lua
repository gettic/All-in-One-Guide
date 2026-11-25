-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M4: the settings panel in Blizzard's Options > AddOns, built from the schema (DB\Settings.lua).
-- Pages: General (the main category), Guide window, Arrow, Map, Advanced (subcategories); each page ends
-- with "Reset this page", Advanced also has "Reset window positions" (asks first).
-- Settings API checked in the UI source 1.60.1.70959: Blizzard_Settings_Shared\Blizzard_Settings.lua
-- (RegisterVerticalLayoutCategory / Subcategory, RegisterAddOnCategory, RegisterProxySetting (name,
-- variable and type are checked there: the default must have the variable's type), CreateCheckbox /
-- CreateSlider / CreateDropdown, CreateSliderOptions, CreateControlTextContainer, OpenToCategory, VarType),
-- Blizzard_SettingControls.lua (CreateSettingsButtonInitializer: addSearchTags must not be nil),
-- Blizzard_SharedXML\Shared\Slider\MinimalSlider.lua (MinimalSliderWithSteppersMixin.Label.Right).
-- Missing API (feature "settings" off): /aog config and the title menu's "Settings" row open the title
-- menu instead (every switch is there or in /aog).
--   ns.SettingsUI.Build(), .Open(), .Available(), .SetFromPanel(d, v), .category / .pages / .settings
local _, ns = ...
local Co, U = ns.Compat, ns.U
local SU = { built = false, pages = {}, settings = {}, PREFIX = "AllinOneGuide_" }
ns.SettingsUI = SU

local function L() return ns.L end
local F = Co.fn

local VARTYPE = { bool = "boolean", number = "number", choice = "string" }

function SU.Available()
    return ns.Feature.IsOn("settings") and not ns.safeMode
end

-- The tooltip: the setting's line and its default ("Default: on").
function SU.Tooltip(d)
    return (L()[d.tip] or "") .. "\n" .. U.Fill(L().SET_DEFAULT, { value = ns.Settings.DefaultText(d) })
end

-- A value from the panel: rounded to the slider step, the language through /aog lang (asks to reload).
function SU.SetFromPanel(d, v)
    local S = ns.Settings
    if d.kind == "number" then
        v = tonumber(v)
        if not v then return end
        local step = d.step or 1
        v = math.floor((v - d.min) / step + 0.5) * step + d.min
        v = math.max(d.min, math.min(d.max, tonumber(("%.4f"):format(v))))
    end
    SU.fromPanel = true
    if d.key == "lang" then
        if v ~= S.Get("lang") then ns.Locale.Switch(v) end
    else
        S.Set(d.key, v)
    end
    SU.fromPanel = nil
end

local function ChoiceOptions(d)
    return function()
        local c = F.SetTextContainer()
        for _, v in ipairs(d.choices) do
            local key = d.choiceLabels and d.choiceLabels[v]
            c:Add(v, key and L()[key] or tostring(v))
        end
        return c:GetData()
    end
end

local function Control(cat, d)
    local S = ns.Settings
    local setting = F.SetProxy(cat, SU.PREFIX .. d.key, VARTYPE[d.kind], L()[d.label] or d.key, d.default,
        function() return S.Get(d.key) end,
        function(v) ns.Errors.Call("ui", SU.SetFromPanel, d, v) end)
    SU.settings[d.key] = setting
    local tip = SU.Tooltip(d)
    if d.kind == "bool" then
        F.SetCheckbox(cat, setting, tip)
    elseif d.kind == "number" then
        local opts = F.SetSliderOptions(d.min, d.max, d.step or 1)
        local mixin = Co.Resolve("MinimalSliderWithSteppersMixin")
        local right = type(mixin) == "table" and type(mixin.Label) == "table" and mixin.Label.Right
        if right and type(opts.SetLabelFormatter) == "function" then
            opts:SetLabelFormatter(right, function(v) return S.NumberText(d, v) end)
        end
        F.SetSlider(cat, setting, opts, tip)
    else
        F.SetDropdown(cat, setting, ChoiceOptions(d), tip)
    end
    return setting
end

local function Button(layout, label, buttonText, fn, tip)
    local make = F.SetButtonInit
    if not (make and layout and layout.AddInitializer) then return nil end
    -- addSearchTags = false: these buttons don't show up in the options search
    local init = make(label, buttonText, function() ns.Errors.Call("ui", fn) end, tip, false)
    layout:AddInitializer(init)
    return init
end

local function Page(cat, layout, page)
    SU.pages[page] = { category = cat, layout = layout, controls = 0 }
    for _, d in ipairs(ns.Settings.Page(page)) do
        Control(cat, d)
        SU.pages[page].controls = SU.pages[page].controls + 1
    end
    Button(layout, L().SET_RESET_PAGE, L().SET_RESET_BUTTON, function() ns.Settings.ResetPage(page) end, L().SETTIP_RESET_PAGE)
    if page == "advanced" then
        Button(layout, L().SET_RESETPOS, L().SET_RESET_BUTTON, function()
            ns.Popups.Confirm({ kind = "resetpos", text = L().DIALOG_RESETPOS, accept = function() ns.UI.ResetPos() end })
        end, L().SETTIP_RESETPOS)
    end
end

-- Registers the category and its pages once per session (after login). true when the panel is there.
function SU.Build()
    if SU.built then return SU.category ~= nil end
    SU.built = true
    if not SU.Available() then return false end
    local cat, layout = F.SetRegCat(ns.TITLE)
    if not cat then return false end
    SU.category = cat
    Page(cat, layout, "general")
    for _, page in ipairs(ns.Settings.PAGES) do
        if page ~= "general" then
            local sub, subLayout = F.SetRegSub(cat, L()["PAGE_" .. page:upper()])
            if sub then Page(sub, subLayout, page) end
        end
    end
    F.SetRegAddOn(cat)
    return true
end

-- A value changed somewhere else (title menu, a key, a reset): the open panel shows it.
ns.Bus.On("SettingsChanged", SU, function(_, key)
    if SU.fromPanel then return end
    local st = SU.settings[key]
    if st and type(st.NotifyUpdate) == "function" then pcall(st.NotifyUpdate, st) end
end, "ui", 90)

-- /aog config, the title menu row, the minimap button's menu.
function SU.Open()
    if Co.InCombat() then
        ns.Print(L().SETTINGS_COMBAT)
        return false
    end
    local ok, built = ns.Errors.Call("ui", SU.Build)
    if ok and built and SU.category then
        local id = SU.category.GetID and SU.category:GetID() or SU.category.ID
        F.SetOpen(id)
        return true
    end
    -- no settings panel on this client: the title menu has the switches
    ns.UI.Show()
    ns.Menu.Open(ns.UI.title.menu, ns.UI.MenuItems(), { right = true })
    ns.Print(L().SETTINGS_FALLBACK)
    return false
end

-- Self-test: the panel has a control for every page setting (or the fallback is in use), every name and
-- tip exists, the values it shows are the saved ones.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "settings", fn = function(h)
    h.Count()
    local missing, wrong, n = 0, 0, 0
    for _, d in ipairs(ns.Settings.schema) do
        if d.page then
            n = n + 1
            if type(ns.L[d.label]) ~= "string" or type(ns.L[d.tip]) ~= "string" then missing = missing + 1 end
            local st = SU.settings[d.key]
            if SU.category and not st then
                h.Problem("settings: no control for " .. d.key)
            elseif st and type(st.GetValue) == "function" then
                local ok, v = pcall(st.GetValue, st)
                if not ok or v ~= ns.Settings.Get(d.key) then wrong = wrong + 1 end
            end
        end
    end
    if missing > 0 then h.Problem("settings: " .. missing .. " names or tips missing") end
    if wrong > 0 then h.Problem("settings: " .. wrong .. " controls show another value") end
    h.Info(SU.category and ("settings panel: %d settings"):format(n) or "settings panel: not available (menu and /aog instead)")
end }

ns.Bus.On("Login", SU, function() ns.Errors.Call("ui", SU.Build) end, "ui", 90)
ns.Slash.Add("config", function() SU.Open() end, "HELP_CONFIG", { main = true })

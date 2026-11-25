-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M4: the minimap button, the Addon Compartment entry and (only when another addon already loaded
-- one) a data-broker launcher. We ship no library.
--   button: our own art (media\minimap.tga, full colour), on the minimap's ring; drag moves it around the
--     ring (angle saved, setting minimapAngle); left-click shows / hides the guide, right-click opens the
--     main window (a small menu without it); dimmed while the guide window is hidden; hidden with the setting `minimap`
--     (/aog minimap brings it back)
--   Addon Compartment: the .toc names three global functions (Blizzard_Minimap\Mainline\
--     AddonCompartment.lua:106-131 calls them as (addonName, buttonName) / (addonName, button))
--   broker: LibStub("LibDataBroker-1.1", true) at login; a "launcher" object when it's there
--   ns.MinimapButton.Build/Place/Angle/Click/MenuItems/Tip/Update/Broker, .frame, .broker
local _, ns = ...
local Th, Co, K = ns.Theme, ns.Compat, ns.UIKit
local MM = { SIZE = 31, RING = 10 }
ns.MinimapButton = MM

local function L() return ns.L end
local function Map() return Co.fn.MinimapButton end

-- Distance from the minimap's centre to the button's centre (just outside the round minimap).
function MM.Radius()
    local m = Map()
    local w = m and m:GetWidth() or 140
    return w / 2 + MM.RING
end

function MM.Place(angle)
    local f, m = MM.frame, Map()
    if not (f and m) then return end
    local a = math.rad(angle or ns.Settings.Get("minimapAngle"))
    local r = MM.Radius()
    f:ClearAllPoints()
    f:SetPoint("CENTER", m, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- The angle (0-360, 0 = east, counter-clockwise) from the minimap's centre to the cursor; nil when unknown.
function MM.Angle()
    local m = Map()
    if not m then return nil end
    local cx, cy = Co.Cursor(m)
    local mx, my = m:GetCenter()
    if not (cx and mx) then return nil end
    local dx, dy = cx - mx, cy - my
    if dx == 0 and dy == 0 then return nil end
    local a = math.deg(math.atan2(dy, dx)) % 360
    return math.floor(a + 0.5) % 360
end

local function DragUpdate()
    local a = MM.Angle()
    if a then
        MM.dragAngle = a
        MM.Place(a)
    end
end

-- The tooltip lines (the button, the compartment and the broker show the same).
function MM.Tip()
    return ns.TITLE, { L().MINIMAP_LEFT, L().MINIMAP_RIGHT, L().MINIMAP_DRAG }
end

function MM.MenuItems()
    local S = ns.Settings
    local items = {}
    items[#items + 1] = { text = L().MENU_ARROW, checked = S.Get("arrow"), fn = function() S.Set("arrow", not S.Get("arrow")) end }
    items[#items + 1] = { text = L().MENU_LOCK, checked = S.Get("locked"), fn = function() S.Set("locked", not S.Get("locked")) end }
    items[#items + 1] = { text = L().MENU_MINIMAP_HIDE, fn = function()
        S.Set("minimap", false)
        ns.Print(L().MINIMAP_HIDDEN)
    end }
    return items
end

-- Left: show / hide the guide. Right: opens / closes the main window (2026-11-25; "Hide this button" is
-- Settings > General there). Without the main window: the small menu (on the button) or the title menu.
function MM.Click(button, anchor)
    if button == "RightButton" then
        if ns.Hub and ns.Hub.Available() then
            ns.Hub.Toggle()
        elseif anchor then
            ns.Menu.Open(anchor, MM.MenuItems())
        else
            ns.SettingsUI.Open()
        end
    else
        ns.UI.Toggle()
    end
end

-- The look: dim while the guide window is hidden.
function MM.Update()
    local f = MM.frame
    if not f then return end
    f:SetShown(ns.Settings.Get("minimap"))
    f.icon:SetVertexColor(Th.Color(ns.UI.IsShown() and "minimap" or "minimapDim"))
end

function MM.Build()
    if MM.frame or ns.safeMode or not ns.Feature.IsOn("minimap") then return MM.frame end
    local m = Map()
    local f = CreateFrame("Button", nil, m)
    MM.frame = f
    f:SetSize(MM.SIZE, MM.SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel((m:GetFrameLevel() or 1) + 8)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    Th.Glyph(f.icon, "minimap")
    f.hl = f:CreateTexture(nil, "HIGHLIGHT")
    f.hl:SetAllPoints()
    Th.Glyph(f.hl, "minimap")
    f.hl:SetBlendMode("ADD")
    f.hl:SetAlpha(Th.Alpha("hover", 0.35))
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnClick", function(self, button) ns.Errors.Call("minimap", MM.Click, button, self) end)
    f:SetScript("OnDragStart", function(self)
        MM.dragAngle = nil
        self:SetScript("OnUpdate", function() ns.Errors.Call("minimap", DragUpdate) end)
    end)
    f:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if MM.dragAngle then ns.Settings.Set("minimapAngle", MM.dragAngle) end
    end)
    f:SetScript("OnEnter", function(self) K.Tooltip(self, MM.Tip()) end)
    f:SetScript("OnLeave", function() K.HideTooltip() end)
    MM.Place()
    MM.Update()
    return f
end

-- A data-broker launcher when another addon has LibDataBroker loaded (nothing of ours is shipped).
function MM.Broker()
    if MM.broker then return MM.broker end
    local stub = Co.Resolve("LibStub")
    if stub == nil then return nil end
    local ok, ldb = pcall(stub, "LibDataBroker-1.1", true)
    if not ok or type(ldb) ~= "table" or type(ldb.NewDataObject) ~= "function" then return nil end
    local file = ns.Media.Get("tex.minimap")
    local ok2, obj = pcall(ldb.NewDataObject, ldb, ns.TITLE, {
        type = "launcher",
        label = ns.TITLE,
        icon = file,
        OnClick = function(_, button) ns.Errors.Call("minimap", MM.Click, button) end,
        OnTooltipShow = function(tip)
            if not (tip and tip.AddLine) then return end
            local title, lines = MM.Tip()
            tip:AddLine(title)
            local r, g, b = Th.Color("text.dim")   -- the same as K.Tooltip's lines
            for _, l in ipairs(lines) do tip:AddLine(l, r, g, b) end
        end,
    })
    if ok2 and type(obj) == "table" then MM.broker = obj end
    return MM.broker
end

-- Addon Compartment (names in AllinOneGuide_Forever.toc). Globals by necessity: Blizzard calls them by name.
function AllinOneGuide_OnCompartmentClick(_, buttonName)
    ns.Errors.Call("minimap", MM.Click, buttonName)
end
function AllinOneGuide_OnCompartmentEnter(_, button)
    if button then K.Tooltip(button, MM.Tip()) end
end
function AllinOneGuide_OnCompartmentLeave()
    K.HideTooltip()
end

-- Self-test: the button sits on the ring when it's on; the .toc's compartment names are our functions.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "minimap", fn = function(h)
    h.Count()
    for _, field in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }) do
        local name = Co.AddOnMeta(ns.ADDON, field)
        if name and type(Co.Resolve(name)) ~= "function" then h.Problem("minimap: " .. field .. " has no function") end
    end
    local f, m = MM.frame, Map()
    if ns.Settings.Get("minimap") and ns.Feature.IsOn("minimap") and not ns.safeMode then
        if not f then return h.Problem("minimap: button not built") end
        local bx, by = f:GetCenter()
        local mx, my = m:GetCenter()
        if bx and mx then
            local d = math.sqrt((bx - mx) ^ 2 + (by - my) ^ 2)
            if math.abs(d - MM.Radius()) > 2 then h.Problem(("minimap: button off the ring (%d)"):format(d)) end
        end
    end
    h.Info(("minimap: button %s, broker %s"):format(f and (f:IsShown() and "shown" or "hidden") or "none",
        MM.broker and "yes" or "no"))
end }

ns.Bus.On("Login", MM, function()
    ns.Errors.Call("minimap", MM.Build)
    ns.Errors.Call("minimap", MM.Broker)
end, "ui", 85)
ns.Bus.On("SettingsChanged", MM, function(_, key)
    if key == "minimap" then
        if ns.Settings.Get("minimap") then ns.Errors.Call("minimap", MM.Build) end
        MM.Update()
    elseif key == "minimapAngle" then
        MM.Place()
    end
end, "ui", 80)
ns.Bus.On("WindowToggled", MM, function() MM.Update() end, "ui", 80)

ns.Slash.Add("minimap", function()
    ns.Settings.Set("minimap", not ns.Settings.Get("minimap"))
end, "HELP_MINIMAP")

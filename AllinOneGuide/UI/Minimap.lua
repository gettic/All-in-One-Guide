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
--   shape: follows GetMinimapShape() from minimap addons (square, corner, side, tricorner maps), see MM.SHAPES
--   ns.MinimapButton.Build/Place/Offset/Shape/Radius/Angle/Click/MenuItems/Tip/Update/Broker, .frame, .broker
local _, ns = ...
local Th, Co, K = ns.Theme, ns.Compat, ns.UIKit
local MM = { SIZE = 31, RING = 10 }
ns.MinimapButton = MM

local function L() return ns.L end
local function Map() return Co.fn.MinimapButton end

-- Minimap shapes (2026-11-25 fix: "the minimap button dont work with my own minimap addon"). Minimap addons that
-- make the map square (or another shape) define the global GetMinimapShape(), the long-standing convention every
-- minimap button follows; Blizzard's own UI doesn't define it (then the map is round). It is looked up each time
-- (the other addon may load after us) and called in pcall (it's another addon's code). Not in ApiList: it's no
-- Blizzard API, and the self-test's "not secure" check would flag every addon that defines it.
-- Per shape, which quarter of the map is round: 1 = bottom-right, 2 = bottom-left, 3 = top-right, 4 = top-left.
-- A square quarter keeps the button on the edge of the square (the corner is clamped).
MM.SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- The minimap's shape name ("ROUND" when no addon says otherwise, or it answers something unknown).
function MM.Shape()
    local fn = Co.Resolve("GetMinimapShape")
    if type(fn) ~= "function" then return "ROUND" end
    local ok, shape = pcall(fn)
    if ok and type(shape) == "string" and MM.SHAPES[shape] then return shape end
    return "ROUND"
end

-- Half width / half height from the minimap's centre to the button's centre (just outside the map's edge).
local function HalfSize()
    local m = Map()
    local w = m and m:GetWidth() or 0
    local h = m and m:GetHeight() or 0
    if type(w) ~= "number" or w <= 0 then w = 140 end
    if type(h) ~= "number" or h <= 0 then h = w end
    return w / 2 + MM.RING, h / 2 + MM.RING
end

-- Distance from the centre on a round map (kept for older callers; the width decides).
function MM.Radius()
    return (HalfSize())
end

-- The button's offset from the minimap's centre for this angle (degrees), following the map's real shape.
function MM.Offset(angle)
    local a = math.rad(angle or ns.Settings.Get("minimapAngle") or 0)
    local x, y = math.cos(a), math.sin(a)
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local w, h = HalfSize()
    if MM.SHAPES[MM.Shape()][q] then
        return x * w, y * h
    end
    -- square quarter: push out along the diagonal, then clamp to the square's edge (w / h out, the same RING
    -- distance as on a round map; at 45 degrees it lands exactly in the corner)
    local dw, dh = math.sqrt(2) * w, math.sqrt(2) * h
    return math.max(-w, math.min(x * dw, w)), math.max(-h, math.min(y * dh, h))
end

function MM.Place(angle)
    local f, m = MM.frame, Map()
    if not (f and m) then return end
    local x, y = MM.Offset(angle)
    f:ClearAllPoints()
    f:SetPoint("CENTER", m, "CENTER", x, y)
end

-- Re-place when the map may have changed size or shape (another addon resizes / reshapes it).
local function Replace()
    if MM.frame and not MM.frame:GetScript("OnUpdate") then MM.Place() end
end

local function HookMap(m)
    if MM.hooked or not (m and m.HookScript) then return end
    MM.hooked = true
    m:HookScript("OnSizeChanged", function() ns.Errors.Call("minimap", Replace) end)
    m:HookScript("OnShow", function() ns.Errors.Call("minimap", Replace) end)
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
    HookMap(m)
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

-- Self-test: the button sits on the map's edge (its real shape) when it's on; the .toc's compartment names are
-- our functions.
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
            local ex, ey = MM.Offset()
            local d = math.sqrt((bx - mx - ex) ^ 2 + (by - my - ey) ^ 2)
            if d > 2 then h.Problem(("minimap: button off the edge (%d, shape %s)"):format(d, MM.Shape())) end
        end
    end
    h.Info(("minimap: button %s, shape %s, broker %s"):format(f and (f:IsShown() and "shown" or "hidden") or "none",
        MM.Shape(), MM.broker and "yes" or "no"))
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
-- A minimap addon may set its shape / size after our login: place again once the world is up and on zone changes.
ns.Bus.On("Ready", MM, function() ns.Errors.Call("minimap", Replace) end, "ui", 80)
ns.Bus.On("ZoneChanged", MM, function() ns.Errors.Call("minimap", Replace) end, "ui", 80)

ns.Slash.Add("minimap", function()
    ns.Settings.Set("minimap", not ns.Settings.Get("minimap"))
end, "HELP_MINIMAP")

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M4: look overlays that work on top of any theme (data only, laid over the theme by Theme.Raw):
--   high contrast: an opaque panel, brighter dim texts and borders (the opacity setting is ignored)
--   colour-blind:  the arrow runs blue (ahead) -> light grey (side) -> orange (behind) instead of
--                  green -> yellow -> red; done / danger colours follow (blue / orange), badges keep their
--                  own shapes
--   font size:     points on every font (setting fontSize, -4 .. +4; never under Theme.MIN_FONT)
-- and the window scale: own scale per window (setting scale) on top of the UI scale, or the same size
-- whatever the UI scale is (followUIScale off). UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED re-apply the
-- scale and put the window back on screen.
--   ns.Overlay.Apply(), .WindowScale(), .Opacity(a), .KeepOnScreen(frame), .HC / .CB (the tables)
local _, ns = ...
local Th = ns.Theme
local Ov = {}
ns.Overlay = Ov

-- every key here must exist in the base theme (a test checks it)
Ov.HC = {
    ["color.panel"] = { "#05070A", 1 },
    ["color.panelSolid"] = { "#05070A", 1 },
    ["color.border"] = { "#8C99AA", 1 },
    ["color.divider"] = { "#FFFFFF", 0.25 },
    ["color.text"] = { "#FFFFFF", 1 },
    ["color.title"] = { "#FFFFFF", 1 },
    ["color.text.dim"] = { "#C9D1DB", 1 },
    ["color.note"] = { "#C9D1DB", 1 },   -- the step note line, readable on the darker panel
    ["color.done"] = { "#B4BDC8", 1 },
    ["color.stepNumber"] = { "#B4BDC8", 1 },
    ["color.counter"] = { "#D3DAE3", 1 },
    ["color.goal"] = { "#EEF1F5", 1 },
    ["color.goalBoxEmpty"] = { "#9AA5B3", 1 },
    ["color.button"] = { "#E4E8EE", 1 },
    ["color.barTrack"] = { "#2E3846", 1 },
    ["color.buttonHoverBg"] = { "#FFFFFF", 0.18 },
}

Ov.CB = {
    ["color.arrowAhead"] = { "#3D8BFF", 1 },
    ["color.arrowSide"] = { "#D9DEE5", 1 },
    ["color.arrowBehind"] = { "#FF9F1C", 1 },
    ["color.arrived"] = { "#3D8BFF", 1 },
    ["color.arrivedText"] = { "#8AB8FF", 1 },
    ["color.goalDone"] = { "#5AA2FF", 1 },
    ["color.goalDoneBox"] = { "#1C3F73", 1 },
    ["color.goalDoneEdge"] = { "#3D8BFF", 1 },
    ["color.flash"] = { "#3D8BFF", 0.45 },
    ["color.notice.danger"] = { "#FF9F1C", 1 },
    ["color.icon.kill"] = { "#FF9F1C", 1 },
    ["color.stepFrameMissing"] = { "#FF9F1C", 1 },
}

local LOOK_KEYS = { highContrast = true, colorBlind = true, fontSize = true }
local SCALE_KEYS = { scale = true, followUIScale = true }

-- Overlays and font size from the settings into the theme.
function Ov.Apply()
    local S = ns.Settings
    local list = {}
    if S.Get("highContrast") then list[#list + 1] = Ov.HC end
    if S.Get("colorBlind") then list[#list + 1] = Ov.CB end
    Th.SetOverlays(list, S.Get("fontSize"))
end

-- The panel alpha: opaque with high contrast (the combat fade still applies on top).
function Ov.Opacity(a)
    if ns.Settings.Get("highContrast") then return 1 end
    return a
end

-- The window's own scale; with followUIScale off it cancels the UI scale out (same size on screen).
-- key: the scale setting (default "scale" = the guide window)
function Ov.WindowScale(key)
    local s = ns.Settings.Get(key or "scale")
    if not ns.Settings.Get("followUIScale") then
        local p = ns.Compat.UIParent()
        local ui = p and p.GetScale and p:GetScale() or 1
        if type(ui) == "number" and ui > 0 then s = s / ui end
    end
    return s
end

-- Puts a frame back inside its parent when a scale or screen change pushed it (partly) off screen.
-- Works in the frame's own scaled units; nothing happens when it's already inside.
function Ov.KeepOnScreen(f)
    if not (f and f.GetLeft and f:IsShown()) then return false end
    local p = ns.Compat.UIParent()
    -- a frame hanging on another of our frames (the guide window under the NOW window) moves with it
    local _, rel = f:GetPoint(1)
    if type(rel) == "table" and rel ~= p then return false end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b and p) then return false end
    local fs, ps = f:GetEffectiveScale(), p:GetEffectiveScale()
    local k = fs / ps                           -- frame units -> parent units
    local pw, ph = p:GetWidth(), p:GetHeight()
    -- f.keepRoom = { left, right, top, bottom }: room (frame units) kept free around the frame (the one window: its
    -- soft shadow, and the button row above its top); f.keepBottom: anchored by its bottom-left (it grows up)
    local m = type(f.keepRoom) == "function" and f.keepRoom() or f.keepRoom or {}
    local ml, mr, mt, mb = (m[1] or 0) * k, (m[2] or 0) * k, (m[3] or 0) * k, (m[4] or 0) * k
    local dx, dy = 0, 0
    if l * k - ml < 0 then dx = ml - l * k elseif r * k + mr > pw then dx = pw - r * k - mr end
    if b * k - mb < 0 then dy = mb - b * k elseif t * k + mt > ph then dy = ph - t * k - mt end
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then return false end
    f:ClearAllPoints()
    if f.keepBottom then
        f:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", (l * k + dx) / k, (b * k + dy) / k)
    else
        -- re-anchor by TOPLEFT in the frame's own units
        f:SetPoint("TOPLEFT", p, "BOTTOMLEFT", (l * k + dx) / k, (t * k + dy) / k)
    end
    return true
end

-- Re-applies the look everywhere (fonts, colours, layout).
function Ov.Restyle()
    Ov.Apply()
    ns.UIKit.Restyle()
    ns.Bus.Fire("LookChanged")
end

ns.Bus.On("SettingsChanged", Ov, function(_, key)
    if LOOK_KEYS[key] then
        Ov.Restyle()
    elseif SCALE_KEYS[key] then
        ns.Bus.Fire("ScaleChanged")
    end
end, "ui", 60)

-- Ov.Apply() runs at ADDON_LOADED right after the settings are read (Core\Boot.lua), before any frame
-- is built.

-- Self-test: every overlay key exists in every theme and parses; the window is on screen at its scale.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "overlay", fn = function(h)
    h.Count()
    for name in pairs(Th.themes) do
        for _, o in ipairs({ Ov.HC, Ov.CB }) do
            for k, v in pairs(o) do
                if Th.Raw(k, name) == nil then h.Problem("overlay: theme " .. name .. " lacks " .. k) end
                if type(v) ~= "table" or not tostring(v[1]):match("^#%x%x%x%x%x%x$") then h.Problem("overlay: bad colour " .. k) end
            end
        end
    end
    local f = ns.UI and ns.UI.frame
    if f and f:IsShown() and Ov.KeepOnScreen(f) then h.Info("overlay: the window was moved back on screen") end
    local S = ns.Settings
    h.Info(("look: contrast %s, colour-blind %s, text %+d, scale %d%%"):format(S.Get("highContrast") and "on" or "off",
        S.Get("colorBlind") and "on" or "off", S.Get("fontSize"), math.floor(Ov.WindowScale() * 100 + 0.5)))
end }

local function OnScreenChange()
    ns.Bus.Fire("ScaleChanged")
end
ns.Events.On("UI_SCALE_CHANGED", Ov, OnScreenChange, "ui")
ns.Events.On("DISPLAY_SIZE_CHANGED", Ov, OnScreenChange, "ui")

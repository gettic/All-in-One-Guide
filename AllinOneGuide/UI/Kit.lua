-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Small building blocks shared by the window, menu, popups, notice line and arrow. Every colour, font
-- and glyph comes from the theme. Text is dimmed by colour, never by alpha: the only alpha we change
-- is the panel's (Kit.SetPanelAlpha).
local _, ns = ...
local Th, Co = ns.Theme, ns.Compat
local K = { texts = {}, panels = {} }
ns.UIKit = K

-- A font string with a theme font and colour. Remembered so fonts can be re-applied (theme change,
-- shadow when the panel is very see-through).
function K.Text(parent, fontKey, colorKey, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Th.Font(fs, fontKey)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    if colorKey then fs:SetTextColor(Th.Color(colorKey)) end
    K.texts[#K.texts + 1] = { fs = fs, font = fontKey }
    return fs
end

function K.Color(fs, key) fs:SetTextColor(Th.Color(key)) end

-- shadow = true: every remembered text gets a drop shadow.
function K.RefreshFonts(shadow)
    for _, t in ipairs(K.texts) do Th.Font(t.fs, t.font, shadow) end
end

-- Thickness of a hairline (border, divider): a hair over the size, so a 1-unit line never ends up just
-- under 1 unit after the UI scale's rounding (at scale 1.15 the offline checker measured 0.9999).
function K.Hair(n) return (n or 1) + 0.001 end

-- A flat colour texture.
function K.Fill(parent, layer, colorKey, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetColorTexture(Th.Color(colorKey))
    return t
end

-- A vertical gradient (top colour -> bottom colour); flat top colour when gradients aren't available.
function K.Gradient(tex, orientation, fromKey, toKey)
    local r1, g1, b1, a1 = Th.Color(fromKey)
    local r2, g2, b2, a2 = Th.Color(toKey)
    tex:SetColorTexture(1, 1, 1, 1)
    local c1, c2 = Co.Color(r1, g1, b1, a1), Co.Color(r2, g2, b2, a2)
    if c1 and c2 and tex.SetGradient then
        tex:SetGradient(orientation, c1, c2)
    else
        tex:SetColorTexture(r1, g1, b1, a1)
    end
end

-- Panel background + 1 px border. Returns the background texture. follow = its alpha follows the
-- opacity setting (the guide window); menus and dialogs keep the theme's alpha.
function K.Panel(frame, follow)
    local bg = K.Fill(frame, "BACKGROUND", "panel")
    bg:SetAllPoints()
    local b = K.Hair(Th.Size("border"))
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = K.Fill(frame, "BORDER", "border")
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
            t:SetHeight(b)
        else
            t:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
            t:SetWidth(b)
        end
    end
    if follow then K.panels[#K.panels + 1] = bg end
    return bg
end

-- The panel background alpha (the opacity setting). The only alpha change in the UI.
function K.SetPanelAlpha(alpha)
    local r, g, b = Th.Color("panel")
    K.panelAlpha = alpha
    for _, bg in ipairs(K.panels) do bg:SetColorTexture(r, g, b, alpha) end
end

-- A theme glyph texture tinted with a theme colour.
function K.Glyph(parent, slotKey, size, colorKey, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    Th.Glyph(t, slotKey)
    if colorKey then t:SetVertexColor(Th.Color(colorKey)) end
    return t
end

function K.Tooltip(owner, text)
    local tip = Co.Tooltip()
    if not tip or not text then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(text, 1, 1, 1, 1, true)
    tip:Show()
end
function K.HideTooltip()
    local tip = Co.Tooltip()
    if tip then tip:Hide() end
end

-- Esc hides a named frame of ours the standard way: its name goes into Blizzard's UISpecialFrames
-- list (CloseSpecialWindows hides it; none of our code runs in that path except the frame's OnHide).
-- Only for the menu and the dialogs, never the guide window (Esc never closes the guide).
function K.CloseOnEsc(name)
    local list = Co.fn.SpecialFrames
    if type(list) ~= "table" then return false end
    for _, n in pairs(list) do if n == name then return true end end
    table.insert(list, name)
    return true
end

-- A small square button with a glyph: button colour, white on hover with a faint background.
function K.GlyphButton(parent, slotKey, size, tipText, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local hover = K.Fill(b, "BACKGROUND", "buttonHoverBg")
    hover:SetAllPoints()
    hover:Hide()
    local icon = K.Glyph(b, slotKey, size, "button")
    icon:SetPoint("CENTER")
    b.icon, b.hover = icon, hover
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button) ns.Errors.Call("ui", onClick, self, button) end)
    b:SetScript("OnEnter", function(self)
        self.hover:Show()
        self.icon:SetVertexColor(Th.Color("buttonHover"))
        local t = type(tipText) == "function" and tipText() or tipText
        if t then K.Tooltip(self, t) end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover:Hide()
        self.icon:SetVertexColor(Th.Color("button"))
        K.HideTooltip()
    end)
    return b
end

-- A badge: tinted disc + glyph on top (manifest "Badges").
local BADGE = {
    accept = { "badge.accept", "icon.accept", "icon.glyphDark" },
    turnin = { "badge.turnin", "icon.turnin", "icon.glyphDark" },
    objective = { "badge.objective", "icon.kill", "white" },
    collect = { "badge.collect", "icon.collect", "white" },
    ["goto"] = { "badge.goto", "icon.goto", "white" },
    level = { "badge.level", "icon.level", "white" },
    manual = { "badge.manual", "icon.manual", "white" },
}
K.BADGE = BADGE

function K.Badge(parent, size)
    local disc = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    disc:SetSize(size, size)
    Th.Glyph(disc, "badge.disc")
    local glyph = parent:CreateTexture(nil, "ARTWORK", nil, 2)
    glyph:SetAllPoints(disc)
    return { disc = disc, glyph = glyph }
end

-- kind: a BADGE key; dim = done step (icon at 45 %: on the texture, never on text).
function K.SetBadge(badge, kind, dim)
    local b = BADGE[kind] or BADGE.manual
    Th.Glyph(badge.glyph, b[1])
    local r, g, bl = Th.Color(b[2])
    local a = dim and 0.45 or 1
    badge.disc:SetVertexColor(r, g, bl, a)
    local r2, g2, b2 = Th.Color(b[3])
    badge.glyph:SetVertexColor(r2, g2, b2, a)
end

-- The badge kind of a step: objective steps for items show the sack.
function K.BadgeKind(step)
    if step.type == "objective" and step.item then return "collect" end
    if BADGE[step.type] then return step.type end
    return "manual"
end

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Small building blocks shared by the window, menu, popups, notice line and arrow. Every colour, font
-- and glyph comes from the theme. Text is dimmed by colour, never by alpha: the only alpha we change
-- is the panel's (Kit.SetPanelAlpha).
local _, ns = ...
local Th, Co = ns.Theme, ns.Compat
-- texts / fills / glyphs / gradients are remembered with their theme keys, so a theme or overlay change
-- (high contrast, colour-blind, font size: Theme\Overlay.lua) can re-apply them: K.Restyle()
local K = { texts = {}, panels = {}, fills = {}, glyphs = {}, gradients = {}, byFs = {}, byTex = setmetatable({}, { __mode = "k" }) }
ns.UIKit = K

-- A font string with a theme font and colour. Remembered so fonts can be re-applied (theme change,
-- shadow when the panel is very see-through).
function K.Text(parent, fontKey, colorKey, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Th.Font(fs, fontKey)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    if colorKey then fs:SetTextColor(Th.Color(colorKey)) end
    local e = { fs = fs, font = fontKey, color = colorKey }
    K.texts[#K.texts + 1] = e
    K.byFs[fs] = e
    return fs
end

function K.Color(fs, key)
    fs:SetTextColor(Th.Color(key))
    local e = K.byFs[fs]
    if e then e.color = key end
end

-- shadow = true: every remembered text gets a drop shadow.
function K.RefreshFonts(shadow)
    if shadow ~= nil then K.shadow = shadow end
    for _, t in ipairs(K.texts) do Th.Font(t.fs, t.font, K.shadow) end
end

-- Everything remembered gets its font, colour, fill and tint again from the theme (+ overlays).
-- Rows and the arrow set their state colours on their next refresh.
function K.Restyle()
    K.RefreshFonts()
    for _, t in ipairs(K.texts) do
        if t.color then t.fs:SetTextColor(Th.Color(t.color)) end
    end
    for _, f in ipairs(K.fills) do f.tex:SetColorTexture(Th.Color(f.key)) end
    for _, g in ipairs(K.glyphs) do g.tex:SetVertexColor(Th.Color(g.key)) end
    for _, g in ipairs(K.gradients) do K.Gradient(g.tex, g.orientation, g.from, g.to, true) end
    if K.panelAlpha then K.SetPanelAlpha(K.panelAlpha) end
end

-- Thickness of a hairline (border, divider): a hair over the size, so a 1-unit line never ends up just
-- under 1 unit after the UI scale's rounding (at scale 1.15 the offline checker measured 0.9999).
function K.Hair(n) return (n or 1) + 0.001 end

-- A flat colour texture.
function K.Fill(parent, layer, colorKey, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetColorTexture(Th.Color(colorKey))
    K.fills[#K.fills + 1] = { tex = t, key = colorKey }
    return t
end

-- A vertical gradient (top colour -> bottom colour); flat top colour when gradients aren't available.
function K.Gradient(tex, orientation, fromKey, toKey, again)
    if not again then K.gradients[#K.gradients + 1] = { tex = tex, orientation = orientation, from = fromKey, to = toKey } end
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
-- opacity setting (the guide window, colour key "panel"); every other panel (Hub, dialog, copy box, menu)
-- uses "panelSolid" (text over the world stays readable), or `key` when given.
function K.Panel(frame, follow, key)
    local bg = K.Fill(frame, "BACKGROUND", key or (follow and "panel" or "panelSolid"))
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
    if colorKey then
        t:SetVertexColor(Th.Color(colorKey))
        local e = { tex = t, key = colorKey }
        K.glyphs[#K.glyphs + 1] = e
        K.byTex[t] = e
    end
    return t
end

-- A new tint for a glyph made by K.Glyph: remembered, so K.Restyle keeps it (state colours: hover, picked).
function K.Tint(tex, colorKey)
    tex:SetVertexColor(Th.Color(colorKey))
    local e = K.byTex[tex]
    if e then e.key = colorKey end
end

-- text = the first line (white); lines = more lines in a fixed order (dim), optional.
function K.Tooltip(owner, text, lines)
    local tip = Co.Tooltip()
    if not tip or not text then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(text, 1, 1, 1, 1, true)
    if lines and tip.AddLine then
        local r, g, b = Th.Color("text.dim")
        for _, l in ipairs(lines) do
            if type(l) == "string" and l ~= "" then tip:AddLine(l, r, g, b, true) end
        end
    end
    K.lastTip = { text = text, lines = lines }
    tip:Show()
end

-- A small pool of frames: Acquire(parent) reuses a released one (made by `make(parent)`), Release(all).
function K.Pool(make)
    local pool = { free = {}, used = {}, made = 0 }
    function pool.Acquire(parent)
        local f = table.remove(pool.free)
        if not f then
            f = make(parent)
            pool.made = pool.made + 1
        elseif parent and f:GetParent() ~= parent then
            f:SetParent(parent)
        end
        pool.used[#pool.used + 1] = f
        return f
    end
    function pool.ReleaseAll()
        for i = #pool.used, 1, -1 do
            local f = pool.used[i]
            f:Hide()
            f:ClearAllPoints()
            pool.free[#pool.free + 1] = f
            pool.used[i] = nil
        end
    end
    return pool
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

-- The one title bar (look review #5): the guide window, the Hub, the dialog and the copy box. Height
-- size.title, logo size.titleLogo at 4, close button at -3, title text between them.
--   opts.close = fn (a close button), opts.closeTip = text or fn, opts.drag = true (drag moves `frame`),
--   opts.canDrag = fn -> bool (e.g. not while locked), opts.dragStop = fn (after a drag), opts.feature
function K.TitleBar(frame, opts)
    opts = opts or {}
    local tb = CreateFrame("Frame", nil, frame)
    tb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tb:SetHeight(Th.Size("title"))
    tb.bg = tb:CreateTexture(nil, "BACKGROUND", nil, 1)
    tb.bg:SetPoint("TOPLEFT", tb, "TOPLEFT", 1, -1)
    tb.bg:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", -1, 0)
    K.Gradient(tb.bg, "VERTICAL", "titleBottom", "titleTop")
    tb:EnableMouse(true)
    if opts.drag then
        tb:RegisterForDrag("LeftButton")
        tb:SetScript("OnDragStart", function()
            if not opts.canDrag or opts.canDrag() then frame:StartMoving() end
        end)
        tb:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            if opts.dragStop then ns.Errors.Call(opts.feature or "ui", opts.dragStop) end
        end)
    end
    local ls = Th.Size("titleLogo")
    tb.logo = tb:CreateTexture(nil, "ARTWORK")
    tb.logo:SetSize(ls, ls)
    tb.logo:SetPoint("LEFT", tb, "LEFT", 4, 0)
    Th.Glyph(tb.logo, "logo")
    tb.title = K.Text(tb, "title", "title")
    tb.title:SetPoint("LEFT", tb.logo, "RIGHT", 5, 0)
    if opts.close then
        tb.close = K.GlyphButton(tb, "btn.close", Th.Size("button"), opts.closeTip, opts.close)
        tb.close:SetPoint("RIGHT", tb, "RIGHT", -3, 0)
        tb.title:SetPoint("RIGHT", tb.close, "LEFT", -4, 0)
    else
        tb.title:SetPoint("RIGHT", tb, "RIGHT", -6, 0)
    end
    return tb
end

-- A text button (look review #5): fill, a light box under the mouse, primary = accent text.
-- Width = max(size.buttonMin, text + 24), height = a step line + 8. b:SetLabel(text) sets the text and
-- the width again; b:SetPrimary(on).
local function ButtonWidth(b)
    local w = (b.text:GetStringWidth() or 0) + 24
    b:SetWidth(math.max(Th.Size("buttonMin"), math.ceil(w)))
end

function K.Button(parent, text, fn, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(Th.LineHeight("step") + 8)
    b.fill = K.Fill(b, "BACKGROUND", "buttonFill")
    b.fill:SetAllPoints()
    b.hover = K.Fill(b, "BACKGROUND", "buttonHoverBg", 1)
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.text = K.Text(b, "step", opts.primary and "buttonPrimary" or "text", "CENTER")
    b.text:SetPoint("CENTER")
    function b.SetLabel(self, label)
        self.text:SetText(label or "")
        ButtonWidth(self)
    end
    function b.SetPrimary(self, on)
        self.primary = on and true or false
        K.Color(self.text, self.primary and "buttonPrimary" or "text")
    end
    b.primary = opts.primary and true or false
    b:SetLabel(text)
    b:SetScript("OnEnter", function(self) self.hover:Show() end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    if fn then b:SetScript("OnClick", function(self) ns.Errors.Call(opts.feature or "ui", fn, self) end) end
    return b
end

-- A choice row (look review #5): a square tick box (tick as many as you like) or, radio = true, a round
-- ring + dot (pick one). The whole row gets a light box under the mouse. b:Set(on); b.on, b.radio.
function K.Choice(parent, text, fn, radio, feature)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(Th.LineHeight("step") + 4)
    b.radio = radio and true or false
    b.hover = K.Fill(b, "BACKGROUND", "buttonHoverBg")
    b.hover:SetAllPoints()
    b.hover:Hide()
    local s = Th.Size("box")
    if b.radio then
        b.box = K.Glyph(b, "radio.ring", s + 2, "radio")
        b.tick = K.Glyph(b, "radio.dot", math.floor((s + 2) / 2), "radioOn")
    else
        b.box = K.Glyph(b, "check.box", s, "goalBoxEmpty")
        b.tick = K.Glyph(b, "check.tick", s, "goalDone")
    end
    b.box:SetPoint("LEFT", b, "LEFT", 2, 0)
    b.tick:SetPoint("CENTER", b.box, "CENTER", 0, 0)
    b.tick:Hide()
    b.text = K.Text(b, "step", "text")
    b.text:SetPoint("LEFT", b.box, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.text:SetText(text or "")
    b:SetScript("OnEnter", function(self) self.hover:Show() end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    b:SetScript("OnClick", function(self) ns.Errors.Call(feature or "ui", fn, self) end)
    function b.Set(self, on)
        self.on = on and true or false
        self.tick:SetShown(self.on)
        if self.radio then K.Tint(self.box, self.on and "radioOn" or "radio") end
        if self.icon then K.Tint(self.icon, (self.on and self.radio) and "radioOn" or "button") end
    end
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
    -- v0.2 types: their own glyphs (art-src\MANIFEST.md)
    learn = { "badge.learn", "icon.learn", "white" },
    train = { "badge.train", "icon.train", "white" },
    note = { "badge.note", "icon.note", "white" },
    useitem = { "badge.useitem", "icon.useitem", "white" },
    grind = { "badge.grind", "icon.grind", "white" },
    fly = { "badge.fly", "icon.fly", "white" },
    hearth = { "badge.hearth", "icon.hearth", "white" },
    getfp = { "badge.getfp", "icon.getfp", "white" },
    sethearth = { "badge.sethearth", "icon.sethearth", "white" },
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

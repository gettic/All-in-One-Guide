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
            if not opts.canDrag or opts.canDrag() then
                -- moveFrame: the frame that really moves (the NOW window moves the guide window with it)
                local m = opts.moveFrame and opts.moveFrame() or frame
                tb.moving = m
                m:StartMoving()
            end
        end)
        tb:SetScript("OnDragStop", function()
            local m = tb.moving or (opts.moveFrame and opts.moveFrame()) or frame
            tb.moving = nil
            m:StopMovingOrSizing()
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

-- ------------------------------------------------------------------ main window controls
-- All plain frames (tos: no Blizzard templates, no UIDropDownMenu, nothing hooked).

-- A value snapped to the setting's step and clamped to its min / max (the bounds come from the schema
-- entry, never hard-coded).
function K.SnapValue(d, v)
    v = tonumber(v)
    if not v then return nil end
    local step = d.step or 1
    v = math.floor((v - d.min) / step + 0.5) * step + d.min
    return math.max(d.min, math.min(d.max, tonumber(("%.4f"):format(v))))
end

-- A slider for a number setting d (schema entry): track, accent fill, thumb, the value on the right.
-- Drag (cursor, OnUpdate only while the button is down), click on the track, mouse wheel = one step.
-- onChange(value) gets the value snapped to the step, and only when it differs from the shown one (font
-- size fix 2026-11-25, the user: "the text size is janky and jumps around": every mouse move while dragging
-- used to save the same value again and restyle / rebuild everything per frame). The thumb jumps to the
-- snapped value at once. s:Set(v) shows a value.
-- K.dragging = the slider being dragged (nil otherwise); its release fires Bus "SliderReleased", so a page
-- that would rebuild under the mouse (Hub) waits for it.
function K.Slider(parent, d, onChange, feature)
    local s = CreateFrame("Button", nil, parent)
    local w = Th.Size("slider")
    s:SetSize(w + 52, Th.LineHeight("step") + 4)
    s.d, s.w = d, w
    s.track = K.Fill(s, "ARTWORK", "sliderTrack")
    s.track:SetSize(w, Th.Size("barSmall"))
    s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
    s.fill = K.Fill(s, "ARTWORK", "sliderFill", 1)
    s.fill:SetHeight(Th.Size("barSmall"))
    s.fill:SetPoint("LEFT", s.track, "LEFT", 0, 0)
    local tw = Th.Size("sliderThumb")
    s.thumb = K.Fill(s, "OVERLAY", "sliderThumb")
    s.thumb:SetSize(tw, tw + 4)
    s.value = K.Text(s, "goal", "text", "RIGHT")
    s.value:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    s.value:SetWidth(46)
    function s.Set(self, v)
        v = tonumber(v) or d.min
        self.v = v
        local span = d.max - d.min
        local frac = span > 0 and math.max(0, math.min(1, (v - d.min) / span)) or 0
        self.fill:SetWidth(math.max(1, self.w * frac))
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("CENTER", self.track, "LEFT", self.w * frac, 0)
        self.value:SetText(ns.Settings.NumberText(d, v))
    end
    -- the value under the cursor (nil when it can't be read)
    function s.FromCursor(self)
        local x = Co.Cursor(self)
        local left = self.track:GetLeft()
        if not (x and left) then return nil end
        local frac = math.max(0, math.min(1, (x - left) / self.w))
        return d.min + frac * (d.max - d.min)
    end
    local function Push(self, v)
        v = K.SnapValue(d, v)
        if v == nil or v == self.v then return end
        self:Set(v)
        ns.Errors.Call(feature or "ui", onChange, v)
    end
    local function EndDrag(self)
        self:SetScript("OnUpdate", nil)
        if K.dragging == self then
            K.dragging = nil
            ns.Bus.Fire("SliderReleased", self)
        end
    end
    s:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        K.dragging = self
        Push(self, self:FromCursor())
        self:SetScript("OnUpdate", function(me) Push(me, me:FromCursor()) end)
    end)
    s:SetScript("OnMouseUp", EndDrag)
    s:SetScript("OnHide", EndDrag)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        Push(self, (self.v or d.min) + (delta > 0 and 1 or -1) * (d.step or 1))
    end)
    s:Set(d.default)
    return s
end

-- A drop-down for a choice setting d: a text button with a caret; the list is the one ns.Menu (ticked row =
-- the value). onChange(value); b:Set(v) shows a value.
function K.Dropdown(parent, d, onChange, feature)
    local function Label(v)
        local key = d.choiceLabels and d.choiceLabels[v]
        return key and ns.L[key] or tostring(v)
    end
    local b
    b = K.Button(parent, "", function(self)
        if ns.Menu.IsOpen() and ns.Menu.anchor == self then ns.Menu.Close() return end
        local items = {}
        for _, v in ipairs(d.choices) do
            items[#items + 1] = { text = Label(v), checked = v == self.v,
                fn = function() ns.Errors.Call(feature or "ui", onChange, v) end }
        end
        ns.Menu.Open(self, items)
    end, { feature = feature })
    b.caret = K.Glyph(b, "btn.caret", Th.Size("box"), "button")
    b.caret:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    Th.Glyph(b.caret, "btn.caret", "cw")
    function b.Set(self, v)
        self.v = v
        self:SetLabel(Label(v))
        self:SetWidth(math.max(self:GetWidth(), Th.Size("slider")))
    end
    b:Set(d.default)
    return b
end

-- A search box: our own EditBox (never takes the keyboard by itself: no SetAutoFocus, tos), magnifier,
-- a dim placeholder while empty. onChange(text) on every change; Esc / Enter let go of the keyboard.
function K.SearchBox(parent, placeholder, onChange, feature)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(Th.Size("search"), Th.LineHeight("step") + 8)
    f.bg = K.Fill(f, "BACKGROUND", "searchBg")
    f.bg:SetAllPoints()
    local hair = K.Hair(Th.Size("border"))
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        local t = K.Fill(f, "BORDER", "border")
        t:SetPoint(side .. "LEFT", f, side .. "LEFT", 0, 0)
        t:SetPoint(side .. "RIGHT", f, side .. "RIGHT", 0, 0)
        t:SetHeight(hair)
    end
    f.icon = K.Glyph(f, "btn.search", Th.Size("button") - 2, "text.dim")
    f.icon:SetPoint("LEFT", f, "LEFT", 5, 0)
    local e = CreateFrame("EditBox", nil, f)
    f.edit = e
    e:SetAutoFocus(false)
    Th.Font(e, "goal")
    e:SetTextColor(Th.Color("text"))
    e:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 4, 4)
    e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 0)
    e:SetMaxLetters(40)
    f.hint = K.Text(f, "goal", "text.dim")
    f.hint:SetPoint("LEFT", f.icon, "RIGHT", 5, 0)
    f.hint:SetText(placeholder or "")
    local function Hint() f.hint:SetShown((e:GetText() or "") == "" and not f.focused) end
    e:SetScript("OnEditFocusGained", function() f.focused = true Hint() end)
    e:SetScript("OnEditFocusLost", function() f.focused = false Hint() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnTextChanged", function(self)
        Hint()
        ns.Errors.Call(feature or "ui", onChange, self:GetText() or "")
    end)
    f:SetScript("OnHide", function() e:ClearFocus() end)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function() e:SetFocus() end)
    function f.Get() return e:GetText() or "" end
    function f.SetText(_, t) e:SetText(t or "") Hint() end
    Hint()
    K.searchBoxes[#K.searchBoxes + 1] = e
    return f
end
-- combat starts (PLAYER_REGEN_DISABLED, via GameState's CombatStarted): every search box lets go of the keyboard
K.searchBoxes = {}
ns.Bus.On("CombatStarted", K, function()
    for _, e in ipairs(K.searchBoxes) do e:ClearFocus() end
end, "ui", 10)

-- A filter chip: a small box with a text; picked = accent text and edge. c:SetOn(on), c:SetLabel(text).
function K.Chip(parent, text, fn, feature)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(Th.LineHeight("step") + 6)
    c.fill = K.Fill(c, "BACKGROUND", "buttonFill")
    c.fill:SetAllPoints()
    c.hover = K.Fill(c, "BACKGROUND", "buttonHoverBg", 1)
    c.hover:SetAllPoints()
    c.hover:Hide()
    c.edge = K.Fill(c, "BORDER", "chipOn")
    c.edge:SetHeight(K.Hair(1))
    c.edge:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
    c.edge:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    c.edge:Hide()
    c.text = K.Text(c, "goal", "text", "CENTER")
    c.text:SetPoint("CENTER")
    function c.SetLabel(self, t)
        self.text:SetText(t or "")
        self:SetWidth(math.ceil((self.text:GetStringWidth() or 30) + 16))
    end
    function c.SetOn(self, on)
        self.on = on and true or false
        self.edge:SetShown(self.on)
        K.Color(self.text, self.on and "chipOn" or "text")
    end
    c:SetScript("OnEnter", function(self) self.hover:Show() end)
    c:SetScript("OnLeave", function(self) self.hover:Hide() end)
    c:SetScript("OnClick", function(self) ns.Errors.Call(feature or "ui", fn, self) end)
    c:SetLabel(text)
    return c
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

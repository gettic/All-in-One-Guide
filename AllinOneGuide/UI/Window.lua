-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The guide window. From the top: title bar (logo, route title, menu / small / lock / close), section
-- header with "step i/n", the fixed step area (the NOW box with the current step on top, then the NEXT
-- steps), the notice line (always kept free in full mode), the "n done" chip, the footer (back, progress,
-- next). Every step stays shown in combat.
-- Small mode keeps the same width: title bar, the current step and one "Next:" line (a notice replaces it).
-- States: none / finished / error / safe. Clamped to the screen; the position is saved per character
-- only after the player moves it. Opacity changes the panel alpha only (text stays at full alpha and
-- gets a shadow under 0.5). Esc never closes it (it isn't a UI panel).
--   ns.UI.Show(), Hide(), Toggle(), Refresh(), ResetPos(), IsShown(); ns.UI.frame and its parts
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local UI = { rows = {}, built = false, refreshes = 0 }
ns.UI = UI

local FOOT_H = 22
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -90, -200 }
local CHIP_MAX = 10

local function LH() return Th.LineHeight("step") end
local function Pad() return Th.Size("pad") end
local function TitleH() return Th.Size("title") end
local function L() return ns.L end

-- ------------------------------------------------------------------ sizes
function UI.Small() return ns.Settings.Get("small") end
-- The window width (v0.2 M3: the grip changes it; the step area's height never changes with it).
function UI.Width() return ns.Settings.Get("width") end
-- The NOW box's frame around the current step: margin + "NOW" header above, padding below.
function UI.NowChrome()
    return Th.Size("nowMargin") + Th.LineHeight("sectionHead") + Th.Size("nowPadBottom")
end
-- The NEXT header with the gap above it (full mode only).
function UI.NextChrome() return Th.Size("sectionGap") + Th.LineHeight("sectionHead") end
-- The step area: its lines of steps plus the NOW box's frame (and the NEXT header in full mode), so the
-- box never takes room from the steps.
function UI.AreaHeight(small)
    local h = Th.Size(small and "smallLines" or "stepLines") * LH() + UI.NowChrome()
    if not small then h = h + UI.NextChrome() end
    return h
end
function UI.Height(small)
    if small then return TitleH() + UI.AreaHeight(true) + Pad() end
    return TitleH() + LH() * 3 + UI.AreaHeight(false) + FOOT_H + Pad()
end

-- ------------------------------------------------------------------ position (saved only when moved)
local function CanSave() return not ns.safeMode and not ns.DB.readOnly.char end

local function SavedPos()
    local m = ns.DB.char and type(ns.DB.char.modules) == "table" and ns.DB.char.modules.window
    if type(m) ~= "table" or type(m.point) ~= "string" or type(m.x) ~= "number" or type(m.y) ~= "number" then return nil end
    return m
end

function UI.ApplyPos()
    local f, parent = UI.frame, Co.UIParent()
    f:ClearAllPoints()
    local m = SavedPos()
    if m then
        f:SetPoint(m.point, parent, m.rel or m.point, m.x, m.y)
    else
        f:SetPoint(DEFAULT_POINT[1], parent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

-- Saves the spot (when the save may be written) and always tells the others the window moved (the step
-- button follows it, also with a read-only save or in safe mode).
function UI.SavePos()
    local point, _, rel, x, y = UI.frame:GetPoint(1)
    if CanSave() and type(point) == "string" and type(x) == "number" and type(y) == "number" then
        local m = ns.DB.Module("window", "char", 1)
        m.point, m.rel, m.x, m.y = point, rel or point, math.floor(x + 0.5), math.floor(y + 0.5)
    end
    ns.Bus.Fire("WindowMoved")
end

function UI.ResetPos()
    local m = SavedPos()
    if m and CanSave() then m.point, m.rel, m.x, m.y = nil, nil, nil, nil end
    if UI.frame then
        UI.ApplyPos()
        ns.Bus.Fire("WindowMoved")
    end
    if ns.Arrow then ns.Arrow.ResetPos() end
end

-- ------------------------------------------------------------------ building
-- the shared title bar (UIKit, look review #5) + the guide window's own buttons
local function TitleBar(f)
    local tb = K.TitleBar(f, {
        drag = true,
        canDrag = function() return not ns.Settings.Get("locked") end,
        dragStop = function() UI.SavePos() end,
        close = function() UI.Hide() end,
        closeTip = function() return L().TIP_CLOSE end,
    })
    tb:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.Menu.Open(self, UI.MenuItems()) end
    end)
    local s = Th.Size("button")
    tb.lock = K.GlyphButton(tb, "btn.unlock", s, function()
        return ns.Settings.Get("locked") and L().TIP_UNLOCK or L().TIP_LOCK
    end, function()
        ns.Settings.Set("locked", not ns.Settings.Get("locked"))
    end)
    tb.lock:SetPoint("RIGHT", tb.close, "LEFT", -2, 0)
    tb.small = K.GlyphButton(tb, "btn.small", s, function()
        return UI.Small() and L().TIP_EXPAND or L().TIP_SMALL
    end, function()
        ns.Settings.Set("small", not UI.Small())
    end)
    tb.small:SetPoint("RIGHT", tb.lock, "LEFT", -2, 0)
    tb.menu = K.GlyphButton(tb, "btn.menu", s, function() return L().TIP_MENU end, function(self)
        if ns.Menu.IsOpen() then ns.Menu.Close() else ns.Menu.Open(self, UI.MenuItems(), { right = true }) end
    end)
    tb.menu:SetPoint("RIGHT", tb.small, "LEFT", -2, 0)
    tb.title:ClearAllPoints()
    tb.title:SetPoint("LEFT", tb.logo, "RIGHT", 5, 0)
    tb.title:SetPoint("RIGHT", tb.menu, "LEFT", -4, 0)
    return tb
end

local function Header(f)
    local h = CreateFrame("Frame", nil, f)
    h:SetHeight(LH())
    h:SetPoint("TOPLEFT", f, "TOPLEFT", Pad(), -TitleH())
    h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Pad(), -TitleH())
    h.counter = K.Text(h, "small", "counter", "RIGHT")
    h.counter:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.text = K.Text(h, "header", "zone")
    h.text:SetPoint("LEFT", h, "LEFT", 0, 0)
    h.text:SetPoint("RIGHT", h.counter, "LEFT", -6, 0)
    h.line = K.Fill(h, "ARTWORK", "divider")
    h.line:SetHeight(K.Hair(1))
    h.line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    return h
end

local function NoticeLine(f)
    local n = CreateFrame("Button", nil, f)
    n:SetHeight(LH())
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetSize(Th.Size("badge"), Th.Size("badge"))
    n.icon:SetPoint("LEFT", n, "LEFT", 0, 0)
    n.text = K.Text(n, "goal", "notice")
    n.text:SetPoint("LEFT", n.icon, "RIGHT", 5, 0)
    n.btn = CreateFrame("Button", nil, n)
    n.btn:SetHeight(LH() - 2)
    n.btn:SetPoint("RIGHT", n, "RIGHT", 0, 0)
    K.Fill(n.btn, "BACKGROUND", "barTrack"):SetAllPoints()
    n.btn.text = K.Text(n.btn, "small", "accent", "CENTER")
    n.btn.text:SetPoint("CENTER")
    n.btn:SetScript("OnClick", function()
        local cur = UI.notice
        if cur and cur.button and cur.button.fn then ns.Errors.Call("ui", cur.button.fn) end
    end)
    n.text:SetPoint("RIGHT", n.btn, "LEFT", -4, 0)
    n:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    n:SetScript("OnClick", function(self, button)
        if button == "RightButton" and UI.notice then ns.Menu.Open(self, ns.Notice.MenuItems(UI.notice)) end
    end)
    -- hover: the full text, then "Why am I seeing this?" (which part sent it and how to turn it off)
    n:SetScript("OnEnter", function(self)
        if UI.notice then K.Tooltip(self, UI.notice.text, ns.Notice.Why(UI.notice)) end
    end)
    n:SetScript("OnLeave", K.HideTooltip)
    return n
end

-- The "n done" chip (look review #7, variant A): a small square button (fill + a light box under the
-- mouse), tick, text, caret; the caret turns down while its list is open.
local function ChipCaret(c, open)
    c.open = open and true or false
    Th.Glyph(c.caret, "btn.caret", c.open and "cw" or nil)
end

local function Chip(f)
    local c = CreateFrame("Button", nil, f)
    c:SetHeight(LH() - 2)
    local pad = Th.Size("chipPad")
    c.fill = K.Fill(c, "BACKGROUND", "buttonFill")
    c.fill:SetAllPoints()
    c.hover = K.Fill(c, "BACKGROUND", "buttonHoverBg", 1)
    c.hover:SetAllPoints()
    c.hover:Hide()
    c.tick = K.Glyph(c, "done", Th.Size("box") + 2, "goalDone")
    c.tick:SetPoint("LEFT", c, "LEFT", pad, 0)
    c.text = K.Text(c, "small", "text.dim")
    c.text:SetPoint("LEFT", c.tick, "RIGHT", 4, 0)
    c.caret = K.Glyph(c, "btn.caret", Th.Size("box"), "button")
    c.caret:SetPoint("LEFT", c.text, "RIGHT", 3, 0)
    ChipCaret(c, false)
    c:SetScript("OnEnter", function(self)
        self.hover:Show()
        K.Color(self.text, "text")
        K.Tint(self.caret, "buttonHover")
    end)
    c:SetScript("OnLeave", function(self)
        self.hover:Hide()
        K.Color(self.text, "text.dim")
        K.Tint(self.caret, "button")
    end)
    c:SetScript("OnClick", function(self)
        if ns.Menu.IsOpen() and ns.Menu.anchor == self then ns.Menu.Close() return end
        ns.Menu.Open(self, UI.ChipItems(), { onClose = function() ChipCaret(self, false) end })
        ChipCaret(self, ns.Menu.IsOpen())
    end)
    return c
end

-- The chip's width: padding, tick, text, caret, padding.
function UI.ChipWidth()
    local c = UI.chip
    if not c then return 0 end
    local box = Th.Size("box")
    return math.ceil(Th.Size("chipPad") * 2 + box + 2 + 4 + (c.text:GetStringWidth() or 40) + 3 + box)
end

local function Footer(f)
    local ft = CreateFrame("Frame", nil, f)
    ft:SetHeight(FOOT_H)
    ft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", Pad(), Pad() / 2)
    ft:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Pad(), Pad() / 2)
    local s = Th.Size("navButton")
    ft.prev = K.GlyphButton(ft, "btn.prev", s, function() return L().TIP_BACK end, function() ns.Engine.Back() end)
    ft.prev:SetPoint("LEFT", ft, "LEFT", 0, 0)
    ft.next = K.GlyphButton(ft, "btn.next", s, function() return L().TIP_NEXT end, function() ns.Engine.Next() end)
    ft.next:SetPoint("RIGHT", ft, "RIGHT", 0, 0)
    ft.pct = K.Text(ft, "small", "counter", "RIGHT")
    ft.pct:SetWidth(32)
    ft.pct:SetPoint("RIGHT", ft.next, "LEFT", -4, 0)
    ft.track = K.Fill(ft, "ARTWORK", "barTrack")
    ft.track:SetHeight(Th.Size("bar"))
    ft.track:SetPoint("LEFT", ft.prev, "RIGHT", 6, 0)
    ft.track:SetPoint("RIGHT", ft.pct, "LEFT", -4, 0)
    ft.fill = ft:CreateTexture(nil, "ARTWORK", nil, 2)
    ft.fill:SetHeight(Th.Size("bar"))
    ft.fill:SetPoint("LEFT", ft.track, "LEFT", 0, 0)
    K.Gradient(ft.fill, "HORIZONTAL", "barFrom", "barTo")
    return ft
end

-- ------------------------------------------------------------------ width grip (v0.2 M3)
-- Drag the window's right edge: only the width changes (the step area keeps its height). The window
-- is pinned by its top-left corner while dragging, so the left edge stays put; saved on release.
local GRIP_W = 6
function UI.SetWidthLive(w)
    local d = ns.Settings.byKey.width
    w = math.floor(ns.U.Clamp(w, d.min, d.max) + 0.5)
    UI.frame:SetWidth(w)
    return w
end

local function GripUpdate(self)
    local f = UI.frame
    local x = Co.Cursor(f)
    if not x or not self.startX then return end
    self.width = UI.SetWidthLive(self.startW + (x - self.startX))
end

function UI.GripStart(self)
    local f = UI.frame
    if ns.Settings.Get("locked") or Co.InCombat() then return false end
    local left, top = f:GetLeft(), f:GetTop()
    local x = Co.Cursor(f)
    if not (left and top and x) then return false end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", Co.UIParent(), "BOTTOMLEFT", left, top)
    self.startX, self.startW, self.width = x, f:GetWidth(), f:GetWidth()
    self:SetScript("OnUpdate", GripUpdate)
    return true
end

function UI.GripStop(self)
    if not self.startX then return end
    self:SetScript("OnUpdate", nil)
    self.startX = nil
    UI.SavePos()
    ns.Settings.Set("width", math.floor((self.width or UI.Width()) + 0.5))
end

local function Grip(f)
    local g = CreateFrame("Button", nil, f)
    g:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TitleH())
    g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    g:SetWidth(GRIP_W)
    g:SetFrameLevel((f:GetFrameLevel() or 0) + 20)   -- above the step rows
    g.line = K.Fill(g, "OVERLAY", "accent")
    g.line:SetWidth(2)
    g.line:SetPoint("TOPRIGHT", g, "TOPRIGHT", -1, 0)
    g.line:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -1, 0)
    g.line:Hide()
    g:SetScript("OnEnter", function(self)
        if ns.Settings.Get("locked") then return end
        self.line:Show()
        K.Tooltip(self, L().TIP_GRIP)
    end)
    g:SetScript("OnLeave", function(self)
        if not self.startX then self.line:Hide() end
        K.HideTooltip()
    end)
    g:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then ns.Errors.Call("ui", UI.GripStart, self) end
    end)
    g:SetScript("OnMouseUp", function(self)
        ns.Errors.Call("ui", UI.GripStop, self)
        self.line:Hide()
    end)
    return g
end

function UI.Build()
    if UI.built then return end
    UI.built = true
    local f = CreateFrame("Frame", nil, Co.UIParent())
    UI.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetWidth(UI.Width())
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    K.Panel(f, true)
    UI.title = TitleBar(f)
    UI.header = Header(f)
    UI.noticeLine = NoticeLine(f)
    UI.chip = Chip(f)
    UI.area = CreateFrame("Frame", nil, f)
    UI.area:SetPoint("LEFT", f, "LEFT", 1, 0)
    UI.area:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    UI.nextLine = K.Text(UI.area, "goal", "upcoming")
    UI.nextLine:SetPoint("BOTTOMLEFT", UI.area, "BOTTOMLEFT", Pad(), 2)
    UI.nextLine:SetPoint("BOTTOMRIGHT", UI.area, "BOTTOMRIGHT", -Pad(), 2)
    -- the NOW box (the current step in its own panel, a small "NOW" header, accent edge) and the NEXT
    -- header over the following steps. Drawn on the step area itself, so the rows (child frames) are on top.
    local nb = {}
    nb.bg = K.Fill(UI.area, "BACKGROUND", "nowBg")
    nb.edges = {}
    for i = 1, 4 do nb.edges[i] = K.Fill(UI.area, "BORDER", "nowEdge") end
    nb.bar = K.Fill(UI.area, "ARTWORK", "nowBar")
    nb.head = K.Text(UI.area, "sectionHead", "nowHead")
    UI.nowBox = nb
    UI.nextHead = K.Text(UI.area, "sectionHead", "nextHead")
    UI.stateIcon = UI.area:CreateTexture(nil, "ARTWORK")
    UI.stateIcon:SetSize(32, 32)
    UI.stateIcon:SetPoint("TOP", UI.area, "TOP", 0, -LH())
    UI.stateText = K.Text(UI.area, "step", "text.dim", "CENTER")
    UI.stateText:SetWordWrap(true)
    UI.stateText:SetPoint("TOP", UI.stateIcon, "BOTTOM", 0, -6)
    UI.stateText:SetPoint("LEFT", UI.area, "LEFT", Pad() * 2, 0)
    UI.stateText:SetPoint("RIGHT", UI.area, "RIGHT", -Pad() * 2, 0)
    UI.footer = Footer(f)
    UI.grip = Grip(f)
    UI.ApplyPos()
    UI.Layout()
    UI.ApplyOpacity()
    f:Hide()
end

-- ------------------------------------------------------------------ layout (fixed heights)
function UI.Layout()
    local f, small = UI.frame, UI.Small()
    f:SetScale(ns.Overlay.WindowScale())
    f:SetHeight(UI.Height(small))
    f:SetWidth(UI.Width())
    UI.grip:SetShown(not ns.Settings.Get("locked"))
    UI.header:SetShown(not small)
    -- the header and notice line follow the line height (font size setting), so the step area stays
    -- right under the header
    UI.header:SetHeight(LH())
    UI.noticeLine:SetHeight(LH())
    UI.chip:SetShown(not small)
    UI.footer:SetShown(not small)
    UI.noticeLine:ClearAllPoints()
    UI.area:ClearAllPoints()
    UI.area:SetPoint("LEFT", f, "LEFT", 1, 0)
    UI.area:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    if small then
        UI.area:SetPoint("TOP", f, "TOP", 0, -TitleH())
        -- the notice takes the "Next:" line's place
        UI.noticeLine:SetPoint("BOTTOMLEFT", UI.area, "BOTTOMLEFT", Pad(), 0)
        UI.noticeLine:SetPoint("BOTTOMRIGHT", UI.area, "BOTTOMRIGHT", -Pad(), 0)
    else
        -- v0.2 fix (the user: "wasn't we moving the NOW step to the top?"): the step area, and so the NOW
        -- box, sits right under the section header; the notice line and the "n done" chip go under the
        -- steps (they used to sit above the NOW box and push it down the window)
        UI.area:SetPoint("TOP", f, "TOP", 0, -(TitleH() + LH()))
        local below = TitleH() + LH() + UI.AreaHeight(false)
        UI.noticeLine:SetPoint("TOPLEFT", f, "TOPLEFT", Pad(), -below)
        UI.noticeLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Pad(), -below)
        UI.chip:ClearAllPoints()
        UI.chip:SetPoint("TOPLEFT", f, "TOPLEFT", Pad(), -(below + LH() + 1))
        UI.chip:SetHeight(LH() - 2)
        UI.chip:SetWidth(UI.ChipWidth())
    end
    UI.area:SetHeight(UI.AreaHeight(small))
    Th.Glyph(UI.title.small.icon, small and "btn.expand" or "btn.small")
    Th.Glyph(UI.title.lock.icon, ns.Settings.Get("locked") and "btn.lock" or "btn.unlock")
    -- the step button re-places itself (height, width or scale may have moved the window's top-left)
    ns.Bus.Fire("WindowLayout")
end

-- Panel alpha = the opacity setting (v0.2 fix: no combat fade any more, the window looks the same in
-- combat); texts get a shadow when the panel is very see-through.
function UI.ApplyOpacity()
    local a = ns.Overlay.Opacity(ns.Settings.Get("opacity"))
    K.SetPanelAlpha(a)
    local shadow = a < 0.5
    if shadow ~= UI.shadow then
        UI.shadow = shadow
        K.RefreshFonts(shadow)
    end
end

-- ------------------------------------------------------------------ data for the rows
local function Goals(top, step)
    local out = {}
    local GS = ns.GameState
    if step.type == "objective" then
        if step.item then
            local need = step.count or 1
            local have = GS.ItemCount(step.item)
            out[1] = { text = L().GOAL_ITEMS, have = math.min(have, need), need = need, done = have >= need }
        else
            local qs = step.quest and GS.Quest(step.quest)
            if qs then
                local function Add(i)
                    local need = qs.need[i]
                    if not need then return end
                    local have = qs.have[i] or 0
                    out[#out + 1] = { text = qs.text and qs.text[i] or "", have = have, need = need, done = have >= need }
                end
                if ns.Packs.Len(step.obj) > 0 then
                    for _, i in ns.Packs.Each(step.obj) do Add(i) end
                else
                    for i = 1, #qs.need do Add(i) end
                end
            end
        end
    end
    -- v0.2: a level / grind step shows the XP bar as a goal line ("450/1000 XP")
    if step.type == "grind" or step.type == "level" then
        local GS2 = ns.GameState
        if GS2.xp and GS2.xpMax and GS2.xpMax > 0 then
            out[#out + 1] = { text = ns.U.Fill(L().GOAL_XP, { level = (ns.Engine.ctx.level or 0) + 1 }),
                have = GS2.xp, need = GS2.xpMax, done = false }
        end
    end
    for _, b in ipairs(top:Background()) do
        if b ~= step then
            local text = top:Text(b)
            if b.flags.optional then text = ns.U.Fill(L().OPTIONAL_LINE, { text = text }) end
            out[#out + 1] = { text = text, done = false }
        end
    end
    -- v0.2: dynamic First Aid lines ("Optional: make 12 Linen Bandage ..."), like optional steps
    for _, t in ipairs(ns.FirstAid and ns.FirstAid.Lines() or {}) do
        out[#out + 1] = { text = ns.U.Fill(L().OPTIONAL_LINE, { text = t }), done = false, firstAid = true }
    end
    return out
end

-- "in 2 levels" / "at 450/1000 XP" for a step waiting for a level (v0.2), or nil.
function UI.UnderLevelText(top, step)
    local levels, xp, max = top:UnderLevel(step)
    if not levels then return nil end
    if levels == 1 and xp and max and max > 0 then
        return ns.U.Fill(L().UNDER_XP, { have = xp, need = max })
    end
    return ns.Locale.Plural(levels, "UNDER_LEVEL")
end

local function Coord(step)
    if not (step.map and step.x and step.y) then return nil end
    return { text = ("%.1f, %.1f"):format(step.x * 100, step.y * 100), dist = UI.DistText(step) }
end

function UI.DistText(step)
    if not (step and step.map and step.x and step.y) then return nil end
    local d = ns.Geo.PlayerDistance(step.map, step.x, step.y)
    if not d then return nil end
    return ns.U.Fill(L().YARDS, { n = math.floor(d + 0.5) })
end

local function Wrap(field, v)
    if field == "quest" and v then return Th.Wrap("quest", v) end
    return v
end

-- "Done?" for display only: a travel step's Done() latches "reached" (it would finish a step the
-- player hasn't walked to yet), so the window only reads that latch.
local function ShownDone(top, s)
    if ns.StepTypes.Get(s.type).travel then return top.reached[s.id] == true end
    return top:Done(s)
end
UI.ShownDone = ShownDone

-- The upcoming steps after the current one (as many as could fit), in route order.
local function Upcoming(top, cur, max)
    local out = {}
    local n = top:Count()
    local j = top.pos
    while j <= n and #out < max do
        local s = top:Step(j)
        -- (v0.2: a future step waiting for a level shows too, with "in 2 levels"; optional steps sit
        -- with the background goals instead)
        local fits = s and (top:Applicable(s) or (s.minLevel and top:UnderLevel(s) ~= nil and top:Applicable(s, true)))
        if s and s ~= cur and s.index ~= cur.index and fits and not top:Skipped(s)
            and not ShownDone(top, s) and not s.whileUntil and not s.flags.optional then
            out[#out + 1] = s
        end
        j = j + 1
    end
    return out
end

-- What the window shows now: { state = "guide" | "none" | "finished" | "error" | "safe", ... }.
function UI.Model()
    if ns.safeMode then return { state = "safe" } end
    local g = ns.Engine.Focused()
    if not g then return { state = "none" } end
    local cur, top = ns.Engine.Current()
    if not cur then return { state = "finished", guide = g } end
    local m = { state = "guide", guide = g, top = top, cur = cur }
    local route = top.route
    local sec = ns.Packs.Section(route, cur.index or top.pos)
    local secTitle = sec and ((ns.Locale.code == "daDK" and sec.da) or sec.title)
    -- the guide's name (pack header), not the route's mode name ("Normal")
    local h = route.header or g.header or {}
    m.title = (ns.Locale.code == "daDK" and h.da) or h.title or route.title or route.id
    m.section = secTitle or m.title
    -- numbers count only the steps for this character (rows for other classes / races don't count)
    m.pos = cur.index or top.pos
    local numbers, count = UI.Numbers(top)
    m.index, m.count = numbers[m.pos] or 1, count
    -- the distance shows once: on the coordinate line (the arrow keeps it fresh); only a step
    -- without a coordinate line could carry it on the right, and that one has no spot anyway
    local coord = Coord(cur)
    m.rows = { { step = cur, number = m.index, badge = K.BadgeKind(cur), text = top:Text(cur, Wrap), state = "current",
        right = not coord and UI.DistText(cur) or nil, goals = Goals(top, cur), coord = coord } }
    for _, s in ipairs(Upcoming(top, cur, 8)) do
        m.rows[#m.rows + 1] = { step = s, number = numbers[s.index], badge = K.BadgeKind(s), text = top:Text(s), state = "upcoming",
            right = UI.UnderLevelText(top, s) }
    end
    m.done = math.max(0, m.index - 1)
    return m
end

-- Position -> shown number, over the steps that apply to this character; and how many apply.
-- Small mode: the current step must fit above the "Next:" / notice line. One text line, then as
-- many goal lines as fit (goals first, the coordinate line last). Returns a trimmed copy.
function UI.FitSmall(d, avail)
    local lh, lg = Th.LineHeight("step"), Th.LineHeight("goal")
    local room = math.max(0, math.floor((avail - lh) / lg))
    local out = {}
    for k, v in pairs(d) do out[k] = v end
    out.maxLines = 1
    local goals = {}
    for i = 1, math.min(#(d.goals or {}), room) do goals[i] = d.goals[i] end
    out.goals = goals
    if d.coord and #goals >= room then out.coord = nil end
    return out
end

-- Worked out on each refresh (conditions may read the level or quest state); refreshes come from
-- events, never per frame.
-- v0.2 M6 (perf, long routes): whether a step applies only changes for steps with a minLevel or a dynamic
-- condition; every other answer is fixed for the guide's lifetime (static conditions are cached per guide
-- too). So the fixed answers are worked out once per guide (weak keys: nothing kept after the guide closes)
-- and only the live steps are checked on each refresh, instead of decoding every row of the route.
local numCache = setmetatable({}, { __mode = "k" })
local function NumInfo(top)
    local count = top:Count()
    local c = numCache[top]
    if c and c.count == count then return c end
    c = { count = count, fixed = {}, live = {} }
    for j = 1, count do
        local s = top:Step(j)
        if not s then
            c.fixed[j] = 0
        elseif s.minLevel or (s.cond and s.condAst and s.condAst.info and s.condAst.info.dynamic) then
            c.live[#c.live + 1] = j
        else
            c.fixed[j] = top:Applicable(s) and 1 or 0
        end
    end
    numCache[top] = c
    return c
end

-- Optimizer #4: the numbers list is kept in the cache entry and reused while the live answers are the same
-- (the caller only reads it). Returns numbers, count.
function UI.Numbers(top)
    local c = NumInfo(top)
    local live = c.liveAns
    if not live then
        live = {}
        c.liveAns = live
    end
    local same = c.numbers ~= nil
    for _, j in ipairs(c.live) do
        local s = top:Step(j)
        local v = (s and top:Applicable(s)) and 1 or 0
        if live[j] ~= v then
            live[j] = v
            same = false
        end
    end
    if same then return c.numbers, c.n end
    local numbers, n, fixed = c.numbers or {}, 0, c.fixed
    for j = 1, c.count do
        n = n + (fixed[j] or live[j] or 0)
        numbers[j] = math.max(n, 1)
    end
    c.numbers, c.n = numbers, n
    return numbers, n
end

-- ------------------------------------------------------------------ drawing
local function Row(i)
    local r = UI.rows[i]
    if not r then
        r = ns.Rows.New(UI.area)
        UI.rows[i] = r
        -- v0.2 M3: right-click a step for its menu (skip, set current, not doing, point here, copy /way)
        r:EnableMouse(true)
        r:SetScript("OnMouseUp", function(self, button)
            if not self.step then return end
            if button == "RightButton" then
                ns.Errors.Call("ui", function() ns.Menu.Open(self, UI.StepMenu(self.step)) end)
            elseif button == "LeftButton" then
                ns.Errors.Call("ui", UI.StepClick, self.step, self.current)
            end
        end)
        r:SetScript("OnEnter", function(self) if self.step then ns.Errors.Call("ui", UI.StepTip, self) end end)
        r:SetScript("OnLeave", K.HideTooltip)
    end
    return r
end

local STATE_TEXT = { none = "STATE_NONE", finished = "STATE_FINISHED", error = "STATE_ERROR", safe = "STATE_SAFE" }
local STATE_GLYPH = { none = "state.none", finished = "state.finished", error = "state.error", safe = "state.error" }

-- Shows / hides the NOW box (all its textures and its header).
local function NowShown(on)
    local nb = UI.nowBox
    nb.bg:SetShown(on)
    nb.bar:SetShown(on)
    nb.head:SetShown(on)
    for _, e in ipairs(nb.edges) do e:SetShown(on) end
end

-- Places the NOW box from the area's top down to `bottom` (units from the area's top), inset by nowMargin.
local function PlaceNowBox(bottom)
    local nb, a = UI.nowBox, UI.area
    local m = Th.Size("nowMargin")
    local hair = K.Hair(Th.Size("border"))
    nb.bg:ClearAllPoints()
    nb.bg:SetPoint("TOPLEFT", a, "TOPLEFT", m, -m)
    nb.bg:SetPoint("BOTTOMRIGHT", a, "TOPRIGHT", -m, -bottom)
    local sides = { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }
    for i, s in ipairs(sides) do
        local e = nb.edges[i]
        e:ClearAllPoints()
        e:SetPoint(s[1], nb.bg, s[1], 0, 0)
        e:SetPoint(s[2], nb.bg, s[2], 0, 0)
        if s[3] then e:SetHeight(hair) else e:SetWidth(hair) end
    end
    nb.bar:ClearAllPoints()
    nb.bar:SetPoint("TOPLEFT", nb.bg, "TOPLEFT", 0, 0)
    nb.bar:SetPoint("BOTTOMLEFT", nb.bg, "BOTTOMLEFT", 0, 0)
    nb.bar:SetWidth(Th.Size("nowBar"))
    nb.head:ClearAllPoints()
    nb.head:SetPoint("TOPLEFT", nb.bg, "TOPLEFT", Pad(), -1)
    nb.head:SetText(L().NOW_HEAD)
end

local function DrawState(state)
    for _, r in ipairs(UI.rows) do r:Hide() end
    NowShown(false)
    UI.nextHead:Hide()
    UI.nextLine:SetText("")
    UI.stateIcon:Show()
    Th.Glyph(UI.stateIcon, STATE_GLYPH[state])
    UI.stateIcon:SetVertexColor(Th.Color(state == "finished" and "accent" or "text.dim"))
    UI.stateText:Show()
    UI.stateText:SetText(L()[STATE_TEXT[state]])
    UI.title.title:SetText(L().TITLE)
    UI.header.text:SetText("")
    UI.header.counter:SetText("")
    UI.chip:Hide()
    UI.footer.fill:Hide()
    UI.footer.pct:SetText("")
    -- nothing to step through without a guide: no back / next
    UI.footer.prev:Hide()
    UI.footer.next:Hide()
end

local function DrawNotice()
    local n = ns.Notice.Top()
    UI.notice = n
    local line = UI.noticeLine
    if not n then
        line:Hide()
        return false
    end
    line:Show()
    line.text:SetText(ns.Notice.Cut(n.text))
    K.Color(line.text, n.kind == "danger" and "notice.danger" or "notice")
    local iconKey = n.icon or (n.kind == "danger" and "notice.danger" or "notice.tip")
    Th.Glyph(line.icon, iconKey)
    line.icon:SetVertexColor(Th.Color(n.kind == "danger" and "notice.danger" or n.iconColor or "accent"))
    if n.button and n.button.text then
        line.btn:Show()
        line.btn.text:SetText(n.button.text)
        line.btn:SetWidth(math.max(40, (line.btn.text:GetStringWidth() or 30) + 12))
    else
        line.btn:Hide()
        line.btn:SetWidth(1)
    end
    return true
end

function UI.Refresh()
    if not UI.frame or not UI.frame:IsShown() then return end
    UI.refreshes = UI.refreshes + 1
    local small = UI.Small()
    local ok, m = ns.Errors.Call("ui", UI.Model)
    if not ok or type(m) ~= "table" then m = { state = "error" } end
    UI.model = m
    if m.state ~= "guide" then
        DrawState(m.state)
        DrawNotice()
        if ns.Waypoint then ns.Waypoint.Clear("step") elseif ns.Arrow then ns.Arrow.SetTarget(nil) end
        return
    end
    UI.stateIcon:Hide()
    UI.stateText:Hide()
    UI.footer.prev:Show()
    UI.footer.next:Show()
    UI.title.title:SetText(m.title or L().TITLE)
    UI.header.text:SetText(m.section or "")
    UI.header.counter:SetText(ns.U.Fill(L().COUNTER, { i = m.index, n = m.count }))
    UI.chip:SetShown(not small and m.done > 0)
    UI.chip.text:SetText(ns.U.Fill(m.done == 1 and L().CHIP_DONE_ONE or L().CHIP_DONE_MANY, { n = m.done }))
    UI.chip:SetWidth(UI.ChipWidth())
    -- rows: the current step (row 1) in the NOW box, then the NEXT header and the following steps; a row
    -- that doesn't fit is hidden (the area never grows)
    local areaH = UI.AreaHeight(small)
    local reserve = small and Th.LineHeight("goal") or 0
    local margin, headH = Th.Size("nowMargin"), Th.LineHeight("sectionHead")
    local y, shown, nextShown = margin + headH, 0, 0
    local maxRows = small and 1 or #m.rows
    UI.nextHead:Hide()
    for i, d in ipairs(m.rows) do
        local r = Row(i)
        -- (v0.2 fix: no combat filter any more; the user wants every step shown in combat. The rows are
        -- plain frames, nothing secure, so showing them in combat is taint-safe.)
        if i > maxRows then
            r:Hide()
        else
            d.boxed = i == 1
            if small and i == 1 then d = UI.FitSmall(d, areaH - reserve - UI.NowChrome()) end
            local h = ns.Rows.Set(r, d)
            if i > 1 and y + h > areaH - reserve then
                r:Hide()
            else
                r:ClearAllPoints()
                local inset = i == 1 and margin or 0
                r:SetPoint("TOPLEFT", UI.area, "TOPLEFT", inset, -y)
                r:SetPoint("TOPRIGHT", UI.area, "TOPRIGHT", -inset, -y)
                r:Show()
                y = y + h
                shown = shown + 1
                if i == 1 then
                    -- close the NOW box under the current step; the NEXT header follows (full mode)
                    y = y + Th.Size("nowPadBottom")
                    PlaceNowBox(y)
                    if not small then
                        y = y + Th.Size("sectionGap")
                        UI.nextHead:ClearAllPoints()
                        UI.nextHead:SetPoint("TOPLEFT", UI.area, "TOPLEFT", Pad(), -y)
                        UI.nextHead:SetText(L().NEXT_HEAD)
                        y = y + headH
                    end
                else
                    nextShown = nextShown + 1
                end
            end
        end
    end
    NowShown(shown > 0)
    UI.nextHead:SetShown(not small and nextShown > 0)
    for i = #m.rows + 1, #UI.rows do UI.rows[i]:Hide() end
    UI.shownRows = shown
    -- small mode: one "Next:" line under the current step (a notice takes its place)
    local nxt = m.rows[2]
    UI.nextLine:SetText(small and nxt and ns.U.Fill(L().NEXT_LINE, { text = nxt.text }) or "")
    local noticeShown = DrawNotice()
    if small and noticeShown then UI.nextLine:SetText("") end
    -- footer progress
    local frac = m.count > 0 and (m.index - 1) / m.count or 0
    local track = UI.footer.track:GetWidth() or 0
    UI.footer.fill:SetShown(frac > 0 and track > 0)
    UI.footer.fill:SetWidth(math.max(1, track * frac))
    UI.footer.pct:SetText(("%d%%"):format(math.floor(frac * 100 + 0.5)))
    -- finished-a-step flash on the new top row
    if UI.lastId and UI.lastId ~= m.cur.id and UI.lastStep and ShownDone(m.top, UI.lastStep) then ns.Rows.Flash(UI.rows[1]) end
    UI.lastId, UI.lastStep = m.cur.id, m.cur
    if ns.Waypoint then ns.Waypoint.Set("step", m.cur) elseif ns.Arrow then ns.Arrow.SetTarget(m.cur) end
end

-- ------------------------------------------------------------------ step hover and clicks (v0.2 M3)
-- Left-click: point the arrow at the step's spot (the current step: back to the step itself).
-- Shift-click: the quest's link into the chat box the player has open (never sent).
-- Ctrl-click: the world map at the step's map (out of combat).
function UI.StepClick(step, current)
    if Co.Modifier("shift") then
        if step.quest then return Co.InsertQuestLink(step.quest) end
        return false
    end
    if Co.Modifier("ctrl") then
        if step.map then return Co.OpenMap(step.map) end
        return false
    end
    local WP = ns.Waypoint
    if not (WP and step.map and step.x and step.y) then return false end
    if current then WP.ClearManual() return true end
    local g = ns.Engine.Focused()
    return WP.Set("show", { map = step.map, x = step.x, y = step.y, r = step.r, title = g and g:Top():Text(step) })
end

-- The hover lines, in a fixed order: quest, place, why it's grey / waiting, then what clicks do.
function UI.StepLines(step, rightText)
    local lines = {}
    if step.quest and ns.Names then
        local name = ns.Names.Quest(step.quest)
        if name then lines[#lines + 1] = name end
    end
    if step.map and step.x and step.y then
        local where = ("%.1f, %.1f"):format(step.x * 100, step.y * 100)
        local zone = Co.MapName(step.map)
        lines[#lines + 1] = zone and (zone .. " " .. where) or where
    end
    if step.minLevel then lines[#lines + 1] = ns.U.Fill(L().TIP_STEP_LEVEL, { level = step.minLevel }) end
    if rightText then lines[#lines + 1] = rightText end
    if step.flags and step.flags.optional then lines[#lines + 1] = L().TIP_STEP_OPTIONAL end
    if step.map and step.x and step.y then lines[#lines + 1] = L().PIN_CLICK end
    if step.quest then lines[#lines + 1] = L().TIP_STEP_SHIFT end
    if step.map then lines[#lines + 1] = L().TIP_STEP_CTRL end
    lines[#lines + 1] = L().TIP_STEP_RIGHT
    return lines
end

function UI.StepTip(row)
    local step = row.step
    local g = ns.Engine.Focused()
    local title = g and g:Top():Text(step) or step.id
    K.Tooltip(row, title, UI.StepLines(step, row.rightText))
end

-- ------------------------------------------------------------------ menus
-- The right-click menu of a step row (v0.2 M3). Everything goes through the engine / arbiter (undo-able).
function UI.StepMenu(step)
    local E, WP = ns.Engine, ns.Waypoint
    local items = {
        { text = L().MENU_STEP_SKIP, fn = function() E.Skip(step.id) end },
        { text = L().MENU_STEP_CURRENT, fn = function() E.SetCurrent(step.id) end },
    }
    if step.quest then
        items[#items + 1] = { text = L().MENU_STEP_NOTDOING, fn = function() E.NotDoing(step.quest) end }
    end
    if WP and step.map and step.x and step.y then
        items[#items + 1] = { text = L().MENU_STEP_POINT, fn = function()
            local g = E.Focused()
            WP.Set("show", { map = step.map, x = step.x, y = step.y, r = step.r, title = g and g:Top():Text(step) })
        end }
        items[#items + 1] = { text = L().MENU_STEP_WAY, fn = function()
            local g = E.Focused()
            local line = WP.WayLine({ map = step.map, x = step.x, y = step.y, title = g and g:Top():Text(step) })
            if line and ns.Popups.Copy then ns.Popups.Copy(L().COPY_WAY, line) end
        end }
    end
    if WP and (WP.targets.show or WP.targets.external) then
        items[#items + 1] = { text = L().MENU_WAY_CLEAR, fn = function() WP.ClearManual() end }
    end
    return items
end

function UI.ChipItems()
    local items = {}
    local m = UI.model
    if not m or m.state ~= "guide" then return items end
    local top = m.top
    local j = m.pos - 1
    while j >= 1 and #items < CHIP_MAX do
        local s = top:Step(j)
        if s and top:Applicable(s) then
            local id = s.id
            items[#items + 1] = { text = top:Text(s), checked = ShownDone(top, s), fn = function() ns.Engine.SetCurrent(id) end }
        end
        j = j - 1
    end
    return items
end

function UI.MenuItems()
    local S = ns.Settings
    local items = {
        { text = L().MENU_SMALL, checked = S.Get("small"), fn = function() S.Set("small", not S.Get("small")) end },
        { text = L().MENU_LOCK, checked = S.Get("locked"), fn = function() S.Set("locked", not S.Get("locked")) end },
        { text = L().MENU_QUIET, checked = S.Get("quiet"), fn = function() S.Set("quiet", not S.Get("quiet")) end },
        { text = L().MENU_ARROW, checked = S.Get("arrow"), fn = function() S.Set("arrow", not S.Get("arrow")) end },
        { text = L().MENU_MOTION, checked = S.Get("reducedMotion"),
            fn = function() S.Set("reducedMotion", not S.Get("reducedMotion")) end },
        { text = L().MENU_MAPPINS, checked = S.Get("mapPins"), fn = function() S.Set("mapPins", not S.Get("mapPins")) end },
        { text = L().MENU_MINIPINS, checked = S.Get("minimapPins"),
            fn = function() S.Set("minimapPins", not S.Get("minimapPins")) end },
    }
    -- v0.2 M4: every setting in Blizzard's AddOns options (without them, this menu and /aog are the way)
    if ns.SettingsUI and ns.SettingsUI.Available() then
        table.insert(items, 1, { text = L().MENU_SETTINGS, fn = function() ns.SettingsUI.Open() end })
    end
    -- a click-through arrow can't be right-clicked, so its switch is here too (only while it's on)
    if S.Get("arrowClickThrough") then
        items[#items + 1] = { text = L().MENU_ARROW_CLICK, checked = true, fn = function() S.Set("arrowClickThrough", false) end }
    end
    -- opacity: one row that steps 100 -> 80 -> 60 -> 40 % (v0.2 M4: was four rows; the settings panel
    -- has the slider)
    local steps, op = { 1, 0.8, 0.6, 0.4 }, S.Get("opacity")
    local nextOp = steps[1]
    for i, v in ipairs(steps) do if math.abs(op - v) < 0.01 then nextOp = steps[i % #steps + 1] end end
    items[#items + 1] = { text = ns.U.Fill(L().MENU_OPACITY, { n = math.floor(op * 100 + 0.5) }),
        fn = function() S.Set("opacity", nextOp) end }
    -- "use it now" reminder level: one row that steps through off / glow / text / sound (v0.2)
    local levels = { "off", "glow", "text", "sound" }
    local cur = S.Get("reminder")
    local nextLevel = levels[1]
    for i, v in ipairs(levels) do if v == cur then nextLevel = levels[i % #levels + 1] end end
    items[#items + 1] = { text = ns.U.Fill(L().MENU_REMINDER, { level = L()["REMINDER_" .. cur:upper()] or cur }),
        fn = function() S.Set("reminder", nextLevel) end }
    items[#items + 1] = { text = L().MENU_RESETPOS, fn = UI.ResetPos }
    -- v0.2 M5: Report a mistake (the Hub's Report page; About and What's new are next to it there)
    if not ns.safeMode then items[#items + 1] = { text = L().MENU_REPORT, fn = function() ns.HubReport.Open() end } end
    -- the guides for this character (built from the installed packs; at most 3 rows)
    local E = ns.Engine
    local _, ids = E.GuideList()
    local g = E.Focused()
    local focusPack = g and g.key:match("^([^/]+)")
    for i = 1, math.min(3, #ids) do
        local id = ids[i]
        items[#items + 1] = { text = ns.U.Fill(L().MENU_GUIDE, { guide = E.GuideTitle(id) }), checked = id == focusPack,
            fn = function() E.OpenGuide(id) end }
    end
    -- "Link with Gear Set": only when Gear Set is loaded (v0.1.1)
    local gs = ns.GearSet and ns.GearSet.MenuItem()
    if gs then items[#items + 1] = gs end
    -- language: in the settings panel (General > Language, the user's wish 2026-11-25) and /aog lang.
    -- Only without a settings panel (feature "settings" off) are the two rows here, so it stays clickable.
    if not (ns.SettingsUI and ns.SettingsUI.Available()) then
        local lang = S.Get("lang")
        items[#items + 1] = { text = "English", checked = lang ~= "da",
            fn = function() ns.Locale.Switch("en") end }
        items[#items + 1] = { text = "Dansk", checked = lang == "da",
            fn = function() ns.Locale.Switch("da") end }
    end
    return items
end

-- ------------------------------------------------------------------ show / hide
-- keep = true: don't remember it (the self-test opens and closes the window for a moment).
function UI.Show(keep)
    UI.Build()
    UI.frame:Show()
    ns.Jobs.SetUIShown(true)
    if not ns.safeMode and not keep then ns.Settings.Set("shown", true) end
    UI.Refresh()
    ns.Bus.Fire("WindowToggled")
end

function UI.Hide(keep)
    if not UI.frame then return end
    UI.frame:Hide()
    ns.Jobs.SetUIShown(false)
    ns.Menu.Close()
    if not ns.safeMode and not keep then ns.Settings.Set("shown", false) end
    if ns.Arrow then ns.Arrow.SetTarget(nil) end
    ns.Bus.Fire("WindowToggled")
end

function UI.Toggle()
    if UI.frame and UI.frame:IsShown() then UI.Hide() else UI.Show() end
end

function UI.IsShown() return UI.frame ~= nil and UI.frame:IsShown() end

-- ------------------------------------------------------------------ wiring
local function OnSettings(_, key)
    if not UI.frame then return end
    if key == "small" or key == "locked" or key == "width" then
        UI.Layout()
        UI.Refresh()
    elseif key == "opacity" then
        UI.ApplyOpacity()
    elseif key == "reducedMotion" or key == "quiet" then
        UI.Refresh()
    end
end
ns.Bus.On("SettingsChanged", UI, OnSettings, "ui", 70)
ns.Bus.On("StepChanged", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("NoticeChanged", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("QuestsChanged", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("ItemsChanged", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("NameReady", UI, function() UI.Refresh() end, "ui", 70)
-- combat changes nothing in the window's look: every step stays shown, no fade (v0.2 fix, the user's wish)
ns.Bus.On("CombatStarted", UI, function()
    UI.inCombat = true
    if UI.frame then UI.ApplyOpacity() UI.Refresh() end
end, "ui", 70)
ns.Bus.On("CombatEnded", UI, function()
    UI.inCombat = false
    if UI.frame then UI.ApplyOpacity() UI.Refresh() end
end, "ui", 70)
-- v0.2 M4: high contrast / colour-blind / font size, and scale / screen changes (Theme\Overlay.lua)
ns.Bus.On("LookChanged", UI, function()
    if not UI.frame then return end
    UI.shadow = nil
    UI.Layout()
    UI.ApplyOpacity()
    UI.Refresh()
end, "ui", 70)
ns.Bus.On("ScaleChanged", UI, function()
    if not UI.frame then return end
    UI.Layout()
    ns.Overlay.KeepOnScreen(UI.frame)
end, "ui", 70)

-- v0.2 M4: why the window stays away by itself: "char" (Use the guide on this character is off), "bg" /
-- "raid" (switched off there), or nil. The player's own show / hide (setting shown) is kept as it is.
function UI.Suppressed()
    local S = ns.Settings
    if not S.Get("useOnChar") then return "char" end
    local kind = Co.InstanceType()
    if (kind == "pvp" or kind == "arena") and S.Get("offInBG") then return "bg" end
    if kind == "raid" and S.Get("offInRaid") then return "raid" end
    return nil
end

-- Hides the window while it's suppressed and brings it back after (only when it was open before).
function UI.CheckSuppressed()
    local why = UI.Suppressed()
    UI.suppressed = why
    if why then
        if UI.IsShown() then UI.Hide(true) end
    elseif ns.Settings.Get("shown") and not UI.IsShown() then
        UI.Show(true)
    end
end

-- After login: open the window if it was open last time (default: open).
ns.Bus.On("Login", UI, function()
    UI.suppressed = UI.Suppressed()
    if ns.Settings.Get("shown") and not UI.suppressed then UI.Show() end
end, "ui", 80)
ns.Bus.On("ZoneChanged", UI, function() ns.Errors.Call("ui", UI.CheckSuppressed) end, "ui", 70)
ns.Bus.On("SettingsChanged", UI.Suppressed, function(_, key)
    if key == "useOnChar" or key == "offInBG" or key == "offInRaid" then UI.CheckSuppressed() end
end, "ui", 71)

-- The NOW box's state: nil when right (or not judged now), else a short reason. Self-test + offline tests.
function UI.NowProblem()
    local m, r, nb = UI.model, UI.rows[1], UI.nowBox
    if not (UI.frame and UI.frame:IsShown() and m and m.state == "guide" and nb) then return nil end
    if not (r and r:IsShown()) then return "the current step isn't shown" end
    if not (r.step and m.cur and r.step.id == m.cur.id) then return "the NOW box doesn't hold the current step" end
    if not nb.bg:IsShown() then return "the NOW box is hidden" end
    local bt, bb, rt, rb = nb.bg:GetTop(), nb.bg:GetBottom(), r:GetTop(), r:GetBottom()
    if type(bt) == "number" and type(rt) == "number" and type(bb) == "number" and type(rb) == "number"
        and (rt > bt + 0.5 or rb < bb - 0.5) then
        return "the current step sticks out of the NOW box"
    end
    -- v0.2 fix: the box is on top (above the first NEXT row, the notice line and the chip)
    local function Above(o)
        local t = o and o:IsShown() and o:GetTop()
        return not (type(bt) == "number" and type(t) == "number") or bt > t
    end
    if not (Above(UI.rows[2]) and Above(UI.noticeLine) and Above(UI.chip)) then
        return "the NOW box isn't on top"
    end
    return nil
end
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "nowbox", fn = function(h)
    h.Count()
    local bad = UI.NowProblem()
    if bad then h.Problem("nowbox: " .. bad) end
end }

ns.Slash.SetDefault(function() UI.Toggle() end)
ns.Slash.Add("resetpos", function() UI.ResetPos() end, "HELP_RESETPOS")

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The guide window = the one window (2026-11-26, mock-up 4f, plans\guide-window-look\build-plan.md). From the top:
-- title bar (logo, zone, menu / lock / small / close; rounded, soft shadow), the step block (3D view top-left, the
-- step text with its coloured verb, "for <quest>" and the place line right of it, the goal lines under it at full
-- width, the goal to do now tinted), the next steps (tile, coloured verb, coords; setting "lines"), the info chips
-- (route, level / XP, time left) and the row with back / progress bar ("step i / n · p %") / next. A notice takes
-- the last next-step line. The item / target buttons sit in a row above the window's top-left (UI\StepButton.lua,
-- UI\TargetButton.lua). Every step stays shown in combat.
-- Anchored by its bottom-left: a tall current step grows the window UP (the bottom stays; the user's wish) and it
-- shrinks back on the next step; never past the screen top; in combat the height holds (the secure buttons above
-- it move only out of combat) and a too tall step is cut to what fits until the fight ends.
-- Small mode keeps the same width: title bar, the current step and one "Next:" line (a notice replaces it).
-- States: none / finished / error / safe. Clamped to the screen; the position is saved per character only after the
-- player moves it. Opacity changes the panel alpha only (text stays at full alpha and gets a shadow under 0.5).
-- Esc never closes it (it isn't a UI panel).
--   ns.UI.Show(), Hide(), Toggle(), Refresh(), ResetPos(), IsShown(); ns.UI.frame and its parts
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local UI = { rows = {}, built = false, refreshes = 0 }
ns.UI = UI

-- the default spot: bottom right, above the action bars (anchored by the bottom: the window grows up)
local DEFAULT_POINT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -90, 240 }
local CHIP_MAX = 10

local function LH() return Th.LineHeight("step") end
local function LG() return Th.LineHeight("goal") end
local function Pad() return Th.Size("pad") end
local function TitleH() return Th.Size("title") end
local function L() return ns.L end

-- ------------------------------------------------------------------ sizes
function UI.Small() return ns.Settings.Get("small") end
-- The window width (v0.2 M3: the grip changes it; the step area's height never changes with it).
-- UI.liveWidth / UI.liveLines: the size while a grip is being dragged (nil otherwise; saved on release).
function UI.Width() return UI.liveWidth or ns.Settings.Get("width") end
-- The next steps' room in step-font lines (setting "lines", default 3; the bottom / corner grip changes it).
-- Capped at UI.LinesFit() (a save from a bigger screen or a UI scale change could make the window taller than the
-- screen). The saved value is kept as it is, so a bigger screen / smaller scale gets it back. While a grip drags,
-- its own limit (UI.LinesMax) applies.
local fitting = false
function UI.Lines()
    local n = UI.liveLines or ns.Settings.Get("lines")
    if fitting or UI.liveLines then return n end
    return math.min(n, UI.LinesFit())
end
-- The most next-step lines with which the whole window (and the button row above it) fits the screen's height.
function UI.LinesFit()
    local d = ns.Settings.byKey.lines
    local f, p = UI.frame, Co.UIParent()
    if not (f and p and f.GetEffectiveScale and p.GetEffectiveScale) then return d.max end
    local fs, ps, ph = f:GetEffectiveScale(), p:GetEffectiveScale(), p:GetHeight()
    if not (fs and ps and ph) or fs <= 0 or ps <= 0 or ph <= 0 then return d.max end
    local avail = ph * ps / fs - UI.TopRoom() - Th.Size("shadow")   -- the screen's height in the window's units
    fitting = true
    local ok, base = pcall(function() return UI.Height(false) - UI.Grow() - UI.Lines() * LH() end)
    fitting = false
    if not ok or type(base) ~= "number" then return d.max end
    return math.max(d.min, math.min(d.max, math.floor((avail - base) / LH())))
end
-- The room above the window's top kept for the item / target buttons (their frame sticks out 8 more).
function UI.ButtonRow()
    if not ns.Feature.IsOn("stepbutton") then return 0 end
    local SB = ns.StepButton
    return (SB and SB.SIZE or 36) + Th.Size("buttonRowGap") + 8
end
-- The room kept free above the window: the button row, at least the soft shadow.
function UI.TopRoom() return math.max(UI.ButtonRow(), Th.Size("shadow")) end
-- The step block's room without growing: the 3D view's square (or a text line and two sub lines) plus
-- size.blockGoals goal lines. A taller current step grows the window up by the difference.
function UI.BlockBase()
    local MV = ns.ModelView
    local slot = MV and MV.InsideSize and MV.InsideSize() or 0
    local pad = Th.Size("blockPad")
    return pad + math.max(slot > 0 and slot + pad or 0, LH() + 2 * LG()) + Th.Size("blockGoals") * LG()
end
-- The NEXT section's top gap (the divider sits in it).
function UI.NextChrome() return Th.Size("sectionGap") * 2 end
function UI.ChipH() return Th.LineHeight("small") + 4 end
-- The step area: full mode = the step block's room + the gap + the next steps' lines; small mode = its fixed lines.
function UI.AreaHeight(small)
    if small then return Th.Size("smallLines") * LH() end
    return UI.BlockBase() + UI.NextChrome() + UI.Lines() * LH()
end
-- Extra height for a current step taller than its room (0 almost always, set by Refresh).
function UI.Grow() return UI.grow or 0 end
-- The step area as shown: its fixed lines plus the grow.
function UI.ShownAreaHeight(small) return UI.AreaHeight(small) + UI.Grow() end
-- Under the step area (full mode): the chips row and the back / bar / next row.
function UI.BottomH() return 4 + UI.ChipH() + 2 + Th.Size("navH") + 5 end
function UI.Height(small)
    if small then return TitleH() + UI.ShownAreaHeight(true) + Pad() end
    return TitleH() + UI.ShownAreaHeight(false) + UI.BottomH()
end
-- Where the 3D view's square sits (window units from the top-left), and its size this step (nil = none).
function UI.SlotSpot() return Pad(), TitleH() + Th.Size("blockPad") end

-- ------------------------------------------------------------------ position (saved only when moved)
local function CanSave() return not ns.safeMode and not ns.DB.readOnly.char end

-- UI.sessionPos: the spot this session when it can't be written (read-only save, safe mode).
-- The one window's spot lives in modules.window.pos (bottom-left anchored); the old point / rel / x / y of the
-- two-window versions stay untouched in the save (an older version still finds its own spot). Before the one-time
-- move (UI.Migrate, flag oneWin) the old spot is used as it is.
local function Valid(m)
    return type(m) == "table" and type(m.point) == "string" and type(m.x) == "number" and type(m.y) == "number"
end
local function WinModule()
    local mods = ns.DB.char and type(ns.DB.char.modules) == "table" and ns.DB.char.modules
    local m = mods and mods.window
    return type(m) == "table" and m or nil
end
local function SavedPos()
    if UI.sessionPos then return UI.sessionPos end
    local m = WinModule()
    if not m then return nil end
    if Valid(m.pos) then return m.pos end
    if m.oneWin then return nil end
    return Valid(m) and m or nil
end
UI.SavedPos = SavedPos

-- The window on its spot (saved or default), anchored to the screen.
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
UI.ApplyGuidePos = UI.ApplyPos

local function StorePos(point, rel, x, y)
    UI.sessionPos = nil
    local p = { point = point, rel = rel or point, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    if CanSave() then
        local m = ns.DB.Module("window", "char", 1)
        m.pos = p
        m.oneWin = 1
    else
        UI.sessionPos = p
    end
end

-- Re-anchors the window by its bottom-left where it stands now (so a taller step grows it up) and saves that.
local function AnchorBottom(save)
    local f = UI.frame
    local l, b = f:GetLeft(), f:GetBottom()
    if not (l and b) then return false end
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", Co.UIParent(), "BOTTOMLEFT", l, b)
    if save then StorePos("BOTTOMLEFT", "BOTTOMLEFT", l, b) end
    return true
end

-- Saves the spot (when the save may be written) and always tells the others the window moved (the item / target
-- buttons follow it, also with a read-only save or in safe mode).
function UI.SavePos()
    AnchorBottom(true)
    ns.Bus.Fire("WindowMoved")
end

function UI.ResetPos()
    -- it moves the window the secure item button docks to: after combat (beta.3 fix), like scale
    if Co.InCombat() and ns.CombatQueue then
        ns.CombatQueue.Run("resetpos", UI.ResetPos)
        ns.Settings.TellWaits()
        return false
    end
    UI.sessionPos = nil
    local m = WinModule()
    if m and CanSave() then
        m.pos = nil
        -- (the default spot from now on, not the old two-window spot)
        if Valid(m) then m.oneWin = 1 end
    end
    if UI.frame then
        UI.ApplyPos()
        ns.Bus.Fire("WindowMoved")
    end
    if ns.Arrow then ns.Arrow.ResetPos() end
end

-- One-time move from the two windows (NOW window + guide window) to the one window, per character (flag
-- modules.window.oneWin; nothing old is deleted or changed). The old spot's top-left and bottom are worked out
-- from the saved spots and the old heights; a window in the lower half of the screen keeps its bottom, one in the
-- upper half its top. A save without an old spot gets nothing written. Read-only save / safe mode: a session spot.
function UI.Migrate()
    local char = ns.DB.char
    local mods = char and type(char.modules) == "table" and char.modules
    if not mods then return false end
    local w = type(mods.window) == "table" and mods.window or nil
    if w and (w.oneWin or Valid(w.pos)) then return false end
    local guide = Valid(w) and w or nil
    local nw = type(mods.nowwin) == "table" and mods.nowwin or nil
    local pair = nw and Valid(nw.pair) and nw.pair or nil
    local raw = type(char.settings) == "table" and char.settings or {}
    local nowOn = rawget(raw, "nowWindow") ~= false
    local attached = rawget(raw, "nowAttached") ~= false
    if not nowOn or not attached then pair = nil end
    if not guide and not pair then return false end
    local f, p = UI.frame, Co.UIParent()
    local lh = LH()
    local lines = tonumber(rawget(raw, "lines")) or 10
    local oldGuideH = 22 + lh * 3 + lines * lh + 4 + Th.LineHeight("sectionHead") + 22 + 8
    if not nowOn then oldGuideH = oldGuideH + 4 + Th.LineHeight("sectionHead") + 4 end
    local oldNowH = 22 + 4 + math.max(3 * lh, 88) + 4
    local h = f:GetHeight()
    local function Probe(pt, height)
        f:SetHeight(height)
        f:ClearAllPoints()
        f:SetPoint(pt.point, p, pt.rel or pt.point, pt.x, pt.y)
        return f:GetLeft(), f:GetTop()
    end
    local left, top, bottom
    if pair then
        -- attached: the guide window hung under the NOW window (its own saved spot wasn't used)
        local pl, pt = Probe(pair, oldNowH)
        if pl and pt then left, top, bottom = pl, pt, pt - oldNowH - 4 - oldGuideH end
    elseif guide then
        local gl, gt = Probe(guide, oldGuideH)
        if gl and gt then left, top, bottom = gl, gt, gt - oldGuideH end
    end
    f:SetHeight(h)
    if not (left and top and bottom) then
        UI.ApplyPos()
        return false
    end
    local ps, fs = p:GetEffectiveScale(), f:GetEffectiveScale()
    local screenH = (p:GetHeight() or 768) * ((ps and fs and fs > 0) and ps / fs or 1)
    if (top + bottom) / 2 >= screenH / 2 then bottom = top - h end   -- upper half: the top stays
    StorePos("BOTTOMLEFT", "BOTTOMLEFT", left, bottom)
    UI.ApplyPos()
    ns.Overlay.KeepOnScreen(f)
    return true
end
-- ------------------------------------------------------------------ building
-- the shared title bar (UIKit, look review #5; rounded here) + the window's own buttons on soft squares
local function TitleBar(f)
    local tb = K.TitleBar(f, {
        drag = true, round = true,
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
    tb.lock:SetPoint("RIGHT", tb.close, "LEFT", -3, 0)
    tb.small = K.GlyphButton(tb, "btn.small", s, function()
        return UI.Small() and L().TIP_EXPAND or L().TIP_SMALL
    end, function()
        ns.Settings.Set("small", not UI.Small())
    end)
    tb.small:SetPoint("RIGHT", tb.lock, "LEFT", -3, 0)
    tb.menu = K.GlyphButton(tb, "btn.menu", s, function() return L().TIP_MENU end, function(self)
        if ns.Menu.IsOpen() then ns.Menu.Close() else ns.Menu.Open(self, UI.MenuItems(), { right = true }) end
    end)
    tb.menu:SetPoint("RIGHT", tb.small, "LEFT", -3, 0)
    for _, b in ipairs({ tb.menu, tb.small, tb.lock, tb.close }) do K.SoftSquare(b) end
    tb.title:ClearAllPoints()
    tb.title:SetPoint("LEFT", tb.logo, "RIGHT", 5, 0)
    tb.title:SetPoint("RIGHT", tb.menu, "LEFT", -4, 0)
    K.Color(tb.title, "zone")
    return tb
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
    n.btn.text = K.Text(n.btn, "small", "accentText", "CENTER")
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

-- The info chips: route, level / XP, time left (rounded, white 5.5 %, small grey text); hover = more.
UI.CHIPS = { "range", "level", "time" }
UI.FADE = { 1, 0.82, 0.64 }   -- the next steps' alpha by place (mock-up 4h)
local function Chips(f)
    local row = CreateFrame("Frame", nil, f)
    row:SetHeight(UI.ChipH())
    row.list = {}
    for _, key in ipairs(UI.CHIPS) do
        local c = CreateFrame("Button", nil, row)
        c.key = key
        c:SetHeight(UI.ChipH())
        c.bg = K.Slice(c, "round", Th.Size("cornerChip"), "chipBg", { sub = 1 })
        if not c.bg then
            c.flat = K.Fill(c, "BACKGROUND", "chipBg")
            c.flat:SetAllPoints()
        end
        c.text = K.Text(c, "small", "chipText", "CENTER")
        c.text:SetPoint("LEFT", c, "LEFT", 4, 0)
        c.text:SetPoint("RIGHT", c, "RIGHT", -4, 0)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        c:SetScript("OnClick", function(self) ns.Errors.Call("ui", UI.ChipClick, self) end)
        c:SetScript("OnEnter", function(self) if self.tip then K.Tooltip(self, self.tip, self.tipLines) end end)
        c:SetScript("OnLeave", K.HideTooltip)
        row.list[#row.list + 1] = c
        row[key] = c
    end
    return row
end

function UI.ChipClick(c)
    if c.key == "range" and ns.Hub and ns.Hub.Available() then ns.Hub.Open("guides") end
end

-- The back / progress bar / next row. The bar: a rounded track with a rim, the fill, "step i / n · p %" on it;
-- click = the list of done steps (go back to one).
local function Footer(f)
    local ft = CreateFrame("Frame", nil, f)
    ft:SetHeight(Th.Size("navH"))
    local s = Th.Size("navButton")
    ft.prev = K.GlyphButton(ft, "btn.prev", s, function() return L().TIP_BACK end, function() ns.Engine.Back() end)
    ft.prev:SetPoint("LEFT", ft, "LEFT", 0, 0)
    ft.next = K.GlyphButton(ft, "btn.next", s, function() return L().TIP_NEXT end, function() ns.Engine.Next() end)
    ft.next:SetPoint("RIGHT", ft, "RIGHT", 0, 0)
    local bar = CreateFrame("Button", nil, ft)
    bar:SetHeight(Th.Size("barH"))
    bar:SetPoint("LEFT", ft.prev, "RIGHT", 4, 0)
    bar:SetPoint("RIGHT", ft.next, "LEFT", -4, 0)
    ft.bar = bar
    local c = Th.Size("cornerBar")
    ft.track = CreateFrame("Frame", nil, bar)
    ft.track:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    ft.track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
    ft.rim = K.Slice(bar, "round", c, "barRim", { sub = 0 })
    ft.trackSlice = K.Slice(bar, "round", c - 1, "barTrack", { sub = 1, rel = ft.track })
    if not ft.rim then
        local t = K.Fill(bar, "BACKGROUND", "barTrack")
        t:SetAllPoints(ft.track)
    end
    -- the fill: a frame as wide as the progress, the rounded slice on it (flat colour), or a gradient without art
    ft.fillFrame = CreateFrame("Frame", nil, bar)
    ft.fillFrame:SetPoint("TOPLEFT", ft.track, "TOPLEFT", 0, 0)
    ft.fillFrame:SetPoint("BOTTOMLEFT", ft.track, "BOTTOMLEFT", 0, 0)
    ft.fillFrame:SetWidth(1)
    ft.fillSlice = K.Slice(bar, "round", c - 1, "barFill", { sub = 2, rel = ft.fillFrame })
    ft.fill = ft.fillFrame
    if not ft.fillSlice then
        local t = bar:CreateTexture(nil, "ARTWORK", nil, 2)
        t:SetAllPoints(ft.fillFrame)
        K.Gradient(t, "VERTICAL", "barTo", "barFrom")
    end
    ft.text = K.Text(bar, "small", "barText", "CENTER")
    ft.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    ft.pct = ft.text
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar:SetScript("OnClick", function(self)
        if ns.Menu.IsOpen() and ns.Menu.anchor == self then ns.Menu.Close() return end
        local items = UI.ChipItems()
        if #items > 0 then ns.Menu.Open(self, items) end
    end)
    bar:SetScript("OnEnter", function(self) K.Tooltip(self, L().TIP_BAR) end)
    bar:SetScript("OnLeave", K.HideTooltip)
    return ft
end

-- Sets the progress (0..1): the fill is at least its two corners wide (a thinner one hides).
function UI.SetProgress(frac)
    local ft = UI.footer
    local w = (ft.track:GetWidth() or 0)
    local c = Th.Size("cornerBar") - 1
    local fw = w * frac
    local shown = frac > 0 and w > 0
    if ft.fillSlice then
        if fw < 2 * c + 1 then fw = 2 * c + 1 end
        K.SliceShown(ft.fillSlice, shown)
    end
    ft.fillFrame:SetWidth(math.max(1, math.min(w, fw)))
    ft.fillFrame:SetShown(shown)
    UI.progress = frac
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

-- ------------------------------------------------------------------ height + corner grips (beta.4)
-- Drag the bottom edge: the step area gets taller or shorter in whole step lines (the current step stays
-- at the top, more or fewer coming steps under it). The bottom-right corner does width and height in one
-- drag. Full mode only (small mode has its fixed lines). Same rules as the width grip: hidden while
-- locked, never starts in combat, pinned by the top-left, OnUpdate only while dragging, saved on release.
local CORNER = 10

-- The most lines that fit: the setting's max, and the window's bottom stays on the screen (its top stays).
function UI.LinesMax()
    local d = ns.Settings.byKey.lines
    local top = UI.frame and UI.frame:GetTop()
    if not top then return d.max end
    local lh = LH()
    local base = UI.Height(false) - UI.Lines() * lh
    return math.max(d.min, math.min(d.max, math.floor((top - base - Th.Size("shadow")) / lh)))
end

-- Only while a grip is dragged (UI.liveLines is cleared on release): lays out again when the line count
-- changes, never on a mere mouse move.
function UI.SetLinesLive(n)
    local d = ns.Settings.byKey.lines
    n = math.floor(ns.U.Clamp(n, d.min, UI.LinesMax()) + 0.5)
    if n ~= UI.Lines() then
        UI.liveLines = n
        UI.Layout()
        UI.Refresh()
    end
    return n
end

local function GripUpdate(self)
    -- (combat started mid-drag: the window holds still; the release still saves)
    if not self.startX or Co.InCombat() then return end
    local x, y = Co.Cursor(UI.frame)
    if not (x and y) then return end
    local kind = self.kind or "width"
    if kind ~= "height" then
        UI.liveWidth = nil
        self.width = UI.SetWidthLive(self.startW + (x - self.startX))
        UI.liveWidth = self.width
    end
    if kind ~= "width" then
        self.lines = UI.SetLinesLive(self.startLines + math.floor((self.startY - y) / LH() + 0.5))
    end
end

function UI.GripStart(self)
    local f = UI.frame
    if ns.Settings.Get("locked") or Co.InCombat() then return false end
    local kind = self.kind or "width"
    if kind ~= "width" and UI.Small() then return false end
    local left, top = f:GetLeft(), f:GetTop()
    local x, y = Co.Cursor(f)
    if not (left and top and x and y) then return false end
    -- pinned by the top-left while dragging (the release anchors it by the bottom again and saves)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", Co.UIParent(), "BOTTOMLEFT", left, top)
    self.startX, self.startY = x, y
    self.startW, self.width = f:GetWidth(), f:GetWidth()
    self.startLines, self.lines = UI.Lines(), UI.Lines()
    self:SetScript("OnUpdate", GripUpdate)
    return true
end

function UI.GripStop(self)
    if not self.startX then return end
    self:SetScript("OnUpdate", nil)
    self.startX = nil
    UI.SavePos()
    local kind = self.kind or "width"
    -- the width first (its layout still uses the dragged lines), then the lines
    UI.liveWidth = nil
    if kind ~= "height" then ns.Settings.Set("width", math.floor((self.width or UI.Width()) + 0.5)) end
    UI.liveLines = nil
    if kind ~= "width" then ns.Settings.Set("lines", self.lines or UI.Lines()) end
end

local GRIP_TIP = { width = "TIP_GRIP", height = "TIP_GRIP_HEIGHT", corner = "TIP_GRIP_SIZE" }

-- kind "width" (right edge), "height" (bottom edge) or "corner" (bottom-right). The look comes from the
-- theme: an accent line on the edge (the corner: the theme's resize glyph), shown on hover and while dragged.
local function Grip(f, kind)
    local g = CreateFrame("Button", nil, f)
    g.kind = kind
    -- above the step rows (the corner above both edges)
    g:SetFrameLevel((f:GetFrameLevel() or 0) + (kind == "corner" and 21 or 20))
    if kind == "width" then
        g:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TitleH())
        g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        g:SetWidth(GRIP_W)
        g.line = K.Fill(g, "OVERLAY", "accent")
        g.line:SetWidth(2)
        g.line:SetPoint("TOPRIGHT", g, "TOPRIGHT", -1, 0)
        g.line:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -1, 0)
    elseif kind == "height" then
        g:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        g:SetHeight(GRIP_W)
        g.line = K.Fill(g, "OVERLAY", "accent")
        g.line:SetHeight(2)
        g.line:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 1)
        g.line:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 1)
    else
        g:SetSize(CORNER, CORNER)
        g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        g.line = K.Glyph(g, "btn.resize", CORNER, "accent", "OVERLAY")
        g.line:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
        g.icon = g.line
    end
    g.line:Hide()
    g:SetScript("OnEnter", function(self)
        if ns.Settings.Get("locked") then return end
        self.line:Show()
        K.Tooltip(self, L()[GRIP_TIP[self.kind]])
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
    -- hidden mid-drag (window closed, locked by a key): the drag ends and what was dragged is kept
    g:SetScript("OnHide", function(self)
        if self.startX then ns.Errors.Call("ui", UI.GripStop, self) end
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
    -- Overlay.KeepOnScreen: anchored by the bottom-left, room for the shadow and the button row
    f.keepBottom = true
    f.keepRoom = function()
        local sh = Th.Size("shadow")
        return { sh, sh, UI.TopRoom(), sh }
    end
    UI.panel = K.RoundPanel(f)
    UI.title = TitleBar(f)
    UI.noticeLine = NoticeLine(f)
    UI.area = CreateFrame("Frame", nil, f)
    UI.area:SetPoint("LEFT", f, "LEFT", 1, 0)
    UI.area:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    UI.nextLine = K.Text(UI.area, "goal", "upcoming")
    UI.nextLine:SetPoint("BOTTOMLEFT", UI.area, "BOTTOMLEFT", Pad(), 2)
    UI.nextLine:SetPoint("BOTTOMRIGHT", UI.area, "BOTTOMRIGHT", -Pad(), 2)
    -- the hairline between the step block and the next steps
    UI.divider = K.Fill(UI.area, "ARTWORK", "divider")
    UI.divider:SetHeight(K.Hair(1))
    UI.divider:Hide()
    UI.stateIcon = UI.area:CreateTexture(nil, "ARTWORK")
    UI.stateIcon:SetSize(32, 32)
    UI.stateIcon:SetPoint("TOP", UI.area, "TOP", 0, -LH())
    UI.stateText = K.Text(UI.area, "step", "text.dim", "CENTER")
    UI.stateText:SetWordWrap(true)
    UI.stateText:SetPoint("TOP", UI.stateIcon, "BOTTOM", 0, -6)
    UI.stateText:SetPoint("LEFT", UI.area, "LEFT", Pad() * 2, 0)
    UI.stateText:SetPoint("RIGHT", UI.area, "RIGHT", -Pad() * 2, 0)
    UI.chips = Chips(f)
    UI.footer = Footer(f)
    UI.grip = Grip(f, "width")
    UI.gripH = Grip(f, "height")
    UI.gripC = Grip(f, "corner")
    -- on its spot first; Layout sets the scale and size; then the one-time move from the two old windows
    UI.ApplyPos()
    UI.Layout()
    ns.Errors.Call("ui", UI.Migrate)
    UI.ApplyOpacity()
    f:Hide()
end

-- ------------------------------------------------------------------ layout (fixed heights)
function UI.Layout()
    local f, small = UI.frame, UI.Small()
    f:SetScale(ns.Overlay.WindowScale())
    f:SetHeight(UI.Height(small))
    f:SetWidth(UI.Width())
    local free = not ns.Settings.Get("locked")
    UI.grip:SetShown(free)
    UI.gripH:SetShown(free and not small)
    UI.gripC:SetShown(free and not small)
    UI.noticeLine:SetHeight(LH())
    -- (small fonts: the notice icon never gets taller than its line)
    local bs = math.max(8, math.min(Th.Size("badge"), LH()))
    UI.noticeLine.icon:SetSize(bs, bs)
    UI.chips:SetShown(not small)
    UI.footer:SetShown(not small)
    UI.noticeLine:ClearAllPoints()
    UI.area:ClearAllPoints()
    UI.area:SetPoint("LEFT", f, "LEFT", 1, 0)
    UI.area:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    UI.area:SetPoint("TOP", f, "TOP", 0, -TitleH())
    UI.area:SetHeight(UI.ShownAreaHeight(small))
    -- the notice takes the last line of the step area (small: the "Next:" line's place)
    UI.noticeLine:SetPoint("BOTTOMLEFT", UI.area, "BOTTOMLEFT", Pad(), small and 0 or 1)
    UI.noticeLine:SetPoint("BOTTOMRIGHT", UI.area, "BOTTOMRIGHT", -Pad(), small and 0 or 1)
    if not small then
        local below = TitleH() + UI.ShownAreaHeight(false) + 4
        UI.chips:ClearAllPoints()
        UI.chips:SetPoint("TOPLEFT", f, "TOPLEFT", Pad() - 2, -below)
        UI.chips:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(Pad() - 2), -below)
        UI.chips:SetHeight(UI.ChipH())
        for _, c in ipairs(UI.chips.list) do c:SetHeight(UI.ChipH()) end
        UI.footer:ClearAllPoints()
        UI.footer:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -(below + UI.ChipH() + 2))
        UI.footer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -(below + UI.ChipH() + 2))
    end
    Th.Glyph(UI.title.small.icon, small and "btn.expand" or "btn.small")
    Th.Glyph(UI.title.lock.icon, ns.Settings.Get("locked") and "btn.lock" or "btn.unlock")
    -- room above the top for the item / target buttons (positive top = above the frame: warcraft.wiki.gg
    -- API_Frame_SetClampRectInsets), so the clamp never pushes them off the screen
    -- (and the soft shadow on every side: left negative / right positive / bottom negative keep a distance)
    local sh = Th.Size("shadow")
    if f.SetClampRectInsets then f:SetClampRectInsets(-sh, sh, UI.TopRoom(), -sh) end
    -- the 3D view in the step block follows the window's size
    if ns.ModelView and ns.ModelView.frame then ns.Errors.Call("model", ns.ModelView.Place) end
    -- the item / target buttons re-place themselves (height, width or scale may have moved the window's top-left)
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
-- Travel side goals ("on the way"): at most this many lines under a step, then one "+n more" line.
UI.SIDE_MAX = 3
-- objective kind (C_QuestLog.GetQuestObjectives `type`) -> the side line's icon
UI.SIDE_KIND = { monster = "kill", item = "loot", object = "use" }

-- The side lines of one background goal, appended to `out`: one per objective (its `obj` list or all) with
-- the game's objective text and live count, read only from the GameState quest snapshot (never the API
-- here, never on the position ticker); a bag count for an item goal; our step text when the snapshot has
-- no usable text. Nothing while the quest isn't in the log (it comes back when it is).
function UI.SideLines(top, b, out)
    local GS = ns.GameState
    local useKind = b.type == "useitem" and "use" or nil
    if b.item and not b.quest then
        local need = b.count or 1
        local have = GS.ItemCount(b.item)
        out[#out + 1] = { text = top:Text(b), have = math.min(have, need), need = need, done = have >= need,
            kind = useKind or "loot", side = b }
        return out
    end
    if not b.quest then
        out[#out + 1] = { text = top:Text(b), done = false, kind = useKind, side = b }
        return out
    end
    if not GS.InLog(b.quest) then return out end
    local qs = GS.Quest(b.quest)
    local idx = {}
    if qs and ns.Packs.Len(b.obj) > 0 then
        for _, i in ns.Packs.Each(b.obj) do if qs.need[i] then idx[#idx + 1] = i end end
    elseif qs then
        for i = 1, #qs.need do idx[#idx + 1] = i end
    end
    local n0 = #out
    for _, i in ipairs(idx) do
        local need, have = qs.need[i], qs.have[i] or 0
        local text = qs.text and qs.text[i]
        if type(text) ~= "string" or text == "" then text = top:Text(b) end
        if need and need > 0 then
            out[#out + 1] = { text = text, have = math.min(have, need), need = need, done = have >= need,
                kind = useKind or UI.SIDE_KIND[qs.kind and qs.kind[i] or ""], side = b }
        end
    end
    -- no objective data yet (just logged in, or unknown / secret values): one line with our own text
    if #out == n0 then out[#out + 1] = { text = top:Text(b), done = false, kind = useKind, side = b } end
    return out
end

local function Goals(top, step)
    local out = {}
    local GS = ns.GameState
    if step.type == "objective" then
        if step.item then
            local need = step.count or 1
            local have = GS.ItemCount(step.item)
            out[1] = { text = L().GOAL_ITEMS, have = math.min(have, need), need = need, done = have >= need, kind = "loot" }
        else
            local qs = step.quest and GS.Quest(step.quest)
            if qs then
                local function Add(i)
                    local need = qs.need[i]
                    if not need then return end
                    local have = qs.have[i] or 0
                    out[#out + 1] = { text = qs.text and qs.text[i] or "", have = have, need = need, done = have >= need,
                        kind = UI.SIDE_KIND[qs.kind and qs.kind[i] or ""] }
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
    -- background goals: "on the way" side lines with live counts (at most UI.SIDE_MAX, then "+n more"),
    -- optional steps as "Optional:" lines
    local side = {}
    for _, b in ipairs(top:Background()) do
        if b ~= step then
            if b.flags.optional then
                out[#out + 1] = { text = ns.U.Fill(L().OPTIONAL_LINE, { text = top:Text(b) }), done = false }
            else
                UI.SideLines(top, b, side)
            end
        end
    end
    if #side > 0 then
        -- open parts first (done parts tick and stay, after them); route order otherwise
        local open, done = {}, {}
        for _, l in ipairs(side) do
            if l.done then done[#done + 1] = l else open[#open + 1] = l end
        end
        for _, l in ipairs(done) do open[#open + 1] = l end
        local max = UI.SIDE_MAX
        for k = 1, math.min(max, #open) do out[#out + 1] = open[k] end
        if #open > max then
            out[#out + 1] = { text = ns.U.Fill(L().ONWAY_MORE, { n = #open - max }), more = true, done = false }
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

local function Wrap(field, v, id)
    if field == "quest" and v then return Th.Wrap("quest", v) end
    -- an {item:<id>} token: its icon + item link (item pictures on), else the plain name
    if field == "item" and v and id and ns.ItemIcons and ns.ItemIcons.On() then return ns.ItemIcons.Link(id, v) end
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
    local text, kind = UI.Verb(cur, top:Text(cur, Wrap))
    m.zone = (cur.map and Co.MapName(cur.map)) or m.section
    local goals = Goals(top, cur)
    local focus
    for i, gl in ipairs(goals) do
        if not gl.done and not gl.more then focus = i break end
    end
    -- beta.9 item pictures: the icon before the item's first mention, item icons on goal lines
    local II = ns.ItemIcons
    if II and II.On() then
        text = II.Decorate(cur, text)
        for _, gl in ipairs(goals) do gl.item = II.GoalItem(cur, gl) end
    end
    m.rows = { { step = cur, number = m.index, badge = K.BadgeKind(cur), tile = kind, text = text, state = "current",
        right = not coord and UI.DistText(cur) or nil, goals = goals, sub = UI.SubLines(top, cur, coord), focus = focus,
        note = UI.NoteText(cur) } }
    -- (every next row is one line: as many as the lines setting, one spare; perf: no rows that never show)
    for _, s in ipairs(Upcoming(top, cur, UI.Lines() + 1)) do
        local plain = top:Text(s)
        local t, k = UI.Verb(s, plain)
        local tag, target = UI.NextTag(s, plain)
        local where = s.map and s.x and s.y and ("%.0f, %.0f"):format(s.x * 100, s.y * 100) or nil
        m.rows[#m.rows + 1] = { step = s, number = numbers[s.index], badge = K.BadgeKind(s), tile = k, text = t,
            tag = tag, target = target, state = "upcoming", right = UI.UnderLevelText(top, s) or where,
            icon = II and II.NextIcon(s) or nil }
    end
    m.done = math.max(0, m.index - 1)
    return m
end

-- The verb at the start of a step's text in its colour ("Kill" red-orange, "Turn in" yellow, "Go to" blue ...) and
-- the tile kind it stands for. The words come from the locale (VERB_<KIND> = "Turn in|Hand in"), longest first;
-- no verb found = the text as it is and the tile of the step's type.
UI.VERB_KINDS = { "turnin", "accept", "loot", "kill", "use", "goto", "note", "talk", "train", "fly", "hearth" }
local verbCache = {}
function UI.VerbList()
    local Lc = L()
    -- (perf: built once per language table; the words only change with the language)
    local Lo = ns.Locale
    local id = Lo and (Lo.current or Lo.en)
    if id and verbCache.id == id and verbCache.code == Lo.code then return verbCache.list end
    local src = {}
    for i, kind in ipairs(UI.VERB_KINDS) do src[i] = tostring(Lc["VERB_" .. kind:upper()] or "") end
    local key = table.concat(src, "\1")
    if verbCache.key == key then verbCache.id, verbCache.code = id, Lo and Lo.code return verbCache.list end
    local c = {}
    for i, kind in ipairs(UI.VERB_KINDS) do
        for word in src[i]:gmatch("[^|]+") do c[#c + 1] = { word, kind } end
    end
    table.sort(c, function(a, b) return #a[1] > #b[1] end)
    verbCache.key, verbCache.list, verbCache.id, verbCache.code = key, c, id, Lo and Lo.code
    return c
end
-- The verb at the start of a text: word, the rest (no leading space), kind; nil when none.
function UI.VerbSplit(text)
    text = text or ""
    for _, v in ipairs(UI.VerbList()) do
        local w = v[1]
        if text:sub(1, #w) == w then
            local after = text:sub(#w + 1, #w + 1)
            if after == "" or after == " " then return w, text:sub(#w + 2), v[2] end
        end
    end
    return nil
end

function UI.Verb(step, text)
    text = text or ""
    local w, _, kind = UI.VerbSplit(text)
    if w then
        local key = "verb." .. kind
        if not Th.Has("color." .. key) then key = "text" end
        return Th.Wrap(key, w) .. text:sub(#w + 1), kind
    end
    return text, K.TileKind(step)
end

-- A next step as one line (mock-up 4h): the framed verb tag and the target. Accept / turn-in steps show the
-- quest's name as the target; the NPC and the place are in the line's hover tooltip (UI.StepTip). No verb at the
-- start: the tag is the step kind's first verb (TAG_NOTE for notes) and the target the whole text.
function UI.NextTag(step, plain)
    local w, rest, kind = UI.VerbSplit(plain)
    if not w then
        kind = K.TileKind(step)
        rest = plain
        local words
        for _, k in ipairs(UI.VERB_KINDS) do
            if k == kind and k ~= "note" then words = L()["VERB_" .. k:upper()] end
        end
        w = (type(words) == "string" and words:match("^[^|]+")) or L().TAG_NOTE
    end
    if step.quest and (step.type == "accept" or step.type == "turnin") and ns.Names then
        local q, real = ns.Names.Quest(step.quest, step.qname)
        if (real or step.qname) and type(q) == "string" and q ~= "" then rest = q end
    end
    return { kind = kind, word = w:upper() }, rest
end
-- beta.8 step notes (plans\note-line\plan.md): the current step's `why` (pack data, English until v1.0) for the dim
-- note line under its goals; nil when the step has none, the setting is off or the window is small.
function UI.NoteText(step)
    if type(step) ~= "table" or type(step.why) ~= "string" then return nil end
    if not ns.Settings.Get("noteLine") or UI.Small() then return nil end
    local t = step.why:gsub("^%s+", ""):gsub("%s+$", "")
    return t ~= "" and t or nil
end

-- The lines under the current step's text: "for <quest>" (when the text doesn't name the quest) and the place
-- line ("Northshire Valley · 52.0, 36.0", the distance on its right; the arrow's ticker keeps it fresh).
function UI.SubLines(top, step, coord)
    local out = {}
    if step.quest and step.type ~= "accept" and step.type ~= "turnin" and ns.Names then
        local name = ns.Names.Quest(step.quest)
        local plain = top:Text(step) or ""
        if type(name) == "string" and name ~= "" and not plain:find(name, 1, true) then
            out[#out + 1] = { text = ns.U.Fill(L().FOR_QUEST, { quest = Th.Wrap("quest", name) }) }
        end
    end
    if coord then
        local zone = step.map and Co.MapName(step.map)
        out[#out + 1] = { text = zone and ns.U.Fill(L().PLACE_LINE, { zone = zone, coords = coord.text }) or coord.text,
            right = coord.dist, place = true }
    end
    return out
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
    out.sub = nil
    out.note = nil
    out.lean, out.leanX, out.leanH = nil, nil, nil
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
        -- beta.9 item pictures: hovering an item's name / icon in the step text shows the game's item tooltip
        -- (our own item:<number> links only); a click on it does nothing (tos: no chat links, no item use)
        if r.SetHyperlinksEnabled then r:SetHyperlinksEnabled(true) end
        r:SetScript("OnHyperlinkEnter", function(self, link) ns.Errors.Call("itemicons", ns.ItemIcons.LinkEnter, self, link) end)
        r:SetScript("OnHyperlinkLeave", function(self) ns.Errors.Call("itemicons", ns.ItemIcons.LinkLeave, self) end)
        r:SetScript("OnHyperlinkClick", function() end)
    end
    return r
end

local STATE_TEXT = { none = "STATE_NONE", finished = "STATE_FINISHED", error = "STATE_ERROR", safe = "STATE_SAFE" }
local STATE_GLYPH = { none = "state.none", finished = "state.finished", error = "state.error", safe = "state.error" }

local function DrawState(state)
    for _, r in ipairs(UI.rows) do r:Hide() end
    UI.divider:Hide()
    UI.nextLine:SetText("")
    UI.stateIcon:Show()
    Th.Glyph(UI.stateIcon, STATE_GLYPH[state])
    UI.stateIcon:SetVertexColor(Th.Color(state == "finished" and "accentText" or "text.dim"))
    UI.stateText:Show()
    UI.stateText:SetText(L()[STATE_TEXT[state]])
    UI.title.title:SetText(L().TITLE)
    for _, c in ipairs(UI.chips.list) do c:Hide() end
    UI.SetProgress(0)
    UI.footer.text:SetText("")
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
    line.icon:SetVertexColor(Th.Color(n.kind == "danger" and "notice.danger" or n.iconColor or "accentText"))
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

-- The info chips (route, level / XP, time left) from the model; a chip that doesn't fit the row hides.
function UI.ChipTexts(m)
    local out = {}
    out.range = { text = m.title, tip = m.title, lines = { L().TIP_RANGE } }
    local lv = ns.Engine.ctx and ns.Engine.ctx.level
    local GS = ns.GameState
    if type(lv) == "number" then
        local t
        if GS.xp and GS.xpMax and GS.xpMax > 0 then
            t = ns.U.Fill(L().CHIP_LEVEL_XP, { level = lv, pct = math.floor(GS.xp / GS.xpMax * 100) })
        else
            t = ns.U.Fill(L().CHIP_LEVEL, { level = lv })
        end
        out.level = { text = t, tip = t,
            lines = GS.xp and GS.xpMax and GS.xpMax > 0 and { ns.U.Fill(L().UNDER_XP, { have = GS.xp, need = GS.xpMax }) } or nil }
    end
    local ok, time = ns.Errors.Call("pace", function() return ns.Pace and ns.Pace.Text(m.top) end)
    if ok and time then
        local r, n = ns.Pace.Ratio()
        out.time = { text = time, tip = time, lines = { r and ns.U.Fill(L().TIP_TIME_PACE, { n = n }) or L().TIP_TIME_EST } }
    end
    return out
end

local function DrawChips(m)
    local data = UI.ChipTexts(m)
    local row = UI.chips
    local room = (row:GetWidth() or 0)
    if room <= 0 then room = UI.Width() - 2 * (Pad() - 2) end
    local x, gap = 0, Th.Size("chipGap")
    for _, c in ipairs(row.list) do
        local d = data[c.key]
        if d and d.text then
            c.text:SetText(d.text)
            local w = math.ceil((c.text:GetStringWidth() or 30) + 8)
            if c.key == "range" then w = math.min(w, math.floor(room * 0.4)) end
            if x + w > room + 0.5 then
                c:Hide()
            else
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
                c:SetWidth(w)
                c.tip, c.tipLines = d.tip, d.lines
                c:Show()
                x = x + w + gap
            end
        else
            c:Hide()
        end
    end
end

-- The most the window may grow up now: its top stays under the screen top (with the button row).
function UI.GrowMax()
    local f, p = UI.frame, Co.UIParent()
    local t = f and f:GetTop()
    if not (t and p) then return 0 end
    local ps, fs = p:GetEffectiveScale(), f:GetEffectiveScale()
    local ph = (p:GetHeight() or 0) * ((ps and fs and fs > 0) and ps / fs or 1)
    return math.max(0, math.floor((UI.grow or 0) + ph - t - UI.TopRoom()))
end

-- A current step too tall for the room it has (in combat, or at the screen top): one text line, its sub lines
-- dropped, as many goal lines as fit (the rest come back after the fight / on the next step).
-- Finished goals fold into one line ("3 done", the user's yes 2026-11-26, plans\guide-window-look\mockup\
-- done-fold.png): click it to open (the finished goals indented, dim green) or close; closed again on the next
-- step. A goal that just finished flashes green for motion.goalFlash first (0 with reduced motion), then folds in.
-- UI.foldOpen: the fold is open; UI.doneSeen: the goals finished at the last refresh of this step (text -> true).
function UI.ToggleFold()
    UI.foldOpen = not UI.foldOpen
    UI.Refresh()
end

function UI.FoldGoals(d, stepId)
    local goals = d.goals or {}
    if UI.foldStep ~= stepId then
        UI.foldStep, UI.foldOpen, UI.doneSeen, UI.flashUntil = stepId, false, nil, {}
    end
    local now = Co.Now()
    local seen = UI.doneSeen
    local newSeen, done, open, more, wait = {}, {}, {}, {}, nil
    for _, g in ipairs(goals) do
        local key = g.text or ""
        if g.more then
            more[#more + 1] = g
        elseif g.done then
            newSeen[key] = true
            -- just finished on this step: flash first (a goal done when the step came up folds at once)
            if seen and not seen[key] and Th.Motion("goalFlash") > 0 then
                UI.flashUntil[key] = now + Th.Motion("goalFlash")
            end
            local untilT = UI.flashUntil[key]
            if untilT and untilT > now then
                local c = {}
                for k, v in pairs(g) do c[k] = v end
                c.flash = true
                open[#open + 1] = c
                wait = math.max(wait or 0, untilT - now)
            else
                done[#done + 1] = g
            end
        else
            open[#open + 1] = g
        end
    end
    UI.doneSeen = newSeen
    if wait then
        local token = {}
        UI.flashToken = token
        Co.After(wait + 0.05, function() if UI.flashToken == token then UI.Refresh() end end)
    end
    if #done == 0 then return d end
    local out = {}
    for k, v in pairs(d) do out[k] = v end
    local list = { { fold = true, done = true, open = UI.foldOpen, text = ns.U.Fill(L().GOAL_DONE_FOLD, { n = #done }),
        right = UI.foldOpen and L().FOLD_CLOSE or L().FOLD_OPEN } }
    if UI.foldOpen then
        for _, g in ipairs(done) do
            local c = {}
            for k, v in pairs(g) do c[k] = v end
            c.indent = true
            list[#list + 1] = c
        end
    end
    local focus
    for _, g in ipairs(open) do
        list[#list + 1] = g
        if not focus and not g.done then focus = #list end
    end
    for _, g in ipairs(more) do list[#list + 1] = g end
    out.goals, out.focus, out.onFold = list, focus, UI.ToggleFold
    UI.foldCount = #done
    return out
end
local function FitBlock(d, avail)
    local out = {}
    for k, v in pairs(d) do out[k] = v end
    out.maxLines = 1
    out.sub = nil
    out.note = nil
    local base = math.max(LH(), (d.lean and d.leanH or 0) + Th.Size("blockPad"))
    local room = math.max(0, math.floor((avail - base) / LG()))
    local goals = {}
    for i = 1, math.min(#(d.goals or {}), room) do goals[i] = d.goals[i] end
    out.goals = goals
    return out
end

function UI.Refresh()
    if not UI.frame or not UI.frame:IsShown() then return end
    UI.refreshes = UI.refreshes + 1
    local small = UI.Small()
    local ok, m = ns.Errors.Call("ui", UI.Model)
    if not ok or type(m) ~= "table" then m = { state = "error" } end
    UI.model = m
    if m.state ~= "guide" then
        if UI.Grow() > 0 and not Co.InCombat() then
            UI.grow = 0
            UI.Layout()
        end
        DrawState(m.state)
        DrawNotice()
        if ns.ModelView and ns.ModelView.frame then ns.Errors.Call("model", ns.ModelView.Update) end
        if ns.Waypoint then ns.Waypoint.Clear("step") elseif ns.Arrow then ns.Arrow.SetTarget(nil) end
        return
    end
    UI.stateIcon:Hide()
    UI.stateText:Hide()
    UI.footer.prev:Show()
    UI.footer.next:Show()
    UI.title.title:SetText(m.zone or m.title or L().TITLE)
    local noticeShown = DrawNotice()
    -- the notice takes the last line (full mode) / the "Next:" line (small mode)
    local reserve = (small or noticeShown) and LH() or 0
    local blockPad = Th.Size("blockPad")
    -- row 1: the step block (3D view on the left when it shows; small mode: one line + the goals that fit)
    local r = Row(1)
    local d = m.rows[1]
    if r:GetParent() ~= UI.area then r:SetParent(UI.area) end
    d.boxed = true
    d.reserveRight = nil
    local MV = ns.ModelView
    local slot = not small and MV and MV.InsideSlot and MV.InsideSlot(m.cur) or nil
    UI.slot = slot
    if slot then
        d.lean, d.leanX, d.leanH = true, Pad() + slot + 8, slot
    else
        d.lean, d.leanX, d.leanH = nil, nil, nil
    end
    UI.foldCount = 0
    d = UI.FoldGoals(d, m.cur.id)
    local base = small and (UI.AreaHeight(true) - reserve - blockPad) or (UI.BlockBase() - blockPad)
    if small then d = UI.FitSmall(d, base) end
    -- v0.2 fix (the user: "text are overlapping the now step"): anchor the row before laying it out, so its text
    -- is measured at its real width
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", UI.area, "TOPLEFT", 0, -blockPad)
    r:SetPoint("TOPRIGHT", UI.area, "TOPRIGHT", 0, -blockPad)
    r:Show()
    local h = ns.Rows.Set(r, d)
    -- tall step: the window grows up (out of combat, under the screen top); else it's cut to what fits
    local want = math.max(0, math.ceil(h - base))
    if Co.InCombat() then
        want = math.min(want, UI.Grow())
    else
        want = math.min(want, UI.GrowMax())
    end
    -- no room to grow (combat, screen top): the note line goes first, then the usual cuts
    if h > base + want + 0.5 and d.note then
        local nd = {}
        for k, v in pairs(d) do nd[k] = v end
        nd.note = nil
        d = nd
        h = ns.Rows.Set(r, d)
    end
    if h > base + want + 0.5 then
        d = FitBlock(d, base + want)
        h = ns.Rows.Set(r, d)
    end
    if want ~= UI.Grow() then
        UI.grow = want
        UI.Layout()
    end
    local areaH = UI.AreaHeight(small) + want
    local y = blockPad + h
    local shown, nextShown = 1, 0
    -- the next steps (full mode), under a hairline
    if not small then
        y = y + Th.Size("sectionGap")
        UI.divider:ClearAllPoints()
        UI.divider:SetPoint("TOPLEFT", UI.area, "TOPLEFT", Pad(), -y)
        UI.divider:SetPoint("TOPRIGHT", UI.area, "TOPRIGHT", -Pad(), -y)
        y = y + Th.Size("sectionGap")
    end
    local full = false
    for i = 2, #m.rows do
        local row = Row(i)
        local dd = m.rows[i]
        -- (a next line is one step line high: one that can't fit isn't drawn at all; perf)
        if not full and dd.tag and y + Th.LineHeight("step") > areaH - reserve + 0.5 then full = true end
        if small or full then
            row:Hide()
        else
            dd.boxed, dd.reserveRight, dd.lean, dd.leanX, dd.leanH = nil, nil, nil, nil, nil
            -- 4h: fading 100 / 82 / 64 %, a faint hairline between the lines (the divider is above the first)
            dd.fade = UI.FADE[nextShown + 1] or UI.FADE[#UI.FADE]
            dd.sep = nextShown > 0
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", UI.area, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", UI.area, "TOPRIGHT", 0, -y)
            row:Show()
            local rh = ns.Rows.Set(row, dd)
            if y + rh > areaH - reserve + 0.5 then
                row:Hide()
                full = true
            else
                y = y + rh
                shown = shown + 1
                nextShown = nextShown + 1
            end
        end
    end
    UI.divider:SetShown(not small and nextShown > 0)
    for i = #m.rows + 1, #UI.rows do UI.rows[i]:Hide() end
    UI.shownRows = shown
    -- small mode: one "Next:" line under the current step (a notice takes its place)
    local nxt = m.rows[2]
    UI.nextLine:SetText(small and not noticeShown and nxt and ns.U.Fill(L().NEXT_LINE, { text = nxt.text }) or "")
    -- chips and the progress bar
    if not small then DrawChips(m) end
    local frac = m.count > 0 and (m.index - 1) / m.count or 0
    UI.SetProgress(frac)
    UI.footer.text:SetText(ns.U.Fill(L().NAV_TEXT, { i = m.index, n = m.count, p = math.floor(frac * 100 + 0.5) }))
    -- the 3D view in its square (or not)
    if MV and MV.frame then ns.Errors.Call("model", MV.Update) end
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
    local lines = UI.StepLines(step, row.rightText)
    -- the note line was cut ("..."): its full text here (beta.8 step notes)
    if row.current and row.noteCut and type(step.why) == "string" then
        lines[#lines + 1] = Th.Wrap("note", step.why)
    end
    -- the current step: its "on the way" goals by name (the window shows at most UI.SIDE_MAX lines)
    if row.current and g then
        local top, head = g:Top(), false
        for _, b in ipairs(top:Background()) do
            if b ~= step and not b.flags.optional then
                if not head then lines[#lines + 1] = L().ONWAY_TIP head = true end
                lines[#lines + 1] = "- " .. top:Text(b)
            end
        end
    end
    K.Tooltip(row, title, lines)
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

-- The guides for this character (built from the installed packs; at most 3 rows).
local function GuideRows(items)
    local E = ns.Engine
    local _, ids = E.GuideList()
    local g = E.Focused()
    local focusPack = g and g.key:match("^([^/]+)")
    for i = 1, math.min(3, #ids) do
        local id = ids[i]
        items[#items + 1] = { text = ns.U.Fill(L().MENU_GUIDE, { guide = E.GuideTitle(id) }), checked = id == focusPack,
            fn = function() E.OpenGuide(id) end }
    end
end

-- The tail both menus share: the arrow's click-through switch (a click-through arrow can't be right-clicked,
-- so it's here while it's on) and "Link with Gear Set" (only when Gear Set is loaded, v0.1.1).
local function TailRows(items)
    if ns.Settings.Get("arrowClickThrough") then
        items[#items + 1] = { text = L().MENU_ARROW_CLICK, checked = true,
            fn = function() ns.Settings.Set("arrowClickThrough", false) end }
    end
    local gs = ns.GearSet and ns.GearSet.MenuItem()
    if gs then items[#items + 1] = gs end
end

-- The title menu (2026-11-25, main window plan): with the main window, a short list (the window has every
-- setting); without it (safe mode, feature "hub" off) the full list of switches below, so nothing is lost.
function UI.MenuItems()
    local S = ns.Settings
    if ns.Hub and ns.Hub.Available() then
        local items = {
            { text = L().MENU_MAIN, fn = function() ns.Hub.Open() end },
            { text = L().MENU_GUIDES, fn = function() ns.Hub.Open("guides") end },
            { text = L().MENU_SETTINGS_MAIN, fn = function() ns.SettingsUI.Open() end },
            { text = L().MENU_REPORT, fn = function() ns.HubReport.Open() end },
            { text = L().MENU_SMALL, checked = S.Get("small"), fn = function() S.Set("small", not S.Get("small")) end },
            { text = L().MENU_LOCK, checked = S.Get("locked"), fn = function() S.Set("locked", not S.Get("locked")) end },
            { text = L().MENU_MODEL, checked = S.Get("modelViewer"),
                fn = function() S.Set("modelViewer", not S.Get("modelViewer")) end },
            { text = L().MENU_QUIET, checked = S.Get("quiet"), fn = function() S.Set("quiet", not S.Get("quiet")) end },
        }
        GuideRows(items)
        TailRows(items)
        return items
    end
    local items = {
        { text = L().MENU_SMALL, checked = S.Get("small"), fn = function() S.Set("small", not S.Get("small")) end },
        { text = L().MENU_LOCK, checked = S.Get("locked"), fn = function() S.Set("locked", not S.Get("locked")) end },
        { text = L().MENU_QUIET, checked = S.Get("quiet"), fn = function() S.Set("quiet", not S.Get("quiet")) end },
        { text = L().MENU_ARROW, checked = S.Get("arrow"), fn = function() S.Set("arrow", not S.Get("arrow")) end },
        { text = L().MENU_MODEL, checked = S.Get("modelViewer"),
            fn = function() S.Set("modelViewer", not S.Get("modelViewer")) end },
        { text = L().MENU_MOTION, checked = S.Get("reducedMotion"),
            fn = function() S.Set("reducedMotion", not S.Get("reducedMotion")) end },
        { text = L().MENU_MAPPINS, checked = S.Get("mapPins"), fn = function() S.Set("mapPins", not S.Get("mapPins")) end },
        { text = L().MENU_MINIPINS, checked = S.Get("minimapPins"),
            fn = function() S.Set("minimapPins", not S.Get("minimapPins")) end },
    }
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
    GuideRows(items)
    TailRows(items)
    -- language: on the Settings > General page and /aog lang; here only without the main window
    local lang = S.Get("lang")
    items[#items + 1] = { text = "English", checked = lang ~= "da",
        fn = function() ns.Locale.Switch("en") end }
    items[#items + 1] = { text = "Dansk", checked = lang == "da",
        fn = function() ns.Locale.Switch("da") end }
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
    if key == "small" or key == "locked" or key == "width" or key == "lines" or key == "modelViewer" or key == "modelPos"
        or key == "modelScale" then
        UI.Layout()
        UI.Refresh()
        -- taller (the slider): the bottom row and grips stay on screen
        if (key == "lines" or key == "small") and not Co.InCombat() and ns.Overlay.KeepOnScreen(UI.frame) then UI.SavePos() end
    elseif key == "opacity" then
        UI.ApplyOpacity()
    elseif key == "reducedMotion" or key == "quiet" or key == "noteLine" or key == "itemIcons" then
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
    -- the one window is anchored by its bottom: a taller or shorter window (font size) grows / shrinks at the top
    UI.Layout()
    UI.ApplyOpacity()
    UI.Refresh()
end, "ui", 70)
-- (tester beta.7 #2: the new height is placed first, then Refresh caps the grow again under the screen top)
ns.Bus.On("ScaleChanged", UI, function()
    if not UI.frame then return end
    UI.Layout()
    UI.Refresh()
    if not Co.InCombat() and ns.Overlay.KeepOnScreen(UI.frame) then UI.SavePos() end
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

-- The step block's state: nil when right (or not judged now), else a short reason. Self-test "stepblock" + the
-- offline tests: the current step is shown on top, inside the window, nothing under it reaches into it, its text
-- ends above its sub / goal lines, the goal lines start under the 3D view, the button row has room above the top.
function UI.BlockProblem()
    local m, r, f = UI.model, UI.rows[1], UI.frame
    if not (f and f:IsShown() and m and m.state == "guide") then return nil end
    if not (r and r:IsShown()) then return "the current step isn't shown" end
    if not (r.step and m.cur and r.step.id == m.cur.id) then return "the block doesn't hold the current step" end
    local ft, fb, fl, frr = f:GetTop(), f:GetBottom(), f:GetLeft(), f:GetRight()
    local rt, rb, rl, rr = r:GetTop(), r:GetBottom(), r:GetLeft(), r:GetRight()
    if not (ft and fb and fl and frr and rt and rb and rl and rr) then return nil end
    if rt > ft - Th.Size("title") + 0.5 or rb < fb - 0.5 or rl < fl - 0.5 or rr > frr + 0.5 then
        return "the current step sticks out of the window"
    end
    -- nothing under the block reaches into it (the next steps, the divider, the notice, the chips, the bar)
    local function Under(o)
        local t = o and o:IsShown() and o:GetTop()
        return type(t) ~= "number" or t <= rb + 0.5
    end
    if not (Under(UI.rows[2]) and Under(UI.divider) and Under(UI.noticeLine) and Under(UI.chips) and Under(UI.footer)) then
        return "something overlaps the step block"
    end
    -- the text fits its line(s): it ends above the first sub / goal line
    local s1 = r.subs and r.subs[1]
    local ln = r.lines and r.lines[1]
    local tb = r.text:GetBottom()
    local lt = (s1 and s1.text:IsShown() and s1.text:GetTop()) or (ln and ln.text:IsShown() and ln.text:GetTop())
    if type(tb) == "number" and type(lt) == "number" and tb < lt - 0.5 then
        return "the current step's text runs into its goal lines"
    end
    -- finished goals: one fold line at most; closed = no finished goal on a line of its own (unless it just finished)
    local folds, loose = 0, 0
    for _, l in ipairs(r.lines or {}) do
        if l.text:IsShown() then
            if l.fold then folds = folds + 1
            elseif l.done.base:IsShown() and (l.indent or 0) == 0 then loose = loose + 1 end
        end
    end
    if folds > 1 then return "more than one done line" end
    -- beta.8 step note: inside the block, under the last goal line, only on the current step
    local nt = r.note and r.note[1]
    if nt and nt:IsShown() then
        local nb = (r.note[2]:IsShown() and r.note[2] or nt):GetBottom()
        if type(nb) == "number" and nb < rb - 0.5 then return "the note line runs out of the step block" end
        local last
        for _, l in ipairs(r.lines or {}) do if l.text:IsShown() then last = l end end
        local lb, ntop = last and last.text:GetBottom(), nt:GetTop()
        if type(lb) == "number" and type(ntop) == "number" and ntop > lb + 0.5 then return "the note line overlaps the goals" end
    end
    for i = 2, #UI.rows do
        local o = UI.rows[i]
        if o and o:IsShown() and o.note and o.note[1]:IsShown() then return "a next step shows a note line" end
    end
    if (UI.foldCount or 0) > 0 and folds == 0 and loose > 0 and not UI.Small() then return "finished goals aren't folded" end
    -- with the 3D view: goal lines start under its square, the text right of it
    local MV = ns.ModelView
    local v = MV and MV.frame
    if r.lean and v and v:IsShown() and v:GetParent() == f then
        local vb, vr = v:GetBottom(), v:GetRight()
        local gt = ln and ln.text:IsShown() and ln.text:GetTop()
        if type(gt) == "number" and type(vb) == "number" and gt > vb + 0.5 then return "a goal line runs beside the 3D view" end
        local tl = r.text:GetLeft()
        if type(tl) == "number" and type(vr) == "number" and tl < vr - 0.5 then return "the step text runs under the 3D view" end
    end
    return UI.NextProblem()
end
UI.NowProblem = UI.BlockProblem

-- The next steps (4h): one line each, a framed tag, the target ends before the coords, fading, hairlines.
function UI.NextProblem()
    local prevA
    for i = 2, #UI.rows do
        local r = UI.rows[i]
        if r:IsShown() and r.tagged and not UI.Small() then
            if math.abs((r:GetHeight() or 0) - Th.LineHeight("step")) > 0.5 then return "next step " .. (i - 1) .. " isn't one line" end
            if not (r.tag and r.tag.text:IsShown() and r.tag.edges[1]:IsShown()) then return "next step " .. (i - 1) .. " has no tag" end
            local tr, tl = r.text:GetLeft(), r.tag.text:GetRight()
            if type(tr) == "number" and type(tl) == "number" and tr < tl - 0.5 then return "a next step's target runs into its tag" end
            local te = (r.text:GetLeft() or 0) + (r.text:GetStringWidth() or 0)
            local rl = (r.right:GetText() or "") ~= "" and r.right:GetRight() and (r.right:GetRight() - (r.right:GetStringWidth() or 0))
            if type(rl) == "number" and te > rl - 2 then return "a next step's target runs into its coords" end
            local a = select(4, r.text:GetTextColor())
            if prevA and a and a > prevA + 0.01 then return "the next steps don't fade" end
            prevA = a
            if i > 2 and not r.sep:IsShown() then return "no line between the next steps" end
        end
    end
    return nil
end
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "stepblock", fn = function(h)
    h.Count()
    local bad = UI.BlockProblem()
    if bad then h.Problem("stepblock: " .. bad) end
    -- every theme has the keys a theme needs (Theme.REQUIRED)
    for name in pairs(Th.themes) do
        local miss = Th.MissingKeys(name)
        if #miss > 0 then h.Problem(("theme %s lacks %s"):format(name, table.concat(miss, ", ", 1, math.min(3, #miss)))) end
    end
end }

-- Travel side goals: every theme knows the three side icons and their colours; the current step's side lines
-- (when its quests are in the log) each carry a count or our text, and an open one shows its icon.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "side goals", fn = function(h)
    h.Count()
    for name in pairs(Th.themes) do
        for _, kind in pairs(ns.Rows.SIDE_BADGE) do
            local b = K.BADGE[kind]
            if Th.Raw("color." .. b[2], name) == nil then h.Problem("side goals: theme " .. name .. " lacks color." .. b[2]) end
            if not ns.Media.Get(Th.Raw("slot." .. b[1], name) or b[1]) then h.Problem("side goals: no art for " .. b[1]) end
        end
    end
    local m = UI.model
    local row = UI.rows and UI.rows[1]
    if not (m and m.state == "guide" and m.rows and m.rows[1] and row and row:IsShown()) then return end
    local n = 0
    for i, g in ipairs(m.rows[1].goals or {}) do
        if g.side then
            n = n + 1
            if type(g.text) ~= "string" or g.text == "" then h.Problem("side goals: line " .. i .. " has no text") end
            local ln = row.lines and row.lines[i]
            if ln and g.kind and not g.done and not ln.pin:IsShown() then h.Problem("side goals: line " .. i .. " has no icon") end
        end
        if g.more and n ~= UI.SIDE_MAX then h.Problem("side goals: \"more\" line after " .. n .. " lines") end
    end
    h.Info("side goals: " .. n .. " shown")
end }

-- a bare /aog opens the main window on the page used last (the user's answer, 2026-11-25); without it
-- (safe mode, feature "hub" off) it shows or hides the guide window as before. /aog show always does that.
ns.Slash.SetDefault(function()
    if ns.Hub and ns.Hub.Available() then ns.Hub.Open() else UI.Toggle() end
end)
ns.Slash.Add("show", function() UI.Toggle() end, "HELP_SHOW", { main = true })
ns.Slash.Add("resetpos", function() UI.ResetPos() end, "HELP_RESETPOS")

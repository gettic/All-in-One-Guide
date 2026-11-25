-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The NOW window (2026-11-25, plans\now-window\plan.md): the current step in its own small window.
--   * attached (setting nowAttached, default): it sits size.nowGap above the guide window and is the root of
--     the pair: the guide window hangs under it, so the NOW window's top never moves when a taller step grows
--     it (the secure item button docks inside its top-right and never needs a re-place in combat). Dragging
--     either one moves both; one lock (`locked`) and one scale (`scale`) for the pair.
--   * free: its own spot, lock (`nowLocked`) and scale (`nowScale`); the guide window is on its own again.
--   * setting nowWindow off (or the feature "nowwin" switched off after 3 errors): the old NOW box inside the
--     guide window (UI\Window.lua).
-- The current step's row is the guide window's row 1 (ns.UI.rows[1]) moved into this window (SetParent), so
-- the arrow's distance, the finished-step flash and the step clicks keep working as they are.
-- Positions: char module `nowwin` { pair = {point, rel, x, y}, free = {...} }, written only when the player
-- moves it (or attaches / detaches); a session copy is used with a read-only save or in safe mode.
-- Never SetToplevel / Raise (tos: the item button keeps a fixed level above this window).
--   ns.NowWin.On(), .Attached(), .Build(), .Draw(row, d, m), .Layout(), .Place(), .SetShown(on), .SavePos(),
--   .Switch(key), .ResetPos(), .KeepOnScreen(), .Problem(), .CanDrag(), .ButtonSpot(), .frame / .strip / .head /
--   .lock / .attach / .grip
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local NW = { session = {} }
ns.NowWin = NW

local function L() return ns.L end
local function LH() return Th.LineHeight("step") end
local function TitleH() return Th.Size("title") end
local function S() return ns.Settings end

function NW.On()
    return S().Get("nowWindow") and ns.Feature.IsOn("nowwin") and not ns.safeMode and true or false
end
function NW.Attached() return S().Get("nowAttached") and true or false end
-- the scale setting this window follows now
function NW.ScaleKey() return NW.Attached() and "scale" or "nowScale" end
function NW.Locked() return S().Get(NW.Attached() and "locked" or "nowLocked") and true or false end

-- ------------------------------------------------------------------ saved spots
local function CanSave() return not ns.safeMode and not ns.DB.readOnly.char end

local function Saved(which)
    if NW.session[which] then return NW.session[which] end
    local mods = ns.DB.char and ns.DB.char.modules
    local m = type(mods) == "table" and mods.nowwin
    local p = type(m) == "table" and m[which]
    if type(p) ~= "table" or type(p.point) ~= "string" or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
    return p
end
NW.Saved = Saved

-- keep = true: only for this session (a first placement isn't written until the player moves the window)
local function Store(which, point, rel, x, y, keep)
    local p = { point = point, rel = rel or point, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    NW.session[which] = p
    if not keep and CanSave() then
        local m = ns.DB.Module("nowwin", "char", 1)
        m[which] = { point = p.point, rel = p.rel, x = p.x, y = p.y }
    end
    return p
end

-- UIParent units per unit of this frame
local function K_(f)
    local p = Co.UIParent()
    local ps = p and p.GetEffectiveScale and p:GetEffectiveScale()
    local fs = f and f.GetEffectiveScale and f:GetEffectiveScale()
    if not (ps and fs and ps > 0) then return 1 end
    return fs / ps
end

-- The NOW window's spot on top of the guide window where it stands now (the guide window doesn't move).
-- The guide window must be on its own spot (not anchored to this window) when this runs.
local function SpotAboveGuide(which, keep)
    local f, g = NW.frame, ns.UI.frame
    f:SetScale(ns.Overlay.WindowScale(which == "pair" and "scale" or "nowScale"))
    local gl, gt = g:GetLeft(), g:GetTop()
    local kf, kg = K_(f), K_(g)
    if gl and gt then
        local top = gt * kg + ((f:GetHeight() or 0) + Th.Size("nowGap")) * kf
        return Store(which, "TOPLEFT", "BOTTOMLEFT", gl * kg / kf, top / kf, keep)
    end
    -- the rect isn't known yet: the guide window's own point, moved up by this window's height
    local point, _, rel, x, y = g:GetPoint(1)
    if type(point) == "string" and point:find("^TOP") and type(x) == "number" and type(y) == "number" then
        return Store(which, point, rel, x, y + (f:GetHeight() or 0) + Th.Size("nowGap"), keep)
    end
    return Store(which, "TOPRIGHT", "TOPRIGHT", -90, -100, keep)
end

-- ------------------------------------------------------------------ building
-- The step area's height: at least size.nowLines step lines (and the item button's height when it shows).
function NW.MinBody(item)
    local h = Th.Size("nowLines") * LH()
    if item and ns.StepButton then
        h = math.max(h, Th.Size("nowButtonTop") + ns.StepButton.SIZE + 8 - Th.Size("nowMargin"))
    end
    return h
end

function NW.Height(rowH, item)
    return TitleH() + Th.Size("nowMargin") + math.max(rowH or 0, NW.MinBody(item)) + Th.Size("nowPadBottom")
end

-- Room the row keeps free on its right for the item button (Rows d.reserveRight).
function NW.Reserve()
    return Th.Size("nowButtonInset") + ns.StepButton.SIZE + 4 - Th.Size("nowMargin") - Th.Size("pad")
end

local function OnStripEnter(self)
    K.Tooltip(self, NW.Attached() and L().TIP_NOW_GRIP_PAIR or L().TIP_NOW_GRIP)
end

function NW.Build()
    if NW.frame then return NW.frame end
    local f = CreateFrame("Frame", nil, Co.UIParent())
    NW.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetWidth(ns.UI.Width())
    f:SetHeight(NW.Height(0, false))
    K.Panel(f, true)
    -- the step area: the NOW box's own panel and the accent edge on the left
    f.bg = K.Fill(f, "BACKGROUND", "nowBg", 1)
    f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -TitleH())
    f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.bar = K.Fill(f, "ARTWORK", "nowBar")
    f.bar:SetWidth(Th.Size("nowBar"))
    f.bar:SetPoint("TOPLEFT", f.bg, "TOPLEFT", 0, 0)
    f.bar:SetPoint("BOTTOMLEFT", f.bg, "BOTTOMLEFT", 0, 0)
    -- the title strip: grip (where the logo sits elsewhere), "NOW", section + step i/n, detach / attach, lock
    local tb = K.TitleBar(f, {
        drag = true, feature = "nowwin",
        canDrag = function() return NW.CanDrag() end,
        moveFrame = function() return f end,
        dragStop = function() NW.SavePos() end,
    })
    NW.strip = tb
    NW.grip = tb.logo
    Th.Glyph(tb.logo, "btn.grip")
    tb.logo:SetVertexColor(Th.Color("button"))
    NW.head = K.Text(tb, "sectionHead", "nowHead")
    NW.head:SetPoint("LEFT", tb.logo, "RIGHT", 4, 0)
    NW.head:SetText(L().NOW_HEAD)
    local s = Th.Size("button")
    NW.lock = K.GlyphButton(tb, "btn.unlock", s, function()
        return NW.Locked() and L().TIP_NOW_UNLOCK or L().TIP_NOW_LOCK
    end, function()
        local key = NW.Attached() and "locked" or "nowLocked"
        S().Set(key, not S().Get(key))
    end)
    NW.lock:SetPoint("RIGHT", tb, "RIGHT", -3, 0)
    NW.attach = K.GlyphButton(tb, "btn.detach", s, function()
        return NW.Attached() and L().TIP_NOW_DETACH or L().TIP_NOW_ATTACH
    end, function()
        S().Set("nowAttached", not NW.Attached())
    end)
    NW.attach:SetPoint("RIGHT", NW.lock, "LEFT", -2, 0)
    tb.title:ClearAllPoints()
    tb.title:SetPoint("LEFT", NW.head, "RIGHT", 5, 0)
    tb.title:SetPoint("RIGHT", NW.attach, "LEFT", -4, 0)
    K.Color(tb.title, "text.dim")
    tb:SetScript("OnEnter", OnStripEnter)
    tb:SetScript("OnLeave", K.HideTooltip)
    tb:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.Menu.Open(self, ns.UI.MenuItems()) end
    end)
    f:Hide()
    return f
end

-- The strip's buttons follow the mode (lock icon of the setting in charge, chain = what a click does).
local function Buttons()
    Th.Glyph(NW.lock.icon, NW.Locked() and "btn.lock" or "btn.unlock")
    Th.Glyph(NW.attach.icon, NW.Attached() and "btn.detach" or "btn.attach")
    NW.grip:SetVertexColor(Th.Color("button"))   -- (again after a look change: the grip isn't a K.Glyph)
end
NW.Buttons = Buttons

-- Draws the current step (row = the guide window's row 1, moved in here). Returns the window's height.
function NW.Draw(row, d, m)
    local f = NW.Build()
    if row:GetParent() ~= f then row:SetParent(f) end
    local item = ns.Feature.IsOn("stepbutton") and ns.StepButton and ns.StepButton.ItemFor(m.cur) ~= nil
    d.boxed = true
    d.reserveRight = item and NW.Reserve() or nil
    local mg = Th.Size("nowMargin")
    local top = TitleH() + mg
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f, "TOPLEFT", mg, -top)
    row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -mg, -top)
    row:Show()
    local h = ns.Rows.Set(row, d)
    local height = NW.Height(h, item)
    if math.abs((f:GetHeight() or 0) - height) > 0.01 then
        f:SetHeight(height)
        NW.Clamp()
    end
    NW.strip.title:SetText(ns.U.Fill(L().NOW_STRIP, { section = m.section or "", i = m.index or 0, n = m.count or 0 }))
    NW.head:SetText(L().NOW_HEAD)
    return height
end

function NW.SetShown(on)
    if not NW.frame then
        if not on then return end
        NW.Build()
    end
    NW.frame:SetShown(on and true or false)
end

-- ------------------------------------------------------------------ place, clamp, layout
-- Attached: the window at the pair spot and the guide window under it. Free: each on its own spot.
function NW.Place()
    local f, g, p = NW.frame, ns.UI.frame, Co.UIParent()
    if NW.Attached() then
        local s = Saved("pair")
        if not s then
            ns.UI.ApplyGuidePos()
            s = SpotAboveGuide("pair", true)
        end
        f:ClearAllPoints()
        f:SetPoint(s.point, p, s.rel, s.x, s.y)
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -Th.Size("nowGap"))
    else
        ns.UI.ApplyGuidePos()
        local s = Saved("free") or SpotAboveGuide("free", true)
        f:ClearAllPoints()
        f:SetPoint(s.point, p, s.rel, s.x, s.y)
    end
end

-- Attached: this window keeps room under it for the guide window (negative bottom inset; sign from
-- warcraft.wiki.gg API_Frame_SetClampRectInsets) and the guide window's own clamp is off (it would fight its
-- anchor). Free: both clamp on their own.
function NW.Clamp()
    local f, g = NW.frame, ns.UI.frame
    if not (f and g) then return end
    if NW.On() and NW.Attached() then
        g:SetClampedToScreen(false)
        if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 0, -math.floor((g:GetHeight() or 0) + Th.Size("nowGap"))) end
    else
        g:SetClampedToScreen(true)
        if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 0, 0) end
    end
end

-- From UI.Layout: scale, width, spot, clamp, buttons. Off: the guide window back on its own.
function NW.Layout()
    if not NW.On() then return NW.Off() end
    local f = NW.Build()
    f:SetScale(ns.Overlay.WindowScale(NW.ScaleKey()))
    f:SetWidth(ns.UI.Width())
    NW.Place()
    NW.Clamp()
    Buttons()
    NW.KeepOnScreen()
end

function NW.Off()
    local g = ns.UI.frame
    if NW.frame then
        NW.frame:Hide()
        local _, rel = g:GetPoint(1)
        if rel == NW.frame then ns.UI.ApplyGuidePos() end
    end
    g:SetClampedToScreen(true)
end

-- Both windows back inside the screen after a scale or screen change (works without the clamp insets too).
function NW.KeepOnScreen()
    local f, g, p = NW.frame, ns.UI.frame, Co.UIParent()
    if not (NW.On() and f and g and g:IsShown()) then return false end
    if not NW.Attached() then return f:IsShown() and ns.Overlay.KeepOnScreen(f) or false end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), g:GetBottom()
    if not (l and r and t and b and p) then return false end
    local kf, kg = K_(f), K_(g)
    local L_, R_, T_, B_ = l * kf, r * kf, t * kf, b * kg
    local pw, ph = p:GetWidth(), p:GetHeight()
    local dx, dy = 0, 0
    if L_ < 0 then dx = -L_ elseif R_ > pw then dx = pw - R_ end
    if T_ > ph then dy = ph - T_ elseif B_ < 0 then dy = -B_ end
    if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then return false end
    local s = Store("pair", "TOPLEFT", "BOTTOMLEFT", (L_ + dx) / kf, (T_ + dy) / kf, true)
    f:ClearAllPoints()
    f:SetPoint(s.point, p, s.rel, s.x, s.y)
    return true
end

-- ------------------------------------------------------------------ drag, attach / detach
-- In combat the windows stay put while the secure item button shows (it can't follow until combat ends).
function NW.CombatOk()
    local SB = ns.StepButton
    if Co.InCombat() and SB and SB.frame and SB.frame:IsShown() then
        if not NW.saidCombat then
            NW.saidCombat = true
            ns.Print(L().NOW_NO_DRAG_COMBAT)
        end
        return false
    end
    return true
end

function NW.CanDrag()
    if NW.Locked() then return false end
    return NW.CombatOk()
end

-- After a drag (of this window or, attached, of the guide window): re-anchored by its top-left (so a taller
-- step grows it downwards), saved; attached also the guide window's spot (it stays there if the NOW window
-- is turned off later).
function NW.SavePos()
    local f = NW.frame
    if not f then return end
    local l, t = f:GetLeft(), f:GetTop()
    if l and t then
        local s = Store(NW.Attached() and "pair" or "free", "TOPLEFT", "BOTTOMLEFT", l, t)
        f:ClearAllPoints()
        f:SetPoint(s.point, Co.UIParent(), s.rel, s.x, s.y)
    end
    if NW.Attached() then ns.UI.SaveGuideSpot() end
    ns.Bus.Fire("WindowMoved")
end

-- A NOW setting changed (before UI.Layout runs): keep what's on screen where it is.
--   nowAttached off: the NOW window keeps its top-left on screen at its new scale; the guide window stays.
--   nowAttached on: the NOW window jumps on top of the guide window (the guide window stays).
--   nowWindow off: the guide window stays where it is. nowWindow on: the NOW window on top of the guide.
function NW.Switch(key)
    local f, g = NW.frame, ns.UI.frame
    if not g then return end
    if key == "nowWindow" then
        if not S().Get("nowWindow") then
            if f then
                local _, rel = g:GetPoint(1)
                if rel == f then ns.UI.KeepGuideSpot() end
            end
        elseif NW.On() then
            NW.Build()
            NW.session.pair = nil
            ns.UI.ApplyGuidePos()
            if NW.Attached() then SpotAboveGuide("pair") end
        end
        return
    end
    if key ~= "nowAttached" or not f or not NW.On() then return end
    if not NW.Attached() then
        local l, t = f:GetLeft(), f:GetTop()
        ns.UI.KeepGuideSpot()
        if l and t then
            local old = f:GetEffectiveScale()
            local p = Co.UIParent()
            local new = ns.Overlay.WindowScale("nowScale") * (p and p:GetEffectiveScale() or 1)
            if new > 0 then Store("free", "TOPLEFT", "BOTTOMLEFT", l * old / new, t * old / new) end
        end
    else
        ns.UI.ApplyGuidePos()
        f:SetScale(ns.Overlay.WindowScale("scale"))
        SpotAboveGuide("pair")
    end
end

function NW.ResetPos()
    NW.session = {}
    local mods = ns.DB.char and ns.DB.char.modules
    local m = type(mods) == "table" and mods.nowwin
    if type(m) == "table" and CanSave() then m.pair, m.free = nil, nil end
end

-- ------------------------------------------------------------------ item button spot + checks
-- Where the item button's top-right goes, in this window's units from its own top-right.
function NW.ButtonSpot()
    return Th.Size("nowButtonInset"), TitleH() + Th.Size("nowButtonTop")
end

-- nil when right (or not judged now), else a short reason. Self-test "nowwin" + the offline tests.
function NW.Problem()
    local UI = ns.UI
    local m, r, f, g = UI.model, UI.rows[1], NW.frame, UI.frame
    if not (NW.On() and g and g:IsShown() and m and m.state == "guide" and f) then return nil end
    if not f:IsShown() then return "the NOW window is hidden" end
    if not (r and r:IsShown()) then return "the current step isn't shown" end
    if r:GetParent() ~= f then return "the current step isn't in the NOW window" end
    if not (r.step and m.cur and r.step.id == m.cur.id) then return "the NOW window doesn't hold the current step" end
    local fl, fr, ft, fb = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    local rl, rr, rt, rb = r:GetLeft(), r:GetRight(), r:GetTop(), r:GetBottom()
    if not (fl and fr and ft and fb and rl and rr and rt and rb) then return nil end
    if rt > ft - TitleH() + 0.5 or rb < fb - 0.5 or rl < fl - 0.5 or rr > fr + 0.5 then
        return "the current step sticks out of the NOW window"
    end
    local ln = r.lines and r.lines[1]
    local tb, lt = r.text:GetBottom(), ln and ln.text:IsShown() and ln.text:GetTop()
    if type(tb) == "number" and type(lt) == "number" and tb < lt - 0.5 then
        return "the current step's text runs into its goal lines"
    end
    local kf, kg = K_(f), K_(g)
    local gt, gl = g:GetTop(), g:GetLeft()
    if NW.Attached() and gt and gl then
        local gap = fb * kf - gt * kg
        if math.abs(gap - Th.Size("nowGap") * kf) > 1 then return ("gap to the guide window %.1f"):format(gap) end
        if math.abs(gl * kg - fl * kf) > 1 then return "not lined up with the guide window" end
    end   -- (free: it may sit anywhere, even over the guide window: the player put it there)
    -- the item button: inside the top-right, above this window
    local SB, CQ = ns.StepButton, ns.CombatQueue
    local b = SB and SB.frame
    if b and b:IsShown() and not Co.InCombat() and not CQ.Pending("stepbutton") then
        if (b:GetFrameLevel() or 0) <= (f:GetFrameLevel() or 0) then return "the item button is under the NOW window" end
        local bl, br, bt, bb = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
        local kb = K_(b)
        if bl and br and bt and bb and (bl * kb < fl * kf - 0.5 or br * kb > fr * kf + 0.5 or bt * kb > ft * kf + 0.5
            or bb * kb < fb * kf - 0.5) then
            return "the item button isn't inside the NOW window"
        end
    end
    return nil
end

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "nowwin", fn = function(h)
    h.Count()
    local bad = NW.Problem()
    if bad then h.Problem("nowwin: " .. bad) end
    if NW.On() then h.Info(("NOW window: %s"):format(NW.Attached() and "attached" or "free")) end
end }

ns.Bus.On("CombatEnded", NW, function() NW.saidCombat = nil end, "nowwin")

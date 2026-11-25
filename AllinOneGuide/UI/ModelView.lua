-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The 3D viewer (v0.3): one PlayerModel frame `AllinOneGuideModel` that shows the NPC or mob the current step is
-- about, docked to the guide window (setting modelPos: left (default) / right / below / free). Display only:
-- no targeting, no reading of other units, nothing secure (PlayerModel isn't protected, so it may move in combat).
--   * target, in order: a hunt-path target (SetTarget(npc, "hunt"), static pack data only, never a live
--     "nearest mob"), else the step's `model` (a display id), `targetNpc`, `npc`
--   * load: SetCreature(npc) first (by NPC id, the client's own model files); when no model file shows after
--     OnModelLoaded or CHECK_AFTER s, SetDisplayInfo(ns.ModelIds[npc]); then the fallback card (our own badge
--     art + "No 3D view"). Only when the target (or the SD / HD answer) changes.
--   * hidden: setting off, safe mode, window hidden / suppressed, small mode, no target, in combat
--     (modelHideCombat; off = it stays but freezes: no reload until the fight ends)
--   * the frame is built the first time it shows (setting off = no frame); ClearModel after CLEAR_AFTER s hidden
--   * mouse: drag turns it (OnUpdate only while dragging), wheel zooms, double-click resets, right-click menu,
--     Shift+drag moves it in "free" position
--   ns.ModelView.Update(), .TargetFor(step), .SetTarget(npc, source), .Why(), .Place(), .Misplaced()
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local MV = {
    NAME = "AllinOneGuideModel", POSITIONS = { "left", "right", "below", "free" },
    ZOOM_MAX = 0.8, ZOOM_STEP = 0.1, TURN = 0.02, CHECK_AFTER = 0.5, CLEAR_AFTER = 30, DOUBLE = 0.35,
    -- step types that are about someone even without an npc id: they get the card instead of nothing
    CARD_TYPES = { accept = true, turnin = true, objective = true, useitem = true },
    facing = 0, zoom = 0, loads = 0, token = 0,
}
ns.ModelView = MV
local TWO_PI = math.pi * 2

local function S() return ns.Settings end
local function L() return ns.L end
local function PosInt(v) return type(v) == "number" and v > 0 and v == math.floor(v) and v or nil end

-- ------------------------------------------------------------------ what to show
-- { npc, display, key } or nil (nothing to show) or { card = true, key } (someone without a 3D view).
function MV.TargetFor(step)
    local h = MV.hunt
    if h then return { npc = h, display = ns.ModelIds and ns.ModelIds[h], key = "n" .. h, source = "hunt" } end
    if not step then return nil end
    local model = PosInt(step.model)
    if model then return { display = model, key = "d" .. model, source = "step" } end
    local npc = PosInt(step.targetNpc) or PosInt(step.npc)
    if npc then return { npc = npc, display = ns.ModelIds and ns.ModelIds[npc], key = "n" .. npc, source = "step" } end
    if MV.CARD_TYPES[step.type] then return { card = true, key = "card", source = "step" } end
    return nil
end

-- The hunt path's contract (plans\model-viewer\plan.md section 8): its current segment's mob from its static
-- data; source "hunt" wins while set, nil clears it. Anything else is ignored.
function MV.SetTarget(npc, source)
    if source ~= "hunt" then return false end
    MV.hunt = PosInt(npc)
    MV.Update()
    return true
end

-- Why it's hidden now, or nil when it shows.
function MV.Why()
    if not S().Get("modelViewer") then return "off" end
    if ns.safeMode then return "safe" end
    if not (ns.UI and ns.UI.IsShown and ns.UI.IsShown()) then return "window" end
    if ns.UI.suppressed then return "suppressed" end
    if S().Get("small") then return "small" end
    if Co.InCombat() and S().Get("modelHideCombat") then return "combat" end
    if not MV.TargetFor(ns.Engine.Current()) then return "none" end
    return nil
end

-- ------------------------------------------------------------------ building
local function Edges(f)
    local e = {}
    local b = K.Hair(Th.Size("border"))
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = K.Fill(f, "BORDER", "modelEdge")
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT", f, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", f, side .. "RIGHT", 0, 0)
            t:SetHeight(b)
        else
            t:SetPoint("TOP" .. side, f, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, f, "BOTTOM" .. side, 0, 0)
            t:SetWidth(b)
        end
        e[i] = t
    end
    return e
end

local function Build()
    local CreateFrame = _G.CreateFrame
    local f = CreateFrame("Frame", MV.NAME, Co.UIParent())
    f:SetFrameStrata("MEDIUM")
    f:SetSize(Th.Size("modelW"), Th.Size("modelH"))
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:Hide()
    f.bg = K.Fill(f, "BACKGROUND", "modelBg")
    f.bg:SetAllPoints()
    f.edges = Edges(f)
    local m = CreateFrame("PlayerModel", nil, f)
    local inset = Th.Size("modelInset")
    m:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    m:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    m:EnableMouse(false)
    if m.SetKeepModelOnHide then m:SetKeepModelOnHide(true) end
    if m.HasScript and m:HasScript("OnModelLoaded") then
        m:SetScript("OnModelLoaded", function() ns.Errors.Call("model", MV.Check, "loaded") end)
    end
    f.model = m
    -- the fallback card: the step's badge (our own art) and "No 3D view"
    local card = CreateFrame("Frame", nil, f)
    card:SetAllPoints()
    card.badge = K.Badge(card, 32)
    card.badge.disc:SetPoint("CENTER", card, "CENTER", 0, 10)
    card.text = K.Text(card, "goal", "modelText", "CENTER")
    card.text:SetPoint("TOP", card.badge.disc, "BOTTOM", 0, -6)
    card.text:SetText(L().MODEL_NONE)
    card:Hide()
    f.card = card
    f:SetScript("OnMouseDown", function(self, button) ns.Errors.Call("model", MV.MouseDown, self, button) end)
    f:SetScript("OnMouseUp", function(self, button) ns.Errors.Call("model", MV.MouseUp, self, button) end)
    f:SetScript("OnMouseWheel", function(_, delta) ns.Errors.Call("model", MV.Zoom, delta) end)
    f:SetScript("OnEnter", function(self) ns.Errors.Call("model", MV.Tip, self) end)
    f:SetScript("OnLeave", function() K.HideTooltip() end)
    f:SetScript("OnHide", function(self)
        if MV.dragging then MV.dragging = nil self:SetScript("OnUpdate", nil) end
        if MV.moving then MV.moving = nil self:StopMovingOrSizing() end
    end)
    MV.frame = f
    return f
end
MV.Build = function() return MV.frame or Build() end

-- ------------------------------------------------------------------ placing
local function Scale()
    local s = ns.Overlay.WindowScale()
    if type(s) ~= "number" or s <= 0 then s = 1 end
    return s * S().Get("modelScale")
end

local function FreeSpot()
    local m = ns.DB.char and type(ns.DB.char.modules) == "table" and ns.DB.char.modules.model
    if type(m) ~= "table" or type(m.left) ~= "number" or type(m.top) ~= "number" then return nil end
    return m
end

local function CanSave() return not ns.safeMode and not (ns.DB.readOnly and ns.DB.readOnly.char) end

-- Remembers the free spot (UIParent units, so a size change keeps its top-left corner).
function MV.SaveSpot()
    local f, p = MV.frame, Co.UIParent()
    if not (f and p and CanSave()) then return false end
    local l, t, ps = f:GetLeft(), f:GetTop(), p:GetEffectiveScale()
    if not (l and t and ps and ps > 0) then return false end
    local k = f:GetEffectiveScale() / ps
    local m = ns.DB.Module("model", "char", 1)
    m.left, m.top = math.floor(l * k + 0.5), math.floor(t * k + 0.5)
    return true
end

-- The room the step button takes at the window's top-left (window units), so a left dock sits under it.
-- With the NOW window on, the button sits inside that window instead: no room taken.
local function ButtonRoom()
    local SB = ns.StepButton
    if not (SB and SB.frame and SB.frame:IsShown()) then return 0 end
    if SB.InNow and SB.InNow() then return 0 end
    return SB.SIZE + 8 + Th.Size("modelGap")
end

-- The NOW window when it sits attached on top of the guide window (then "above" docks over it), else nil.
local function NowOnTop()
    local NW = ns.NowWin
    if not (NW and NW.On and NW.On() and NW.Attached() and NW.frame and NW.frame:IsShown()) then return nil end
    return NW.frame
end
MV.NowOnTop = NowOnTop

-- Which side it docks to: the wanted one, or another one when that has no room on the screen.
-- below -> above (over the attached NOW window, never on it) -> left / right (whichever fits) when the
-- screen is too short for both (beta.5 fix: "above" used to cover the NOW window or be clamped onto the guide).
function MV.Side(want, f, w)
    local p = Co.UIParent()
    if want == "free" or not (p and w) then return want end
    local ps = p:GetEffectiveScale()
    local wl, wr, wb, wt = w:GetLeft(), w:GetRight(), w:GetBottom(), w:GetTop()
    if not (ps and ps > 0 and wl and wr and wb and wt) then return want end
    local kw, kf = w:GetEffectiveScale() / ps, Scale() * (p:GetEffectiveScale() / ps)
    local gap = Th.Size("modelGap") * kw
    local vw, vh = Th.Size("modelW") * kf, Th.Size("modelH") * kf
    local pw, ph = p:GetWidth(), p:GetHeight()
    local roomL = wl * kw - gap - vw >= 0
    local roomR = wr * kw + gap + vw <= pw
    local top = wt * kw
    local now = NowOnTop()
    if now and now:GetTop() then top = math.max(top, now:GetTop() * (now:GetEffectiveScale() / ps)) end
    local roomB = wb * kw - gap - vh >= 0
    local roomA = top + gap + vh <= ph
    if want == "left" and not roomL and roomR then return "right" end
    if want == "right" and not roomR and roomL then return "left" end
    if want == "below" and not roomB then
        if roomA then return "above" end
        if roomL then return "left" end
        if roomR then return "right" end
    end
    return want
end

function MV.Place()
    local f, w, p = MV.frame, ns.UI and ns.UI.frame, Co.UIParent()
    if not f then return end
    local s = Scale()
    f:SetScale(s)
    f:SetSize(Th.Size("modelW"), Th.Size("modelH"))
    f:ClearAllPoints()
    local want = S().Get("modelPos")
    local side = MV.Side(want, f, w)
    MV.side = side
    local ms = S().Get("modelScale")
    local gap = Th.Size("modelGap") / ms   -- window units -> the viewer's own units
    if side == "free" or not w then
        local m = FreeSpot()
        local ps = p and p:GetEffectiveScale()
        if m and ps and ps > 0 then
            local k = f:GetEffectiveScale() / ps
            f:SetPoint("TOPLEFT", p, "BOTTOMLEFT", m.left / k, m.top / k)
        elseif w then
            f:SetPoint("TOPRIGHT", w, "TOPLEFT", -gap, -ButtonRoom() / ms)
        else
            f:SetPoint("CENTER", p, "CENTER", 0, 0)
        end
    elseif side == "right" then
        f:SetPoint("TOPLEFT", w, "TOPRIGHT", gap, 0)
    elseif side == "below" then
        f:SetPoint("TOPLEFT", w, "BOTTOMLEFT", 0, -gap)
    elseif side == "above" then
        -- over the attached NOW window's top (same left edge as the guide window), else the guide's top
        local now = NowOnTop()
        if now then
            -- anchored to the NOW window itself (it moves and grows with it), lined up with the guide's left
            local nl, wl = now:GetLeft(), w:GetLeft()
            local dx = 0
            if nl and wl then dx = (wl * w:GetEffectiveScale() - nl * now:GetEffectiveScale()) / f:GetEffectiveScale() end
            f:SetPoint("BOTTOMLEFT", now, "TOPLEFT", dx, gap)
        else
            f:SetPoint("BOTTOMLEFT", w, "TOPLEFT", 0, gap)
        end
    else
        f:SetPoint("TOPRIGHT", w, "TOPLEFT", -gap, -ButtonRoom() / ms)
    end
end

-- nil when it sits where it should (or can't be judged now), else a short reason. Self-test + offline tests.
function MV.Misplaced()
    local f, w, p = MV.frame, ns.UI and ns.UI.frame, Co.UIParent()
    if not (f and w and p and f:IsShown() and w:IsShown()) or MV.side == "free" or MV.moving then return nil end
    local ps = p:GetEffectiveScale()
    local fl, fr, fb, ft = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
    local wl, wr, wb, wt = w:GetLeft(), w:GetRight(), w:GetBottom(), w:GetTop()
    if not (ps and fl and fr and fb and ft and wl and wr and wb and wt) then return nil end
    local kf, kw = f:GetEffectiveScale() / ps, w:GetEffectiveScale() / ps
    local want = Scale() * (p:GetEffectiveScale() / ps)
    if math.abs(kf - want) > 0.01 then return ("scale %.2f, wanted %.2f"):format(kf, want) end
    fl, fr, fb, ft = fl * kf, fr * kf, fb * kf, ft * kf
    wl, wr, wb, wt = wl * kw, wr * kw, wb * kw, wt * kw
    local gap = Th.Size("modelGap") * kw
    -- never on the guide window or the attached NOW window, also when the screen edge clamps it (beta.5)
    local function Covers(l, r, b, t) return fl < r - 0.5 and fr > l + 0.5 and fb < t - 0.5 and ft > b + 0.5 end
    if Covers(wl, wr, wb, wt) then return "covers the guide window" end
    local now = NowOnTop()
    if now then
        local kn = now:GetEffectiveScale() / ps
        local nl, nr, nb, nt = now:GetLeft(), now:GetRight(), now:GetBottom(), now:GetTop()
        if nl and nr and nb and nt and Covers(nl * kn, nr * kn, nb * kn, nt * kn) then return "covers the NOW window" end
    end
    -- clamped at a screen edge: the gaps aren't judged
    if fl < 0.5 or fb < 0.5 or fr > p:GetWidth() - 0.5 or ft > p:GetHeight() - 0.5 then return nil end
    local side = MV.side
    if side == "left" then
        if math.abs((wl - fr) - gap) > 1 then return ("left gap %.1f, wanted %.1f"):format(wl - fr, gap) end
        if math.abs((wt - ft) - ButtonRoom() * kw) > 1 then return "not under the step button / window top" end
    elseif side == "right" then
        if math.abs((fl - wr) - gap) > 1 then return ("right gap %.1f, wanted %.1f"):format(fl - wr, gap) end
        if math.abs(ft - wt) > 1 then return "not level with the window's top" end
    elseif side == "below" then
        if math.abs((wb - ft) - gap) > 1 then return ("gap below %.1f, wanted %.1f"):format(wb - ft, gap) end
        if math.abs(fl - wl) > 1 then return "not level with the window's left edge" end
    elseif side == "above" then
        local top = wt
        if now and now:GetTop() then top = math.max(top, now:GetTop() * (now:GetEffectiveScale() / ps)) end
        if math.abs((fb - top) - gap) > 1 then return ("gap above %.1f, wanted %.1f"):format(fb - top, gap) end
        if math.abs(fl - wl) > 1 then return "not level with the window's left edge" end
    end
    return nil
end

-- ------------------------------------------------------------------ loading
-- SD / HD character models (#20): true / false, or nil when the game can't tell. Read on every update.
local function SD() return Co.SDModels() end

local function ShowCard(on)
    local f = MV.frame
    f.card:SetShown(on)
    f.model:SetShown(not on)
    if on then
        local step = ns.Engine.Current()
        K.SetBadge(f.card.badge, step and K.BadgeKind(step) or "manual")
        f.card.text:SetText(L().MODEL_NONE)
    end
end

local function ApplyView()
    local m = MV.frame.model
    if m.SetFacing then m:SetFacing(MV.facing) end
    if m.SetPortraitZoom then m:SetPortraitZoom(MV.zoom) end
end

-- stage: "npc" (SetCreature), "display" (SetDisplayInfo), "card" (nothing to show)
local function Try(stage)
    local f, t = MV.frame, MV.target
    local m = f.model
    MV.token = MV.token + 1
    MV.stage = stage
    if stage == "npc" then
        ShowCard(false)
        m:SetCreature(t.npc)
    elseif stage == "display" then
        ShowCard(false)
        m:SetDisplayInfo(t.display)
    else
        if m.ClearModel then m:ClearModel() end
        ShowCard(true)
        return
    end
    MV.loads = MV.loads + 1
    ApplyView()
    local token = MV.token
    Co.After(MV.CHECK_AFTER, function()
        if MV.token == token then ns.Errors.Call("model", MV.Check, "timer") end
    end)
end

local function Next(stage)
    local t = MV.target
    if stage == "npc" and t.display then return "display" end
    return "card"
end

-- Did the model load? why = "loaded" (OnModelLoaded) or "timer". A late model brings the view back.
function MV.Check(why)
    local f = MV.frame
    if not (f and MV.target) or MV.stage == nil then return end
    -- no way to ask: trust what was asked for (never step down on a guess)
    if not f.model.GetModelFileID then
        if MV.stage ~= "card" then MV.result = MV.stage end
        return
    end
    local id = f.model:GetModelFileID()
    if type(id) == "number" and id > 0 then
        if MV.stage == "card" then
            -- a late model after all: back to the view (the last thing asked for)
            if MV.target.card then return end
            ShowCard(false)
            MV.stage = MV.target.display and "display" or "npc"
        end
        MV.result = MV.stage
        MV.token = MV.token + 1   -- no step down any more
        ApplyView()
        return
    end
    if MV.stage == "card" then return end
    if why == "loaded" or why == "timer" then
        local nxt = Next(MV.stage)
        Try(nxt)
        if nxt == "card" then MV.result = "none" end
    end
end

-- Loads the target when it (or the SD / HD answer) changed. Returns true when it loaded something new.
local function Load(t)
    local sd = SD()
    local key = t.key .. "|" .. tostring(sd)
    if key == MV.loadedKey then return false end
    MV.loadedKey = key
    MV.target = t
    MV.sd = sd
    MV.result = nil
    if t.card then
        Try("card")
        MV.result = "none"
    elseif t.npc then
        Try("npc")
    else
        Try("display")
    end
    return true
end

-- ------------------------------------------------------------------ show / hide
function MV.Update()
    local why = MV.Why()
    MV.why = why
    local f = MV.frame
    if why then
        if f and f:IsShown() then
            f:Hide()
            if ns.Menu.anchor == f and ns.Menu.IsOpen() then ns.Menu.Close() end   -- only our own menu
            -- one unload timer per hide: showing again (or another hide) cancels it (beta.5 fix)
            MV.hideSeq = (MV.hideSeq or 0) + 1
            local token, seq = MV.token, MV.hideSeq
            MV.hiddenAt = Co.Now()
            Co.After(MV.CLEAR_AFTER, function()
                if MV.frame and not MV.frame:IsShown() and MV.token == token and MV.hideSeq == seq then
                    ns.Errors.Call("model", MV.Unload)
                end
            end)
        end
        return
    end
    f = f or Build()
    if not f:IsShown() then MV.hideSeq = (MV.hideSeq or 0) + 1 end
    MV.Place()
    -- in combat with modelHideCombat off: it stays as it is (no reload until the fight ends); with nothing
    -- loaded (first show or after the unload) the card stands in until then (beta.5 fix: an empty box)
    MV.waiting = nil
    if not Co.InCombat() then
        Load(MV.TargetFor(ns.Engine.Current()))
    elseif not MV.loadedKey then
        MV.waiting = true
        MV.stage = "card"
        ShowCard(true)
    end
    f:Show()
end

-- Frees the model (after CLEAR_AFTER s hidden); the next show loads it again.
function MV.Unload()
    local f = MV.frame
    if not f then return end
    if f.model.ClearModel then f.model:ClearModel() end
    MV.token = MV.token + 1
    MV.loadedKey, MV.target, MV.stage = nil, nil, nil
    MV.unloads = (MV.unloads or 0) + 1
end

-- ------------------------------------------------------------------ mouse
function MV.Wrap(a)
    a = a % TWO_PI
    if a < 0 then a = a + TWO_PI end
    return a
end

local function DragUpdate(self)
    local x = Co.Cursor(self)
    if not (x and MV.dragging) then return end
    local d = MV.dragging
    if math.abs(x - d.x0) > 2 then d.moved = true end
    MV.facing = MV.Wrap(d.f0 + (x - d.x0) * MV.TURN)
    if self.model.SetFacing then self.model:SetFacing(MV.facing) end
end
MV.DragUpdate = DragUpdate

function MV.MouseDown(self, button)
    if button ~= "LeftButton" then return end
    if S().Get("modelPos") == "free" and Co.Modifier("shift") then
        MV.moving = true
        self:StartMoving()
        return
    end
    local x = Co.Cursor(self)
    MV.dragging = { x0 = x or 0, f0 = MV.facing }
    self:SetScript("OnUpdate", DragUpdate)
end

function MV.MouseUp(self, button)
    if button == "RightButton" then
        ns.Menu.Open(self, MV.MenuItems())
        return
    end
    if button ~= "LeftButton" then return end
    if MV.moving then
        MV.moving = nil
        self:StopMovingOrSizing()
        MV.SaveSpot()
        MV.Place()
        return
    end
    local d = MV.dragging
    MV.dragging = nil
    self:SetScript("OnUpdate", nil)
    if d and d.moved then MV.lastClick = nil return end
    local now = Co.Now()
    if MV.lastClick and now - MV.lastClick <= MV.DOUBLE then
        MV.lastClick = nil
        MV.ResetView()
    else
        MV.lastClick = now
    end
end

function MV.Zoom(delta)
    MV.zoom = ns.U.Clamp(MV.zoom + (delta > 0 and MV.ZOOM_STEP or -MV.ZOOM_STEP), 0, MV.ZOOM_MAX)
    local f = MV.frame
    if f and f.model.SetPortraitZoom then f.model:SetPortraitZoom(MV.zoom) end
end

function MV.ResetView()
    MV.facing, MV.zoom = 0, 0
    if MV.frame then ApplyView() end
end

function MV.Tip(owner)
    local step = ns.Engine.Current()
    local g = ns.Engine.Focused()
    local title = (step and g and g:Top():Text(step)) or L().MODEL_TITLE
    local lines = {}
    if MV.stage ~= "card" then
        lines[#lines + 1] = L().MODEL_TIP_DRAG
        lines[#lines + 1] = L().MODEL_TIP_WHEEL
        lines[#lines + 1] = L().MODEL_TIP_RESET
    end
    if S().Get("modelPos") == "free" then lines[#lines + 1] = L().MODEL_TIP_MOVE end
    lines[#lines + 1] = L().MODEL_TIP_RIGHT
    K.Tooltip(owner, title, lines)
end

local POS_LABEL = { left = "CHOICE_MODEL_LEFT", right = "CHOICE_MODEL_RIGHT", below = "CHOICE_MODEL_BELOW", free = "CHOICE_MODEL_FREE" }
MV.POS_LABEL = POS_LABEL

function MV.MenuItems()
    local set = S()
    local cur = set.Get("modelPos")
    local nxt = MV.POSITIONS[1]
    for i, v in ipairs(MV.POSITIONS) do if v == cur then nxt = MV.POSITIONS[i % #MV.POSITIONS + 1] end end
    return {
        { text = L().MENU_MODEL_RESET, fn = MV.ResetView },
        { text = ns.U.Fill(L().MENU_MODEL_POS, { pos = L()[POS_LABEL[cur]] or cur }), fn = function() set.Set("modelPos", nxt) end },
        { text = L().MENU_MODEL_COMBAT, checked = set.Get("modelHideCombat"),
            fn = function() set.Set("modelHideCombat", not set.Get("modelHideCombat")) end },
        { text = L().MENU_MODEL_HIDE, fn = function() set.Set("modelViewer", false) end },
    }
end

-- /aog model: on / off
function MV.Toggle()
    local on = not S().Get("modelViewer")
    S().Set("modelViewer", on)
    ns.Print(on and L().MODEL_SHOWN or L().MODEL_HIDDEN)
end
ns.Slash.Add("model", function() MV.Toggle() end, "HELP_MODEL")

-- ------------------------------------------------------------------ wiring
local SETTING_KEYS = { modelViewer = true, modelPos = true, modelScale = true, modelHideCombat = true, small = true,
    scale = true, followUIScale = true }

ns.Bus.On("Login", MV, function()
    local function Up() ns.Errors.Call("model", MV.Update) end
    ns.Bus.On("StepChanged", MV, Up, "model", 85)
    ns.Bus.On("WindowToggled", MV, Up, "model", 85)
    ns.Bus.On("WindowMoved", MV, Up, "model", 85)
    ns.Bus.On("WindowLayout", MV, Up, "model", 85)
    ns.Bus.On("ScaleChanged", MV, Up, "model", 85)
    ns.Bus.On("LookChanged", MV, Up, "model", 85)
    ns.Bus.On("CombatStarted", MV, Up, "model", 85)
    ns.Bus.On("CombatEnded", MV, Up, "model", 85)
    ns.Bus.On("ZoneChanged", MV, Up, "model", 85)
    -- the step button shows / hides (a left dock sits under it)
    ns.Bus.On("CombatQueueChanged", MV, Up, "model", 85)
    ns.Bus.On("SettingsChanged", MV, function(_, key)
        if key == "modelPos" and S().Get("modelPos") == "free" and MV.frame and MV.frame:IsShown() and not FreeSpot() then
            MV.SaveSpot()   -- free starts where it is
        end
        if SETTING_KEYS[key] then Up() end
    end, "model", 85)
    Up()
end, "model", 95)

-- In-game self-test: docked where it should be, theme keys, and how the current target loaded.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "model", fn = function(h)
    h.Count()
    for _, key in ipairs({ "color.modelBg", "color.modelEdge", "color.modelText", "size.modelW", "size.modelH",
        "size.modelGap", "size.modelInset" }) do
        if not Th.Has(key) then h.Problem("model: theme lacks " .. key) end
    end
    local f = MV.frame
    if not f then
        h.Info("model: not built (" .. tostring(MV.Why() or "not shown yet") .. ")")
        return
    end
    if f:IsShown() ~= (MV.Why() == nil) then h.Problem("model: shown " .. tostring(f:IsShown()) .. ", why " .. tostring(MV.Why())) end
    local bad = MV.Misplaced()
    if bad then h.Problem("model: " .. bad) end
    local t = MV.target
    local res = MV.result == "npc" and "npc ok" or MV.result == "display" and "display fallback"
        or MV.result == "none" and "none" or "loading"
    h.Info(("model: %s %s, %s (sd %s, side %s)"):format(t and (t.npc and "npc " .. t.npc or t.display and "display " .. t.display or "card") or "-",
        t and t.source or "", res, tostring(MV.sd), tostring(MV.side)))
end }

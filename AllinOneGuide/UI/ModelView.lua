-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The 3D viewer (v0.3): one PlayerModel frame `AllinOneGuideModel` that shows the NPC or mob the current step is
-- about. Setting modelPos: "now" (default, "Inside the window") = a square at the step block's top-left in the one
-- window, the step text right of it and the goal lines under it (UI\Window.lua + UI\Rows.lua `lean`; stays frozen in
-- combat). Or docked to the window: left / right / below, or free. Display only:
-- no targeting, no reading of other units, nothing secure (PlayerModel isn't protected, so it may move in combat).
--   * target, in order: a hunt-path target (SetTarget(npc, "hunt"), static pack data only, never a live
--     "nearest mob"), else the step's `model` (a display id), `targetNpc`, `npc`
--   * load: SetCreature(npc) first (by NPC id, the client's own model files); when no model file shows after
--     OnModelLoaded or CHECK_AFTER s, SetDisplayInfo(ns.ModelIds[npc]); then the fallback card (our own badge
--     art + "No 3D view"). Only when the target (or the SD / HD answer) changes.
--   * go-to steps (setting modelMurloc): a walking murloc (MV.MurlocChain: Azurky -> Murky), else the go-to picture
--   * hidden: setting off, safe mode, window hidden / suppressed, small mode, no target, in combat
--     (modelHideCombat; off = it stays but freezes: no reload until the fight ends)
--   * the frame is built the first time it shows (setting off = no frame); ClearModel after CLEAR_AFTER s hidden
--   * mouse: drag turns it (OnUpdate only while dragging), wheel zooms, double-click resets, right-click menu,
--     Shift+drag moves it in "free" position
--   ns.ModelView.Update(), .TargetFor(step), .SetTarget(npc, source), .Why(), .Place(), .Misplaced()
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local MV = {
    NAME = "AllinOneGuideModel", POSITIONS = { "now", "left", "right", "below", "free" },
    ZOOM_MAX = 0.8, ZOOM_STEP = 0.1, TURN = 0.02, CHECK_AFTER = 0.5, CLEAR_AFTER = 30, DOUBLE = 0.35,
    -- beta.13 (the user: "rotate the 3d model a little so you dont see it straight on ... more like 45"): every new
    -- model starts turned FACING radians (45 degrees) toward the window's text; positive = toward the screen's
    -- right (SetRotation / SetFacing turn counter-clockwise seen from above; 0 looks at the camera)
    FACING = math.pi / 4,
    -- go-to steps (the user, 2026-11-26: "for that walking steps can we use a murloc walking?", their pick "Try
    -- Azurky, else Murky"): a baby murloc walking on the spot instead of the go-to picture. Display only (tos
    -- 2026-11-26). Chain: Azurky (the Forever shop pet, creature AZURKY: its display id from the pet journal, else
    -- SetCreature) -> Murky (display MURKY, 1.12 data) -> the go-to picture. A murloc that doesn't load (no model
    -- file after OnModelLoaded / CHECK_AFTER) or has no Walk animation is skipped for the rest of the session.
    AZURKY = 275487, MURKY = 15369, WALK = 4,
    -- beta.14 zoom drift: the wheel moves the camera straight in (SetCamDistanceScale, 1 at zoom 0 down to CAM_NEAR
    -- at ZOOM_MAX); SetPortraitZoom stays 0 (see Zoomed)
    CAM_NEAR = 0.45,
    zoom = 0, loads = 0, token = 0, murlocBad = {},
}
ns.ModelView = MV
local TWO_PI = math.pi * 2
-- The start facing: toward the text, so turned to the left when the view is docked right of the window.
function MV.DefaultFacing()
    local pos = ns.Settings and ns.Settings.Get and ns.Settings.Get("modelPos")
    local a = pos == "right" and -MV.FACING or MV.FACING
    return a % TWO_PI
end
MV.facing = MV.FACING

local function S() return ns.Settings end
local function L() return ns.L end
local function PosInt(v) return type(v) == "number" and v > 0 and v == math.floor(v) and v or nil end

-- ------------------------------------------------------------------ what to show
-- { npc, display, key } or { picture = true, item | kind, key } or nil (no step).
-- beta.13 (the user: "why are we switching the 3d viewer off? ... it makes the look of the guide jump around", their
-- pick "Big step picture"): a step without a unit shows a big picture in the same frame instead of hiding it: the
-- step's own item (II.Ids: item, useItem, cond item=) or else its kind tile (accept, turn in, go to ...).
function MV.TargetFor(step)
    local h = MV.hunt
    if h then return { npc = h, display = ns.ModelIds and ns.ModelIds[h], key = "n" .. h, source = "hunt" } end
    if not step then return nil end
    local model = PosInt(step.model)
    if model then return { display = model, key = "d" .. model, source = "step" } end
    local npc = PosInt(step.targetNpc) or PosInt(step.npc)
    if npc then return { npc = npc, display = ns.ModelIds and ns.ModelIds[npc], key = "n" .. npc, source = "step" } end
    local II = ns.ItemIcons
    local item = II and II.Ids and II.Ids(step)[1]
    if item then return { picture = true, item = item, key = "i" .. item, source = "step" } end
    local kind = MV.KindOf(step)
    if kind == "goto" and S().Get("modelMurloc") then
        local chain = MV.MurlocChain()
        if chain[1] then return { murloc = true, chain = chain, i = 1, kind = kind, key = "w", source = "step" } end
    end
    return { picture = true, kind = kind, key = "k" .. kind, source = "step" }
end

-- The murlocs still worth trying this session, in order: Azurky by its journal display id, Azurky by creature id,
-- Murky by display id (entries in MV.murlocBad failed before). The journal is read once per session.
function MV.MurlocChain()
    if MV.azurkyDisplay == nil then MV.azurkyDisplay = Co.PetDisplay and Co.PetDisplay(MV.AZURKY) or false end
    local all = {}
    if MV.azurkyDisplay then
        all[#all + 1] = { name = "Azurky", display = MV.azurkyDisplay, key = "d" .. MV.azurkyDisplay }
    end
    all[#all + 1] = { name = "Azurky", creature = MV.AZURKY, key = "c" .. MV.AZURKY }
    all[#all + 1] = { name = "Murky", display = MV.MURKY, key = "d" .. MV.MURKY }
    local list = {}
    for _, e in ipairs(all) do
        if not MV.murlocBad[e.key] then list[#list + 1] = e end
    end
    return list
end

-- One line for the self-test: which murloc walks, which failed, or why none.
function MV.MurlocState()
    if not S().Get("modelMurloc") then return "off" end
    local failed = {}
    for key in pairs(MV.murlocBad) do failed[#failed + 1] = key end
    table.sort(failed)
    local bad = #failed > 0 and " (failed: " .. table.concat(failed, ", ") .. ")" or ""
    local t = MV.target
    if t and t.murloc and MV.result == "murloc" then
        local e = t.chain[t.i]
        return ("%s walking (%s)%s"):format(e.name, e.display and "display " .. e.display or "creature " .. e.creature, bad)
    end
    if t and t.murloc and t.picture then return "none loaded: go-to picture" .. bad end
    if t and t.murloc then return "loading " .. ((t.chain[t.i] or {}).name or "?") .. bad end
    if #failed > 0 and not MV.MurlocChain()[1] then return "none loaded: go-to picture" .. bad end
    return "not on a go-to step" .. bad
end

-- The step's tile kind as its row shows it (the verb at the start of its text, else its type).
function MV.KindOf(step)
    local UI, g = ns.UI, ns.Engine.Focused and ns.Engine.Focused()
    if UI and UI.Verb and g then
        local ok, _, kind = pcall(UI.Verb, step, g:Top():Text(step))
        if ok and type(kind) == "string" then return kind end
    end
    return K.TileKind(step)
end

-- The hunt path's contract (plans\model-viewer\plan.md section 8): its current segment's mob from its static
-- data; source "hunt" wins while set, nil clears it. Anything else is ignored.
function MV.SetTarget(npc, source)
    if source ~= "hunt" then return false end
    local step = ns.Engine.Current()
    local before = MV.InsideSlot(step)
    MV.hunt = PosInt(npc)
    -- inside the NOW window: only when the row must make (or give back) room, redraw the guide on the next
    -- frame (never from inside the caller: the hunt path calls this while the arrow is being aimed)
    if (before ~= nil) ~= (MV.InsideSlot(step) ~= nil) and ns.UI and ns.UI.frame then
        Co.After(0, function()
            ns.Errors.Call("ui", ns.UI.Refresh)
            ns.Errors.Call("model", MV.Update)
        end)
    end
    MV.Update()
    return true
end

-- Inside the window (position "now", the default): the square in the step block.
function MV.InsideMode()
    return S().Get("modelPos") == "now"
end

-- The square's size from the settings alone (the window keeps this room for it whether a step has a model or not),
-- or nil when the view isn't inside (off / another position / small mode / safe mode).
function MV.InsideSize()
    if not (S().Get("modelViewer") and MV.InsideMode()) or ns.safeMode or S().Get("small") then return nil end
    if not ns.Feature.IsOn("model") then return nil end
    local size = Th.Size("modelInside")
    if ns.UI and ns.UI.Width and ns.UI.Width() < 272 then size = Th.Size("modelInsideMin") end
    return math.floor(size * S().Get("modelScale") + 0.5)
end

-- The square's size (window units) when the step block shows the 3D view for this step, else nil.
-- Pure (UI\Window.lua Refresh asks it before laying out the row): the same rules as Why() below, so the room
-- is kept exactly when the viewer shows. A step with nothing to show (card targets) shows its tile and text from
-- the left; the card stands in only when a model fails to load.
function MV.InsideSlot(step)
    local size = MV.InsideSize()
    if not size or not step then return nil end
    -- (beta.13: every step has a model or a big picture: the room is always the view's)
    if not MV.TargetFor(step) then return nil end
    return size
end

-- Why it's hidden now, or nil when it shows.
-- Inside the NOW window it never hides for combat (the user's answer: "Stay, frozen"): the window's look
-- doesn't change in fights; it just doesn't load anything new until the fight ends.
function MV.Why()
    if not S().Get("modelViewer") then return "off" end
    if ns.safeMode then return "safe" end
    if not (ns.UI and ns.UI.IsShown and ns.UI.IsShown()) then return "window" end
    if ns.UI.suppressed then return "suppressed" end
    if S().Get("small") then return "small" end
    local inside = MV.InsideMode()
    if not inside and Co.InCombat() and S().Get("modelHideCombat") then return "combat" end
    -- (beta.13: no "none" for a step without a unit any more: it shows its big picture)
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
    -- (beta.12 bug: no SetKeepModelOnHide; warcraft.wiki.gg API_PlayerModel_SetKeepModelOnHide marks it
    -- AllowedWhenUntainted, so an addon can't rely on it: MV.Update loads again whenever the view is shown again)
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
    -- beta.13 the big step picture (a step without a unit): the item's icon or the step's kind tile, centred
    local pic = CreateFrame("Frame", nil, f)
    pic:SetAllPoints()
    pic.icon = pic:CreateTexture(nil, "ARTWORK", nil, 1)
    pic.icon:SetPoint("CENTER")
    pic.icon:SetTexCoord(MV.PIC_CROP, 1 - MV.PIC_CROP, MV.PIC_CROP, 1 - MV.PIC_CROP)   -- (again after every SetTexture)
    pic.tile = K.Tile(pic, 32)
    pic.tile.base:SetPoint("CENTER")
    pic:Hide()
    f.pic = pic
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

-- Inside the window: a rounded box (round.s at size.cornerButton) instead of the square fill + hairlines.
function MV.Round(on)
    local f = MV.frame
    if not f then return end
    if on and not f.round then
        f.round = K.Slice(f, "round", Th.Size("cornerButton"), "modelBg", { sub = -1 })
        f.roundEdge = K.Slice(f, "frame.border", Th.Size("cornerButton"), "modelEdge", { layer = "BORDER" })
        if not f.round then f.round = false end
    end
    local r = on and f.round and true or false
    K.SliceShown(f.round or nil, r)
    K.SliceShown(f.roundEdge or nil, r)
    f.bg:SetShown(not r)
    for _, e in ipairs(f.edges) do e:SetShown(not r) end
end

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

-- The item / target buttons sit in a row above the window (not beside it): a left dock takes no room for them.
local function ButtonRoom() return 0 end

-- Which side it docks to: the wanted one, or another one when that has no room on the screen.
-- below -> above -> left / right (whichever fits) when the screen is too short for both.
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
    if MV.InsideMode() and w then
        -- inside the window: a square at the step block's top-left, the step text right of it (Refresh keeps the room)
        if f:GetParent() ~= w then f:SetParent(w) end
        local size = MV.InsideSize() or math.floor(Th.Size("modelInside") * S().Get("modelScale") + 0.5)
        f:SetScale(1)
        f:SetSize(size, size)
        f:ClearAllPoints()
        local x, y = ns.UI.SlotSpot()
        f:SetPoint("TOPLEFT", w, "TOPLEFT", x, -y)
        f:SetFrameLevel((w:GetFrameLevel() or 0) + 3)
        MV.side = "now"
        MV.Round(true)
        return
    end
    MV.Round(false)
    if p and f:GetParent() ~= p then f:SetParent(p) f:SetFrameStrata("MEDIUM") end
    local s = Scale()
    f:SetScale(s)
    f:SetSize(Th.Size("modelW"), Th.Size("modelH"))
    f:ClearAllPoints()
    local want = S().Get("modelPos")
    if want == "now" then want = "left" end   -- (inside not possible, e.g. small mode: the left dock)
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
    elseif side == "right" or side == "left" then
        -- level with the window's top
        if side == "right" then
            f:SetPoint("TOPLEFT", w, "TOPRIGHT", gap, 0)
        else
            f:SetPoint("TOPRIGHT", w, "TOPLEFT", -gap, -ButtonRoom() / ms)
        end
    elseif side == "below" then
        f:SetPoint("TOPLEFT", w, "BOTTOMLEFT", 0, -gap)
    elseif side == "above" then
        f:SetPoint("BOTTOMLEFT", w, "TOPLEFT", 0, gap)
    else
        f:SetPoint("TOPRIGHT", w, "TOPLEFT", -gap, -ButtonRoom() / ms)
    end
end

-- Inside the window: at the step block's top-left under the title bar, the square's size, beside (never under)
-- the step text, and the row shows no number / icon. nil when right.
function MV.InsideProblem()
    local f = MV.frame
    local n = ns.UI and ns.UI.frame
    if not (n and n:IsShown()) then return "the window is hidden" end
    if f:GetParent() ~= n then return "not in the window" end
    local k = n:GetEffectiveScale()
    local function R(o)
        local l, r, b, t = o:GetLeft(), o:GetRight(), o:GetBottom(), o:GetTop()
        if not (l and r and b and t) then return nil end
        local e = o:GetEffectiveScale() / k   -- in the window's units
        return l * e, r * e, b * e, t * e
    end
    local fl, fr, fb, ft = R(f)
    local nl, nr, nb, nt = R(n)
    if not (fl and nl) then return nil end
    local want = ns.UI.slot
    if want and (math.abs((fr - fl) - want) > 0.5 or math.abs((ft - fb) - want) > 0.5) then
        return ("size %.0fx%.0f, wanted %d"):format(fr - fl, ft - fb, want)
    end
    local x, y = ns.UI.SlotSpot()
    if math.abs(fl - (nl + x)) > 0.5 or math.abs(ft - (nt - y)) > 0.5 then return "not at the window's left, under its title" end
    if fb < nb - 0.5 or fr > nr + 0.5 then return "sticks out of the window" end
    local row = ns.UI.rows and ns.UI.rows[1]
    if row and row:IsShown() and row:GetParent() == ns.UI.area and ns.UI.slot then
        if not row.lean then return "the step row still has its number / icon" end
        if row.num:IsShown() or row.badge.disc:IsShown() then return "the step number / icon still show" end
        local ln = row.lines and row.lines[1]
        local gt = ln and ln.text:IsShown() and ln.text:GetTop()
        if gt and gt * (row:GetEffectiveScale() / k) > fb + 0.5 then return "a goal line runs beside the 3D view" end
        local tl = R(row.text)
        if tl and tl < fr - 0.5 then return "the step text runs under the 3D view" end
    end
    return nil
end

-- nil when it sits where it should (or can't be judged now), else a short reason. Self-test + offline tests.
function MV.Misplaced()
    local f, w, p = MV.frame, ns.UI and ns.UI.frame, Co.UIParent()
    if not (f and w and p and f:IsShown() and w:IsShown()) or MV.side == "free" or MV.moving then return nil end
    if MV.side == "now" then return MV.InsideProblem() end
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
    -- never on the guide window, also when the screen edge clamps it (beta.5)
    if fl < wr - 0.5 and fr > wl + 0.5 and fb < wt - 0.5 and ft > wb + 0.5 then return "covers the guide window" end
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
        if math.abs((fb - wt) - gap) > 1 then return ("gap above %.1f, wanted %.1f"):format(fb - wt, gap) end
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
    f.pic:Hide()
    if on then
        local step = ns.Engine.Current()
        K.SetBadge(f.card.badge, step and K.BadgeKind(step) or "manual")
        f.card.text:SetText(L().MODEL_NONE)
    end
end

-- beta.13 the big step picture: PIC_SHARE of the frame's smaller side, centred; the item's icon (II.Icon: the
-- theme's unknown-item file until the game has it, then it is drawn again) or the kind tile. Never with the model.
MV.PIC_SHARE = 0.65
-- beta.13 bug (the user: "the new book in the 3d viwer have some white sports in the cornors"): a 1.x item icon's
-- bevelled border has light, rounded corners that reach further in than the 7 % crop, and at the big picture's
-- size the filtering pulls them in; the crop was also only set once at Build, never after SetTexture. Now 10 %,
-- set again after every SetTexture (as the step button does).
MV.PIC_CROP = 0.1
function MV.DrawPicture()
    local f, t = MV.frame, MV.target
    if not (f and t and t.picture) then return end
    f.card:Hide()
    f.model:Hide()
    f.pic:Show()
    local w, h = f:GetWidth() or 0, f:GetHeight() or 0
    local size = math.max(16, math.floor(math.min(w, h) * MV.PIC_SHARE + 0.5))
    local pic = f.pic
    if t.item then
        local II = ns.ItemIcons
        pic.icon:SetTexture(II and II.Icon(t.item) or Th.File("itemUnknown"))
        pic.icon:SetTexCoord(MV.PIC_CROP, 1 - MV.PIC_CROP, MV.PIC_CROP, 1 - MV.PIC_CROP)
        pic.icon:SetSize(size, size)
        pic.icon:Show()
        K.TileShown(pic.tile, false)
    else
        pic.icon:Hide()
        pic.tile.base:SetSize(size, size)
        K.SetTile(pic.tile, t.kind)
        K.TileShown(pic.tile, true)
    end
    MV.picSize = size
end

-- Turns the model to MV.facing. beta.13 bug (the user: "after we have rotated the 3d model. when i now zoom in the
-- model moves other to the rigth side and are not centered anymore"): SetFacing (SimpleModel) turns the model in
-- world space round its root, while SetPortraitZoom aims the camera at the model's portrait point as it was before
-- the turn, so with any turn (the 45-degree start, a drag) zooming in slid the model sideways. SetRotation
-- (CharacterModelBase, FrameAPICharacterModelBaseDocumentation:229) turns it under the portrait camera, and is what
-- Blizzard pairs with SetPortraitZoom (Blizzard_SharedXML\Mainline\ModelFrames.lua:19/48/60). SetFacing only when a
-- client has no SetRotation. MV.turnBy says which one was used (the self-check reads GetFacing only for SetFacing).
local function Turn(m)
    if m.SetRotation then
        m:SetRotation(MV.facing, false)
        MV.turnBy = "rotation"
    elseif m.SetFacing then
        m:SetFacing(MV.facing)
        MV.turnBy = "facing"
    end
end
MV.Turn = Turn

-- The camera distance for a zoom level: 1 (whole model) at 0, CAM_NEAR at ZOOM_MAX.
function MV.CamScale(zoom)
    local z = ns.U.Clamp(zoom or 0, 0, MV.ZOOM_MAX)
    return 1 - (1 - MV.CAM_NEAR) * z / MV.ZOOM_MAX
end

-- Zooms the model. beta.14 bug (the user: "the 3d model still moves over to the rigth on zoom!"): the beta.14 fix
-- (SetRotation instead of SetFacing) wasn't the cause. SetPortraitZoom doesn't move the camera straight in: it
-- slides the camera from the whole-model view toward the model's portrait (head) point, and on a turned model that
-- point sits off to one side (a head ahead of the root, like a kobold's, turned 45 degrees), so the more you zoom
-- the further the view slides sideways, whichever way the model was turned. SetCamDistanceScale
-- (FrameAPICharacterModelBaseDocumentation.lua:143, Forever 1.60.1) moves the camera along its own line of sight,
-- so the point it looks at (the model's middle, centred at zoom 0) stays in the middle at every zoom and facing.
-- SetPortraitZoom is held at 0. A client without SetCamDistanceScale doesn't zoom (better than sliding off).
-- MV.zoomBy says which was used (self-check).
local function Zoomed(m)
    if m.SetCamDistanceScale then
        if m.SetPortraitZoom then m:SetPortraitZoom(0) end
        m:SetCamDistanceScale(MV.CamScale(MV.zoom))
        MV.zoomBy = "distance"
    else
        MV.zoomBy = "none"
    end
end
MV.Zoomed = Zoomed

local function ApplyView()
    local m = MV.frame.model
    Turn(m)
    Zoomed(m)
    -- the murloc walks on the spot; set again after every load / update (an animation set before the model file
    -- is in is lost: Blizzard sets theirs in OnModelLoaded, Blizzard_ArtifactPerks.lua:153)
    if MV.stage == "murloc" and m.SetAnimation then m:SetAnimation(MV.WALK) end
end

-- stage: "npc" (SetCreature), "display" (SetDisplayInfo), "murloc" (the go-to murloc, chain entry t.i),
-- "card" (nothing to show), "picture"
local function Try(stage)
    local f, t = MV.frame, MV.target
    local m = f.model
    MV.token = MV.token + 1
    MV.stage = stage
    if stage == "picture" then
        if m.ClearModel then m:ClearModel() end
        MV.DrawPicture()
        return
    end
    if stage == "npc" then
        ShowCard(false)
        m:SetCreature(t.npc)
    elseif stage == "display" then
        ShowCard(false)
        m:SetDisplayInfo(t.display)
    elseif stage == "murloc" then
        ShowCard(false)
        local e = t.chain[t.i]
        if e.display then m:SetDisplayInfo(e.display) else m:SetCreature(e.creature) end
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
    if stage == "murloc" then
        -- this murloc failed: skip it for the session; the next one, else the go-to picture (never the card)
        local e = t.chain[t.i]
        if e then MV.murlocBad[e.key] = true end
        t.i = t.i + 1
        if t.chain[t.i] then return "murloc" end
        -- the go-to picture under its own key (= what TargetFor gives from now on: no reload, same as a /reload)
        t.picture, t.key = true, "k" .. t.kind
        MV.loadedKey = t.key .. "|" .. tostring(MV.sd)
        return "picture"
    end
    if stage == "npc" and t.display then return "display" end
    return "card"
end

-- A loaded murloc without a Walk animation counts as failed (only asked after OnModelLoaded: before that the
-- model's animation data may not be in yet).
local function NoWalk(why)
    local m = MV.frame.model
    if MV.stage ~= "murloc" or why ~= "loaded" or not m.HasAnimation then return false end
    local ok, has = pcall(m.HasAnimation, m, MV.WALK)
    return ok and has == false
end

-- Did the model load? why = "loaded" (OnModelLoaded) or "timer". A late model brings the view back.
function MV.Check(why)
    local f = MV.frame
    if not (f and MV.target) or MV.stage == nil or MV.stage == "picture" or MV.target.picture then return end
    -- a hidden view drops its model (beta.12): no verdict on a murloc then (it would be skipped for the session);
    -- showing again loads it again
    if MV.stage == "murloc" and not f:IsShown() then return end
    -- no way to ask: trust what was asked for (never step down on a guess)
    if not f.model.GetModelFileID then
        if MV.stage ~= "card" then MV.result = MV.stage end
        return
    end
    local id = f.model:GetModelFileID()
    if type(id) == "number" and id > 0 and not NoWalk(why) then
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
        if nxt == "picture" then MV.result = "picture" end
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
    -- beta.13: every new model starts at the 45-degree default (a drag turn lasts until the next model)
    MV.facing, MV.turned = MV.DefaultFacing(), nil
    if t.picture then
        Try("picture")
        MV.result = "picture"
    elseif t.card then
        Try("card")
        MV.result = "none"
    elseif t.murloc then
        Try("murloc")
    elseif t.npc then
        Try("npc")
    else
        Try("display")
    end
    return true
end

-- ------------------------------------------------------------------ show / hide
function MV.Update()
    -- (for MV.StepUp: which window refresh and which step this update saw)
    MV.doneAt, MV.doneFor = ns.UI and ns.UI.refreshes, (ns.Engine.Current())
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
    -- beta.12 bug (the user: "go forward some steps and then back to step 10 ... the 3d viewer window is gone"): the
    -- client drops a PlayerModel's model while it is hidden, so the same target shown again after a hide was an
    -- empty box (its key hadn't changed: no reload). Shown again = load again, and only once it is shown.
    local wasHidden = not f:IsShown()
    if wasHidden then
        MV.hideSeq = (MV.hideSeq or 0) + 1
        MV.loadedKey = nil
        MV.reshows = (MV.reshows or 0) + 1
    end
    MV.Place()
    if wasHidden and not Co.InCombat() then f:Show() end
    -- in combat with modelHideCombat off: it stays as it is (no reload until the fight ends); with nothing
    -- loaded (first show or after the unload) the card stands in until then (beta.5 fix: an empty box)
    MV.waiting = nil
    if not Co.InCombat() then
        Load(MV.TargetFor(ns.Engine.Current()))
        -- beta.13: some clients reset the facing when a model (re)loads: set it again on every update (step
        -- change, window shown); the default follows the dock side until the player turns the model
        if not MV.turned then MV.facing = MV.DefaultFacing() end
        if MV.stage == "picture" then
            MV.DrawPicture()   -- (again on every update: the item's icon may have come in, the size changed)
        elseif MV.stage and MV.stage ~= "card" then
            ApplyView()
        end
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
    if x ~= d.x0 then MV.turned = true end
    Turn(self.model)
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
    if f then Zoomed(f.model) end
end

function MV.ResetView()
    MV.facing, MV.zoom, MV.turned = MV.DefaultFacing(), 0, nil   -- (beta.13: back to the 45-degree start)
    if MV.frame then ApplyView() end
end

function MV.Tip(owner)
    local step = ns.Engine.Current()
    local g = ns.Engine.Focused()
    local title = (step and g and g:Top():Text(step)) or L().MODEL_TITLE
    local lines = {}
    if MV.stage ~= "card" and MV.stage ~= "picture" then
        lines[#lines + 1] = L().MODEL_TIP_DRAG
        lines[#lines + 1] = L().MODEL_TIP_WHEEL
        lines[#lines + 1] = L().MODEL_TIP_RESET
    end
    if S().Get("modelPos") == "free" then lines[#lines + 1] = L().MODEL_TIP_MOVE end
    lines[#lines + 1] = L().MODEL_TIP_RIGHT
    K.Tooltip(owner, title, lines)
end

local POS_LABEL = { now = "CHOICE_MODEL_NOW", left = "CHOICE_MODEL_LEFT", right = "CHOICE_MODEL_RIGHT", below = "CHOICE_MODEL_BELOW", free = "CHOICE_MODEL_FREE" }
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
local SETTING_KEYS = { modelViewer = true, modelPos = true, modelScale = true, modelHideCombat = true, modelMurloc = true, small = true,
    scale = true, followUIScale = true, width = true }

-- StepChanged: the window's refresh (order 70) has usually just updated the 3D view for this step already; update
-- again only when it didn't (window hidden, not refreshed, or another step) (perf: one update per step change)
function MV.StepUp()
    local UI = ns.UI
    if MV.doneAt ~= nil and UI and MV.doneAt == UI.refreshes and MV.doneFor ~= nil
        and MV.doneFor == (ns.Engine.Current()) and UI.IsShown() then
        MV.stepSkips = (MV.stepSkips or 0) + 1
        return
    end
    MV.Update()
end

ns.Bus.On("Login", MV, function()
    local function Up() ns.Errors.Call("model", MV.Update) end
    ns.Bus.On("StepChanged", MV, function() ns.Errors.Call("model", MV.StepUp) end, "model", 85)
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
        -- inside the NOW window the step row makes or gives back the room: redraw the guide first
        if (key == "modelViewer" or key == "modelPos" or key == "modelScale") and ns.UI.frame then
            ns.Errors.Call("ui", ns.UI.Refresh)
        end
        if SETTING_KEYS[key] then Up() end
    end, "model", 85)
    Up()
end, "model", 95)

-- In-game self-test: docked where it should be, theme keys, and how the current target loaded.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "model", fn = function(h)
    h.Count()
    for _, key in ipairs({ "color.modelBg", "color.modelEdge", "color.modelText", "size.modelW", "size.modelH",
        "size.modelGap", "size.modelInset", "size.modelInside" }) do
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
        or MV.result == "none" and "none" or MV.result == "picture" and "picture"
        or MV.result == "murloc" and "murloc walking" or "loading"
    -- beta.13: the model and the big picture never show together; a picture target shows the picture
    if f:IsShown() and f.pic then
        if f.pic:IsShown() and f.model:IsShown() then h.Problem("model: the model and the picture both show") end
        if t and t.picture and not f.pic:IsShown() then h.Problem("model: a step without a unit but no picture") end
        if t and not t.picture and f.pic:IsShown() then h.Problem("model: a picture on a step with a unit") end
    end
    -- the go-to murloc: which one walks (Azurky / Murky) or why none; a walking one has its Walk animation
    h.Info("model murloc: " .. MV.MurlocState())
    if t and t.murloc and not t.picture and MV.result == "murloc" and f.model.HasAnimation then
        local ok, has = pcall(f.model.HasAnimation, f.model, MV.WALK)
        if ok and has == false then h.Problem("model: the murloc has no walk animation") end
    end
    -- the big picture's item icon is cropped (beta.13 white corners)
    if f.pic and f.pic.icon.GetTexCoord then
        local l = f.pic.icon:GetTexCoord()
        if type(l) == "number" and math.abs(l - MV.PIC_CROP) > 0.001 then h.Problem("model: the picture's icon isn't cropped") end
    end
    h.Info(("model: %s %s, %s (sd %s, side %s, facing %d deg%s)"):format(t and (t.murloc and not t.picture and "murloc "
        .. ((t.chain[t.i] or {}).name or "?") or t.npc and "npc " .. t.npc or t.display and "display " .. t.display
        or t.item and "picture item " .. t.item or t.kind and "picture " .. t.kind or "card") or "-",
        t and t.source or "", res, tostring(MV.sd), tostring(MV.side), math.floor(math.deg(MV.facing or 0) + 0.5),
        MV.turned and ", turned by you" or ""))
    -- beta.13: an untouched model faces the 45-degree start (the model's own answer when the client has GetFacing)
    if not MV.turned and math.abs((MV.facing or 0) - MV.DefaultFacing()) > 0.01 then
        h.Problem(("model: facing %.2f, not the start %.2f"):format(MV.facing or 0, MV.DefaultFacing()))
    end
    local m = f.model
    if MV.turnBy then h.Info("model turn: " .. (MV.turnBy == "rotation" and "SetRotation" or "SetFacing (no SetRotation)")) end
    if MV.zoomBy then
        h.Info(("model zoom: %s (zoom %.1f, camera %.2f)"):format(MV.zoomBy == "distance" and "SetCamDistanceScale"
            or "off (no SetCamDistanceScale)", MV.zoom or 0, MV.CamScale(MV.zoom)))
    end
    if MV.turnBy == "facing" and not MV.turned and f:IsShown() and MV.stage ~= "card" and MV.stage ~= "picture" and m.GetFacing then
        local got = m:GetFacing()
        if type(got) == "number" and math.abs(MV.Wrap(got) - MV.DefaultFacing()) > 0.05 then
            h.Problem(("model: the model faces %.2f, not %.2f (the client reset it)"):format(got, MV.DefaultFacing()))
        end
    end
end }

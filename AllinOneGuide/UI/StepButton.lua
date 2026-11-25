-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The step button (v0.2 M2): one secure item button for the current step's quest item (or the hearthstone on
-- a hearth step). The player presses it; the addon never uses an item itself.
--   * SecureActionButtonTemplate with type = "item" only (tos plan: never a macro, /target or /cast)
--   * only items named in the step data (`useItem`, a `useitem` step's `item`, 6948 on `hearth` steps)
--   * every secure change (item, show, hide, position) goes through the combat queue: never in combat
--   * parented to UIParent and placed next to the guide window out of combat (not anchored to the window, so
--     moving the window in combat never moves a secure frame)
--   * look only (any time, also in combat): icon, count, cooldown swirl, dim when not in the bags, red edge +
--     "not in your bags" tooltip line, an hourglass while a change waits, the reminder glow
--   named AllinOneGuideStepButton so a key binding can click it (M4: Bindings.xml)
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local CQ = ns.CombatQueue
-- CROP: item icons show only their inner 84 % (Blizzard's baked edge sits under our frame; look review #9)
local SB = { NAME = "AllinOneGuideStepButton", SIZE = 36, HEARTHSTONE = 6948, item = nil, want = nil, CROP = 0.08 }
ns.StepButton = SB

-- The item the current step wants on the button, or nil.
function SB.ItemFor(step)
    if not step then return nil end
    if step.type == "hearth" then return SB.HEARTHSTONE end
    if type(step.useItem) == "number" then return step.useItem end
    if step.type == "useitem" and type(step.item) == "number" then return step.item end
    return nil
end

local function Build()
    local CreateFrame = _G.CreateFrame
    local b = CreateFrame("Button", SB.NAME, Co.fn.UIParent, "SecureActionButtonTemplate")
    b:SetSize(SB.SIZE, SB.SIZE)
    b:SetClampedToScreen(true)   -- never off screen when the window sits at the left edge
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    b:Hide()
    local bg = K.Fill(b, "BACKGROUND", "panel")
    bg:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(SB.CROP, 1 - SB.CROP, SB.CROP, 1 - SB.CROP)
    -- the button frame (art: frame.stepbutton, 52x52 centred; normal / reminder / missing tint)
    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetSize(52, 52)
    b.border:SetPoint("CENTER")
    Th.Glyph(b.border, "frame.stepbutton")
    b.border:SetVertexColor(Th.Color("stepFrame"))
    b.edge = { b.border }
    -- outlined (font.buttonText): readable on busy item icons
    b.count = K.Text(b, "buttonText", "white", "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.key = K.Text(b, "buttonText", "counter", "LEFT")
    b.key:SetPoint("TOPLEFT", 3, -3)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    -- reminder glow (look only)
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.glow:SetSize(72, 72)
    b.glow:SetPoint("CENTER")
    Th.Glyph(b.glow, "frame.glow")
    b.glow:SetVertexColor(Th.Color("accent"))
    if b.glow.SetBlendMode then b.glow:SetBlendMode("ADD") end
    b.glow:Hide()
    -- the glow pulses (look review #9, variant A): alpha alpha.pulseLow -> 1 -> back, one loop per
    -- motion.pulse; still with reduced motion. Look only (an animation on a texture, never a secure change).
    if b.glow.CreateAnimationGroup then
        b.pulse = b.glow:CreateAnimationGroup()
        b.pulse:SetLooping("BOUNCE")
        b.pulseAlpha = b.pulse:CreateAnimation("Alpha")
        b.pulseAlpha:SetToAlpha(1)
    end
    -- a change waits for the end of combat (hourglass on the top-right corner)
    b.wait = b:CreateTexture(nil, "OVERLAY")
    b.wait:SetSize(16, 16)
    b.wait:SetPoint("CENTER", b, "TOPRIGHT", -2, -2)
    Th.Glyph(b.wait, "state.wait")
    b.wait:SetVertexColor(Th.Color("wait"))
    b.wait:Hide()
    b:SetScript("OnEnter", function(self) ns.Errors.Call("stepbutton", SB.Tooltip, self) end)
    b:SetScript("OnLeave", function() K.HideTooltip() end)
    SB.frame = b
    return b
end

-- Look-only refresh (safe in combat).
function SB.Look()
    local b = SB.frame
    if not b then return end
    -- while a secure change waits (combat), show what a click really uses: the item still on the button
    local pending = CQ.Pending("stepbutton")
    local id = SB.item
    if not pending then id = SB.want or SB.item end
    b.wait:SetShown(pending)
    SB.Pulse(b.glow:IsShown())
    if not id then return end
    b.icon:SetTexture(Co.ItemIcon(id) or Th.File("itemUnknown"))
    b.icon:SetTexCoord(SB.CROP, 1 - SB.CROP, SB.CROP, 1 - SB.CROP)
    local n = Co.ItemCount(id)
    b.count:SetText(n > 1 and tostring(n) or "")
    local missing = n == 0
    b.missing = missing
    b.icon:SetDesaturated(missing)
    local edge = (missing and "stepFrameMissing") or (b.glow:IsShown() and "accent") or "stepFrame"
    b.border:SetVertexColor(Th.Color(edge))
    local s, d = Co.ItemCooldown(id)
    if b.cd.SetCooldown then b.cd:SetCooldown(s, d) end
    local key = Co.BindingKey("CLICK " .. SB.NAME .. ":LeftButton")
    b.key:SetText(key or "")
end

-- The glow's pulse (look only, safe in combat): plays while the glow is up and motion is on; otherwise
-- stopped with the glow at full alpha. SB.pulsing = the state (for the self-test and the offline tests).
function SB.Pulse(on)
    local b = SB.frame
    if not (b and b.pulse) then return false end
    local d = Th.Motion("pulse")
    local want = (on and d > 0) and true or false
    if want and SB.pulsing ~= d then
        b.pulse:Stop()
        b.pulseAlpha:SetFromAlpha(Th.Alpha("pulseLow", 0.4))
        b.pulseAlpha:SetDuration(d / 2)   -- BOUNCE: up in half the loop, down in the other half
        b.pulse:Play()
        SB.pulsing = d
    elseif not want and SB.pulsing then
        b.pulse:Stop()
        SB.pulsing = nil
    end
    if not want then b.glow:SetAlpha(1) end
    return want
end

function SB.Tooltip(owner)
    local id = SB.item
    local tip = Co.Tooltip()
    if not tip or not id then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    if tip.SetItemByID then tip:SetItemByID(id) else tip:SetText(Co.ItemName(id) or "", 1, 1, 1) end
    local L = ns.L
    if Co.ItemCount(id) == 0 then tip:AddLine(L.BUTTON_MISSING, Th.Color("notice.danger")) end
    local s, d = Co.ItemCooldown(id)
    if d > 1.5 then
        local left = math.max(0, s + d - Co.Now())
        tip:AddLine(ns.U.Fill(L.BUTTON_COOLDOWN, { n = math.ceil(left / 60) }), Th.Color("counter"))
    end
    tip:AddLine(L.BUTTON_HINT, Th.Color("counter"))
    tip:Show()
end

-- Places the button left of the window's top edge, at the window's own scale (look review #1). The window's
-- GetLeft / GetTop are in its own scaled units: k turns them into UIParent units, and the button's offsets
-- are in its own units (UIParent units / its scale). Secure: only from Apply (combat queue).
local function Place(b)
    local p = Co.fn.UIParent
    local s = ns.Overlay.WindowScale()
    if type(s) ~= "number" or s <= 0 then s = 1 end
    b:SetScale(s)
    b:ClearAllPoints()
    local w = ns.UI and ns.UI.frame
    local x, y = w and w:GetLeft(), w and w:GetTop()
    local ps = p and p.GetEffectiveScale and p:GetEffectiveScale()
    if x and y and ps and ps > 0 then
        local k = w:GetEffectiveScale() / ps
        b:SetPoint("TOPRIGHT", p, "BOTTOMLEFT", x * k / s - Th.Size("stepButtonGap"), y * k / s)
    else
        b:SetPoint("CENTER", p, "CENTER", -200 / s, 0)
    end
    SB.placed = { x = x, y = y, scale = s }
end
SB.Place = Place

-- Secure part: item attribute, place, shown. Only ever called through the combat queue.
local function Apply(id)
    local b = SB.frame or Build()
    SB.item = id
    if id then
        b:SetAttribute("item", "item:" .. id)
        Place(b)
        b:Show()
    else
        b:SetAttribute("item", nil)
        b:Hide()
    end
    SB.Look()
end

-- Follows the current step (out of combat at once, else after combat; the last wish wins).
-- replace = true (window moved, scaled or laid out again): always queue a re-place, even when the item is
-- the same (the early return used to leave the button behind when the window was dragged).
function SB.Update(replace)
    local step = ns.Engine.Current()
    local id = SB.ItemFor(step)
    if not (ns.UI and ns.UI.IsShown and ns.UI.IsShown()) then id = nil end
    SB.want = id
    if replace and id and SB.frame then
        CQ.Run("stepbutton", Apply, id)
        SB.Look()
        return
    end
    if id == SB.item and (not id or (SB.frame and SB.frame:IsShown())) then
        SB.Look()
        return
    end
    CQ.Run("stepbutton", Apply, id)
    SB.Look()
end

-- In-game self-test (/aog selftest): the button only ever holds type = item, and matches the step out of combat.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "stepbutton", fn = function(h)
    h.Count()
    local b = SB.frame
    if not b then
        h.Info("stepbutton: not built (no step with an item yet)")
        return
    end
    local t = b:GetAttribute("type")
    if t ~= "item" then h.Problem("stepbutton: type is " .. tostring(t)) end
    if not Co.InCombat() and not CQ.Pending("stepbutton") and SB.want ~= SB.item then
        h.Problem("stepbutton: shows another item than the step")
    end
    -- while a change waits, the icon is the item a click uses now (post-check fix)
    if CQ.Pending("stepbutton") and SB.item and b.icon.GetTexture then
        local want = Co.ItemIcon(SB.item)
        if want and b.icon:GetTexture() ~= want then h.Problem("stepbutton: the icon isn't the item on the button") end
    end
    -- look review #1: next to the window's top-left at the window's scale (unless the screen edge clamps it)
    local bad = SB.Misplaced()
    if bad then h.Problem("stepbutton: " .. bad) end
    -- look review #9: the icon is cropped; the glow pulses exactly while it is up (motion on)
    if b.icon.GetTexCoord then
        local l = b.icon:GetTexCoord()
        if type(l) == "number" and math.abs(l - SB.CROP) > 0.001 then h.Problem("stepbutton: the icon isn't cropped") end
    end
    if b.pulse and ((SB.pulsing ~= nil) ~= (b.glow:IsShown() and Th.Motion("pulse") > 0)) then
        h.Problem("stepbutton: the glow pulse doesn't match the glow")
    end
end }

-- nil when the button sits where it should (or can't be judged now), else a short reason.
function SB.Misplaced()
    local b, w = SB.frame, ns.UI and ns.UI.frame
    if not (b and w and b:IsShown() and w:IsShown()) or Co.InCombat() or CQ.Pending("stepbutton") then return nil end
    local p = Co.fn.UIParent
    local ps = p and p:GetEffectiveScale()
    local bl, br, bt = b:GetLeft(), b:GetRight(), b:GetTop()
    local wl, wt = w:GetLeft(), w:GetTop()
    if not (ps and bl and br and bt and wl and wt) then return nil end
    local kb, kw = b:GetEffectiveScale() / ps, w:GetEffectiveScale() / ps
    if math.abs(kb - kw) > 0.01 then return ("scale %.2f, the window %.2f"):format(kb, kw) end
    local gap = Th.Size("stepButtonGap") * kb
    local room = wl * kw - gap - (br - bl) * kb
    if room < 0 then return nil end   -- clamped at the screen's left edge
    if math.abs(bt * kb - wt * kw) > 1 then return "not level with the window's top" end
    if math.abs((wl * kw - br * kb) - gap) > 1 then return ("gap %.1f, wanted %.1f"):format(wl * kw - br * kb, gap) end
    return nil
end

ns.Bus.On("Login", SB, function()
    if not ns.Feature.IsOn("stepbutton") then return end
    local function Up() SB.Update() end
    ns.Bus.On("StepChanged", SB, Up, "stepbutton")
    ns.Bus.On("WindowToggled", SB, Up, "stepbutton")
    local function Replace() SB.Update(true) end
    ns.Bus.On("WindowMoved", SB, Replace, "stepbutton")
    ns.Bus.On("WindowLayout", SB, Replace, "stepbutton")              -- height / width / scale (UI.Layout)
    ns.Bus.On("ScaleChanged", SB, Replace, "stepbutton", 80)          -- after the window's KeepOnScreen (70)
    ns.Bus.On("ItemsChanged", SB, function() SB.Look() end, "stepbutton")
    ns.Bus.On("CombatQueueChanged", SB, function() SB.Look() end, "stepbutton")
    -- reduced motion on / off: the glow pulse stops / starts at once
    ns.Bus.On("SettingsChanged", SB, function(_, key) if key == "reducedMotion" then SB.Look() end end, "stepbutton")
    SB.Update()
end, "stepbutton", 90)

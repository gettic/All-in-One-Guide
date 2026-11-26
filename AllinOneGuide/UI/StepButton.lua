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
-- Use-item button (plans\use-item-button\plan.md, tos ok 2026-11-26): it also offers items that start a quest
-- (an accept step `from = "item"`, an objective step whose `item` starts a quest, or such a goal riding along),
-- only while the item is in the bags, with a yellow "!" badge. A click does what a right-click in the bag does
-- (the game opens the quest window; the player accepts). Starters are known from ns.BagQuests' out-of-combat bag
-- scan (C_Container.GetContainerItemQuestInfo, plain bag / slot numbers) or ns.QuestItems + the route's accept row;
-- never read in combat here. Setting `itemButton` (off = hidden); hidden in small mode like the target button.
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local CQ = ns.CombatQueue
-- CROP: item icons show only their inner 84 % (Blizzard's baked edge sits under our frame; look review #9)
-- LEVEL_GAP: the item / target buttons sit this many frame levels above the guide window (same strata), so no
--   part of the window (grips +20/+21, the 3D view +3) can ever take their clicks
-- CLICKS: both up and down (beta.11 fix, the user: "i now see the new iteam buttom. but cant click it?"). An addon's
--   SecureActionButtonTemplate acts on the DOWN click when the CVar ActionButtonUseKeyDown is on (the default):
--   SecureActionButton_OnClick gets no isSecureAction from an addon button, so useOnKeyDown = the CVar and
--   clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown) (checked in the 16001 UI source,
--   Blizzard_FrameXML\SecureTemplates.lua + .xml). Registered for "AnyUp" only, the down never reached it: nothing.
--   With both, exactly one of the two acts, whichever way the CVar is set.
-- BADGE: the built-in game quest "!" (referenced by path, never copied); our own glyph when it can't be set
local SB = { NAME = "AllinOneGuideStepButton", SIZE = 36, HEARTHSTONE = 6948, item = nil, want = nil, CROP = 0.08,
    LEVEL_GAP = 30, BADGE = "Interface\\GossipFrame\\AvailableQuestIcon", BADGE_FALLBACK = "glyph.step.accept",
    starts = {}, FARM_ALPHA = 0.45, CLICKS = { "AnyUp", "AnyDown" } }
ns.StepButton = SB

-- Click setup of a secure button (item and target button; at build, out of combat): both clicks, mouse on.
-- b.aogClicks = what was registered (the game has no getter; for the self-test and the offline tests).
function SB.Clicks(b)
    b:RegisterForClicks(unpack(SB.CLICKS))
    b.aogClicks = SB.CLICKS
    b:EnableMouse(true)
end

-- Same strata as the guide window, LEVEL_GAP levels above it (secure: only from Apply, out of combat).
function SB.Raise(b)
    local w = ns.UI and ns.UI.frame
    if not (b and w) then return end
    b:SetFrameStrata(w:GetFrameStrata() or "MEDIUM")
    b:SetFrameLevel((w:GetFrameLevel() or 0) + SB.LEVEL_GAP)
end

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
SB.STRATA = STRATA

-- Screen rect (left, bottom, right, top) of a frame, or nil.
local function ScreenRect(f)
    local l, b, r, t = f:GetLeft(), f:GetBottom(), f:GetRight(), f:GetTop()
    if not (l and b and r and t) then return nil end
    local k = f:GetEffectiveScale() or 1
    return l * k, b * k, r * k, t * k
end

-- Which of our frames sits on top of the button's centre and takes the mouse (higher strata, or the same strata
-- at the same or a higher level): its label, else nil. Ours only (the game has no "frame at a point" query).
function SB.CoveredBy(b)
    if not (b and b:IsVisible()) then return nil end
    local l, bo, r, t = ScreenRect(b)
    if not l then return nil end
    local cx, cy = (l + r) / 2, (bo + t) / 2
    local bs = STRATA[b:GetFrameStrata() or "MEDIUM"] or 3
    local bl = b:GetFrameLevel() or 0
    local list = {
        { "the guide window", ns.UI and ns.UI.frame }, { "the 3D view", ns.ModelView and ns.ModelView.frame },
        { "the arrow", ns.Arrow and ns.Arrow.frame }, { "the item button", SB.frame },
        { "the target button", ns.TargetButton and ns.TargetButton.frame },
    }
    for _, e in ipairs(list) do
        local f = e[2]
        if f and f ~= b and f:IsVisible() and f:IsMouseEnabled() then
            local fl, fb, fr, ft = ScreenRect(f)
            if fl and cx >= fl and cx <= fr and cy >= fb and cy <= ft then
                local fs = STRATA[f:GetFrameStrata() or "MEDIUM"] or 3
                if fs > bs or (fs == bs and (f:GetFrameLevel() or 0) >= bl) then return e[1] end
            end
        end
    end
    return nil
end

-- nil when a click on the button reaches its secure action, else a short reason (self-test + offline tests):
-- both clicks registered, mouse on, enabled, no hit-rect inset that eats the centre, the type and its attribute
-- set, nothing of ours on top.
function SB.Unclickable(b, kind, attr)
    if not b then return "not built" end
    local c = b.aogClicks or {}
    local up, down = false, false
    for _, v in ipairs(c) do
        if v == "AnyUp" or v == "LeftButtonUp" then up = true end
        if v == "AnyDown" or v == "LeftButtonDown" then down = true end
    end
    if not (up and down) then return "clicks registered: " .. (#c > 0 and table.concat(c, ",") or "none") .. " (needs up and down)" end
    if b.IsMouseEnabled and not b:IsMouseEnabled() then return "mouse off" end
    if b.IsEnabled and not b:IsEnabled() then return "disabled" end
    if b.GetHitRectInsets then
        local l, r, t, bo = b:GetHitRectInsets()
        local w, h = b:GetWidth() or 0, b:GetHeight() or 0
        if (l or 0) + (r or 0) >= w / 2 or (t or 0) + (bo or 0) >= h / 2 then return "hit rect inset too large" end
    end
    if b:GetAttribute("type") ~= kind then return "type is " .. tostring(b:GetAttribute("type")) end
    if b:IsShown() and b:GetAttribute(attr) == nil then return attr .. " attribute not set" end
    local top = SB.CoveredBy(b)
    if top then return "covered by " .. top end
    return nil
end

-- The quest an item is listed for in ns.QuestItems (q = id or a list), by quest: built once.
local function ByQuest()
    if SB.byQuest and SB.byQuestSrc == ns.QuestItems then return SB.byQuest end
    local t = {}
    for id, d in pairs(type(ns.QuestItems) == "table" and ns.QuestItems or {}) do
        if type(id) == "number" and type(d) == "table" then
            local q = d.q or d.quest
            if type(q) == "number" then q = { q } end
            for _, x in ipairs(type(q) == "table" and q or {}) do
                if type(x) == "number" and not t[x] then t[x] = id end
            end
        end
    end
    SB.byQuest, SB.byQuestSrc = t, ns.QuestItems
    return t
end

-- Is the quest already taken (in the log or done)?
local function Taken(q)
    if type(q) ~= "number" then return false end
    local GS = ns.GameState
    return (GS and (GS.InLog(q) or GS.IsDone(q))) or Co.OnQuest(q) == true
end

-- The quest an item starts (and that the player hasn't taken yet), or nil. From the bag scan (out of combat) or
-- ns.QuestItems when the route accepts that quest from an item.
-- The quest an item starts (taken or not), or nil: an accept step from = "item" names it; else the bag scan's
-- starter flag, or ns.QuestItems when the route accepts that quest from an item. Plain loot / use items: nil.
function SB.StarterQuest(id, step)
    if type(id) ~= "number" then return nil end
    if type(step) == "table" and step.type == "accept" and step.from == "item" and type(step.quest) == "number" then
        return step.quest
    end
    local BQ = ns.BagQuests
    if not BQ then return nil end
    local e = BQ.items and BQ.items[id]
    if e and e.starter and type(e.quest) == "number" then return e.quest end
    local q = BQ.DataQuest(id)
    if type(q) == "number" then
        local info = BQ.QuestInfo(q)
        if info and info.accept and info.accept.from == "item" then return q end
    end
    return nil
end

-- The quest an item starts and that the player hasn't taken yet, or nil.
function SB.Starts(id, step)
    local q = SB.StarterQuest(id, step)
    if q and not Taken(q) then return q end
    return nil
end

-- The quest's name (game first, else the route's qname), or nil.
function SB.QuestName(q)
    if type(q) ~= "number" then return nil end
    local BQ = ns.BagQuests
    local info = BQ and BQ.QuestInfo(q)
    local fallback = info and info.accept and info.accept.qname or nil
    local N = ns.Names
    return (N and N.Quest(q, fallback)) or fallback
end

local function InBags(id) return type(id) == "number" and Co.ItemCount(id) > 0 end

-- The item of an accept step that comes from an item: its cond item=<id>, else the ns.QuestItems row of its quest.
local function AcceptItem(step)
    if Taken(step.quest) then return nil end
    local Cd = ns.Conditions
    local ast = step.condAst or (type(step.cond) == "string" and Cd and Cd.Get(step.cond)) or nil
    local ids = {}
    for id in pairs(Cd and Cd.Items(ast) or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do if InBags(id) then return id end end
    local id = type(step.quest) == "number" and ByQuest()[step.quest]
    return InBags(id) and id or nil
end

-- The item the step wants on the button, or nil; second value: the quest it starts (badge, tooltip).
-- Order: hearth, useItem / useitem (shown even when not in the bags: dimmed; a quest starter whose quest is already
-- taken: hidden), then quest starters without useItem (only in the bags).
function SB.ItemFor(step)
    if type(step) ~= "table" then return nil end
    if step.type == "hearth" then return SB.HEARTHSTONE end
    local use = type(step.useItem) == "number" and step.useItem
        or (step.type == "useitem" and type(step.item) == "number" and step.item) or nil
    if use then
        local q = SB.StarterQuest(use, step)
        if q and Taken(q) then return nil end
        return use, q
    end
    if step.type == "accept" and step.from == "item" then
        local id = AcceptItem(step)
        if id then return id, step.quest end
    elseif step.type == "objective" and InBags(step.item) then
        local q = SB.Starts(step.item)
        if q then return step.item, q end
    end
    return nil
end

-- What the button should hold now: the current step's item first, else the first goal riding along with an item
-- in the bags (the user's yes, 2026-11-26). nil when hidden (setting off, window hidden or small).
function SB.Wanted()
    if not (ns.UI and ns.UI.IsShown and ns.UI.IsShown()) then return nil end
    if ns.UI.Small and ns.UI.Small() then return nil end
    if ns.Settings and ns.Settings.Get("itemButton") == false then return nil end
    local cur, top = ns.Engine.Current()
    local id, q = SB.ItemFor(cur)
    if id then return id, q end
    if top and top.Background then
        for _, s in ipairs(top:Background()) do
            id, q = SB.ItemFor(s)
            if id and InBags(id) then return id, q end
        end
    end
    -- beta.8 fix (the user: "on step 8 i allready have the book ... i dont see a button"): a quest starter the
    -- route uses a little later (or passed a little earlier) that is already in the bags: offer it now
    id, q = SB.NearStarter(top)
    if id then return id, q end
    return nil
end

-- The first quest-starting item in the bags that a route step near the current one starts (an accept step
-- from = "item", or a step with a starter `useItem`), whose quest isn't taken and whose step isn't skipped.
SB.AHEAD, SB.BEHIND = 25, 15
function SB.NearStarter(top)
    if not (top and top.Step and top.pos) then return nil end
    local skips = top.save and top.save.skips or {}
    local last = top.Count and top:Count() or top.pos
    for i = math.max(1, top.pos - SB.BEHIND), math.min(last, top.pos + SB.AHEAD) do
        local s = top:Step(i)
        if s and i ~= top.pos and not skips[s.id] and ((s.type == "accept" and s.from == "item") or type(s.useItem) == "number") then
            local id, q = SB.ItemFor(s)
            if id and q and InBags(id) and not Taken(q) then return id, q end
        end
    end
    return nil
end

-- Why the button is hidden now (self-test, offline tests), or nil when it shows / should show.
function SB.HiddenWhy()
    if not ns.Feature.IsOn("stepbutton") then return "the stepbutton feature is off" end
    if not (ns.UI and ns.UI.IsShown and ns.UI.IsShown()) then return "the guide window is hidden" end
    if ns.UI.Small and ns.UI.Small() then return "small mode" end
    if ns.Settings.Get("itemButton") == false then return "the Item button setting is off" end
    local id = SB.Wanted()
    if not id then return "no item for this step (none named, none in the bags, or its quest is taken)" end
    if CQ.Pending("stepbutton") then return "waiting for the end of combat" end
    if not (SB.frame and SB.frame:IsShown()) then return "should show item " .. id .. " but the frame is hidden" end
    return nil
end

local function Build()
    local CreateFrame = _G.CreateFrame
    local b = CreateFrame("Button", SB.NAME, Co.fn.UIParent, "SecureActionButtonTemplate")
    b:SetSize(SB.SIZE, SB.SIZE)
    b:SetClampedToScreen(true)   -- never off screen when the window sits at the left edge
    SB.Clicks(b)
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
    -- (the one window: the rounded frame, its hole covers the icon's square corners)
    Th.Glyph(b.border, Th.Has("slot.frame.button") and "frame.button" or "frame.stepbutton")
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
    -- the quest "!" on items that start a quest (look only): the game's own icon by path, else our glyph
    b.badge = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.badge:SetSize(16, 16)
    b.badge:SetPoint("CENTER", b, "TOPRIGHT", -3, -3)
    if b.badge:SetTexture(SB.BADGE) == false then
        Th.Glyph(b.badge, SB.BADGE_FALLBACK)
        b.badge:SetVertexColor(Th.Color("accent"))
        SB.badgeFallback = true
    end
    b.badge:Hide()
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
    if not id then
        b.badge:Hide()
        return
    end
    b.icon:SetTexture(Co.ItemIcon(id) or Th.File("itemUnknown"))
    b.icon:SetTexCoord(SB.CROP, 1 - SB.CROP, SB.CROP, 1 - SB.CROP)
    local n = Co.ItemCount(id)
    b.count:SetText(n > 1 and tostring(n) or "")
    local missing = n == 0
    b.missing = missing
    -- a quest starter not looted yet (a farm step): a quiet "what you're farming for" hint, not a red "missing"
    local farming = missing and SB.starts[id] ~= nil
    SB.farming = farming
    b.badge:SetShown(SB.starts[id] ~= nil and not missing and not pending)
    b.icon:SetDesaturated(missing)
    b.icon:SetAlpha(farming and SB.FARM_ALPHA or 1)
    local edge = (farming and "stepFrame") or (missing and "stepFrameMissing") or (b.glow:IsShown() and "accent") or "stepFrame"
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
    local q = SB.starts[id]
    local missing = Co.ItemCount(id) == 0
    if q and missing then
        -- farming for it: no "missing" warning and no click hint
        tip:AddLine(ns.U.Fill(L.BUTTON_FARMING, { item = Co.ItemName(id) or L.BUTTON_FARMING_ITEM }), Th.Color("counter"))
        tip:Show()
        return
    end
    if q then
        local name = SB.QuestName(q)
        tip:AddLine(name and ns.U.Fill(L.BUTTON_STARTS, { quest = name }) or L.BUTTON_STARTS_ANY, Th.Color("accent"))
    end
    if missing then tip:AddLine(L.BUTTON_MISSING, Th.Color("notice.danger")) end
    local s, d = Co.ItemCooldown(id)
    if d > 1.5 then
        local left = math.max(0, s + d - Co.Now())
        tip:AddLine(ns.U.Fill(L.BUTTON_COOLDOWN, { n = math.ceil(left / 60) }), Th.Color("counter"))
    end
    tip:AddLine(L.BUTTON_HINT, Th.Color("counter"))
    tip:Show()
end

-- Places the button in the row above the window's top-left (beta.8: the target button first, the item button right
-- of it), at the window's own scale. The window's GetLeft / GetTop are in its own scaled units: k turns them into
-- UIParent units, and the button's offsets are in its own units (UIParent units / its scale). Secure: only from Apply
-- (combat queue). SB.Spot(i) = the i-th spot of that row (the target button always spot 1; the item button SB.SpotIndex()).
function SB.Spot(i)
    local w = ns.UI and ns.UI.frame
    local p = Co.fn.UIParent
    local s = ns.Overlay.WindowScale()
    if type(s) ~= "number" or s <= 0 then s = 1 end
    local x, y = w and w:GetLeft(), w and w:GetTop()
    local ps = p and p.GetEffectiveScale and p:GetEffectiveScale()
    if not (x and y and ps and ps > 0) then return nil, nil, s end
    local k = w:GetEffectiveScale() / ps
    local gap = Th.Size("buttonRowGap")
    -- the frame art sticks out 8 on each side: the first button's frame lines up with the window's left edge
    local bx = x * k / s + 8 + (i - 1) * (SB.SIZE + 16)
    local by = y * k / s + gap + SB.SIZE
    return bx, by, s
end

-- The item button's spot (beta.8, the user: "move the button to the other side of target"): right of the target
-- button (spot 2) while that shows, else spot 1.
function SB.SpotIndex()
    local TB = ns.TargetButton
    return (TB and TB.frame and TB.frame:IsShown()) and 2 or 1
end

-- The target button was shown / hidden / moved (from its Apply, out of combat): follow it when the item button
-- now sits in the wrong spot. Secure: through the combat queue like every change.
function SB.FollowTarget()
    local b = SB.frame
    if b and b:IsShown() and SB.MisplacedAt(b, SB.SpotIndex()) then
        CQ.Run("stepbutton", SB.Apply, SB.item)
    end
end

local function Place(b)
    local p = Co.fn.UIParent
    local x, y, s = SB.Spot(SB.SpotIndex())
    b:SetScale(s)
    SB.Raise(b)
    b:ClearAllPoints()
    if x then
        b:SetPoint("TOPLEFT", p, "BOTTOMLEFT", x, y)
    else
        b:SetPoint("CENTER", p, "CENTER", -200 / s, 0)
    end
    SB.placed = { x = x, y = y, scale = s }
end
SB.Place = Place
-- Secure part: item attribute, place, shown. Only ever called through the combat queue.
local function Apply(id)
    local b = SB.frame or Build()
    id = tonumber(id)
    SB.item = id
    if id then
        b:SetAttribute("item", "item:" .. tonumber(id))
        Place(b)
        b:Show()
    else
        b:SetAttribute("item", nil)
        b:Hide()
    end
    SB.Look()
end
SB.Apply = Apply

-- Follows the current step (out of combat at once, else after combat; the last wish wins).
-- replace = true (window moved, scaled or laid out again): always queue a re-place, even when the item is
-- the same (the early return used to leave the button behind when the window was dragged).
function SB.Update(replace)
    local id, q = SB.Wanted()
    if id then SB.starts[id] = q end   -- look only (badge, tooltip): the quest this item starts, or nil
    SB.want = id
    if replace and id and SB.frame then
        CQ.Run("stepbutton", Apply, id)
        SB.Look()
        return
    end
    -- (messy-play fix: a change queued in combat for another item must be replaced, so only skip when none waits)
    if id == SB.item and not CQ.Pending("stepbutton") and (not id or (SB.frame and SB.frame:IsShown())) then
        SB.Look()
        return
    end
    CQ.Run("stepbutton", Apply, id)
    SB.Look()
end

-- In-game self-test (/aog selftest): the button only ever holds type = item, and matches the step out of combat.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "stepbutton", fn = function(h)
    h.Count()
    -- why the item button is hidden on this step (the beta.8 book report): a line the player can paste
    local why = SB.HiddenWhy()
    if why then
        if why:find("should show", 1, true) and not Co.InCombat() then h.Problem("stepbutton: " .. why)
        else h.Info("stepbutton hidden: " .. why) end
    end
    local b = SB.frame
    if not b then
        h.Info("stepbutton: not built (no step with an item yet)")
        return
    end
    local t = b:GetAttribute("type")
    if t ~= "item" then h.Problem("stepbutton: type is " .. tostring(t)) end
    -- tos (use-item button): the item attribute is exactly "item:<number>" of the item the button holds
    local attr = b:GetAttribute("item")
    if SB.item and attr ~= "item:" .. SB.item then h.Problem("stepbutton: item attribute is " .. tostring(attr)) end
    if b:IsShown() and not SB.item then h.Problem("stepbutton: shown without an item") end
    if not Co.InCombat() and not CQ.Pending("stepbutton") and SB.want ~= SB.item then
        h.Problem("stepbutton: shows another item than the step")
    end
    -- while a change waits, the icon is the item a click uses now (post-check fix)
    if CQ.Pending("stepbutton") and SB.item and b.icon.GetTexture then
        local want = Co.ItemIcon(SB.item)
        if want and b.icon:GetTexture() ~= want then h.Problem("stepbutton: the icon isn't the item on the button") end
    end
    -- the one window: in the row above the window's top-left at the window's scale (unless the screen top clamps it)
    local bad = SB.Misplaced()
    if bad then h.Problem("stepbutton: " .. bad) end
    -- clickability (beta.11 "cant click it"): clicks, mouse, attributes, what's on top at its centre
    local clicks = table.concat(b.aogClicks or {}, ",")
    local top = SB.CoveredBy(b)
    h.Info(("stepbutton click: clicks %s, mouse %s, type %s, item %s, level %s (window %s), on top: %s"):format(
        clicks ~= "" and clicks or "none", tostring(b:IsMouseEnabled()), tostring(t), tostring(attr),
        tostring(b:GetFrameLevel()), tostring(ns.UI and ns.UI.frame and ns.UI.frame:GetFrameLevel()),
        top or "nothing of ours"))
    local nope = b:IsShown() and not Co.InCombat() and SB.Unclickable(b, "item", "item")
    if nope then h.Problem("stepbutton: can't be clicked: " .. nope) end
    -- look review #9: the icon is cropped; the glow pulses exactly while it is up (motion on)
    if b.icon.GetTexCoord then
        local l = b.icon:GetTexCoord()
        if type(l) == "number" and math.abs(l - SB.CROP) > 0.001 then h.Problem("stepbutton: the icon isn't cropped") end
    end
    if b.pulse and ((SB.pulsing ~= nil) ~= (b.glow:IsShown() and Th.Motion("pulse") > 0)) then
        h.Problem("stepbutton: the glow pulse doesn't match the glow")
    end
end }

-- nil when a button sits where it should (or can't be judged now), else a short reason. spot: 1 = the left one.
function SB.MisplacedAt(b, spot)
    local w = ns.UI and ns.UI.frame
    if not (b and w and b:IsShown() and w:IsShown()) or Co.InCombat() then return nil end
    local p = Co.fn.UIParent
    local ps = p and p:GetEffectiveScale()
    local bl, bt, wl, wt = b:GetLeft(), b:GetTop(), w:GetLeft(), w:GetTop()
    if not (ps and bl and bt and wl and wt) then return nil end
    local kb, kw = b:GetEffectiveScale() / ps, w:GetEffectiveScale() / ps
    if math.abs(kb - kw) > 0.01 then return ("scale %.2f, the window %.2f"):format(kb, kw) end
    local p2 = p:GetHeight()
    if bt * kb > p2 - 0.5 then return nil end   -- clamped at the screen's top edge
    local x, y = SB.Spot(spot)
    if not x then return nil end
    if math.abs(bt - y) > 1 then return "not in the row above the window's top" end
    if math.abs(bl - x) > 1 then return ("not at spot %d of that row"):format(spot) end
    -- above the window, never on it
    local bb = b:GetBottom()
    if bb and bb * kb < wt * kw - 0.5 then return "covers the window's top" end
    return nil
end

function SB.Misplaced()
    if CQ.Pending("stepbutton") then return nil end
    return SB.MisplacedAt(SB.frame, SB.SpotIndex())
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
    -- the bags or the quest log changed: a quest-starting item may have come or gone (Update ends in Look);
    -- order 75: after the engine (60) has updated the goals riding along, and the window (70)
    -- (perf: a StepChanged already waiting in this bus chain updates the button right after; no second update)
    local function UpUnlessStep() if not ns.Bus.Pending("StepChanged") then SB.Update() end end
    ns.Bus.On("ItemsChanged", SB, UpUnlessStep, "stepbutton", 75)
    ns.Bus.On("BagQuestsChanged", SB, UpUnlessStep, "stepbutton")
    -- any bag change (a starter the current step doesn't watch, e.g. the book on the kill step before its farm step)
    ns.Bus.On("BagsChanged", SB, UpUnlessStep, "stepbutton", 75)
    ns.Bus.On("QuestsChanged", SB, UpUnlessStep, "stepbutton", 75)
    ns.Bus.On("CombatQueueChanged", SB, function() SB.Look() end, "stepbutton")
    -- reduced motion on / off: the glow pulse stops / starts at once; itemButton / small: shown or hidden
    ns.Bus.On("SettingsChanged", SB, function(_, key)
        if key == "reducedMotion" then SB.Look() end
        if key == "itemButton" or key == "small" then Up() end
    end, "stepbutton")
    SB.Update()
end, "stepbutton", 90)

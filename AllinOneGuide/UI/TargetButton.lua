-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The target button (the one window, Part B): one secure button above the window that targets the mob the current
-- step names, when the player presses it. The tos check (plans\guide-window-look\tos-target.md) allows it with
-- these conditions, all kept here and checked by the self-test:
--   1. the macro is exactly one line "/targetexact <name>" (no other command, no cycling, one name)
--   2. the name is cleaned (no ; [ ] or line breaks, at most TB.MAX characters)
--   3. the name comes only from static data for the current step (Data\MobNames.lua by the step's mob id); never
--      from units, nameplates, the combat log or "nearest"
--   4. only the player's press targets (a SecureActionButtonTemplate, type "macro"); the addon never clicks it
--   5. macro text, show / hide and position change only out of combat (ns.CombatQueue "targetbutton"); in combat
--      it keeps the last mob
--   6. only on English clients (enUS / enGB): the names are English
--   7. creature names only (MobNames holds creature_template names; never a player's)
-- /targetexact: Forever's UI source (1.60.1) Blizzard_ChatFrameBase\Shared\SlashCommands.lua; type "macro" +
-- "macrotext": Blizzard_FrameXML\SecureTemplates.lua SECURE_ACTIONS.macro.
-- Named AllinOneGuideTargetButton so a key binding can click it (Bindings.xml).
--   ns.TargetButton.Update(replace), .NameFor(step), .Clean(name), .Macro(name), .Wanted(), .Problem()
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local CQ = ns.CombatQueue
local TB = { NAME = "AllinOneGuideTargetButton", MAX = 60, LOCALES = { enUS = true, enGB = true }, name = nil, want = nil }
ns.TargetButton = TB

-- Condition 2: the cleaned name, or nil when nothing usable is left.
function TB.Clean(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[;%[%]\r\n%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > TB.MAX then return nil end
    return name
end

-- Condition 1: the one macro line.
function TB.Macro(name)
    name = TB.Clean(name)
    return name and ("/targetexact " .. name) or nil
end

-- Condition 6: English clients only.
function TB.Allowed()
    return TB.LOCALES[Co.Locale() or ""] == true
end

-- Conditions 3 and 7: the mob of the current step (a kill / loot step's mob, or its targetNpc) from the static
-- name table, or nil.
function TB.NameFor(step)
    if type(step) ~= "table" then return nil end
    local names = ns.MobNames
    if type(names) ~= "table" then return nil end
    local id = tonumber(step.targetNpc)
    if not id and step.type == "objective" then id = tonumber(step.npc) end
    return id and TB.Clean(names[id]) or nil
end

-- The name the button should have now (nil = hidden).
function TB.Wanted()
    if not (ns.Settings.Get("targetButton") and TB.Allowed() and ns.Feature.IsOn("targetbutton")) or ns.safeMode then
        return nil
    end
    if not (ns.UI and ns.UI.IsShown and ns.UI.IsShown()) or ns.UI.Small() then return nil end
    return TB.NameFor(ns.Engine.Current())
end

local function Build()
    local CreateFrame = _G.CreateFrame
    local SB = ns.StepButton
    local size = SB.SIZE
    local b = CreateFrame("Button", TB.NAME, Co.fn.UIParent, "SecureActionButtonTemplate")
    b:SetSize(size, size)
    b:SetClampedToScreen(true)
    SB.Clicks(b)   -- up and down (beta.11 fix: ActionButtonUseKeyDown acts on the down click; see StepButton.CLICKS)
    b:SetAttribute("type", "macro")
    b:Hide()
    b.bg = K.Fill(b, "BACKGROUND", "targetBg")
    b.bg:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(size - 8, size - 8)
    b.icon:SetPoint("CENTER")
    Th.Glyph(b.icon, Th.Has("slot.btn.target") and "btn.target" or "state.none")
    b.icon:SetVertexColor(Th.Color("target"))
    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetSize(52, 52)
    b.border:SetPoint("CENTER")
    Th.Glyph(b.border, Th.Has("slot.frame.button") and "frame.button" or "frame.stepbutton")
    b.border:SetVertexColor(Th.Color("stepFrame"))
    b.key = K.Text(b, "buttonText", "counter", "LEFT")
    b.key:SetPoint("TOPLEFT", 3, -3)
    b.wait = b:CreateTexture(nil, "OVERLAY")
    b.wait:SetSize(16, 16)
    b.wait:SetPoint("CENTER", b, "TOPRIGHT", -2, -2)
    Th.Glyph(b.wait, "state.wait")
    b.wait:SetVertexColor(Th.Color("wait"))
    b.wait:Hide()
    -- look only: the crosshair turns white on hover
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(Th.Color("white"))
        ns.Errors.Call("targetbutton", TB.Tooltip, self)
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(Th.Color("target"))
        K.HideTooltip()
    end)
    TB.frame = b
    return b
end

function TB.Tooltip(owner)
    local tip = Co.Tooltip()
    if not tip or not TB.name then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(ns.U.Fill(ns.L.TIP_TARGET, { name = TB.name }), Th.Color("target"))
    tip:AddLine(ns.L.TIP_TARGET_HINT, Th.Color("counter"))
    tip:Show()
end

-- Look only (safe in combat): the hourglass while a change waits, the key.
function TB.Look()
    local b = TB.frame
    if not b then return end
    b.wait:SetShown(CQ.Pending("targetbutton"))
    b.key:SetText(Co.BindingKey("CLICK " .. TB.NAME .. ":LeftButton") or "")
end

-- Its spot in the row above the window: always the first (beta.8, the user: the item button goes "to the other side
-- of target"); the item button follows it (StepButton.SpotIndex / FollowTarget).
function TB.Spot() return 1 end

-- Secure part: macro text, place, shown. Only ever called through the combat queue (condition 5).
local function Apply(name)
    local b = TB.frame or Build()
    local macro = TB.Macro(name)
    TB.name = macro and TB.Clean(name) or nil
    if macro then
        b:SetAttribute("macrotext", macro)
        local x, y, s = ns.StepButton.Spot(TB.Spot())
        b:SetScale(s)
        ns.StepButton.Raise(b)
        b:ClearAllPoints()
        if x then
            b:SetPoint("TOPLEFT", Co.fn.UIParent, "BOTTOMLEFT", x, y)
        else
            b:SetPoint("CENTER", Co.fn.UIParent, "CENTER", -150 / s, 0)
        end
        b:Show()
    else
        b:SetAttribute("macrotext", nil)
        b:Hide()
    end
    TB.Look()
    -- the item button sits right of this one, or takes spot 1 when this one hides (its own combat queue key)
    if ns.StepButton and ns.StepButton.FollowTarget then ns.StepButton.FollowTarget() end
end

-- Follows the current step (out of combat at once, else after combat; the last wish wins). Never targets
-- anything itself (condition 4).
function TB.Update(replace)
    local name = TB.Wanted()
    TB.want = name
    -- (messy-play fix: a change queued in combat for another mob must be replaced, so only skip when none waits)
    if not replace and name == TB.name and not CQ.Pending("targetbutton") and (not name or (TB.frame and TB.frame:IsShown())) then
        TB.Look()
        return
    end
    -- (nothing to hide when never built, unless a change for a mob waits: that one must be replaced)
    if not name and not TB.frame and not CQ.Pending("targetbutton") then return end
    CQ.Run("targetbutton", Apply, name)
    TB.Look()
end

-- nil when everything holds, else a short reason (self-test + offline tests).
function TB.Problem()
    local b = TB.frame
    if not b then return nil end
    local t = b:GetAttribute("type")
    if t ~= "macro" then return "type is " .. tostring(t) end
    local m = b:GetAttribute("macrotext")
    if m ~= nil then
        if type(m) ~= "string" or m:find("[\r\n;]") then return "the macro isn't one line" end
        local name = m:match("^/targetexact (.+)$")
        if not name then return "the macro isn't /targetexact <name>" end
        if TB.Clean(name) ~= name then return "the name isn't clean" end
        -- creature names only: it must be one of the static mob names
        local known = false
        for _, v in pairs(ns.MobNames or {}) do
            if v == name then known = true break end
        end
        if not known then return "the name isn't a mob from the guide data" end
        if not TB.Allowed() then return "shown on a non-English client" end
    end
    if b:IsShown() and m == nil then return "shown without a mob" end
    if not Co.InCombat() and not CQ.Pending("targetbutton") then
        if (TB.want ~= nil) ~= b:IsShown() then return "shown / hidden against the step" end
        if TB.want and TB.want ~= TB.name then return "holds another mob than the step" end
        local bad = ns.StepButton.MisplacedAt(b, TB.Spot())
        if bad then return bad end
        local nope = b:IsShown() and ns.StepButton.Unclickable(b, "macro", "macrotext")
        if nope then return "can't be clicked: " .. nope end
    end
    return nil
end

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "targetbutton", fn = function(h)
    h.Count()
    -- the cleaning always holds (condition 2)
    if TB.Clean("A;B[C]\nD") ~= "ABCD" or TB.Clean(("x"):rep(TB.MAX + 1)) ~= nil then
        h.Problem("targetbutton: the name cleaning is broken")
    end
    local bad = TB.Problem()
    if bad then h.Problem("targetbutton: " .. bad) end
end }

ns.Bus.On("Login", TB, function()
    local function Up() ns.Errors.Call("targetbutton", TB.Update) end
    local function Replace() ns.Errors.Call("targetbutton", TB.Update, true) end
    ns.Bus.On("StepChanged", TB, Up, "targetbutton")
    ns.Bus.On("WindowToggled", TB, Up, "targetbutton")
    ns.Bus.On("WindowMoved", TB, Replace, "targetbutton")
    ns.Bus.On("WindowLayout", TB, Replace, "targetbutton")
    ns.Bus.On("ScaleChanged", TB, Replace, "targetbutton", 81)
    -- the item button came or went: the target button takes the other spot
    ns.Bus.On("CombatQueueChanged", TB, function()
        TB.Look()
        local b = TB.frame
        if b and b:IsShown() and not Co.InCombat() and not CQ.Pending("targetbutton")
            and ns.StepButton.MisplacedAt(b, TB.Spot()) then
            Replace()
        end
    end, "targetbutton")
    ns.Bus.On("SettingsChanged", TB, function(_, key)
        if key == "targetButton" or key == "small" then Up() end
    end, "targetbutton")
    Up()
end, "targetbutton", 91)

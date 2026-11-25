-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- One small drop-down menu (our own frame, no Blizzard menu code): the title menu, the notice line's
-- right-click menu and the "n done" chip's list all use it.
--   ns.Menu.Open(anchor, items)   items = { { text, checked = true/false/nil, fn, disabled } ... }
--   ns.Menu.Close(), ns.Menu.IsOpen()
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local Mn = { buttons = {}, WIDTH = 190, MAX = 12 }
ns.Menu = Mn

local function Build()
    -- named only so Blizzard's Esc list (UISpecialFrames) can hide it; nothing else uses the name
    local f = CreateFrame("Frame", "AllinOneGuideMenu", ns.Compat.UIParent())
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetWidth(Mn.WIDTH)
    f:EnableMouse(true)
    K.Panel(f)
    f:Hide()
    -- however it gets hidden (Close, Esc): forget the items and stop listening for clicks
    f:SetScript("OnHide", function()
        Mn.items = nil
        ns.Events.Off("GLOBAL_MOUSE_DOWN", Mn)
    end)
    K.CloseOnEsc("AllinOneGuideMenu")
    Mn.frame = f
end

local function Button(i)
    local b = Mn.buttons[i]
    if b then return b end
    local f = Mn.frame
    b = CreateFrame("Button", nil, f)
    b:SetHeight(Th.LineHeight("step") + 4)
    b:SetPoint("LEFT", f, "LEFT", 1, 0)
    b:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    b:SetPoint("TOP", f, "TOP", 0, -4 - (i - 1) * (Th.LineHeight("step") + 4))
    b.hover = K.Fill(b, "BACKGROUND", "buttonHoverBg")
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.check = K.Glyph(b, "check.tick", Th.Size("box"), "goalDone")
    b.check:SetPoint("LEFT", b, "LEFT", 8, 0)
    b.text = K.Text(b, "step", "text")
    b.text:SetPoint("LEFT", b, "LEFT", 8 + Th.Size("box") + 6, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b:SetScript("OnEnter", function(self) self.hover:Show() end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    b:SetScript("OnClick", function(self)
        local item = self.item
        if not item or item.disabled then return end
        if not item.keepOpen then Mn.Close() end
        if item.fn then ns.Errors.Call("ui", item.fn) end
        if item.keepOpen and Mn.items then Mn.Open(Mn.anchor, Mn.items, Mn.opts) end
    end)
    Mn.buttons[i] = b
    return b
end

-- A click anywhere outside the menu (and outside the button that opened it) closes it. Listened to
-- only while the menu is open.
local function Over(f)
    if type(f) ~= "table" or type(f.IsMouseOver) ~= "function" then return false end
    local ok, over = pcall(f.IsMouseOver, f)
    return ok and over == true
end
function Mn.OnMouseDown()
    if not Mn.IsOpen() then return end
    if Over(Mn.frame) or Over(Mn.anchor) then return end
    Mn.Close()
end

-- Esc: the frame's name is in UISpecialFrames, so Blizzard's own Esc code hides it (OnHide cleans up).

-- opts.right = line the menu's right edge up with the anchor's (for a button at the window's right).
function Mn.Open(anchor, items, opts)
    if not Mn.frame then Build() end
    local f = Mn.frame
    Mn.anchor, Mn.items = anchor, items
    local n = math.min(#items, Mn.MAX)
    for i = 1, n do
        local b, item = Button(i), items[i]
        b.item = item
        b.text:SetText(item.text or "")
        K.Color(b.text, item.disabled and "text.dim" or "text")
        b.check:SetShown(item.checked == true)
        b:Show()
    end
    for i = n + 1, #Mn.buttons do Mn.buttons[i]:Hide() end
    f:SetHeight(8 + n * (Th.LineHeight("step") + 4))
    f:ClearAllPoints()
    if opts and opts.right then
        f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    else
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    Mn.opts = opts
    f:Show()
    ns.Events.On("GLOBAL_MOUSE_DOWN", Mn, Mn.OnMouseDown, "ui")
end

function Mn.Close()
    if Mn.frame then Mn.frame:Hide() end   -- OnHide forgets the items and the click listener
    Mn.items = nil
end

function Mn.IsOpen() return Mn.frame ~= nil and Mn.frame:IsShown() end

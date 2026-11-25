-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- One confirm dialog and one copy box (our own frames). Dialogs the addon raises by itself (safe mode,
-- "move data?") come in a fixed order (safe > move) and at most one of them per session; a dialog the
-- player asked for (language reload) always shows, but never on top of another one.
--   ns.Popups.Confirm{ kind, text, accept, cancel, acceptText, cancelText, noCancel }
--   ns.Popups.Copy(title, text)
local _, ns = ...
local Th, K, L = ns.Theme, ns.UIKit, ns.L
local Pp = { queue = {}, autoShown = false, ORDER = { safe = 3, crash = 3, move = 2, route = 1, lang = 1, restore = 1 }, AUTO = { safe = true, crash = true, move = true, route = true } }
ns.Popups = Pp

local WIDTH = 300

local function Build()
    -- named only for Blizzard's Esc list (UISpecialFrames): Esc = "No"
    local f = CreateFrame("Frame", "AllinOneGuideDialog", ns.Compat.UIParent())
    f:SetFrameStrata("DIALOG")
    f:SetSize(WIDTH, 120)
    f:SetPoint("CENTER", ns.Compat.UIParent(), "CENTER", 0, 120)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    K.Panel(f)
    -- the shared title bar says which addon asks (look review #5); its X = hiding = the No answer
    f.titleBar = K.TitleBar(f, { drag = true, close = function() f:Hide() end })
    f.titleBar.title:SetText(ns.TITLE)
    local top = Th.Size("title") + 10
    f.text = K.Text(f, "step", "text")
    f.text:SetWordWrap(true)
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -top)
    f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -top)
    -- primary = the accept answer (accent text), the other a plain button
    f.yes = K.Button(f, L.POPUP_YES, function() Pp.Answer(true) end, { primary = true })
    f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 12)
    f.no = K.Button(f, L.POPUP_NO, function() Pp.Answer(false) end)
    f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 12)
    f:Hide()
    -- hidden while a question is open (Esc): the answer is No (noCancel dialogs: their only button)
    f:SetScript("OnHide", function()
        local p = Pp.current
        if p then Pp.Answer(p.noCancel and true or false) end
    end)
    K.CloseOnEsc("AllinOneGuideDialog")
    Pp.frame = f
end

function Pp.Confirm(p)
    if Pp.AUTO[p.kind] and Pp.autoShown then return false end
    for _, q in ipairs(Pp.queue) do if q.kind == p.kind then return false end end
    Pp.queue[#Pp.queue + 1] = p
    table.sort(Pp.queue, function(a, b) return (Pp.ORDER[a.kind] or 0) > (Pp.ORDER[b.kind] or 0) end)
    Pp.Next()
    return true
end

-- Shows the first waiting dialog when none is showing.
function Pp.Next()
    if Pp.current then return end
    local p = table.remove(Pp.queue, 1)
    while p and Pp.AUTO[p.kind] and Pp.autoShown do p = table.remove(Pp.queue, 1) end
    if not p then return end
    if Pp.AUTO[p.kind] then Pp.autoShown = true end
    if not Pp.frame then Build() end
    local f = Pp.frame
    Pp.current = p
    f.yes:SetLabel(p.acceptText or L.POPUP_YES)
    f.no:SetLabel(p.cancelText or L.POPUP_NO)
    -- wide enough for both buttons (long Danish words)
    local need = f.yes:GetWidth() + (p.noCancel and 0 or f.no:GetWidth() + 12) + 24
    f:SetWidth(math.max(WIDTH, need))
    f.text:SetText(p.text or "")
    f.no:SetShown(not p.noCancel)
    if p.noCancel then
        f.yes:ClearAllPoints()
        f.yes:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    else
        f.yes:ClearAllPoints()
        f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 12)
    end
    local textH = f.text:GetStringHeight() or Th.LineHeight("step")
    f:SetHeight(math.max(90, Th.Size("title") + textH + 22 + Th.LineHeight("step") + 28))
    f:Show()
end

function Pp.Answer(yes)
    local p = Pp.current
    Pp.current = nil
    if Pp.frame then Pp.frame:Hide() end
    if p then
        local fn = yes and p.accept or (not yes and p.cancel)
        if fn then ns.Errors.Call("ui", fn) end
    end
    Pp.Next()
end

function Pp.Current() return Pp.current end

-- ------------------------------------------------------------------ copy box
local function BuildCopy()
    local f = CreateFrame("Frame", nil, ns.Compat.UIParent())
    f:SetFrameStrata("DIALOG")
    local top = Th.Size("title")
    f:SetSize(360, 96 + top)
    f:SetPoint("CENTER", ns.Compat.UIParent(), "CENTER", 0, 40)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    K.Panel(f)
    -- the shared title bar (look review #5) with its close button; what is copied stays the heading below
    f.titleBar = K.TitleBar(f, { drag = true, close = function() f:Hide() end })
    f.titleBar.title:SetText(ns.TITLE)
    f.title = K.Text(f, "header", "zone")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(top + 8))
    local e = CreateFrame("EditBox", nil, f)
    e:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(top + 30))
    e:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -(top + 30))
    e:SetHeight(Th.LineHeight("step") + 6)
    e:SetAutoFocus(false)
    Th.Font(e, "step")
    e:SetTextColor(Th.Color("text"))
    K.Fill(e, "BACKGROUND", "barTrack"):SetAllPoints()
    e:SetScript("OnEscapePressed", function() f:Hide() end)
    e:SetScript("OnEnterPressed", function() f:Hide() end)
    -- the text can't be edited: typing puts it back
    e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.value or "") self:HighlightText() end end)
    f.edit = e
    -- an optional line under the text (where to paste it); the box grows to fit it
    f.note = K.Text(f, "goal", "text")
    f.note:SetWordWrap(true)
    f.note:SetWidth(340)
    f.note:SetPoint("TOPLEFT", e, "BOTTOMLEFT", 0, -6)
    f.note:Hide()
    f.hint = K.Text(f, "small", "text.dim")
    f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    f.hint:SetText(L.COPY_HINT)
    f:Hide()
    Pp.copy = f
end

-- note (optional): one or two lines under the text, e.g. the web address to paste it at.
function Pp.Copy(title, text, note)
    if not Pp.copy then BuildCopy() end
    local f = Pp.copy
    f.value = tostring(text or "")
    f.title:SetText(title or "")
    local extra = 0
    if note and note ~= "" then
        f.note:SetText(note)
        f.note:Show()
        extra = math.max(Th.LineHeight("goal"), f.note:GetStringHeight() or 0) + 8
    else
        f.note:SetText("")
        f.note:Hide()
    end
    f:SetHeight(96 + Th.Size("title") + extra)
    f.edit:SetText(f.value)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

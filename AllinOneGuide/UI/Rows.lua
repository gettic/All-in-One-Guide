-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Step rows and goal lines. A row = number, badge, main text, right-hand info (distance or done tick),
-- then for the current step: goal lines (checkbox + text + count), the coordinate line and background
-- goals. States: "current" (accent bar + glow, bright text), "upcoming" (dim by colour), "done".
-- Never SetAlpha on text: dimming is always a text colour.
--   ns.Rows.New(parent) -> row;  ns.Rows.Set(row, data) -> height
--   data = { number, badge, text, state, right, goals = { { text, have, need, done } }, coord, maxLines }
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local R = {}
ns.Rows = R

local function Pad() return Th.Size("pad") end

function R.New(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(Th.LineHeight("step"))
    -- on the row itself and hidden until Set: a row that's never set leaves nothing shown behind
    row.glow = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.glow:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.glow:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    K.Gradient(row.glow, "HORIZONTAL", "accentGlow", "accentGlowEnd")
    row.glow:Hide()
    row.bar = K.Fill(row, "ARTWORK", "accent")
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.flash = K.Fill(row, "ARTWORK", "flash", 3)
    row.flash:SetAllPoints(row)
    row.flash:Hide()
    row.num = K.Text(row, "small", "stepNumber", "RIGHT")
    row.num:SetWidth(14)
    row.num:SetPoint("TOPLEFT", row, "TOPLEFT", Pad() - 4, -3)
    row.badge = K.Badge(row, Th.Size("badge"))
    row.badge.disc:SetPoint("TOPLEFT", row, "TOPLEFT", Pad() + 14, -1)
    row.text = K.Text(row, "step", "text")
    row.text:SetPoint("TOPLEFT", row.badge.disc, "TOPRIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -(Pad() + 44), 0)
    row.right = K.Text(row, "goal", "text.dim", "RIGHT")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -Pad(), -2)
    row.tick = K.Glyph(row, "done", Th.Size("badge"), "goalDone")
    row.tick:SetPoint("TOPRIGHT", row, "TOPRIGHT", -Pad(), 0)
    row.lines = {}
    return row
end

-- A goal / coordinate line inside a row (created on first use).
local function Line(row, i)
    local ln = row.lines[i]
    if ln then return ln end
    local box = Th.Size("box")
    ln = {}
    ln.fill = row:CreateTexture(nil, "ARTWORK", nil, 1)
    ln.fill:SetSize(box, box)
    Th.Glyph(ln.fill, "check.fill")
    ln.fill:SetVertexColor(Th.Color("goalDoneBox"))
    ln.box = row:CreateTexture(nil, "ARTWORK", nil, 2)
    ln.box:SetAllPoints(ln.fill)
    Th.Glyph(ln.box, "check.box")
    ln.tick = row:CreateTexture(nil, "ARTWORK", nil, 3)
    ln.tick:SetAllPoints(ln.fill)
    Th.Glyph(ln.tick, "check.tick")
    ln.tick:SetVertexColor(Th.Color("goalDone"))
    ln.pin = row:CreateTexture(nil, "ARTWORK", nil, 2)
    ln.pin:SetAllPoints(ln.fill)
    Th.Glyph(ln.pin, "badge.goto")
    ln.pin:SetVertexColor(Th.Color("icon.goto"))
    ln.text = K.Text(row, "goal", "goal")
    ln.text:SetPoint("LEFT", ln.fill, "RIGHT", 5, 0)
    ln.text:SetPoint("RIGHT", row, "RIGHT", -(Pad() + 44), 0)
    ln.right = K.Text(row, "goal", "text.dim", "RIGHT")
    ln.right:SetPoint("RIGHT", row, "RIGHT", -Pad(), 0)
    ln.right:SetPoint("TOP", ln.text, "TOP", 0, 0)
    row.lines[i] = ln
    return ln
end

local function ShowLine(ln, shown)
    for _, k in ipairs({ "fill", "box", "tick", "pin", "text", "right" }) do ln[k]:SetShown(shown) end
end

-- Lays out one row; returns its height.
function R.Set(row, d)
    local LH, LG = Th.LineHeight("step"), Th.LineHeight("goal")
    local state = d.state or "upcoming"
    local current = state == "current"
    row.glow:SetShown(current)
    row.bar:SetShown(current)
    row.num:SetText(d.number and tostring(d.number) or "")
    K.Color(row.num, current and "accent" or "stepNumber")
    K.SetBadge(row.badge, d.badge or "manual", state == "done")
    row.text:SetText(d.text or "")
    K.Color(row.text, (state == "done" and "done") or (current and "text") or "upcoming")
    row.text:SetWordWrap(current and (d.maxLines or 2) > 1)
    if row.text.SetMaxLines then row.text:SetMaxLines(current and (d.maxLines or 2) or 1) end
    row.tick:SetShown(state == "done")
    row.right:SetText(state ~= "done" and d.right or "")
    -- main line height (one line, or two when the current step's text wraps)
    local h = LH
    if current and (d.maxLines or 2) > 1 then
        local sh = row.text:GetStringHeight() or 0
        if sh > Th.FontSize("step") * 1.6 then h = LH * 2 end
    end
    -- goal lines, then the coordinate line
    local n = 0
    local lines = {}
    if current then
        for _, gl in ipairs(d.goals or {}) do lines[#lines + 1] = { kind = "goal", g = gl } end
        if d.coord then lines[#lines + 1] = { kind = "coord", c = d.coord } end
    end
    for _, l in ipairs(lines) do
        n = n + 1
        local ln = Line(row, n)
        ShowLine(ln, true)
        ln.fill:ClearAllPoints()
        ln.fill:SetPoint("TOPLEFT", row, "TOPLEFT", Pad() + 14 + Th.Size("badge") + 6, -(h + (LG - Th.Size("box")) / 2))
        if l.kind == "goal" then
            local g = l.g
            ln.pin:Hide()
            ln.fill:SetShown(g.done)
            ln.tick:SetShown(g.done)
            ln.box:SetVertexColor(Th.Color(g.done and "goalDoneEdge" or "goalBoxEmpty"))
            ln.text:SetText(g.text or "")
            K.Color(ln.text, g.done and "goalDone" or "goal")
            if g.need and g.need > 1 then
                ln.right:SetText(("%d/%d"):format(g.have or 0, g.need))
            else
                ln.right:SetText("")
            end
            K.Color(ln.right, g.done and "goalDone" or "goalCount")
        else
            ln.fill:Hide()
            ln.box:Hide()
            ln.tick:Hide()
            ln.text:SetText(l.c.text or "")
            K.Color(ln.text, "coord")
            ln.right:SetText(l.c.dist or "")
            K.Color(ln.right, "text.dim")
        end
        h = h + LG
    end
    for i = n + 1, #row.lines do ShowLine(row.lines[i], false) end
    row.coordLine = d.coord and row.lines[n] or nil
    row:SetHeight(h)
    return h
end

-- Updates only the distance on the current row's coordinate line (called by the arrow's ticker).
function R.SetDistance(row, text)
    if row and row.coordLine then row.coordLine.right:SetText(text or "") end
end

-- The "finished a step" flash (an animation on a texture; nothing with reduced motion).
function R.Flash(row)
    local d = Th.Motion("flash")
    if d <= 0 or not row.flash.CreateAnimationGroup then return end
    if not row.flashAnim then
        local ag = row.flash:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0)
        ag:SetScript("OnFinished", function() row.flash:Hide() end)
        row.flashAnim, row.flashAlpha = ag, a
    end
    row.flashAlpha:SetDuration(d)
    row.flash:Show()
    row.flashAnim:Stop()
    row.flashAnim:Play()
end

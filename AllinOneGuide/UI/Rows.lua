-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Step rows and goal lines. A row = number, badge, main text, right-hand info (distance or done tick),
-- then for the current step: goal lines (checkbox + text + count), the coordinate line and background
-- goals. States: "current" (accent bar + glow, bright text), "upcoming" (dim by colour), "done".
-- Never SetAlpha on text: dimming is always a text colour.
--   ns.Rows.New(parent) -> row;  ns.Rows.Set(row, data) -> height
--   data = { number, badge, text, state, right, goals = { { text, have, need, done } }, coord, maxLines, boxed,
--            reserveRight (units kept free on the right: the NOW window's item button) }
--   a goal may also carry kind ("kill" / "loot" / "use": travel side goal icon), side (its step), more ("+n more")
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local R = {}
ns.Rows = R
-- side goal kind -> K.BADGE entry (glyph + colour key; our own theme glyphs)
local SIDE_BADGE = { kill = "objective", loot = "collect", use = "useitem" }
R.SIDE_BADGE = SIDE_BADGE

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
    -- v0.2 fix (text over the NOW box): top anchors only on both sides plus a set height, so the text never
    -- centres itself in a tall row (a "RIGHT" point also pins the vertical middle) and never draws past its line(s)
    row.text = K.Text(row, "step", "text")
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", Pad() + 14 + Th.Size("badge") + 6, -1)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + 44), -1)
    row.text:SetJustifyV("TOP")
    row.text:SetHeight(Th.LineHeight("step") - 1)
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
    -- placed per line by R.Set (top anchors + the goal line's height, never a middle point)
    ln.text = K.Text(row, "goal", "goal")
    ln.text:SetJustifyV("MIDDLE")
    ln.right = K.Text(row, "goal", "text.dim", "RIGHT")
    ln.right:SetJustifyV("MIDDLE")
    row.lines[i] = ln
    return ln
end

local function ShowLine(ln, shown)
    for _, k in ipairs({ "fill", "box", "tick", "pin", "text", "right" }) do ln[k]:SetShown(shown) end
end

-- Room kept free on the right of a text for its right-hand text (count, distance, "in 2 levels"):
-- at least the usual 44, more when that text is wider (big fonts), so the two never overlap.
-- row.reserve (d.reserveRight, NOW window): room kept free on the far right for the item button.
local function RightInset(rightFs, gap, reserve)
    local w = rightFs and rightFs:GetText() ~= nil and rightFs:GetText() ~= "" and (rightFs:GetStringWidth() or 0) or 0
    return Pad() + math.max(44, math.ceil(w) + gap) + (reserve or 0)
end

-- A goal / coordinate line's text: top anchors at the line's top (ln.top), clear of its right-hand text.
local function PlaceLineText(row, ln)
    local x = Pad() + 14 + Th.Size("badge") + 6 + Th.Size("box") + 5
    ln.text:ClearAllPoints()
    ln.text:SetPoint("TOPLEFT", row, "TOPLEFT", x, -ln.top)
    ln.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -RightInset(ln.right, 4, row.reserve), -ln.top)
end

-- Lays out one row; returns its height.
function R.Set(row, d)
    local LH, LG = Th.LineHeight("step"), Th.LineHeight("goal")
    local state = d.state or "upcoming"
    local current = state == "current"
    row.step = d.step   -- v0.2 M3: the right-click step menu, hover and clicks
    row.current, row.rightText = current, d.right
    -- d.boxed: the row sits in the window's NOW box, which draws its own panel and accent edge
    row.glow:SetShown(current and not d.boxed)
    row.bar:SetShown(current and not d.boxed)
    row.num:SetText(d.number and tostring(d.number) or "")
    K.Color(row.num, current and "accent" or "stepNumber")
    K.SetBadge(row.badge, d.badge or "manual", state == "done")
    -- the badge and done tick never get taller than the line (small fonts: a 14 px badge in an 11 px line
    -- drew into the next row); the badge stays centred in its column
    local full = Th.Size("badge")
    local bs = math.max(8, math.min(full, LH - 1))
    row.badge.disc:SetSize(bs, bs)
    row.badge.disc:ClearAllPoints()
    row.badge.disc:SetPoint("TOPLEFT", row, "TOPLEFT", Pad() + 14 + (full - bs) / 2, -1)
    row.tick:SetSize(bs, bs)
    row.text:SetText(d.text or "")
    K.Color(row.text, (state == "done" and "done") or (current and "text") or "upcoming")
    row.text:SetWordWrap(current and (d.maxLines or 2) > 1)
    if row.text.SetMaxLines then row.text:SetMaxLines(current and (d.maxLines or 2) or 1) end
    row.tick:SetShown(state == "done")
    row.right:SetText(state ~= "done" and d.right or "")
    local reserve = tonumber(d.reserveRight) or 0
    row.reserve = reserve
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + reserve), -2)
    row.tick:ClearAllPoints()
    row.tick:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + reserve), 0)
    -- the main text ends left of the right-hand text (or the done tick)
    local inset = state == "done" and Pad() + math.max(44, Th.Size("badge") + 6) + reserve or RightInset(row.right, 6, reserve)
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", Pad() + 14 + Th.Size("badge") + 6, -1)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -inset, -1)
    -- main line height (one line, or two when the current step's text wraps). Measured with room for two
    -- lines (a set height can cut the measure), then the text gets exactly its line(s). The caller anchors
    -- the row first, so the width is known (v0.2 fix: a new row measured before it had a width came out one
    -- line high on login and its second line drew over the goal lines until the next refresh).
    local h = LH
    if current and (d.maxLines or 2) > 1 then
        row.text:SetHeight(LH * 2 - 1)
        local sh = row.text:GetStringHeight() or 0
        if sh > Th.FontSize("step") * 1.6 then h = LH * 2 end
    end
    row.text:SetHeight(h - 1)
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
        local gx, box = Pad() + 14 + Th.Size("badge") + 6, Th.Size("box")
        ln.fill:ClearAllPoints()
        ln.fill:SetPoint("TOPLEFT", row, "TOPLEFT", gx, -(h + (LG - box) / 2))
        ln.top = h
        ln.right:ClearAllPoints()
        ln.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + reserve), -h)
        ln.right:SetHeight(LG)
        ln.text:SetHeight(LG)
        if l.kind == "goal" then
            local g = l.g
            -- travel side goal still open: the kind icon (kill / loot / use) in the box's place; done = the tick.
            -- "+n more" line: no box at all. Both stay one line (cut, never wrapped).
            local icon = not g.done and not g.more and g.kind and SIDE_BADGE[g.kind]
            if icon then
                local b = K.BADGE[icon]
                Th.Glyph(ln.pin, b[1])
                ln.pin:SetVertexColor(Th.Color(b[2]))
            end
            ln.pin:SetShown(icon and true or false)
            ln.fill:SetShown(g.done)
            ln.tick:SetShown(g.done)
            ln.box:SetShown(not icon and not g.more)
            ln.box:SetVertexColor(Th.Color(g.done and "goalDoneEdge" or "goalBoxEmpty"))
            ln.text:SetText(g.text or "")
            if ln.text.SetWordWrap then ln.text:SetWordWrap(not (g.side or g.more)) end
            K.Color(ln.text, (g.done and "goalDone") or (g.more and "text.dim") or "goal")
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
            -- (the pin may have carried a side goal's icon in an earlier draw)
            Th.Glyph(ln.pin, "badge.goto")
            ln.pin:SetVertexColor(Th.Color("icon.goto"))
            if ln.text.SetWordWrap then ln.text:SetWordWrap(true) end
            ln.text:SetText(l.c.text or "")
            K.Color(ln.text, "coord")
            ln.right:SetText(l.c.dist or "")
            K.Color(ln.right, "text.dim")
        end
        PlaceLineText(row, ln)
        h = h + LG
    end
    for i = n + 1, #row.lines do ShowLine(row.lines[i], false) end
    row.coordLine = d.coord and row.lines[n] or nil
    row:SetHeight(h)
    return h
end

-- Updates only the distance on the current row's coordinate line (called by the arrow's ticker).
function R.SetDistance(row, text)
    if row and row.coordLine then
        row.coordLine.right:SetText(text or "")
        PlaceLineText(row, row.coordLine)
    end
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

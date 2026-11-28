-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Step rows and goal lines (the one window, 4f). A row = (number when the theme has a number column) + tile icon +
-- text (the window colours its verb) + right-hand info (coords / "in 2 levels" / done tick); the current step also
-- gets sub lines under its text ("for <quest>", the place line with the distance) and goal lines (tile + text +
-- count), the goal to do now tinted with an edge. States: "current", "upcoming" (dim by colour), "done".
-- Never SetAlpha on text: dimming is always a text colour.
--   ns.Rows.New(parent) -> row;  ns.Rows.Set(row, data) -> height
--   data = { number, tile (K.TILE kind), text, state, right, goals = { { text, have, need, done, kind } }, coord,
--            sub = { { text, right } } (lines under the text; the one with place = true gets the distance),
--            maxLines, boxed (no glow / bar of its own), focus (index of the goal to do now),
--            lean (the 3D view on the left: no number, no icon), leanX (where the text starts), leanH (the goal lines
--            start under this height: the 3D view's square), reserveRight (units kept free on the right),
--            tag = { kind, word } + target + fade + sep (a next step as one line, mock-up 4h) }
--   a goal may also carry kind ("kill" / "loot" / "use": its tile), side (its step), more ("+n more")
--   wait = { label, time, over } (v0.2.5, ns.Waits.Parts): the countdown line after the note, before the goals
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local R = {}
ns.Rows = R
-- side goal kind -> K.BADGE entry (old badge art: the map pins and the "side goals" self-check use it)
local SIDE_BADGE = { kill = "objective", loot = "collect", use = "useitem" }
R.SIDE_BADGE = SIDE_BADGE
-- goal kind -> tile kind
local GOAL_TILE = { kill = "kill", loot = "loot", use = "use", talk = "talk", ["goto"] = "goto" }
R.GOAL_TILE = GOAL_TILE

local function Pad() return Th.Size("pad") end
local function NumW() return Th.Size("numberCol") end
local function TileS(LH) return math.max(8, math.min(Th.Size("tile"), LH - 2)) end

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
    row.num:SetWidth(math.max(1, NumW()))
    row.num:SetPoint("TOPLEFT", row, "TOPLEFT", Pad() - 4, -3)
    -- the tile icon (row.badge keeps the old names: .disc = the tile, .glyph = its symbol)
    local tile = K.Tile(row, Th.Size("tile"))
    tile.disc, tile.glyph = tile.base, tile.sym
    row.badge = tile
    -- v0.2 fix (text over the NOW box): top anchors only on both sides plus a set height, so the text never
    -- centres itself in a tall row (a "RIGHT" point also pins the vertical middle) and never draws past its line(s)
    row.text = K.Text(row, "step", "text")
    row.text:SetJustifyV("TOP")
    row.text:SetHeight(Th.LineHeight("step") - 1)
    row.right = K.Text(row, "goal", "text.dim", "RIGHT")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -Pad(), -2)
    row.tick = K.Glyph(row, "done", Th.Size("badge"), "goalDone")
    row.tick:SetPoint("TOPRIGHT", row, "TOPRIGHT", -Pad(), 0)
    row.tick:Hide()   -- (never shown since the "tile only" pick, 2026-11-28; kept for older callers)
    row.lines = {}
    row.subs = {}
    -- a faint hairline at the top of a next step (mock-up 4h; not the first one: the divider is above it)
    row.sep = K.Fill(row, "ARTWORK", "divider")
    row.sep:SetHeight(K.Hair(1))
    row.sep:SetPoint("TOPLEFT", row, "TOPLEFT", Pad(), 0)
    row.sep:SetPoint("TOPRIGHT", row, "TOPRIGHT", -Pad(), 0)
    row.sep:Hide()
    return row
end

-- The framed verb tag of a next step (4h): 1 px frame + the verb in capitals, both in the step's colour
-- (created on first use; tinted per row, so a white fill with a vertex colour).
local function Tag(row)
    if row.tag then return row.tag end
    local tg = { edges = {} }
    tg.text = K.Text(row, "small", "text", "CENTER")
    for i = 1, 4 do
        local e = K.Fill(row, "ARTWORK", "white")
        tg.edges[i] = e
    end
    row.tag = tg
    return tg
end

-- beta.13 equal tags (plans\tag-width\, the user: "make all boxes for the next step the same size"): every verb
-- up to R.TAG_STD_LEN letters ("GO BACK") gets one box width, the widest of them MEASURED in the tag's own font and
-- size (so it follows the Text font and size settings); longer phrases ("SPEAK TO", "SET YOUR HEARTHSTONE") keep
-- their own wider box. Cached per font file + size + flags + verb list; a new font or size measures again.
R.TAG_STD_LEN = 7
R.TAG_PAD = 8
R.TAG_GAP = 6    -- clear room between a tag box's right border and the target text
R.TAG_VGAP = 4   -- a tag box is the line height minus this (centred: this much between two lines' boxes)
R.TAG_MIN_H = 6  -- (the smallest text size: the 4 px gap wins over a taller box)
local tagStd = {}
function R.TagWidth(fs)
    local file, size, flags = fs:GetFont()
    local UI = ns.UI
    local list = UI and UI.VerbList and UI.VerbList() or {}
    local key = tostring(file) .. "\1" .. tostring(size) .. "\1" .. tostring(flags) .. "\1" .. tostring(list)
    if tagStd.key == key then return tagStd.w end
    local keep = fs:GetText()
    local w, words = 0, { tostring(ns.L and ns.L.TAG_NOTE or "") }
    for _, v in ipairs(list) do words[#words + 1] = v[1] end
    for _, word in ipairs(words) do
        word = word:upper()
        if word ~= "" and #word <= R.TAG_STD_LEN then
            fs:SetText(word)
            w = math.max(w, math.ceil(fs:GetStringWidth() or 0))
        end
    end
    fs:SetText(keep)
    tagStd.key, tagStd.w = key, w + R.TAG_PAD
    R.tagMeasures = (R.tagMeasures or 0) + 1
    return tagStd.w
end

local function TagShown(row, on)
    local tg = row.tag
    if not tg then return end
    tg.text:SetShown(on)
    for _, e in ipairs(tg.edges) do e:SetShown(on) end
end

-- Cuts a one-line text with "..." until it fits w (the font string shows it as is). Returns the shown text.
-- A cut text never ends inside an icon "|T..|t" or an item link "|H..|h..|h" (beta.11 item pictures in the note):
-- it is cut back to before that escape (a half escape would show as raw text).
function R.Whole(s)
    local t = s:match("^(.*)|T[^|]*$") or s:match("^(.*)|T[^|]*|$")
    if t then s = t end
    local opens = select(2, s:gsub("|H", ""))
    local marks = select(2, s:gsub("|h", ""))
    if marks < opens * 2 then
        local last
        for p in s:gmatch("()|H") do last = p end
        if last then s = s:sub(1, last - 1) end
    end
    if s:sub(-1) == "|" then s = s:sub(1, -2) end
    return s
end

local function Cut(fs, text, w)
    fs:SetText(text)
    if w <= 0 or (fs:GetStringWidth() or 0) <= w then return text end
    local lo, hi, best = 0, #text, ""
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local s = text:sub(1, mid)
        -- (never cut inside a UTF-8 letter)
        while #s > 0 and s:byte(#s) >= 0x80 and s:byte(#s) < 0xC0 do s = s:sub(1, #s - 1) end
        while #s > 0 and s:byte(#s) >= 0xC0 do s = s:sub(1, #s - 1) end
        s = R.Whole(s)
        fs:SetText(s:gsub("%s+$", "") .. "...")
        if (fs:GetStringWidth() or 0) <= w then best = fs:GetText() lo = mid + 1 else hi = mid - 1 end
    end
    if best == "" then best = "..." end
    fs:SetText(best)
    return best
end
R.Cut = Cut
R.TARGET_MIN = 60   -- a next line's target text never gets less room than this (its right-hand text is cut first)

local function Faded(fs, key, a)
    local r, g, b, al = Th.Color(key)
    K.Color(fs, key)
    if a and a < 1 then fs:SetTextColor(r, g, b, (al or 1) * a) end
end

-- A sub line under the step text ("for <quest>", the place line): text + right-hand text (created on first use).
local function Sub(row, i)
    local s = row.subs[i]
    if s then return s end
    s = { text = K.Text(row, "goal", "sub"), right = K.Text(row, "goal", "text.dim", "RIGHT") }
    s.text:SetJustifyV("MIDDLE")
    s.right:SetJustifyV("MIDDLE")
    row.subs[i] = s
    return s
end

-- A goal / coordinate line inside a row (created on first use): its tinted background (the goal to do now / done),
-- the edge, and three tiles of which one shows: the kind tile (pin), the empty tile (box), the done tile (tick).
local function Line(row, i)
    local ln = row.lines[i]
    if ln then return ln end
    ln = {}
    ln.holder = CreateFrame("Frame", nil, row)
    ln.bg = K.Slice(row, "round", Th.Size("cornerSquare"), "goalNowBg", { rel = ln.holder, sub = 2 })
    if not ln.bg then
        local f = K.Fill(row, "BACKGROUND", "goalNowBg", 2)
        f:SetAllPoints(ln.holder)
        ln.bgFlat = f
    end
    ln.edge = K.Fill(row, "ARTWORK", "goalNowEdge")
    ln.edge:SetPoint("TOPLEFT", ln.holder, "TOPLEFT", 0, 0)
    ln.edge:SetPoint("BOTTOMLEFT", ln.holder, "BOTTOMLEFT", 0, 0)
    ln.edge:SetWidth(Th.Size("focusEdge"))
    local size = Th.Size("tile")
    ln.tile = K.Tile(row, size, 3)
    ln.pin = ln.tile.base
    ln.open = K.Tile(row, size, 3)
    K.SetTile(ln.open, "open")
    ln.box = ln.open.base
    ln.done = K.Tile(row, size, 3)
    K.SetTile(ln.done, "done")
    ln.tick, ln.fill = ln.done.base, ln.done.sym
    ln.open.base:SetAllPoints(ln.pin)
    ln.done.base:SetAllPoints(ln.pin)
    -- placed per line by R.Set (top anchors + the goal line's height, never a middle point)
    ln.text = K.Text(row, "goal", "goal")
    ln.text:SetJustifyV("MIDDLE")
    ln.right = K.Text(row, "goal", "text.dim", "RIGHT")
    ln.right:SetJustifyV("MIDDLE")
    -- the fold line ("3 done", one line for the finished goals): a caret after its text, the line clickable
    ln.caret = K.Glyph(row, "btn.caret", math.max(8, Th.Size("tile") - 2), "goalDone", "ARTWORK")
    ln.caret:Hide()
    ln.holder:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and ln.fold and row.onFold then row.onFold() return end
        -- an item goal line takes the mouse (its tooltip): clicks still reach the row (step menu, click)
        local f = not ln.fold and row:GetScript("OnMouseUp")
        if f then f(row, button) end
    end)
    -- beta.9 item pictures: hovering an item goal line shows the game's item tooltip
    ln.holder:SetScript("OnEnter", function(self)
        if ln.item and ns.ItemIcons then ns.Errors.Call("itemicons", ns.ItemIcons.ItemTip, self, ln.item) end
    end)
    ln.holder:SetScript("OnLeave", function() K.HideTooltip() end)
    row.lines[i] = ln
    return ln
end

-- The item icon of a goal line (created on first use), over its tile, edge trimmed.
-- beta.12 (the user: the icon "to the left side of the text like the little X we have for kills"): an item tile at
-- a line's left, the goal tile's size and spot; a small mouse holder over it shows the item tooltip, clicks reach
-- the row. key: "note" / "text". Created on first use; R.ItemTile(row, key, id, x, top, s) / R.HideItemTile.
function R.ItemTile(row, key, id, x, top, s)
    row.itemTiles = row.itemTiles or {}
    local t = row.itemTiles[key]
    if not t then
        t = { icon = row:CreateTexture(nil, "ARTWORK", nil, 5), hold = CreateFrame("Frame", nil, row) }
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.hold:SetAllPoints(t.icon)
        t.hold:EnableMouse(true)
        t.hold:SetScript("OnEnter", function(self)
            if t.id and ns.ItemIcons then ns.Errors.Call("itemicons", ns.ItemIcons.ItemTip, self, t.id) end
        end)
        t.hold:SetScript("OnLeave", function() K.HideTooltip() end)
        t.hold:SetScript("OnMouseUp", function(_, button)
            local f = row:GetScript("OnMouseUp")
            if f then f(row, button) end
        end)
        row.itemTiles[key] = t
    end
    t.id = id
    t.icon:SetTexture(ns.ItemIcons.Icon(id))
    t.icon:SetSize(s, s)
    t.icon:ClearAllPoints()
    t.icon:SetPoint("TOPLEFT", row, "TOPLEFT", x, -top)
    t.icon:Show()
    t.hold:Show()
    return t
end

function R.HideItemTile(row, key)
    local t = row.itemTiles and row.itemTiles[key]
    if t then t.id = nil t.icon:Hide() t.hold:Hide() end
end

local function ItemTex(row, ln)
    if ln.icon then return ln.icon end
    local ic = row:CreateTexture(nil, "ARTWORK", nil, 5)
    ic:SetAllPoints(ln.pin)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ln.icon = ic
    return ic
end

local function LineBg(ln, key)
    if ln.bg then
        K.SliceShown(ln.bg, key ~= nil)
        if key then K.TintSlice(ln.bg, key) end
    elseif ln.bgFlat then
        ln.bgFlat:SetShown(key ~= nil)
        if key then ln.bgFlat:SetColorTexture(Th.Color(key)) end
    end
end

local function ShowLine(ln, shown)
    for _, k in ipairs({ "text", "right" }) do ln[k]:SetShown(shown) end
    ln.holder:SetShown(shown)
    if not shown then
        ln.caret:Hide()
        ln.fold, ln.item = nil, nil
        if ln.icon then ln.icon:Hide() end
        if ln.waitIcon then ln.waitIcon:Hide() end
        ln.holder:EnableMouse(false)
        K.TileShown(ln.tile, false)
        K.TileShown(ln.open, false)
        K.TileShown(ln.done, false)
        ln.edge:Hide()
        LineBg(ln, nil)
    end
end

-- Room kept free on the right of a text for its right-hand text (count, distance, "in 2 levels"):
-- at least the usual 44 (none when there is no right-hand text in lean / goal-line mode), more when it is wider.
local function RightInset(rightFs, gap, reserve, min)
    local w = rightFs and rightFs:GetText() ~= nil and rightFs:GetText() ~= "" and (rightFs:GetStringWidth() or 0) or 0
    return Pad() + math.max(min or 44, w > 0 and math.ceil(w) + gap or 0) + (reserve or 0)
end

-- Where the main text starts: after the number and tile, or at leanX beside the 3D view.
local function TextX(row)
    if row.lean then return row.leanX or Pad() end
    return Pad() + NumW() + Th.Size("tile") + 6
end
R.TextX = TextX

-- Where goal lines start: under the 3D view at the row's left (full width), else in the text column.
local function GoalX(row)
    if row.lean then return Pad() end
    return TextX(row)
end
R.GoalX = GoalX

-- Does a line whose top is `top` (from the row's top) sit beside the 3D view? Only on a lean row, above the line
-- where the goals start under the view (row.leanH = the view's height in the row, + blockPad).
function R.BesideView(row, top)
    return (row.lean and row.leanH and top < row.leanH + Th.Size("blockPad")) and true or false
end

-- A goal / coordinate line's text: top anchors at the line's top (ln.top), clear of its right-hand text.
local function PlaceLineText(row, ln)
    local x = GoalX(row) + Th.Size("tile") + 5 + (ln.indent or 0)
    ln.text:ClearAllPoints()
    ln.text:SetPoint("TOPLEFT", row, "TOPLEFT", x, -ln.top)
    ln.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -RightInset(ln.right, 4, row.reserve, row.lean and 0 or nil), -ln.top)
end

local function PlaceSubText(row, s)
    s.text:ClearAllPoints()
    s.text:SetPoint("TOPLEFT", row, "TOPLEFT", TextX(row), -s.top)
    s.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -RightInset(s.right, 4, row.reserve, 0), -s.top)
end

-- Splits text into lines of the given widths (widths[i] for line i; as many lines as widths), by words, measured on
-- fs (single line); the last line is cut with "..." when the text doesn't fit. An item link is one word. Returns
-- the list of lines (1..#widths), cut.
function R.NoteFlow(fs, text, widths)
    local words = {}
    local kept = text:gsub("|H.-|h.-|h", function(l) return (l:gsub(" ", "\1")) end)
    for word in kept:gmatch("%S+") do words[#words + 1] = (word:gsub("\1", " ")) end
    local lines, k = {}, 0
    for li, w in ipairs(widths) do
        local rest = table.concat(words, " ", k + 1)
        if rest == "" then break end
        fs:SetText(rest)
        if w <= 0 or (fs:GetStringWidth() or 0) <= w then
            lines[li] = rest
            return lines, false
        end
        if li == #widths then
            lines[li] = Cut(fs, rest, w)
            return lines, true
        end
        local line, kk = "", k
        for i = k + 1, #words do
            local try = line == "" and words[i] or (line .. " " .. words[i])
            fs:SetText(try)
            if (fs:GetStringWidth() or 0) > w then break end
            line, kk = try, i
        end
        if kk == k then   -- one word wider than the line: cut it there
            lines[li] = Cut(fs, rest, w)
            return lines, true
        end
        lines[li], k = line, kk
    end
    return lines, false
end

-- beta.8 step notes: at most two lines of width w. Returns line1, line2 (or nil), cut.
function R.NoteLines(fs, text, w)
    local lines, cut = R.NoteFlow(fs, text, { w, w })
    return lines[1] or "", lines[2], cut
end

-- The note's most lines: all that fit beside the 3D view, then at most R.NOTE_BELOW under it (R.NOTE_MAX in all,
-- a guard for huge fonts / tiny ones).
R.NOTE_MAX, R.NOTE_BELOW = 10, 2

-- Lays out the note from height h (right under the step text); returns the new height. row.noteCut: the text was
-- cut. beta.15 (the user: "i want to move the grey text, "a nibbled-on book may drop""): the grey note sits right
-- under the step text, above the goals. A note line beside the 3D view (R.BesideView) wraps in the step text's
-- column (its item tile there too); lines below the view use the full width, text at the goal lines' text column
-- (tile at the goal tile's x). Without the view: the goal text column (beta.13 "Line up the grey note with the
-- text"; beta.14 bug: never pushed right of the view when it isn't beside it).
function R.Note(row, text, h, reserve, item)
    local note = row.note
    if not (text and item) then R.HideItemTile(row, "note") end
    if not text then
        row.noteCut, row.noteLines = nil, 0
        if note then for _, fs in ipairs(note) do fs:Hide() end end
        return h
    end
    if not note then note = {} row.note = note end
    local LG = Th.LineHeight("goal")
    local tileW = Th.Size("tile") + 5
    local rowW = row:GetWidth() or 0
    h = h + Th.Size("noteGap")
    -- each line's spot: beside the view (step text column) or below it (goal text column, full width)
    local xs, widths, below = {}, {}, 0
    for i = 1, R.NOTE_MAX do
        local beside = R.BesideView(row, h + (i - 1) * LG)
        if not beside then
            below = below + 1
            if below > R.NOTE_BELOW then break end
        end
        local x = beside and (TextX(row) + (item and tileW or 0)) or (GoalX(row) + tileW)
        xs[i], widths[i] = x, rowW - x - Pad() - (reserve or 0)
    end
    -- (FontStrings made only as needed: at least 2, as many as this note can use)
    for i = #note + 1, math.max(2, #widths) do
        local fs = K.Text(row, "goal", "note")
        fs:SetJustifyV("MIDDLE")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        fs:Hide()
        note[i] = fs
    end
    local lines, cut = R.NoteFlow(note[1], text, widths)
    row.noteCut = cut or nil
    if item then
        local s = TileS(LG)   -- (the goal tile's size helper: always the same as the kill sword)
        local beside = R.BesideView(row, h)
        R.ItemTile(row, "note", item, beside and TextX(row) or GoalX(row), h + (LG - s) / 2, s)
    end
    row.noteX = xs[1]
    row.noteLines = #lines
    for i, fs in ipairs(note) do
        local t = lines[i]
        if t then
            fs:SetText(t)
            K.Color(fs, "note")
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", row, "TOPLEFT", xs[i], -h)
            fs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + (reserve or 0)), -h)
            fs:SetHeight(LG)
            fs:Show()
            h = h + LG
        else
            fs:Hide()
        end
    end
    return h + Th.Size("noteGap")   -- (the same gap under it as above it, before the goals)
end

-- Lays out one row; returns its height.
function R.Set(row, d)
    local LH, LG = Th.LineHeight("step"), Th.LineHeight("goal")
    local state = d.state or "upcoming"
    local current = state == "current"
    row.step = d.step   -- v0.2 M3: the right-click step menu, hover and clicks
    -- lean (3D view on the left): the 3D view stands where the number and tile were
    local lean = d.lean and true or false
    row.lean = lean
    row.leanX = lean and d.leanX or nil
    row.leanH = lean and tonumber(d.leanH) or nil
    local numbered = NumW() > 0 and not lean
    row.num:SetShown(numbered)
    row.current, row.rightText = current, d.right
    -- d.boxed: the step block draws its own look; no glow / bar of the row's own
    row.glow:SetShown(current and not d.boxed)
    row.bar:SetShown(current and not d.boxed)
    row.num:SetText(numbered and d.number and tostring(d.number) or "")
    K.Color(row.num, current and "accentText" or "stepNumber")
    -- the tile never gets taller than the line (small fonts); centred in its column
    local ts = TileS(LH)
    local tile = row.badge
    -- icon review #7 (2026-11-28): a done row shows the green done tile (dimmed), not its dimmed kind tile (a dim
    -- grey-yellow "?" read like WoW's "quest not finished")
    K.SetTile(tile, state == "done" and "done" or (d.tile or "note"), state == "done")
    tile.base:SetSize(ts, ts)
    tile.base:ClearAllPoints()
    tile.base:SetPoint("TOPLEFT", row, "TOPLEFT", Pad() + NumW() + (Th.Size("tile") - ts) / 2, -math.max(0, (LH - ts) / 2))
    K.TileShown(tile, not lean)
    row.tick:SetSize(ts, ts)
    row.text:SetText(d.text or "")
    K.Color(row.text, (state == "done" and "done") or (current and "text") or "upcoming")
    local most = current and (d.maxLines or (lean and 4 or 3)) or 1
    row.text:SetWordWrap(most > 1)
    if row.text.SetMaxLines then row.text:SetMaxLines(most) end
    -- ui look check (2026-11-28, the user: "Tile only"): a done row's only tick is its done tile at the left
    row.tick:Hide()
    row.right:SetText(state ~= "done" and d.right or "")
    local reserve = tonumber(d.reserveRight) or 0
    row.reserve = reserve
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + reserve), -2)
    row.tick:ClearAllPoints()
    row.tick:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + reserve), 0)
    -- the main text ends left of the right-hand text; a done row has none (no tick either): the text gets the room
    local inset = state == "done" and Pad() + reserve or RightInset(row.right, 6, reserve)
    if current and (row.right:GetText() or "") == "" then inset = Pad() + reserve end
    row.text:ClearAllPoints()
    -- beta.12: the current step's first item as a tile at the text's left, only when the line has no step tile
    -- (next to the 3D view); otherwise the step tile stays and the item is just the hover link in the text
    local textX = TextX(row)
    local textItem = current and lean and d.textItem or nil
    if textItem then
        local s = TileS(LH)
        R.ItemTile(row, "text", textItem, textX, math.max(0, (LH - s) / 2), s)
        textX = textX + Th.Size("tile") + 5
    else
        R.HideItemTile(row, "text")
    end
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -1)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -inset, -1)
    -- main line height: measured with room for all its lines (a set height can cut the measure), then the text
    -- gets exactly its line(s). The caller anchors the row first, so the width is known (v0.2 fix).
    local h = LH
    if most > 1 then
        row.text:SetHeight(LH * most - 1)
        local sh = row.text:GetStringHeight() or 0
        local fsz = Th.FontSize("step")
        local n = 1
        for k = 2, most do if sh > fsz * (k - 0.4) then n = k end end
        h = LH * n
    end
    row.text:SetHeight(h - 1)
    -- sub lines under the text (current step): "for <quest>", the place line (its right text = the distance)
    local ns_ = 0
    row.coordLine = nil
    if current then
        for _, sd in ipairs(d.sub or {}) do
            ns_ = ns_ + 1
            local s = Sub(row, ns_)
            s.top = h
            s.text:SetText(sd.text or "")
            s.text:SetHeight(LG)
            s.right:SetText(sd.right or "")
            s.right:ClearAllPoints()
            s.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + reserve), -h)
            s.right:SetHeight(LG)
            s.text:Show()
            s.right:Show()
            PlaceSubText(row, s)
            if sd.place then row.coordLine = s end
            h = h + LG
        end
    end
    for i = ns_ + 1, #row.subs do
        row.subs[i].text:Hide()
        row.subs[i].right:Hide()
    end
    -- beta.15: the grey note right under the step text (beside the 3D view while there is room there)
    h = R.Note(row, current and d.note or nil, h, reserve, current and d.noteItem or nil)
    -- goal lines (under the 3D view when it shows: full width), then the coordinate line
    if current and lean and d.leanH then h = math.max(h, d.leanH + Th.Size("blockPad")) end
    local n = 0
    local lines = {}
    row.waitLine = nil
    -- v0.2.5 waits countdown: one line after the note, before the goals (label left, time right)
    local off = 0
    if current and d.wait then lines[1], off = { kind = "wait", w = d.wait }, 1 end
    if current then
        for _, gl in ipairs(d.goals or {}) do lines[#lines + 1] = { kind = "goal", g = gl } end
        if d.coord then lines[#lines + 1] = { kind = "coord", c = d.coord } end
    end
    local gx = GoalX(row)
    local tsg = TileS(LG)
    local focus = d.focus
    row.onFold = d.onFold
    for _, l in ipairs(lines) do
        n = n + 1
        local ln = Line(row, n)
        ShowLine(ln, true)
        ln.pin:SetSize(tsg, tsg)
        ln.pin:ClearAllPoints()
        -- (an opened fold shows its finished goals indented)
        ln.indent = l.kind == "goal" and l.g.indent and Th.Size("foldIndent") or 0
        ln.pin:SetPoint("TOPLEFT", row, "TOPLEFT", gx + ln.indent, -(h + (LG - tsg) / 2))
        ln.top = h
        ln.holder:ClearAllPoints()
        ln.holder:SetPoint("TOPLEFT", row, "TOPLEFT", gx - 4, -h)
        ln.holder:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() - 4 + reserve), -h)
        ln.holder:SetHeight(LG)
        ln.right:ClearAllPoints()
        ln.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + reserve), -h)
        ln.right:SetHeight(LG)
        ln.text:SetHeight(LG)
        if ln.waitIcon and l.kind ~= "wait" then ln.waitIcon:Hide() end
        if l.kind == "goal" then
            local g = l.g
            -- open goal with a kind: its tile; done: the done tile; plain open goal: the empty tile; "+n more": none
            local kindTile = not g.done and not g.more and g.kind and GOAL_TILE[g.kind]
            if kindTile then K.SetTile(ln.tile, kindTile) end
            K.TileShown(ln.tile, kindTile and true or false)
            K.TileShown(ln.done, g.done and true or false)
            K.TileShown(ln.open, not kindTile and not g.done and not g.more)
            -- beta.9 item pictures: an open goal about an item shows the item's icon instead of its tile
            local itemIcon = g.item and not g.done and not g.more and not g.fold and ns.ItemIcons
            if itemIcon then
                local ic = ItemTex(row, ln)
                ic:SetTexture(ns.ItemIcons.Icon(g.item))
                ic:Show()
                K.TileShown(ln.tile, false)
                K.TileShown(ln.open, false)
            elseif ln.icon then
                ln.icon:Hide()
            end
            ln.item = itemIcon and g.item or nil
            ln.text:SetText(g.text or "")
            if ln.text.SetWordWrap then ln.text:SetWordWrap(false) end
            local doneKey = g.indent and "goalDoneDim" or "goalDone"
            K.Color(ln.text, (g.done and doneKey) or (g.more and "text.dim") or "goal")
            if g.fold then
                ln.right:SetText(g.right or "")
            elseif g.need and g.need > 1 then
                ln.right:SetText(("%d/%d"):format(g.have or 0, g.need))
            else
                ln.right:SetText("")
            end
            K.Color(ln.right, g.fold and "text.dim" or (g.done and doneKey) or "goalCount")
            local isFocus = focus == n - off and not g.done and not g.more
            -- a goal that just finished flashes green before it folds in; the fold line and opened goals: no box
            local bg = (isFocus and "goalNowBg") or (g.flash and "goalFlashBg")
                or (g.done and not g.more and not g.fold and not g.indent and "goalDoneBg") or nil
            LineBg(ln, bg)
            ln.edge:SetShown(isFocus)
            -- the fold line: clickable, caret right of its text (pointing right = closed, down = open)
            ln.fold = g.fold and true or nil
            ln.holder:EnableMouse((g.fold or ln.item) and true or false)
            ln.caret:SetShown(g.fold and true or false)
            if g.fold then
                Th.Glyph(ln.caret, "btn.caret", g.open and "cw" or nil)
                ln.caret:ClearAllPoints()
                local tw = math.min(ln.text:GetStringWidth() or 0, 200)
                ln.caret:SetPoint("LEFT", row, "TOPLEFT", gx + Th.Size("tile") + 5 + tw + 4, -(h + LG / 2))
            end
        elseif l.kind == "wait" then
            -- the waits countdown (ui review #2): the hourglass glyph tinted color.wait while counting, the danger
            -- glyph once over; label in the goal colour (danger colour once over), the time at the right in the
            -- count colour; the window updates only the time each second (row.waitLine)
            ln.fold, ln.indent, ln.item = nil, 0, nil
            if ln.icon then ln.icon:Hide() end
            ln.caret:Hide()
            ln.holder:EnableMouse(false)
            K.TileShown(ln.tile, false)
            K.TileShown(ln.open, false)
            K.TileShown(ln.done, false)
            if not ln.waitIcon then
                ln.waitIcon = row:CreateTexture(nil, "ARTWORK", nil, 5)
                ln.waitIcon:SetAllPoints(ln.pin)
            end
            Th.Glyph(ln.waitIcon, l.w.over and "notice.danger" or "state.wait")
            ln.waitIcon:SetVertexColor(Th.Color(l.w.over and "notice.danger" or "wait"))
            ln.waitIcon:Show()
            if ln.text.SetWordWrap then ln.text:SetWordWrap(false) end
            ln.text:SetText(l.w.label or "")
            K.Color(ln.text, l.w.over and "notice.danger" or "goal")
            ln.right:SetText(l.w.time or "")
            K.Color(ln.right, "goalCount")
            LineBg(ln, nil)
            ln.edge:Hide()
            row.waitLine = ln
        else
            ln.fold, ln.indent, ln.item = nil, 0, nil
            if ln.icon then ln.icon:Hide() end
            ln.caret:Hide()
            ln.holder:EnableMouse(false)
            K.TileShown(ln.tile, true)
            K.SetTile(ln.tile, "goto")
            K.TileShown(ln.tile, true)
            K.TileShown(ln.open, false)
            K.TileShown(ln.done, false)
            if ln.text.SetWordWrap then ln.text:SetWordWrap(false) end
            ln.text:SetText(l.c.text or "")
            K.Color(ln.text, "coord")
            ln.right:SetText(l.c.dist or "")
            K.Color(ln.right, "text.dim")
            LineBg(ln, nil)
            ln.edge:Hide()
            row.coordLine = ln
        end
        PlaceLineText(row, ln)
        h = h + LG
    end
    for i = n + 1, #row.lines do ShowLine(row.lines[i], false) end
    -- 4h: a next step is one line: framed verb tag + target (cut with "..." before the coords), fading
    local tagged = state == "upcoming" and d.tag ~= nil
    row.tagged = tagged
    row.sep:SetShown(tagged and d.sep and true or false)
    if tagged then
        local a = tonumber(d.fade) or 1
        local key = "verb." .. tostring(d.tag.kind)
        -- (beta.13, the user: "Lighter blue and red text"): a theme may give next lines their own, lighter verb
        -- colour (color.next.<kind>), readable after the row fade; else the verb's own colour
        if Th.Has("color.next." .. tostring(d.tag.kind)) then key = "next." .. tostring(d.tag.kind) end
        if not Th.Has("color." .. key) then key = "upcoming" end
        local tg = Tag(row)
        TagShown(row, true)
        K.TileShown(tile, false)
        row.num:Hide()
        local std = R.TagWidth(tg.text)   -- (beta.13: one box width for every short verb, word centred)
        tg.text:SetText(d.tag.word or "")
        Faded(tg.text, key, a)
        local tw = math.max(std, math.ceil(tg.text:GetStringWidth() or 20) + R.TAG_PAD)
        -- (ui look check: LH - 4 tall and centred in the LH-high line, so 4 px between the boxes of two lines)
        local th = math.max(R.TAG_MIN_H, LH - R.TAG_VGAP)
        local x = Pad()
        tg.text:ClearAllPoints()
        tg.text:SetPoint("TOPLEFT", row, "TOPLEFT", x, -math.max(0, (LH - th) / 2))
        tg.text:SetSize(tw, th)
        local r, g, b, al = Th.Color(key)
        local e = tg.edges
        local hair = K.Hair(1)
        for i = 1, 4 do e[i]:ClearAllPoints() e[i]:SetVertexColor(r, g, b, (al or 1) * a * 0.8) end
        e[1]:SetPoint("TOPLEFT", tg.text, "TOPLEFT") e[1]:SetPoint("TOPRIGHT", tg.text, "TOPRIGHT") e[1]:SetHeight(hair)
        e[2]:SetPoint("BOTTOMLEFT", tg.text, "BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT", tg.text, "BOTTOMRIGHT") e[2]:SetHeight(hair)
        e[3]:SetPoint("TOPLEFT", tg.text, "TOPLEFT") e[3]:SetPoint("BOTTOMLEFT", tg.text, "BOTTOMLEFT") e[3]:SetWidth(hair)
        e[4]:SetPoint("TOPRIGHT", tg.text, "TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT", tg.text, "BOTTOMRIGHT") e[4]:SetWidth(hair)
        -- the target: after the tag, ends a gap before the coords; cut with "..." when too long
        -- (ui look check: at least R.TAG_GAP clear from the box's right border to the target's first letter)
        local tx = x + tw + hair + R.TAG_GAP
        -- (beta.12: no item picture on next lines, the user: "only show icons for active steps")
        local rw = (row.right:GetText() or "") ~= "" and math.ceil(row.right:GetStringWidth() or 0) or 0
        local gap = 8
        -- (messy-play fix) the target keeps at least R.TARGET_MIN; a too-long right-hand text is cut first
        local room = (row:GetWidth() or 0) - tx - Pad() - reserve
        if rw > 0 and room - rw - gap < R.TARGET_MIN then
            Cut(row.right, row.right:GetText(), math.max(1, room - gap - R.TARGET_MIN))
            rw = math.ceil(row.right:GetStringWidth() or 0)
        end
        local avail = room - (rw > 0 and rw + gap or 0)
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", tx, -1)
        row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(Pad() + reserve + (rw > 0 and rw + gap or 0)), -1)
        row.text:SetWordWrap(false)
        if row.text.SetMaxLines then row.text:SetMaxLines(1) end
        Cut(row.text, d.target or d.text or "", avail)
        Faded(row.text, key, a)
        Faded(row.right, "text.dim", a)
        row.text:SetHeight(LH - 1)
        h = LH
    else
        TagShown(row, false)
    end
    row:SetHeight(h)
    return h
end

-- Updates only the distance on the current row's place / coordinate line (called by the arrow's ticker).
function R.SetDistance(row, text)
    local ln = row and row.coordLine
    if not ln then return end
    ln.right:SetText(text or "")
    if ln.pin then PlaceLineText(row, ln) else PlaceSubText(row, ln) end
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

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The guide window. From the top: title bar (logo, route title, menu / small / lock / close), section
-- header with "step i/n", the notice line (always kept free in full mode), the "n done" chip, the fixed
-- step area (current step always the top row, then upcoming steps), the footer (back, progress, next).
-- Small mode keeps the same width: title bar, the current step and one "Next:" line (a notice replaces it).
-- States: none / finished / error / safe. Clamped to the screen; the position is saved per character
-- only after the player moves it. Opacity changes the panel alpha only (text stays at full alpha and
-- gets a shadow under 0.5). Esc never closes it (it isn't a UI panel).
--   ns.UI.Show(), Hide(), Toggle(), Refresh(), ResetPos(), IsShown(); ns.UI.frame and its parts
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local UI = { rows = {}, built = false, refreshes = 0 }
ns.UI = UI

local TITLE_H, FOOT_H = 22, 22
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -90, -200 }
local CHIP_MAX = 10

local function LH() return Th.LineHeight("step") end
local function Pad() return Th.Size("pad") end
local function L() return ns.L end

-- ------------------------------------------------------------------ sizes
function UI.Small() return ns.Settings.Get("small") end
function UI.AreaHeight(small) return Th.Size(small and "smallLines" or "stepLines") * LH() end
function UI.Height(small)
    if small then return TITLE_H + UI.AreaHeight(true) + Pad() end
    return TITLE_H + LH() * 3 + UI.AreaHeight(false) + FOOT_H + Pad()
end

-- ------------------------------------------------------------------ position (saved only when moved)
local function CanSave() return not ns.safeMode and not ns.DB.readOnly.char end

local function SavedPos()
    local m = ns.DB.char and type(ns.DB.char.modules) == "table" and ns.DB.char.modules.window
    if type(m) ~= "table" or type(m.point) ~= "string" or type(m.x) ~= "number" or type(m.y) ~= "number" then return nil end
    return m
end

function UI.ApplyPos()
    local f, parent = UI.frame, Co.UIParent()
    f:ClearAllPoints()
    local m = SavedPos()
    if m then
        f:SetPoint(m.point, parent, m.rel or m.point, m.x, m.y)
    else
        f:SetPoint(DEFAULT_POINT[1], parent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

function UI.SavePos()
    if not CanSave() then return end
    local point, _, rel, x, y = UI.frame:GetPoint(1)
    if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
    local m = ns.DB.Module("window", "char", 1)
    m.point, m.rel, m.x, m.y = point, rel or point, math.floor(x + 0.5), math.floor(y + 0.5)
end

function UI.ResetPos()
    local m = SavedPos()
    if m and CanSave() then m.point, m.rel, m.x, m.y = nil, nil, nil, nil end
    if UI.frame then UI.ApplyPos() end
    if ns.Arrow then ns.Arrow.ResetPos() end
end

-- ------------------------------------------------------------------ building
local function TitleBar(f)
    local tb = CreateFrame("Frame", nil, f)
    tb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    tb:SetHeight(TITLE_H)
    tb.bg = tb:CreateTexture(nil, "BACKGROUND", nil, 1)
    tb.bg:SetPoint("TOPLEFT", tb, "TOPLEFT", 1, -1)
    tb.bg:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", -1, 0)
    K.Gradient(tb.bg, "VERTICAL", "titleBottom", "titleTop")
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function()
        if not ns.Settings.Get("locked") then f:StartMoving() end
    end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        UI.SavePos()
    end)
    tb:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.Menu.Open(self, UI.MenuItems()) end
    end)
    tb.logo = tb:CreateTexture(nil, "ARTWORK")
    tb.logo:SetSize(16, 16)
    tb.logo:SetPoint("LEFT", tb, "LEFT", 4, 0)
    Th.Glyph(tb.logo, "logo")
    local s = Th.Size("button")
    tb.close = K.GlyphButton(tb, "btn.close", s, function() return L().TIP_CLOSE end, function() UI.Hide() end)
    tb.close:SetPoint("RIGHT", tb, "RIGHT", -3, 0)
    tb.lock = K.GlyphButton(tb, "btn.unlock", s, function()
        return ns.Settings.Get("locked") and L().TIP_UNLOCK or L().TIP_LOCK
    end, function()
        ns.Settings.Set("locked", not ns.Settings.Get("locked"))
    end)
    tb.lock:SetPoint("RIGHT", tb.close, "LEFT", -2, 0)
    tb.small = K.GlyphButton(tb, "btn.small", s, function()
        return UI.Small() and L().TIP_EXPAND or L().TIP_SMALL
    end, function()
        ns.Settings.Set("small", not UI.Small())
    end)
    tb.small:SetPoint("RIGHT", tb.lock, "LEFT", -2, 0)
    tb.menu = K.GlyphButton(tb, "btn.menu", s, function() return L().TIP_MENU end, function(self)
        if ns.Menu.IsOpen() then ns.Menu.Close() else ns.Menu.Open(self, UI.MenuItems(), { right = true }) end
    end)
    tb.menu:SetPoint("RIGHT", tb.small, "LEFT", -2, 0)
    tb.title = K.Text(tb, "title", "title")
    tb.title:SetPoint("LEFT", tb.logo, "RIGHT", 5, 0)
    tb.title:SetPoint("RIGHT", tb.menu, "LEFT", -4, 0)
    return tb
end

local function Header(f)
    local h = CreateFrame("Frame", nil, f)
    h:SetHeight(LH())
    h:SetPoint("TOPLEFT", f, "TOPLEFT", Pad(), -TITLE_H)
    h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Pad(), -TITLE_H)
    h.counter = K.Text(h, "small", "counter", "RIGHT")
    h.counter:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.text = K.Text(h, "header", "zone")
    h.text:SetPoint("LEFT", h, "LEFT", 0, 0)
    h.text:SetPoint("RIGHT", h.counter, "LEFT", -6, 0)
    h.line = K.Fill(h, "ARTWORK", "divider")
    h.line:SetHeight(K.Hair(1))
    h.line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    return h
end

local function NoticeLine(f)
    local n = CreateFrame("Button", nil, f)
    n:SetHeight(LH())
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetSize(Th.Size("badge"), Th.Size("badge"))
    n.icon:SetPoint("LEFT", n, "LEFT", 0, 0)
    n.text = K.Text(n, "goal", "notice")
    n.text:SetPoint("LEFT", n.icon, "RIGHT", 5, 0)
    n.btn = CreateFrame("Button", nil, n)
    n.btn:SetHeight(LH() - 2)
    n.btn:SetPoint("RIGHT", n, "RIGHT", 0, 0)
    K.Fill(n.btn, "BACKGROUND", "barTrack"):SetAllPoints()
    n.btn.text = K.Text(n.btn, "small", "accent", "CENTER")
    n.btn.text:SetPoint("CENTER")
    n.btn:SetScript("OnClick", function()
        local cur = UI.notice
        if cur and cur.button and cur.button.fn then ns.Errors.Call("ui", cur.button.fn) end
    end)
    n.text:SetPoint("RIGHT", n.btn, "LEFT", -4, 0)
    n:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    n:SetScript("OnClick", function(self, button)
        if button == "RightButton" and UI.notice then ns.Menu.Open(self, ns.Notice.MenuItems(UI.notice)) end
    end)
    n:SetScript("OnEnter", function(self) if UI.notice then K.Tooltip(self, UI.notice.text) end end)
    n:SetScript("OnLeave", K.HideTooltip)
    return n
end

local function Chip(f)
    local c = CreateFrame("Button", nil, f)
    c:SetHeight(LH())
    c.tick = K.Glyph(c, "done", Th.Size("box") + 2, "goalDone")
    c.tick:SetPoint("LEFT", c, "LEFT", 0, 0)
    c.text = K.Text(c, "small", "text.dim")
    c.text:SetPoint("LEFT", c.tick, "RIGHT", 4, 0)
    c.caret = K.Glyph(c, "btn.caret", Th.Size("box"), "text.dim")
    c.caret:SetPoint("LEFT", c.text, "RIGHT", 3, 0)
    c:SetScript("OnClick", function(self)
        if ns.Menu.IsOpen() then ns.Menu.Close() return end
        ns.Menu.Open(self, UI.ChipItems())
    end)
    return c
end

local function Footer(f)
    local ft = CreateFrame("Frame", nil, f)
    ft:SetHeight(FOOT_H)
    ft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", Pad(), Pad() / 2)
    ft:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Pad(), Pad() / 2)
    local s = Th.Size("navButton")
    ft.prev = K.GlyphButton(ft, "btn.prev", s, function() return L().TIP_BACK end, function() ns.Engine.Back() end)
    ft.prev:SetPoint("LEFT", ft, "LEFT", 0, 0)
    ft.next = K.GlyphButton(ft, "btn.next", s, function() return L().TIP_NEXT end, function() ns.Engine.Next() end)
    ft.next:SetPoint("RIGHT", ft, "RIGHT", 0, 0)
    ft.pct = K.Text(ft, "small", "counter", "RIGHT")
    ft.pct:SetWidth(32)
    ft.pct:SetPoint("RIGHT", ft.next, "LEFT", -4, 0)
    ft.track = K.Fill(ft, "ARTWORK", "barTrack")
    ft.track:SetHeight(Th.Size("bar"))
    ft.track:SetPoint("LEFT", ft.prev, "RIGHT", 6, 0)
    ft.track:SetPoint("RIGHT", ft.pct, "LEFT", -4, 0)
    ft.fill = ft:CreateTexture(nil, "ARTWORK", nil, 2)
    ft.fill:SetHeight(Th.Size("bar"))
    ft.fill:SetPoint("LEFT", ft.track, "LEFT", 0, 0)
    K.Gradient(ft.fill, "HORIZONTAL", "barFrom", "barTo")
    return ft
end

function UI.Build()
    if UI.built then return end
    UI.built = true
    local f = CreateFrame("Frame", nil, Co.UIParent())
    UI.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetWidth(Th.Size("width"))
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    K.Panel(f, true)
    UI.title = TitleBar(f)
    UI.header = Header(f)
    UI.noticeLine = NoticeLine(f)
    UI.chip = Chip(f)
    UI.area = CreateFrame("Frame", nil, f)
    UI.area:SetPoint("LEFT", f, "LEFT", 1, 0)
    UI.area:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    UI.nextLine = K.Text(UI.area, "goal", "upcoming")
    UI.nextLine:SetPoint("BOTTOMLEFT", UI.area, "BOTTOMLEFT", Pad(), 2)
    UI.nextLine:SetPoint("BOTTOMRIGHT", UI.area, "BOTTOMRIGHT", -Pad(), 2)
    UI.stateIcon = UI.area:CreateTexture(nil, "ARTWORK")
    UI.stateIcon:SetSize(32, 32)
    UI.stateIcon:SetPoint("TOP", UI.area, "TOP", 0, -LH())
    UI.stateText = K.Text(UI.area, "step", "text.dim", "CENTER")
    UI.stateText:SetWordWrap(true)
    UI.stateText:SetPoint("TOP", UI.stateIcon, "BOTTOM", 0, -6)
    UI.stateText:SetPoint("LEFT", UI.area, "LEFT", Pad() * 2, 0)
    UI.stateText:SetPoint("RIGHT", UI.area, "RIGHT", -Pad() * 2, 0)
    UI.footer = Footer(f)
    UI.ApplyPos()
    UI.Layout()
    UI.ApplyOpacity()
    f:Hide()
end

-- ------------------------------------------------------------------ layout (fixed heights)
function UI.Layout()
    local f, small = UI.frame, UI.Small()
    f:SetHeight(UI.Height(small))
    UI.header:SetShown(not small)
    UI.chip:SetShown(not small)
    UI.footer:SetShown(not small)
    UI.noticeLine:ClearAllPoints()
    UI.area:ClearAllPoints()
    UI.area:SetPoint("LEFT", f, "LEFT", 1, 0)
    UI.area:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    if small then
        UI.area:SetPoint("TOP", f, "TOP", 0, -TITLE_H)
        -- the notice takes the "Next:" line's place
        UI.noticeLine:SetPoint("BOTTOMLEFT", UI.area, "BOTTOMLEFT", Pad(), 0)
        UI.noticeLine:SetPoint("BOTTOMRIGHT", UI.area, "BOTTOMRIGHT", -Pad(), 0)
    else
        UI.noticeLine:SetPoint("TOPLEFT", f, "TOPLEFT", Pad(), -(TITLE_H + LH()))
        UI.noticeLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Pad(), -(TITLE_H + LH()))
        UI.chip:ClearAllPoints()
        UI.chip:SetPoint("TOPLEFT", f, "TOPLEFT", Pad(), -(TITLE_H + LH() * 2))
        UI.chip:SetWidth(Th.Size("width") / 2)
        UI.area:SetPoint("TOP", f, "TOP", 0, -(TITLE_H + LH() * 3))
    end
    UI.area:SetHeight(UI.AreaHeight(small))
    Th.Glyph(UI.title.small.icon, small and "btn.expand" or "btn.small")
    Th.Glyph(UI.title.lock.icon, ns.Settings.Get("locked") and "btn.lock" or "btn.unlock")
end

-- Panel alpha = opacity x the combat fade; texts get a shadow when the panel is very see-through.
function UI.ApplyOpacity()
    local a = ns.Settings.Get("opacity")
    if Co.InCombat() then a = a * (Th.Raw("motion.combatFade") or 0.5) end
    K.SetPanelAlpha(a)
    local shadow = a < 0.5
    if shadow ~= UI.shadow then
        UI.shadow = shadow
        K.RefreshFonts(shadow)
    end
end

-- ------------------------------------------------------------------ data for the rows
local function Goals(top, step)
    local out = {}
    local GS = ns.GameState
    if step.type == "objective" then
        if step.item then
            local need = step.count or 1
            local have = GS.ItemCount(step.item)
            out[1] = { text = L().GOAL_ITEMS, have = math.min(have, need), need = need, done = have >= need }
        else
            local qs = step.quest and GS.Quest(step.quest)
            if qs then
                local function Add(i)
                    local need = qs.need[i]
                    if not need then return end
                    local have = qs.have[i] or 0
                    out[#out + 1] = { text = qs.text and qs.text[i] or "", have = have, need = need, done = have >= need }
                end
                if ns.Packs.Len(step.obj) > 0 then
                    for _, i in ns.Packs.Each(step.obj) do Add(i) end
                else
                    for i = 1, #qs.need do Add(i) end
                end
            end
        end
    end
    for _, b in ipairs(top:Background()) do
        if b ~= step then out[#out + 1] = { text = top:Text(b), done = false } end
    end
    return out
end

local function Coord(step)
    if not (step.map and step.x and step.y) then return nil end
    return { text = ("%.1f, %.1f"):format(step.x * 100, step.y * 100), dist = UI.DistText(step) }
end

function UI.DistText(step)
    if not (step and step.map and step.x and step.y) then return nil end
    local d = ns.Geo.PlayerDistance(step.map, step.x, step.y)
    if not d then return nil end
    return ns.U.Fill(L().YARDS, { n = math.floor(d + 0.5) })
end

local function Wrap(field, v)
    if field == "quest" and v then return Th.Wrap("quest", v) end
    return v
end

-- "Done?" for display only: a travel step's Done() latches "reached" (it would finish a step the
-- player hasn't walked to yet), so the window only reads that latch.
local function ShownDone(top, s)
    if ns.StepTypes.Get(s.type).travel then return top.reached[s.id] == true end
    return top:Done(s)
end
UI.ShownDone = ShownDone

-- The upcoming steps after the current one (as many as could fit), in route order.
local function Upcoming(top, cur, max)
    local out = {}
    local n = top:Count()
    local j = top.pos
    while j <= n and #out < max do
        local s = top:Step(j)
        if s and s ~= cur and s.index ~= cur.index and top:Applicable(s) and not top:Skipped(s)
            and not ShownDone(top, s) and not s.whileUntil then
            out[#out + 1] = s
        end
        j = j + 1
    end
    return out
end

-- What the window shows now: { state = "guide" | "none" | "finished" | "error" | "safe", ... }.
function UI.Model()
    if ns.safeMode then return { state = "safe" } end
    local g = ns.Engine.Focused()
    if not g then return { state = "none" } end
    local cur, top = ns.Engine.Current()
    if not cur then return { state = "finished", guide = g } end
    local m = { state = "guide", guide = g, top = top, cur = cur }
    local route = top.route
    local sec = ns.Packs.Section(route, cur.index or top.pos)
    local secTitle = sec and ((ns.Locale.code == "daDK" and sec.da) or sec.title)
    -- the guide's name (pack header), not the route's mode name ("Normal")
    local h = route.header or g.header or {}
    m.title = (ns.Locale.code == "daDK" and h.da) or h.title or route.title or route.id
    m.section = secTitle or m.title
    -- numbers count only the steps for this character (rows for other classes / races don't count)
    m.pos = cur.index or top.pos
    local numbers, count = UI.Numbers(top)
    m.index, m.count = numbers[m.pos] or 1, count
    -- the distance shows once: on the coordinate line (the arrow keeps it fresh); only a step
    -- without a coordinate line could carry it on the right, and that one has no spot anyway
    local coord = Coord(cur)
    m.rows = { { step = cur, number = m.index, badge = K.BadgeKind(cur), text = top:Text(cur, Wrap), state = "current",
        right = not coord and UI.DistText(cur) or nil, goals = Goals(top, cur), coord = coord } }
    for _, s in ipairs(Upcoming(top, cur, 8)) do
        m.rows[#m.rows + 1] = { step = s, number = numbers[s.index], badge = K.BadgeKind(s), text = top:Text(s), state = "upcoming" }
    end
    m.done = math.max(0, m.index - 1)
    return m
end

-- Position -> shown number, over the steps that apply to this character; and how many apply.
-- Small mode: the current step must fit above the "Next:" / notice line. One text line, then as
-- many goal lines as fit (goals first, the coordinate line last). Returns a trimmed copy.
function UI.FitSmall(d, avail)
    local lh, lg = Th.LineHeight("step"), Th.LineHeight("goal")
    local room = math.max(0, math.floor((avail - lh) / lg))
    local out = {}
    for k, v in pairs(d) do out[k] = v end
    out.maxLines = 1
    local goals = {}
    for i = 1, math.min(#(d.goals or {}), room) do goals[i] = d.goals[i] end
    out.goals = goals
    if d.coord and #goals >= room then out.coord = nil end
    return out
end

-- Worked out on each refresh (conditions may read the level or quest state); refreshes come from
-- events, never per frame.
function UI.Numbers(top)
    local numbers, n = {}, 0
    for j = 1, top:Count() do
        local s = top:Step(j)
        if s and top:Applicable(s) then n = n + 1 end
        numbers[j] = math.max(n, 1)
    end
    return numbers, n
end

-- ------------------------------------------------------------------ drawing
local function Row(i)
    local r = UI.rows[i]
    if not r then
        r = ns.Rows.New(UI.area)
        UI.rows[i] = r
    end
    return r
end

local STATE_TEXT = { none = "STATE_NONE", finished = "STATE_FINISHED", error = "STATE_ERROR", safe = "STATE_SAFE" }
local STATE_GLYPH = { none = "state.none", finished = "state.finished", error = "state.error", safe = "state.error" }

local function DrawState(state)
    for _, r in ipairs(UI.rows) do r:Hide() end
    UI.nextLine:SetText("")
    UI.stateIcon:Show()
    Th.Glyph(UI.stateIcon, STATE_GLYPH[state])
    UI.stateIcon:SetVertexColor(Th.Color(state == "finished" and "accent" or "text.dim"))
    UI.stateText:Show()
    UI.stateText:SetText(L()[STATE_TEXT[state]])
    UI.title.title:SetText(L().TITLE)
    UI.header.text:SetText("")
    UI.header.counter:SetText("")
    UI.chip:Hide()
    UI.footer.fill:Hide()
    UI.footer.pct:SetText("")
    -- nothing to step through without a guide: no back / next
    UI.footer.prev:Hide()
    UI.footer.next:Hide()
end

local function DrawNotice()
    local n = ns.Notice.Top()
    UI.notice = n
    local line = UI.noticeLine
    if not n then
        line:Hide()
        return false
    end
    line:Show()
    line.text:SetText(ns.Notice.Cut(n.text))
    K.Color(line.text, n.kind == "danger" and "notice.danger" or "notice")
    local iconKey = n.icon or (n.kind == "danger" and "notice.danger" or "notice.tip")
    Th.Glyph(line.icon, iconKey)
    line.icon:SetVertexColor(Th.Color(n.kind == "danger" and "notice.danger" or "accent"))
    if n.button and n.button.text then
        line.btn:Show()
        line.btn.text:SetText(n.button.text)
        line.btn:SetWidth(math.max(40, (line.btn.text:GetStringWidth() or 30) + 12))
    else
        line.btn:Hide()
        line.btn:SetWidth(1)
    end
    return true
end

function UI.Refresh()
    if not UI.frame or not UI.frame:IsShown() then return end
    UI.refreshes = UI.refreshes + 1
    local small = UI.Small()
    local ok, m = ns.Errors.Call("ui", UI.Model)
    if not ok or type(m) ~= "table" then m = { state = "error" } end
    UI.model = m
    if m.state ~= "guide" then
        DrawState(m.state)
        DrawNotice()
        if ns.Arrow then ns.Arrow.SetTarget(nil) end
        return
    end
    UI.stateIcon:Hide()
    UI.stateText:Hide()
    UI.footer.prev:Show()
    UI.footer.next:Show()
    UI.title.title:SetText(m.title or L().TITLE)
    UI.header.text:SetText(m.section or "")
    UI.header.counter:SetText(ns.U.Fill(L().COUNTER, { i = m.index, n = m.count }))
    UI.chip:SetShown(not small and m.done > 0)
    UI.chip.text:SetText(ns.U.Fill(m.done == 1 and L().CHIP_DONE_ONE or L().CHIP_DONE_MANY, { n = m.done }))
    UI.chip:SetWidth((UI.chip.text:GetStringWidth() or 40) + Th.Size("box") * 2 + 12)
    -- rows: fill the fixed area from the top; a row that doesn't fit is hidden (the area never grows)
    local areaH = UI.AreaHeight(small)
    local reserve = small and Th.LineHeight("goal") or 0
    local y, shown = 0, 0
    local maxRows = small and 1 or #m.rows
    for i, d in ipairs(m.rows) do
        local r = Row(i)
        if i > maxRows then
            r:Hide()
        else
            if small and i == 1 then d = UI.FitSmall(d, areaH - reserve) end
            local h = ns.Rows.Set(r, d)
            if i > 1 and y + h > areaH - reserve then
                r:Hide()
            else
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", UI.area, "TOPLEFT", 0, -y)
                r:SetPoint("TOPRIGHT", UI.area, "TOPRIGHT", 0, -y)
                r:Show()
                y = y + h
                shown = shown + 1
            end
        end
    end
    for i = #m.rows + 1, #UI.rows do UI.rows[i]:Hide() end
    UI.shownRows = shown
    -- small mode: one "Next:" line under the current step (a notice takes its place)
    local nxt = m.rows[2]
    UI.nextLine:SetText(small and nxt and ns.U.Fill(L().NEXT_LINE, { text = nxt.text }) or "")
    local noticeShown = DrawNotice()
    if small and noticeShown then UI.nextLine:SetText("") end
    -- footer progress
    local frac = m.count > 0 and (m.index - 1) / m.count or 0
    local track = UI.footer.track:GetWidth() or 0
    UI.footer.fill:SetShown(frac > 0 and track > 0)
    UI.footer.fill:SetWidth(math.max(1, track * frac))
    UI.footer.pct:SetText(("%d%%"):format(math.floor(frac * 100 + 0.5)))
    -- finished-a-step flash on the new top row
    if UI.lastId and UI.lastId ~= m.cur.id and UI.lastStep and ShownDone(m.top, UI.lastStep) then ns.Rows.Flash(UI.rows[1]) end
    UI.lastId, UI.lastStep = m.cur.id, m.cur
    if ns.Arrow then ns.Arrow.SetTarget(m.cur) end
end

-- ------------------------------------------------------------------ menus
function UI.ChipItems()
    local items = {}
    local m = UI.model
    if not m or m.state ~= "guide" then return items end
    local top = m.top
    local j = m.pos - 1
    while j >= 1 and #items < CHIP_MAX do
        local s = top:Step(j)
        if s and top:Applicable(s) then
            local id = s.id
            items[#items + 1] = { text = top:Text(s), checked = ShownDone(top, s), fn = function() ns.Engine.SetCurrent(id) end }
        end
        j = j - 1
    end
    return items
end

function UI.MenuItems()
    local S = ns.Settings
    local items = {
        { text = L().MENU_SMALL, checked = S.Get("small"), fn = function() S.Set("small", not S.Get("small")) end },
        { text = L().MENU_LOCK, checked = S.Get("locked"), fn = function() S.Set("locked", not S.Get("locked")) end },
        { text = L().MENU_QUIET, checked = S.Get("quiet"), fn = function() S.Set("quiet", not S.Get("quiet")) end },
        { text = L().MENU_ARROW, checked = S.Get("arrow"), fn = function() S.Set("arrow", not S.Get("arrow")) end },
        { text = L().MENU_MOTION, checked = S.Get("reducedMotion"),
            fn = function() S.Set("reducedMotion", not S.Get("reducedMotion")) end },
    }
    -- opacity: four steps
    for _, v in ipairs({ 1, 0.8, 0.6, 0.4 }) do
        items[#items + 1] = { text = ns.U.Fill(L().MENU_OPACITY, { n = math.floor(v * 100) }),
            checked = math.abs(S.Get("opacity") - v) < 0.01, fn = function() S.Set("opacity", v) end }
    end
    items[#items + 1] = { text = L().MENU_RESETPOS, fn = UI.ResetPos }
    -- language: names in their own language (never translated); a change asks to reload
    local lang = S.Get("lang")
    items[#items + 1] = { text = "English", checked = lang ~= "da",
        fn = function() ns.Locale.Switch("en") end }
    items[#items + 1] = { text = "Dansk", checked = lang == "da",
        fn = function() ns.Locale.Switch("da") end }
    return items
end

-- ------------------------------------------------------------------ show / hide
-- keep = true: don't remember it (the self-test opens and closes the window for a moment).
function UI.Show(keep)
    UI.Build()
    UI.frame:Show()
    ns.Jobs.SetUIShown(true)
    if not ns.safeMode and not keep then ns.Settings.Set("shown", true) end
    UI.Refresh()
end

function UI.Hide(keep)
    if not UI.frame then return end
    UI.frame:Hide()
    ns.Jobs.SetUIShown(false)
    ns.Menu.Close()
    if not ns.safeMode and not keep then ns.Settings.Set("shown", false) end
    if ns.Arrow then ns.Arrow.SetTarget(nil) end
end

function UI.Toggle()
    if UI.frame and UI.frame:IsShown() then UI.Hide() else UI.Show() end
end

function UI.IsShown() return UI.frame ~= nil and UI.frame:IsShown() end

-- ------------------------------------------------------------------ wiring
local function OnSettings(_, key)
    if not UI.frame then return end
    if key == "small" or key == "locked" then
        UI.Layout()
        UI.Refresh()
    elseif key == "opacity" then
        UI.ApplyOpacity()
    elseif key == "reducedMotion" or key == "quiet" then
        UI.Refresh()
    end
end
ns.Bus.On("SettingsChanged", UI, OnSettings, "ui", 70)
ns.Bus.On("StepChanged", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("NoticeChanged", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("QuestsChanged", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("ItemsChanged", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("NameReady", UI, function() UI.Refresh() end, "ui", 70)
ns.Bus.On("CombatStarted", UI, function() if UI.frame then UI.ApplyOpacity() end end, "ui", 70)
ns.Bus.On("CombatEnded", UI, function() if UI.frame then UI.ApplyOpacity() end end, "ui", 70)
-- After login: open the window if it was open last time (default: open).
ns.Bus.On("Login", UI, function()
    if ns.Settings.Get("shown") then UI.Show() end
end, "ui", 80)

ns.Slash.SetDefault(function() UI.Toggle() end)
ns.Slash.Add("resetpos", function() UI.ResetPos() end, "HELP_RESETPOS")

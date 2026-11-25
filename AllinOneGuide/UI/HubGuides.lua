-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The main window's Guides page (2026-11-25, plans\main-window\plan.md): every installed guide pack as a card
-- (shield, title, faction tag, levels and steps, how far this character got, Active / Switch) plus the guides
-- we plan (ns.PlannedGuides, dimmed, "Coming in vX": text only, no links, tos). Search box, filter chips
-- (All / Alliance / Horde / Coming soon) and the order: guides that fit this character first, then by title.
-- Progress is read from the save without creating entries (DB.Guide would make one per card).
-- Switching away from a guide that's past its first step asks first ("Your place ... is kept").
--   ns.HubGuides.List(), .Progress(id), .Switch(id), .Layout(), .filter, .query, .cards
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local HG = { filter = "all", query = "", cards = {}, chips = {} }
ns.HubGuides = HG

local function L() return ns.L end
local P, E = ns.Packs, ns.Engine

-- How far this character got in a guide: step number, step count (nil, count when never opened).
-- routeId = nil: the pack's first route (the one OpenGuide opens).
function HG.Progress(id, routeId)
    local route = P.Open(id, routeId)
    if not route then return nil, 0 end
    local count = P.Count(route)
    local guides = ns.DB.char and ns.DB.char.guides
    local save = type(guides) == "table" and guides[E.Key(id, route.id)]
    local cur = type(save) == "table" and save.current
    local i = cur and P.IndexOf(route, cur)
    return i, count
end

local function FocusPack()
    local g = E.Focused()
    return g and g.key:match("^([^/]+)")
end

-- The cards' data: installed route packs, then planned ones that aren't installed.
function HG.List()
    E.UpdateCtx()
    local out, have = {}, {}
    local focus = FocusPack()
    for _, id in ipairs(P.List()) do
        local h = P.Header(id)
        if h and h.kind == "route" then
            have[id] = true
            local i, count = HG.Progress(id)
            local lv = type(h.levels) == "table" and h.levels or {}
            out[#out + 1] = { id = id, title = E.GuideTitle(id), faction = h.faction, a = lv[1], b = lv[2],
                steps = count, at = i, fits = E.Fits(id, false), active = id == focus,
                blurb = type(h.blurb) == "string" and h.blurb or nil }
        end
    end
    for _, g in ipairs(ns.PlannedGuides or {}) do
        if not have[g.id] then
            local lv = g.levels or {}
            out[#out + 1] = { id = g.id, title = g.title, faction = g.faction, a = lv[1], b = lv[2], planned = true,
                version = g.version, blurb = g.area }
        end
    end
    table.sort(out, function(x, y)
        if (x.planned or false) ~= (y.planned or false) then return not x.planned end
        if (x.fits or false) ~= (y.fits or false) then return x.fits == true end
        return tostring(x.title) < tostring(y.title)
    end)
    return out
end

local function Side(c)
    if c.faction == "Alliance" then return "alliance" elseif c.faction == "Horde" then return "horde" end
    return "both"
end

-- The filter and search on one card.
local function Shown(c)
    local f = HG.filter
    if f == "soon" and not c.planned then return false end
    if (f == "alliance" or f == "horde") and Side(c) ~= f and Side(c) ~= "both" then return false end
    local q = HG.query
    if q ~= "" then
        local hay = (tostring(c.title) .. " " .. tostring(c.blurb or "")):lower()
        if not hay:find(q, 1, true) then return false end
    end
    return true
end

-- Switching: asks first when the open guide is past its first step.
function HG.Switch(id)
    -- the open guide's own route (beta.3 fix: not always the pack's first one)
    local g = E.Focused()
    local pack, routeId = tostring(g and g.key or ""):match("^([^/]+)/(.+)$")
    local i = pack and HG.Progress(pack, routeId)
    local function Go()
        E.OpenGuide(id)
        HG.Layout()
    end
    if i and i > 1 then
        ns.Popups.Confirm({ kind = "switch", text = ns.U.Fill(L().DIALOG_SWITCH, { guide = E.GuideTitle(id) }),
            accept = Go })
    else
        Go()
    end
end

-- ------------------------------------------------------------------ cards
local function MakeCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(Th.Size("card"))
    c.bg = K.Fill(c, "BACKGROUND", "cardBg")
    c.bg:SetAllPoints()
    c.edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = K.Fill(c, "BORDER", "cardBorder")
        if i <= 2 then
            t:SetPoint(side .. "LEFT", c, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", c, side .. "RIGHT", 0, 0)
            t:SetHeight(K.Hair(1))
        else
            t:SetPoint("TOP" .. side, c, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, c, "BOTTOM" .. side, 0, 0)
            t:SetWidth(K.Hair(1))
        end
        c.edges[i] = t
    end
    local es = Th.Size("cardEmblem")
    -- full-colour shield (our own art, emblems.tga): no tint
    c.emblem = K.Glyph(c, "emblem.neutral", es)
    c.emblem:SetPoint("LEFT", c, "LEFT", 8, 0)
    c.title = K.Text(c, "step", "text")
    c.title:SetPoint("TOPLEFT", c.emblem, "TOPRIGHT", 10, 0)
    c.tag = K.Text(c, "small", "tagBoth")
    c.tag:SetPoint("LEFT", c.title, "RIGHT", 8, 0)
    c.line = K.Text(c, "goal", "text.dim")
    c.line:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -3)
    c.blurb = K.Text(c, "goal", "text.dim")
    c.blurb:SetPoint("TOPLEFT", c.line, "BOTTOMLEFT", 0, -2)
    c.button = K.Button(c, "", function(self) if self.id then HG.Switch(self.id) end end, { feature = "hub" })
    c.button:SetPoint("RIGHT", c, "RIGHT", -10, 0)
    c.state = K.Text(c, "goal", "accent", "RIGHT")
    c.state:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.title:SetPoint("RIGHT", c, "RIGHT", -110, 0)
    c.line:SetPoint("RIGHT", c, "RIGHT", -110, 0)
    c.blurb:SetPoint("RIGHT", c, "RIGHT", -110, 0)
    return c
end

local function Fill(card, c)
    card.data = c
    local side = Side(c)
    Th.Glyph(card.emblem, c.planned and "emblem.soon" or ("emblem." .. (side == "both" and "neutral" or side)))
    card.title:SetText(c.title or c.id)
    card.tag:SetText(L()["FACTION_" .. side:upper()] or "")
    K.Color(card.tag, side == "alliance" and "tagAlliance" or side == "horde" and "tagHorde" or "tagBoth")
    card.title:SetPoint("RIGHT", card, "RIGHT", -(130 + (card.tag:GetStringWidth() or 0)), 0)
    local lv = c.a and c.b
    if c.planned then
        card.line:SetText(lv and ns.U.Fill(L().GUIDES_LEVELS_SOON, { a = c.a, b = c.b }) or L().GUIDES_NOT_WRITTEN)
        card.button:Hide()
        card.button.id = nil
        card.state:SetText(ns.U.Fill(L().GUIDES_COMING, { v = c.version or "?" }))
        K.Color(card.state, "text.dim")
        card.state:Show()
        card:SetAlpha(0.6)
    else
        local done = (c.at and c.steps > 0) and math.floor((c.at - 1) * 100 / c.steps + 0.5) or nil
        local where = done and ns.U.Fill(L().GUIDES_DONE, { n = done }) or L().GUIDES_NOT_STARTED
        card.line:SetText(ns.U.Fill(L().GUIDES_LEVELS, { a = c.a or "?", b = c.b or "?", n = c.steps or 0 }) .. " - " .. where)
        card:SetAlpha(1)
        if c.active then
            card.button:Hide()
            card.button.id = nil
            card.state:SetText(L().GUIDES_ACTIVE)
            K.Color(card.state, "accent")
            card.state:Show()
        else
            card.state:Hide()
            card.button.id = c.id
            card.button:SetLabel(L().GUIDES_SWITCH)
            card.button:SetPrimary(c.fits)
            card.button:Show()
        end
    end
    card.blurb:SetText(c.blurb or "")
    for _, t in ipairs(card.edges) do
        t:SetColorTexture(Th.Color(c.active and "cardEdge" or "cardBorder"))
    end
end

-- Puts the shown cards under the controls; the page's height follows (scroll range).
function HG.Layout()
    local page = HG.page
    if not page then return 0 end
    local list = HG.List()
    local counts = { all = 0, alliance = 0, horde = 0, soon = 0 }
    local installed, planned = 0, 0
    for _, c in ipairs(list) do
        counts.all = counts.all + 1
        local s = Side(c)
        if s == "alliance" or s == "both" then counts.alliance = counts.alliance + 1 end
        if s == "horde" or s == "both" then counts.horde = counts.horde + 1 end
        if c.planned then counts.soon = counts.soon + 1 planned = planned + 1 else installed = installed + 1 end
    end
    for key, chip in pairs(HG.chips) do
        chip:SetLabel(ns.U.Fill(L()["GUIDES_" .. key:upper()], { n = counts[key] }))
        chip:SetOn(HG.filter == key)
    end
    local y, n = HG.top, 0
    local gap = 6
    for _, c in ipairs(list) do
        if Shown(c) then
            n = n + 1
            local card = HG.cards[n]
            if not card then
                card = MakeCard(page)
                HG.cards[n] = card
            end
            Fill(card, c)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
            card:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -y)
            card:Show()
            y = y + Th.Size("card") + gap
        end
    end
    for i = n + 1, #HG.cards do HG.cards[i]:Hide() end
    HG.none:SetShown(n == 0)
    HG.none:ClearAllPoints()
    HG.none:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    if n == 0 then y = y + Th.LineHeight("step") + 6 end
    HG.count:ClearAllPoints()
    HG.count:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y + 4))
    HG.count:SetText(ns.U.Fill(L().GUIDES_COUNT, { n = installed, m = planned }))
    HG.shown = n
    local h = y + 4 + math.max(Th.LineHeight("goal"), HG.count:GetStringHeight() or 0) + 6
    if ns.Hub.current == "guides" then ns.Hub.SetHeight("guides", h) end
    return h
end

local FILTERS = { "all", "alliance", "horde", "soon" }

function HG.Build(parent, width)
    -- (HG.page is set last: the search box's first text change must not lay out a half-built page)
    HG.page, HG.cards, HG.chips = nil, {}, {}
    HG.search = K.SearchBox(parent, L().GUIDES_SEARCH, function(text)
        HG.query = strtrim(text):lower()
        if HG.page == parent then HG.Layout() end
    end, "hub")
    HG.search:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    HG.search:SetText(HG.query)
    HG.sort = K.Text(parent, "goal", "text.dim", "RIGHT")
    HG.sort:SetPoint("RIGHT", parent, "TOPRIGHT", -4, -(HG.search:GetHeight() / 2))
    HG.sort:SetText(L().GUIDES_SORT)
    local y = HG.search:GetHeight() + 8
    local x = 0
    for _, key in ipairs(FILTERS) do
        local chip = K.Chip(parent, "", function()
            HG.filter = key
            HG.Layout()
        end, "hub")
        chip:SetLabel(ns.U.Fill(L()["GUIDES_" .. key:upper()], { n = 99 }))
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        x = x + chip:GetWidth() + 6
        HG.chips[key] = chip
    end
    HG.top = y + Th.LineHeight("step") + 6 + 10
    HG.none = K.Text(parent, "step", "text.dim")
    HG.none:SetText(L().GUIDES_NONE_MATCH)
    HG.count = K.Text(parent, "goal", "text.dim")
    HG.count:SetWordWrap(true)
    HG.count:SetWidth(width - 4)
    HG.width = width
    HG.page = parent
    return HG.Layout()
end

ns.Hub.AddPage("guides", { title = "HUB_GUIDES", icon = "badge.goto", order = 5,
    build = function(parent, width) return HG.Build(parent, width) end,
    refresh = function() HG.Layout() end })

ns.Slash.Add("guides", function()
    if not ns.Hub.Open("guides") then ns.Print(ns.U.Fill(L().GUIDE_LIST, { list = (E.GuideList()) })) end
end, "HELP_GUIDES", { main = true })

-- the open guide changed somewhere else (title menu, /aog guide): the Active card follows
ns.Bus.On("StepChanged", HG, function()
    if ns.Hub.IsShown() and ns.Hub.current == "guides" and HG.page then HG.Layout() end
end, "hub", 90)

-- Self-test: every installed route pack has a card on the list, at most one is Active, planned ones aren't
-- installed, and a shown page has its cards laid out.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "guides", fn = function(h)
    h.Count()
    local list = HG.List()
    local active, installed = 0, 0
    for _, c in ipairs(list) do
        if c.active then active = active + 1 end
        if not c.planned then installed = installed + 1 end
        if c.planned and P.Header(c.id) then h.Problem("guides: " .. c.id .. " is installed and planned") end
    end
    local packs = 0
    for _, id in ipairs(P.List()) do
        local hd = P.Header(id)
        if hd and hd.kind == "route" then packs = packs + 1 end
    end
    if installed ~= packs then h.Problem(("guides: %d cards for %d guides"):format(installed, packs)) end
    if active > 1 then h.Problem("guides: " .. active .. " cards say Active") end
    if HG.page and ns.Hub.current == "guides" and ns.Hub.IsShown() then
        local want = 0
        for _, c in ipairs(list) do if Shown(c) then want = want + 1 end end
        if HG.shown ~= want then h.Problem(("guides: %d cards shown, %d expected"):format(HG.shown or 0, want)) end
    end
    h.Info(("guides: %d installed, %d planned"):format(installed, #list - installed))
end }

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2: the Hub's "Quest items" page: every quest-starting or quest item in the bags with ONE advice
-- (Engine\BagQuests.lua). Read only: the player deletes or banks items themselves.
--   ns.HubBag.Fill(child) (re-fills the open page), .rows (the line pool, for tests)
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local HB = { rows = {}, ICON = 18 }
ns.HubBag = HB

local function L() return ns.L end

local function Row(parent, i)
    local r = HB.rows[i]
    if r and r.parent == parent then return r end
    r = { parent = parent }
    r.icon = parent:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(HB.ICON, HB.ICON)
    r.name = K.Text(parent, "goal", "text")
    r.advice = K.Text(parent, "goal", "accent")
    r.why = K.Text(parent, "goal", "text.dim")
    r.why:SetWordWrap(true)
    HB.rows[i] = r
    return r
end

-- Fills the page from the current advice; returns its height.
function HB.Fill(child)
    if not child then return 0 end
    local width = child:GetWidth() or 300
    local list = ns.BagQuests.List()
    child.head = child.head or K.Text(child, "header", "zone")
    child.head:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    child.head:SetText(L().QI_TITLE)
    local y = Th.LineHeight("header") + 6
    child.note = child.note or K.Text(child, "goal", "text.dim")
    child.note:SetWordWrap(true)
    child.note:SetWidth(width)
    child.note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    child.note:SetText(#list == 0 and L().QI_EMPTY or L().QI_NOTE)
    y = y + math.max(Th.LineHeight("goal"), child.note:GetStringHeight() or 0) + 10
    for i, a in ipairs(list) do
        local r = Row(child, i)
        r.icon:SetTexture(ns.Compat.ItemIcon(a.item) or 134400)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r.name:ClearAllPoints()
        r.name:SetPoint("TOPLEFT", child, "TOPLEFT", HB.ICON + 6, -y)
        r.name:SetText(ns.Compat.ItemName(a.item) or ("#" .. a.item))
        r.advice:ClearAllPoints()
        r.advice:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
        r.advice:SetText(L()[ns.BagQuests.LABEL[a.kind]])
        K.Color(r.advice, ns.BagQuests.COLOR[a.kind])
        y = y + Th.LineHeight("goal") + 2
        r.why:ClearAllPoints()
        r.why:SetWidth(width - HB.ICON - 6)
        r.why:SetPoint("TOPLEFT", child, "TOPLEFT", HB.ICON + 6, -y)
        r.why:SetText(ns.BagQuests.Why(a))
        y = y + math.max(Th.LineHeight("goal"), r.why:GetStringHeight() or 0) + 8
        for _, part in ipairs({ r.icon, r.name, r.advice, r.why }) do part:Show() end
    end
    for i = #list + 1, #HB.rows do
        local r = HB.rows[i]
        if r.parent == child then for _, part in ipairs({ r.icon, r.name, r.advice, r.why }) do part:Hide() end end
    end
    child:SetHeight(y + 8)
    HB.shown = #list
    return y + 8
end

ns.Hub.AddPage("questitems", { title = "HUB_QUESTITEMS", icon = "badge.useitem", order = 55,
    build = function(child) return HB.Fill(child) end,
    refresh = function(child) HB.Fill(child) end })

-- new advice while the page is open: fill it again
ns.Bus.On("BagQuestsChanged", HB, function()
    local p = ns.Hub.pages and ns.Hub.pages.questitems
    if p and p.child and ns.Hub.IsShown() and ns.Hub.current == "questitems" then
        ns.Errors.Call("hub", HB.Fill, p.child)
    end
end, "hub")

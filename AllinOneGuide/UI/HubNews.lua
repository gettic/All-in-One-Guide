-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M5: the Hub's "What's new" page: at most 5 bullets for this version (locale keys NEWS_1..NEWS_5;
-- the release replaces them each version). Once per new version the notice line says so, with a button
-- that opens this page; on a first install nothing is said (account module `news`, seen = version).
--   ns.HubNews.Bullets(), .Check() (the notice), .MAX
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local HN = { MAX = 5 }
ns.HubNews = HN

local function L() return ns.L end

function HN.Bullets()
    local out = {}
    for i = 1, HN.MAX do
        local t = L()["NEWS_" .. i]
        if type(t) == "string" and t ~= "" then out[#out + 1] = t end
    end
    return out
end

local function Build(parent, width)
    local head = K.Text(parent, "header", "zone")
    head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    head:SetText(L().NEWS_TITLE)
    local y = Th.LineHeight("header") + 8
    for _, text in ipairs(HN.Bullets()) do
        local dot = K.Glyph(parent, "badge.disc", 6, "accent")
        dot:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -(y + 5))
        local fs = K.Text(parent, "goal", "text")
        fs:SetWordWrap(true)
        fs:SetWidth(width - 14)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y)
        fs:SetText(text)
        y = y + math.max(Th.LineHeight("goal"), fs:GetStringHeight() or 0) + 6
    end
    return y + 8
end

-- Once per new version: a hint with a button to this page. Never on a first install, never in safe mode.
function HN.Check()
    if ns.safeMode or ns.DB.readOnly.account or ns.Test.quietFirstRun then return false end
    local m = ns.DB.Module("news", "account", 1)
    local v = tostring(ns.version)
    if m.seen == v then return false end
    -- detect by version, not by the module: v0.1 saves have no `news` module but do have a dbVersion stamp
    local first = m.seen == nil and ns.DB.freshAccount ~= false
    m.seen = v
    if first then return false end
    ns.Notice.Push({ id = "news", kind = "tip", text = L().NEWS_NOTICE, source = "hub",
        button = { text = L().NEWS_SHOW, fn = function()
            ns.Notice.Remove("news")
            ns.Hub.Open("news")
        end } })
    return true
end

ns.Hub.AddPage("news", { title = "HUB_NEWS", icon = "hub.news", order = 70, build = Build })
ns.Bus.On("Login", HN, function() ns.Errors.Call("hub", HN.Check) end, "hub", 95)

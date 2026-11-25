-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M5: the Hub's About page: what the addon is, the version, the GPL notice, where the source for this
-- version is (the matching tag), credits (only the free sources we use; the full list is CREDITS.txt), and
-- copyable links. No links asking for money of any kind (tos fix, Policy rule 5).
--   ns.HubAbout.SourceLink(), .IssuesLink(), .page
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local HA = { REPO = "https://github.com/gettic/All-in-One-Guide" }
ns.HubAbout = HA

local function L() return ns.L end

-- The source for exactly this version: the release tag (vX.Y.Z or vX.Y.Z-beta.N).
function HA.SourceLink()
    local v = tostring(ns.version or "?")
    if v:match("^%d+%.%d+%.%d+") then return HA.REPO .. "/tree/v" .. v end
    return HA.REPO
end
function HA.IssuesLink() return HA.REPO .. "/issues" end

local function Para(parent, y, width, text, font, color)
    local fs = K.Text(parent, font or "goal", color or "text")
    fs:SetWordWrap(true)
    fs:SetWidth(width)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    fs:SetText(text)
    return y + math.max(Th.LineHeight(font or "goal"), fs:GetStringHeight() or 0) + 8, fs
end

-- the shared text button (UIKit, look review #5)
local function LinkButton(parent, text, link)
    return K.Button(parent, text, function() ns.Popups.Copy(text, link()) end, { feature = "hub" })
end

local function Build(parent, width)
    local p = {}
    HA.page = p
    local logo = parent:CreateTexture(nil, "ARTWORK")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    Th.Glyph(logo, "logo")
    p.name = K.Text(parent, "title", "title")
    p.name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
    p.name:SetText(ns.TITLE)
    p.version = K.Text(parent, "goal", "counter")
    p.version:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -4)
    local y = Para(parent, 58, width, L().ABOUT_LINE)
    y = Para(parent, y, width, L().ABOUT_LICENCE, "goal", "text.dim")
    y = Para(parent, y, width, L().ABOUT_SOURCE, "goal", "text.dim")
    p.source = LinkButton(parent, L().ABOUT_COPY_SOURCE, HA.SourceLink)
    p.source:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.issues = LinkButton(parent, L().ABOUT_COPY_ISSUES, HA.IssuesLink)
    y = y + Th.LineHeight("step") + 18
    -- the second button wraps below when two don't fit side by side (the Hub's minimum width)
    if p.source:GetWidth() + p.issues:GetWidth() + 10 > width then
        p.issues:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y - 10))
        y = y + Th.LineHeight("step") + 8
    else
        p.issues:SetPoint("LEFT", p.source, "RIGHT", 10, 0)
    end
    y = Para(parent, y, width, L().ABOUT_CREDITS, "goal", "text.dim")
    y = Para(parent, y, width, L().ABOUT_BLIZZARD, "small", "text.dim")
    return y + 8
end

ns.Hub.AddPage("about", { title = "HUB_ABOUT", icon = "hub.about", order = 65, build = Build, refresh = function()
    HA.page.version:SetText(ns.U.Fill(L().ABOUT_VERSION, { v = ns.version }))
end })

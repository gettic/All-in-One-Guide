-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.3: the Hub's "Game data" page (/aog data): what the game data recording (Data\Gather.lua) keeps on your PC and
-- what it never keeps, the "Don't record" switch (tos T3a), counts per kind, the exact lines (copy box) and
-- "Delete recorded data" (asks once). Sharing is the Addon Manager's choice: named once, as a plain fact (tos T6).
--   ns.HubData.Open(), .Update(), .Delete(), .Show(), .page{ off, counts, list, show, delete }
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
local HD = {}
ns.HubData = HD

local function L() return ns.L end

local function Para(parent, y, width, text, color)
    local fs = K.Text(parent, "goal", color or "text")
    fs:SetWordWrap(true)
    fs:SetWidth(width)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    fs:SetText(text)
    return y + math.max(Th.LineHeight("goal"), fs:GetStringHeight() or 0) + 8, fs
end

function HD.Open() ns.Hub.Open("data") end

-- "kind: n" lines, most first
function HD.KindLines()
    local c = ns.Gather.Counts()
    local list = {}
    for k, n in pairs(c) do list[#list + 1] = { k = k, n = n } end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.k < b.k end)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = ("%s: %d"):format(L()["DATA_KIND_" .. e.k:upper()] or e.k, e.n) end
    return out
end

function HD.Show()
    local text = ns.Gather.Text()
    ns.Popups.Copy(L().DATA_SHOW_TITLE, text ~= "" and text or L().DATA_NONE)
end

function HD.Delete()
    local p = HD.page
    if ns.Gather.Clear() then
        ns.Print(L().DATA_DELETED)
        if p then p.delete:SetLabel(L().DATA_DELETE) end
    elseif p then
        p.delete:SetLabel(L().DATA_DELETE_ASK)
    end
    HD.Update()
end

-- Fills the changing parts; the page grows with the list.
function HD.Update()
    local p = HD.page
    if not p then return end
    p.off:Set(not ns.Settings.Get("gatherData"))
    local _, total = ns.Gather.Counts()
    p.counts:SetText(total == 0 and L().DATA_NONE or ns.U.Fill(L().DATA_COUNTS, { n = total, p = #ns.Gather.Pages() }))
    p.list:SetText(table.concat(HD.KindLines(), "\n"))
    local h = p.listY + math.max(0, p.list:GetStringHeight() or 0) + 12
    ns.Hub.SetHeight("data", h)
    return h
end

local function Build(parent, width)
    local p = {}
    HD.page = p
    p.title = K.Text(parent, "header", "zone")
    p.title:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    p.title:SetText(L().DATA_TITLE)
    local y = Th.LineHeight("header") + 6
    y = Para(parent, y, width, L().DATA_WHAT)
    y = Para(parent, y, width, L().DATA_ALSO)
    y = Para(parent, y, width, L().DATA_NEVER, "text.dim")
    y = Para(parent, y, width, L().DATA_SHARE, "text.dim")
    p.off = K.Choice(parent, L().DATA_OFF, function(b)
        ns.Settings.Set("gatherData", b.on == true)   -- ticked = don't record: the click turns it the other way
        HD.Update()
    end, false, "hub")
    p.off:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.off:SetWidth(width)
    y = y + Th.LineHeight("step") + 12
    p.show = K.Button(parent, L().DATA_SHOW, HD.Show, { feature = "hub" })
    p.show:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.delete = K.Button(parent, L().DATA_DELETE, HD.Delete, { feature = "hub" })
    y = y + Th.LineHeight("step") + 18
    if p.show:GetWidth() + p.delete:GetWidth() + 10 > width then
        p.delete:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y - 10))
        y = y + Th.LineHeight("step") + 8
    else
        p.delete:SetPoint("LEFT", p.show, "RIGHT", 10, 0)
    end
    p.counts = K.Text(parent, "goal", "accent")
    p.counts:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    y = y + Th.LineHeight("goal") + 6
    p.list = K.Text(parent, "goal", "text.dim")
    p.list:SetWordWrap(true)
    p.list:SetWidth(width)
    p.list:SetJustifyH("LEFT")
    p.list:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.listY = y
    return y + Th.LineHeight("goal") * 4
end

-- Added only while the recording is switched on (ns.GATHER, Data\Gather.lua: G.Enable)
function HD.Register()
    if HD.registered then return end
    HD.registered = true
    ns.Hub.AddPage("data", { title = "HUB_DATA", icon = "badge.note", order = 58, build = Build,
        refresh = function() HD.Update() end })
end

-- the switch changed elsewhere (settings page): the page follows
ns.Bus.On("SettingsChanged", HD, function(_, key)
    if key == "gatherData" and HD.page and ns.Hub.IsShown() and ns.Hub.current == "data" then HD.Update() end
end, "hub")

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M5: the Hub (FR-26): one frame with a left nav and pages. Pages register themselves:
--   ns.Hub.AddPage(id, { title = locale key, icon = slot key, order = n, build = fn(parent) -> height,
--                        refresh = fn(), action = fn() (a nav row that does something instead of a page) })
-- Opens on the side of the screen away from the guide window, clamped; Esc closes it (UISpecialFrames).
-- Size: 600 x 420, smaller on small screens (min 420 x 300); the page area scrolls (mouse wheel) when a
-- page is taller. Nav overflow: when the rows don't fit, the last row becomes "More" with the rest.
--   ns.Hub.Open(id), .Close(), .Toggle(id), .IsShown(), .Show(id), .current, .frame, .navButtons
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
-- (the title bar's height is the theme's size.title, shared with the guide window: look review #5)
local Hub = { pages = {}, list = {}, navButtons = {}, W = 600, H = 420, MIN_W = 420, MIN_H = 300, NAV_W = 150,
    ROW_H = 24 }
ns.Hub = Hub

local function L() return ns.L end

function Hub.AddPage(id, def)
    def.id = id
    def.order = def.order or 50
    Hub.pages[id] = def
    Hub.list = {}
    for _, p in pairs(Hub.pages) do Hub.list[#Hub.list + 1] = p end
    table.sort(Hub.list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
    if Hub.frame then Hub.Nav() end
end

-- ------------------------------------------------------------------ building
local function NavButton(i)
    local b = Hub.navButtons[i]
    if b then return b end
    local f = Hub.frame
    b = CreateFrame("Button", nil, f.nav)
    b:SetHeight(Hub.ROW_H)
    b:SetPoint("TOPLEFT", f.nav, "TOPLEFT", 0, -(i - 1) * Hub.ROW_H)
    b:SetPoint("TOPRIGHT", f.nav, "TOPRIGHT", 0, -(i - 1) * Hub.ROW_H)
    b.hover = K.Fill(b, "BACKGROUND", "buttonHoverBg")
    b.hover:SetAllPoints()
    b.hover:Hide()
    -- the open page (look review #6, variant A): a light box + a thin accent bar on the left
    b.selBg = K.Fill(b, "BACKGROUND", "navSelected", 1)
    b.selBg:SetAllPoints()
    b.selBg:Hide()
    b.bar = K.Fill(b, "ARTWORK", "navBar")
    b.bar:SetWidth(Th.Size("navBar"))
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.bar:Hide()
    b.icon = K.Glyph(b, "hub.about", Th.Size("navButton"), "button")
    b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
    b.text = K.Text(b, "step", "text")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b:SetScript("OnEnter", function(self)
        self.hover:SetShown(not self.sel)
        if not self.sel then
            K.Tint(self.icon, "buttonHover")
            K.Color(self.text, "buttonHover")
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover:Hide()
        Hub.NavLook(self)
    end)
    b:SetScript("OnClick", function(self) ns.Errors.Call("hub", Hub.NavClick, self) end)
    Hub.navButtons[i] = b
    return b
end

-- A nav row's look: open page = box + bar + accent icon and text; else plain.
function Hub.NavLook(b)
    local sel = b.sel and true or false
    b.selBg:SetShown(sel)
    b.bar:SetShown(sel)
    K.Color(b.text, sel and "accent" or "text")
    K.Tint(b.icon, sel and "accent" or "button")
end

function Hub.NavClick(b)
    if b.more then
        local items = {}
        for _, p in ipairs(b.more) do
            items[#items + 1] = { text = L()[p.title] or p.id, fn = function() Hub.Show(p.id) end }
        end
        ns.Menu.Open(b, items)
        return
    end
    local p = b.page
    if not p then return end
    if p.action then p.action() return end
    Hub.Show(p.id)
end

-- The nav rows; when they don't fit, the last one is "More" (a menu with the rest).
function Hub.Nav()
    local f = Hub.frame
    local fit = math.max(1, math.floor(f.nav:GetHeight() / Hub.ROW_H))
    local n = #Hub.list
    local shown = n <= fit and n or fit - 1
    for i = 1, shown do
        local b, p = NavButton(i), Hub.list[i]
        b.page, b.more = p, nil
        b.text:SetText(L()[p.title] or p.id)
        Th.Glyph(b.icon, p.icon or "hub.about")
        b.sel = Hub.current == p.id
        Hub.NavLook(b)
        b:Show()
    end
    local used = shown
    if shown < n then
        used = shown + 1
        local b = NavButton(used)
        b.page, b.more = nil, {}
        for i = shown + 1, n do b.more[#b.more + 1] = Hub.list[i] end
        b.text:SetText(L().HUB_MORE)
        Th.Glyph(b.icon, "btn.caret")
        b.sel = false
        for _, p in ipairs(b.more) do if p.id == Hub.current then b.sel = true end end
        Hub.NavLook(b)
        b:Show()
    end
    for i = used + 1, #Hub.navButtons do Hub.navButtons[i]:Hide() end
    Hub.navRows, Hub.navFit = used, fit
end

local function Size()
    local p = Co.UIParent()
    local pw, ph = p:GetWidth(), p:GetHeight()
    local w = math.max(Hub.MIN_W, math.min(Hub.W, pw - 40))
    local h = math.max(Hub.MIN_H, math.min(Hub.H, ph - 80))
    return w, h
end

function Hub.Build()
    if Hub.frame then return Hub.frame end
    -- named only for Blizzard's Esc list (UISpecialFrames)
    local f = CreateFrame("Frame", "AllinOneGuideHub", Co.UIParent())
    Hub.frame = f
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    K.Panel(f)
    -- the shared title bar (look review #5; drag to move)
    f.titleBar = K.TitleBar(f, { drag = true, feature = "hub",
        close = function() Hub.Close() end, closeTip = function() return L().TIP_CLOSE_HUB end })
    -- nav
    f.nav = CreateFrame("Frame", nil, f)
    f.nav:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(Th.Size("title") + 4))
    f.nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 4)
    f.nav:SetWidth(Hub.NAV_W)
    f.navLine = K.Fill(f, "ARTWORK", "divider")
    f.navLine:SetWidth(K.Hair(1))
    f.navLine:SetPoint("TOPLEFT", f.nav, "TOPRIGHT", 0, 0)
    f.navLine:SetPoint("BOTTOMLEFT", f.nav, "BOTTOMRIGHT", 0, 0)
    -- page area: a scroll frame with one child per page
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", f.nav, "TOPRIGHT", 10, 0)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta) ns.Errors.Call("hub", Hub.Scroll, delta) end)
    f.scroll = sf
    -- a slim scroll thumb on the right, only while the page is taller than the area (look review #2)
    local tw = Th.Size("thumb")
    f.track = K.Fill(f, "ARTWORK", "thumbTrack")
    f.track:SetWidth(tw)
    f.track:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
    f.track:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
    f.thumb = K.Fill(f, "ARTWORK", "thumb", 1)
    f.thumb:SetWidth(tw)
    f.track:Hide()
    f.thumb:Hide()
    K.CloseOnEsc("AllinOneGuideHub")
    f:Hide()
    return f
end

-- Mouse wheel: 40 units per notch, inside the page's height.
function Hub.Scroll(delta)
    local f, p = Hub.frame, Hub.pages[Hub.current]
    if not (f and p and p.child) then return end
    local max = math.max(0, (p.height or 0) - f.scroll:GetHeight())
    local v = math.max(0, math.min(max, f.scroll:GetVerticalScroll() - delta * 40))
    f.scroll:SetVerticalScroll(v)
    Hub.Thumb()
end

-- The scroll thumb: shown only when the open page is taller than the page area; its size is the shown
-- part, its place the scroll position. Returns shown, thumb height, offset from the top (for the tests).
function Hub.Thumb()
    local f, p = Hub.frame, Hub.pages[Hub.current]
    if not (f and f.thumb) then return false end
    local view = f.scroll:GetHeight() or 0
    local total = p and p.child and p.height or 0
    if view <= 0 or total <= view + 1 then
        f.track:Hide()
        f.thumb:Hide()
        return false
    end
    local th = math.max(16, math.floor(view * view / total))
    local max = total - view
    local v = math.max(0, math.min(max, f.scroll:GetVerticalScroll() or 0))
    local off = math.floor((view - th) * v / max + 0.5)
    f.thumb:SetHeight(th)
    f.thumb:ClearAllPoints()
    f.thumb:SetPoint("TOPLEFT", f.track, "TOPLEFT", 0, -off)
    f.track:Show()
    f.thumb:Show()
    return true, th, off
end

-- Placement: away from the guide window (left half when the guide sits on the right, and the other way).
function Hub.Place()
    local f, p = Hub.frame, Co.UIParent()
    local w, h = Size()
    f:SetSize(w, h)
    local x = 0
    local gw = ns.UI and ns.UI.frame
    if gw and gw:IsShown() then
        local gx = gw:GetCenter()
        local s = gw:GetEffectiveScale() / p:GetEffectiveScale()
        local cx = p:GetWidth() / 2
        if gx then
            local side = (gx * s > cx) and -1 or 1
            x = side * math.max(0, math.min(cx - w / 2 - 10, w / 2 + 20))
        end
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", p, "CENTER", x, 20)
end

-- Shows one page (built on first use).
function Hub.Show(id)
    local f = Hub.Build()
    local p = Hub.pages[id] or Hub.list[1]
    if not p then return false end
    if p.action then p.action() return true end
    for _, other in pairs(Hub.pages) do if other.child and other ~= p then other.child:Hide() end end
    local width = math.max(200, f:GetWidth() - Hub.NAV_W - 22)
    if not p.child then
        p.child = CreateFrame("Frame", nil, f.scroll)
        p.child:SetWidth(width)
        p.child:SetHeight(10)
        local ok, height = ns.Errors.Call("hub", p.build, p.child, width)
        p.height = ok and tonumber(height) or 10
        p.child:SetHeight(p.height)
    end
    p.child:SetWidth(width)
    f.scroll:SetScrollChild(p.child)
    f.scroll:SetVerticalScroll(0)
    p.child:Show()
    Hub.current = p.id
    f.titleBar.title:SetText(ns.TITLE .. " - " .. (L()[p.title] or p.id))
    if p.refresh then ns.Errors.Call("hub", p.refresh, p.child) end
    Hub.Nav()
    Hub.Thumb()
    return true
end

-- A new look (font size, contrast): page heights were measured with the old fonts, so every built page
-- is dropped and the open one is built again (look review #4). Old children are hidden and let go.
function Hub.Rebuild()
    local f = Hub.frame
    if not f then return false end
    for _, p in pairs(Hub.pages) do
        if p.child then
            p.child:Hide()
            p.child = nil
            p.height = nil
        end
    end
    if f:IsShown() and Hub.current then Hub.Show(Hub.current) end
    return true
end
ns.Bus.On("LookChanged", Hub, function() Hub.Rebuild() end, "hub", 80)

function Hub.Open(id)
    if ns.safeMode then return false end
    local f = Hub.Build()
    Hub.Place()
    f:Show()
    Hub.Show(id or Hub.current or (Hub.list[1] and Hub.list[1].id))
    return true
end

function Hub.Close() if Hub.frame then Hub.frame:Hide() end end
function Hub.IsShown() return Hub.frame ~= nil and Hub.frame:IsShown() end
function Hub.Toggle(id)
    if Hub.IsShown() and (not id or Hub.current == id) then Hub.Close() else Hub.Open(id) end
end

-- the settings page is Blizzard's panel: a nav row that opens it
Hub.AddPage("settings", { title = "MENU_SETTINGS", icon = "hub.settings", order = 90, action = function()
    Hub.Close()
    ns.SettingsUI.Open()
end })

-- Self-test: every page is registered, and the Hub fits this screen.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "hub", fn = function(h)
    h.Count()
    for _, id in ipairs({ "report", "about", "news", "settings" }) do
        if not Hub.pages[id] then h.Problem("hub: page " .. id .. " missing") end
    end
    local w, hh = Size()
    local p = Co.UIParent()
    if w > p:GetWidth() or hh > p:GetHeight() then h.Problem(("hub: %dx%d does not fit"):format(w, hh)) end
    -- the scroll thumb shows exactly when the open page is taller than the page area
    local f, cur = Hub.frame, Hub.pages[Hub.current]
    -- one title bar height for the guide window, the Hub and the dialogs (look review #5)
    local want = Th.Size("title")
    local bars = { f and f.titleBar, ns.UI and ns.UI.title, ns.Popups.frame and ns.Popups.frame.titleBar,
        ns.Popups.copy and ns.Popups.copy.titleBar }
    for i = 1, 4 do
        local tb = bars[i]
        if tb and math.abs((tb:GetHeight() or 0) - want) > 0.5 then h.Problem("hub: a title bar isn't " .. want .. " high") end
    end
    -- the open page's nav row is marked (look review #6)
    if f and f:IsShown() and cur and not cur.action then
        local marked = false
        for _, b in ipairs(Hub.navButtons) do if b:IsShown() and b.sel and b.bar:IsShown() then marked = true end end
        if not marked then h.Problem("hub: the open page isn't marked in the nav") end
    end
    if f and f:IsShown() and cur and cur.child then
        local taller = (cur.height or 0) > (f.scroll:GetHeight() or 0) + 1
        if (Hub.Thumb() and true or false) ~= taller then h.Problem("hub: scroll thumb doesn't match the page height") end
    end
    h.Info(("hub: %d pages, %dx%d"):format(#Hub.list, w, hh))
end }

ns.Slash.Add("hub",function(arg) Hub.Toggle(arg ~= "" and arg or nil) end, "HELP_HUB")

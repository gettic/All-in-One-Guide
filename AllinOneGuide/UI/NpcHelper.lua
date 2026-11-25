-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- NPC talk helper (plans\npc-talk-helper\plan.md). In NPC windows (gossip list, quest greeting) the quest rows
-- your route takes get a small tag ("Route: step 14", "Hand in: step 9", "Later guide"); with the "dim" setting
-- the others are faded. The accept window gets one line under it ("On your route: step 14, ~450 XP").
-- Display only (tos): it never clicks, accepts, declines, selects or closes anything, and every row stays
-- clickable (dimming is SetAlpha on the plain, non-secure row; our tags take no mouse). Blizzard code is only
-- hooked through ns.Hooks (hooksecurefunc / HookScript); gossip rows are followed through the ScrollBox's own
-- OnInitializedFrame event (ScrollUtil.AddInitializedFrameCallback; the plan's "plan B": a per-row Setup hook
-- misses rows the ScrollBox makes on scroll). Our state sits in weak-key tables, never in Blizzard's frames;
-- our tag / line are our own frames parented to Blizzard's rows / the accept panel.
--   ns.NpcHelper.Mode()                  "off" / "mark" / "dim"
--   ns.NpcHelper.Answer(q, kind)         kind "available" / "active" -> { state, n, xp, guide, why } or nil
--   ns.NpcHelper.Hook()                  at Login: the gossip, greeting and accept-window hooks
local _, ns = ...
local Co, K, Th = ns.Compat, ns.UIKit, ns.Theme
local FEATURE = "npchelper"
local WEAK = { __mode = "k" }
local NT = {
    tags = setmetatable({}, WEAK),       -- Blizzard row -> our tag frame
    dimmed = setmetatable({}, WEAK),     -- Blizzard rows we faded (set back to 1 when not needed)
    rowQuest = setmetatable({}, WEAK),   -- Blizzard row -> { q, kind } last applied (for a setting change)
    greet = setmetatable({}, WEAK),      -- greeting rows we touched
    cache = {},
    stats = { rows = 0, lines = 0, answers = 0 },
}
ns.NpcHelper = NT

-- Gossip row types (Blizzard_UIPanels_Game\Shared\GossipFrameShared.lua: GOSSIP_BUTTON_TYPE_*)
NT.ACTIVE, NT.AVAILABLE = 4, 5

function NT.Mode()
    if ns.safeMode or not ns.Feature.IsOn(FEATURE) then return "off" end
    local ok, v = pcall(ns.Settings.Get, "npcHelper")
    return ok and v or "off"
end

-- ------------------------------------------------------------------ the answer for one quest
local function Contains(list, i)
    for _, b in ipairs(list or {}) do if b == i then return true end end
    return false
end

-- The step number the guide window shows for index i of guide g (UI.Numbers), else the route index.
local function Number(g, i)
    local UI = ns.UI
    if UI and UI.Numbers then
        local ok, nums = pcall(UI.Numbers, g)
        if ok and type(nums) == "table" and nums[i] then return nums[i] end
    end
    return i
end

-- Looks at the accept (available) or turn-in (active) steps of quest q in guide g.
-- Returns "route", index  /  "skipped", why  /  nil (no such step that applies).
local function InGuide(g, q, kind)
    local e = g:QuestSteps()[q]
    local list = e and (kind == "active" and e.turnin or e.accept)
    if not list or #list == 0 then return nil end
    local start = g:GroupStart(g.pos)
    local skipped
    for _, i in ipairs(list) do
        local s = g:Step(i)
        if s and g:Applicable(s, true) then
            local why = g:SkipReason(s)
            if why then
                skipped = skipped or why
            elseif not g:Done(s) then
                if i >= start or Contains(g.bg, i) then return "route", i end
                skipped = skipped or "behind"
            end
        end
    end
    if skipped then return "skipped", skipped end
    return nil
end

local function XpOf(g, q)
    local e = g:QuestSteps()[q]
    for _, i in ipairs(e and e.turnin or {}) do
        local s = g:Step(i)
        if s and type(s.xp) == "number" then return s.xp end
    end
    local BQ = ns.BagQuests
    local info = BQ and BQ.QuestInfo and BQ.QuestInfo(q)
    return info and type(info.xp) == "number" and info.xp or nil
end

local function GuideName(route)
    local h = route and ns.Packs.Header(route.packId) or {}
    return h.title or (route and route.title) or (route and route.packId) or "?"
end

-- The quest in another installed route that fits this character (a later guide), or nil.
local function Later(q, focusRoute)
    local BQ = ns.BagQuests
    local info = BQ and BQ.QuestInfo and BQ.QuestInfo(q)
    if not info then return nil end
    local E = ns.Engine
    for _, r in ipairs({ info.turnin and info.route, info.acceptRoute }) do
        if r and r ~= focusRoute and r.packId and r.packId ~= "detour" and E.Fits and E.Fits(r.packId) then
            return { state = "later", guide = GuideName(r), xp = type(info.xp) == "number" and info.xp or nil }
        end
    end
    return nil
end

-- What our guides say about quest q at this NPC. nil = say nothing (no guide open, helper off).
function NT.Answer(q, kind)
    if type(q) ~= "number" or Co.IsSecret(q) or q <= 0 then return nil end
    local E = ns.Engine
    local g = E and E.Focused and E.Focused()
    if not g then return nil end
    local key = q .. ":" .. kind
    local hit = NT.cache[key]
    if hit ~= nil then return hit or nil end
    NT.stats.answers = NT.stats.answers + 1
    -- the deepest detour first (what the window shows), then its parents
    local chain, x = {}, g
    while x do
        table.insert(chain, 1, x)
        x = x.child
    end
    local a, skipped
    for _, gd in ipairs(chain) do
        local st, v = InGuide(gd, q, kind)
        if st == "route" then
            a = { state = kind == "active" and "turnin" or "route", n = Number(gd, v), xp = XpOf(gd, q) }
            break
        elseif st == "skipped" and not skipped then
            skipped = { state = "skipped", why = v }
        end
    end
    a = a or skipped or Later(q, g.route) or { state = "none" }
    NT.cache[key] = a
    return a
end

function NT.Clear() NT.cache = {} end

-- ------------------------------------------------------------------ texts
local function Fill(key, fields) return ns.U.Fill(ns.L[key], fields) end
local WHY = { skip = "NPC_WHY_SKIP", notdoing = "NPC_WHY_NOTDOING", na = "NPC_WHY_NA", behind = "NPC_WHY_BEHIND" }

-- Tag text + colour key for a row (nil = no tag). short = the narrow form for a row with a long title.
function NT.TagText(a, short)
    if not a then return nil end
    local s = short and "_SHORT" or ""
    if a.state == "route" then return Fill("NPC_TAG_ROUTE" .. s, { n = a.n }), "npcRoute" end
    if a.state == "turnin" then return Fill("NPC_TAG_TURNIN" .. s, { n = a.n }), "npcRoute" end
    if a.state == "later" then return ns.L["NPC_TAG_LATER" .. s], "npcLater" end
    if a.state == "skipped" then return ns.L["NPC_TAG_SKIPPED" .. s], "npcDim" end
    return nil
end

-- A guide name in the accept line is cut to this many characters (tester beta.4 #2: the XP part stays visible).
NT.GUIDE_MAX = 32

-- The accept window's line + colour key.
function NT.LineText(a)
    if not a then return nil end
    local xp = a.xp and ns.Locale and ns.Locale.Number and ns.Locale.Number(a.xp) or a.xp
    if a.state == "route" or a.state == "turnin" then
        if xp then return Fill("NPC_LINE_ROUTE_XP", { n = a.n, xp = xp }), "npcRoute" end
        return Fill("NPC_LINE_ROUTE", { n = a.n }), "npcRoute"
    end
    if a.state == "later" then
        a = { guide = (ns.U.Utf8Cut(a.guide or "?", NT.GUIDE_MAX)) }
        if xp then return Fill("NPC_LINE_LATER_XP", { guide = a.guide, xp = xp }), "npcLater" end
        return Fill("NPC_LINE_LATER", { guide = a.guide }), "npcLater"
    end
    if a.state == "skipped" then
        return Fill("NPC_LINE_SKIPPED", { why = ns.L[WHY[a.why] or "NPC_WHY_SKIP"] }), "npcDim"
    end
    return ns.L.NPC_LINE_NONE, "npcDim"
end

-- A row is faded only in "dim" mode, only for a quest that isn't on the route (skipped / none).
function NT.Dims(a, mode)
    return mode == "dim" and a ~= nil and (a.state == "none" or a.state == "skipped")
end

-- ------------------------------------------------------------------ the row tags
local function MakeTag(row)
    local t = CreateFrame("Frame", nil, row)
    t:EnableMouse(false)        -- clicks go to Blizzard's row underneath
    t:SetHeight(14)
    t:SetPoint("RIGHT", row, "RIGHT", -NT.TAG_INSET, 0)
    t.bg = K.Fill(t, "BACKGROUND", "npcTagBg")
    t.bg:SetAllPoints()
    t.text = K.Text(t, "small", "npcRoute", "CENTER")
    t.text:SetPoint("CENTER", t, "CENTER", 0, 0)
    -- the narrowest mark: a thin bar at the row's very right edge (Blizzard's title text ends 5 short of it)
    t.bar = t:CreateTexture(nil, "ARTWORK")
    t.bar:SetAllPoints()
    t.bar:Hide()
    t:Hide()
    return t
end

-- Tag placement (tester beta.4 #1: the tag must never sit on the quest title). Room = row width minus where
-- Blizzard's title text ends; we only READ the row and its font string (GetLeft / GetWidth / GetStringWidth),
-- never move or resize them.
NT.TAG_INSET, NT.TAG_GAP, NT.BAR_W = 2, 6, 3
function NT.FreeRoom(row)
    local fs = type(row.GetFontString) == "function" and row:GetFontString() or nil
    local rw = row:GetWidth()
    if type(fs) ~= "table" or type(rw) ~= "number" or Co.IsSecret(rw) or rw <= 0 then return nil end
    local w = fs:GetStringWidth()
    if type(w) ~= "number" or Co.IsSecret(w) then return nil end
    -- a title wider than its text box wraps (or is cut): it fills the box, so count the box's width
    local fw = fs:GetWidth()
    if type(fw) == "number" and not Co.IsSecret(fw) and fw > 0 and w > fw then w = fw end
    local fl, rl = fs:GetLeft(), row:GetLeft()
    local start = 20   -- the templates' text inset (GossipFrame.xml / QuestFrameTemplates.xml)
    if type(fl) == "number" and type(rl) == "number" and not Co.IsSecret(fl) and not Co.IsSecret(rl) then start = fl - rl end
    return rw - (start + w)
end

-- Shows the tag in the widest form that fits next to the title: full text, short text, a thin bar, or nothing.
-- Returns the form used ("full" / "short" / "bar" / "none"; also t.form).
function NT.PlaceTag(row, t, a)
    local room = NT.FreeRoom(row)
    for _, short in ipairs({ false, true }) do
        local text, color = NT.TagText(a, short)
        t.text:SetText(text)
        local w = math.floor((t.text:GetStringWidth() or 40) + 10)
        if room and room >= w + NT.TAG_GAP + NT.TAG_INSET then
            K.Color(t.text, color)
            t.bar:Hide()
            t.bg:Show()
            t.text:Show()
            t:SetPoint("RIGHT", row, "RIGHT", -NT.TAG_INSET, 0)
            t:SetWidth(w)
            t:SetHeight(14)
            t.form = short and "short" or "full"
            t:Show()
            return t.form
        end
    end
    local _, color = NT.TagText(a)
    -- the bar sits in the row's last BAR_W + 1 units (296-299 of 300); with an unknown title width it still never reaches the
    -- template's text box (it ends 5 units short of the row's edge)
    if room == nil or room >= NT.BAR_W + 1 then
        t.text:SetText("")
        t.text:Hide()
        t.bg:Hide()
        t.bar:SetColorTexture(Th.Color(color))
        t.bar:Show()
        t:SetPoint("RIGHT", row, "RIGHT", -1, 0)
        t:SetWidth(NT.BAR_W)
        t:SetHeight(12)
        t.form = "bar"
        t:Show()
        return "bar"
    end
    t.form = "none"
    t:Hide()
    return "none"
end

local function Reset(row)
    if NT.dimmed[row] then
        row:SetAlpha(1)
        NT.dimmed[row] = nil
    end
    local t = NT.tags[row]
    if t then t:Hide() end
end
NT.Reset = Reset

-- Marks one Blizzard quest row (gossip or greeting) for quest q ("available" / "active").
function NT.ApplyRow(row, q, kind)
    if type(row) ~= "table" then return end
    if Co.IsSecret(q) then q = nil end      -- a secret id is unknown: say nothing
    NT.rowQuest[row] = { q = q, kind = kind }
    local mode = NT.Mode()
    local a = mode ~= "off" and NT.Answer(q, kind) or nil
    if not a then return Reset(row) end
    NT.stats.rows = NT.stats.rows + 1
    if NT.Dims(a, mode) then
        row:SetAlpha(Th.Alpha("npcDim", 0.45))
        NT.dimmed[row] = true
    elseif NT.dimmed[row] then
        row:SetAlpha(1)
        NT.dimmed[row] = nil
    end
    local t = NT.tags[row]
    if not NT.TagText(a) then
        if t then t:Hide() end
        return
    end
    if not t then
        t = MakeTag(row)
        NT.tags[row] = t
    end
    NT.PlaceTag(row, t, a)
end

-- ------------------------------------------------------------------ gossip window
-- quest id + kind of a gossip ScrollBox row (its element data; GetID() = the quest id as a fallback)
local function GossipRow(row, info)
    local data = type(row.GetElementData) == "function" and row:GetElementData() or nil
    local bt = type(data) == "table" and data.buttonType or nil
    if bt ~= NT.ACTIVE and bt ~= NT.AVAILABLE then
        if bt ~= nil then return nil end
        -- no element data: only a row whose Setup we hooked comes here (a quest row)
        info = info or {}
        bt = info.isComplete ~= nil and NT.ACTIVE or NT.AVAILABLE
    end
    info = info or (type(data) == "table" and data.info) or nil
    local q = type(info) == "table" and info.questID or nil
    if type(q) ~= "number" and type(row.GetID) == "function" then q = row:GetID() end
    return q, bt == NT.ACTIVE and "active" or "available"
end
NT.GossipRow = GossipRow

local function OnRowSetup(row, info)
    local q, kind = GossipRow(row, info)
    if q then NT.ApplyRow(row, q, kind) else Reset(row) end
end

-- A gossip row the ScrollBox just set up (its OnInitializedFrame event: after Blizzard's Setup, also for rows
-- made or reused on scroll). Option / title rows that once showed a quest lose our marks.
function NT.OnInitRow(row, data)
    local bt = type(data) == "table" and data.buttonType or nil
    if bt == NT.ACTIVE or bt == NT.AVAILABLE then
        OnRowSetup(row, data.info)
    elseif NT.tags[row] or NT.dimmed[row] then
        Reset(row)
    end
end

-- After GossipFrame:Update (show and QUEST_LOG_UPDATE): every row on screen. Without the ScrollBox event
-- (ScrollUtil missing) quest rows get a Setup hook the first time we see them instead.
function NT.GossipUpdate()
    local gf = NT.gossip
    local box = gf and gf.GreetingPanel and gf.GreetingPanel.ScrollBox
    if not (box and type(box.ForEachFrame) == "function") then return end
    box:ForEachFrame(function(row, data)
        if not NT.boxCallback then
            local bt = type(data) == "table" and data.buttonType or nil
            if bt == NT.ACTIVE or bt == NT.AVAILABLE then ns.Hooks.Func(row, "Setup", OnRowSetup, FEATURE) end
        end
        NT.OnInitRow(row, data)
    end)
end

function NT.GossipHide()
    for row in pairs(NT.rowQuest) do Reset(row) end
end

-- ------------------------------------------------------------------ quest greeting (non-gossip NPCs)
function NT.GreetingUpdate()
    local panel = NT.greeting
    local pool = panel and panel.titleButtonPool
    for row in pairs(NT.greet) do Reset(row) end
    if not (pool and type(pool.EnumerateActive) == "function") then return end
    local F = Co.fn
    for row in pool:EnumerateActive() do
        local i = type(row.GetID) == "function" and row:GetID() or nil
        local q, kind
        if type(i) == "number" then
            if row.isActive == 1 then
                q, kind = F.ActiveQuestID and F.ActiveQuestID(i), "active"
            else
                q, kind = F.AvailQuestInfo and select(5, F.AvailQuestInfo(i)), "available"
            end
        end
        NT.greet[row] = true
        if type(q) == "number" and not Co.IsSecret(q) then NT.ApplyRow(row, q, kind) else Reset(row) end
    end
end

-- ------------------------------------------------------------------ the accept window line
function NT.BuildLine()
    if NT.line or not NT.detail then return NT.line end
    local panel = NT.detail
    local anchor = (type(panel.GetParent) == "function" and panel:GetParent()) or panel
    local l = CreateFrame("Frame", nil, panel)
    l:EnableMouse(false)
    l:SetHeight(22)
    l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    l:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    K.Panel(l, false)
    l.text = K.Text(l, "goal", "npcRoute", "CENTER")
    l.text:SetPoint("TOPLEFT", l, "TOPLEFT", NT.LINE_PAD, -5)
    l.text:SetPoint("TOPRIGHT", l, "TOPRIGHT", -NT.LINE_PAD, -5)
    -- tester beta.4 #2: a long line wraps to a second line (our own font string), never cut mid-way
    l.text:SetWordWrap(true)
    if type(l.text.SetMaxLines) == "function" then l.text:SetMaxLines(2) end
    l:Hide()
    NT.line = l
    return l
end

-- One or two lines high: two when the text is wider than the line's text area (the panel follows).
NT.LINE_PAD = 6
function NT.SizeLine(l)
    local lh = Th.LineHeight("goal")
    local room = (l:GetWidth() or 0) - 2 * NT.LINE_PAD
    local w = l.text:GetStringWidth() or 0
    l.lines = (room > 0 and w > room) and 2 or 1
    l.text:SetHeight(l.lines * lh)
    l:SetHeight(l.lines * lh + 10)
    return l.lines
end

function NT.DetailShow()
    local l = NT.line or NT.BuildLine()
    if not l then return end
    local F = Co.fn
    local q = F.QuestID and F.QuestID()
    local mode = NT.Mode()
    local a = mode ~= "off" and type(q) == "number" and not Co.IsSecret(q) and NT.Answer(q, "available") or nil
    if not a then return l:Hide() end
    local text, color = NT.LineText(a)
    l.text:SetText(text)
    K.Color(l.text, color)
    NT.SizeLine(l)
    l.quest = q
    NT.stats.lines = NT.stats.lines + 1
    l:Show()
end

function NT.DetailHide()
    if NT.line then NT.line:Hide() end
end

-- ------------------------------------------------------------------ wiring
local function Shown(f) return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() == true end

-- Redraws whatever NPC window is open now (setting changed, step changed, quest log changed).
function NT.Redraw()
    NT.Clear()
    if Shown(NT.gossip) then NT.GossipUpdate() else NT.GossipHide() end
    if Shown(NT.greeting) then NT.GreetingUpdate() else for row in pairs(NT.greet) do Reset(row) end end
    if Shown(NT.detail) then NT.DetailShow() else NT.DetailHide() end
end

function NT.Hook()
    if NT.hooked then return true end
    local H, R = ns.Hooks, Co.Resolve
    NT.gossip = Co.fn.GossipFrame or R("GossipFrame")
    NT.greeting = Co.fn.QuestGreetingPanel or R("QuestFrameGreetingPanel")
    NT.detail = Co.fn.QuestDetailPanel or R("QuestFrameDetailPanel")
    local n = 0
    if type(NT.gossip) == "table" then
        -- the ScrollBox's own "row set up" event (ScrollUtil's helper; CallbackRegistry runs it through
        -- secureexecuterange, so Blizzard's code path stays clean)
        local box = NT.gossip.GreetingPanel and NT.gossip.GreetingPanel.ScrollBox
        local add = Co.fn.ScrollInitCb
        if not NT.boxCallback and type(box) == "table" and type(box.RegisterCallback) == "function" and add then
            add(box, function(_, row, data) ns.Errors.Call(FEATURE, NT.OnInitRow, row, data) end, NT)
            NT.boxCallback = true
            n = n + 1
        end
        if H.Func(NT.gossip, "Update", NT.GossipUpdate, FEATURE) then n = n + 1 end
        if H.Script(NT.gossip, "OnHide", NT.GossipHide, FEATURE) then n = n + 1 end
    end
    if type(NT.greeting) == "table" then
        if H.Script(NT.greeting, "OnShow", NT.GreetingUpdate, FEATURE) then n = n + 1 end
        if H.Script(NT.greeting, "OnHide", function() for row in pairs(NT.greet) do Reset(row) end end, FEATURE) then n = n + 1 end
        -- QUEST_LOG_UPDATE calls the global directly (QuestFrame.lua:86-90), not the panel's script
        if H.Func(nil, "QuestFrameGreetingPanel_OnShow", NT.GreetingUpdate, FEATURE) then n = n + 1 end
    end
    if type(NT.detail) == "table" then
        NT.BuildLine()
        if H.Script(NT.detail, "OnShow", NT.DetailShow, FEATURE) then n = n + 1 end
        if H.Script(NT.detail, "OnHide", NT.DetailHide, FEATURE) then n = n + 1 end
    end
    NT.hooked = n > 0
    NT.hookCount = n
    return NT.hooked
end

-- (bus listeners get the event name first and already run under ns.Errors.Call with their feature)
local function Changed() NT.Redraw() end
ns.Bus.On("Login", NT, function() NT.Hook() end, FEATURE, 55)
for _, ev in ipairs({ "StepChanged", "QuestsChanged", "PackLoaded", "LevelChanged" }) do
    ns.Bus.On(ev, NT, Changed, FEATURE, 90)
end
ns.Bus.On("SettingsChanged", NT, function(_, key)
    if key == "npcHelper" then Changed() end
end, FEATURE, 90)
-- switched off (3 errors, or by hand): nothing of ours may stay on Blizzard's rows (runs as "ui": ours is off)
function NT.ResetAll()
    for row in pairs(NT.dimmed) do
        row:SetAlpha(1)
        NT.dimmed[row] = nil
    end
    for _, t in pairs(NT.tags) do t:Hide() end
    if NT.line then NT.line:Hide() end
end
ns.Bus.On("FeatureChanged", NT, function(_, name, state)
    if name == FEATURE and state ~= "on" then NT.ResetAll() end
end, "ui", 90)

-- ------------------------------------------------------------------ self-check
-- The accept line is ours, parented to the accept panel and hidden with it; tags sit on their rows and take
-- no mouse; no row stays faded outside "dim"; a live gossip list matches Blizzard's own quest lists.
function NT.Problem()
    if NT.Mode() == "off" then return nil end
    local l = NT.line
    if NT.detail then
        if not l then return "accept line not built" end
        if l:GetParent() ~= NT.detail then return "accept line not on the accept panel" end
        if not Shown(NT.detail) and l:IsVisible() then return "accept line shown without the accept window" end
        if l:IsMouseEnabled() then return "accept line takes the mouse" end
    end
    for row, t in pairs(NT.tags) do
        if t:GetParent() ~= row then return "a tag left its row" end
        if t:IsMouseEnabled() then return "a tag takes the mouse" end
    end
    if NT.Mode() ~= "dim" and next(NT.dimmed) then return "a row is faded outside dim mode" end
    return nil
end

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "npchelper", fn = function(h)
    h.Count()
    if NT.Mode() == "off" then return h.Info("npc helper off") end
    local bad = NT.Problem()
    if bad then h.Problem("npchelper: " .. bad) end
    if Shown(NT.gossip) and Co.fn.GossipAvail and Co.fn.GossipActive then
        h.Count()
        local want = #(Co.fn.GossipAvail() or {}) + #(Co.fn.GossipActive() or {})
        local seen = 0
        local box = NT.gossip.GreetingPanel and NT.gossip.GreetingPanel.ScrollBox
        if box and box.ForEachFrame then
            box:ForEachFrame(function(_, data)
                if type(data) == "table" and (data.buttonType == NT.ACTIVE or data.buttonType == NT.AVAILABLE) then seen = seen + 1 end
            end)
            if seen > want then h.Problem(("npchelper: %d quest rows, the game lists %d"):format(seen, want)) end
        end
    end
    h.Info(("npc helper %s, hooks %d, rows %d, lines %d"):format(NT.Mode(), NT.hookCount or 0, NT.stats.rows, NT.stats.lines))
end }

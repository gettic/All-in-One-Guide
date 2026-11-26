-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Item pictures (plans\item-icons\plan.md, option C; tos plans\item-icons\tos.md): the item's own game icon
--   * inline before the item's name in the current step's text (first mention per item), as an item link
--     "|Hitem:<id>|h<icon><no-break space><name>|h" built only from our pack ids, so hovering it shows the game's
--     item tooltip (OnHyperlinkEnter on the row; other link types are ignored; a click does nothing);
--   * on goal rows instead of the goal tile (hover: the item tooltip), and 12 px on next-step lines;
--   * beta.11: also in the current step's note line, the step tooltip (icons only), and for items a step only
--     mentions by name (any item the route names: II.Index, built once per route from the raw rows);
--   * ids from the step's `item` / `useItem` / cond item=, `{item:<id>}` tokens, and Data\QuestItems.lua for goals;
--     names from the game, else Data\ItemNames.lua (CMaNGOS, GPL);
--   * an icon the game hasn't loaded: the theme's file.itemUnknown, and GET_ITEM_INFO_RECEIVED is registered only
--     while one waits (one window refresh per frame at most);
--   * nothing at login: everything is built on the first draw of a step and cached per step.
-- Setting itemIcons (on by default). Display only: never uses, links into chat or clicks anything.
--   ns.ItemIcons.On(), .Ids(step), .Icon(id), .Name(id), .Link(id, name), .Decorate(step, text), .GoalItem(step, g),
--   .NextIcon(step), .LinkEnter(row, link), .LinkLeave(row), .Reset(), .Problem(text)
local _, ns = ...
local Th, Co = ns.Theme, ns.Compat
local II = { NBSP = "\194\160", CROP = ":0:0:0:0:64:64:5:59:5:59|t", NEXT = 12, calls = 0,
    pending = nil, queued = false, cache = setmetatable({}, { __mode = "k" }), byQuest = nil }
ns.ItemIcons = II

function II.On() return ns.Settings.Get("itemIcons") ~= false end

-- ------------------------------------------------------------------ data
-- The quests' items from Data\QuestItems.lua, by quest (built on first use, never at login).
local function ByQuest()
    if II.byQuest and II.byQuestSrc == ns.QuestItems then return II.byQuest end
    local t = {}
    for id, d in pairs(type(ns.QuestItems) == "table" and ns.QuestItems or {}) do
        if type(id) == "number" and type(d) == "table" then
            local q = d.q or d.quest
            if type(q) == "number" then q = { q } end
            for _, x in ipairs(type(q) == "table" and q or {}) do
                if type(x) == "number" then
                    t[x] = t[x] or {}
                    t[x][#t[x] + 1] = id
                end
            end
        end
    end
    for _, list in pairs(t) do table.sort(list) end
    II.byQuest, II.byQuestSrc = t, ns.QuestItems
    return t
end

-- The items a step names itself (item, useItem, a useitem step's item, cond item=), in a fixed order.
function II.Ids(step)
    local out, seen = {}, {}
    local function Add(id)
        id = tonumber(id)
        if id and id > 0 and not seen[id] then seen[id] = true out[#out + 1] = id end
    end
    if type(step) ~= "table" then return out end
    Add(step.item)
    Add(step.useItem)
    local Cd = ns.Conditions
    local ast = step.condAst or (type(step.cond) == "string" and Cd and Cd.Get(step.cond)) or nil
    if ast and Cd then
        local ids = {}
        for id in pairs(Cd.Items(ast)) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do Add(id) end
    end
    return out
end

-- ------------------------------------------------------------------ waiting for the game's item data
local function Refresh()
    II.queued = false
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function II.OnInfo(_, itemID)
    local p = II.pending
    if not (p and p[itemID]) then return end
    p[itemID] = nil
    II.Reset()
    if not II.queued then
        II.queued = true
        Co.After(0, function() ns.Errors.Call("itemicons", Refresh) end)
    end
    if not next(p) then
        II.pending = nil
        ns.Events.Off("GET_ITEM_INFO_RECEIVED", II)
    end
end

function II.Wait(id)
    if not II.pending then
        II.pending = {}
        ns.Events.On("GET_ITEM_INFO_RECEIVED", II, II.OnInfo, "itemicons")
    end
    II.pending[id] = true
end

-- The item's icon (a file id), or the theme's unknown-item file while the game hasn't loaded it.
function II.Icon(id)
    II.calls = II.calls + 1
    local tex = Co.ItemIcon(id)
    if tex then return tex end
    II.Wait(id)
    return Th.File("itemUnknown")
end

-- The item's name for display: the game's, else Data\ItemNames.lua; nil when neither knows it (then it waits).
function II.Name(id)
    local n = Co.ItemName(id) or (ns.ItemNames and ns.ItemNames[id])
    if not n then II.Wait(id) end
    return n
end

function II.Escape(id)
    return "|T" .. tostring(II.Icon(id)) .. II.CROP
end

-- An item link from our own id only: icon + no-break space + name, one hover target.
function II.Link(id, name)
    id = tonumber(id)
    if not id then return name end
    return "|Hitem:" .. id .. "|h" .. II.Escape(id) .. II.NBSP .. tostring(name or "") .. "|h"
end

-- ------------------------------------------------------------------ the step text
local function IsWord(c) return c ~= "" and c:match("[%w']") ~= nil end

-- Is byte position i inside an existing link's shown text ("|H<link>|h<shown>|h": an odd count of "|h" before it)?
local function InLink(text, i)
    local n = 0
    for _ in text:sub(1, i - 1):gmatch("|h") do n = n + 1 end
    return n % 2 == 1
end

-- The first whole-word, case-insensitive mention of name in text outside links: start, end; or nil.
local function Find(text, name)
    local lt, ln = text:lower(), name:lower()
    local from = 1
    while true do
        local a, b = lt:find(ln, from, true)
        if not a then return nil end
        if not IsWord(text:sub(a - 1, a - 1)) and not IsWord(text:sub(b + 1, b + 1)) and not InLink(text, a) then
            return a, b
        end
        from = a + 1
    end
end

-- The names an item is known by (Data\ItemNames.lua, the game's); none known yet = wait for the game.
-- beta.11 fix (the user: "i dont see the icon down at the step"): this was ipairs({ ItemNames[id], game name }),
-- which stops at the first nil, so a Forever-only item (no ItemNames entry, e.g. the Nibbled-On Book) never got
-- its game name looked at: no picture on its steps. Both are read on their own now.
local function Names(id)
    local names = {}
    local a = ns.ItemNames and ns.ItemNames[id]
    local b = Co.ItemName(id)
    if type(a) == "string" and a ~= "" then names[#names + 1] = a end
    if type(b) == "string" and b ~= "" and b ~= a then names[#names + 1] = b end
    if #names == 0 then II.Wait(id) end
    return names
end
II.Names = Names

-- Every item the route names anywhere (item / useItem / cond item= / {item:<id>}), with its names, longest name first:
-- items a step only mentions by name ("A Nibbled-On Book may drop here") get their picture too (beta.11, the user: "i
-- dont see the icon down at the step"). Built on first use per route from the raw rows (no decoding), never at login.
function II.Index(top)
    local route = type(top) == "table" and top.route or nil
    if type(route) ~= "table" then return {} end
    local c = II.index
    if c and c.route == route then return c.list end
    local ids, seen = {}, {}
    local function Add(id)
        id = tonumber(id)
        if id and id > 0 and not seen[id] then seen[id] = true ids[#ids + 1] = id end
    end
    for _, row in ipairs(type(route.rows) == "table" and route.rows or {}) do
        if type(row) == "string" and (row:find("tem", 1, true)) then
            for id in row:gmatch("[Ii]tem[=:](%d+)") do Add(id) end
        end
    end
    for _, s in ipairs(type(route.steps) == "table" and route.steps or {}) do
        for _, id in ipairs(II.Ids(s)) do Add(id) end
        if type(s.text) == "string" then for id in s.text:gmatch("{item:(%d+)}") do Add(id) end end
    end
    table.sort(ids)
    local list = {}
    for _, id in ipairs(ids) do
        for _, n in ipairs(Names(id)) do list[#list + 1] = { id = id, name = n, low = n:lower() } end
    end
    table.sort(list, function(a, b) if #a.name ~= #b.name then return #a.name > #b.name end return a.id < b.id end)
    II.index = { route = route, list = list }
    return list
end

-- text with the item picture before the first mention of each item: the step's own items first (by id), then any
-- other item of the route it names. link = true: "|Hitem:..|h<icon> name|h" (the window's rows, hover tooltip);
-- false: just the icon before the name (tooltips: no links there).
local function Mark(text, step, top, link)
    local out, done = text, {}
    local function Put(id, a, b)
        local name = out:sub(a, b)
        local mark = link and II.Link(id, name) or (II.Escape(id) .. II.NBSP .. name)
        out = out:sub(1, a - 1) .. mark .. out:sub(b + 1)
        done[id] = true
    end
    for _, id in ipairs(II.Ids(step)) do
        if out:find("|Hitem:" .. id .. "|h", 1, true) then done[id] = true end
        if not done[id] then
            for _, n in ipairs(Names(id)) do
                local a, b = Find(out, n)
                if a then Put(id, a, b) break end
            end
        end
    end
    for id in out:gmatch("|Hitem:(%d+)|h") do done[tonumber(id)] = true end
    local low = out:lower()
    for _, e in ipairs(II.Index(top)) do
        if not done[e.id] and low:find(e.low, 1, true) then
            local a, b = Find(out, e.name)
            if a and not out:sub(1, a - 1):find("|T[^|]*$") then Put(e.id, a, b) end
        end
    end
    return out
end

-- The step text (field "text"), its note ("note") or a tooltip line ("tip..", icons only) with the item pictures;
-- cached per step and field. top: the step's guide (for the route's item names), may be nil.
function II.Decorate(step, text, top, field)
    if type(text) ~= "string" or not II.On() or type(step) ~= "table" then return text end
    field = field or "text"
    local c = II.cache[step]
    if not c then c = {} II.cache[step] = c end
    local e = c[field]
    if e and e.text == text then return e.out end
    local out = Mark(text, step, top, field:sub(1, 3) ~= "tip")
    c[field] = { text = text, out = out }
    return out
end

-- The first item a step names or mentions (for its 12 px icon on a next line): its own ids, a {item:} token, else
-- the first route item named in its plain text.
function II.FirstItem(step, top, plain)
    local id = II.Ids(step)[1]
    if id then return id end
    local t = step.text
    id = type(t) == "string" and tonumber(t:match("{item:(%d+)}")) or nil
    if id or type(plain) ~= "string" then return id end
    -- (perf: the name search once per step and text, cached like Decorate)
    local c = II.cache[step]
    if not c then c = {} II.cache[step] = c end
    local e = c.first
    if e and e.text == plain then return e.id end
    local best, at
    local low = plain:lower()
    for _, x in ipairs(II.Index(top)) do
        if low:find(x.low, 1, true) then
            local a = Find(plain, x.name)
            if a and (not at or a < at) then best, at = x.id, a end
        end
    end
    c.first = { text = plain, id = best }
    return best
end

-- {item:<id>} tokens (Engine\Guide.lua Guide:Text): the name, or with wrap the window's link.
function II.Token(id)
    local name = II.Name(id) or ns.L.ITEM_FALLBACK
    return name
end

-- ------------------------------------------------------------------ goals and next lines
-- The item a goal line is about: the step's own item for its "have N" goal, else a quest item of the goal's step whose
-- name starts the goal text ("Tough Wolf Meat: 3/8"). nil when none.
function II.GoalItem(step, g)
    if not II.On() or type(g) ~= "table" or g.more or g.fold or g.firstAid then return nil end
    local s = g.side or step
    if type(s) ~= "table" then return nil end
    if g.kind == "loot" and tonumber(s.item) and not g.side then return tonumber(s.item) end
    local text = type(g.text) == "string" and g.text:lower() or ""
    if text == "" then return nil end
    local ids = II.Ids(s)
    for _, id in ipairs(type(s.quest) == "number" and ByQuest()[s.quest] or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        for _, n in ipairs(Names(id)) do
            if text:sub(1, #n) == n:lower() then return id end
        end
    end
    return nil
end

-- The 12 px icon of a next-step line: the step's first item (a token in its text counts too), or nil.
function II.NextIcon(step, top, plain)
    if not II.On() or type(step) ~= "table" then return nil end
    local id = II.FirstItem(step, top, plain)
    return id and II.Icon(id) or nil, id
end

-- ------------------------------------------------------------------ hover
function II.LinkEnter(row, link)
    local id = type(link) == "string" and tonumber(link:match("^item:(%d+)$"))
    if not id then return end   -- only our own item:<number> links
    local tip = Co.Tooltip()
    if not tip then return end
    tip:SetOwner(row, "ANCHOR_RIGHT")
    if tip.SetHyperlink then tip:SetHyperlink("item:" .. id) elseif tip.SetItemByID then tip:SetItemByID(id) end
    tip:Show()
    II.hovered = id
end

function II.LinkLeave(row)
    II.hovered = nil
    ns.UIKit.HideTooltip()
    if row and row.step and row.IsMouseOver and row:IsMouseOver() and ns.UI.StepTip then ns.UI.StepTip(row) end
end

function II.ItemTip(owner, id)
    local tip = Co.Tooltip()
    if not (tip and id) then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    if tip.SetItemByID then tip:SetItemByID(id) else tip:SetText(II.Name(id) or "", 1, 1, 1) end
    tip:Show()
end

function II.Reset()
    II.cache = setmetatable({}, { __mode = "k" })
    II.index = nil
end

-- nil when the text's item links are well formed (item:<number> only, closed, one per item), else a reason.
function II.Problem(text)
    if type(text) ~= "string" then return nil end
    local seen = {}
    for link in text:gmatch("|H([^|]*)|h") do
        local id = link:match("^item:(%d+)$")
        if not id then return "a link that isn't item:<number>: " .. link end
        if seen[id] then return "item " .. id .. " linked twice" end
        seen[id] = true
    end
    local opens = select(2, text:gsub("|H", ""))
    local marks = select(2, text:gsub("|h", ""))
    if marks ~= opens * 2 then return "an item link isn't closed" end
    if select(2, text:gsub("|T", "")) ~= select(2, text:gsub("|t", "")) then return "an icon isn't closed" end
    return nil
end

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "itemicons", fn = function(h)
    h.Count()
    local r = ns.UI and ns.UI.rows and ns.UI.rows[1]
    local t = r and r:IsShown() and r.text and r.text:GetText()
    local bad = II.Problem(t)
    if bad then h.Problem("itemicons: " .. bad) end
    if not II.On() and type(t) == "string" and t:find("|Hitem:", 1, true) then
        h.Problem("itemicons: item links shown with the setting off")
    end
    h.Info(II.State())
end }

-- One line for /aog selftest: the item-picture state of the steps shown now (beta.11 "i dont see the icon").
function II.State()
    if not II.On() then return "itemicons: off (the Item pictures setting)" end
    local rows = ns.UI and ns.UI.rows or {}
    local r = rows[1]
    if not (r and r:IsShown() and r.step) then return "itemicons: on, no step shown" end
    local g = ns.Engine.Focused()
    local function Count(s) return type(s) == "string" and select(2, s:gsub("|Hitem:", "")) or 0 end
    local noteN = 0
    for _, fs in ipairs(r.note or {}) do if fs:IsShown() then noteN = noteN + Count(fs:GetText()) end end
    local goalN = 0
    for _, ln in ipairs(r.lines or {}) do if ln.item and ln.icon and ln.icon:IsShown() then goalN = goalN + 1 end end
    local nextN, nextAll = 0, 0
    for i = 2, #rows do
        local o = rows[i]
        if o:IsShown() then
            nextAll = nextAll + 1
            if o.tagIcon and o.tagIcon:IsShown() then nextN = nextN + 1 end
        end
    end
    local ids = II.Ids(r.step)
    local waiting = 0
    for _ in pairs(II.pending or {}) do waiting = waiting + 1 end
    return ("itemicons: on; step %s: own items %s, route items %d; icons: text %d, note %d, goals %d, next lines %d/%d; waiting for %d"):format(
        tostring(r.step.id), #ids > 0 and table.concat(ids, ",") or "none", #II.Index(g and g:Top()), Count(r.text and r.text:GetText()),
        noteN, goalN, nextN, nextAll, waiting)
end

ns.Bus.On("SettingsChanged", II, function(_, key) if key == "itemIcons" then II.Reset() end end, "itemicons", 60)
ns.Bus.On("PackLoaded", II, function() II.Reset() II.byQuest = nil end, "itemicons")

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Item pictures (plans\item-icons\plan.md, option C; tos plans\item-icons\tos.md): the item's own game icon
--   * the item's name in the current step's text and note line (first mention per item) is an item link
--     "|Hitem:<id>|h<coloured name>|h" built only from our pack ids, so hovering it shows the game's item tooltip
--     (OnHyperlinkEnter on the row; other link types are ignored; a click does nothing);
--   * beta.12 (the user: "a ICON nibble" is weird): never an icon inside the text; the line's first item gets a
--     tile at the line's left (the note line; the step text only when it has no step tile, i.e. next to the 3D
--     view), hover = the item tooltip (UI\Rows.lua);
--   * on goal rows instead of the goal tile (hover: the item tooltip);
--   * items a step only mentions by name count too (any item the route names: II.Index, built once per route);
--   * the current step only (the user: "only show icons for active steps"), with its goals riding along; next-step
--     lines and tooltips never get one;
--   * ids from the step's `item` / `useItem` / cond item=, `{item:<id>}` tokens, and Data\QuestItems.lua for goals;
--     names from the game, else Data\ItemNames.lua (CMaNGOS, GPL);
--   * an icon the game hasn't loaded: the theme's file.itemUnknown, and GET_ITEM_INFO_RECEIVED is registered only
--     while one waits (one window refresh per frame at most);
--   * nothing at login: everything is built on the first draw of a step and cached per step.
-- Setting itemIcons (on by default). Display only: never uses, links into chat or clicks anything.
--   ns.ItemIcons.On(), .Ids(step), .Icon(id), .Name(id), .Names(id), .Index(top), .Link(id, name),
--   .Decorate(step, text, top, field), .FirstIn(text), .GoalItem(step, g), .LinkEnter(row, link), .LinkLeave(row), .Reset(),
--   .Problem(text), .State(), .NextWithPicture()
local _, ns = ...
local Th, Co = ns.Theme, ns.Compat
local II = { calls = 0,
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

-- An item link from our own id only: the name in the item colour, one hover target (no icon inside: beta.12).
function II.Link(id, name)
    id = tonumber(id)
    if not id then return name end
    return "|Hitem:" .. id .. "|h" .. Th.Wrap("itemLink", tostring(name or "")) .. "|h"
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

-- text with the first mention of each item as a coloured hover link: the step's own items first (by id), then any
-- other item of the route it names. Never an icon inside the text (beta.12, the user: "a ICON nibble" is weird);
-- the line's first item gets a tile at its left instead (II.FirstIn + Rows).
local function Mark(text, step, top)
    local out, done = text, {}
    local function Put(id, a, b)
        out = out:sub(1, a - 1) .. II.Link(id, out:sub(a, b)) .. out:sub(b + 1)
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
            if a then Put(e.id, a, b) end
        end
    end
    return out
end

-- The current step's text (field "text") or its note ("note") with its items as hover links; cached per step and
-- field. top: the step's guide (for the route's item names), may be nil.
function II.Decorate(step, text, top, field)
    if type(text) ~= "string" or not II.On() or type(step) ~= "table" then return text end
    field = field or "text"
    local c = II.cache[step]
    if not c then c = {} II.cache[step] = c end
    local e = c[field]
    if e and e.text == text then return e.out end
    local out = Mark(text, step, top)
    c[field] = { text = text, out = out }
    return out
end

-- The first item linked in a decorated text (the one whose tile stands at the line's left), or nil.
function II.FirstIn(text)
    return type(text) == "string" and tonumber(text:match("|Hitem:(%d+)|h")) or nil
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
    if II.NextWithPicture() > 0 then h.Problem("itemicons: a next-step line shows an item picture (current step only)") end
    -- beta.12: never an icon inside the current step's text or note (the icon is a tile at the line's left)
    local texts = { t }
    for _, fs in ipairs(r and r.note or {}) do if fs:IsShown() then texts[#texts + 1] = fs:GetText() end end
    for _, s in ipairs(texts) do
        if type(s) == "string" and s:find("|T", 1, true) then h.Problem("itemicons: an icon inside the step text or note") break end
    end
end }

-- The item a row's left tile shows (key "text" / "note"), or nil when it's hidden.
function II.TileOf(r, key)
    local t = r and r.itemTiles and r.itemTiles[key]
    return t and t.icon:IsShown() and t.id or nil
end

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
    local ids = II.Ids(r.step)
    local waiting = 0
    for _ in pairs(II.pending or {}) do waiting = waiting + 1 end
    return ("itemicons: on, current step only; step %s: own items %s, route items %d; links: text %d, note %d; tiles: text %s, note %s, goals %d; next lines with a picture: %d (should be 0); waiting for %d"):format(
        tostring(r.step.id), #ids > 0 and table.concat(ids, ",") or "none", #II.Index(g and g:Top()), Count(r.text and r.text:GetText()),
        noteN, tostring(II.TileOf(r, "text") or "-"), tostring(II.TileOf(r, "note") or "-"), goalN, II.NextWithPicture(), waiting)
end

-- How many shown next-step lines carry an item picture (beta.12: must be 0; current step only).
function II.NextWithPicture()
    local rows = ns.UI and ns.UI.rows or {}
    local n = 0
    for i = 2, #rows do
        local o = rows[i]
        local t = o:IsShown() and o.text and o.text:GetText()
        if type(t) == "string" and (t:find("|T", 1, true) or t:find("|H", 1, true)) then n = n + 1 end
    end
    return n
end

ns.Bus.On("SettingsChanged", II, function(_, key) if key == "itemIcons" then II.Reset() end end, "itemicons", 60)
ns.Bus.On("PackLoaded", II, function() II.Reset() II.byQuest = nil end, "itemicons")

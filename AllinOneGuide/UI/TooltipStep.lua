-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Step line on tooltips (plans\tooltip-step\plan.md, tos plans\tooltip-step\tos.md). When the game tooltip shows
-- a mob, NPC or world object that the guide wants right now, we add one line (at most two) at its bottom:
-- "Step: Kobold Vermin slain 4/10", "On the way: ...", "Step: Accept <quest>".
-- Display only (tos D): a hit is never used for anything else (no arrow, sound, marking or step change).
-- Hooked only through TooltipDataProcessor.AddTooltipPostCall (ns.Hooks.TooltipPost); Blizzard shows the tooltip
-- right after the post-calls (TooltipDataHandler.lua:298-300) and rebuilds it on TOOLTIP_DATA_UPDATE, so counts
-- follow kills without any ticker of ours.
-- Secret values (tos A-C): we only read tooltipData.guid and lines[1].leftText (and the line type / text of
-- QuestObjective lines for the "already shown" check), each checked with Co.IsSecret before any string use. A
-- secret value is never recovered another way (no FontString read-back, no second try through the unit GUID / name functions).
-- Both secret = no line. AddLine only gets our own plain strings built from the GameState snapshot.
--   ns.TooltipStep.Mode()                      "off" / "short" / "full"
--   ns.TooltipStep.LinesFor(data, kind, mode)  kind "unit" / "object" -> { {text, color}, ... } (pure; self-check)
local _, ns = ...
local Co, Th = ns.Compat, ns.Theme
local FEATURE = "tooltipstep"
local TT = { stats = { hovers = 0, hits = 0, rebuilds = 0, lines = 0 }, dirty = true, registered = 0 }
ns.TooltipStep = TT

TT.MAX_LINES = 2     -- lines we add to one tooltip
TT.MAX_SCAN = 30     -- tooltip lines looked at for the "already shown" check
TT.MIN_NAME = 3      -- shorter names never match an objective by name

function TT.Mode()
    if ns.safeMode or not ns.Feature.IsOn(FEATURE) then return "off" end
    local ok, v = pcall(ns.Settings.Get, "tooltipStep")
    return ok and v or "off"
end

-- Enum values, read once (nil = this client doesn't have them: no post-call for that type).
local function EnumValue(tbl, key)
    local ok, v = pcall(function() return _G.Enum[tbl][key] end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function Plain(v) return not Co.IsSecret(v) and type(v) == "string" end

-- ------------------------------------------------------------------ the index (rebuilt only when dirty)
-- byNpc[npcId] = { entry, ... }; names = { { key, entry, i, kind }, ... } (key = lowercased objective text)
local function AddStep(idx, top, step, where)
    if not step or idx.seen[step] then return end
    idx.seen[step] = true
    local e = { step = step, top = top, where = where }
    local npc = tonumber(step.npc)
    if npc then
        idx.byNpc[npc] = idx.byNpc[npc] or {}
        table.insert(idx.byNpc[npc], e)
    end
    -- objective names: only objective / useitem steps of a quest in the log (snapshot texts, never secret)
    if not step.quest or (step.type ~= "objective" and step.type ~= "useitem") then return end
    local GS = ns.GameState
    local qs = GS.InLog(step.quest) and GS.Quest(step.quest)
    if not qs then return end
    local list = {}
    if ns.Packs.Len(step.obj) > 0 then
        for _, i in ns.Packs.Each(step.obj) do list[#list + 1] = i end
    else
        for i = 1, #qs.need do list[#list + 1] = i end
    end
    for _, i in ipairs(list) do
        local text, kind = qs.text[i], qs.kind[i]
        -- loot goals have no mob to match by name (the user's answer: left out for now)
        if type(text) == "string" and #text >= TT.MIN_NAME and kind ~= "item" and (qs.need[i] or 0) > 0 then
            idx.names[#idx.names + 1] = { key = text:lower(), e = e, i = i, kind = kind }
        end
    end
end

-- A cheap stamp of the goals shown right now (guide, current step, background goals). Checked on each hover, so
-- a goal that hands over or drops out without a bus event (tester-beta4 issue 3) still rebuilds the index.
local function Stamp()
    local E = ns.Engine
    if not (E and E.Current) then return "", nil, nil end
    local cur, top = E.Current()
    if not (cur and top) then return "", nil, nil end
    local bg = top:Background()
    local parts = { tostring(top), tostring(cur.id), tostring(top.pos) }
    for _, b in ipairs(bg) do parts[#parts + 1] = tostring(b.id) end
    return table.concat(parts, "|"), cur, top, bg
end

function TT.Index()
    local stamp, cur, top, bg = Stamp()
    if not TT.dirty and TT.idx and stamp == TT.stamp then return TT.idx end
    local idx = { byNpc = {}, names = {}, seen = {} }
    TT.idx, TT.dirty, TT.stamp = idx, false, stamp
    TT.stats.rebuilds = TT.stats.rebuilds + 1
    if not (cur and top) then return idx end
    AddStep(idx, top, cur, "step")
    -- the rest of the current any-order group counts as the current step too
    local pos = top.pos
    local s0 = pos and top:Step(top:GroupStart(pos))
    if s0 and s0.anyOrder then
        for j = top:GroupStart(pos), top:Count() do
            local s = top:Step(j)
            if not s or s.anyOrder ~= s0.anyOrder then break end
            if top:IsStop(s, j) then AddStep(idx, top, s, "step") end
        end
    end
    for _, b in ipairs(bg) do AddStep(idx, top, b, "onway") end
    return idx
end

function TT.MarkDirty() TT.dirty = true end

-- ------------------------------------------------------------------ reading the tooltip data
-- the npc id from tooltipData.guid (Creature / Vehicle only; secret / player / pet / object -> nil)
local function NpcOf(data)
    local g = data.guid
    if Co.IsSecret(g) then return nil end
    local id, kind = Co.GuidNpcId(g)
    if kind ~= "npc" then return nil end
    return id
end

-- the first line's text, lowercased (nil when missing or secret)
local function NameOf(data)
    local lines = data.lines
    if Co.IsSecret(lines) or type(lines) ~= "table" then return nil end
    local l1 = lines[1]
    if Co.IsSecret(l1) or type(l1) ~= "table" then return nil end
    local t = l1.leftText
    if not Plain(t) or #t < TT.MIN_NAME then return nil end
    return t:lower()
end

-- "kobold vermin" starts "kobold vermin slain" as whole words ("wolf" never matches "young wolf slain")
local function Prefix(key, name)
    if key:sub(1, #name) ~= name then return false end
    local nx = key:sub(#name + 1, #name + 1)
    return nx == "" or not nx:find("[%w\128-\255]")
end
TT.Prefix = Prefix

-- true when the tooltip already has one of our objective texts in a game quest line (or might: secret)
local function AlreadyShown(data, keys)
    local QO = TT.QUEST_LINE
    if not QO or #keys == 0 then return false end
    local lines = data.lines
    if Co.IsSecret(lines) or type(lines) ~= "table" then return false end
    for n = 1, TT.MAX_SCAN do
        local ln = lines[n]
        if ln == nil then break end
        if Co.IsSecret(ln) then return true end
        if type(ln) == "table" then
            local t = ln.type
            if Co.IsSecret(t) then return true end
            if t == QO then
                local txt = ln.leftText
                if Co.IsSecret(txt) then return true end
                if type(txt) == "string" then
                    local low = txt:lower()
                    for _, k in ipairs(keys) do
                        if low:find(k, 1, true) then return true end
                    end
                end
            end
        end
    end
    return false
end
TT.AlreadyShown = AlreadyShown

function TT.QuestieShown()
    if TT.questie == nil then
        local f = Co.fn.IsAddOnLoaded
        local ok, v = pcall(function() return f and f("Questie") end)
        TT.questie = ok and v == true
    end
    return TT.questie
end

-- ------------------------------------------------------------------ the lines
local function Fill(key, fields) return ns.U.Fill(ns.L[key], fields) end

local function Count(have, need) return ("%d/%d"):format(math.min(have, need), need) end

-- one objective of a quest in the snapshot: text + count, done flag (nil = not usable)
local function ObjLine(e, i)
    local qs = ns.GameState.Quest(e.step.quest)
    if not qs then return nil end
    local need, have = qs.need[i], qs.have[i] or 0
    if type(need) ~= "number" or need <= 0 then return nil end
    local text = qs.text[i]
    if type(text) ~= "string" or text == "" then text = e.top:Text(e.step) end
    return text .. " " .. Count(have, need), have >= need, text:lower()
end

-- the lines of an npc-matched step: its open objectives (with counts), else its own text (accept / turn-in)
local function StepLines(e, out)
    local s, GS = e.step, ns.GameState
    if s.item and not s.quest then
        local need = s.count or 1
        local have = GS.ItemCount(s.item)
        out[#out + 1] = { e = e, text = e.top:Text(s) .. " " .. Count(have, need), done = have >= need }
        return
    end
    local qs = s.quest and GS.InLog(s.quest) and GS.Quest(s.quest)
    if qs and (s.type == "objective" or s.type == "useitem") then
        local list = {}
        if ns.Packs.Len(s.obj) > 0 then
            for _, i in ns.Packs.Each(s.obj) do list[#list + 1] = i end
        else
            for i = 1, #qs.need do list[#list + 1] = i end
        end
        local n0 = #out
        for _, i in ipairs(list) do
            local text, done, key = ObjLine(e, i)
            if text then out[#out + 1] = { e = e, text = text, done = done, key = key } end
        end
        if #out > n0 then return end
    end
    local text = e.top:Text(s)
    if Plain(text) then out[#out + 1] = { e = e, text = text, done = false } end
end

-- Pure: the lines for this tooltip data. kind "unit" / "object".
function TT.LinesFor(data, kind, mode)
    if mode == "off" or Co.IsSecret(data) or type(data) ~= "table" then return {} end
    local idx = TT.Index()
    local found = {}
    -- 1. the npc id from the GUID (units only: the pack's npc field)
    local npc = kind == "unit" and NpcOf(data) or nil
    if npc and idx.byNpc[npc] then
        for _, e in ipairs(idx.byNpc[npc]) do StepLines(e, found) end
    end
    -- 2. the name against the open objectives' texts (kill objectives for units, use objectives for objects)
    if #found == 0 then
        local name = NameOf(data)
        if name then
            for _, n in ipairs(idx.names) do
                local fits = n.kind == nil or (kind == "unit" and n.kind == "monster") or (kind == "object" and n.kind == "object")
                if fits and Prefix(n.key, name) then
                    local text, done, key = ObjLine(n.e, n.i)
                    if text then found[#found + 1] = { e = n.e, text = text, done = done, key = key } end
                end
            end
        end
    end
    if #found == 0 then return {} end
    -- current-step lines first, then the on-the-way ones; open before done; at most MAX_LINES
    table.sort(found, function(a, b)
        if a.e.where ~= b.e.where then return a.e.where == "step" end
        if a.done ~= b.done then return not a.done end
        return false
    end)
    local keys = {}
    for _, f in ipairs(found) do if f.key then keys[#keys + 1] = f.key end end
    local short = mode == "short" or TT.QuestieShown() or AlreadyShown(data, keys)
    local out, seen = {}, {}
    for _, f in ipairs(found) do
        local text, color
        if short then
            text = f.e.where == "step" and ns.L.TIPSTEP_SHORT or ns.L.TIPSTEP_SHORT_ONWAY
            color = f.e.where == "step" and "tipStep" or "tipOnWay"
        else
            local body = f.done and Fill("TIPSTEP_DONE", { text = f.text }) or f.text
            text = Fill(f.e.where == "step" and "TIPSTEP_STEP" or "TIPSTEP_ONWAY", { text = body })
            color = f.done and "tipDone" or (f.e.where == "step" and "tipStep" or "tipOnWay")
        end
        if Plain(text) and not seen[text] then
            seen[text] = true
            out[#out + 1] = { text = text, color = color }
            if #out >= TT.MAX_LINES then break end
        end
    end
    return out
end

-- ------------------------------------------------------------------ the post-calls
local function OnTooltip(kind, tooltip, data)
    if tooltip ~= TT.tip then return end          -- GameTooltip only (not ItemRefTooltip, shopping tips ...)
    local mode = TT.Mode()
    if mode == "off" then return end
    TT.stats.hovers = TT.stats.hovers + 1
    local lines = TT.LinesFor(data, kind, mode)
    if #lines > 0 then TT.stats.hits = TT.stats.hits + 1 end
    for _, l in ipairs(lines) do
        local r, g, b = Th.Color(l.color)
        tooltip:AddLine(l.text, r, g, b, true)
        TT.stats.lines = TT.stats.lines + 1
    end
end

function TT.Register()
    if TT.registered > 0 then return true end
    TT.tip = Co.fn.GameTooltip
    TT.UNIT = EnumValue("TooltipDataType", "Unit")
    TT.OBJECT = EnumValue("TooltipDataType", "Object")
    TT.QUEST_LINE = EnumValue("TooltipDataLineType", "QuestObjective")
    if not TT.tip or not Co.fn.TipPostCall then return false end
    local H, n = ns.Hooks, 0
    if TT.UNIT and H.TooltipPost(TT.UNIT, function(tip, data) OnTooltip("unit", tip, data) end, FEATURE) then n = n + 1 end
    if TT.OBJECT and H.TooltipPost(TT.OBJECT, function(tip, data) OnTooltip("object", tip, data) end, FEATURE) then n = n + 1 end
    TT.registered = n
    TT.QuestieShown()
    return n > 0
end

ns.Bus.On("Login", TT, function() TT.Register() end, FEATURE, 56)
for _, ev in ipairs({ "StepChanged", "QuestsChanged", "PackLoaded", "LevelChanged", "ItemsChanged" }) do
    ns.Bus.On(ev, TT, TT.MarkDirty, FEATURE, 90)
end
ns.Bus.On("SettingsChanged", TT, function(_, key)
    if key == "tooltipStep" then TT.MarkDirty() end
end, FEATURE, 90)

-- ------------------------------------------------------------------ self-check
-- Both post-calls are in; the index builds; a made-up tooltip for the current step's first named objective gives
-- a line, an empty one gives none. Never touches GameTooltip.
function TT.Problem()
    if TT.Mode() == "off" then return nil end
    if Co.fn.TipPostCall and TT.tip and TT.registered < 2 then return "post-calls not registered" end
    TT.MarkDirty()
    local idx = TT.Index()
    local n = idx.names[1]
    if n then
        local data = { guid = nil, lines = { { leftText = n.key } } }
        if #TT.LinesFor(data, n.kind == "object" and "object" or "unit", "full") == 0 then
            return "no line for the current step's objective"
        end
    end
    if #TT.LinesFor({ lines = {} }, "unit", "full") > 0 then return "a line for an empty tooltip" end
    return nil
end

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "tooltip step", fn = function(h)
    h.Count()
    if TT.Mode() == "off" then return h.Info("tooltip step off") end
    local bad = TT.Problem()
    if bad then h.Problem("tooltip step: " .. bad) end
    h.Info(("tooltip step %s, post-calls %d, hovers %d, lines %d"):format(TT.Mode(), TT.registered, TT.stats.hovers, TT.stats.lines))
end }

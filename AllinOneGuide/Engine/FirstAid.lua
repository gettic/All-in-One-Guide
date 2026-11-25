-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 dynamic First Aid "level up" lines (the user's wish 2026-11-25; tos OK, plans\first-aid):
--   * "Optional: make N <bandage> (First Aid a to b)" when the bags hold cloth for the bandage that fits
--     the skill now (N = what the cloth allows, at most the points left on that bandage)
--   * "Optional: train <rank> First Aid at <the next First Aid trainer the route passes>" once the skill
--     reaches a rank's training point and the cap is still below it (caps / costs marked unconfirmed)
--   They ride along under the current step like optional steps and change or go away as the skill rises.
--   Read only: C_SkillInfo by id (or the index scan; never Expand / CollapseSkillHeader: a First Aid line
--   under a collapsed header shows its text without numbers) and bag counts. Never crafts or trains, no
--   secure buttons. Reads only on SKILL_LINES_CHANGED / CHAT_MSG_SKILL (debounced) and the cloth's
--   ItemsChanged (GameState, after BAG_UPDATE_DELAYED); never in OnUpdate. Setting: firstAidSteps.
--   ns.FirstAid.Rank(name), .Read(), .Update(), .Lines() -> { text, ... }, .On(); bus SkillChanged, FirstAidChanged
local _, ns = ...
local Co, GS = ns.Compat, ns.GameState
local FA = { rank = nil, max = nil, hidden = false, lines = {}, stats = { reads = 0, updates = 0 }, DEBOUNCE = 0.5 }
ns.FirstAid = FA

local function L() return ns.L end
local function D() return ns.FirstAidData end

function FA.On() return ns.Settings.Get("firstAidSteps") ~= false end

-- The skill rank for a condition name (skill=firstaid>=50); nil = not learned / unknown.
function FA.Rank(name)
    if name == "firstaid" then return FA.rank end
    return nil
end

-- The bandage to make at this rank (nil past the table).
function FA.Recipe(rank)
    for _, r in ipairs(D().recipes) do
        if rank >= r.from and rank < r.to then return r end
    end
    return nil
end

local function ItemName(id, fallback) return Co.ItemName(id) or fallback end

-- The next First Aid trainer for a rank on the focused route, from the current step on; nil when none.
function FA.TrainerOnRoute(rank)
    local g = ns.Engine and ns.Engine.Focused and ns.Engine.Focused()
    local top = g and g:Top()
    if not top then return nil end
    local set = {}
    for _, id in ipairs(rank.trainers or {}) do set[id] = true end
    if not next(set) then return nil end
    for i = top.pos or 1, top:Count() do
        local s = top:Step(i)
        if s and s.npc and set[s.npc] then return s end
    end
    return nil
end

local function Place(s)
    if not (s and s.map and s.x and s.y) then return L().FA_TRAINER_ANY end
    return ns.U.Fill(L().FA_TRAINER_AT, { zone = Co.MapName(s.map) or ("#" .. s.map),
        x = ("%.1f"):format(s.x * 100), y = ("%.1f"):format(s.y * 100) })
end

-- Works out the lines (FA.lines) from the last read; fires FirstAidChanged when they change.
function FA.Update(quiet)
    FA.stats.updates = FA.stats.updates + 1
    local out = {}
    if FA.On() and D() then
        local rank, max = FA.rank, FA.max
        if FA.hidden then
            -- under a collapsed header: no numbers, only what the cloth allows
            for _, key in ipairs({ "linen", "wool", "silk" }) do
                local id = D().cloth[key]
                if Co.ItemCount(id) > 0 then
                    out[#out + 1] = ns.U.Fill(L().FA_MAKE_ANY, { cloth = ItemName(id, L()["FA_CLOTH_" .. key:upper()]) })
                    break
                end
            end
        elseif type(rank) == "number" then
            -- training first: a rank whose training point is reached and whose cap isn't there yet
            for _, r in ipairs(D().ranks) do
                if rank >= r.at and (max == nil or max < r.cap) then
                    local text = ns.U.Fill(L().FA_TRAIN, { rank = L()["FA_RANK_" .. r.key] or r.key,
                        place = Place(FA.TrainerOnRoute(r)) })
                    if r.confirmed == false then text = text .. " " .. L().FA_UNCONFIRMED end
                    out[#out + 1] = text
                    break
                end
            end
            local capped = max ~= nil and rank >= max
            local rec = not capped and FA.Recipe(rank)
            if rec then
                local crafts = math.floor(Co.ItemCount(rec.cloth) / rec.per)
                local top = rec.to
                if max then top = math.min(top, max) end
                local n = math.min(crafts, top - rank)
                if n >= 1 then
                    out[#out + 1] = ns.U.Fill(L().FA_MAKE, { n = n, item = ItemName(rec.item, L().FA_BANDAGES),
                        from = rank, to = rank + n })
                end
            end
        end
    end
    local same = #out == #FA.lines
    if same then for i, t in ipairs(out) do if FA.lines[i] ~= t then same = false end end end
    FA.lines = out
    if not same and not quiet then ns.Bus.Fire("FirstAidChanged") end
    return out
end

-- The lines for the window. Another guide or step in focus = the "next trainer" may differ: worked out
-- again here, quietly (the window is already drawing).
function FA.Lines()
    local g = ns.Engine and ns.Engine.Focused and ns.Engine.Focused()
    local key = g and (g.key .. ":" .. tostring(g:Top().pos)) or ""
    if key ~= FA.focusKey then
        FA.focusKey = key
        if FA.rank then FA.Update(true) end
    end
    return FA.lines
end

-- Reads the skill (debounced callers only).
function FA.Read()
    FA.stats.reads = FA.stats.reads + 1
    if not FA.watching and D() then
        -- the cloth counts, watched from the first read on (not at login: keeps the login short)
        FA.watching = true
        for _, id in pairs(D().cloth) do GS.WatchItem(id) end
    end
    local r, m = Co.SkillRank(D() and D().skillLine or 129)
    local hidden = r == "hidden"
    if hidden then r, m = nil, nil end
    local changed = r ~= FA.rank or m ~= FA.max or hidden ~= FA.hidden
    FA.rank, FA.max, FA.hidden = r, m, hidden
    if changed then ns.Bus.Fire("SkillChanged", "firstaid") end
    FA.Update()
end

local function Queue() ns.Events.Debounce("firstaid", FA.DEBOUNCE, FA.Read, "firstaid") end

ns.Bus.On("Login", FA, function()
    local E = ns.Events
    E.On("SKILL_LINES_CHANGED", FA, Queue, "firstaid")
    E.On("CHAT_MSG_SKILL", FA, Queue, "firstaid")
    Queue()
end, "firstaid", 50)

ns.Bus.On("ItemsChanged", FA, function(_, changed)
    if type(changed) ~= "table" or not D() then return end
    for _, id in pairs(D().cloth) do
        if changed[id] then return ns.Errors.Call("firstaid", FA.Update) end
    end
end, "firstaid")
ns.Bus.On("SettingsChanged", FA, function(_, key)
    if key == "firstAidSteps" then ns.Errors.Call("firstaid", FA.Update) end
end, "firstaid")
ns.Bus.On("FirstAidChanged", FA, function() if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end end, "firstaid", 80)

-- In-game self-test: the skill reads and the lines (numbers only).
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "firstaid", fn = function(h)
    h.Count()
    if not D() then h.Problem("FA", "data", "FirstAidData missing") return end
    h.Info(("firstaid rank %s/%s%s, lines %d, reads %d"):format(tostring(FA.rank or "-"), tostring(FA.max or "-"),
        FA.hidden and " (collapsed)" or "", #FA.lines, FA.stats.reads))
end }

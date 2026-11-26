-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- One Guide object per active guide (and one per detour on its stack).
-- Progress comes from the game; the save holds only the current step id, a pin, manual skips and the
-- detour stack. Rules:
--   * a step is a stop when it applies (condition), isn't skipped, isn't done, and isn't a travel step
--     whose target is already done (leadsTo auto-skip)
--   * whileUntil steps are background goals: passed over, shown next to the current step, and they
--     become the current step when their target step is reached and they're still not done
--   * a quest needed by the current step that is gone from the log (abandoned) sends the guide back to
--     its accept step; a full quest log is reported as the status "logfull"
--   * Set current / Back pin a step (it stays even when done) until Next, Skip or it gets done
local _, ns = ...
local P, ST, Cd, GS = ns.Packs, ns.StepTypes, ns.Conditions, ns.GameState

local Guide = {}
Guide.__index = Guide
ns.Guide = Guide

-- save = { current, pin, skips, keeps, mode, stack } (DB.Guide, or a stack entry for a detour)
function Guide.New(key, route, save)
    local g = setmetatable({ key = key, route = route, save = save, header = route.header or {},
        pos = 1, bg = {}, reached = {}, static = {}, pinned = false, pinDone = false, status = nil,
        child = nil, needsLoad = true }, Guide)
    save.skips = type(save.skips) == "table" and save.skips or {}
    save.stack = type(save.stack) == "table" and save.stack or {}
    -- v0.2: steps ticked by hand, quests the player isn't doing (only written when used)
    if type(save.done) ~= "table" then save.done = nil end
    if type(save.notDoing) ~= "table" then save.notDoing = nil end
    return g
end

function Guide:Count() return P.Count(self.route) end
function Guide:Step(i) return P.GetStep(self.route, i) end
function Guide:IndexOf(id) return P.IndexOf(self.route, id) end

-- v0.2: the item ids this route's conditions ask about (cond item=<id>), found once per route: only rows
-- with "item=" in them are decoded. The engine watches these so such a step shows / hides on bag changes.
function Guide:CondItems()
    local r = self.route
    if r.condItems then return r.condItems end
    local set = {}
    if r.steps then
        for _, s in ipairs(r.steps) do
            if s.cond then Cd.Items(Cd.Get(s.cond), set) end
        end
    else
        for _, row in ipairs(r.rows or {}) do
            if type(row) == "string" and row:find("item=", 1, true) then
                local s = ns.Format.DecodeRow(row)
                if s and s.cond then Cd.Items(Cd.Get(s.cond), set) end
            end
        end
    end
    r.condItems = set
    return set
end

-- Follows renamedSteps (old id -> new id), at most 10 hops.
function Guide:Resolve(id)
    local ren = self.header.renamedSteps
    if type(ren) ~= "table" then return id end
    for _ = 1, 10 do
        local nxt = ren[id]
        if not nxt then break end
        id = nxt
    end
    return id
end

-- ------------------------------------------------------------------ step tests
function Guide:Applicable(step, ignoreLevel)
    if step.bad then return false end
    -- v0.2: a minimum level (checked live, never cached; ignoreLevel = would it fit once the level is there)
    if step.minLevel and not ignoreLevel then
        local lv = ns.Engine.ctx.level
        if type(lv) == "number" and lv < step.minLevel then return false end
    end
    if not step.cond then return true end
    local ast = step.condAst
    if not ast then return false end
    if ast.info.dynamic then return Cd.Check(ast, ns.Engine.ctx) end
    local v = self.static[step.cond]
    if v == nil then
        v = Cd.Check(ast, ns.Engine.ctx)
        self.static[step.cond] = v
    end
    return v
end

-- Shown ahead as "not yet possible" (future flag, condition false).
function Guide:IsFuture(step)
    return step.flags.future == true and not self:Applicable(step)
end

-- Skipped by the player, or its quest is "not doing" (with its follow-ups), or not on this server.
function Guide:Skipped(step)
    if self.save.skips[step.id] == true then return true end
    local q = step.quest
    if q then
        if self.save.notDoing and next(self.save.notDoing) and self:Dropped(q) then return true end
        if ns.QuestData and ns.QuestData.NotAvailable(q) then return true end
        if self:Held(q) then return true end
    end
    return false
end

-- Why a step is passed over: "skip", "notdoing", "na", "notoffered" or nil.
function Guide:SkipReason(step)
    if self.save.skips[step.id] == true then return "skip" end
    local q = step.quest
    if q and self.save.notDoing and next(self.save.notDoing) and self:Dropped(q) then return "notdoing" end
    if q and ns.QuestData and ns.QuestData.NotAvailable(q) then return "na" end
    if q and self:Held(q) then return "notoffered" end
    return nil
end

-- Quest giver check (Engine\QuestGiver.lua): the quest's NPC didn't offer it, or it follows (through `pre`)
-- a quest that wasn't offered. Its steps wait until the mark is cleared.
function Guide:Held(q, depth)
    local QG = ns.QuestGiver
    if not (QG and QG.any) then return false end
    if QG.Marked(q) then return true end
    depth = depth or 0
    if depth > 10 then return false end
    for _, p in ipairs(self:PreMap()[q] or {}) do
        if not GS.IsDone(p) and self:Held(p, depth + 1) then return true end
    end
    return false
end

-- Quest giver check: quest q may be offered again. Its accept step ahead of the current step needs nothing
-- (the route gets there); one behind comes back as a background goal only when near(step) says so (least
-- travel: never sends the player back). Once accepted, its later steps behind come back too (Refresh).
function Guide:BringBack(q, near)
    local list = self:AcceptsOf()[q]
    if not list then return false end
    for _, i in ipairs(list) do
        local s = self:Step(i)
        if s and i < self.pos and self:IsStop(s, i) and near(s) then
            for _, b in ipairs(self.bg) do if b == i then return true end end
            self.bg[#self.bg + 1] = i
            self.backQuests = self.backQuests or {}
            self.backQuests[q] = true
            return true
        end
    end
    return false
end

-- ------------------------------------------------------------------ not doing a quest (v0.2)
-- quest -> its pre-quests, from the steps' `pre` lists (built once per guide, on first use)
function Guide:PreMap()
    if self.preOf then return self.preOf end
    local map = {}
    for i = 1, self:Count() do
        local s = self:Step(i)
        if s and s.quest and P.Len(s.pre) > 0 then
            local list = map[s.quest] or {}
            for _, p in P.Each(s.pre) do list[#list + 1] = p end
            map[s.quest] = list
        end
    end
    self.preOf = map
    return map
end

-- A quest is dropped when the player isn't doing it, or it follows (through `pre`) one that is dropped.
function Guide:Dropped(q, depth)
    local nd = self.save.notDoing
    if not nd then return false end
    if nd[q] then return true end
    depth = depth or 0
    if depth > 10 then return false end
    for _, p in ipairs(self:PreMap()[q] or {}) do
        if self:Dropped(p, depth + 1) then return true end
    end
    return false
end

function Guide:NotDoing(q, on)
    if type(q) ~= "number" then return false end
    if on == false then
        if self.save.notDoing then self.save.notDoing[q] = nil end
    else
        self.save.notDoing = self.save.notDoing or {}
        self.save.notDoing[q] = true
    end
    self.pinned = false
    self:Advance()
    self:Store()
    return true
end

-- Undo support: what the player's actions change, as a copy; Restore puts it back.
function Guide:Snapshot()
    local U = ns.U
    return { pos = self.pos, pinned = self.pinned, pinDone = self.pinDone, skips = U.Copy(self.save.skips),
        notDoing = self.save.notDoing and U.Copy(self.save.notDoing) or nil,
        done = self.save.done and U.Copy(self.save.done) or nil }
end

function Guide:Restore(snap)
    self.pos, self.pinned, self.pinDone = snap.pos, snap.pinned, snap.pinDone
    self.save.skips, self.save.notDoing, self.save.done = snap.skips, snap.notDoing, snap.done
    self:Store()
end

-- ------------------------------------------------------------------ levels and the quest log (v0.2)
-- For a step that waits for a level: levels to go, XP now, XP needed for the next level (or nil).
function Guide:UnderLevel(step)
    local need = step.minLevel or ((step.type == "grind" or step.type == "level") and step.level) or nil
    local lv = ns.Engine.ctx.level
    if not need or type(lv) ~= "number" or lv >= need then return nil end
    local GS2 = ns.GameState
    return need - lv, GS2.xp, GS2.xpMax
end

-- The quest ids this route uses (built once).
function Guide:RouteQuests()
    if self.routeQuests then return self.routeQuests end
    local set = {}
    for i = 1, self:Count() do
        local s = self:Step(i)
        if s and s.quest then set[s.quest] = true end
    end
    self.routeQuests = set
    return set
end

-- quest -> the indexes of its accept steps, in route order (built once; optimizer #1: CheckQuest no longer
-- walks back to step 1 on every refresh while a quest is missing)
function Guide:AcceptsOf()
    if self.acceptsOf then return self.acceptsOf end
    local map = {}
    for i = 1, self:Count() do
        local a = self:Step(i)
        if a and a.type == "accept" and a.quest then
            local l = map[a.quest] or {}
            l[#l + 1] = i
            map[a.quest] = l
        end
    end
    self.acceptsOf = map
    return map
end

-- NPC talk helper: quest -> { accept = {indexes}, turnin = {indexes} }, in route order (built once, like
-- AcceptsOf). Read only by UI\NpcHelper.lua.
function Guide:QuestSteps()
    if self.questSteps then return self.questSteps end
    local map = {}
    for i = 1, self:Count() do
        local s = self:Step(i)
        if s and s.quest and (s.type == "accept" or s.type == "turnin") then
            local e = map[s.quest] or { accept = {}, turnin = {} }
            local l = e[s.type]
            l[#l + 1] = i
            map[s.quest] = e
        end
    end
    self.questSteps = map
    return map
end

-- Quests in the log the route never uses (for the "quest log full" hint), sorted.
function Guide:UnneededLogQuests()
    local set, out = self:RouteQuests(), {}
    for id in pairs(GS.quests) do
        if not set[id] then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

function Guide:Done(step)
    local d = ST.Get(step.type).Done(step, self)
    if not d and step.overrideAst then d = Cd.Check(step.overrideAst, ns.Engine.ctx) end
    return d == true
end

-- A travel step whose target (leadsTo, or the next non-travel step) is already done.
function Guide:TravelDone(step, i)
    if not ST.Get(step.type).travel then return false end
    local target
    if step.leadsTo then
        local j = self:IndexOf(step.leadsTo)
        target = j and self:Step(j)
    else
        local n = self:Count()
        -- background goals (whileUntil) and optional steps ride along: they are never what a walk leads to
        -- (fix: a walk followed by an already-done "as you go" goal skipped itself)
        for j = i + 1, n do
            local s = self:Step(j)
            if s and not ST.Get(s.type).travel and not s.whileUntil and not s.flags.optional then
                target = s
                break
            end
        end
    end
    if not target or not self:Applicable(target) then return false end
    return self:Done(target)
end

function Guide:IsStop(step, i)
    return self:Applicable(step) and not self:Skipped(step) and not self:Done(step) and not self:TravelDone(step, i)
end

-- Travel side goals (hand-over): a background goal whose target is an objective step of the same quest isn't
-- due there; that step shows the same objectives at the right spot, so the goal just stops riding along.
-- Only when that step covers the goal's objectives (its obj list is empty = all, or holds each of the goal's;
-- the same rule as tools\packlib.lua Lib.Covers). Returns the target's index for such a goal, else nil.
local function Covers(t, s)
    local Pk = ns.Packs
    if Pk.Len(t.obj) == 0 then return true end
    if Pk.Len(s.obj) == 0 then return false end
    local have = {}
    for _, i in Pk.Each(t.obj) do have[i] = true end
    for _, i in Pk.Each(s.obj) do if not have[i] then return false end end
    return true
end

function Guide:HandOverAt(step)
    local u = step.whileUntil and step.quest and self:IndexOf(step.whileUntil)
    if not u then return nil end
    local t = self:Step(u)
    if t and t.type == "objective" and t.quest == step.quest and not t.whileUntil and Covers(t, step) then return u end
    return nil
end

-- True when a hand-over goal's target has been reached (it no longer shows).
function Guide:HandedOver(step)
    local u = self:HandOverAt(step)
    return u ~= nil and self.pos >= u
end

-- A background step waiting for the step `id` (it must be done there), or nil.
function Guide:WaitingFor(id)
    for _, b in ipairs(self.bg) do
        local s = self:Step(b)
        if s and s.whileUntil == id and self:IsStop(s, b) and not self:HandOverAt(s) then return b end
    end
end

-- ------------------------------------------------------------------ moving
local AddOptional

local function AddBg(self, i)
    for _, b in ipairs(self.bg) do if b == i then return end end
    self.bg[#self.bg + 1] = i
end

-- Optional steps ride along as background goals; at most this many at once (the oldest drop out).
local MAX_OPTIONAL = 3
Guide.ITEM_BACK = 15   -- an optional item step this many steps back still comes back when the item shows up

-- An optional turn-in / objective step whose quest isn't in the log and isn't done (beta.8 fix: the book turn-ins
-- showed as "Optional:" lines to players who never got the book). It waits in the background list unseen and shows
-- once the quest is in the log; optional accept steps never wait like this. Same quest rule as CheckQuest.
function Guide:WaitsForQuest(s)
    local q = s and s.flags.optional and (s.type == "turnin" or s.type == "objective") and not s.item and s.quest
    return q and not GS.InLog(q) and not GS.IsDone(q) or false
end

function AddOptional(self, i)
    for _, b in ipairs(self.bg) do if b == i then return end end
    -- the cap counts only the optional goals that show (one waiting for its quest takes no place)
    local n = 0
    for _, b in ipairs(self.bg) do
        local s = self:Step(b)
        if s and s.flags.optional and not self:WaitsForQuest(s) then n = n + 1 end
    end
    if n >= MAX_OPTIONAL then
        for k, b in ipairs(self.bg) do
            local s = self:Step(b)
            if s and s.flags.optional and not self:WaitsForQuest(s) then table.remove(self.bg, k) break end
        end
    end
    self.bg[#self.bg + 1] = i
end

-- Any-order group (`anyOrder`): the first index of the run of steps sharing s.anyOrder around i.
function Guide:GroupStart(i)
    local s = self:Step(i)
    local g = s and s.anyOrder
    if not g then return i end
    while i > 1 do
        local p = self:Step(i - 1)
        if not p or p.anyOrder ~= g then break end
        i = i - 1
    end
    return i
end

-- Among the stops of the any-order run starting at i: the nearest one (route order without a position).
function Guide:PickInGroup(i)
    local first = self:Step(i)
    local g = first.anyOrder
    local n = self:Count()
    local best, bestD
    local j = i
    while j <= n do
        local s = self:Step(j)
        if not s or s.anyOrder ~= g then break end
        if self:IsStop(s, j) and not s.flags.optional then
            local d = (s.map and s.x and s.y) and ns.Geo.PlayerDistance(s.map, s.x, s.y) or nil
            if not best then
                best, bestD = j, d
            elseif d and (not bestD or d < bestD) then
                best, bestD = j, d
            end
        end
        j = j + 1
    end
    return best
end

function Guide:Advance()
    local n = self:Count()
    local i = self:GroupStart(self.pos)
    while i <= n do
        local s = self:Step(i)
        -- a step passed over only for its level comes back once the level is there (see Refresh)
        if s and s.minLevel and not self:Applicable(s) and self:UnderLevel(s) then
            self.levelWait = self.levelWait or {}
            self.levelWait[i] = true
        end
        -- v0.2: an optional step for an item not in the bags yet (cond item=) comes back when it is
        if s and s.flags.optional and s.condAst and next(Cd.Items(s.condAst)) and not self:Applicable(s) then
            self.itemWait = self.itemWait or {}
            self.itemWait[i] = true
        end
        if s then
            if self:WaitingFor(s.id) then
                self.pos = i
                return
            end
            if self:IsStop(s, i) then
                local untilIndex = s.whileUntil and self:IndexOf(s.whileUntil)
                if untilIndex and untilIndex > i then
                    AddBg(self, i)
                elseif s.flags.optional then
                    AddOptional(self, i)   -- never blocks the route
                elseif s.anyOrder then
                    self.pos = self:PickInGroup(i) or i
                    return
                else
                    self.pos = i
                    return
                end
            end
        end
        i = i + 1
    end
    self.pos = n + 1
end

function Guide:Finished() return self.pos > self:Count() end

-- The step to show now (a waiting background step first), or nil when the route is finished.
function Guide:Current()
    if self:Finished() then return nil end
    local s = self:Step(self.pos)
    if not s then return nil end
    if not self.pinned then
        local w = self:WaitingFor(s.id)
        if w then return self:Step(w) end
    end
    return s
end

function Guide:CurrentId()
    local s = self:Current()
    return s and s.id or nil
end

-- Background goals shown next to the current step.
function Guide:Background()
    local out = {}
    for _, b in ipairs(self.bg) do
        local s = self:Step(b)
        if s and self:IsStop(s, b) and not self:HandedOver(s) and not self:WaitsForQuest(s) then out[#out + 1] = s end
    end
    return out
end

function Guide:Store()
    local id = self:CurrentId()
    self.save.current = id
    self.save.pin = self.pinned and id or nil
    self.save.finished = self:Finished() or nil
end

-- First refresh after opening: restore the saved position (following renames).
function Guide:Load()
    self.needsLoad = false
    local ren = self.header.renamedSteps
    if type(ren) == "table" then
        for old in pairs(ren) do
            if self.save.skips[old] then self.save.skips[self:Resolve(old)] = true end
        end
    end
    local cur = self.save.current and self:Resolve(self.save.current)
    local i = cur and self:IndexOf(cur)
    if i then
        self.pos = i
        if self.save.pin and self:Resolve(self.save.pin) == cur then
            self.pinned = true
            self.pinDone = self:Done(self:Step(i))
        end
        -- background goals left behind before the saved position
        for j = 1, i - 1 do
            local s = self:Step(j)
            local u = s and s.whileUntil and self:IndexOf(s.whileUntil)
            if u and u >= i and self:IsStop(s, j) and not self:HandedOver(s) then AddBg(self, j) end
            -- optional steps not done yet, from the last 15 steps
            if s and s.flags.optional and j >= i - 15 and self:IsStop(s, j) then AddOptional(self, j) end
            if s and s.flags.optional and j >= i - Guide.ITEM_BACK and s.condAst and next(Cd.Items(s.condAst))
                and not self:Applicable(s) then
                self.itemWait = self.itemWait or {}
                self.itemWait[j] = true
            end
            -- steps passed over for their level
            if s and s.minLevel and not self:Applicable(s) then
                self.levelWait = self.levelWait or {}
                self.levelWait[j] = true
            end
        end
    else
        self.pos = 1
    end
end

-- The quest the current step needs is gone (abandoned): back to its accept step, if there is one.
function Guide:CheckQuest()
    self.status = nil
    local s = self:Current()
    if not s then return end
    local q = s.quest
    if q and (s.type == "objective" or s.type == "turnin") and not s.item and not GS.InLog(q) and not GS.IsDone(q) then
        -- the nearest usable accept step before this one (same answer and order as walking back)
        local list = self:AcceptsOf()[q]
        for k = list and #list or 0, 1, -1 do
            local j = list[k]
            if j < s.index then
                local a = self:Step(j)
                if a and self:Applicable(a) and not self:Skipped(a) then
                    self.pos, self.pinned = j, false
                    return
                end
            end
        end
        self.status = "missing"
    elseif s.type == "accept" and not GS.InLog(s.quest or 0) then
        local max = GS.LogMax()
        if max and GS.LogCount() >= max then self.status = "logfull" end
    end
end

-- Re-evaluates; returns true when the current step changed.
function Guide:Refresh()
    if self.needsLoad then self:Load() end
    local before = self:CurrentId()
    -- drop finished background goals
    for k = #self.bg, 1, -1 do
        local s = self:Step(self.bg[k])
        if not s or not self:IsStop(s, self.bg[k]) or self:HandedOver(s)
            or (self:WaitsForQuest(s) and self.bg[k] < self.pos - Guide.ITEM_BACK) then   -- waited too far back
            table.remove(self.bg, k)
        end
    end
    -- v0.2: steps passed over for their level: once the level is there they are background goals
    -- (or the current step when the route had run out)
    if self.levelWait then
        for i in pairs(self.levelWait) do
            local s = self:Step(i)
            if not s or i >= self.pos then
                self.levelWait[i] = nil
            elseif self:Applicable(s) then
                self.levelWait[i] = nil
                if self:IsStop(s, i) then
                    if self.pos > self:Count() then self.pos = i else AddBg(self, i) end
                end
            end
        end
    end
    -- v0.2: optional item steps passed over (cond item=): once the item is in the bags they ride along
    -- as background goals; only the last ITEM_BACK steps are kept waiting
    if self.itemWait then
        for i in pairs(self.itemWait) do
            local s = self:Step(i)
            if not s or i >= self.pos or i < self.pos - Guide.ITEM_BACK then
                self.itemWait[i] = nil
            elseif self:Applicable(s) then
                self.itemWait[i] = nil
                if self:IsStop(s, i) then AddOptional(self, i) end
            end
        end
        if not next(self.itemWait) then self.itemWait = nil end
    end
    -- quest giver check: a quest brought back (BringBack) and now accepted: its objective / turn-in steps behind
    -- the current step ride along as background goals
    if self.backQuests then
        for q in pairs(self.backQuests) do
            if GS.InLog(q) then
                self.backQuests[q] = nil
                for i = 1, math.min(self.pos - 1, self:Count()) do
                    local s = self:Step(i)
                    if s and s.quest == q and s.type ~= "accept" and self:IsStop(s, i) then AddBg(self, i) end
                end
            elseif GS.IsDone(q) then
                self.backQuests[q] = nil
            end
        end
        if not next(self.backQuests) then self.backQuests = nil end
    end
    if self.pinned then
        local s = self:Step(self.pos)
        if not s or (not self.pinDone and self:Done(s)) then self.pinned = false end
    end
    if not self.pinned then
        self:CheckQuest()
        self:Advance()
        self:CheckQuest()
    end
    self:Store()
    return before ~= self:CurrentId()
end

-- ------------------------------------------------------------------ the player's actions
function Guide:Skip(id)
    local s
    if id ~= nil then
        local i = self:IndexOf(self:Resolve(id))
        if not i then return false end   -- unknown id: nothing changes
        s = self:Step(i)
    else
        s = self:Current()
    end
    if not s then return false end
    self.save.skips[s.id] = true
    if self.pinned and s.index == self.pos then self.pinned = false end
    self:Advance()
    self:Store()
    return true
end

function Guide:SetCurrent(id)
    local i = self:IndexOf(self:Resolve(id))
    if not i then return false end
    local s = self:Step(i)
    self.save.skips[s.id] = nil
    if self.save.done then self.save.done[s.id] = nil end
    self.pos, self.pinned, self.pinDone = i, true, self:Done(s)
    self:Store()
    return true
end

-- Back to the step before the current one (done or not); it stays pinned until Next.
function Guide:Back()
    local cur = self:Current()
    local from = cur and cur.index or (self:Count() + 1)
    for j = from - 1, 1, -1 do
        local s = self:Step(j)
        if s and self:Applicable(s) then return self:SetCurrent(s.id) end
    end
    return false
end

-- Moves on from the current step: a step that isn't done is marked skipped.
function Guide:Next()
    local cur = self:Current()
    if not cur then return false end
    if not self:Done(cur) then
        if ST.Get(cur.type).manualDone then
            -- steps the game can't confirm: "next" means the player did it
            self.save.done = self.save.done or {}
            self.save.done[cur.id] = true
        else
            self.save.skips[cur.id] = true
        end
    end
    if cur.index == self.pos then self.pos = self.pos + 1 end
    self.pinned = false
    self:Advance()
    self:Store()
    return true
end

-- ------------------------------------------------------------------ detours (guide stack)
-- steps: plain step tables; their ids become "<kind>:<id>:<n>" so they never clash with route ids.
function Guide:PushDetour(kind, id, steps, entry)
    local list = {}
    for n, s in ipairs(steps) do
        local c = {}
        for k, v in pairs(s) do c[k] = v end
        c.id = kind .. ":" .. id .. ":" .. n
        list[n] = c
    end
    local route = P.MakeRoute(kind .. ":" .. id, list)
    if not entry then
        entry = { kind = kind, id = id, skips = {} }
        self.save.stack[#self.save.stack + 1] = entry
    end
    local child = Guide.New(self.key .. ">" .. kind .. ":" .. id, route, entry)
    child.parent = self
    self.child = child
    return child
end

function Guide:PopDetour()
    local stack = self.save.stack
    if self.child then
        for k = #stack, 1, -1 do
            if stack[k] == self.child.save then table.remove(stack, k) break end
        end
    end
    self.child = nil
end

-- The guide whose step is shown (the deepest detour).
function Guide:Top()
    local g = self
    while g.child do g = g.child end
    return g
end

-- Refreshes the detour chain; a finished detour pops back to its parent.
function Guide:RefreshTree()
    local changed = false
    if self.child then
        if self.child:RefreshTree() then changed = true end
        if self.child:Finished() then
            self:PopDetour()
            changed = true
        end
    end
    if not self.child then
        if self:Refresh() then changed = true end
    end
    return changed
end

-- ------------------------------------------------------------------ text
-- The step's text in the chosen language with {quest} etc. filled in. wrap(field, value) may decorate
-- the filled values (the window colours quest names); plain text without it.
function Guide:Text(step, wrap)
    local L = ns.L
    local text = (ns.Locale.code == "daDK" and step.da) or step.text
    if not text then text = L[ST.Get(step.type).text] end
    if text:find("{", 1, true) then
        local qname = step.quest and ns.Names.Quest(step.quest, step.qname) or nil
        local fields = { quest = qname, level = step.level, count = step.count }
        if wrap then
            for k, v in pairs(fields) do fields[k] = wrap(k, v) end
        end
        text = ns.U.Fill(text, fields)
        -- {item:<id>} (beta.9 item pictures): the item's name; the window's wrap turns it into its icon + link
        if text:find("{item:", 1, true) then
            text = text:gsub("{item:(%d+)}", function(id)
                id = tonumber(id)
                local II = ns.ItemIcons
                local name = II and II.Token(id) or ns.L.ITEM_FALLBACK
                if wrap then return wrap("item", name, id) or name end
                return name
            end)
        end
    end
    return text
end

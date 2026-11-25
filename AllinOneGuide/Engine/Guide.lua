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
    return g
end

function Guide:Count() return P.Count(self.route) end
function Guide:Step(i) return P.GetStep(self.route, i) end
function Guide:IndexOf(id) return P.IndexOf(self.route, id) end

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
function Guide:Applicable(step)
    if step.bad then return false end
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

function Guide:Skipped(step) return self.save.skips[step.id] == true end

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
        for j = i + 1, n do
            local s = self:Step(j)
            if s and not ST.Get(s.type).travel then target = s break end
        end
    end
    if not target or not self:Applicable(target) then return false end
    return self:Done(target)
end

function Guide:IsStop(step, i)
    return self:Applicable(step) and not self:Skipped(step) and not self:Done(step) and not self:TravelDone(step, i)
end

-- A background step waiting for the step `id` (it must be done there), or nil.
function Guide:WaitingFor(id)
    for _, b in ipairs(self.bg) do
        local s = self:Step(b)
        if s and s.whileUntil == id and self:IsStop(s, b) then return b end
    end
end

-- ------------------------------------------------------------------ moving
local function AddBg(self, i)
    for _, b in ipairs(self.bg) do if b == i then return end end
    self.bg[#self.bg + 1] = i
end

function Guide:Advance()
    local n = self:Count()
    local i = self.pos
    while i <= n do
        local s = self:Step(i)
        if s then
            if self:WaitingFor(s.id) then
                self.pos = i
                return
            end
            if self:IsStop(s, i) then
                local untilIndex = s.whileUntil and self:IndexOf(s.whileUntil)
                if untilIndex and untilIndex > i then
                    AddBg(self, i)
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
        if s and self:IsStop(s, b) then out[#out + 1] = s end
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
            if u and u >= i and self:IsStop(s, j) then AddBg(self, j) end
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
        for j = s.index - 1, 1, -1 do
            local a = self:Step(j)
            if a and a.type == "accept" and a.quest == q and self:Applicable(a) and not self:Skipped(a) then
                self.pos, self.pinned = j, false
                return
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
        if not s or not self:IsStop(s, self.bg[k]) then table.remove(self.bg, k) end
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
    if not self:Done(cur) then self.save.skips[cur.id] = true end
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
    end
    return text
end

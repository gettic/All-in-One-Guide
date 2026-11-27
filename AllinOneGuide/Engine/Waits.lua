-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Waits countdown (v0.2.5 C6 display, the user's choice "Countdown now"; plans\v0.2.5-code\plan.md). Display only.
--   * timed quests (`waits = "timed"`, `timeLimit` minutes on the accept step): once the quest is in the log, the
--     time left on its own timer, from C_QuestLog.GetQuestTimers when the game gives it, else from the moment we saw
--     it accepted + timeLimit (saved per character, module `waits`, so a /reload keeps counting). Shown on every
--     step while it runs, until it's turned in, abandoned or out of time.
--   * escort / event / respawn (`waitMin` minutes): while that step is current, "wait up to" counts down from when it
--     came up (this session); at 0 it says so and the step stays (the player decides).
-- Light: no OnUpdate; a 1 s ticker runs only while something counts, and stops when nothing does.
--   ns.Waits.Running() -> list of { quest, left (s), limit (s), source = "game" | "ours" } (soonest first)
--   .ForStep(step) -> { kind, left (s) | nil, limit (s) } | nil    .Line() -> text, kind | nil   .Time(seconds) -> "m:ss"
--   bus: WaitsTick (once a second while counting; the window redraws the line)
local _, ns = ...
local Co = ns.Compat
local WT = { ticker = nil, stepAt = {}, ticks = 0 }
ns.Waits = WT

local function Store(write)
    if write and not ns.safeMode and not (ns.DB.readOnly and ns.DB.readOnly.char) then
        local m = ns.DB.Module("waits", "char", 1)
        if type(m.timed) ~= "table" then m.timed = {} end
        return m
    end
    local mods = ns.DB.char and ns.DB.char.modules
    return type(mods) == "table" and type(mods.waits) == "table" and mods.waits or nil
end

function WT.Time(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

-- A timed accept step that is done (quest now in the log): remember when, once.
local function NoteAccepted(step)
    if not (step and step.waits == "timed" and step.type == "accept" and step.quest and step.timeLimit) then return end
    if not ns.GameState.InLog(step.quest) then return end
    local m = Store(false)
    if m and m.timed and m.timed[step.quest] then return end
    m = Store(true)
    if not m then return end
    -- server time survives a relog; the client clock (GetTime) is the fallback when the server time is unknown
    m.timed[step.quest] = { start = Co.ServerTime(), at = Co.Now(), limit = step.timeLimit }
end

function WT.Running()
    local out = {}
    local m = Store(false)
    local now = Co.ServerTime()
    for quest, e in pairs(m and m.timed or {}) do
        if type(quest) == "number" and type(e) == "table" and ns.GameState.InLog(quest) then
            local limit = (tonumber(e.limit) or 0) * 60
            local left, source = Co.QuestTimer(quest), "game"
            if not left and now and tonumber(e.start) then
                left, source = math.max(0, e.start + limit - now), "ours"
            elseif not left and tonumber(e.at) then
                left, source = math.max(0, e.at + limit - Co.Now()), "ours"
            end
            if left then out[#out + 1] = { quest = quest, left = left, limit = limit, source = source } end
        end
    end
    table.sort(out, function(a, b) return a.left < b.left end)
    return out
end

-- Quests no longer in the log (turned in, abandoned, failed) leave the saved list.
local function Prune()
    local m = Store(false)
    if not (m and type(m.timed) == "table") then return end
    for quest in pairs(m.timed) do
        if not ns.GameState.InLog(quest) then
            local w = Store(true)
            if w then w.timed[quest] = nil end
        end
    end
end

function WT.ForStep(step)
    if not (step and step.waits) then return nil end
    if step.waits == "timed" then
        return { kind = "timed", limit = (step.timeLimit or 0) * 60 }
    end
    local limit = (step.waitMin or 0) * 60
    if limit <= 0 then return nil end
    local at = WT.stepAt[step.id]
    local left = at and math.max(0, at + limit - Co.Now()) or limit
    return { kind = step.waits, left = left, limit = limit }
end

-- The one line the window shows, in parts: { label, time ("m:ss" or nil), kind, over (out of time / waited long
-- enough) }. A running timer first (soonest), else the current step's wait. nil = no line.
function WT.Parts()
    local L = ns.L
    local run = WT.Running()[1]
    if run then
        local name = ns.Names and ns.Names.Quest(run.quest, "#" .. run.quest) or ("#" .. run.quest)
        if run.left <= 0 then return { label = ns.U.Fill(L.WAITS_TIMED_OUT, { quest = name }), kind = "timedOut", over = true } end
        return { label = ns.U.Fill(L.WAITS_TIMED_LEFT, { quest = name }), time = WT.Time(run.left), kind = "timed" }
    end
    local w = WT.ForStep(ns.Engine.Current())
    if not w then return nil end
    if w.kind == "timed" then
        return { label = ns.U.Fill(L.WAITS_TIMED_LIMIT, { n = math.floor(w.limit / 60) }), kind = "timedInfo" }
    end
    local up = w.kind:upper()
    if w.left <= 0 then return { label = L["WAITS_OVER_" .. up] or L.WAITS_OVER_EVENT, kind = w.kind, over = true } end
    return { label = L["WAITS_UPTO_" .. up] or L.WAITS_UPTO_EVENT, time = WT.Time(w.left), kind = w.kind }
end

-- The same as one text (self-test, chat): label + time.
function WT.Line()
    local p = WT.Parts()
    if not p then return nil end
    return p.time and (p.label .. " " .. p.time) or p.label, p.kind
end

-- Something counts down right now?
local function Counting()
    if #WT.Running() > 0 then return true end
    local w = WT.ForStep(ns.Engine.Current())
    return w ~= nil and w.left ~= nil and w.left > 0
end

local function Tick()
    WT.ticks = WT.ticks + 1
    ns.Bus.Fire("WaitsTick")
    if not Counting() and WT.ticker then
        WT.ticker:Cancel()
        WT.ticker = nil
    end
end

function WT.Update()
    local cur = ns.Engine.Current()
    if cur and cur.waits and cur.waits ~= "timed" and not WT.stepAt[cur.id] then WT.stepAt[cur.id] = Co.Now() end
    -- the step before (an accept that just got done) and the current one
    local _, top = ns.Engine.Current()
    if top and top.pos then
        for i = math.max(1, top.pos - 3), top.pos do NoteAccepted(top:Step(i)) end
    end
    Prune()
    if Counting() then
        if not WT.ticker then WT.ticker = Co.Ticker(1, function() ns.Errors.Call("waits", Tick) end) end
    elseif WT.ticker then
        WT.ticker:Cancel()
        WT.ticker = nil
    end
    ns.Bus.Fire("WaitsTick")
end

-- Self-test: the ticker runs only while something counts (no work when nothing does), and the line reads.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "waits", fn = function(h)
    h.Count()
    local counting = Counting()
    -- (the ticker stops on its next tick once nothing counts, so up to 1 s of overlap is normal: an info line only)
    if WT.ticker and not counting then h.Info("waits: ticker stops on its next tick") end
    local line = WT.Line()
    h.Info("waits: " .. (line and ("'" .. line .. "'") or "none") .. (WT.ticker and " (ticking)" or ""))
end }

ns.Bus.On("StepChanged", WT, function() ns.Errors.Call("waits", WT.Update) end, "waits", 70)
ns.Bus.On("QuestsChanged", WT, function() ns.Errors.Call("waits", WT.Update) end, "waits", 70)

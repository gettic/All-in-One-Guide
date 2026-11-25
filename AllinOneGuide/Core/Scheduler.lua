-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- One shared job scheduler. Heavy work runs as coroutines that yield often; each frame gets a
-- millisecond budget. Jobs run by priority (lower first), can be cancelled, and pause in combat
-- (and, for jobs marked `ui`, while our window is hidden). The OnUpdate script is set only while
-- jobs wait, so an idle addon costs nothing per frame.
--   ns.Jobs.Add(name, fn, { priority = 50, ui = false, feature = "core", done = function(ok) end })
--   inside fn: call ns.Jobs.Yield() between small pieces of work
local _, ns = ...
local J = { list = {}, budgetMs = 4, running = nil, uiHidden = true, ran = 0 }
ns.Jobs = J

local frame = CreateFrame("Frame")
local co_create, co_resume, co_status, co_yield = coroutine.create, coroutine.resume, coroutine.status, coroutine.yield

local function Finish(job, ok, err)
    for i, j in ipairs(J.list) do
        if j == job then table.remove(J.list, i) break end
    end
    if not ok then ns.Errors.Record(job.feature, err) end
    if job.done then ns.Errors.Call(job.feature, job.done, ok) end
end

local function Runnable(job)
    if ns.Compat.InCombat() and not job.combat then return false end
    if job.ui and J.uiHidden then return false end
    return true
end

local function OnUpdate()
    local start = debugprofilestop()
    local any = false
    while #J.list > 0 do
        local job
        for _, j in ipairs(J.list) do
            if Runnable(j) then job = j break end
        end
        if not job then break end
        any = true
        J.running = job
        local ok, err = co_resume(job.co)
        J.running = nil
        J.ran = J.ran + 1
        if not ok then
            Finish(job, false, err)
        elseif co_status(job.co) == "dead" then
            Finish(job, true)
        end
        if debugprofilestop() - start >= J.budgetMs then break end
    end
    if #J.list == 0 or not any then frame:SetScript("OnUpdate", nil) end
end

local function Wake()
    if #J.list > 0 then frame:SetScript("OnUpdate", OnUpdate) end
end
J.Wake = Wake

function J.Add(name, fn, opts)
    opts = opts or {}
    J.Cancel(name)
    local job = { name = name, co = co_create(fn), priority = opts.priority or 50, ui = opts.ui, combat = opts.combat,
        feature = opts.feature or "core", done = opts.done }
    local pos = #J.list + 1
    for i, j in ipairs(J.list) do
        if job.priority < j.priority then pos = i break end
    end
    table.insert(J.list, pos, job)
    Wake()
    return job
end

function J.Cancel(name)
    for i = #J.list, 1, -1 do
        if J.list[i].name == name then table.remove(J.list, i) end
    end
end

function J.Has(name)
    for _, j in ipairs(J.list) do if j.name == name then return true end end
    return false
end

-- Inside a job: give the frame back when the budget is used (cheap to call often).
function J.Yield()
    if J.running then co_yield() end
end

function J.SetUIShown(shown)
    J.uiHidden = not shown
    Wake()
end

-- Combat end: paused jobs may run again.
ns.Events.On("PLAYER_REGEN_ENABLED", J, Wake, "core")

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Quest data requests (C_QuestLog.RequestLoadQuestByID), the only place that asks the server for quest data.
-- tos R2 (plans\v0.2\tos-plan.md): only for the quests the guide shows (current step + the next ~5),
-- at most one request per 0.5 s, a cap per session, and results remembered per character:
--   * a quest the server says doesn't exist twice is "not on this server" (saved per character with the
--     game build; a new build clears the list, so it's checked again once)
--   * names of quests that exist come back through the Names service (bus NameReady)
--   ns.QuestData.Request(id, front)   ns.QuestData.Check(ids)   ns.QuestData.NotAvailable(id)
--   bus: QuestNotAvailable(id)
local _, ns = ...
local Co = ns.Compat
local QD = { queue = {}, queued = {}, asked = {}, results = {}, misses = {}, calls = 0, CAP = 60, GAP = 0.5,
    AHEAD = 5, RETRY = 5, ticker = nil, last = -100, capped = false }
ns.QuestData = QD

-- The saved list (char module "questdata": { build, na = { [id] = true } }); nil until something is saved.
local function Saved(create)
    local root = ns.DB.char
    if not root or type(root.modules) ~= "table" then return nil end
    local m = root.modules.questdata
    if type(m) ~= "table" then
        if not create or ns.DB.readOnly.char or ns.safeMode then return nil end
        m = ns.DB.Module("questdata", "char", 1)
    end
    if type(m.na) ~= "table" then
        if not create then return nil end
        m.na = {}
    end
    return m
end

local function Build() local _, b = Co.Build() return tostring(b) end

function QD.NotAvailable(id)
    local m = Saved(false)
    return m ~= nil and m.build == Build() and m.na[id] == true
end

local function MarkNotAvailable(id)
    local m = Saved(true)
    if not m then return end
    if m.build ~= Build() then m.na, m.build = {}, Build() end
    m.na[id] = true
    ns.Errors.Debug("quest %d: not on this server", id)
    ns.Bus.Fire("QuestNotAvailable", id)
end

local function Send(id)
    QD.calls = QD.calls + 1
    QD.last = Co.Now()
    QD.asked[id] = true
    Co.RequestQuest(id)
end

local function Pump()
    if #QD.queue == 0 then
        if QD.ticker then QD.ticker:Cancel() QD.ticker = nil end
        return
    end
    if QD.calls >= QD.CAP then
        if not QD.capped then
            QD.capped = true
            ns.Errors.Debug("quest data: session cap of %d requests reached", QD.CAP)
        end
        for _, id in ipairs(QD.queue) do QD.queued[id] = nil end
        QD.queue = {}
        return Pump()
    end
    if Co.Now() - QD.last < QD.GAP then return end
    local id = table.remove(QD.queue, 1)
    QD.queued[id] = nil
    Send(id)
    if #QD.queue == 0 and QD.ticker then QD.ticker:Cancel() QD.ticker = nil end
end

-- Asks for one quest (deduplicated; front = before the others). false when it won't be asked.
function QD.Request(id, front)
    if type(id) ~= "number" or id <= 0 then return false end
    if QD.queued[id] or QD.asked[id] or QD.results[id] ~= nil then return false end
    if QD.calls >= QD.CAP or not Co.has.QuestRequest then return false end
    QD.queued[id] = true
    if front then table.insert(QD.queue, 1, id) else QD.queue[#QD.queue + 1] = id end
    Pump()
    if #QD.queue > 0 and not QD.ticker then QD.ticker = Co.Ticker(QD.GAP, function() ns.Errors.Call("questdata", Pump) end) end
    return true
end

-- The engine passes the quest ids of the shown steps (current first, at most 1 + AHEAD are used).
-- Asks only for quests whose name the client doesn't know, that aren't in the log or done, and
-- that aren't already known as missing.
function QD.Check(ids)
    local GS = ns.GameState
    for i = 1, math.min(#ids, 1 + QD.AHEAD) do
        local id = ids[i]
        if type(id) == "number" and not GS.InLog(id) and not GS.IsDone(id) and not QD.NotAvailable(id)
            and Co.QuestTitle(id) == nil then
            QD.Request(id, i == 1)
        end
    end
end

function QD.OnResult(_, id, ok)
    if type(id) ~= "number" or not QD.asked[id] then return end
    QD.asked[id] = nil
    if ok then
        QD.results[id] = true
        QD.misses[id] = nil
        return
    end
    QD.misses[id] = (QD.misses[id] or 0) + 1
    if QD.misses[id] >= 2 then
        QD.results[id] = false
        MarkNotAvailable(id)
    else
        -- once more a little later (a slow server can say "no" the first time)
        Co.After(QD.RETRY, function() ns.Errors.Call("questdata", QD.Request, id) end)
    end
end

-- In-game self-test (/aog selftest): the request limiter's numbers and the v0.2 game reads.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "questdata", fn = function(h)
    h.Count()
    if QD.calls > QD.CAP then h.Problem("questdata: " .. QD.calls .. " requests, cap " .. QD.CAP) end
    local GS = ns.GameState
    h.Info(("questdata %d/%d, xp %s, bind %s"):format(QD.calls, QD.CAP, GS.xpMax and "ok" or "none",
        GS.bind and "ok" or "none"))
end }

ns.Bus.On("Login", QD, function()
    ns.Events.On("QUEST_DATA_LOAD_RESULT", QD, QD.OnResult, "questdata")
end, "questdata", 40)

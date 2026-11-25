-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The internal callback bus (StepChanged, PackLoaded, SettingsChanged, CombatEnded, QuestsChanged ...).
-- Rules: no re-entrant dispatch (a Fire during a Fire is queued and runs after), a fixed listener
-- order (by `order`, then by registration), and each listener isolated in xpcall.
local _, ns = ...
local Bus = { listeners = {}, queue = {}, firing = false, seq = 0 }
ns.Bus = Bus

local function Sort(list)
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)
end

-- Bus.On("StepChanged", owner, fn, feature, order)
function Bus.On(name, owner, fn, feature, order)
    local list = Bus.listeners[name]
    if not list then
        list = {}
        Bus.listeners[name] = list
    end
    for _, l in ipairs(list) do
        if l.owner == owner then l.fn = fn return end
    end
    Bus.seq = Bus.seq + 1
    list[#list + 1] = { owner = owner, fn = fn, feature = feature or "core", order = order or 50, seq = Bus.seq }
    Sort(list)
end

function Bus.Off(name, owner)
    local list = Bus.listeners[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then
            list[i].removed = true
            table.remove(list, i)
        end
    end
end

local function Dispatch(name, n, ...)
    if ns.Test.busRecord then
        local rec = ns.Test.busRecord
        rec[#rec + 1] = name
    end
    local list = Bus.listeners[name]
    if not list then return end
    for i = 1, #list do
        local l = list[i]
        if l and not l.removed then ns.Errors.Call(l.feature, l.fn, name, ...) end
    end
end

function Bus.Fire(name, ...)
    if Bus.firing then
        Bus.queue[#Bus.queue + 1] = { name, select("#", ...), ... }
        return
    end
    Bus.firing = true
    Dispatch(name, select("#", ...), ...)
    -- queued fires, in order
    local i = 1
    while i <= #Bus.queue do
        local q = Bus.queue[i]
        Dispatch(q[1], q[2], unpack(q, 3, 2 + q[2]))
        i = i + 1
    end
    if i > 1 then Bus.queue = {} end
    Bus.firing = false
end

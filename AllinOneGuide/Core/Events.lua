-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The event hub: one frame for every game event. A game event is registered while at least one
-- listener wants it and unregistered when the last one leaves. Each listener runs in xpcall under
-- its feature name. Debounce: many events in a burst -> one call after a short quiet time.
local _, ns = ...
local Ev = { listeners = {}, debounce = {} }
ns.Events = Ev

local frame = CreateFrame("Frame")
Ev.frame = frame

local function Dispatch(_, event, ...)
    local list = Ev.listeners[event]
    if not list then return end
    -- the list may change while we walk it: walk a fixed length, skip removed entries
    for i = 1, #list do
        local l = list[i]
        if l and not l.removed then ns.Errors.Call(l.feature, l.fn, event, ...) end
    end
end
frame:SetScript("OnEvent", Dispatch)

-- Ev.On("QUEST_LOG_UPDATE", owner, fn, feature): owner is any key (a table or string) used by Off.
function Ev.On(event, owner, fn, feature)
    local list = Ev.listeners[event]
    if not list then
        list = {}
        Ev.listeners[event] = list
    end
    for _, l in ipairs(list) do
        if l.owner == owner and not l.removed then l.fn, l.feature = fn, feature or l.feature return end
    end
    list[#list + 1] = { owner = owner, fn = fn, feature = feature or "core" }
    if #list == 1 then frame:RegisterEvent(event) end
end

function Ev.Off(event, owner)
    local list = Ev.listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then
            list[i].removed = true
            table.remove(list, i)
        end
    end
    if #list == 0 then
        Ev.listeners[event] = nil
        frame:UnregisterEvent(event)
    end
end

function Ev.Has(event) return Ev.listeners[event] ~= nil end

-- Calls fn once, `delay` seconds after the last Debounce(key, ...) call of a burst.
function Ev.Debounce(key, delay, fn, feature)
    local d = Ev.debounce[key]
    if not d then
        d = { fn = fn, feature = feature or "core", due = 0, armed = false, gen = 0 }
        Ev.debounce[key] = d
    end
    d.fn, d.due = fn, GetTime() + delay
    if d.armed then return end
    d.armed = true
    local gen = d.gen
    local function Check()
        if d.gen ~= gen then return end   -- flushed meanwhile
        local now = GetTime()
        if now + 0.0005 < d.due then
            C_Timer.After(d.due - now, Check)
            return
        end
        d.armed = false
        ns.Errors.Call(d.feature, d.fn)
    end
    C_Timer.After(delay, Check)
end

-- Runs a pending debounce right away (used before reading state that must be fresh).
function Ev.Flush(key)
    local d = Ev.debounce[key]
    if d and d.armed then
        d.gen = d.gen + 1
        d.armed = false
        ns.Errors.Call(d.feature, d.fn)
    end
end

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Combat queue (v0.2 M2): every change to a secure frame, a binding or a macro goes through here. Out of
-- combat it runs at once; in combat it waits for PLAYER_REGEN_ENABLED (one entry per key, the last one wins)
-- and runs once after, in the order the keys were first queued. Nothing secure is ever shown, hidden, moved
-- or changed in combat.
--   ns.CombatQueue.Run(key, fn, ...)   -> true when it ran now, false when it waits
--   ns.CombatQueue.Pending(key)        -> true while a change for key waits (the hourglass state)
--   bus: CombatQueueChanged
local _, ns = ...
local Co = ns.Compat
local CQ = { queue = {}, order = {} }
ns.CombatQueue = CQ

function CQ.Pending(key) return CQ.queue[key] ~= nil end
function CQ.Count() return #CQ.order end

function CQ.Run(key, fn, ...)
    if not Co.InCombat() then
        -- a newer change out of combat replaces a waiting one
        if CQ.queue[key] then
            CQ.queue[key] = nil
            for i, k in ipairs(CQ.order) do if k == key then table.remove(CQ.order, i) break end end
            ns.Bus.Fire("CombatQueueChanged")
        end
        ns.Errors.Call("combatqueue", fn, ...)
        return true
    end
    if not CQ.queue[key] then CQ.order[#CQ.order + 1] = key end
    CQ.queue[key] = { fn = fn, n = select("#", ...), ... }
    ns.Bus.Fire("CombatQueueChanged")
    return false
end

function CQ.Flush()
    if Co.InCombat() or #CQ.order == 0 then return end
    local order, queue = CQ.order, CQ.queue
    CQ.order, CQ.queue = {}, {}
    for _, key in ipairs(order) do
        local e = queue[key]
        if e then ns.Errors.Call("combatqueue", e.fn, unpack(e, 1, e.n)) end
    end
    ns.Bus.Fire("CombatQueueChanged")
end

ns.Bus.On("Login", CQ, function()
    ns.Events.On("PLAYER_REGEN_ENABLED", CQ, CQ.Flush, "combatqueue")
end, "combatqueue", 10)

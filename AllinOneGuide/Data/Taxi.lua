-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Known flight paths (v0.2 M2). Read from the client (C_TaxiMap.GetTaxiNodesForMap on the continents at
-- login, C_TaxiMap.GetAllTaxiNodes when a flight master's map opens) and kept per character (module "taxi"),
-- so `getfp` steps tick by themselves and `fly` steps can warn about a missing node. Read only: the player
-- always picks the flight.
--   ns.Taxi.Known(node) -> true / false / nil (nil = nothing read yet)   ns.Taxi.Name(node)   ns.Taxi.open
--   bus: TaxiChanged, TaxiOpened, TaxiClosed
local _, ns = ...
local Co = ns.Compat
local T = { CONTINENTS = { 1414, 1415 }, names = {}, open = false, read = false }
ns.Taxi = T

local function Saved(create)
    local root = ns.DB.char
    if not root or type(root.modules) ~= "table" then return nil end
    local m = root.modules.taxi
    if type(m) ~= "table" then
        if not create or ns.DB.readOnly.char or ns.safeMode then return nil end
        m = ns.DB.Module("taxi", "char", 1)
    end
    if type(m.nodes) ~= "table" then
        if not create then return nil end
        m.nodes = {}
    end
    return m
end

function T.Known(node)
    if type(node) ~= "number" then return nil end
    local m = Saved(false)
    if m and m.nodes[node] then return true end
    if not T.read and not m then return nil end
    return false
end

function T.Name(node) return T.names[node] end

-- Adds known nodes; fires TaxiChanged when something new came in.
local function Learn(list, onlyKnown)
    local new = false
    for _, n in ipairs(list) do
        if n.name then T.names[n.id] = n.name end
        if not onlyKnown or n.known then
            local m = Saved(true)
            if m and not m.nodes[n.id] then
                m.nodes[n.id] = true
                new = true
            end
        end
    end
    return new
end

function T.ReadContinents()
    local new = false
    for _, map in ipairs(T.CONTINENTS) do
        if Learn(Co.TaxiNodesForMap(map), true) then new = true end
    end
    T.read = true
    if new then ns.Bus.Fire("TaxiChanged") end
end

function T.OnOpened()
    T.open = true
    local new = false
    for _, map in ipairs(T.CONTINENTS) do
        if Learn(Co.TaxiOpenNodes(map), false) then new = true end
        if Learn(Co.TaxiNodesForMap(map), true) then new = true end
    end
    T.read = true
    if new then ns.Bus.Fire("TaxiChanged") end
    ns.Bus.Fire("TaxiOpened")
end

ns.Bus.On("Login", T, function()
    ns.Events.On("TAXIMAP_OPENED", T, T.OnOpened, "taxi")
    ns.Events.On("TAXIMAP_CLOSED", T, function()
        T.open = false
        ns.Bus.Fire("TaxiClosed")
    end, "taxi")
    T.ReadContinents()
end, "taxi", 45)

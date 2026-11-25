-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Pack store. Packs register their header and readable rows; nothing is decoded at login.
-- Opening a route builds its id index (ids only); steps are decoded on demand through the one
-- accessor, GetStep, and kept in a small window cache. Steps handed out are frozen (read-only).
--   ns.Packs.Register(header, routes)   -> true, or false + reason (e.g. needs a newer addon)
--   ns.Packs.Open(packId, routeId)      -> route handle (or nil, reason)
--   ns.Packs.GetStep(route, i), Count(route), IndexOf(route, id), Section(route, i), Close(route)
--   ns.Packs.MakeRoute(id, steps)       -> in-memory route for detours (steps are plain decoded tables)
local _, ns = ...
local Fm = ns.Format
local P = { packs = {}, order = {}, refused = {}, CACHE_MAX = 64 }
ns.Packs = P

-- Read-only proxy, all the way down (flags, obj ...). Lua 5.1's # and ipairs don't see through a proxy,
-- so lists in a step are read with P.Len / P.Each (index access).
-- (condAst / overrideAst are shared, cached parse results: left as they are.)
local SHARED = { condAst = true, overrideAst = true }
local function Freeze(t)
    for k, v in pairs(t) do
        if type(v) == "table" and not SHARED[k] then t[k] = Freeze(v) end
    end
    return setmetatable({}, {
        __index = t,
        __newindex = function() error("pack steps are read-only", 2) end,
        __metatable = false,
    })
end

-- Length of a list in a (frozen) step.
function P.Len(list)
    if not list then return 0 end
    local n = 0
    while list[n + 1] ~= nil do n = n + 1 end
    return n
end

-- for i, v in P.Each(list): ipairs that works on frozen lists.
function P.Each(list)
    return function(l, i)
        i = i + 1
        local v = l and l[i]
        if v ~= nil then return i, v end
    end, list, 0
end

function P.Register(header, routes)
    if type(header) ~= "table" or type(header.id) ~= "string" or type(routes) ~= "table" then
        return false, "bad pack"
    end
    if not Fm.CanRead(header) then
        P.refused[header.id] = "needs a newer All-in-One Guide"
        return false, P.refused[header.id]
    end
    if P.packs[header.id] then return false, "pack registered twice" end
    local pack = { header = header, routes = {}, routeOrder = {} }
    for _, r in ipairs(routes) do
        if type(r) == "table" and type(r.id) == "string" and type(r.rows) == "table" then
            pack.routes[r.id] = { packId = header.id, id = r.id, title = r.title, da = r.da,
                rawSections = r.sections or {}, rows = r.rows }
            pack.routeOrder[#pack.routeOrder + 1] = r.id
        end
    end
    P.packs[header.id] = pack
    P.order[#P.order + 1] = header.id
    if ns.Bus then ns.Bus.Fire("PackLoaded", header.id) end
    return true
end

function P.Header(packId) local p = P.packs[packId] return p and p.header end
function P.List() return P.order end
function P.Routes(packId) local p = P.packs[packId] return p and p.routeOrder or {} end

-- Builds the id index and sections. Cheap: only the id part of each row is read.
function P.Open(packId, routeId)
    local pack = P.packs[packId]
    if not pack then return nil, P.refused[packId] or "pack not installed" end
    local r = pack.routes[routeId or pack.routeOrder[1]]
    if not r then return nil, "no such route" end
    if not r.index then
        local index = {}
        for i, row in ipairs(r.rows) do
            -- a row that isn't a string becomes a bad (manual) step in GetStep; it has no id here
            local id = type(row) == "string" and Fm.RowId(row) or nil
            if id and id ~= "" and index[id] == nil then index[id] = i end
        end
        r.index = index
        local sections = {}
        for _, s in ipairs(type(r.rawSections) == "table" and r.rawSections or {}) do
            local first, title, da
            if type(s) == "string" then first, title, da = s:match("^(%d+)|([^|]*)|?(.*)$") end
            if first then
                sections[#sections + 1] = { first = tonumber(first), title = Fm.Unescape(title),
                    da = da ~= "" and Fm.Unescape(da) or nil }
            end
        end
        r.sections = sections
        r.cache, r.cached = {}, 0
    end
    r.header = pack.header
    return r
end

function P.Count(route)
    if route.steps then return #route.steps end
    return #route.rows
end

function P.IndexOf(route, id) return route.index and route.index[id] end

-- The one accessor. Returns a frozen step (or nil past the end / on a bad row).
function P.GetStep(route, i)
    if route.steps then return route.steps[i] end
    local c = route.cache and route.cache[i]
    if c then return c end
    local row = route.rows[i]
    if not row then return nil end
    local step, err = Fm.DecodeRow(row)
    if not step then
        if ns.Errors then ns.Errors.Debug("bad row %d in %s/%s: %s", i, route.packId, route.id, tostring(err)) end
        step = { id = "row" .. i, type = "manual", flags = {}, bad = true }
    end
    step.index = i
    if step.cond then step.condAst = ns.Conditions.Get(step.cond) end
    if step.override then step.overrideAst = ns.Conditions.Get(step.override, true) end
    local frozen = Freeze(step)
    if route.cached >= P.CACHE_MAX then route.cache, route.cached = {}, 0 end
    route.cache[i] = frozen
    route.cached = route.cached + 1
    return frozen
end

-- The section a step index belongs to.
function P.Section(route, i)
    local found
    for _, s in ipairs(route.sections or {}) do
        if s.first <= i then found = s else break end
    end
    return found
end

-- Frees the decoded steps (on guide switch); the rows stay.
function P.Close(route)
    route.cache, route.cached = {}, 0
end

-- An in-memory route for a detour (class moment, chain ...): steps already decoded, ids "<kind>:<id>:<n>".
function P.MakeRoute(id, steps)
    local route = { packId = "detour", id = id, steps = {}, index = {}, sections = {} }
    for i, s in ipairs(steps) do
        local step = {}
        for k, v in pairs(s) do step[k] = v end
        step.flags = step.flags or {}
        step.index = i
        if step.cond then step.condAst = ns.Conditions.Get(step.cond) end
        if step.override then step.overrideAst = ns.Conditions.Get(step.override, true) end
        route.steps[i] = Freeze(step)
        route.index[step.id] = i
    end
    return route
end

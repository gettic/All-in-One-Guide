-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Pack diff (v0.2 M6): compares an old and a new pack source (after include expansion, per route) and
-- prints what a release needs to know:
--   * the step id map: kept, gone, new;
--   * suggestions: a gone id whose step is the same (type, quest, npc, map, rounded x / y) as a new id ->
--     `renamedSteps["old"] = "new"`; any other gone id that the new pack doesn't list -> `retiredSteps`;
--     a new id that reuses a retired id is an error;
--   * one changelog line per changed step id (which fields changed);
--   * a phase change in the header (`phase`).
-- Packs are loaded as data only (tools\packlib.lua, empty environment).
-- Run (from the repository folder):  luajit tools/packdiff.lua <old pack.lua> <new pack.lua>
-- Exit code 1 on an error (a reused retired id, a pack that doesn't load).
-- As a library: local PD = assert(loadfile("tools/packdiff.lua"))("--lib", "<tools folder>")
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2]) or (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tools"
local PD = {}
local Lib = assert(loadfile(toolsDir .. "/packlib.lua"))()
PD.Lib = Lib

-- fields compared for the changelog (in this order)
PD.FIELDS = { "type", "quest", "npc", "map", "x", "y", "r", "text", "da", "cond", "flags", "src", "level", "item",
    "count", "obj", "useItem", "node", "inn", "pre", "xp", "why", "minLevel", "override", "whileUntil", "leadsTo",
    "anyOrder", "dungeon" }

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
PD.Same = Same

-- What makes two steps "the same step" for a rename: kind of step and where / what it is about.
local function Sig(s)
    local function R(v) return type(v) == "number" and math.floor(v + 0.5) or "" end
    return table.concat({ tostring(s.type), tostring(s.quest or ""), tostring(s.npc or ""), tostring(s.map or ""),
        R(s.x), R(s.y), tostring(s.level or ""), tostring(s.item or "") }, "|")
end
PD.Sig = Sig

local function Index(pack)
    local routes, errs = Lib.Expand(pack)
    local out = {}
    for _, r in ipairs(routes) do
        local t = { order = {}, byId = {} }
        for _, s in ipairs(r.steps) do
            if type(s.id) == "string" then
                t.order[#t.order + 1] = s.id
                t.byId[s.id] = s
            end
        end
        out[r.id or "?"] = t
    end
    return out, errs
end

-- old, new = pack tables (as loaded). Returns a report = { lines, errors, renames, retires, changed, phase }.
function PD.Diff(old, new)
    local rep = { lines = {}, errors = {}, renames = {}, retires = {}, changed = 0, kept = 0, gone = 0, added = 0 }
    local function Line(s) rep.lines[#rep.lines + 1] = s end
    local oi, oe = Index(old)
    local ni, ne = Index(new)
    for _, e in ipairs(oe) do rep.errors[#rep.errors + 1] = "old: " .. e end
    for _, e in ipairs(ne) do rep.errors[#rep.errors + 1] = "new: " .. e end
    local oldPhase, newPhase = old.phase, new.phase
    if not Same(oldPhase, newPhase) then
        rep.phase = { tostring(oldPhase), tostring(newPhase) }
        Line(("phase: %s -> %s"):format(tostring(oldPhase), tostring(newPhase)))
    end
    local renamed = type(new.renamedSteps) == "table" and new.renamedSteps or {}
    local retired = {}
    for _, id in ipairs(type(new.retiredSteps) == "table" and new.retiredSteps or {}) do retired[id] = true end
    for _, id in ipairs(type(old.retiredSteps) == "table" and old.retiredSteps or {}) do retired[id] = true end

    local routeIds = {}
    for id in pairs(oi) do routeIds[#routeIds + 1] = id end
    for id in pairs(ni) do if not oi[id] then routeIds[#routeIds + 1] = id end end
    table.sort(routeIds)
    for _, rid in ipairs(routeIds) do
        local o, n = oi[rid], ni[rid]
        if not o then
            Line(("route %s: new route (%d steps)"):format(rid, #n.order))
        elseif not n then
            Line(("route %s: gone (%d steps)"):format(rid, #o.order))
        else
            -- new ids that reuse a retired one
            for _, id in ipairs(n.order) do
                if retired[id] then rep.errors[#rep.errors + 1] = ("route %s: %s reuses a retired id"):format(rid, id) end
            end
            local newBySig = {}
            for _, id in ipairs(n.order) do
                if not o.byId[id] then
                    local sig = Sig(n.byId[id])
                    newBySig[sig] = newBySig[sig] or {}
                    table.insert(newBySig[sig], id)
                end
            end
            local claimed = {}
            for _, id in ipairs(o.order) do
                local os_, ns_ = o.byId[id], n.byId[id]
                if ns_ then
                    rep.kept = rep.kept + 1
                    local diff = {}
                    for _, f in ipairs(PD.FIELDS) do
                        if not Same(os_[f], ns_[f]) then diff[#diff + 1] = f end
                    end
                    if #diff > 0 then
                        rep.changed = rep.changed + 1
                        Line(("route %s: %s changed: %s"):format(rid, id, table.concat(diff, ", ")))
                    end
                else
                    rep.gone = rep.gone + 1
                    if renamed[id] then
                        if not n.byId[renamed[id]] then
                            rep.errors[#rep.errors + 1] = ("route %s: renamedSteps %s -> %s, but %s isn't in the new pack"):format(
                                rid, id, renamed[id], renamed[id])
                        else
                            claimed[renamed[id]] = true
                            Line(("route %s: %s renamed to %s (listed)"):format(rid, id, renamed[id]))
                        end
                    elseif retired[id] then
                        Line(("route %s: %s retired (listed)"):format(rid, id))
                    else
                        local cands = newBySig[Sig(os_)]
                        local pick
                        for _, c in ipairs(cands or {}) do
                            if not claimed[c] then pick = c break end
                        end
                        if pick then
                            claimed[pick] = true
                            rep.renames[#rep.renames + 1] = { id, pick }
                            Line(("route %s: %s looks renamed to %s: add renamedSteps[\"%s\"] = \"%s\""):format(rid, id, pick, id, pick))
                        else
                            rep.retires[#rep.retires + 1] = id
                            Line(("route %s: %s is gone: add it to retiredSteps"):format(rid, id))
                        end
                    end
                end
            end
            for _, id in ipairs(n.order) do
                if not o.byId[id] and not claimed[id] then
                    rep.added = rep.added + 1
                    Line(("route %s: %s new"):format(rid, id))
                end
            end
        end
    end
    Line(("packdiff: kept %d, changed %d, gone %d (rename %d, retire %d), new %d, errors %d"):format(
        rep.kept, rep.changed, rep.gone, #rep.renames, #rep.retires, rep.added, #rep.errors))
    return rep
end

function PD.Main(a)
    if #a < 2 then print("usage: luajit tools/packdiff.lua <old pack.lua> <new pack.lua>") return false end
    local old, e1 = Lib.LoadData(a[1])
    local new, e2 = Lib.LoadData(a[2])
    if not old then print("ERROR old pack: " .. tostring(e1)) return false end
    if not new then print("ERROR new pack: " .. tostring(e2)) return false end
    local rep = PD.Diff(old, new)
    for _, l in ipairs(rep.lines) do print(l) end
    for _, e in ipairs(rep.errors) do print("ERROR " .. e) end
    return #rep.errors == 0
end

if args[1] == "--lib" then return PD end
if not PD.Main(args) then os.exit(1) end

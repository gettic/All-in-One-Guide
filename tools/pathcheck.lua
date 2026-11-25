-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Hunt path checks (v0.3, packs-src\FORMAT.md "Hunt paths"): the `path` loop of a kill / collect step. Used by
-- tools\packcheck.lua after the includes are expanded (and `path = "auto"` is filled from packs-src\paths\).
--   errors: `path` on a step type that can't have one; "auto" with no entry; not 3-12 points; a point outside
--           0-100 or with more than 2 decimals; no step spot; `pathSrc` missing / not hand or gen; `pathR` not 5-30;
--           `pathOpen` not true / false; a point more than FAR yd from the step spot or a leg longer than LEG yd
--           (typo); a point in another connector room than the step's spot (walls); a point inside a
--           known-exploits `places` circle
--   warnings: a loop longer than LONG yd (least travel), two points closer than CLOSE yd (one is enough)
-- Distances in yards from tools\data\mapsizes.lua (estimates); a map without a size skips the yard checks (warns).
-- As a library: local PH = assert(loadfile("tools/pathcheck.lua"))("--lib", "<tools folder>")
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2]) or "tools"
local PH = { MIN = 3, MAX = 12, FAR = 250, LEG = 120, LONG = 600, CLOSE = 5, R_MIN = 5, R_MAX = 30,
    TYPES = { objective = true, useitem = true, grind = true }, SRC = { hand = true, gen = true } }

local MapSizes
function PH.MapSizes()
    if not MapSizes then MapSizes = assert(loadfile(toolsDir .. "/data/mapsizes.lua"))() end
    return MapSizes
end

local function Num(v) return type(v) == "number" and v == v end

local function Decimals(n)
    local s = string.format("%.6f", n):gsub("0+$", "")
    return #(s:match("%.(%d*)$") or "")
end

-- Yards between two percent points on one map (nil when the map has no size).
function PH.Yards(sizes, map, ax, ay, bx, by)
    local size = sizes[map]
    if not size then return nil end
    return math.sqrt(((bx - ax) / 100 * size[1]) ^ 2 + ((by - ay) / 100 * size[2]) ^ 2)
end

-- Total length of the loop (closed unless open), yards.
function PH.Length(sizes, map, pts, open)
    local total = 0
    for i = 1, #pts - 1 do
        local d = PH.Yards(sizes, map, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
        if not d then return nil end
        total = total + d
    end
    if not open and #pts > 2 then
        total = total + PH.Yards(sizes, map, pts[#pts][1], pts[#pts][2], pts[1][1], pts[1][2])
    end
    return total
end

-- routes: expanded routes (packlib). opts = { connectors = CC index or nil, CC = tools\connectors.lua module,
-- exploits = known-exploits list, mapSizes }. Returns errors, warnings (lists of "route #i id: message").
function PH.Check(routes, opts)
    opts = opts or {}
    local sizes = opts.mapSizes or PH.MapSizes()
    local errs, warns = {}, {}
    for _, r in ipairs(routes or {}) do
        for i, s in ipairs(r.steps or {}) do
            local where = r.id .. " #" .. i .. " " .. tostring(s.id)
            local function E(msg) errs[#errs + 1] = where .. ": " .. msg end
            local function W(msg) warns[#warns + 1] = where .. ": " .. msg end
            local p = s.path
            if p == nil then
                if s.pathSrc ~= nil or s.pathOpen ~= nil or s.pathR ~= nil then E("pathSrc / pathOpen / pathR without a path") end
            elseif not PH.TYPES[s.type] then
                E("path only on objective, useitem or grind steps")
            elseif p == "auto" then
                E("path 'auto' was not filled in (no entry in packs-src/paths/)")
            elseif p == false then
                if s.pathSrc ~= nil or s.pathOpen ~= nil or s.pathR ~= nil then E("path = false with pathSrc / pathOpen / pathR") end
            elseif type(p) ~= "table" then
                E("path must be false, \"auto\" or a list of { x, y } points")
            else
                local ok = true
                if #p < PH.MIN or #p > PH.MAX then E(("path needs %d-%d points (has %d)"):format(PH.MIN, PH.MAX, #p)) ok = false end
                for k, pt in ipairs(p) do
                    if type(pt) ~= "table" or not Num(pt[1]) or not Num(pt[2]) then
                        E("path point " .. k .. " must be { x, y }")
                        ok = false
                    elseif pt[1] < 0 or pt[1] > 100 or pt[2] < 0 or pt[2] > 100 then
                        E("path point " .. k .. " outside 0-100")
                        ok = false
                    elseif Decimals(pt[1]) > 2 or Decimals(pt[2]) > 2 then
                        E("path point " .. k .. " has more than 2 decimals")
                    end
                end
                if not (Num(s.map) and Num(s.x) and Num(s.y)) then E("path needs the step's map, x, y") ok = false end
                if not PH.SRC[s.pathSrc] then E("pathSrc must be \"hand\" or \"gen\"") end
                if s.pathR ~= nil and (not Num(s.pathR) or s.pathR < PH.R_MIN or s.pathR > PH.R_MAX) then
                    E(("pathR must be %d-%d yards"):format(PH.R_MIN, PH.R_MAX))
                end
                if s.pathOpen ~= nil and type(s.pathOpen) ~= "boolean" then E("pathOpen must be true or false") end
                if ok then
                    local map = s.map
                    if not sizes[map] then
                        W("map " .. map .. " has no size in mapsizes.lua; path distances not checked")
                    else
                        for k, pt in ipairs(p) do
                            local d = PH.Yards(sizes, map, s.x, s.y, pt[1], pt[2])
                            if d > PH.FAR then E(("path point %d is %.0f yd from the step spot (over %d)"):format(k, d, PH.FAR)) end
                        end
                        local n = #p
                        for k = 1, s.pathOpen and n - 1 or n do
                            local a, b = p[k], p[k % n + 1]
                            local d = PH.Yards(sizes, map, a[1], a[2], b[1], b[2])
                            if d > PH.LEG then E(("path leg %d-%d is %.0f yd (over %d)"):format(k, k % n + 1, d, PH.LEG)) end
                            if d < PH.CLOSE then W(("path points %d and %d are %.1f yd apart"):format(k, k % n + 1, d)) end
                        end
                        local len = PH.Length(sizes, map, p, s.pathOpen)
                        if len and len > PH.LONG then W(("path is %.0f yd long (over %d: least travel)"):format(len, PH.LONG)) end
                    end
                    -- walls: every point in the step spot's own connector room (or outdoors like it)
                    if opts.connectors and opts.CC then
                        local home = opts.CC.RoomAt(opts.connectors, map, s.x, s.y)
                        for k, pt in ipairs(p) do
                            local room = opts.CC.RoomAt(opts.connectors, map, pt[1], pt[2])
                            if room ~= home then
                                E(("path point %d is in room %s, the step spot in %s"):format(k, tostring(room or "outdoors"),
                                    tostring(home or "outdoors")))
                            end
                        end
                    end
                    -- known exploit places (packs-src\known-exploits.lua `places = { { map, x, y, r yards } }`)
                    for _, x in ipairs(opts.exploits or {}) do
                        for _, pl in ipairs(x.places or {}) do
                            if pl[1] == map then
                                for k, pt in ipairs(p) do
                                    local d = PH.Yards(sizes, map, pl[2], pl[3], pt[1], pt[2])
                                    if d and d <= (pl[4] or 10) then
                                        E(("path point %d is at known exploit place '%s'"):format(k, tostring(x.id)))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return errs, warns
end

if args[1] == "--lib" then return PH end
print("pathcheck.lua is a library: tools\\packcheck.lua runs it")

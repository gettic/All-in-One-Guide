-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Smart arrow connectors: checks the readable sources (packs-src\connectors\*.lua) and compiles them into
-- AllinOneGuide\Routes\Connectors.lua (one ns.SmartRoute.Register call per area). Same source, same bytes.
-- Run from the repository folder:
--   luajit tools/connectors.lua [--check] [--addon AllinOneGuide] [--out <file>]
--   --check: write nothing, fail when the compiled file differs from the sources (or is missing).
-- Library mode: local CC = loadfile("tools/connectors.lua")("--lib", "tools")
--   CC.Check(list, opts) -> errors, warnings      list = { data, ... } (all areas together: links cross areas)
--   CC.Compile(list) -> text                      CC.LoadAll(dir) -> list, errors
local argv = { ... }
local CC = {}

CC.KINDS = { door = true, cave = true, ramp = true, bridge = true, gate = true, tram = true, path = true, stairs = true }
-- where a point may come from: our own estimate / recording, or a bare position fact from CMaNGOS classic-db
-- (GPL; a door / gate game object, or a cave's size from its dwellers' spawn area, grid-snapped; never paths
-- or waypoints: plans ruling 2026-11-25), or a position measured on Shortest Path Forever's baked walking grid
-- (GPL-3.0-or-later, by Cillian Berragan: its walkable floors and steps, read with its own decoder; 2026-11-27)
CC.SOURCES = { own = true, cmangos = true, spf = true }
CC.ID = "^[a-z0-9][a-z0-9%-]*$"
CC.TRICK = { "jump", "hop", "glitch", "wall", "fall through", "out of bounds", "unstuck", "hoppe" }

local function Num(v) return type(v) == "number" and v == v end
local function Fmt(...) return string.format(...) end

-- ------------------------------------------------------------------ checks
local function Cross(a, b, c, d)
    local function O(p, q, r) return (q[1] - p[1]) * (r[2] - p[2]) - (q[2] - p[2]) * (r[1] - p[1]) end
    local d1, d2, d3, d4 = O(c, d, a), O(c, d, b), O(a, b, c), O(a, b, d)
    return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
end

local function SelfCrossing(poly)
    local n = #poly
    for i = 1, n do
        for j = i + 1, n do
            local a, b = poly[i], poly[i % n + 1]
            local c, d = poly[j], poly[j % n + 1]
            if j ~= i + 1 and not (i == 1 and j == n) and Cross(a, b, c, d) then return true end
        end
    end
    return false
end

local function LinkTarget(l)
    if type(l) == "table" then return l[1] or l.id, l end
    return l, nil
end

-- opts = { maps = set of uiMapIDs, keys = { enUS = {...}, daDK = {...} }, exploits = known-exploits list }
function CC.Check(list, opts)
    opts = opts or {}
    local errs, warns = {}, {}
    local function E(...) errs[#errs + 1] = Fmt(...) end
    local function W(...) warns[#warns + 1] = Fmt(...) end
    local nodes, rooms, order = {}, {}, {}
    local trick = {}
    for _, w in ipairs(CC.TRICK) do trick[#trick + 1] = w end
    for _, e in ipairs(opts.exploits or {}) do
        for _, w in ipairs(e.words or {}) do trick[#trick + 1] = w end
    end
    for _, data in ipairs(list) do
        local area = tostring(data.area)
        if type(data.area) ~= "string" then E("a connector file without area") end
        for _, r in ipairs(data.rooms or {}) do
            local id = tostring(r.id)
            if type(r.id) ~= "string" or not r.id:match(CC.ID) then E("%s: bad room id %s", area, id) end
            if rooms[id] or nodes[id] then E("%s: duplicate id %s", area, id) end
            rooms[id] = r
            if opts.maps and not opts.maps[r.map] then E("%s: room %s: unknown map %s", area, id, tostring(r.map)) end
            local poly = r.poly or {}
            if #poly < 3 then E("%s: room %s: needs 3 or more corners", area, id) end
            for _, p in ipairs(poly) do
                if not (type(p) == "table" and Num(p[1]) and Num(p[2]) and p[1] >= 0 and p[1] <= 100 and p[2] >= 0 and p[2] <= 100) then
                    E("%s: room %s: a corner outside 0-100", area, id)
                end
            end
            if #poly >= 4 and SelfCrossing(poly) then E("%s: room %s: the outline crosses itself", area, id) end
            if r.chain ~= nil and r.chain ~= true and r.chain ~= false then E("%s: room %s: chain must be true or false", area, id) end
            if not CC.SOURCES[r.src] then E("%s: room %s: src must be \"own\", \"cmangos\" or \"spf\"", area, id) end
        end
        for _, c in ipairs(data.connectors or {}) do
            local id = tostring(c.id)
            order[#order + 1] = id
            if type(c.id) ~= "string" or not c.id:match(CC.ID) then E("%s: bad connector id %s", area, id) end
            if nodes[id] or rooms[id] then E("%s: duplicate id %s", area, id) end
            nodes[id] = c
            c._area = area
            if opts.maps and not opts.maps[c.map] then E("%s: %s: unknown map %s", area, id, tostring(c.map)) end
            if not (Num(c.x) and Num(c.y) and c.x >= 0 and c.x <= 100 and c.y >= 0 and c.y <= 100) then
                E("%s: %s: x / y outside 0-100", area, id)
            end
            if c.r ~= nil and not (Num(c.r) and c.r >= 1 and c.r <= 15) then E("%s: %s: r must be 1-15 yards", area, id) end
            if not CC.KINDS[c.kind] then E("%s: %s: unknown kind %s", area, id, tostring(c.kind)) end
            if c.hint ~= nil then
                for _, code in ipairs({ "enUS", "daDK" }) do
                    local keys = opts.keys and opts.keys[code]
                    -- Danish waits until v1.0 (missing Danish falls back to English): only a warning
                    if keys and keys[c.hint] == nil then
                        (code == "daDK" and W or E)("%s: %s: hint %s missing in %s", area, id, tostring(c.hint), code)
                    end
                end
            end
            if not CC.SOURCES[c.src] then E("%s: %s: src must be \"own\", \"cmangos\" or \"spf\"", area, id) end
            if c.confirmed ~= true and c.confirmed ~= false then E("%s: %s: confirmed must be true or false", area, id) end
        end
    end
    -- links, rooms, one-way trick words, long links
    local adj = {}
    for _, id in ipairs(order) do adj[id] = {} end
    for _, id in ipairs(order) do
        local c = nodes[id]
        if c.inside ~= nil and not rooms[c.inside] then E("%s: %s: room %s doesn't exist", c._area, id, tostring(c.inside)) end
        for _, l in ipairs(c.link or {}) do
            local to, lt = LinkTarget(l)
            local oneWay = c.oneWay == true or (lt and lt.oneWay == true)
            if type(to) ~= "string" or not nodes[to] then
                E("%s: %s: link to %s doesn't exist", c._area, id, tostring(to))
            elseif to == id then
                E("%s: %s: links to itself", c._area, id)
            else
                adj[id][#adj[id] + 1] = to
                if not oneWay then adj[to][#adj[to] + 1] = id end
                local t = nodes[to]
                if t.map == c.map and Num(t.x) and Num(c.x) and Num(t.y) and Num(c.y)
                    and math.sqrt((t.x - c.x) ^ 2 + (t.y - c.y) ^ 2) > 25 then
                    W("%s: %s -> %s: a very long link (over 25 %% of the map): a typo?", c._area, id, to)
                end
                if oneWay then
                    local text = (tostring(c.note or "") .. " " .. tostring(lt and lt.note or "")):lower()
                    for _, w in ipairs(trick) do
                        if text:find(w) then E("%s: %s -> %s: one-way link that reads like a trick (%s)", c._area, id, to, w) end
                    end
                end
            end
        end
    end
    -- every room has an exit: a node inside it linked to a node outside it
    for rid in pairs(rooms) do
        local exit = false
        for _, id in ipairs(order) do
            if nodes[id].inside == rid then
                for _, to in ipairs(adj[id]) do if nodes[to].inside ~= rid then exit = true end end
            end
        end
        if not exit then E("room %s: no exit connector (a node inside it linked to one outside)", rid) end
    end
    -- no islands: every node reachable from an outdoor node (inside = nil)
    local seen, queue = {}, {}
    for _, id in ipairs(order) do
        if nodes[id].inside == nil then seen[id] = true queue[#queue + 1] = id end
    end
    local q = 1
    while queue[q] do
        for _, to in ipairs(adj[queue[q]] or {}) do
            if not seen[to] then seen[to] = true queue[#queue + 1] = to end
        end
        q = q + 1
    end
    for _, id in ipairs(order) do
        if not seen[id] then E("%s: %s: can't be reached from outdoors (an island)", nodes[id]._area, id) end
    end
    for _, id in ipairs(order) do nodes[id]._area = nil end
    return errs, warns
end

-- ------------------------------------------------------------------ compile
local function Lit(v)
    local t = type(v)
    if t == "string" then return Fmt("%q", v) end
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return Fmt("%d", v) end
        return (Fmt("%.4f", v):gsub("0+$", ""):gsub("%.$", ""))
    end
    if t == "boolean" then return tostring(v) end
    error("can't write a " .. t)
end

local NODE_KEYS = { "id", "map", "x", "y", "r", "kind", "hint", "inside", "oneWay" }
local ROOM_KEYS = { "id", "map", "indoor", "chain" }

local function Fields(t, keys)
    local out = {}
    for _, k in ipairs(keys) do
        if t[k] ~= nil then out[#out + 1] = k .. " = " .. Lit(t[k]) end
    end
    return out
end

-- Only what the addon needs: no subzone (checker only), src, confirmed or notes.
function CC.Compile(list)
    local L = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2026 gettic",
        "-- Generated by tools/connectors.lua from packs-src/connectors/*.lua (smart arrow). Never edit by hand.",
        "local _, ns = ...",
        "local R = ns.SmartRoute.Register",
    }
    local sorted = {}
    for _, d in ipairs(list) do sorted[#sorted + 1] = d end
    table.sort(sorted, function(a, b) return a.area < b.area end)
    for _, data in ipairs(sorted) do
        L[#L + 1] = "R({ area = " .. Lit(data.area) .. ","
        L[#L + 1] = "    connectors = {"
        for _, c in ipairs(data.connectors or {}) do
            local f = Fields(c, NODE_KEYS)
            if c.link and #c.link > 0 then
                local links = {}
                for _, l in ipairs(c.link) do
                    local to, lt = LinkTarget(l)
                    if lt then
                        local parts = { Lit(to) }
                        if lt.cost then parts[#parts + 1] = "cost = " .. Lit(lt.cost) end
                        if lt.oneWay then parts[#parts + 1] = "oneWay = true" end
                        links[#links + 1] = "{ " .. table.concat(parts, ", ") .. " }"
                    else
                        links[#links + 1] = Lit(to)
                    end
                end
                f[#f + 1] = "link = { " .. table.concat(links, ", ") .. " }"
            end
            L[#L + 1] = "        { " .. table.concat(f, ", ") .. " },"
        end
        L[#L + 1] = "    },"
        L[#L + 1] = "    rooms = {"
        for _, r in ipairs(data.rooms or {}) do
            local f = Fields(r, ROOM_KEYS)
            local pts = {}
            for _, p in ipairs(r.poly or {}) do pts[#pts + 1] = "{ " .. Lit(p[1]) .. ", " .. Lit(p[2]) .. " }" end
            f[#f + 1] = "poly = { " .. table.concat(pts, ", ") .. " }"
            L[#L + 1] = "        { " .. table.concat(f, ", ") .. " },"
        end
        L[#L + 1] = "    },"
        L[#L + 1] = "})"
    end
    return table.concat(L, "\n") .. "\n"
end

-- ------------------------------------------------------------------ steps (used by build / packcheck)
local function InPoly(poly, x, y)
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

local function Area(poly)
    local a = 0
    for i = 1, #poly do
        local p, q = poly[i], poly[i % #poly + 1]
        a = a + p[1] * q[2] - q[1] * p[2]
    end
    return math.abs(a) / 2
end

-- Index of the connector data: nodes by id, rooms by id, exits per room.
function CC.Index(list)
    local idx = { nodes = {}, rooms = {}, exits = {} }
    for _, data in ipairs(list or {}) do
        for _, c in ipairs(data.connectors or {}) do if type(c.id) == "string" then idx.nodes[c.id] = c end end
        for _, r in ipairs(data.rooms or {}) do if type(r.id) == "string" then idx.rooms[r.id] = r end end
    end
    for id, c in pairs(idx.nodes) do
        for _, l in ipairs(c.link or {}) do
            local to = LinkTarget(l)
            local t = idx.nodes[to]
            if t and t.inside ~= c.inside then
                if c.inside then idx.exits[c.inside] = true end
                if t.inside then idx.exits[t.inside] = true end
            end
        end
        idx.nodes[id] = c
    end
    return idx
end

-- The smallest room holding map / x / y (percent), or nil. The indoor flag isn't known at build time.
function CC.RoomAt(idx, map, x, y)
    local best, bestArea
    for id, r in pairs(idx.rooms) do
        if r.map == map and r.poly and #r.poly >= 3 and InPoly(r.poly, x, y) then
            local a = Area(r.poly)
            if not best or a < bestArea or (a == bestArea and id < best) then best, bestArea = id, a end
        end
    end
    return best
end

-- Writes step.room for every step whose spot is inside a room (the build, before compiling).
function CC.SetRooms(routes, idx)
    local n = 0
    for _, r in ipairs(routes or {}) do
        for _, s in ipairs(r.steps or {}) do
            if type(s.map) == "number" and type(s.x) == "number" and type(s.y) == "number" then
                s.room = CC.RoomAt(idx, s.map, s.x, s.y)
                if s.room then n = n + 1 end
            end
        end
    end
    return n
end

-- Step rules (plan 1d): a `via` names existing connectors (or valid inline points); a step's goal inside a room
-- needs a way in (the room has an exit); a `via` way longer than 1.5 x the straight line from the step before
-- without a `why` note is a warning (least travel). Distances in map percent (same map only).
function CC.StepCheck(routes, idx)
    local errs, warns = {}, {}
    for _, r in ipairs(routes or {}) do
        local prev
        for i, s in ipairs(r.steps or {}) do
            local where = r.id .. " #" .. i .. " " .. tostring(s.id)
            local hasSpot = type(s.map) == "number" and type(s.x) == "number" and type(s.y) == "number"
            if s.via ~= nil and s.via ~= false then
                if type(s.via) ~= "table" or #s.via == 0 then
                    errs[#errs + 1] = where .. ": via must be a list of connector ids / points, or false"
                else
                    local pts = {}
                    for _, v in ipairs(s.via) do
                        if type(v) == "string" then
                            local n = idx.nodes[v]
                            if not n then errs[#errs + 1] = where .. ": via '" .. v .. "' is not a connector"
                            else pts[#pts + 1] = n end
                        elseif type(v) == "table" and Num(v.map) and Num(v.x) and Num(v.y)
                            and v.x >= 0 and v.x <= 100 and v.y >= 0 and v.y <= 100 then
                            pts[#pts + 1] = v
                        else
                            errs[#errs + 1] = where .. ": a via point needs map and x / y in 0-100"
                        end
                    end
                    if hasSpot and prev and #pts == #s.via then
                        local walk, last, same = 0, prev, true
                        for _, p in ipairs(pts) do
                            if p.map ~= last.map then same = false break end
                            walk = walk + math.sqrt((p.x - last.x) ^ 2 + (p.y - last.y) ^ 2)
                            last = p
                        end
                        if same and s.map == last.map then
                            walk = walk + math.sqrt((s.x - last.x) ^ 2 + (s.y - last.y) ^ 2)
                            local straight = math.sqrt((s.x - prev.x) ^ 2 + (s.y - prev.y) ^ 2)
                            if straight > 0 and walk > 1.5 * straight and not s.why then
                                warns[#warns + 1] = where .. (": the via way is %.1fx the straight line with no why (least travel)")
                                    :format(walk / straight)
                            end
                        end
                    end
                end
            end
            if hasSpot then
                local room = CC.RoomAt(idx, s.map, s.x, s.y)
                if room and not idx.exits[room] then
                    errs[#errs + 1] = where .. ": the spot is in room " .. room .. ", which has no exit connector"
                end
                prev = s
            end
        end
    end
    return errs, warns
end

-- ------------------------------------------------------------------ files
local function LoadData(path)
    local chunk, err = loadfile(path)
    if not chunk then return nil, err end
    setfenv(chunk, {})
    local ok, v = pcall(chunk)
    if not ok then return nil, v end
    return v
end
CC.LoadData = LoadData

local function ListDir(dir)
    local out = {}
    local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.lua" 2>nul')
    if p then
        for line in p:lines() do
            line = line:gsub("\r", "")
            if line ~= "" then out[#out + 1] = line end
        end
        p:close()
    end
    table.sort(out)
    return out
end

function CC.LoadAll(dir)
    local list, errs = {}, {}
    for _, f in ipairs(ListDir(dir)) do
        local data, err = LoadData(dir .. "/" .. f)
        if type(data) == "table" then list[#list + 1] = data
        else errs[#errs + 1] = f .. ": " .. tostring(err or "doesn't return a table") end
    end
    return list, errs
end

-- Locale keys of enUS / daDK (the files call ns.Locale.Add(code, table)).
function CC.LoadKeys(addon)
    local keys = {}
    for _, code in ipairs({ "enUS", "daDK" }) do
        local chunk = loadfile(addon .. "/Locale/" .. code .. ".lua")
        if chunk then
            local ns = { Locale = { Add = function(c, t) keys[c] = t end } }
            setfenv(chunk, { pairs = pairs, ipairs = ipairs, type = type, tostring = tostring })
            pcall(chunk, "AllinOneGuide", ns)
        end
    end
    return keys
end

local function ReadFile(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

-- Checks and compiles (or with opts.check compares). opts = { addon, src, out, exploits, maps, check }, paths
-- relative to the repository. Returns exit code (0 = fine), the loaded list.
function CC.Run(opts)
    opts.addon = opts.addon or "AllinOneGuide"
    opts.src = opts.src or "packs-src/connectors"
    opts.exploits = opts.exploits or "packs-src/known-exploits.lua"
    opts.out = opts.out or (opts.addon .. "/Routes/Connectors.lua")
    local list, lerrs = CC.LoadAll(opts.src)
    local maps = LoadData(opts.maps or "tools/data/maps.lua")
    local errs, warns = CC.Check(list, { maps = type(maps) == "table" and maps or nil, keys = CC.LoadKeys(opts.addon),
        exploits = LoadData(opts.exploits) })
    for _, e in ipairs(lerrs) do errs[#errs + 1] = e end
    for _, w in ipairs(warns) do print("WARN " .. w) end
    for _, e in ipairs(errs) do print("ERROR " .. e) end
    if #errs > 0 then
        print(Fmt("connectors: %d error(s), nothing written", #errs))
        return 1, list
    end
    local text = CC.Compile(list)
    local old = ReadFile(opts.out)
    if old == text then
        print(Fmt("connectors: %d area(s) up to date", #list))
        return 0, list
    end
    if opts.check then
        print("DIFFERS " .. opts.out .. (old and "" or " (missing)") .. ": run tools\\build.ps1 (or luajit tools/connectors.lua)")
        return 1, list
    end
    local fh = assert(io.open(opts.out, "wb"))
    fh:write(text)
    fh:close()
    print(Fmt("connectors: wrote %s (%d area(s))", opts.out, #list))
    return 0, list
end

function CC.Main(args)
    local opts = {}
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--check" then opts.check = true i = i + 1
        elseif a == "--addon" or a == "--out" or a == "--src" then opts[a:sub(3)] = args[i + 1] i = i + 2
        else i = i + 1 end
    end
    return (CC.Run(opts))
end

if argv[1] == "--lib" then return CC end
os.exit(CC.Main(argv))

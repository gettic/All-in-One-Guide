-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Hunt path generator (v0.3): writes packs-src\paths\<pack id>.lua, the loops the arrow leads round on kill /
-- collect steps that say `path = "auto"`. Our own loops, made from bare spawn position FACTS of a LOCAL CMaNGOS
-- classic-db SQL dump (https://github.com/cmangos/classic-db, GPL-3.0), read as text by tools\import\cmangos.lua.
-- Never used: waypoint / movement tables, other addons' or guides' points, anything from the reference guides.
--   1. spawns of the step's npc (+ targetNpc) on the step's map, turned into map percent by a per-map fit made
--      from the NPC spots in our own packs (cmangos.lua CM.Calibrate; a fit worse than MAX_FIT yd skips the map)
--   2. only spawns within NEAR yd of the step spot and in the step spot's own connector room
--   3. the biggest cluster (spawns within LINK yd of each other are linked)
--   4. about one point per two GRID yd cells the cluster covers (3..MAX): the middles of that many groups of
--      spawns (k-means), snapped to a SNAP yd grid (no single spawn coordinate is copied); points that fall in
--      another room are dropped
--   5. ordered as a closed tour (nearest neighbour from the point nearest the step spot, then 2-opt)
--   6. simplified: a point within FLAT yd of the line between its neighbours goes (never below 3 points, never
--      making a leg longer than LEG yd); rounded to 0.1 %
-- A step whose cluster covers fewer than 3 cells gets no entry (the tool says so: use `path = false` there).
-- Run (from the repository folder; the dump path is an argument, never stored):
--   luajit tools/import/huntpath.lua --sql <ClassicDB.sql> [--out packs-src/paths] [--calibrate <pack> ...]
--          [--check] packs-src/elwynn.lua packs-src/durotar.lua
--   --calibrate: packs whose NPC spots make the fit (default: every pack in packs-src\)
--   --check: write nothing, fail when a paths file would change
-- As a library: local HP = assert(loadfile("tools/import/huntpath.lua"))("--lib", "<tools folder>")
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2])
    or (arg and arg[0] and arg[0]:match("^(.*)[/\\]import[/\\][^/\\]+$")) or "tools"
local HP = { NEAR = 200, LINK = 40, GRID = 25, SNAP = 10, FLAT = 8, LEG = 110, MAX = 8, MAX_FIT = 15 }

local Lib = assert(loadfile(toolsDir .. "/packlib.lua"))()
local CM = assert(loadfile(toolsDir .. "/import/cmangos.lua"))()
local CC = assert(loadfile(toolsDir .. "/connectors.lua"))("--lib", toolsDir)
local sizes = assert(loadfile(toolsDir .. "/data/mapsizes.lua"))()
HP.Lib, HP.CM, HP.CC, HP.sizes = Lib, CM, CC, sizes

local sqrt, floor = math.sqrt, math.floor

-- ------------------------------------------------------------------ geometry in yards
-- Percent <-> yards on one map (x yards = x% * width / 100).
local function ToYd(size, p) return { p[1] / 100 * size[1], p[2] / 100 * size[2] } end
local function ToPct(size, p) return { p[1] * 100 / size[1], p[2] * 100 / size[2] } end
local function D(a, b) return sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

-- Distance from p to the segment a -> b.
local function SegD(p, a, b)
    local vx, vy = b[1] - a[1], b[2] - a[2]
    local l2 = vx * vx + vy * vy
    local u = l2 > 0 and ((p[1] - a[1]) * vx + (p[2] - a[2]) * vy) / l2 or 0
    u = math.max(0, math.min(1, u))
    return sqrt((p[1] - a[1] - u * vx) ^ 2 + (p[2] - a[2] - u * vy) ^ 2)
end

-- Clusters (single link within `link` yd); returns the biggest (ties: the one nearest `home`).
function HP.Cluster(pts, link, home)
    local seen, best, bestD = {}, nil, nil
    for i = 1, #pts do
        if not seen[i] then
            local group, queue = {}, { i }
            seen[i] = true
            while #queue > 0 do
                local k = table.remove(queue)
                group[#group + 1] = pts[k]
                for j = 1, #pts do
                    if not seen[j] and D(pts[k], pts[j]) <= link then
                        seen[j] = true
                        queue[#queue + 1] = j
                    end
                end
            end
            local near = math.huge
            for _, p in ipairs(group) do near = math.min(near, D(p, home)) end
            if not best or #group > #best or (#group == #best and near < bestD) then best, bestD = group, near end
        end
    end
    return best or {}
end

-- k groups (k-means, seeded deterministically: the point nearest `home`, then each time the point farthest from
-- every seed so far); returns the group centres (averages of several spawns), snapped to a `snap` yd grid.
function HP.Centres(pts, k, home, snap)
    local seeds, best, bd = {}, nil, math.huge
    for _, p in ipairs(pts) do
        local d = D(p, home)
        if d < bd then best, bd = p, d end
    end
    seeds[1] = { best[1], best[2] }
    while #seeds < k do
        local far, fd = nil, -1
        for _, p in ipairs(pts) do
            local m = math.huge
            for _, s in ipairs(seeds) do m = math.min(m, D(p, s)) end
            if m > fd then far, fd = p, m end
        end
        if fd <= 0 then break end
        seeds[#seeds + 1] = { far[1], far[2] }
    end
    for _ = 1, 30 do
        local sx, sy, n = {}, {}, {}
        for i = 1, #seeds do sx[i], sy[i], n[i] = 0, 0, 0 end
        for _, p in ipairs(pts) do
            local bi, bdd = 1, math.huge
            for i, s in ipairs(seeds) do
                local d = D(p, s)
                if d < bdd then bi, bdd = i, d end
            end
            sx[bi], sy[bi], n[bi] = sx[bi] + p[1], sy[bi] + p[2], n[bi] + 1
        end
        local moved = false
        for i, s in ipairs(seeds) do
            if n[i] > 0 then
                local nx, ny = sx[i] / n[i], sy[i] / n[i]
                if math.abs(nx - s[1]) > 1e-6 or math.abs(ny - s[2]) > 1e-6 then moved = true end
                s[1], s[2] = nx, ny
            end
        end
        if not moved then break end
    end
    local out, seen = {}, {}
    for _, s in ipairs(seeds) do
        local c = { (floor(s[1] / snap) + 0.5) * snap, (floor(s[2] / snap) + 0.5) * snap }
        local key = c[1] .. ":" .. c[2]
        if not seen[key] then seen[key] = true out[#out + 1] = c end
    end
    return out
end

-- Grid cells (centres) holding at least one point, in a fixed order.
function HP.Cells(pts, grid)
    local cells, list = {}, {}
    for _, p in ipairs(pts) do
        local gx, gy = floor(p[1] / grid), floor(p[2] / grid)
        local key = gx .. ":" .. gy
        if not cells[key] then
            cells[key] = true
            list[#list + 1] = { (gx + 0.5) * grid, (gy + 0.5) * grid }
        end
    end
    table.sort(list, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    return list
end

local function TourLen(t)
    local s = 0
    for i = 1, #t do s = s + D(t[i], t[i % #t + 1]) end
    return s
end

-- Closed tour: nearest neighbour from the point nearest `home`, then 2-opt until nothing improves.
function HP.Tour(pts, home)
    local n = #pts
    if n == 0 then return {} end
    local start, sd = 1, math.huge
    for i, p in ipairs(pts) do
        local d = D(p, home)
        if d < sd then start, sd = i, d end
    end
    local used, tour = { [start] = true }, { pts[start] }
    for _ = 2, n do
        local last, bi, bd = tour[#tour], nil, math.huge
        for i, p in ipairs(pts) do
            if not used[i] then
                local d = D(last, p)
                if d < bd then bi, bd = i, d end
            end
        end
        used[bi] = true
        tour[#tour + 1] = pts[bi]
    end
    local improved = true
    while improved and n >= 4 do
        improved = false
        for i = 1, n - 2 do
            for j = i + 2, n do
                if not (i == 1 and j == n) then
                    local a, b, c, d = tour[i], tour[i + 1], tour[j], tour[j % n + 1]
                    if D(a, c) + D(b, d) < D(a, b) + D(c, d) - 1e-9 then
                        local lo, hi = i + 1, j
                        while lo < hi do
                            tour[lo], tour[hi] = tour[hi], tour[lo]
                            lo, hi = lo + 1, hi - 1
                        end
                        improved = true
                    end
                end
            end
        end
    end
    return tour
end

-- Drops points that hardly bend the loop (closest to the line between their neighbours first), while that point
-- is within `flat` yd of it, or while there are more than `max` points; never below 3, never a leg over `leg`.
function HP.Simplify(t, flat, max, leg)
    t = { unpack(t) }
    while #t > 3 do
        local n, bi, bd = #t, nil, math.huge
        for i = 1, n do
            local a, b = t[(i - 2) % n + 1], t[i % n + 1]
            if D(a, b) <= leg then
                local d = SegD(t[i], a, b)
                if d < bd then bi, bd = i, d end
            end
        end
        if not bi or (bd > flat and n <= max) then break end
        table.remove(t, bi)
    end
    return t
end

-- ------------------------------------------------------------------ one step
local function R1(v) return floor(v * 10 + 0.5) / 10 end

-- Returns points (percent, rounded) or nil, why. step = expanded source step; db / fits from cmangos.lua;
-- idx = connector index (or nil).
function HP.Loop(step, db, fits, idx)
    local size = sizes[step.map]
    if not size then return nil, "map " .. tostring(step.map) .. " has no size" end
    if not fits[step.map] then return nil, "no spawn fit for map " .. tostring(step.map) end
    local ids = {}
    if type(step.npc) == "number" then ids[#ids + 1] = step.npc end
    if type(step.targetNpc) == "number" and step.targetNpc ~= step.npc then ids[#ids + 1] = step.targetNpc end
    if #ids == 0 then return nil, "no npc / targetNpc (objects need a hand loop)" end
    local home = ToYd(size, { step.x, step.y })
    local homeRoom = idx and CC.RoomAt(idx, step.map, step.x, step.y)
    local pts = {}
    for _, id in ipairs(ids) do
        for _, p in ipairs(CM.ZonePoints(db, fits, id, step.map)) do
            local y = ToYd(size, p)
            if D(y, home) <= HP.NEAR and (not idx or CC.RoomAt(idx, step.map, p[1], p[2]) == homeRoom) then
                pts[#pts + 1] = y
            end
        end
    end
    if #pts == 0 then return nil, "no spawns within " .. HP.NEAR .. " yd in the step's room" end
    local cluster = HP.Cluster(pts, HP.LINK, home)
    local cells = HP.Cells(cluster, HP.GRID)
    if #cells < 3 then return nil, ("only %d grid cell(s) from %d spawns: use path = false"):format(#cells, #cluster) end
    -- the loop's points: about one per two cells, 3..MAX, each the middle of a group of spawns
    local k = math.max(3, math.min(HP.MAX, math.ceil(#cells / 2)))
    local centres = HP.Centres(cluster, k, home, HP.SNAP)
    -- a point must still be in the step's room (a wall next to the spawns)
    if idx then
        local keep = {}
        for _, c in ipairs(centres) do
            local pc = ToPct(size, c)
            if CC.RoomAt(idx, step.map, pc[1], pc[2]) == homeRoom then keep[#keep + 1] = c end
        end
        centres = keep
    end
    if #centres < 3 then return nil, ("only %d point(s) left: use path = false"):format(#centres) end
    local loop = HP.Simplify(HP.Tour(centres, home), HP.FLAT, HP.MAX, HP.LEG)
    loop = HP.Tour(loop, home)
    -- a leg longer than LEG gets a point in its middle (when that is in the step's room), up to 12 points
    local i = 1
    while i <= #loop and #loop < 12 do
        local a, b = loop[i], loop[i % #loop + 1]
        local mid = { (floor((a[1] + b[1]) / 2 / HP.SNAP) + 0.5) * HP.SNAP, (floor((a[2] + b[2]) / 2 / HP.SNAP) + 0.5) * HP.SNAP }
        local pm = ToPct(size, mid)
        if D(a, b) > HP.LEG and (not idx or CC.RoomAt(idx, step.map, pm[1], pm[2]) == homeRoom) then
            table.insert(loop, i + 1, mid)
        else
            i = i + 1
        end
    end
    local out = {}
    for n, c in ipairs(loop) do
        local p = ToPct(size, c)
        out[n] = { R1(p[1]), R1(p[2]) }
    end
    return out, ("%d spawns, %d in the cluster, %d cells, %d points, %.0f yd"):format(#pts, #cluster, #cells, #out,
        TourLen(loop))
end

-- ------------------------------------------------------------------ files
local function Ours(files)
    local ours = {}
    local function Walk(t, seen)
        if type(t) ~= "table" or seen[t] then return end
        seen[t] = true
        if type(t.npc) == "number" and type(t.map) == "number" and type(t.x) == "number" and type(t.y) == "number" then
            local l = ours[t.npc] or {}
            local dup = false
            for _, p in ipairs(l) do
                if p[1] == t.map and math.abs(p[2] - t.x) < 0.3 and math.abs(p[3] - t.y) < 0.3 then dup = true end
            end
            if not dup then l[#l + 1] = { t.map, t.x, t.y } end
            ours[t.npc] = l
        end
        for _, v in pairs(t) do Walk(v, seen) end
    end
    for _, f in ipairs(files) do
        local d = Lib.LoadData(f)
        if d then Walk(d, {}) end
    end
    return ours
end
HP.Ours = Ours

-- The paths file text (deterministic: steps sorted by id).
function HP.Text(packId, entries)
    local ids = {}
    for id in pairs(entries) do ids[#ids + 1] = id end
    table.sort(ids)
    local L = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2026 gettic",
        "-- Hunt paths of pack " .. packId .. " (packs-src\\FORMAT.md \"Hunt paths\"). Generated from CMaNGOS classic-db spawn",
        "-- facts (GPL-3.0), grid-snapped and ordered by tools\\import\\huntpath.lua. Edit by hand only with src = \"hand\".",
        "return {",
        ("    pack = %q, formatVersion = 1, license = \"GPL-3.0-or-later\","):format(packId),
        "    steps = {",
    }
    for _, id in ipairs(ids) do
        local e = entries[id]
        local pts = {}
        for i, p in ipairs(e.points) do pts[i] = ("{ %s, %s }"):format(("%.1f"):format(p[1]), ("%.1f"):format(p[2])) end
        L[#L + 1] = ("        [%q] = { src = %q, points = { %s } },"):format(id, e.src, table.concat(pts, ", "))
    end
    L[#L + 1] = "    },"
    L[#L + 1] = "}"
    return table.concat(L, "\n") .. "\n"
end

function HP.Main(argv)
    local opts = { out = "packs-src/paths", files = {}, calibrate = {} }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--sql" or a == "--out" then
            opts[a:sub(3)] = argv[i + 1]
            i = i + 2
        elseif a == "--calibrate" then
            opts.calibrate[#opts.calibrate + 1] = argv[i + 1]
            i = i + 2
        elseif a == "--check" then
            opts.check = true
            i = i + 1
        else
            opts.files[#opts.files + 1] = a
            i = i + 1
        end
    end
    if not opts.sql or #opts.files == 0 then
        print("usage: luajit tools/import/huntpath.lua --sql <ClassicDB.sql> [--out dir] [--calibrate pack ...] [--check] pack ...")
        return false
    end
    if #opts.calibrate == 0 then
        for _, f in ipairs(Lib.ListDir("packs-src", "lua")) do opts.calibrate[#opts.calibrate + 1] = "packs-src/" .. f end
    end
    local db = assert(CM.Read(opts.sql))
    local fits = CM.Calibrate(Ours(opts.calibrate), db.creatures)
    for m, f in pairs(fits) do
        local size = sizes[m]
        local yd = size and f.rms / 100 * math.max(size[1], size[2]) or math.huge
        if yd > HP.MAX_FIT then
            print(("map %d: fit %.1f yd (over %d), skipped"):format(m, yd, HP.MAX_FIT))
            fits[m] = nil
        end
    end
    local list = CC.LoadAll("packs-src/connectors")
    local idx = #list > 0 and CC.Index(list) or nil
    local ok = true
    for _, f in ipairs(opts.files) do
        local pack = assert(Lib.LoadData(f))
        local routes = Lib.Expand(pack)   -- "auto" steps without an entry yet are reported there; ignored here
        local entries, n = {}, 0
        for _, r in ipairs(routes) do
            for _, s in ipairs(r.steps) do
                if s.path == "auto" or (type(s.path) == "table" and s.pathSrc == "gen") then
                    local pts, why = HP.Loop(s, db, fits, idx)
                    if pts then
                        entries[s.id], n = { src = "gen", points = pts }, n + 1
                        print(("%s %s: %s"):format(pack.id, s.id, why))
                    else
                        print(("%s %s: NO LOOP: %s"):format(pack.id, s.id, why))
                    end
                end
            end
        end
        if n > 0 then
            local path = opts.out .. "/" .. pack.id .. ".lua"
            local text = HP.Text(pack.id, entries)
            local old = Lib.ReadFile(path)
            if old == text then
                print("unchanged " .. path)
            elseif opts.check then
                print("DIFFERS " .. path)
                ok = false
            else
                local fh = io.open(path, "wb")
                if not fh then
                    os.execute('mkdir "' .. opts.out:gsub("/", "\\") .. '"')
                    fh = assert(io.open(path, "wb"))
                end
                fh:write(text)
                fh:close()
                print("wrote " .. path)
            end
        end
    end
    return ok
end

if args[1] == "--lib" then return HP end
if not HP.Main(args) then os.exit(1) end

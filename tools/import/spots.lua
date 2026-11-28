-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Spawn spot generator (v0.3, plans\spawn-arrow\plan.md): writes packs-src\spots\<pack id>.lua, the spawn spots the
-- arrow picks from on kill / collect steps (Engine\Spots.lua: the nearest spot you haven't cleared). Our own spots,
-- made from bare spawn position and respawn time FACTS of a LOCAL CMaNGOS classic-db SQL dump
-- (https://github.com/cmangos/classic-db, GPL-3.0), read as text by tools\import\cmangos.lua. Creatures only (no
-- game objects). Never used: waypoint / movement tables, other addons' or guides' points, the reference guides.
--   1. every objective step with an npc / targetNpc: that creature's spawns on the step's map within NEAR yd of the
--      step spot, in the step spot's connector room, outside known-exploit places (per-map fit from cmangos.lua)
--   2. spawns within LINK yd of a camp's first spawn = one spot (a camp); the spot = the camp's middle snapped to a SNAP yd
--      grid (no single spawn coordinate is copied); respawn = the camp's median spawntimesecsmin, clamped
--      MIN_RESP..MAX_RESP (DEFAULT_RESP when the dump has none)
--   3. per target (npc @ map) at most MAX spots, nearest to the step spot first; a target with fewer than MIN spots
--      gets no entry (a lone quest NPC is no hunt)
-- Run (from the repository folder; the dump path is an argument, never stored):
--   luajit tools/import/spots.lua --sql <ClassicDB.sql> [--out packs-src/spots] [--check] packs-src/elwynn.lua ...
--   --check: write nothing, fail when a spots file would change
-- As a library: local SP = assert(loadfile("tools/import/spots.lua"))("--lib", "<tools folder>")
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2])
    or (arg and arg[0] and arg[0]:match("^(.*)[/\\]import[/\\][^/\\]+$")) or "tools"
local SP = { NEAR = 400, LINK = 20, SNAP = 5, MAX = 40, MIN = 2, MAX_FIT = 15, MIN_RESP = 120, MAX_RESP = 900,
    DEFAULT_RESP = 300, AREA = 90, QUEST_MOBS = "AllinOneGuide/Data/QuestMobs.lua" }
--   4. huge spawn areas: only the area nearest the step spot is kept (spots chained within AREA yd of a kept spot,
--      starting at the nearest one), so a step never sends you across the zone
--   5. a step that names no mob uses its quest's mobs from Data\QuestMobs.lua (quest id -> creature ids, also cmangos)

local Lib = assert(loadfile(toolsDir .. "/packlib.lua"))()
local CM = assert(loadfile(toolsDir .. "/import/cmangos.lua"))()
local CC = assert(loadfile(toolsDir .. "/connectors.lua"))("--lib", toolsDir)
local HP = assert(loadfile(toolsDir .. "/import/huntpath.lua"))("--lib", toolsDir)
local sizes = assert(loadfile(toolsDir .. "/data/mapsizes.lua"))()
SP.Lib, SP.CM, SP.CC, SP.sizes = Lib, CM, CC, sizes

local sqrt, floor = math.sqrt, math.floor
local function ToYd(size, p) return { p[1] / 100 * size[1], p[2] / 100 * size[2] } end
local function ToPct(size, p) return { p[1] * 100 / size[1], p[2] * 100 / size[2] } end
local function D(a, b) return sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
local function R1(v) return floor(v * 10 + 0.5) / 10 end

-- Camps: spawns taken nearest-to-home first; each joins the first camp whose first spawn is within `link` yd, else
-- starts a new one (so a camp is never wider than 2 x link, even where spawns form a long chain). Returns
-- { points } lists, deterministic for the same input order.
function SP.Groups(pts, link, home)
    local order = {}
    for i = 1, #pts do order[i] = i end
    table.sort(order, function(a, b)
        local da, db = D(pts[a], home), D(pts[b], home)
        if da ~= db then return da < db end
        if pts[a][1] ~= pts[b][1] then return pts[a][1] < pts[b][1] end
        return pts[a][2] < pts[b][2]
    end)
    local out = {}
    for _, i in ipairs(order) do
        local p, joined = pts[i], false
        for _, g in ipairs(out) do
            if D(g[1], p) <= link then
                g[#g + 1] = p
                joined = true
                break
            end
        end
        if not joined then out[#out + 1] = { p } end
    end
    return out
end

local function Median(list)
    if #list == 0 then return nil end
    table.sort(list)
    return list[floor((#list + 1) / 2)]
end

function SP.Respawn(group)
    local times = {}
    for _, p in ipairs(group) do if type(p.resp) == "number" and p.resp > 0 then times[#times + 1] = p.resp end end
    local m = Median(times) or SP.DEFAULT_RESP
    m = math.max(SP.MIN_RESP, math.min(SP.MAX_RESP, m))
    return floor(m / 10 + 0.5) * 10
end

local function InExploit(exploits, map, pct, size)
    for _, x in ipairs(exploits or {}) do
        for _, pl in ipairs(x.places or {}) do
            if pl[1] == map then
                local d = D(ToYd(size, { pl[2], pl[3] }), ToYd(size, pct))
                if d <= (pl[4] or 0) then return true end
            end
        end
    end
    return false
end

-- Rule 4: the spots chained to the one nearest the step spot (each within AREA yd of an already kept spot).
function SP.Area(list)
    if #list == 0 then return list end
    local start = 1
    for i, s in ipairs(list) do if s.d < list[start].d then start = i end end
    local keep, kept, grew = { [start] = true }, { list[start] }, true
    while grew do
        grew = false
        for i, s in ipairs(list) do
            if not keep[i] then
                for _, k in ipairs(kept) do
                    if D(s.yd, k.yd) <= SP.AREA then
                        keep[i], kept[#kept + 1], grew = true, s, true
                        break
                    end
                end
            end
        end
    end
    local out = {}
    for i, s in ipairs(list) do if keep[i] then out[#out + 1] = s end end
    return out
end

-- Rule 5: Data\QuestMobs.lua as a table (quest id -> creature ids), or {}.
function SP.QuestMobs(path)
    local f = loadfile(path or SP.QUEST_MOBS)
    if not f then return {} end
    local ns = {}
    local ok = pcall(f, "AllinOneGuide", ns)
    return ok and ns.QuestMobs or {}
end

-- The spots of one creature for one step: list of { x%, y%, respawn, d (yd from the step spot) } or nil, why.
function SP.ForStep(step, id, db, fits, idx, exploits)
    local size = sizes[step.map]
    if not size then return nil, "map " .. tostring(step.map) .. " has no size" end
    if not fits[step.map] then return nil, "no spawn fit for map " .. tostring(step.map) end
    local home = ToYd(size, { step.x, step.y })
    local homeRoom = idx and CC.RoomAt(idx, step.map, step.x, step.y)
    local pts = {}
    for _, p in ipairs(CM.ZonePoints(db, fits, id, step.map)) do
        local y = ToYd(size, p)
        if D(y, home) <= SP.NEAR and (not idx or CC.RoomAt(idx, step.map, p[1], p[2]) == homeRoom)
            and not InExploit(exploits, step.map, p, size) then
            pts[#pts + 1] = { y[1], y[2], resp = p[3] }
        end
    end
    if #pts == 0 then return nil, "no spawns within " .. SP.NEAR .. " yd in the step's room" end
    local out = {}
    for _, g in ipairs(SP.Groups(pts, SP.LINK, home)) do
        local sx, sy = 0, 0
        for _, p in ipairs(g) do sx, sy = sx + p[1], sy + p[2] end
        local c = { (floor(sx / #g / SP.SNAP) + 0.5) * SP.SNAP, (floor(sy / #g / SP.SNAP) + 0.5) * SP.SNAP }
        local pc = ToPct(size, c)
        if (not idx or CC.RoomAt(idx, step.map, pc[1], pc[2]) == homeRoom) and not InExploit(exploits, step.map, pc, size) then
            out[#out + 1] = { R1(pc[1]), R1(pc[2]), SP.Respawn(g), d = D(c, home), yd = c }
        end
    end
    out = SP.Area(out)
    return out, ("%d spawns, %d spots"):format(#pts, #out)
end

-- Merges a step's spots into a target's list (same rounded spot once; nearest to any step spot kept).
local function Merge(list, spots)
    local at = {}
    for k, s in ipairs(list) do at[s[1] .. ":" .. s[2]] = k end
    for _, s in ipairs(spots) do
        local key = s[1] .. ":" .. s[2]
        local k = at[key]
        if not k then
            list[#list + 1] = s
            at[key] = #list
        elseif s.d < list[k].d then
            list[k].d = s.d
        end
    end
end

-- All targets of a pack's routes: { ["npc@map"] = { spots } }, plus a log.
function SP.Pack(pack, db, fits, idx, exploits, questMobs)
    local routes = Lib.Expand(pack)
    local targets, log = {}, {}
    questMobs = questMobs or {}
    for _, r in ipairs(routes) do
        for _, s in ipairs(r.steps) do
            if s.type == "objective" and type(s.map) == "number" and type(s.x) == "number" and type(s.y) == "number"
                and s.spots ~= false then
                local ids = {}
                if type(s.npc) == "number" then ids[#ids + 1] = s.npc end
                if type(s.targetNpc) == "number" and s.targetNpc ~= s.npc then ids[#ids + 1] = s.targetNpc end
                if #ids == 0 and type(s.quest) == "number" then
                    for _, id in ipairs(questMobs[s.quest] or {}) do ids[#ids + 1] = id end
                    if #ids == 0 then log[#log + 1] = ("%s %s q%d: NOMOB"):format(pack.id, s.id, s.quest) end
                end
                for _, id in ipairs(ids) do
                    local spots, why = SP.ForStep(s, id, db, fits, idx, exploits)
                    local key = id .. "@" .. s.map
                    if spots and #spots > 0 then
                        targets[key] = targets[key] or {}
                        Merge(targets[key], spots)
                    end
                    log[#log + 1] = ("%s %s %s: %s"):format(pack.id, s.id, key, why)
                end
            end
        end
    end
    local keep = {}
    for key, list in pairs(targets) do
        table.sort(list, function(a, b)
            if a.d ~= b.d then return a.d < b.d end
            if a[1] ~= b[1] then return a[1] < b[1] end
            return a[2] < b[2]
        end)
        while #list > SP.MAX do table.remove(list) end
        if #list >= SP.MIN then keep[key] = list else log[#log + 1] = key .. ": fewer than " .. SP.MIN .. " spots, left out" end
    end
    return keep, log
end

-- The spots file text (deterministic: targets sorted by key, spots nearest first).
function SP.Text(packId, targets)
    local keys = {}
    for k in pairs(targets) do keys[#keys + 1] = k end
    table.sort(keys)
    local L = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2026 gettic",
        "-- Spawn spots of pack " .. packId .. " (packs-src\\FORMAT.md \"Spawn spots\"): { x %, y %, respawn s } per",
        "-- target (npc @ uiMapID), nearest to the step spot first. Generated from CMaNGOS classic-db spawn position and",
        "-- respawn time facts (GPL-3.0), camps grid-snapped by tools\\import\\spots.lua. Never edit by hand.",
        "return {",
        ("    pack = %q, formatVersion = 1, license = \"GPL-3.0-or-later\","):format(packId),
        "    targets = {",
    }
    for _, k in ipairs(keys) do
        local parts = {}
        for i, s in ipairs(targets[k]) do parts[i] = ("{ %.1f, %.1f, %d }"):format(s[1], s[2], s[3]) end
        L[#L + 1] = ("        [%q] = { %s },"):format(k, table.concat(parts, ", "))
    end
    L[#L + 1] = "    },"
    L[#L + 1] = "}"
    return table.concat(L, "\n") .. "\n"
end

-- The compiled addon file (Routes\Spots.lua) from every packs-src\spots\*.lua: one Register call per pack,
-- each target one string "x,y,r;..." (x / y in 0.1 %, r = respawn in 10 s).
function SP.Compile(files)
    local L = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2026 gettic",
        "-- Generated by tools\\build.lua from packs-src\\spots\\*.lua (tools\\import\\spots.lua). Never edit by hand.",
        "-- Spawn spots per target (npc @ uiMapID): \"x,y,r;...\" with x / y in 0.1 % and r = respawn in 10 s.",
        "local _, ns = ...",
        "if not (ns.Spots and ns.Spots.Register) then return end",
    }
    table.sort(files)
    for _, f in ipairs(files) do
        local d = assert(Lib.LoadData(f))
        local keys = {}
        for k in pairs(d.targets or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        L[#L + 1] = ("ns.Spots.Register(%q, {"):format(d.pack)
        for _, k in ipairs(keys) do
            local parts = {}
            for i, s in ipairs(d.targets[k]) do
                parts[i] = ("%d,%d,%d"):format(floor(s[1] * 10 + 0.5), floor(s[2] * 10 + 0.5), floor(s[3] / 10 + 0.5))
            end
            L[#L + 1] = ("    [%q] = %q,"):format(k, table.concat(parts, ";"))
        end
        L[#L + 1] = "})"
    end
    return table.concat(L, "\n") .. "\n"
end

-- Checks a spots source table: shape, ranges, spot counts. Returns a list of problems.
function SP.Check(d, name)
    local errs = {}
    local function E(msg) errs[#errs + 1] = name .. ": " .. msg end
    if type(d) ~= "table" or type(d.pack) ~= "string" or type(d.targets) ~= "table" then E("not a spots table") return errs end
    for k, list in pairs(d.targets) do
        if type(k) ~= "string" or not k:match("^%d+@%d+$") then E("bad target key " .. tostring(k)) end
        if type(list) ~= "table" or #list < SP.MIN or #list > SP.MAX then E(tostring(k) .. ": spot count out of range")
        else
            for _, s in ipairs(list) do
                if type(s[1]) ~= "number" or type(s[2]) ~= "number" or s[1] < 0 or s[1] > 100 or s[2] < 0 or s[2] > 100 then
                    E(k .. ": spot outside 0-100")
                elseif type(s[3]) ~= "number" or s[3] < SP.MIN_RESP or s[3] > SP.MAX_RESP then
                    E(k .. ": respawn outside " .. SP.MIN_RESP .. "-" .. SP.MAX_RESP)
                end
            end
        end
    end
    return errs
end

function SP.Main(argv)
    local opts = { out = "packs-src/spots", files = {} }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--sql" or a == "--out" then
            opts[a:sub(3)] = argv[i + 1]
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
        print("usage: luajit tools/import/spots.lua --sql <ClassicDB.sql> [--out dir] [--check] pack ...")
        return false
    end
    local calibrate = {}
    for _, f in ipairs(Lib.ListDir("packs-src", "lua")) do calibrate[#calibrate + 1] = "packs-src/" .. f end
    local db = assert(CM.Read(opts.sql))
    local fits = CM.Calibrate(HP.Ours(calibrate), db.creatures)
    for m, f in pairs(fits) do
        local size = sizes[m]
        local yd = size and f.rms / 100 * math.max(size[1], size[2]) or math.huge
        if yd > SP.MAX_FIT then
            print(("map %d: fit %.1f yd (over %d), skipped"):format(m, yd, SP.MAX_FIT))
            fits[m] = nil
        end
    end
    local list = CC.LoadAll("packs-src/connectors")
    local idx = #list > 0 and CC.Index(list) or nil
    local exploits = Lib.LoadData("packs-src/known-exploits.lua") or {}
    local questMobs = SP.QuestMobs()
    local ok = true
    for _, f in ipairs(opts.files) do
        local pack = assert(Lib.LoadData(f))
        local targets, log = SP.Pack(pack, db, fits, idx, exploits, questMobs)
        for _, l in ipairs(log) do print(l) end
        if next(targets) then
            local path = opts.out .. "/" .. pack.id .. ".lua"
            local text = SP.Text(pack.id, targets)
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

if args[1] == "--lib" then return SP end
if not SP.Main(args) then os.exit(1) end

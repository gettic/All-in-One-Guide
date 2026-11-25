-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Merges and cleans dev-recorder exports ("AOGREC1 k=v;..." lines from /aog rec export, Dev\Recorder.lua).
-- The text is parsed as data (no code), only the known fields are kept, values are checked, then records
-- are merged per place: the coordinates become the median of all sightings, `seen` = total sightings,
-- `exports` = how many exports saw it. A record needs at least --min sightings (default 2) to be kept;
-- a record whose sightings are spread far apart (more than --spread map percent, default 3) is kept with
-- `spread = true` so a person looks at it. Output: a facts file with src = "rec" on every record.
-- Run (from the repository folder):
--   luajit tools/recmerge.lua [--min 2] [--spread 3] [--out <facts.lua>] <export.txt> [<export.txt> ...]
-- As a library: local RM = assert(loadfile("tools/recmerge.lua"))("--lib")
local args = { ... }
local RM = { MAX_BYTES = 8 * 1024 * 1024, MAX_RECORDS = 200000, GRID = 2 }

RM.FIELDS = { h = "num", v = "text", c = "text", cnt = "num", pg = "text", k = "kind", q = "id", npc = "id", obj = "id",
    ins = "id", from = "id", m = "id", x = "coord", y = "coord", n = "num", it = "ids" }
RM.KINDS = { accept = true, turnin = true, loot = true, gather = true, merchant = true, trainer = true, entrance = true }

local function Unescape(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
local function IsId(v) return type(v) == "number" and v >= 1 and v < 1e7 and v == math.floor(v) end

-- Parses one export text (one or many records, any spacing). Returns records, problems.
function RM.Parse(text)
    local recs, bad = {}, {}
    if type(text) ~= "string" then return recs, { "not text" } end
    if #text > RM.MAX_BYTES then return recs, { ("input over %d bytes"):format(RM.MAX_BYTES) } end
    -- records start at each "AOGREC1 " and run to the next one (values may hold spaces, never ";")
    local marks, p = {}, 1
    while true do
        local s, e = text:find("AOGREC1 ", p, true)
        if not s then break end
        marks[#marks + 1] = { s, e }
        p = e + 1
    end
    for i, se in ipairs(marks) do
        local stop = marks[i + 1] and marks[i + 1][1] - 1 or #text
        local body = text:sub(se[2] + 1, stop):gsub("^%s+", ""):gsub("%s+$", "")
        if body ~= "" then
            local r, ok = {}, true
            for pair in body:gmatch("[^;]+") do
                local k, v = pair:match("^(%w+)=(.*)$")
                local kind = k and RM.FIELDS[k]
                if not kind then
                    ok = false
                    bad[#bad + 1] = "unknown field in: " .. body:sub(1, 60)
                    break
                end
                v = Unescape(v)
                if kind == "num" or kind == "id" or kind == "coord" then
                    local nv = tonumber(v)
                    if not nv or (kind == "id" and not IsId(nv)) or (kind == "coord" and (nv < 0 or nv > 100)) then
                        ok = false
                        bad[#bad + 1] = ("bad %s=%s"):format(k, v)
                        break
                    end
                    r[k] = nv
                elseif kind == "kind" then
                    if not RM.KINDS[v] then ok = false bad[#bad + 1] = "bad kind " .. v break end
                    r[k] = v
                elseif kind == "ids" then
                    local l = {}
                    for id in v:gmatch("[^,]+") do
                        local nv = tonumber(id)
                        if IsId(nv) then l[#l + 1] = nv end
                    end
                    r[k] = l
                else
                    r[k] = v
                end
            end
            if ok and not r.h and not r.k then ok = false bad[#bad + 1] = "record without a kind" end
            if ok and not r.h then
                recs[#recs + 1] = r
                if #recs > RM.MAX_RECORDS then return recs, { "too many records" } end
            end
        end
    end
    return recs, bad
end

local function Key(r)
    local k = table.concat({ r.k, r.q or "", r.npc or "", r.obj or "", r.ins or "", r.m or "" }, ":")
    if r.k == "gather" and r.x then k = k .. ":" .. math.floor(r.x / RM.GRID) .. "," .. math.floor(r.y / RM.GRID) end
    return k
end

local function Median(t)
    if #t == 0 then return nil end
    table.sort(t)
    local mid = math.floor((#t + 1) / 2)
    local v = (#t % 2 == 0) and (t[mid] + t[mid + 1]) / 2 or t[mid]
    return math.floor(v * 100 + 0.5) / 100
end

-- lists = { records from RM.Parse per export }; opts = { min = 2, spread = 3 }.
-- Returns merged records (sorted by key), stats.
function RM.Merge(lists, opts)
    opts = opts or {}
    local minSeen, maxSpread = opts.min or 2, opts.spread or 3
    local by, order = {}, {}
    for e, list in ipairs(lists) do
        for _, r in ipairs(list) do
            local key = Key(r)
            local g = by[key]
            if not g then
                g = { k = r.k, q = r.q, npc = r.npc, obj = r.obj, ins = r.ins, m = r.m, from = r.from, xs = {}, ys = {},
                    seen = 0, exports = {}, it = {}, itSeen = {} }
                by[key] = g
                order[#order + 1] = key
            end
            local n = math.max(1, math.floor(tonumber(r.n) or 1))
            g.seen = g.seen + n
            g.exports[e] = true
            if r.x and r.y then
                g.xs[#g.xs + 1] = r.x
                g.ys[#g.ys + 1] = r.y
            end
            for _, id in ipairs(r.it or {}) do
                if not g.itSeen[id] then g.itSeen[id] = true g.it[#g.it + 1] = id end
            end
        end
    end
    table.sort(order)
    local out, stats = {}, { groups = #order, kept = 0, tooFew = 0, spread = 0 }
    for _, key in ipairs(order) do
        local g = by[key]
        if g.seen < minSeen then
            stats.tooFew = stats.tooFew + 1
        else
            local nx, ny = #g.xs, #g.ys
            local lo, hi = math.huge, -math.huge
            for i = 1, nx do lo = math.min(lo, g.xs[i]) hi = math.max(hi, g.xs[i]) end
            local spread = nx > 1 and (hi - lo) > maxSpread
            lo, hi = math.huge, -math.huge
            for i = 1, ny do lo = math.min(lo, g.ys[i]) hi = math.max(hi, g.ys[i]) end
            spread = spread or (ny > 1 and (hi - lo) > maxSpread)
            local ex = 0
            for _ in pairs(g.exports) do ex = ex + 1 end
            table.sort(g.it)
            local r = { k = g.k, q = g.q, npc = g.npc, obj = g.obj, ins = g.ins, m = g.m, from = g.from,
                x = Median(g.xs), y = Median(g.ys), seen = g.seen, exports = ex, it = #g.it > 0 and g.it or nil,
                spread = spread or nil, src = "rec" }
            out[#out + 1] = r
            stats.kept = stats.kept + 1
            if spread then stats.spread = stats.spread + 1 end
        end
    end
    return out, stats
end

local ORDER = { "k", "q", "npc", "obj", "ins", "from", "m", "x", "y", "seen", "exports", "it", "spread", "src" }
local function Lit(v)
    if type(v) == "string" then return ("%q"):format(v) end
    if type(v) == "table" then
        local p = {}
        for _, x in ipairs(v) do p[#p + 1] = Lit(x) end
        return "{ " .. table.concat(p, ", ") .. " }"
    end
    return tostring(v)
end

-- The facts file text (data only: one table).
function RM.Text(recs, stats)
    local lines = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Recorder facts merged by tools/recmerge.lua from dev-recorder exports (src = \"rec\"). No names.",
        ("-- %d places kept, %d with too few sightings left out, %d spread out (check them)."):format(
            stats.kept, stats.tooFew, stats.spread),
        "return {",
    }
    for _, r in ipairs(recs) do
        local p = {}
        for _, k in ipairs(ORDER) do
            if r[k] ~= nil then p[#p + 1] = k .. " = " .. Lit(r[k]) end
        end
        lines[#lines + 1] = "    { " .. table.concat(p, ", ") .. " },"
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

function RM.Main(a)
    local opts, files, out = {}, {}, nil
    local i = 1
    while i <= #a do
        local k = a[i]
        if k == "--min" then opts.min = tonumber(a[i + 1]) i = i + 1
        elseif k == "--spread" then opts.spread = tonumber(a[i + 1]) i = i + 1
        elseif k == "--out" then out = a[i + 1] i = i + 1
        else files[#files + 1] = k end
        i = i + 1
    end
    if #files == 0 then print("usage: luajit tools/recmerge.lua [--min 2] [--spread 3] [--out <file>] <export.txt> ...") return false end
    local lists, problems = {}, 0
    for _, f in ipairs(files) do
        local fh = io.open(f, "rb")
        if not fh then print("cannot read " .. f) return false end
        local recs, bad = RM.Parse(fh:read("*a"))
        fh:close()
        for _, b in ipairs(bad) do print("SKIP " .. f .. ": " .. b) end
        problems = problems + #bad
        lists[#lists + 1] = recs
    end
    local merged, stats = RM.Merge(lists, opts)
    local text = RM.Text(merged, stats)
    if out then
        local fh = assert(io.open(out, "wb"))
        fh:write(text)
        fh:close()
    else
        io.write(text)
    end
    print(("recmerge: %d exports, %d places kept, %d too few sightings, %d spread, %d skipped lines"):format(
        #lists, stats.kept, stats.tooFew, stats.spread, problems))
    return true
end

if args[1] == "--lib" then return RM end
if not RM.Main(args) then os.exit(1) end

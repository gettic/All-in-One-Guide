-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Merges and cleans dev-recorder exports ("AOGREC1 k=v;..." lines from /aog rec export, Dev\Recorder.lua).
-- The text is parsed as data (no code), only the known fields are kept, values are checked, then records
-- are merged per place: the coordinates become the median of all sightings, `seen` = total sightings,
-- `exports` = how many exports saw it. A record needs at least --min sightings (default 2) to be kept;
-- a record whose sightings are spread far apart (more than --spread map percent, default 3) is kept with
-- `spread = true` so a person looks at it. Output: a facts file with src = "rec" on every record.
-- v0.3: also the players' game data pages ("AOGD1 ...", Data\Gather.lua): RM.ParseD1 / RM.MergeD1 / RM.TextD1 (checksum,
-- duplicate page ids, field allowlist, at least --min separate pages per fact (default 3), median +- 3 MAD outlier cut,
-- quest XP normalised by the level gap, minimum samples for drop / coin / skill-up rates; src = "gather").
-- Run (from the repository folder):
--   luajit tools/recmerge.lua [--min 2] [--spread 3] [--out <facts.lua>] <export.txt> [<export.txt> ...]
--   (a file that starts with game data pages is merged as game data)
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

-- ------------------------------------------------------------------ v0.3 game data pages ("AOGD1 ...")
-- Pages from Data\Gather.lua (sent by the Addon Manager). Each page: a header (rid = a random page id, h=1, addon
-- version, client build, faction, class, count), records, then a checksum record. A page whose checksum or format
-- fails is dropped whole; a page id seen before (a duplicate send) is skipped. Values are only ids, numbers, map
-- cells and comma lists of ids: no names ever (a page with anything else fails the field check).
RM.D1_FIELDS = { rid = "text", h = "num", v = "text", b = "text", fac = "text", cls = "text", race = "text",
    realm = "name", loc = "text", day = "day", cnt = "num", k = "kind",
    q = "id", npc = "id", obj = "id", ins = "id", from = "id", m = "id", x = "coord", y = "coord", c = "cell", n = "num",
    xp = "num", mo = "num", pl = "num", ql = "num", it = "id", loot = "num", got = "num", cu = "num", sh = "num",
    gray = "num", cloth = "num", herb = "num", ore = "num", pk = "text", s = "text", t = "num", fn = "id", tn = "id",
    sec = "num", lo = "num", hi = "num", cl = "text", fa = "id", gain = "num", sp = "id", sk = "id", lv = "num", dif = "num",
    tries = "num", ups = "num", sv = "text", rc = "text", sup = "text", min = "num", boss = "text", qs = "text", pz = "num",
    pn = "num", dd = "num", gs = "num", gx = "num", rt = "text", gph = "num", ck = "text",
    -- rev 6 (Data\GatherMore.lua)
    e = "num", st = "num", skp = "num", und = "num", nd = "num", bk = "num", spc = "num", ns = "num", hs = "num",
    fl = "num", wk = "num", hr = "num", mt = "num", sw = "num", ft = "num", dev = "num", pct = "num", rd = "num",
    kv = "text", ms = "num", rf = "num", uk = "text", on = "num", fe = "text", msg = "name", at = "text", stk = "text",
    tt = "name", nq = "text", oi = "num", why = "text", ch = "text", sz = "name", ct = "name", cf = "name", ml = "num",
    hc = "num", cn = "num", cb = "num", eq = "text", stt = "text", am = "num", qcu = "num", vcu = "num", dcu = "num",
    mcu = "num", gv = "num", sks = "text" }
RM.D1_KINDS = { accept = true, turnin = true, qxp = true, offer = true, drop = true, camp = true, coin = true, sell = true,
    farm = true, gather = true, merchant = true, vend = true, trainer = true, train = true, inn = true, fm = true, fly = true,
    entrance = true, step = true, gph = true, craft = true, gskill = true, mlvl = true, repq = true, repk = true, repo = true,
    dun = true,
    -- rev 6
    sact = true, leg = true, trav = true, mv = true, rest = true, mount = true, spec = true, set = true, guide = true,
    perf = true, use = true, err = true, miss = true, chain = true, pmiss = true, qstart = true, rdrop = true, grp = true,
    abandon = true, qfail = true, qtime = true, obj = true, ostk = true, death = true, crun = true, gy = true, ctype = true,
    tap = true, pull = true, ttk = true, cast = true, eat = true, rew = true, gear = true, stat = true, bagfull = true,
    repair = true, fpl = true, expl = true, ammo = true, earn = true }
RM.TEXT_OK = "^[%w %.,:_/%+%(%)'!%?%-]*$"   -- what the strict escaping leaves (after unescaping: no separators)

function RM.Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return ("%04x%04x"):format(b, a)
end

local function D1Record(body, bad)
    local r = {}
    for pair in body:gmatch("[^;]+") do
        local k, v = pair:match("^(%w+)=(.*)$")
        local kind = k and RM.D1_FIELDS[k]
        if not kind then bad[#bad + 1] = "unknown field in: " .. body:sub(1, 60) return nil end
        v = Unescape(v)
        if kind == "num" or kind == "id" or kind == "coord" then
            local nv = tonumber(v)
            if not nv or (kind == "id" and not IsId(nv)) or (kind == "coord" and (nv < 0 or nv > 100)) then
                bad[#bad + 1] = ("bad %s=%s"):format(k, v)
                return nil
            end
            r[k] = nv
        elseif kind == "kind" then
            if not RM.D1_KINDS[v] then bad[#bad + 1] = "bad kind " .. v return nil end
            r[k] = v
        elseif kind == "day" then
            if not v:match("^%d%d%d%d%-%d%d%-%d%d$") then bad[#bad + 1] = "bad day " .. v return nil end
            r[k] = v
        elseif kind == "name" then
            -- a realm name: letters in any language (UTF-8), no control signs or separators
            if #v > 64 or v:find("[%c;=|]") then bad[#bad + 1] = "bad text in " .. k return nil end
            r[k] = v
        elseif kind == "cell" then
            if not v:match("^%d+,%d+$") then bad[#bad + 1] = "bad cell " .. v return nil end
            r[k] = v
        else
            if #v > 1600 or not v:find(RM.TEXT_OK) then bad[#bad + 1] = "bad text in " .. k return nil end
            r[k] = v
        end
    end
    return r
end

-- Parses one text with any number of pages (one per line or run together). Returns pages = { { rid, head, recs } },
-- problems. A page is kept only when its checksum matches and every record passes.
function RM.ParseD1(text)
    local pages, bad = {}, {}
    if type(text) ~= "string" then return pages, { "not text" } end
    if #text > RM.MAX_BYTES then return pages, { ("input over %d bytes"):format(RM.MAX_BYTES) } end
    for page in text:gmatch("AOGD1 rid=.-AOGD1 ck=%x%x%x%x%x%x%x%x") do
        local core, ck = page:match("^(.*) AOGD1 ck=(%x%x%x%x%x%x%x%x)$")
        if not core or RM.Adler32(core) ~= ck then
            bad[#bad + 1] = "checksum: " .. page:sub(1, 40)
        else
            -- the records: split at each " AOGD1 " (the first part is the header)
            local parts, ok, rest, pos = {}, true, core:sub(7), 1
            while true do
                local s, e = rest:find(" AOGD1 ", pos, true)
                if not s then parts[#parts + 1] = rest:sub(pos) break end
                parts[#parts + 1] = rest:sub(pos, s - 1)
                pos = e + 1
            end
            local head, recs = nil, {}
            for i, body in ipairs(parts) do
                local r = D1Record(body, bad)
                if not r then ok = false break end
                if i == 1 then
                    if not (r.rid and r.h == 1) then bad[#bad + 1] = "no header" ok = false break end
                    head = r
                elseif not r.k then
                    bad[#bad + 1] = "record without a kind" ok = false break
                else
                    recs[#recs + 1] = r
                end
            end
            if ok and head then pages[#pages + 1] = { rid = head.rid, head = head, recs = recs } end
        end
    end
    return pages, bad
end

-- classic quest XP for a player above the quest's level (full up to 5 levels above, then 80/60/40/20/10 %)
function RM.XPFactor(pl, ql)
    local d = pl - ql
    if d <= 5 then return 1 end
    return ({ [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 })[d] or 0.1
end

local function Med(t)
    if #t == 0 then return nil end
    local s = {}
    for i, v in ipairs(t) do s[i] = v end
    table.sort(s)
    local mid = math.floor((#s + 1) / 2)
    return (#s % 2 == 0) and (s[mid] + s[mid + 1]) / 2 or s[mid]
end
-- values inside median +- 3 MAD (all of them when MAD is 0)
local function Inliers(t)
    local m = Med(t)
    if not m then return t end
    local dev = {}
    for i, v in ipairs(t) do dev[i] = math.abs(v - m) end
    local mad = Med(dev)
    if not mad or mad == 0 then
        local out = {}
        for _, v in ipairs(t) do if v == m then out[#out + 1] = v end end
        return #out * 2 >= #t and out or t
    end
    local out = {}
    for _, v in ipairs(t) do if math.abs(v - m) <= 3 * mad then out[#out + 1] = v end end
    return out
end
RM.Inliers = Inliers
local function Mode(t)
    local c, best, bn = {}, nil, 0
    for _, v in ipairs(t) do
        c[v] = (c[v] or 0) + 1
        if c[v] > bn or (c[v] == bn and v < best) then best, bn = v, c[v] end
    end
    return best
end
local function R2(v) return v and math.floor(v * 100 + 0.5) / 100 or nil end

-- The merge key per kind (which records are the same fact).
local KEYS = {
    accept = { "q", "npc", "obj", "from", "m" }, turnin = { "q", "npc", "obj", "from", "m" }, qxp = { "q" }, offer = { "q" },
    drop = { "npc", "it" }, camp = { "npc", "m" }, coin = { "npc" }, sell = { "it" }, farm = { "npc", "m" },
    gather = { "obj", "m" }, merchant = { "npc", "m" }, vend = { "npc" }, trainer = { "npc", "m" }, train = { "npc" },
    inn = { "npc", "m" }, fm = { "npc", "fn" }, fly = { "fn", "tn" }, entrance = { "ins", "m" }, step = { "pk", "s" },
    gph = { "rt" }, craft = { "sp", "lv" }, gskill = { "obj", "npc", "sk", "lv" }, mlvl = { "npc", "m", "c" },
    repq = { "q", "fa" }, repk = { "npc", "fa" }, repo = { "fa" }, dun = { "ins" },
    -- rev 6
    sact = { "pk", "s" }, leg = { "pk", "s" }, trav = { "pk", "s" }, mv = { "pk", "s" }, rest = { "pl" },
    mount = { "pl", "rd" }, spec = { "pl", "spc" }, set = { "kv" }, guide = { "pk" }, perf = {}, use = { "uk", "on" },
    err = { "msg", "at" }, miss = { "npc", "q", "tt" }, chain = { "q", "npc" }, pmiss = { "q", "npc" },
    qstart = { "it", "npc", "obj", "q" }, rdrop = { "it", "npc", "obj" }, grp = { "q", "npc", "gs" }, abandon = { "q" },
    qfail = { "q", "why" }, qtime = { "q" }, obj = { "q", "oi" }, ostk = { "q", "s" }, death = { "m", "c", "npc" },
    crun = { "m" }, gy = { "m", "c" }, ctype = { "npc" }, tap = { "npc", "m" }, pull = { "npc", "m" }, ttk = { "npc", "pl" },
    cast = { "sp", "pl" }, eat = { "pl" }, rew = { "q", "it" }, gear = { "pl" }, stat = { "why", "pl" },
    bagfull = { "pk", "s" }, repair = { "pl" }, fpl = { "fn" }, expl = { "m", "sz" }, ammo = { "pl" }, earn = { "pl" },
}
-- rev 6: how each new kind merges (sum = add up, mode = most common, med = median, lo / hi = smallest / largest,
-- per = median of field / n per record). What it is for is in plans\data-gathering\plan.md (rev 6).
RM.D1_MERGE = {
    sact = { sum = { "skp", "und", "nd", "bk" } }, trav = { sum = { "hs", "fl", "wk" } },
    leg = { sum = { "ns", "xp", "sec", "dd" }, lo = { "lo" }, hi = { "hi" }, mode = { "spc" } },
    mv = { sum = { "hr", "mt", "sw", "ft", "dev" }, mode = { "c" } }, rest = { med = { "pct" } },
    use = { sum = {} }, err = { mode = { "stk", "fe" } }, miss = { mode = { "ql", "pk" } }, chain = { mode = { "nq" } },
    pmiss = { lo = { "pl" } }, abandon = { med = { "pl" }, mode = { "gs" } }, qtime = { per = { "min" } },
    obj = { med = { "sec" } }, ostk = { sum = { "min" } }, death = { med = { "pl" }, mode = { "ml", "hc" } },
    crun = { per = { "sec" } }, ctype = { mode = { "ct", "cf" } }, pull = { mode = { "ml" } },
    ttk = { per = { "sec" }, mode = { "ml" } }, cast = { sum = { "cn", "cb" } }, eat = { per = { "sec" } },
    rew = { mode = { "ch" } }, gear = { mode = { "eq" } }, stat = { mode = { "stt" } }, fpl = { lo = { "pl" } },
    expl = { mode = { "xp" } }, ammo = { med = { "am" } }, perf = { med = { "ms", "rf" } },
    earn = { sum = { "qcu", "vcu", "dcu", "mcu", "gv", "min" } }, camp = { sum = { "sec" } },
}
local function D1Key(r)
    local p = { r.k }
    for _, f in ipairs(KEYS[r.k] or {}) do p[#p + 1] = tostring(r[f] or "") end
    if r.k == "dun" then p[#p + 1] = math.floor((r.pl or 0) / 5) .. "/" .. ((r.gs or 1) >= 4 and "g" or "s") end
    return table.concat(p, ":")
end

-- pages_list = { pages from RM.ParseD1 per file }; opts = { batches = 3, minLoots = 50, coinLoots = 100, tries = 30 }.
-- Returns facts (sorted by key; src = "gather"), stats.
function RM.MergeD1(pagesList, opts)
    opts = opts or {}
    local minB, minLoot, coinLoot, minTries = opts.batches or 3, opts.minLoots or 50, opts.coinLoots or 100, opts.tries or 30
    local seenRid, groups, order, stats = {}, {}, {}, { pages = 0, dupes = 0, groups = 0, kept = 0, tooFew = 0, outliers = 0 }
    for _, pages in ipairs(pagesList) do
        for _, pg in ipairs(pages) do
            if seenRid[pg.rid] then
                stats.dupes = stats.dupes + 1
            else
                seenRid[pg.rid] = true
                stats.pages = stats.pages + 1
                for _, r in ipairs(pg.recs) do
                    local key = D1Key(r)
                    local g = groups[key]
                    if not g then
                        g = { key = key, k = r.k, recs = {}, batches = {} }
                        groups[key] = g
                        order[#order + 1] = key
                    end
                    g.recs[#g.recs + 1] = r
                    g.batches[pg.rid] = true
                end
            end
        end
    end
    table.sort(order)
    stats.groups = #order
    local out = {}
    for _, key in ipairs(order) do
        local g = groups[key]
        local nb = 0
        for _ in pairs(g.batches) do nb = nb + 1 end
        local first = g.recs[1]
        local f = { k = g.k, batches = nb, src = "gather" }
        for _, fld in ipairs(KEYS[g.k] or {}) do f[fld] = first[fld] end
        local function sum(field) local s = 0 for _, r in ipairs(g.recs) do s = s + (r[field] or 0) end return s end
        local function list(field) local t = {} for _, r in ipairs(g.recs) do if r[field] then t[#t + 1] = r[field] end end return t end
        local keep = nb >= minB
        if g.k == "qxp" then
            local base = {}
            for _, r in ipairs(g.recs) do
                if r.xp and r.pl and r.ql then base[#base + 1] = r.xp / RM.XPFactor(r.pl, r.ql) end
            end
            local inl = Inliers(base)
            stats.outliers = stats.outliers + (#base - #inl)
            f.xp = inl[1] and math.floor(Med(inl) + 0.5) or nil
            f.mo = Mode(list("mo"))
            f.ql = Mode(list("ql"))
            keep = keep and f.xp ~= nil
        elseif g.k == "offer" then
            local t = list("pl")
            table.sort(t)
            f.pl = t[1]
        elseif g.k == "drop" then
            f.loot, f.got = sum("loot"), sum("got")
            keep = keep and f.loot >= minLoot
            if f.loot > 0 then
                local p = f.got / f.loot
                f.rate = R2(p)
                f.err = R2(1.96 * math.sqrt(p * (1 - p) / f.loot))   -- a rough 95 % range
            end
        elseif g.k == "coin" then
            local avg, loots = {}, 0
            for _, r in ipairs(g.recs) do
                if (r.n or 0) > 0 then avg[#avg + 1] = (r.cu or 0) / r.n loots = loots + r.n end
            end
            f.loots, f.cu = loots, avg[1] and math.floor(Med(avg) + 0.5) or nil
            keep = keep and loots >= coinLoot
        elseif g.k == "sell" then
            f.cu = Mode(list("cu"))
        elseif g.k == "farm" then
            for _, fld in ipairs({ "loot", "gray", "cloth", "herb", "ore", "cu" }) do f[fld] = sum(fld) end
        elseif g.k == "craft" or g.k == "gskill" then
            f.tries, f.ups = sum("tries"), sum("ups")
            f.dif = Mode(list("dif"))
            keep = keep and f.tries >= minTries
            if f.tries > 0 then f.rate = R2(f.ups / f.tries) end
        elseif g.k == "mlvl" then
            local lo, hi = list("lo"), list("hi")
            table.sort(lo)
            table.sort(hi)
            f.lo, f.hi, f.cl = lo[1], hi[#hi], Mode(list("cl"))
        elseif g.k == "repq" or g.k == "repo" then
            f.gain = Mode(list("gain"))
        elseif g.k == "repk" then
            local per = {}
            for _, r in ipairs(g.recs) do if (r.n or 0) > 0 then per[#per + 1] = r.gain / r.n end end
            f.gain = per[1] and R2(Med(per)) or nil
        elseif g.k == "step" then
            local per = {}
            for _, r in ipairs(g.recs) do if (r.n or 0) > 0 then per[#per + 1] = r.t / r.n end end
            local inl = Inliers(per)
            stats.outliers = stats.outliers + (#per - #inl)
            f.t = inl[1] and math.floor(Med(inl) + 0.5) or nil
        elseif g.k == "fly" then
            local per = {}
            for _, r in ipairs(g.recs) do if (r.n or 0) > 0 then per[#per + 1] = r.sec / r.n end end
            f.sec = per[1] and math.floor(Med(Inliers(per)) + 0.5) or nil
        elseif g.k == "gph" then
            local w, s = 0, 0
            for _, r in ipairs(g.recs) do w = w + (r.min or 0) s = s + (r.gph or 0) * (r.min or 0) end
            f.gph, f.min = w > 0 and R2(s / w) or nil, w
        elseif g.k == "dun" then
            local clean = {}
            for _, r in ipairs(g.recs) do if (r.pn or 0) == 0 then clean[#clean + 1] = r end end
            local mins, xp, cu = {}, {}, {}
            for _, r in ipairs(clean) do mins[#mins + 1] = r.min xp[#xp + 1] = r.xp cu[#cu + 1] = r.cu end
            f.pl, f.gs = first.pl, first.gs
            f.runs, f.clean = #g.recs, #clean
            f.min, f.xp, f.cu = Med(mins), Med(xp), Med(cu)
            -- full clear: the run(s) that killed the most distinct bosses set the list
            local most = 0
            for _, r in ipairs(g.recs) do
                local n = 0
                for _ in tostring(r.boss or ""):gmatch("[^,]+") do n = n + 1 end
                most = math.max(most, n)
            end
            f.bosses = most
        elseif g.k == "train" or g.k == "vend" then
            for _, fld in ipairs({ "sv", "rc", "sup" }) do f[fld] = Mode(list(fld)) end
        end
        local how = RM.D1_MERGE[g.k]
        if how then
            f.n = sum("n")
            for _, fld in ipairs(how.sum or {}) do f[fld] = sum(fld) end
            for _, fld in ipairs(how.mode or {}) do f[fld] = Mode(list(fld)) end
            for _, fld in ipairs(how.med or {}) do f[fld] = Med(list(fld)) end
            for _, fld in ipairs(how.lo or {}) do local t = list(fld) table.sort(t) f[fld] = t[1] end
            for _, fld in ipairs(how.hi or {}) do local t = list(fld) table.sort(t) f[fld] = t[#t] end
            for _, fld in ipairs(how.per or {}) do
                local per = {}
                for _, r in ipairs(g.recs) do if (r.n or 0) > 0 and r[fld] then per[#per + 1] = r[fld] / r.n end end
                f[fld] = per[1] and R2(Med(Inliers(per))) or nil
            end
            if g.k == "leg" and (f.sec or 0) > 0 then f.xph = math.floor(f.xp / f.sec * 3600 / 100 + 0.5) * 100 end
            if g.k == "earn" and (f.min or 0) > 0 then
                for _, fld in ipairs({ "qcu", "vcu", "dcu", "mcu", "gv" }) do f[fld .. "h"] = math.floor(f[fld] / f.min * 60 + 0.5) end
            end
        end
        if g.k == "step" then f.e, f.st = Mode(list("e")), sum("st") end
        -- places: the median of the spots (spots far from it are left out)
        local xs, ys = list("x"), list("y")
        if #xs > 0 then
            local ix, iy = Inliers(xs), Inliers(ys)
            stats.outliers = stats.outliers + (#xs - #ix)
            f.x, f.y = R2(Med(ix)), R2(Med(iy))
        end
        if keep then
            out[#out + 1] = f
            stats.kept = stats.kept + 1
        else
            stats.tooFew = stats.tooFew + 1
        end
    end
    return out, stats
end

local D1_ORDER = { "k", "q", "npc", "obj", "ins", "from", "it", "sp", "sk", "fa", "fn", "tn", "pk", "s", "rt", "m", "c", "x",
    "y", "lv", "pl", "gs", "ql", "xp", "mo", "loot", "got", "rate", "err", "loots", "cu", "gray", "cloth", "herb", "ore",
    "tries", "ups", "dif", "lo", "hi", "cl", "gain", "t", "sec", "gph", "min", "runs", "clean", "bosses", "sv", "rc", "sup",
    "e", "st", "skp", "und", "nd", "bk", "spc", "ns", "xph", "hs", "fl", "wk", "hr", "mt", "sw", "ft", "dev", "pct", "rd",
    "kv", "ms", "rf", "uk", "on", "fe", "msg", "at", "stk", "tt", "nq", "oi", "why", "ch", "sz", "ct", "cf", "ml", "hc",
    "cn", "cb", "eq", "stt", "am", "qcu", "vcu", "dcu", "mcu", "gv", "qcuh", "vcuh", "dcuh", "mcuh", "gvh", "sks", "n",
    "batches", "src" }
function RM.TextD1(recs, stats)
    local lines = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Game data contributed by players (Data\\Gather.lua pages), merged by tools/recmerge.lua (src = \"gather\").",
        "-- No names. Facts need several separate pages to agree; outliers are left out.",
        ("-- %d pages (%d duplicate sends skipped), %d facts kept, %d with too little data, %d outlying values left out."):format(
            stats.pages, stats.dupes, stats.kept, stats.tooFew, stats.outliers),
        "return {",
    }
    for _, r in ipairs(recs) do
        local p = {}
        for _, k in ipairs(D1_ORDER) do if r[k] ~= nil then p[#p + 1] = k .. " = " .. Lit(r[k]) end end
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
    -- v0.3: game data pages (AOGD1) have their own merge
    local texts = {}
    for _, f in ipairs(files) do
        local fh = io.open(f, "rb")
        if not fh then print("cannot read " .. f) return false end
        texts[#texts + 1] = fh:read("*a")
        fh:close()
    end
    if texts[1] and texts[1]:find("AOGD1 rid=", 1, true) then
        local all, problems = {}, 0
        for i, t in ipairs(texts) do
            local pages, bad = RM.ParseD1(t)
            for _, b in ipairs(bad) do print("SKIP " .. files[i] .. ": " .. b) end
            problems = problems + #bad
            all[#all + 1] = pages
        end
        local merged, stats = RM.MergeD1(all, { batches = opts.min })
        local text = RM.TextD1(merged, stats)
        if out then
            local fh = assert(io.open(out, "wb"))
            fh:write(text)
            fh:close()
        else
            io.write(text)
        end
        print(("recmerge (game data): %d pages, %d duplicates, %d facts kept, %d too little data, %d outliers, %d skipped"):format(
            stats.pages, stats.dupes, stats.kept, stats.tooFew, stats.outliers, problems))
        return true
    end
    local lists, problems = {}, 0
    for i, f in ipairs(files) do
        local recs, bad = RM.Parse(texts[i])
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

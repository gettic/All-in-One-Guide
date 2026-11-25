-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Offline importer (v0.2 M6): reads another project's data dump AS DATA ONLY (tools/import/luadata.lua:
-- no loadfile / loadstring on the input, size / depth / count caps), keeps only records whose source licence
-- and provenance allow it (tools/import/provenance.lua), and writes our facts file with a source tag on every
-- record, the source's exact SPDX id pinned, and a data manifest (source, pinned version, counts, dataVersion).
-- Names (quest titles, NPC names) are never written: ids, levels, givers, pre-quests and spawn spots only.
--
-- Run (from the repository folder):
--   luajit tools/import/import.lua --in <dump> --out <facts.lua> [--format questie|generic]
--          [--manifest <file>] [--no-consent <list file>] [--provenance <file>] [--max-bytes N] [--date YYYY-MM]
-- --provenance: the source's own provenance file (consent / no-consent / reserved / released lists, read as
-- data, provenance.lua P.LoadProvenance). Questie records are kept only with positive provenance (fail closed).
-- Exit code 1 when the source or the dump is refused.
-- As a library: local IM = assert(loadfile("tools/import/import.lua"))("--lib", "<tools/import folder>")
--
-- Formats: "generic" = { meta = { source, version, spdx }, records = { { kind = "quest" | "npc" | "object",
-- id, level, minLevel, pre, start, finish, spawns = { { map, x, y } }, prov = { from, by, consent,
-- reserved } } } }; "questie" = a Questie-shaped dump read by tools/import/questie.lua (sample layout,
-- adapt to the real one after the download yes).
local args = { ... }
local here = (args[1] == "--lib" and args[2]) or (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tools/import"
local IM = { VERSION = 1 }

local function Load(name, ...) return assert(loadfile(here .. "/" .. name))(...) end
local LD = Load("luadata.lua")
local P = Load("provenance.lua")
local Q = Load("questie.lua", LD)
IM.LD, IM.P, IM.Q = LD, P, Q

local function IsId(v) return type(v) == "number" and v >= 1 and v < 1e7 and v == math.floor(v) end

-- Adler-32 without bit operations (same idea as the addon's Fm.Adler32), 8 hex digits.
local function Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return ("%08x"):format(b * 65536 + a)
end
IM.Adler32 = Adler32

-- Shape checks for one plain record (after the reader); returns a clean copy or nil.
local function Clean(r, tag, spdx, seen)
    if type(r) ~= "table" or not IsId(r.id) then return nil end
    local out = { src = tag, spdx = spdx, seen = seen }
    if r.kind == "quest" then
        if type(r.level) == "number" and r.level >= 1 and r.level <= 80 then out.level = r.level end
        if type(r.minLevel) == "number" and r.minLevel >= 1 and r.minLevel <= 80 then out.minLevel = r.minLevel end
        if type(r.pre) == "table" then
            local pre = {}
            for _, id in ipairs(r.pre) do if IsId(id) then pre[#pre + 1] = id end end
            if #pre > 0 then out.pre = pre end
        end
        for _, side in ipairs({ "start", "finish" }) do
            local g = r[side]
            if type(g) == "table" then
                local c = {}
                for _, k in ipairs({ "npc", "obj", "item" }) do
                    if type(g[k]) == "table" then
                        local l = {}
                        for _, id in ipairs(g[k]) do if IsId(id) then l[#l + 1] = id end end
                        if #l > 0 then c[k] = l end
                    end
                end
                if next(c) then out[side] = c end
            end
        end
    elseif r.kind == "npc" or r.kind == "object" then
        local sp = {}
        for _, p in ipairs(type(r.spawns) == "table" and r.spawns or {}) do
            if type(p) == "table" and IsId(p[1]) and type(p[2]) == "number" and type(p[3]) == "number"
                and p[2] >= 0 and p[2] <= 100 and p[3] >= 0 and p[3] <= 100 then
                sp[#sp + 1] = { p[1], p[2], p[3] }
            end
        end
        out.spawns = sp
    else
        return nil
    end
    return out
end

-- opts = { text = dump text, format = "questie" | "generic", noConsent = { names }, maxBytes, date }
-- Returns result = { meta, facts = { quests, npcs, objects }, manifest } or nil, reason.
function IM.Run(opts)
    local parseOpts = { maxBytes = opts.maxBytes, maxDepth = opts.maxDepth, maxItems = opts.maxItems }
    local dump, err = LD.Parse(opts.text, parseOpts)
    if dump == nil then return nil, "refused: " .. tostring(err) end
    if type(dump) ~= "table" then return nil, "refused: the dump is not a table" end
    local meta, recs, stats
    if (opts.format or "generic") == "questie" then
        meta, recs, stats = Q.Read(dump, parseOpts)
        if not meta and type(recs) == "string" then return nil, "refused: " .. recs end
        if not recs then return nil, "refused: " .. tostring(meta) end
    else
        meta, recs, stats = dump.meta, dump.records, {}
        if type(recs) ~= "table" then return nil, "refused: no records list" end
    end
    local rules = {}
    for k, v in pairs(P.RULES) do rules[k] = v end
    rules.noConsent, rules.consent = {}, {}
    for k, v in pairs(P.RULES.noConsent) do rules.noConsent[k] = v end
    for k, v in pairs(P.RULES.consent) do rules.consent[k] = v end
    for _, name in ipairs(opts.noConsent or {}) do rules.noConsent[name:lower()] = true end
    rules.reserved = { quest = {}, npc = {}, object = {} }
    rules.released = { quest = {}, npc = {}, object = {} }
    -- the source's own provenance lists (opts.provenance = text of its provenance file, read as data)
    if opts.provenance then
        local lists, perr = P.LoadProvenance(opts.provenance, LD, parseOpts)
        if not lists then return nil, "refused: provenance file: " .. tostring(perr) end
        for k in pairs(lists.consent) do rules.consent[k] = true end
        for k in pairs(lists.noConsent) do rules.noConsent[k] = true end
        for _, part in ipairs({ "reserved", "released" }) do
            for kind, ids in pairs(lists[part]) do
                for id in pairs(ids) do rules[part][kind][id] = true end
            end
        end
    end
    local ok, why = P.Source(meta, rules)
    if not ok then return nil, "refused: " .. why end
    local tag = P.Tag(meta, rules)
    local spdx = meta.spdx
    local facts = { quests = {}, npcs = {}, objects = {} }
    local kept, dropped = 0, { wowhead = 0, consent = 0, reserved = 0, noprov = 0, invalid = 0, zone = stats.zone or 0 }
    dropped.invalid = stats.invalid or 0
    local into = { quest = facts.quests, npc = facts.npcs, object = facts.objects }
    for _, r in ipairs(recs) do
        local keep, bucket = P.Record(r, rules, tag)
        if not keep then
            dropped[bucket] = (dropped[bucket] or 0) + 1
        else
            local c = type(r) == "table" and Clean(r, tag, spdx, opts.date) or nil
            if not c or into[r.kind][r.id] then
                dropped.invalid = dropped.invalid + 1
            else
                into[r.kind][r.id] = c
                kept = kept + 1
            end
        end
    end
    local body = LD.Write(facts)
    local manifest = {
        source = tostring(meta.source), version = tostring(meta.version), spdx = spdx, tag = tag,
        importer = IM.VERSION, kept = kept, dropped = dropped,
        counts = { quests = 0, npcs = 0, objects = 0 },
        dataVersion = tostring(meta.source) .. "@" .. tostring(meta.version) .. "#" .. Adler32(body),
    }
    for kind, t in pairs(facts) do for _ in pairs(t) do manifest.counts[kind] = manifest.counts[kind] + 1 end end
    return { meta = meta, facts = facts, manifest = manifest }
end

-- The facts file text: SPDX = the source's pinned id; loadable as data (an empty environment is enough).
function IM.FactsText(res)
    local m = res.manifest
    local t = { manifest = m, quests = res.facts.quests, npcs = res.facts.npcs, objects = res.facts.objects }
    return table.concat({
        "-- SPDX-License-Identifier: " .. m.spdx,
        ("-- Contains data from %s %s (%s); kept records only, see the manifest."):format(m.source, m.version, m.spdx),
        "-- Generated by tools/import/import.lua; do not edit by hand. No names: ids and spots only.",
        "return " .. LD.Write(t), "",
    }, "\n")
end

function IM.ManifestText(res)
    return table.concat({
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Data manifest written by tools/import/import.lua.",
        "return " .. LD.Write(res.manifest), "",
    }, "\n")
end

local function ReadFile(p)
    local fh = io.open(p, "rb")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end
local function WriteFile(p, s)
    local fh = assert(io.open(p, "wb"))
    fh:write(s)
    fh:close()
end

function IM.Main(a)
    local o = { noConsent = {} }
    local i = 1
    while i <= #a do
        local k, v = a[i], a[i + 1]
        if k == "--in" then o.input = v
        elseif k == "--out" then o.out = v
        elseif k == "--manifest" then o.manifest = v
        elseif k == "--format" then o.format = v
        elseif k == "--max-bytes" then o.maxBytes = tonumber(v)
        elseif k == "--date" then o.date = v
        elseif k == "--provenance" then
            o.provenance = ReadFile(v)
            if not o.provenance then print("cannot read " .. tostring(v)) return false end
        elseif k == "--no-consent" then
            for line in (ReadFile(v) or ""):gmatch("[^\r\n]+") do
                line = line:gsub("^%s+", ""):gsub("%s+$", "")
                if line ~= "" and not line:find("^#") then o.noConsent[#o.noConsent + 1] = line end
            end
        else
            print("unknown option " .. tostring(k))
            return false
        end
        i = i + 2
    end
    if not (o.input and o.out) then
        print("usage: luajit tools/import/import.lua --in <dump> --out <facts.lua> [--format questie|generic]")
        return false
    end
    local text = ReadFile(o.input)
    if not text then print("cannot read " .. o.input) return false end
    o.text = text
    local res, err = IM.Run(o)
    if not res then print(err) return false end
    WriteFile(o.out, IM.FactsText(res))
    WriteFile(o.manifest or (o.out:gsub("%.lua$", "") .. ".manifest.lua"), IM.ManifestText(res))
    local d = res.manifest.dropped
    print(("import: kept %d (quests %d, npcs %d, objects %d); dropped wowhead %d, consent %d, reserved %d, no provenance %d, invalid %d, unknown zone %d; %s")
        :format(res.manifest.kept, res.manifest.counts.quests, res.manifest.counts.npcs, res.manifest.counts.objects,
            d.wowhead, d.consent, d.reserved, d.noprov, d.invalid, d.zone, res.manifest.dataVersion))
    return true
end

if args[1] == "--lib" then return IM end
if not IM.Main(args) then os.exit(1) end

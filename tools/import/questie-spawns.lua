-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Builds plans\tools\data\npc-spawns.lua (LOCAL ONLY, gitignored: not published while the QuestieDB licence ruling is open; for packcheck's NPC distance check) from a LOCAL QuestieDB copy (GPL-3.0,
-- see its LICENSE.md). Reads only the NPCs that our packs' talk steps use (packcheck PC.TALK: accept, turn-in,
-- train, learn, set hearth, get flight path), and keeps only numbers: NPC id, uiMapID, x, y. Names, texts and
-- every other field are never read. Nothing is downloaded: point it at a QuestieDB folder that is already there.
--
-- QuestieDB "baked" layout (QuestieDB_Forever.toc, contract 4): one metadata line per NPC field,
--   ## X-Npc-<id>-7: <base64 of CBOR>   field 7 = spawns = { [areaId] = { { x, y }, ... } }
-- areaId -> uiMapID comes from support\Forever\Zones\areaIdToUiMapId.lua (its override table wins).
--
-- Run (from the repository folder):
--   luajit tools/import/questie-spawns.lua [--questiedb ../.addons/QuestieDB] [--flavor Forever]
--                                          [--out plans/tools/data/npc-spawns.lua] [packs-src/x.lua ...]
--   no pack files given: every pack in packs-src\.
-- As a library (tests): local QS = assert(loadfile("tools/import/questie-spawns.lua"))("--lib", "<tools folder>")
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2])
    or (arg and arg[0] and arg[0]:match("^(.*)[/\\]import[/\\][^/\\]+$")) or "tools"
local QS = { MAX_SPAWNS = 40 }

-- ------------------------------------------------------------------ base64 and CBOR (data only, never run)
local B64 = {}
do
    local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do B64[abc:byte(i)] = i - 1 end
end

function QS.Base64(s)
    local out, acc, bits = {}, 0, 0
    for i = 1, #s do
        local v = B64[s:byte(i)]
        if v then
            acc, bits = acc * 64 + v, bits + 6
            if bits >= 8 then
                bits = bits - 8
                local b = math.floor(acc / 2 ^ bits)
                out[#out + 1] = b
                acc = acc - b * 2 ^ bits
            end
        elseif s:sub(i, i) ~= "=" and not s:sub(i, i):match("%s") then
            return nil, "bad base64"
        end
    end
    return out
end

local function Float(b, i, n)
    if n == 2 then
        local h = b[i] * 256 + b[i + 1]
        local sign = h >= 32768 and -1 or 1
        local e, m = math.floor(h / 1024) % 32, h % 1024
        if e == 0 then return sign * m * 2 ^ -24 end
        if e == 31 then return 0 / 0 end
        return sign * (1 + m / 1024) * 2 ^ (e - 15)
    elseif n == 4 then
        local sign = b[i] >= 128 and -1 or 1
        local e = (b[i] % 128) * 2 + math.floor(b[i + 1] / 128)
        local m = (b[i + 1] % 128) * 65536 + b[i + 2] * 256 + b[i + 3]
        if e == 0 then return sign * m * 2 ^ -149 end
        if e == 255 then return 0 / 0 end
        return sign * (1 + m / 2 ^ 23) * 2 ^ (e - 127)
    else
        local sign = b[i] >= 128 and -1 or 1
        local e = (b[i] % 128) * 16 + math.floor(b[i + 1] / 16)
        local m = b[i + 1] % 16
        for k = 2, 7 do m = m * 256 + b[i + k] end
        if e == 0 then return sign * m * 2 ^ -1074 end
        if e == 2047 then return 0 / 0 end
        return sign * (1 + m / 2 ^ 52) * 2 ^ (e - 1023)
    end
end

local BREAK = {}
-- Decodes one CBOR item from byte list b at position i. Returns value, next position (errors on bad data).
local function Item(b, i, depth)
    if depth > 16 then error("too deep", 0) end
    local t = b[i]
    if not t then error("truncated", 0) end
    i = i + 1
    local major, info = math.floor(t / 32), t % 32
    if t == 0xFF then return BREAK, i end
    if major == 7 then
        if info == 20 then return false, i end
        if info == 21 then return true, i end
        if info == 22 or info == 23 then return nil, i end
        if info == 25 then return Float(b, i, 2), i + 2 end
        if info == 26 then return Float(b, i, 4), i + 4 end
        if info == 27 then return Float(b, i, 8), i + 8 end
        if info < 20 then return nil, i end
        error("bad simple value", 0)
    end
    local n, indef = info, false
    if info == 24 then n, i = b[i], i + 1
    elseif info == 25 then n, i = b[i] * 256 + b[i + 1], i + 2
    elseif info == 26 then n, i = ((b[i] * 256 + b[i + 1]) * 256 + b[i + 2]) * 256 + b[i + 3], i + 4
    elseif info == 27 then
        n = 0
        for k = 0, 7 do n = n * 256 + b[i + k] end
        i = i + 8
    elseif info == 31 then indef = true
    elseif info > 27 then error("bad length", 0) end
    if not n then error("truncated", 0) end
    if major == 0 then return n, i end
    if major == 1 then return -1 - n, i end
    if major == 2 or major == 3 then
        if indef then error("indefinite string", 0) end
        return "", i + n   -- strings are skipped: spawns are numbers only
    end
    if major == 6 then return Item(b, i, depth + 1) end
    if major == 4 then
        local arr, k = {}, 0
        while indef or k < n do
            local v
            v, i = Item(b, i, depth + 1)
            if v == BREAK then break end
            k = k + 1
            arr[k] = v
        end
        return arr, i
    end
    if major == 5 then
        local map, k = {}, 0
        while indef or k < n do
            local key, v
            key, i = Item(b, i, depth + 1)
            if key == BREAK then break end
            v, i = Item(b, i, depth + 1)
            k = k + 1
            if key ~= nil then map[key] = v end
        end
        return map, i
    end
    error("bad major type", 0)
end

function QS.Cbor(bytes)
    local ok, v = pcall(Item, bytes, 1, 0)
    if not ok then return nil, v end
    return v
end

-- ------------------------------------------------------------------ reading QuestieDB
local function Round2(v) return math.floor(v * 100 + 0.5) / 100 end

-- areaId -> uiMapID. The file holds two tables as text ([[return { ... }]]); we only read "[n] = m" pairs,
-- nothing is run. The override table (first in the file) wins over the main one.
function QS.AreaMaps(path)
    local fh = io.open(path, "rb")
    if not fh then return nil, "can't open " .. path end
    local text = fh:read("*a")
    fh:close()
    local over, main, cur = {}, {}, nil
    for line in text:gmatch("[^\n]+") do
        if line:find("areaIdToUiMapIdOverride%s*=") then cur = over
        elseif line:find("areaIdToUiMapId%s*=") then cur = main
        elseif cur then
            local a, m = line:match("^%s*%[(%d+)%]%s*=%s*(%d+)")
            if a then cur[tonumber(a)] = tonumber(m) end
        end
    end
    for a, m in pairs(over) do main[a] = m end
    return main
end

-- spawns (decoded field 7) -> flat sorted list { map, x, y, map, x, y, ... }, stats
function QS.Flatten(spawns, areaMaps, stats)
    local pts, seen = {}, {}
    if type(spawns) ~= "table" then return pts end
    for area, list in pairs(spawns) do
        local map = type(area) == "number" and areaMaps[area]
        if not map or map == 0 then
            stats.unknownArea = (stats.unknownArea or 0) + 1
        elseif type(list) == "table" then
            for _, p in ipairs(list) do
                local x, y = type(p) == "table" and p[1], type(p) == "table" and p[2]
                if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                    x, y = Round2(x), Round2(y)
                    local key = map .. ":" .. x .. ":" .. y
                    if not seen[key] then
                        seen[key] = true
                        pts[#pts + 1] = { map, x, y }
                    end
                else
                    stats.badPoint = (stats.badPoint or 0) + 1
                end
            end
        end
    end
    table.sort(pts, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        if a[2] ~= b[2] then return a[2] < b[2] end
        return a[3] < b[3]
    end)
    if #pts > QS.MAX_SPAWNS then
        stats.capped = (stats.capped or 0) + 1
        for k = #pts, QS.MAX_SPAWNS + 1, -1 do pts[k] = nil end
    end
    local flat = {}
    for k, p in ipairs(pts) do flat[k * 3 - 2], flat[k * 3 - 1], flat[k * 3] = p[1], p[2], p[3] end
    return flat
end

-- Generic reader for the baked TOC store. want = { Npc = { ids = { [id] = true }, fields = { [7] = true, S = true } },
-- Quest = ..., Item = ..., Object = ... }. A value is base64(CBOR); "~N~" means it is split into lines
-- <key>-1 .. <key>-N whose texts are joined. Field "S" is a map of the small fields ({ [fieldIndex] = value }) and
-- is merged into the entity. Strings (names, texts) are skipped by the decoder: only numbers and tables come back.
-- Returns ents = { Npc = { [id] = { [field] = value } }, ... }, stats, meta
function QS.ReadEntities(tocPath, want)
    local fh = io.open(tocPath, "rb")
    if not fh then return nil, "can't open " .. tocPath end
    local ents, stats, meta, pending = {}, { decodeError = 0 }, {}, {}
    for kind in pairs(want) do ents[kind] = {} end
    local function Store(kind, id, field, text)
        local bytes = QS.Base64(text)
        local v = bytes and QS.Cbor(bytes)
        if v == nil then stats.decodeError = stats.decodeError + 1 return end
        local e = ents[kind][id] or {}
        ents[kind][id] = e
        if field == "S" then
            if type(v) == "table" then
                for k, x in pairs(v) do if type(k) == "number" then e[k] = x end end
            end
        else
            e[tonumber(field)] = v
        end
    end
    for line in fh:lines() do
        local key, val = line:match("^## X%-([%w%-]+): ?(.-)%s*$")
        if key then
            local kind, id, field, part = key:match("^(%a+)%-(%d+)%-(%w+)%-?(%d*)$")
            local w = kind and want[kind]
            id = id and tonumber(id)
            if w and w.ids[id] and (w.fields[field] or w.fields[tonumber(field)]) then
                local pk = kind .. id .. "-" .. field
                if part == "" then
                    local n = val:match("^~(%d+)~$")
                    if n then pending[pk] = { n = tonumber(n), parts = {}, got = 0 }
                    else Store(kind, id, field, val) end
                else
                    local p = pending[pk]
                    if p then
                        p.parts[tonumber(part)] = val
                        p.got = p.got + 1
                        if p.got == p.n then
                            Store(kind, id, field, table.concat(p.parts))
                            pending[pk] = nil
                        end
                    end
                end
            elseif key == "Flavor" or key == "Contract-Version" or key == "BUILD-COMMIT" or key == "BUILD-TIME" then
                meta[key] = val
            end
        elseif not meta.Version then
            meta.Version = line:match("^## Version: (.-)%s*$")
        end
    end
    fh:close()
    for _ in pairs(pending) do stats.decodeError = stats.decodeError + 1 end
    return ents, stats, meta
end

-- wanted = { [npcId] = true }. Returns spawns = { [id] = flat list }, missing = { ids }, stats, meta
function QS.ReadToc(tocPath, wanted, areaMaps)
    local ents, stats, meta = QS.ReadEntities(tocPath, { Npc = { ids = wanted, fields = { [7] = true } } })
    if not ents then return nil, stats end
    local spawns = {}
    for id, e in pairs(ents.Npc) do
        local flat = QS.Flatten(e[7], areaMaps, stats)
        if #flat > 0 then spawns[id] = flat end
    end
    local missing = {}
    for id in pairs(wanted) do if not spawns[id] then missing[#missing + 1] = id end end
    table.sort(missing)
    return spawns, missing, stats, meta
end

-- The NPC ids of the packs' talk steps (packcheck's PC.TALK types).
function QS.PackNpcs(files)
    local PC = assert(loadfile(toolsDir .. "/packcheck.lua"))("--lib", toolsDir)
    local L = PC.Lib()
    local wanted, n = {}, 0
    for _, f in ipairs(files) do
        local t = L.LoadData(f)
        if L.IsPack(t) then
            local routes = L.Expand(t)
            for _, r in ipairs(routes) do
                for _, s in ipairs(r.steps) do
                    if PC.TALK[s.type] and type(s.npc) == "number" and not wanted[s.npc] then
                        wanted[s.npc] = true
                        n = n + 1
                    end
                end
            end
        end
    end
    return wanted, n
end

-- The data file's text. Numbers only.
function QS.Write(spawns, missing, meta, date)
    local ids = {}
    for id in pairs(spawns) do ids[#ids + 1] = id end
    table.sort(ids)
    local o = {}
    o[#o + 1] = "-- SPDX-License-Identifier: GPL-3.0-or-later"
    o[#o + 1] = "-- NPC spawn points for packcheck's NPC distance check (tools\\packcheck.lua PC.NpcCheck). Local only: never shipped or published."
    o[#o + 1] = "-- Source: QuestieDB (Questie project, https://github.com/Questie), flavour "
        .. tostring(meta.Flavor or "?") .. ", version " .. tostring(meta.Version or "?")
        .. ", build " .. tostring(meta["BUILD-COMMIT"] or "?") .. ", read from a local copy."
    o[#o + 1] = "-- Licence: QuestieDB LICENSE.md (GNU GPL v3 for consenting contributors; other content may be all rights"
    o[#o + 1] = "-- reserved; ruling open, so this file stays local). Only bare facts are kept: NPC id, uiMapID, x, y."
    o[#o + 1] = "-- Converted and changed by gettic, " .. date .. " (only the NPCs our packs talk to; areaId -> uiMapID;"
    o[#o + 1] = "-- coordinates rounded to 2 decimals; duplicates dropped; at most " .. QS.MAX_SPAWNS .. " points per NPC)."
    o[#o + 1] = "-- Made by tools/import/questie-spawns.lua: rerun it after the packs change, don't edit by hand."
    o[#o + 1] = "-- questie[npcId] = { map, x, y, map, x, y, ... }; missing = NPC ids our packs use that have no spawn there."
    o[#o + 1] = "return {"
    o[#o + 1] = "    questie = {"
    for _, id in ipairs(ids) do
        local f = spawns[id]
        local parts = {}
        for k = 1, #f, 3 do
            local x = ("%.2f"):format(f[k + 1]):gsub("%.?0+$", "")
            local y = ("%.2f"):format(f[k + 2]):gsub("%.?0+$", "")
            parts[#parts + 1] = ("%d, %s, %s"):format(f[k], x, y)
        end
        o[#o + 1] = ("        [%d] = { %s },"):format(id, table.concat(parts, ", "))
    end
    o[#o + 1] = "    },"
    local m = {}
    for _, id in ipairs(missing) do m[#m + 1] = tostring(id) end
    o[#o + 1] = "    missing = { " .. table.concat(m, ", ") .. (#m > 0 and " " or "") .. "},"
    o[#o + 1] = "}"
    return table.concat(o, "\n") .. "\n"
end

function QS.Main(argv)
    local opts = { questiedb = "../.addons/QuestieDB", flavor = "Forever", out = "plans/tools/data/npc-spawns.lua", files = {} }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--questiedb" or a == "--flavor" or a == "--out" or a == "--date" then
            opts[a:sub(3)] = argv[i + 1]
            i = i + 2
        else
            opts.files[#opts.files + 1] = a
            i = i + 1
        end
    end
    if #opts.files == 0 then
        local PC = assert(loadfile(toolsDir .. "/packcheck.lua"))("--lib", toolsDir)
        for _, f in ipairs(PC.Lib().ListDir("packs-src", "lua")) do opts.files[#opts.files + 1] = "packs-src/" .. f end
    end
    local wanted, n = QS.PackNpcs(opts.files)
    local areaMaps, err = QS.AreaMaps(opts.questiedb .. "/support/" .. opts.flavor .. "/Zones/areaIdToUiMapId.lua")
    if not areaMaps then print("ERROR " .. err) return false end
    local spawns, missing, stats, meta = QS.ReadToc(opts.questiedb .. "/QuestieDB_" .. opts.flavor .. ".toc", wanted, areaMaps)
    if not spawns then print("ERROR " .. missing) return false end
    local text = QS.Write(spawns, missing, meta, opts.date or os.date("%Y-%m-%d"))
    local fh = assert(io.open(opts.out, "wb"))
    fh:write(text)
    fh:close()
    local kept, pts = 0, 0
    for _, f in pairs(spawns) do kept, pts = kept + 1, pts + #f / 3 end
    print(("questie-spawns: %d NPCs in the packs, %d with spawns (%d points), %d without (missing), "
        .. "decode errors %d, unknown areas dropped %d, bad points dropped %d, capped %d; %s, %d bytes")
        :format(n, kept, pts, #missing, stats.decodeError, stats.unknownArea or 0, stats.badPoint or 0,
            stats.capped or 0, opts.out, #text))
    return stats.decodeError == 0
end

if args[1] == "--lib" then return QS end
if not QS.Main(args) then os.exit(1) end

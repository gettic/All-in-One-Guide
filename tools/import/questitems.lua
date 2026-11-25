-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Builds AllinOneGuide\Data\QuestItems.lua: the quest-starting items and quest-objective items of the quests in
-- our 1-20 zones, as bare ids (item, quest, role, source kind, "can it be got again"). No names, no texts.
--
-- Inputs (nothing is downloaded; point it at copies that are already there):
--   * a LOCAL CMaNGOS classic-db SQL dump (https://github.com/cmangos/classic-db, GPL-3.0), parsed as TEXT only
--     (never loaded into a database, never run). Only numbers are read: quest_template (item columns, level,
--     zone), item_template (startquest), loot tables, npc_vendor, creature / gameobject spawn counts.
--     Ruling: plans\bug-first-step\licence-cmangos.md (bare ids only; the dump itself is never shipped).
--   * tools\data\forever-questitems.lua: Forever-only items, typed in from foreverdb.net item / quest pages.
--   * the packs in packs-src\ (which quests and which zones are "ours").
--   * optional, CROSS-CHECK ONLY: a local QuestieDB Forever copy. Its values never go into the output; the
--     differences are written to the --report file (local, plans\).
-- Rows with an unclear source are dropped and listed in the report.
--
-- Which quests: every quest id used in the packs, plus quests of our zones (quest level <= MAXLEVEL) that an
-- item starts (the drop-started quests the routes leave out), plus the Forever list.
-- `again`: true = a normal repeatable source (a drop from mobs with 2+ spawns, a respawning object with 2+
-- spawns, a vendor); false = one-time (handed out by the quest, a single unique mob or object, or no source
-- left in the data = removed content).
--
-- Run (from the repository folder):
--   luajit tools/import/questitems.lua [--sql plans/tools/data/cmangos/ClassicDB.sql] [--packs packs-src]
--       [--forever tools/data/forever-questitems.lua] [--questiedb ../.addons/QuestieDB/QuestieDB_Forever.toc]
--       [--out AllinOneGuide/Data/QuestItems.lua] [--report plans/quest-items/report.txt] [--audit plans/quest-items/audit.lua] [--date YYYY-MM-DD]
-- As a library (tests): local QI = assert(loadfile("tools/import/questitems.lua"))("--lib")
local args = { ... }
local QI = { MAXLEVEL = 22 }

-- uiMapID (as used in the packs) -> AreaTable zone id (quest_template.ZoneOrSort). Open-world zones only:
-- cities and Moonglade are left out on purpose (no 1-20 drop starters there).
QI.ZONE = { [1426] = 1, [1429] = 12, [1411] = 14, [1413] = 17, [1436] = 40, [1432] = 38, [1433] = 44,
    [1431] = 10, [1420] = 85, [1421] = 130, [1438] = 141, [1439] = 148, [1412] = 215, [1442] = 406,
    [1437] = 11, [1440] = 331 }

-- ------------------------------------------------------------------ SQL text reader (data only, never run)
-- Calls cb(row) for each "(...)" tuple of an INSERT line; row[col] = raw text of the wanted (numeric) columns.
-- Strings are skipped (their text is never kept).
function QI.Tuples(line, want, cb)
    local p = line:find(" VALUES ", 1, true)
    if not p then return end
    while true do
        p = line:find("(", p, true)
        if not p then return end
        p = p + 1
        local col, row = 0, {}
        while true do
            col = col + 1
            if line:byte(p) == 39 then
                local q = p + 1
                while true do
                    local s = line:find("[\\']", q)
                    if not s then return end
                    if line:byte(s) == 92 then q = s + 2 else q = s break end
                end
                p = q + 1
            else
                local s = line:find("[,)]", p)
                if not s then return end
                if want[col] then row[col] = line:sub(p, s - 1) end
                p = s
            end
            local d = line:byte(p)
            p = p + 1
            if d == 41 then break end
        end
        cb(row)
    end
end

-- One pass over the dump. handlers = { [table] = { cols = { "name", ... }, fn = function(v) end } } where
-- v[name] is a number. Column positions come from the dump's own CREATE TABLE lines.
function QI.Pass(path, handlers)
    local fh = io.open(path, "rb")
    if not fh then return nil, "can't open " .. path end
    local defs, cur = {}, nil
    for line in fh:lines() do
        local ct = line:match("^CREATE TABLE `([%w_]+)`")
        if ct then
            cur = handlers[ct] and { n = 0, idx = {} } or nil
            if cur then defs[ct] = cur end
        elseif cur then
            local c = line:match("^%s+`([%w_]+)`")
            if c then
                cur.n = cur.n + 1
                cur.idx[c] = cur.n
            elseif not line:match("^%s") then
                cur = nil
            end
        else
            local tbl = line:match("^INSERT INTO `([%w_]+)` VALUES ")
            local h = tbl and handlers[tbl]
            if h then
                local d = defs[tbl]
                if not d then fh:close() return nil, "no CREATE TABLE for " .. tbl end
                local want, map = {}, {}
                for _, name in ipairs(h.cols) do
                    local i = d.idx[name]
                    if not i then fh:close() return nil, tbl .. ": no column " .. name end
                    want[i], map[name] = true, i
                end
                QI.Tuples(line, want, function(row)
                    local v = {}
                    for name, i in pairs(map) do v[name] = tonumber(row[i]) or 0 end
                    h.fn(v)
                end)
            end
        end
    end
    fh:close()
    return true
end

-- ------------------------------------------------------------------ packs
-- Quest ids and uiMapIDs of the packs' expanded steps (tools\packlib.lua: packs are read as data, never run).
function QI.ReadPacks(files, toolsDir)
    local L = assert(loadfile(toolsDir .. "/packlib.lua"))()
    local quests, maps, n = {}, {}, 0
    for _, f in ipairs(files) do
        local t = L.LoadData(f)
        if L.IsPack(t) then
            n = n + 1
            for _, r in ipairs(L.Expand(t)) do
                for _, s in ipairs(r.steps) do
                    if type(s.quest) == "number" then quests[s.quest] = true end
                    if type(s.map) == "number" then maps[s.map] = true end
                end
            end
        end
    end
    return quests, maps, n
end

local function ListPacks(dir, toolsDir)
    local L = assert(loadfile(toolsDir .. "/packlib.lua"))()
    local out = {}
    for _, f in ipairs(L.ListDir(dir, "lua")) do out[#out + 1] = dir .. "/" .. f end
    table.sort(out)
    return out
end

-- ------------------------------------------------------------------ cmangos
-- Returns rows = { [item] = { q = { quest, ... }, r = { role, ... }, kind, again, src = "cmangos" } }, stats
function QI.FromCmangos(sql, packQuests, zones)
    local st = { quests = 0, packQuestsMissing = 0, zoneStarters = 0 }
    -- pass 1: quests and item start links
    local quest, starts = {}, {}
    local ok, err = QI.Pass(sql, {
        item_template = { cols = { "entry", "startquest" }, fn = function(v)
            if v.startquest > 0 then
                starts[v.startquest] = starts[v.startquest] or {}
                local l = starts[v.startquest]
                l[#l + 1] = v.entry
            end
        end },
        quest_template = { cols = { "entry", "ZoneOrSort", "QuestLevel", "SrcItemId", "ReqItemId1", "ReqItemId2",
            "ReqItemId3", "ReqItemId4", "ReqSourceId1", "ReqSourceId2", "ReqSourceId3", "ReqSourceId4" },
            fn = function(v) quest[v.entry] = v end },
    })
    if not ok then return nil, err end

    local wanted = {}
    for q in pairs(packQuests) do
        if quest[q] then wanted[q] = true else st.packQuestsMissing = st.packQuestsMissing + 1 end
    end
    for q, items in pairs(starts) do
        local v = quest[q]
        if v and not wanted[q] and zones[v.ZoneOrSort] and v.QuestLevel > 0 and v.QuestLevel <= QI.MAXLEVEL and #items > 0 then
            wanted[q] = true
            st.zoneStarters = st.zoneStarters + 1
        end
    end

    local rows, given = {}, {}
    local function Add(item, q, role)
        if item <= 0 then return end
        local r = rows[item]
        if not r then r = { q = {}, r = {}, src = "cmangos" } rows[item] = r end
        for i, x in ipairs(r.q) do
            if x == q then
                if role == "start" or (role == "obj" and r.r[i] == "use") then r.r[i] = role end
                return
            end
        end
        r.q[#r.q + 1], r.r[#r.r + 1] = q, role
    end
    for q in pairs(wanted) do
        st.quests = st.quests + 1
        local v = quest[q]
        for _, it in ipairs(starts[q] or {}) do Add(it, q, "start") end
        for i = 1, 4 do Add(v["ReqItemId" .. i], q, "obj") end
        if v.SrcItemId > 0 then Add(v.SrcItemId, q, "use") given[v.SrcItemId] = true end
        for i = 1, 4 do Add(v["ReqSourceId" .. i], q, "use") end
    end
    -- any quest (not only ours) that hands the item out
    for _, v in pairs(quest) do if v.SrcItemId > 0 and rows[v.SrcItemId] then given[v.SrcItemId] = true end end

    -- pass 2: where each item comes from
    local cSpawn, oSpawn, cLoot, oLoot = {}, {}, {}, {}
    local cDrop, oDrop, vend, cont = {}, {}, {}, {}   -- [item] = { lootEntry = true }
    local refUp = { c = {}, o = {}, r = {} }           -- [refId] = { lootEntry / parent ref }
    local refHas = {}                                  -- [refId] = { item = true }
    local vtpl, vtplItems = {}, {}
    local function Push(t, k, v) t[k] = t[k] or {} t[k][v] = true end
    -- spawns: a creature / gameobject row with id 0 takes its entry from *_spawn_entry or a spawn group
    local cWorld, oWorld = {}, {}                      -- [guid] = true when on map 0 or 1
    local cEntry, oEntry = {}, {}                      -- { { guid, entry } }
    local gType, gSpawns, gEntries = {}, {}, {}        -- spawn groups: type, { guid }, { entry }
    ok, err = QI.Pass(sql, {
        creature = { cols = { "guid", "id", "map" }, fn = function(v)
            if v.map == 0 or v.map == 1 then
                cWorld[v.guid] = true
                if v.id > 0 then cSpawn[v.id] = (cSpawn[v.id] or 0) + 1 end
            end
        end },
        gameobject = { cols = { "guid", "id", "map" }, fn = function(v)
            if v.map == 0 or v.map == 1 then
                oWorld[v.guid] = true
                if v.id > 0 then oSpawn[v.id] = (oSpawn[v.id] or 0) + 1 end
            end
        end },
        creature_spawn_entry = { cols = { "guid", "entry" }, fn = function(v) cEntry[#cEntry + 1] = { v.guid, v.entry } end },
        gameobject_spawn_entry = { cols = { "guid", "entry" }, fn = function(v) oEntry[#oEntry + 1] = { v.guid, v.entry } end },
        spawn_group = { cols = { "Id", "Type" }, fn = function(v) gType[v.Id] = v.Type end },
        spawn_group_spawn = { cols = { "Id", "Guid" }, fn = function(v)
            gSpawns[v.Id] = gSpawns[v.Id] or {}
            local l = gSpawns[v.Id]
            l[#l + 1] = v.Guid
        end },
        spawn_group_entry = { cols = { "Id", "Entry" }, fn = function(v) Push(gEntries, v.Id, v.Entry) end },
        creature_template = { cols = { "Entry", "LootId", "VendorTemplateId" }, fn = function(v)
            if v.LootId > 0 then Push(cLoot, v.LootId, v.Entry) end
            if v.VendorTemplateId > 0 then Push(vtpl, v.VendorTemplateId, v.Entry) end
        end },
        gameobject_template = { cols = { "entry", "type", "data1" }, fn = function(v)
            -- 3 = chest, 25 = fishing hole: data1 is the loot id
            if (v.type == 3 or v.type == 25) and v.data1 > 0 then Push(oLoot, v.data1, v.entry) end
        end },
        creature_loot_template = { cols = { "entry", "item", "mincountOrRef" }, fn = function(v)
            if v.mincountOrRef < 0 then Push(refUp.c, -v.mincountOrRef, v.entry)
            elseif rows[v.item] then Push(cDrop, v.item, v.entry) end
        end },
        gameobject_loot_template = { cols = { "entry", "item", "mincountOrRef" }, fn = function(v)
            if v.mincountOrRef < 0 then Push(refUp.o, -v.mincountOrRef, v.entry)
            elseif rows[v.item] then Push(oDrop, v.item, v.entry) end
        end },
        reference_loot_template = { cols = { "entry", "item", "mincountOrRef" }, fn = function(v)
            if v.mincountOrRef < 0 then Push(refUp.r, -v.mincountOrRef, v.entry)
            elseif rows[v.item] then Push(refHas, v.entry, v.item) end
        end },
        item_loot_template = { cols = { "entry", "item" }, fn = function(v)
            if rows[v.item] then Push(cont, v.item, v.entry) end
        end },
        npc_vendor = { cols = { "entry", "item" }, fn = function(v)
            if rows[v.item] then Push(vend, v.item, v.entry) end
        end },
        npc_vendor_template = { cols = { "entry", "item" }, fn = function(v)
            if rows[v.item] then Push(vtplItems, v.item, v.entry) end
        end },
    })
    if not ok then return nil, err end
    -- random-entry spawns count once for each entry they can be (enough to tell "one" from "several")
    for _, p in ipairs(cEntry) do if cWorld[p[1]] then cSpawn[p[2]] = (cSpawn[p[2]] or 0) + 1 end end
    for _, p in ipairs(oEntry) do if oWorld[p[1]] then oSpawn[p[2]] = (oSpawn[p[2]] or 0) + 1 end end
    for id, entries in pairs(gEntries) do
        local isGo = gType[id] == 1
        local world, spawn = isGo and oWorld or cWorld, isGo and oSpawn or cSpawn
        local n = 0
        for _, g in ipairs(gSpawns[id] or {}) do if world[g] then n = n + 1 end end
        if n > 0 then for e in pairs(entries) do spawn[e] = (spawn[e] or 0) + n end end
    end

    -- references: walk up (ref in ref) to the creature / object loot entries
    for ref, items in pairs(refHas) do
        local seen, todo = {}, { ref }
        while #todo > 0 do
            local r = table.remove(todo)
            if not seen[r] then
                seen[r] = true
                for item in pairs(items) do
                    for e in pairs(refUp.c[r] or {}) do Push(cDrop, item, e) end
                    for e in pairs(refUp.o[r] or {}) do Push(oDrop, item, e) end
                end
                for parent in pairs(refUp.r[r] or {}) do todo[#todo + 1] = parent end
            end
        end
    end
    for item, tpls in pairs(vtplItems) do
        for t in pairs(tpls) do for npc in pairs(vtpl[t] or {}) do Push(vend, item, npc) end end
    end

    -- spawns behind a set of loot entries (creature or object)
    local function Spawns(lootEntries, owners, spawn)
        local n = 0
        for e in pairs(lootEntries or {}) do
            for id in pairs(owners[e] or {}) do n = n + (spawn[id] or 0) end
        end
        return n
    end
    for item, r in pairs(rows) do
        local nc = Spawns(cDrop[item], cLoot, cSpawn)
        local no = Spawns(oDrop[item], oLoot, oSpawn)
        local nv = 0
        for npc in pairs(vend[item] or {}) do nv = nv + (cSpawn[npc] or 0) end
        local allUse = true
        for _, role in ipairs(r.r) do if role ~= "use" then allUse = false end end
        -- a loot table with no world spawn behind it = a summoned / event mob or object: one-time
        if given[item] and allUse then r.kind, r.again = "given", false
        elseif nc > 0 or (cDrop[item] and no == 0) then r.kind, r.again = "drop", nc >= 2
        elseif oDrop[item] then r.kind, r.again = "object", no >= 2
        elseif nv > 0 then r.kind, r.again = "vendor", true
        elseif given[item] or cont[item] then r.kind, r.again = "given", false
        else r.kind, r.again = "given", false r.nosrc = true end
    end
    return rows, st
end

-- ------------------------------------------------------------------ Forever list
local KINDS = { drop = true, object = true, vendor = true, given = true }
local ROLES = { start = true, obj = true, use = true }

-- Returns rows (same shape, src = "foreverdb"), dropped = { "reason", ... }
function QI.FromForever(path)
    local chunk = loadfile(path, "t", {})   -- a plain table literal; read in an empty environment
    if not chunk then return {}, { "no Forever list at " .. tostring(path) } end
    local ok, list = pcall(chunk)
    if not ok or type(list) ~= "table" then return {}, { "Forever list does not load" } end
    local rows, dropped = {}, {}
    for _, e in ipairs(list) do
        if type(e.item) == "number" and type(e.q) == "number" and ROLES[e.r] and KINDS[e.kind]
            and type(e.again) == "boolean" and type(e.from) == "string" and e.from:match("^https://foreverdb%.net/") then
            local r = rows[e.item]
            if not r then r = { q = {}, r = {}, src = "foreverdb", kind = e.kind, again = e.again } rows[e.item] = r end
            r.q[#r.q + 1], r.r[#r.r + 1] = e.q, e.r
        else
            dropped[#dropped + 1] = "forever row " .. tostring(e.item) .. ": incomplete or source not foreverdb.net"
        end
    end
    return rows, dropped
end

-- ------------------------------------------------------------------ output
local function Sorted(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
end

local SHORT = { start = "s", obj = "o", use = "u" }

-- Shipped file: only what the game reads (q and again). `full` = true writes the local audit file
-- (every field, kept under plans\quest-items\, never shipped).
function QI.Render(rows, date, counts, full)
    local out
    if full then
        out = {
            "-- LOCAL AUDIT COPY (not shipped, gitignored): the full rows of AllinOneGuide\\Data\\QuestItems.lua with",
            "-- provenance. Generated by tools/import/questitems.lua on " .. date .. ".",
            "-- Row: [itemId] = { q = quest id(s), r = role(s) (s start, o objective, u handed to you), kind, again, src, confirmed }",
            ("-- %d rows: %d cmangos, %d foreverdb."):format(counts.total, counts.cmangos, counts.foreverdb),
            "return {",
        }
    else
        out = {
            "-- SPDX-License-Identifier: GPL-3.0-or-later",
            "-- Copyright (C) 2026 gettic",
            "-- Quest items of the 1-20 zones (bare ids only; names come from the game at runtime). Generated by",
            "-- tools/import/questitems.lua (source in the public repo); do not edit by hand.",
            "-- Sources: CMaNGOS classic-db (https://github.com/cmangos/classic-db), GPL-3.0: ids and flags from its quest,",
            "--   item, loot and vendor tables; foreverdb.net item and quest pages for Forever-only items.",
            "--   QuestieDB was used only to cross-check. Game facts come from World of Warcraft,",
            "--   (c) Blizzard Entertainment; they are not covered by our GPL licence. See CREDITS.txt.",
            "-- Converted and changed by gettic, " .. date .. ". Nothing here is confirmed on Forever yet.",
            "-- Row: [itemId] = { q = quest id (or a list when more than one quest uses the item),",
            "--   again = true: can be got again (normal loot table, respawning object, vendor); false: one-time }",
            ("-- %d rows: %d cmangos, %d foreverdb."):format(counts.total, counts.cmangos, counts.foreverdb),
            "local _, ns = ...",
            "ns.QuestItems = {",
        }
    end
    for _, item in ipairs(Sorted(rows)) do
        local r = rows[item]
        local q, ro
        if #r.q == 1 then
            q, ro = tostring(r.q[1]), '"' .. SHORT[r.r[1]] .. '"'
        else
            local qs, rs = {}, {}
            for i = 1, #r.q do qs[i], rs[i] = tostring(r.q[i]), '"' .. SHORT[r.r[i]] .. '"' end
            q, ro = "{" .. table.concat(qs, ",") .. "}", "{" .. table.concat(rs, ",") .. "}"
        end
        if full then
            out[#out + 1] = ('[%d]={q=%s,r=%s,kind="%s",again=%s,src="%s",confirmed=false},')
                :format(item, q, ro, r.kind, tostring(r.again), r.src)
        else
            out[#out + 1] = ('[%d]={q=%s,again=%s},'):format(item, q, tostring(r.again))
        end
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
end
-- ------------------------------------------------------------------ QuestieDB cross-check (report only)
function QI.CrossCheck(rows, tocPath, toolsDir)
    local lines = {}
    local okLoad, QS = pcall(function() return assert(loadfile(toolsDir .. "/import/questie-spawns.lua"))("--lib", toolsDir) end)
    if not okLoad then return { "cross-check skipped: questie-spawns.lua did not load" } end
    local ids = {}
    for item in pairs(rows) do ids[item] = true end
    local ents = QS.ReadEntities(tocPath, { Item = { ids = ids, fields = { [2] = true, [3] = true, [5] = true, [14] = true, S = true } } })
    if not ents then return { "cross-check skipped: no QuestieDB at " .. tostring(tocPath) } end
    local agree, missing = 0, 0
    local function NonEmpty(t) return type(t) == "table" and next(t) ~= nil end
    for _, item in ipairs(Sorted(rows)) do
        local r, e = rows[item], ents.Item[item]
        if not e then
            missing = missing + 1
            lines[#lines + 1] = ("%d: not in QuestieDB"):format(item)
        else
            local diffs = {}
            for i, role in ipairs(r.r) do
                if role == "start" and e[5] ~= r.q[i] then diffs[#diffs + 1] = ("start: ours %d, questie %s"):format(r.q[i], tostring(e[5])) end
            end
            local qk = NonEmpty(e[2]) and "drop" or NonEmpty(e[3]) and "object" or NonEmpty(e[14]) and "vendor" or "given"
            if qk ~= r.kind then diffs[#diffs + 1] = ("kind: ours %s, questie %s"):format(r.kind, qk) end
            if #diffs == 0 then agree = agree + 1
            else lines[#lines + 1] = ("%d (%s): %s"):format(item, r.src, table.concat(diffs, "; ")) end
        end
    end
    table.insert(lines, 1, ("QuestieDB cross-check: %d agree, %d differ, %d not in QuestieDB"):format(agree, #lines - missing, missing))
    return lines
end

-- ------------------------------------------------------------------ main
function QI.Main(argv)
    local o = { sql = "plans/tools/data/cmangos/ClassicDB.sql", packs = "packs-src", forever = "tools/data/forever-questitems.lua",
        questiedb = "../.addons/QuestieDB/QuestieDB_Forever.toc", out = "AllinOneGuide/Data/QuestItems.lua",
        report = "plans/quest-items/report.txt", audit = "plans/quest-items/audit.lua", date = os.date("%Y-%m-%d"), tools = "tools" }
    local i = 1
    while i <= #argv do
        local k = argv[i]:match("^%-%-(%w+)$")
        if k and o[k] ~= nil and argv[i + 1] then o[k] = argv[i + 1] i = i + 2
        else io.stderr:write("unknown argument " .. argv[i] .. "\n") return 2 end
    end
    local packQuests, packMaps, nPacks = QI.ReadPacks(ListPacks(o.packs, o.tools), o.tools)
    if nPacks == 0 then io.stderr:write("no packs read from " .. o.packs .. "\n") return 1 end
    local zones = {}
    for m in pairs(packMaps) do if QI.ZONE[m] then zones[QI.ZONE[m]] = true end end
    local rows, st = QI.FromCmangos(o.sql, packQuests, zones)
    if not rows then io.stderr:write(tostring(st) .. "\n") return 1 end
    local frows, dropped = QI.FromForever(o.forever)
    local counts = { cmangos = 0, foreverdb = 0, total = 0 }
    local report = {}
    for item, r in pairs(rows) do
        if r.nosrc then
            -- not handed out by a quest and in no loot / vendor table: removed content or a scripted source.
            -- Kept as one-time ("given", again = false), listed for the updater.
            report[#report + 1] = ("%d (quest %d): no source in cmangos, kept as given / one-time"):format(item, r.q[1])
        end
    end
    for item, r in pairs(frows) do
        if rows[item] then dropped[#dropped + 1] = ("forever row %d: also in cmangos, cmangos row kept"):format(item)
        else rows[item] = r end
    end
    for _, r in pairs(rows) do counts[r.src] = counts[r.src] + 1 counts.total = counts.total + 1 end
    local text = QI.Render(rows, o.date, counts)
    local fh = assert(io.open(o.out, "wb"))
    fh:write(text)
    fh:close()
    local af = io.open(o.audit, "wb")   -- local audit copy with every field (plans\ is gitignored)
    if af then af:write(QI.Render(rows, o.date, counts, true)) af:close() end

    local cc = QI.CrossCheck(rows, o.questiedb, o.tools)
    local rep = { ("questitems %s: %d rows (%d cmangos, %d foreverdb), %d bytes"):format(o.date, counts.total, counts.cmangos,
        counts.foreverdb, #text),
        ("quests read: %d (pack quests not in cmangos: %d, zone quests started by an item: %d)"):format(st.quests,
            st.packQuestsMissing, st.zoneStarters), "", "Dropped:" }
    for _, d in ipairs(dropped) do rep[#rep + 1] = "  " .. d end
    rep[#rep + 1] = ""
    rep[#rep + 1] = "No source in cmangos:"
    table.sort(report)
    for _, d in ipairs(report) do rep[#rep + 1] = "  " .. d end
    rep[#rep + 1] = ""
    for _, l in ipairs(cc) do rep[#rep + 1] = l end
    local rf = io.open(o.report, "wb")
    if rf then rf:write(table.concat(rep, "\n") .. "\n") rf:close() end
    print(rep[1])
    print(rep[2])
    print(cc[1])
    return 0
end

if args[1] == "--lib" then return QI end
os.exit(QI.Main(args))

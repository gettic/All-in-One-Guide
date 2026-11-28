-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Writes AllinOneGuide\Data\QuestMobs.lua: for the shipped packs' objective steps that name no mob of their own
-- (no `npc`, no `targetNpc`), the creatures the quest asks you to kill, with each creature's display id and
-- English name. The 3D viewer (UI\ModelView.lua) shows these mobs on such steps (taking turns when there are
-- several); the target button (UI\TargetButton.lua) uses the name (English clients only).
-- Source: a LOCAL CMaNGOS classic-db SQL dump (https://github.com/cmangos/classic-db, GPL-3.0), read as TEXT
-- only (never loaded into a database). Read: quest_template `entry`, `ReqCreatureOrGOId1..4` (positive = a
-- creature), `ReqItemId1..4`; creature_loot_template `entry`, `item`, `ChanceOrQuestChance` (who drops the quest's
-- items); creature_template `Entry`, `LootId`, `Name`, `ModelId1..4` (the first non-zero one). At most QM.MAX mobs
-- per quest: the kill targets first, then the droppers with the best chance.
-- Run from the repository folder:
--   luajit tools/quest_mobs.lua <ClassicDB.sql> [--routes dir]... [--out AllinOneGuide/Data/QuestMobs.lua]
--   [--check]     write nothing; fail when the file differs (or is missing)
--   [--missing f] also write the objective steps that got no mob (a list for the route writers)
-- Default routes: AllinOneGuide_Horde/Routes, AllinOneGuide_Alliance/Routes, AllinOneGuide/Routes.
-- Library mode: local QM = loadfile("tools/quest_mobs.lua")("--lib")
local argv = { ... }
local QM = { ROUTES = { "AllinOneGuide_Horde/Routes", "AllinOneGuide_Alliance/Routes", "AllinOneGuide/Routes" }, MAX = 4 }

-- A compiled row: id|type|quest|npc|map|x|y|r|text|da|flags|cond|src|extra (texts never hold "|").
local function Fields(row)
    local f, i = {}, 1
    for part in (row .. "|"):gmatch("([^|]*)|") do f[i] = part i = i + 1 end
    return f
end

-- The objective steps without a mob of their own: { { id, quest, text } }, and the set of their quests.
function QM.Steps(texts)
    local steps, quests = {}, {}
    for _, text in ipairs(texts) do
        for row in text:gmatch('\n%s*"([^"\n]*)",?') do
            if row:find("|", 1, true) and select(2, row:gsub("|", "")) >= 12 then
                local f = Fields(row)
                local q = tonumber(f[3])
                local extra = f[14] or ""
                if f[2] == "objective" and q and q > 0 and not tonumber(f[4]) and not extra:match("targetNpc=%d")
                    and not extra:match("model=%d") then
                    steps[#steps + 1] = { id = f[1], quest = q, text = f[9] }
                    quests[q] = true
                end
            end
        end
    end
    return steps, quests
end

-- creature_template rows: Entry, Name (a quoted string), SubName, MinLevel, MaxLevel, ModelId1..4.
local function Creatures(path, want)
    local fh = io.open(path, "rb")
    if not fh then return nil, "can't open " .. path end
    local out = {}
    for line in fh:lines() do
        if line:sub(1, 38) == "INSERT INTO `creature_template` VALUES" then
            local i = 40
            while true do
                i = line:find("(", i, true)
                if not i then break end
                i = i + 1
                local vals, n = {}, 0
                while true do
                    n = n + 1
                    local c = line:sub(i, i)
                    local v, j
                    if c == "'" then
                        local k = i + 1
                        local buf = {}
                        while true do
                            local ch = line:sub(k, k)
                            if ch == "" then break end
                            if ch == "\\" then buf[#buf + 1] = line:sub(k + 1, k + 1) k = k + 2
                            elseif ch == "'" then break
                            else buf[#buf + 1] = ch k = k + 1 end
                        end
                        v, j = table.concat(buf), k + 1
                    else
                        j = line:find("[,)]", i) or (#line + 1)
                        v = line:sub(i, j - 1)
                    end
                    if n <= 9 then vals[n] = v end
                    local d = line:sub(j, j)
                    i = j + 1
                    if d ~= "," then break end
                end
                local entry = tonumber(vals[1])
                if entry and want[entry] then
                    local model
                    for k = 6, 9 do
                        local m = tonumber(vals[k])
                        if m and m > 0 then model = m break end
                    end
                    out[entry] = { model = model, name = vals[2] }
                end
            end
        end
    end
    fh:close()
    return out
end

local function Lua(s) return (("%q"):format(s):gsub("\\\n", "\\n")) end

function QM.Text(mobs, info)
    local lines = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2026 gettic",
        "-- Generated by tools\\quest_mobs.lua from a CMaNGOS classic-db dump (https://github.com/cmangos/classic-db,",
        "-- GPL-3.0; quest_template ReqCreatureOrGOId1..4, creature_template Name / ModelId1..4, src = \"cmangos\");",
        "-- do not edit. See CREDITS.txt.",
        "-- Command: luajit tools/quest_mobs.lua <ClassicDB.sql> (reads the objective steps of the packs' Routes\\*.lua).",
        "-- QuestMobs: quest id -> the creatures it asks you to kill, only for objective steps that name no mob.",
        "-- QuestMobInfo: creature id -> { display id or false, English name } (3D view fallback, target button).",
        "local _, ns = ...",
        "ns.QuestMobs = {",
    }
    local qs = {}
    for q in pairs(mobs) do qs[#qs + 1] = q end
    table.sort(qs)
    local all = {}
    for _, q in ipairs(qs) do
        lines[#lines + 1] = ("    [%d] = { %s },"):format(q, table.concat(mobs[q], ", "))
        for _, c in ipairs(mobs[q]) do all[c] = true end
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = "ns.QuestMobInfo = {"
    local cs = {}
    for c in pairs(all) do cs[#cs + 1] = c end
    table.sort(cs)
    for _, c in ipairs(cs) do
        local i = info[c] or {}
        lines[#lines + 1] = ("    [%d] = { %s, %s },"):format(c, i.model and tostring(i.model) or "false", Lua(i.name or ""))
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

local function ReadFile(p)
    local fh = io.open(p, "rb")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

local function ListLua(dir)
    local out = {}
    local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.lua" 2>nul')
    if p then
        for name in p:lines() do
            name = name:match("([^/\\]+)$")
            if name and name ~= "Connectors.lua" and name ~= "Spots.lua" then out[#out + 1] = dir .. "/" .. name end
        end
        p:close()
    end
    table.sort(out)
    return out
end

function QM.Main(args)
    local sql, routes, outPath, check, missingPath = nil, {}, "AllinOneGuide/Data/QuestMobs.lua", false, nil
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--routes" then routes[#routes + 1] = args[i + 1] i = i + 1
        elseif a == "--out" then outPath = args[i + 1] i = i + 1
        elseif a == "--missing" then missingPath = args[i + 1] i = i + 1
        elseif a == "--check" then check = true
        else sql = a end
        i = i + 1
    end
    if not sql then
        io.stderr:write("use: luajit tools/quest_mobs.lua <ClassicDB.sql> [--routes dir]... [--out file] [--check] [--missing file]\n")
        return 2
    end
    if #routes == 0 then routes = QM.ROUTES end
    local QI = assert(loadfile("tools/import/questitems.lua"))("--lib")
    local texts = {}
    for _, dir in ipairs(routes) do
        for _, p in ipairs(ListLua(dir)) do texts[#texts + 1] = assert(ReadFile(p)) end
    end
    local steps, quests = QM.Steps(texts)
    local mobs, want = {}, {}
    local kills, items, itemSet, lootOf, drops = {}, {}, {}, {}, {}
    local ok, err = QI.Pass(sql, {
        quest_template = { cols = { "entry", "ReqCreatureOrGOId1", "ReqCreatureOrGOId2", "ReqCreatureOrGOId3",
            "ReqCreatureOrGOId4", "ReqItemId1", "ReqItemId2", "ReqItemId3", "ReqItemId4" }, fn = function(v)
            if quests[v.entry] then
                local k, it = {}, {}
                for n = 1, 4 do
                    local c = v["ReqCreatureOrGOId" .. n]
                    if c > 0 then k[#k + 1] = c end
                    local item = v["ReqItemId" .. n]
                    if item > 0 then it[#it + 1] = item itemSet[item] = true end
                end
                kills[v.entry], items[v.entry] = k, it
            end
        end } })
    if not ok then io.stderr:write(tostring(err) .. "\n") return 1 end
    -- (a second pass: the loot table comes before quest_template in the dump)
    ok, err = QI.Pass(sql, {
        creature_template = { cols = { "Entry", "LootId" }, fn = function(v)
            if v.LootId > 0 then lootOf[v.LootId] = lootOf[v.LootId] or {} table.insert(lootOf[v.LootId], v.Entry) end
        end },
        creature_loot_template = { cols = { "entry", "item", "ChanceOrQuestChance" }, fn = function(v)
            if itemSet[v.item] and v.ChanceOrQuestChance ~= 0 then
                drops[v.item] = drops[v.item] or {}
                table.insert(drops[v.item], { loot = v.entry, chance = math.abs(v.ChanceOrQuestChance) })
            end
        end },
    })
    if not ok then io.stderr:write(tostring(err) .. "\n") return 1 end
    -- kill targets first, then the mobs that drop the quest's items (best chance first), at most QM.MAX in all
    for q in pairs(quests) do
        local list, seen = {}, {}
        local function Add(c)
            if not seen[c] and #list < QM.MAX then seen[c] = true list[#list + 1] = c want[c] = true end
        end
        for _, c in ipairs(kills[q] or {}) do Add(c) end
        for _, item in ipairs(items[q] or {}) do
            local d = drops[item] or {}
            table.sort(d, function(a, b) if a.chance ~= b.chance then return a.chance > b.chance end return a.loot < b.loot end)
            for _, e in ipairs(d) do
                local cs = lootOf[e.loot] or {}
                table.sort(cs)
                for _, c in ipairs(cs) do Add(c) end
            end
        end
        if #list > 0 then mobs[q] = list end
    end
    local info, err2 = Creatures(sql, want)
    if not info then io.stderr:write(err2 .. "\n") return 1 end
    local text = QM.Text(mobs, info)
    local nq, nm = 0, 0
    for _ in pairs(mobs) do nq = nq + 1 end
    for _ in pairs(want) do nm = nm + 1 end
    if missingPath then
        local out = { "# objective steps with no npc / targetNpc whose quest has no creature to kill in the cmangos dump",
            "# (collect / use / Forever-only quests): the 3D view shows the step picture there. step | quest | text" }
        local seen = 0
        for _, s in ipairs(steps) do
            if not mobs[s.quest] then out[#out + 1] = ("%s | %d | %s"):format(s.id, s.quest, s.text) seen = seen + 1 end
        end
        local fh = assert(io.open(missingPath, "wb"))
        fh:write(table.concat(out, "\n") .. "\n")
        fh:close()
        print(("quest mobs: %d steps without a mob -> %s"):format(seen, missingPath))
    end
    if check then
        if ReadFile(outPath) ~= text then
            io.stderr:write(outPath .. " is out of date (run tools/quest_mobs.lua)\n")
            return 1
        end
        print(("quest mobs: up to date (%d quests, %d mobs, %d steps)"):format(nq, nm, #steps))
        return 0
    end
    local fh = assert(io.open(outPath, "wb"))
    fh:write(text)
    fh:close()
    print(("quest mobs: %d quests, %d mobs for %d steps -> %s"):format(nq, nm, #steps, outPath))
    return 0
end

if argv[1] == "--lib" then return QM end
os.exit(QM.Main(argv))

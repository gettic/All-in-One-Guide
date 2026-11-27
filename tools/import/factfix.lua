-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Writes the route test's quest-fact fixtures (plans\offline-tests\world\facts\<pack source name>.lua) for packs,
-- from LOCAL copies of two GPL sources, never from the pack itself (so a typo in the pack fails the route test):
--   QuestieDB Forever (..\.addons\QuestieDB): givers, enders, required level, prerequisites, race / class limits,
--     objective kinds; quest XP from its support\Forever\QuestXP\xpDB-traces.lua (measured on Forever), else
--     xpDB-classic.lua (Classic values).
--   CMaNGOS classic-db (a local ClassicDB.sql, read as TEXT): objective counts and the quest timer.
-- Forever-only quests have no XP there: the pack's own turn-in `xp` is used, tagged xpSrc = "pack" (not a fact).
-- The fixtures hold QuestieDB-derived facts, so they stay in plans\ (local only, never published).
-- Run (from the repository folder):
--   luajit tools/import/factfix.lua [--questiedb ../.addons/QuestieDB] [--sql plans/tools/data/cmangos/ClassicDB.sql]
--        [--out plans/offline-tests/world/facts] packs-src/x.lua ...
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2])
    or (arg and arg[0] and arg[0]:match("^(.*)[/\\]import[/\\][^/\\]+$")) or "tools"
local QS = assert(loadfile(toolsDir .. "/import/questie-spawns.lua"))("--lib", toolsDir)
local PC = assert(loadfile(toolsDir .. "/packcheck.lua"))("--lib", toolsDir)
local L = PC.Lib()
local FF = {}

local Q_START, Q_END, Q_REQLV, Q_QLV, Q_RACES, Q_CLASSES, Q_OBJ, Q_PREGROUP, Q_PRESINGLE = 2, 3, 4, 5, 6, 7, 10, 12, 13
-- race / class bit by name (alphabetical), turned into bit -> name below
local function ByBit(t) local out = {} for name, bit in pairs(t) do out[bit] = name end return out end
local RACES = ByBit({ Dwarf = 4, Gnome = 64, Human = 1, NightElf = 8, Orc = 2, Scourge = 16, Tauren = 32, Troll = 128 })
local CLASSES = ByBit({ DRUID = 1024, HUNTER = 4, MAGE = 128, PALADIN = 2, PRIEST = 16, ROGUE = 8, SHAMAN = 64,
    WARLOCK = 256, WARRIOR = 1 })

local function List(v) return type(v) == "table" and v or {} end

-- one race / class only (the low bits; Forever's extra race bits are ignored): its name, else nil
local function Single(mask, names, low)
    if type(mask) ~= "number" or mask <= 0 then return nil end
    local m = mask % low
    return names[m]
end

local function Numbers(t)
    local out = {}
    for _, v in ipairs(List(t)) do if type(v) == "number" then out[#out + 1] = v end end
    return out
end

-- The pack's quests and its turn-in xp values (expanded routes, all modes).
function FF.PackQuests(file)
    local pack, err = L.LoadData(file)
    if not pack then return nil, err end
    local want, xp, title = {}, {}, {}
    for _, r in ipairs(L.Expand(pack)) do
        for _, s in ipairs(r.steps) do
            if type(s.quest) == "number" then
                want[s.quest] = true
                if s.type == "turnin" and type(s.xp) == "number" then xp[s.quest] = s.xp end
                if type(s.qname) == "string" then title[s.quest] = s.qname end
            end
        end
    end
    return want, xp, title
end

-- quest XP: { [quest] = xp }. First QuestieDB's xpDB-traces.lua (measured on Forever: `QuestXP.db[id] = {lv, xp}`),
-- then xpDB-classic.lua (Classic values: `[id] = {lv, xp},`) for quests without a trace. The pack's own xp comes
-- last (FF.Build). (2026-11-27: the pack's guesses for Forever-only quests were often far off the traces.)
function FF.ReadXp(root)
    local out = {}
    local function Read(file, pattern)
        local fh = io.open(root .. "/support/Forever/QuestXP/" .. file, "rb")
        if not fh then return end
        for line in fh:lines() do
            local id, xp = line:match(pattern)
            id = tonumber(id)
            if id and out[id] == nil then out[id] = tonumber(xp) end
        end
        fh:close()
    end
    Read("xpDB-traces.lua", "^%s*QuestXP%.db%[(%d+)%] = {%-?%d+, (%d+)}")
    Read("xpDB-classic.lua", "^%s*%[(%d+)%] = {%-?%d+, (%d+)}")
    return out
end

-- One SQL tuple's values from position i (just after "("): strings unescaped, numbers as numbers.
local function Tuple(line, i)
    local vals, n = {}, #line
    while i <= n do
        local c = line:sub(i, i)
        if c == "'" then
            local j, buf = i + 1, {}
            while j <= n do
                local d = line:sub(j, j)
                if d == "\\" then buf[#buf + 1] = line:sub(j + 1, j + 1) j = j + 2
                elseif d == "'" then break
                else
                    local k = line:find("[\\']", j)
                    buf[#buf + 1] = line:sub(j, (k or n + 1) - 1)
                    j = k or n + 1
                end
            end
            vals[#vals + 1] = table.concat(buf)
            i = j + 1
        else
            local k = line:find("[,)]", i)
            vals[#vals + 1] = tonumber(line:sub(i, k - 1)) or line:sub(i, k - 1)
            i = k
        end
        c = line:sub(i, i)
        if c == ")" then return vals, i + 1 end
        i = i + 1   -- the comma
    end
    return vals, i
end

-- CMaNGOS quest_template: { [quest] = { items = { {id, n} }, mobs = { {id, n} }, limit = minutes } } for `want`.
function FF.ReadSql(path, want)
    local out = {}
    local fh = io.open(path, "rb")
    if not fh then return out end
    for line in fh:lines() do
        if line:find("^INSERT INTO `quest_template` VALUES") then
            local i = line:find("(", 30, true)
            while i do
                local id = tonumber(line:match("^(%d+)", i + 1))
                local vals
                vals, i = Tuple(line, i + 1)
                if id and want[id] then
                    local q = { items = {}, mobs = {}, limit = (vals[20] or 0) > 0 and math.max(1, math.floor(vals[20] / 60 + 0.5)) or nil }
                    for k = 0, 3 do
                        local item, cnt = vals[41 + k], vals[45 + k]
                        if type(item) == "number" and item > 0 then q.items[#q.items + 1] = { item, cnt } end
                        local mob, mcnt = vals[57 + k], vals[61 + k]
                        if type(mob) == "number" and mob ~= 0 then q.mobs[#q.mobs + 1] = { mob, mcnt } end
                    end
                    out[id] = q
                end
                i = line:find("(", i, true)
            end
        end
    end
    fh:close()
    return out
end

-- The fixture for one pack. Returns facts = { [quest] = fact }, stats
-- Known slips in the QuestieDB data, with the sources that disagree. Only for clear data errors (a fact that
-- contradicts itself), never to make a route pass. Each entry sets fields on the built fact.
FF.FIXES = {
    -- Prove Your Worth: QuestieDB Forever says needs 12 for a level 10 quest whose follow-up (422) needs 9;
    -- the Classic wiki and CMaNGOS both say 9
    [421] = { minLevel = 9 },
    -- Forever Cat Form chain: QuestieDB lists the faction versions of the step before as "all of" (98340 Horde
    -- + 98393 Alliance; 98731 / 98738 / 98739 the night elf, Windborne and tauren blessings), but each race only
    -- gets one of them (their race masks don't overlap), so one is enough
    [98405] = { after = {}, afterAny = { 98340, 98393 } },
    [98362] = { after = {}, afterAny = { 98731, 98738, 98739 } },
}

function FF.Build(want, packXp, titles, ents, xpDb, sql)
    local facts, st = {}, { quests = 0, missing = 0, xpPack = 0, xpNone = 0 }
    for q in pairs(want) do
        local e = ents.Quest[q]
        if not e then
            st.missing = st.missing + 1
        else
            st.quests = st.quests + 1
            local f = { title = titles[q] or ("Quest " .. q) }
            local req = e[Q_REQLV]
            if type(req) == "number" and req > 1 then f.minLevel = req end
            if type(e[Q_QLV]) == "number" and e[Q_QLV] > 0 then f.level = e[Q_QLV] end
            local starts, ends = Numbers(List(e[Q_START])[1]), Numbers(List(e[Q_END])[1])
            if #starts == 1 then f.giver = starts[1] elseif #starts > 1 then f.givers = starts end
            if #ends == 1 then f.ender = ends[1] elseif #ends > 1 then f.enders = ends end
            local group, single = Numbers(e[Q_PREGROUP]), Numbers(e[Q_PRESINGLE])
            if #group > 0 then f.after = group end
            if #single > 0 then f.afterAny = single end
            f.race = Single(e[Q_RACES], RACES, 256)
            f.class = Single(e[Q_CLASSES], CLASSES, 2048)
            -- objectives: counts from CMaNGOS when it has the quest; else one per QuestieDB objective, count unknown
            local obj, c = {}, sql[q]
            if c then
                for _, m in ipairs(c.mobs) do obj[#obj + 1] = { type = "monster", text = "Objective", need = m[2], needSrc = "cmangos" } end
                for _, it in ipairs(c.items) do obj[#obj + 1] = { type = "item", text = "Objective", need = it[2], needSrc = "cmangos" } end
                f.timeLimit = c.limit
            else
                for _, group_ in ipairs({ 1, 2, 3, 5 }) do
                    for _ in ipairs(List(List(e[Q_OBJ])[group_])) do
                        obj[#obj + 1] = { type = "monster", text = "Objective", need = 1, needUnknown = true }
                    end
                end
            end
            f.objectives = obj
            if xpDb[q] then f.xp = xpDb[q]
            elseif packXp[q] then f.xp, f.xpSrc = packXp[q], "pack" st.xpPack = st.xpPack + 1
            else st.xpNone = st.xpNone + 1 end
            for k, v in pairs(FF.FIXES[q] or {}) do f[k] = v end
            facts[q] = f
        end
    end
    return facts, st
end

local function Val(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "table" then
        local out = {}
        if v[1] ~= nil then
            for i = 1, #v do out[i] = Val(v[i]) end
            return "{ " .. table.concat(out, ", ") .. " }"
        end
        for name in pairs(v) do out[#out + 1] = name end
        table.sort(out)  -- stable field order in the fixture file
        for i, name in ipairs(out) do out[i] = name .. " = " .. Val(v[name]) end
        return "{ " .. table.concat(out, ", ") .. " }"
    end
    return tostring(v)
end

function FF.Text(facts, src, st)
    local ids = {}
    for q in pairs(facts) do ids[#ids + 1] = q end
    table.sort(ids)
    local L_ = {
        "-- Quest facts for " .. src .. " (route test fixture), written by tools\\import\\factfix.lua; do not edit.",
        "-- From QuestieDB Forever (GPL-3.0) and CMaNGOS classic-db (GPL-3.0); local only (plans\\), never published.",
        ("-- %d quests; %d not in QuestieDB (not checked); xp from the pack (xpSrc = \"pack\"): %d; no xp: %d"):format(
            st.quests, st.missing, st.xpPack, st.xpNone),
        "return {",
    }
    for _, q in ipairs(ids) do
        local f, parts = facts[q], {}
        for _, k in ipairs({ "title", "level", "minLevel", "giver", "givers", "ender", "enders", "after", "afterAny", "race",
            "class", "xp", "xpSrc", "timeLimit", "objectives" }) do
            if f[k] ~= nil then parts[#parts + 1] = k .. " = " .. Val(f[k]) end
        end
        L_[#L_ + 1] = ("    [%d] = { %s },"):format(q, table.concat(parts, ", "))
    end
    L_[#L_ + 1] = "}"
    return table.concat(L_, "\n") .. "\n"
end

function FF.Main(argv)
    local opts = { questiedb = "../.addons/QuestieDB", sql = "plans/tools/data/cmangos/ClassicDB.sql",
        out = "plans/offline-tests/world/facts", files = {} }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--questiedb" or a == "--sql" or a == "--out" then opts[a:sub(3)] = argv[i + 1] i = i + 2
        else opts.files[#opts.files + 1] = a i = i + 1 end
    end
    local all, per = {}, {}
    for _, f in ipairs(opts.files) do
        local want, xp, titles = FF.PackQuests(f)
        if not want then print("ERROR " .. f .. ": " .. tostring(xp)) return 1 end
        per[#per + 1] = { file = f, want = want, xp = xp, titles = titles }
        for q in pairs(want) do all[q] = true end
    end
    local fields = { S = true, [Q_START] = true, [Q_END] = true, [Q_OBJ] = true, [Q_PREGROUP] = true,
        [Q_PRESINGLE] = true, [Q_REQLV] = true, [Q_QLV] = true, [Q_RACES] = true, [Q_CLASSES] = true }
    local ents, stats = QS.ReadEntities(opts.questiedb .. "/QuestieDB_Forever.toc", { Quest = { ids = all, fields = fields } })
    if not ents then print("ERROR " .. tostring(stats)) return 1 end
    local xpDb = FF.ReadXp(opts.questiedb)
    local sql = FF.ReadSql(opts.sql, all)
    for _, p in ipairs(per) do
        local src = p.file:match("([^/\\]+)%.lua$")
        local facts, st = FF.Build(p.want, p.xp, p.titles, ents, xpDb, sql)
        local path = opts.out .. "/" .. src .. ".lua"
        local fh = assert(io.open(path, "wb"))
        fh:write(FF.Text(facts, src, st))
        fh:close()
        print(("%s: %d quests, %d not in QuestieDB, xp from pack %d, no xp %d -> %s"):format(
            src, st.quests, st.missing, st.xpPack, st.xpNone, path))
    end
    return 0
end

if args[1] == "--lib" then return FF end
os.exit(FF.Main(args))

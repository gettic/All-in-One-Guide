-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Guide-data audit against a LOCAL QuestieDB copy (never downloaded by this tool). Checks every accept, turn-in,
-- objective and trainer / flight / inn step of our packs:
--   (a) the quest exists and the step's NPC really starts / ends it      (b) the point is near the NPC's spawn
--   (c) the quest's required level <= the route's estimated level         (d) prerequisite quests come earlier
--   (e) race / class limits fit the step's conditions                     (f) objective mobs / items exist and
--       the mobs (or the items' droppers) spawn near the objective point
-- and lists every NPC coordinate with its second-source state ("questie only" / "confirmed by 2 sources").
-- The output holds QuestieDB-derived facts, so it is written to plans\ (local only, gitignored) and never published
-- (licence ruling plans\bug-first-step\licence-questie.md). Names and texts are never read.
--
-- Run (from the repository folder):
--   luajit tools/import/questie-audit.lua [--questiedb ../.addons/QuestieDB] [--flavor Forever]
--        [--out plans/bug-first-step/audit.md] [--csv plans/bug-first-step/audit-coords.csv] [packs-src/x.lua ...]
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2])
    or (arg and arg[0] and arg[0]:match("^(.*)[/\\]import[/\\][^/\\]+$")) or "tools"
local QS = assert(loadfile(toolsDir .. "/import/questie-spawns.lua"))("--lib", toolsDir)
local PC = assert(loadfile(toolsDir .. "/packcheck.lua"))("--lib", toolsDir)
local CM = assert(loadfile(toolsDir .. "/import/cmangos.lua"))()
local L = PC.Lib()
local A = {}

A.TALK_WARN, A.TALK_FAIL = PC.NPC_WARN, PC.NPC_FAIL   -- yd
A.OBJ_WARN, A.OBJ_FAIL = 150, 400                     -- yd: mobs spread over an area
-- QuestieDB field numbers (src\meta\*Meta.lua)
local Q_START, Q_END, Q_REQLV, Q_RACES, Q_CLASSES, Q_OBJ, Q_PREGROUP, Q_PRESINGLE, Q_SRCITEMS =
    2, 3, 4, 6, 7, 10, 12, 13, 21   -- 5 = questLevel (not used)
local N_SPAWNS, N_STARTS, N_ENDS, N_FLAGS = 7, 10, 11, 15
local I_NPCDROPS, I_OBJDROPS = 2, 3
local O_SPAWNS = 4
local NPCFLAG = { train = 4, getfp = 3, sethearth = 7 }   -- bit numbers: trainer 16, flight master 8, innkeeper 128
local RACEBIT = { Human = 0, Orc = 1, Dwarf = 2, NightElf = 3, Scourge = 4, Tauren = 5, Gnome = 6, Troll = 7,
    ["Skyborne(A)"] = 32, ["Skyborne(H)"] = 33 }
local FACTION_RACES = { Alliance = { "Human", "Dwarf", "NightElf", "Gnome", "Skyborne(A)" },
    Horde = { "Orc", "Scourge", "Tauren", "Troll", "Skyborne(H)" } }
local CLASSBIT = { WARRIOR = 0, PALADIN = 1, HUNTER = 2, ROGUE = 3, PRIEST = 4, SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 10 }
local ALL_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function Bit(mask, b) return math.floor(mask / 2 ^ b) % 2 == 1 end
local function List(v) return type(v) == "table" and v or {} end
local function Has(list, x)
    for _, v in ipairs(List(list)) do if v == x then return true end end
    return false
end
local function Add(set, list) for _, v in ipairs(List(list)) do if type(v) == "number" then set[v] = true end end end

-- objective entries: { { id, text?, ... }, ... }; kill credit: { { { ids }, baseId, text }, ... }
local function ObjIds(group, out)
    for _, e in ipairs(List(group)) do
        if type(e) == "table" then
            if type(e[1]) == "number" then out[e[1]] = true
            elseif type(e[1]) == "table" then Add(out, e[1]) if type(e[2]) == "number" then out[e[2]] = true end end
        elseif type(e) == "number" then out[e] = true end
    end
    return out
end

-- The races / classes a step is shown to (pack faction + simple `race=` / `class=` / `faction=` in cond).
local function Audience(pack, s)
    local cond = s.cond or ""
    local complex = cond:find(" or ") or cond:find("not ") or cond:find("[!~]=")
    local faction = cond:match("faction=(%a+)") or pack.faction
    -- every `key=a,b` in an and-only cond narrows the set (includes join conds with "and")
    local function Narrow(key, base)
        if complex then return base end
        local set
        for v in cond:gmatch(key .. "=([%w,]+)") do
            local here = {}
            for x in v:gmatch("[^,]+") do here[x] = true end
            if not set then set = here
            else for x in pairs(set) do if not here[x] then set[x] = nil end end end
        end
        if not set then return base end
        local out = {}
        for _, x in ipairs(base) do if set[x] then out[#out + 1] = x end end
        for x in pairs(set) do
            local known = false
            for _, y in ipairs(base) do if y == x then known = true end end
            if not known and not next(out) then out[#out + 1] = x end
        end
        return out
    end
    local base = FACTION_RACES[faction] or {}
    if not FACTION_RACES[faction] then
        for _, f in pairs(FACTION_RACES) do for _, r in ipairs(f) do base[#base + 1] = r end end
    end
    local races = Narrow("race", base)
    local hasRace = not complex and cond:find("race=")
    -- no race in cond: the pack's entry races (who starts the pack)
    if not hasRace and pack.entry then
        local er = {}
        for x in ((pack.entry or ""):match("race=([%w,]+)") or ""):gmatch("[^,]+") do er[#er + 1] = x end
        if #er > 0 then races = er end
    end
    local classes = Narrow("class", ALL_CLASSES)
    return races, classes, complex
end

-- true when an and-only cond asks for two different single values of the same key (never shown)
local function Contradicts(cond)
    if not cond or cond:find(" or ") or cond:find("not ") then return false end
    for _, key in ipairs({ "race", "class", "faction" }) do
        local sets = {}
        for v in cond:gmatch(key .. "=([%w,]+)") do sets[#sets + 1] = v end
        if #sets > 1 then
            local common = {}
            for x in sets[1]:gmatch("[^,]+") do common[x] = true end
            for k = 2, #sets do
                local here = {}
                for x in sets[k]:gmatch("[^,]+") do if common[x] then here[x] = true end end
                common = here
            end
            if not next(common) then return true end
        end
    end
    return false
end

local function Spawns(raw, areaMaps)
    local st = {}
    local flat = QS.Flatten(raw, areaMaps, st)
    local pts = {}
    for k = 1, #flat, 3 do pts[#pts + 1] = { flat[k], flat[k + 1], flat[k + 2] } end
    return pts
end

-- nearest spawn of any id in `ids` (set) on the step's map: distance in yd, x, y, id; or nil, { other maps }
local function Nearest(s, ids, spawnsOf, sizes)
    local size = sizes[s.map]
    local best, bx, by, bid
    local other = {}
    for id in pairs(ids) do
        for _, p in ipairs(spawnsOf(id)) do
            if p[1] == s.map and size then
                local d = math.sqrt(((s.x - p[2]) / 100 * size[1]) ^ 2 + ((s.y - p[3]) / 100 * size[2]) ^ 2)
                if not best or d < best then best, bx, by, bid = d, p[2], p[3], id end
            else
                other[p[1]] = true
            end
        end
    end
    if best then return best, bx, by, bid end
    local ml = {}
    for m in pairs(other) do ml[#ml + 1] = m end
    table.sort(ml)
    return nil, ml
end

function A.Run(opts)
    local db = opts.questiedb
    local toc = db .. "/QuestieDB_" .. opts.flavor .. ".toc"
    local areaMaps = assert(QS.AreaMaps(db .. "/support/" .. opts.flavor .. "/Zones/areaIdToUiMapId.lua"))
    local sizes = PC.MapSizes()
    -- packs
    local packs = {}
    local qids, iids = {}, {}
    for _, f in ipairs(opts.files) do
        local t = L.LoadData(f)
        if L.IsPack(t) then
            local routes = L.Expand(t)
            packs[#packs + 1] = { file = f, pack = t, routes = routes }
            for _, r in ipairs(routes) do
                for _, s in ipairs(r.steps) do
                    if type(s.quest) == "number" then qids[s.quest] = true end
                    if type(s.item) == "number" then iids[s.item] = true end
                end
            end
        end
    end
    -- pass 1: quests
    local stats = { decodeError = 0 }
    local ents, st, meta = QS.ReadEntities(toc, { Quest = { ids = qids, fields = { [Q_START] = true, [Q_END] = true,
        [Q_OBJ] = true, [Q_PREGROUP] = true, [Q_PRESINGLE] = true, [Q_SRCITEMS] = true, S = true } } })
    assert(ents, st)
    stats.decodeError = stats.decodeError + st.decodeError
    local quests = ents.Quest
    -- pass 2: items (step items + quest objective / source items)
    for _, q in pairs(quests) do
        ObjIds(List(q[Q_OBJ])[3], iids)
        Add(iids, q[Q_SRCITEMS])
    end
    ents, st = QS.ReadEntities(toc, { Item = { ids = iids, fields = { [I_NPCDROPS] = true, [I_OBJDROPS] = true, S = true } } })
    stats.decodeError = stats.decodeError + st.decodeError
    local items = ents.Item
    -- pass 3: NPCs and objects
    local nids, oids = {}, {}
    for _, p in ipairs(packs) do
        for _, r in ipairs(p.routes) do
            for _, s in ipairs(r.steps) do
                if type(s.npc) == "number" then nids[s.npc] = true end
                if type(s.targetNpc) == "number" then nids[s.targetNpc] = true end
            end
        end
    end
    for _, q in pairs(quests) do
        Add(nids, List(q[Q_START])[1]) Add(nids, List(q[Q_END])[1])
        Add(oids, List(q[Q_START])[2]) Add(oids, List(q[Q_END])[2])
        local o = List(q[Q_OBJ])
        ObjIds(o[1], nids) ObjIds(o[5], nids) ObjIds(o[2], oids)
    end
    for _, it in pairs(items) do Add(nids, it[I_NPCDROPS]) Add(oids, it[I_OBJDROPS]) end
    -- second source (CMaNGOS classic-db, local SQL dump, optional): then every NPC's spawns are read for the fit
    local cm, fits
    local cfh = opts.cmangos and io.open(opts.cmangos, "rb")
    if cfh then
        cfh:close()
        cm = assert(CM.Read(opts.cmangos))
        nids = setmetatable({}, { __index = function() return true end })
    end
    ents, st = QS.ReadEntities(toc, {
        Npc = { ids = nids, fields = { [N_SPAWNS] = true, [N_STARTS] = true, [N_ENDS] = true, S = true } },
        Object = { ids = oids, fields = { [O_SPAWNS] = true } } })
    stats.decodeError = stats.decodeError + st.decodeError
    local npcs, objects = ents.Npc, ents.Object
    if cm then
        local all = {}
        for id, e in pairs(npcs) do
            local pts = Spawns(e[N_SPAWNS], areaMaps)
            if #pts > 0 then all[id] = pts end
        end
        fits = CM.Calibrate(all, cm.creatures)
    end
    stats.fits = fits
    local spawnCache = {}
    local function NpcSpawns(id)
        local k = "n" .. id
        if not spawnCache[k] then spawnCache[k] = Spawns(npcs[id] and npcs[id][N_SPAWNS], areaMaps) end
        return spawnCache[k]
    end
    local function ObjSpawns(id)
        local k = "o" .. id
        if not spawnCache[k] then spawnCache[k] = Spawns(objects[id] and objects[id][O_SPAWNS], areaMaps) end
        return spawnCache[k]
    end

    -- quest XP (support\<flavor>\QuestXP\xpDB-classic.lua: "[id] = {level, xp}"; read as text, never run)
    local xpToNext = PC.Facts().xpToNext.value
    local xpOf = {}
    local xfh = io.open(db .. "/support/" .. opts.flavor .. "/QuestXP/xpDB-classic.lua", "rb")
    if xfh then
        for line in xfh:lines() do
            local id, xp = line:match("^%s*%[(%d+)%]%s*=%s*{%s*%-?%d+%s*,%s*(%d+)")
            if id and qids[tonumber(id)] then xpOf[tonumber(id)] = tonumber(xp) end
        end
        xfh:close()
    end
    -- the checks
    local results, coords, givers = {}, {}, {}
    for _, p in ipairs(packs) do
        local pack = p.pack
        local res = { file = p.file, items = {}, counts = {} }
        results[#results + 1] = res
        local function F(sev, check, where, msg)
            res.items[#res.items + 1] = { sev = sev, check = check, where = where, msg = msg }
            local k = check .. " " .. sev
            res.counts[k] = (res.counts[k] or 0) + 1
        end
        local lv = pack.levels
        local start = tonumber(type(lv) == "table" and lv[1] or type(lv) == "string" and lv:match("^(%d+)") or nil) or 1
        for _, r in ipairs(p.routes) do
            local turnedIn, turnedInLater = {}, {}
            for i, s in ipairs(r.steps) do
                if s.type == "turnin" and type(s.quest) == "number" then turnedInLater[s.quest] = turnedInLater[s.quest] or i end
            end
            local level = start
            local xpLv, xpHave = start, 0
            for i, s in ipairs(r.steps) do
                local where = r.id .. " #" .. i .. " " .. tostring(s.id)
                if Contradicts(s.cond) then
                    F("INFO", "e", where, "conditions contradict (" .. s.cond .. "): the step is never shown")
                    goto continue
                end
                if (s.type == "level" or s.type == "grind") and type(s.level) == "number" and s.level > level then level = s.level end
                local est = level
                if type(s.minLevel) == "number" and s.minLevel > est then est = s.minLevel end
                local cl = tonumber((s.cond or ""):match("level>=(%d+)"))
                if cl and cl > est then est = cl end
                local q = type(s.quest) == "number" and quests[s.quest] or nil
                local isQuestStep = s.type == "accept" or s.type == "turnin" or (s.type == "objective" and s.quest)
                -- (a) quest exists, right giver / ender
                if isQuestStep and type(s.quest) == "number" and not q then
                    F("ERROR", "a", where, ("quest %d is not in QuestieDB %s"):format(s.quest, opts.flavor))
                end
                if q and s.type == "accept" then
                    local st2 = List(q[Q_START])
                    if type(s.npc) == "number" then
                        if not Has(st2[1], s.npc) then
                            F("ERROR", "a", where, ("npc %d doesn't start quest %d (starters: npc %s%s%s)"):format(s.npc, s.quest,
                                table.concat(List(st2[1]), ","),
                                #List(st2[2]) > 0 and ", object " .. table.concat(st2[2], ",") or "",
                                #List(st2[3]) > 0 and ", item " .. table.concat(st2[3], ",") or ""))
                        end
                    elseif not s.from then
                        F("INFO", "a", where, ("accept without npc (quest %d starters: npc %s)"):format(s.quest, table.concat(List(st2[1]), ",")))
                    end
                end
                if q and s.type == "turnin" and type(s.npc) == "number" then
                    local en = List(q[Q_END])
                    if not Has(en[1], s.npc) then
                        F("ERROR", "a", where, ("npc %d doesn't end quest %d (enders: npc %s%s)"):format(s.npc, s.quest,
                            table.concat(List(en[1]), ","), #List(en[2]) > 0 and ", object " .. table.concat(en[2], ",") or ""))
                    end
                end
                -- trainer / flight master / innkeeper flag
                if NPCFLAG[s.type] and type(s.npc) == "number" and npcs[s.npc] and type(npcs[s.npc][N_FLAGS]) == "number"
                    and not Bit(npcs[s.npc][N_FLAGS], NPCFLAG[s.type]) then
                    F("WARN", "a", where, ("npc %d has no %s flag in QuestieDB"):format(s.npc,
                        s.type == "train" and "trainer" or s.type == "getfp" and "flight master" or "innkeeper"))
                end
                -- quest giver / ender: do QuestieDB and cmangos both say so?
                if q and cm and (s.type == "accept" or s.type == "turnin") and type(s.npc) == "number" then
                    local qOk = Has(List(q[s.type == "accept" and Q_START or Q_END])[1], s.npc)
                    local rel = (s.type == "accept" and cm.cStart or cm.cEnd)[s.quest]
                    local cOk = rel and rel[s.npc] or false
                    local others = {}
                    for id in pairs(rel or {}) do if id ~= s.npc then others[#others + 1] = id end end
                    table.sort(others)
                    givers[#givers + 1] = { p.file, where, s.type, s.quest, s.npc,
                        qOk and cOk and "confirmed by 2 sources (questie + cmangos)" or qOk and "questie only"
                            or cOk and "cmangos only" or "neither source", table.concat(others, " ") }
                end
                -- (b) talk steps: distance to the NPC, and the coordinate's second-source state
                if PC.TALK[s.type] and type(s.npc) == "number" and s.map and s.x and s.y then
                    local d, bx, by = Nearest(s, { [s.npc] = true }, NpcSpawns, sizes)
                    if not npcs[s.npc] then
                        F("WARN", "b", where, ("npc %d is not in QuestieDB"):format(s.npc))
                    elseif not d and sizes[s.map] then
                        F("WARN", "b", where, ("npc %d has no spawn on map %d (spawns on map %s)"):format(s.npc, s.map, table.concat(bx, ", ")))
                    elseif d and d > A.TALK_FAIL then
                        F("ERROR", "b", where, ("npc %d is %.0f yd from its spawn %.2f,%.2f"):format(s.npc, d, bx, by))
                    elseif d and d > A.TALK_WARN then
                        F("WARN", "b", where, ("npc %d is %.0f yd from its spawn %.2f,%.2f"):format(s.npc, d, bx, by))
                    end
                    if not d then d = nil end
                    -- cmangos: nearest spawn of the NPC, turned into zone percent with the map's fit
                    local cd
                    if cm and sizes[s.map] then
                        local size = sizes[s.map]
                        for _, pt in ipairs(CM.ZonePoints(cm, fits, s.npc, s.map)) do
                            local dd = math.sqrt(((s.x - pt[1]) / 100 * size[1]) ^ 2 + ((s.y - pt[2]) / 100 * size[2]) ^ 2)
                            if not cd or dd < cd then cd = dd end
                        end
                    end
                    local qAgree = d and d <= A.TALK_WARN
                    local cAgree = cd and cd <= A.TALK_WARN
                    local state
                    if not sizes[s.map] then state = "map size unknown"
                    elseif qAgree and cAgree then state = "confirmed by 2 sources (questie + cmangos)"
                    elseif qAgree then state = cm and (fits and fits[s.map] and "questie only" or "questie only (no cmangos fit for this map)") or "questie only"
                    elseif cAgree then state = "cmangos only"
                    else state = "no source agrees" end
                    coords[#coords + 1] = { p.file, where, s.type, s.npc, s.map, s.x, s.y, tostring(s.src), state,
                        d and ("%.0f"):format(d) or "", cd and ("%.0f"):format(cd) or "" }
                end
                -- (c) level
                -- est = what the route guarantees (level steps, minLevel, level>= in cond); xpLv = what quest XP
                -- alone gives (a floor: kills add more). Unguarded and above both by 3+ = error.
                local need = q and s.type == "accept" and type(q[Q_REQLV]) == "number" and q[Q_REQLV] or nil
                if need and need > est and need > xpLv then
                    F(need - math.max(est, xpLv) > 2 and "ERROR" or "WARN", "c", where,
                        ("quest %d needs level %d; the route guarantees %d, quest XP alone gives %d (add minLevel %d or a level step)")
                            :format(s.quest, need, est, xpLv, need))
                end
                -- (d) prerequisites
                if q and s.type == "accept" then
                    local function State(pq)
                        if turnedIn[pq] then return "ok" end
                        if turnedInLater[pq] then return "later (#" .. turnedInLater[pq] .. ")" end
                        return "not in this route"
                    end
                    for _, pq in ipairs(List(q[Q_PREGROUP])) do
                        local stt = State(pq)
                        if stt ~= "ok" then
                            F(stt:find("later") and "ERROR" or "WARN", "d", where,
                                ("quest %d needs quest %d first: %s"):format(s.quest, pq, stt))
                        end
                    end
                    local single = List(q[Q_PRESINGLE])
                    if #single > 0 then
                        local any, states = false, {}
                        for _, pq in ipairs(single) do
                            local stt = State(pq)
                            if stt == "ok" then any = true end
                            states[#states + 1] = pq .. " " .. stt
                        end
                        if not any then
                            F(table.concat(states):find("later") and "ERROR" or "WARN", "d", where,
                                ("quest %d needs one of: %s"):format(s.quest, table.concat(states, "; ")))
                        end
                    end
                end
                -- (e) race / class
                if q and s.type == "accept" then
                    local races, classes, complex = Audience(pack, s)
                    local rm, cmask = q[Q_RACES], q[Q_CLASSES]
                    if type(rm) == "number" and rm > 0 then
                        local ok, bad = {}, {}
                        for _, rc in ipairs(races) do
                            local b = RACEBIT[rc]
                            if b and Bit(rm, b) then ok[#ok + 1] = rc elseif b then bad[#bad + 1] = rc end
                        end
                        if #ok == 0 then
                            F("ERROR", "e", where, ("quest %d is for other races; the step is shown to %s"):format(s.quest, table.concat(races, ",")))
                        elseif #bad > 0 and not complex then
                            F("WARN", "e", where, ("quest %d is not for %s (add a race condition)"):format(s.quest, table.concat(bad, ",")))
                        end
                    end
                    if type(cmask) == "number" and cmask > 0 then
                        local ok, bad = {}, {}
                        for _, c in ipairs(classes) do
                            local b = CLASSBIT[c]
                            if b and Bit(cmask, b) then ok[#ok + 1] = c elseif b then bad[#bad + 1] = c end
                        end
                        if #ok == 0 then
                            F("ERROR", "e", where, ("quest %d is for other classes; the step is shown to %s"):format(s.quest, table.concat(classes, ",")))
                        elseif #bad > 0 and not complex then
                            F("WARN", "e", where, ("quest %d is not for %s (add a class condition)"):format(s.quest, table.concat(bad, ",")))
                        end
                    end
                end
                -- (f) objectives
                if s.type == "objective" then
                    local o = q and List(q[Q_OBJ]) or {}
                    local mobs, objs, qitems = {}, {}, {}
                    ObjIds(o[1], mobs) ObjIds(o[5], mobs) ObjIds(o[2], objs) ObjIds(o[3], qitems)
                    if q then Add(qitems, q[Q_SRCITEMS]) end
                    if type(s.item) == "number" then
                        if not items[s.item] then
                            F("WARN", "f", where, ("item %d is not in QuestieDB"):format(s.item))
                        elseif q and not qitems[s.item] then
                            F("WARN", "f", where, ("item %d is not an objective of quest %d"):format(s.item, s.quest))
                        end
                    end
                    -- the item droppers count as objective mobs / objects
                    local wantItems = {}
                    if type(s.item) == "number" then wantItems[s.item] = true else for it in pairs(qitems) do wantItems[it] = true end end
                    for it in pairs(wantItems) do
                        if items[it] then Add(mobs, items[it][I_NPCDROPS]) Add(objs, items[it][I_OBJDROPS]) end
                    end
                    if type(s.npc) == "number" then
                        if not npcs[s.npc] then
                            F("WARN", "f", where, ("mob %d is not in QuestieDB"):format(s.npc))
                        elseif q and next(mobs) and not mobs[s.npc] then
                            F("WARN", "f", where, ("mob %d is not an objective of quest %d nor drops its items"):format(s.npc, s.quest))
                        end
                    end
                    if s.map and s.x and s.y and sizes[s.map] then
                        local set = type(s.npc) == "number" and { [s.npc] = true } or mobs
                        local d, bx, by, bid = Nearest(s, set, NpcSpawns, sizes)
                        local kind = "mob"
                        if not d and type(s.npc) ~= "number" and next(objs) then
                            d, bx, by, bid = Nearest(s, objs, ObjSpawns, sizes)
                            kind = "object"
                        end
                        if d then
                            if d > A.OBJ_FAIL then
                                F("ERROR", "f", where, ("nearest %s %d spawn is %.0f yd away (%.2f,%.2f)"):format(kind, bid, d, bx, by))
                            elseif d > A.OBJ_WARN then
                                F("WARN", "f", where, ("nearest %s %d spawn is %.0f yd away (%.2f,%.2f)"):format(kind, bid, d, bx, by))
                            end
                        elseif next(set) or next(objs) then
                            F("WARN", "f", where, ("no objective mob / object spawns on map %d"):format(s.map))
                        end
                    end
                end
                if s.type == "turnin" and type(s.quest) == "number" then
                    -- XP once per quest, and not for class / race-only steps (not everyone gets it)
                    local c = s.cond or ""
                    if not turnedIn[s.quest] and not c:find("class=") and not c:find("race=") then
                        xpHave = xpHave + (xpOf[s.quest] or 0)
                    end
                    turnedIn[s.quest] = true
                    while xpToNext[xpLv] and xpHave >= xpToNext[xpLv] do
                        xpHave = xpHave - xpToNext[xpLv]
                        xpLv = xpLv + 1
                    end
                end
                ::continue::
            end
        end
    end
    return results, coords, stats, meta, givers
end

local CHECKS = { "a", "b", "c", "d", "e", "f" }
local CHECK_NAME = { a = "(a) quest / giver / ender", b = "(b) NPC distance", c = "(c) level", d = "(d) prerequisites",
    e = "(e) race / class", f = "(f) objectives" }

function A.Markdown(results, coords, meta, date, givers, fits)
    givers = givers or {}
    local o = {}
    o[#o + 1] = "# Guide-data audit against QuestieDB " .. tostring(meta.Flavor) .. " (" .. date .. ")"
    o[#o + 1] = ""
    o[#o + 1] = "Made by `tools/import/questie-audit.lua` from the local QuestieDB copy (version " .. tostring(meta.Version)
        .. ", build " .. tostring(meta["BUILD-COMMIT"]) .. "). LOCAL ONLY: holds QuestieDB-derived facts, never publish"
        .. " (plans\\bug-first-step\\licence-questie.md). Distances use estimated Classic map sizes (tools\\data\\mapsizes.lua)."
    o[#o + 1] = "Limits: talk steps warn > " .. A.TALK_WARN .. " yd, error > " .. A.TALK_FAIL .. " yd; objective points warn > "
        .. A.OBJ_WARN .. " yd, error > " .. A.OBJ_FAIL .. " yd from the nearest mob / dropper spawn. Level (c) error when the quest needs"
        .. " 3+ levels more than the route's estimate (last level step, minLevel, `level>=` in cond). (d) error = the"
        .. " prerequisite is turned in later in the route; warning = not in this route (may come from another pack)."
    o[#o + 1] = ""
    o[#o + 1] = "## Summary (errors / warnings)"
    o[#o + 1] = ""
    local head = { "| pack |" }
    for _, c in ipairs(CHECKS) do head[#head + 1] = " " .. CHECK_NAME[c] .. " |" end
    o[#o + 1] = table.concat(head)
    o[#o + 1] = "|---|" .. ("---|"):rep(#CHECKS)
    for _, r in ipairs(results) do
        local row = { "| " .. r.file:gsub("^packs%-src/", "") .. " |" }
        for _, c in ipairs(CHECKS) do
            row[#row + 1] = (" %d / %d |"):format(r.counts[c .. " ERROR"] or 0, r.counts[c .. " WARN"] or 0)
        end
        o[#o + 1] = table.concat(row)
    end
    local function Count(list, col)
        local cs, ks = {}, {}
        for _, c in ipairs(list) do cs[c[col]] = (cs[c[col]] or 0) + 1 end
        for k in pairs(cs) do ks[#ks + 1] = k end
        table.sort(ks)
        for _, k in ipairs(ks) do o[#o + 1] = ("- %s: %d"):format(k, cs[k]) end
    end
    local function Short(f) return (f:gsub("^packs%-src/", "")) end
    -- second sources
    o[#o + 1] = ""
    o[#o + 1] = "## Second source: CMaNGOS classic-db"
    o[#o + 1] = ""
    if not fits then
        o[#o + 1] = "Not on this PC (plans\\tools\\data\\cmangos\\ClassicDB.sql): coordinates and givers are QuestieDB only."
    else
        o[#o + 1] = "Local copy of https://github.com/cmangos/classic-db (GPL-3.0; Vanilla 1.12 data, so WoW Forever changes show up as"
            .. " disagreements), parsed as text. Its world coordinates are turned into map percent with a per-map linear fit made from"
            .. " NPCs both sources have once (pairs / rms error in map %):"
        o[#o + 1] = ""
        local ms = {}
        for m in pairs(fits) do ms[#ms + 1] = m end
        table.sort(ms)
        local parts = {}
        for _, m in ipairs(ms) do parts[#parts + 1] = ("%d: %d / %.2f"):format(m, fits[m].n, fits[m].rms) end
        o[#o + 1] = table.concat(parts, "; ")
    end
    -- coordinate states
    o[#o + 1] = ""
    o[#o + 1] = "## NPC coordinates: who agrees within " .. A.TALK_WARN .. " yd (full list: audit-coords.csv)"
    o[#o + 1] = ""
    Count(coords, 9)
    o[#o + 1] = ""
    o[#o + 1] = "Rows not confirmed by 2 sources (pack step: npc, map, our x,y, src -> questie yd / cmangos yd, state):"
    o[#o + 1] = ""
    for _, c in ipairs(coords) do
        if not c[9]:find("^confirmed") then
            o[#o + 1] = ("- %s %s: npc %d, map %d, %s,%s, %s -> %s / %s, %s"):format(Short(c[1]), c[2], c[4], c[5], c[6], c[7], c[8],
                c[10] ~= "" and c[10] or "-", c[11] ~= "" and c[11] or "-", c[9])
        end
    end
    -- givers
    o[#o + 1] = ""
    o[#o + 1] = "## Quest starters / enders: who agrees"
    o[#o + 1] = ""
    if #givers == 0 then
        o[#o + 1] = "No second source on this PC."
    else
        Count(givers, 6)
        o[#o + 1] = ""
        o[#o + 1] = "Rows not confirmed by 2 sources (pack step: type quest npc, state, cmangos names npc ...):"
        o[#o + 1] = ""
        for _, g in ipairs(givers) do
            if not g[6]:find("^confirmed") then
                o[#o + 1] = ("- %s %s: %s %d npc %d, %s%s"):format(Short(g[1]), g[2], g[3], g[4], g[5], g[6],
                    g[7] ~= "" and (", cmangos: npc " .. g[7]) or "")
            end
        end
    end
    -- findings per pack
    for _, r in ipairs(results) do
        o[#o + 1] = ""
        o[#o + 1] = "## " .. r.file:gsub("^packs%-src/", "")
        if #r.items == 0 then
            o[#o + 1] = ""
            o[#o + 1] = "No findings."
        end
        for _, c in ipairs(CHECKS) do
            local any = false
            for _, sev in ipairs({ "ERROR", "WARN", "INFO" }) do
                for _, it in ipairs(r.items) do
                    if it.check == c and it.sev == sev then
                        if not any then
                            o[#o + 1] = ""
                            o[#o + 1] = "### " .. CHECK_NAME[c]
                            o[#o + 1] = ""
                            any = true
                        end
                        o[#o + 1] = ("- %s %s: %s"):format(sev, it.where, it.msg)
                    end
                end
            end
        end
    end
    return table.concat(o, "\n") .. "\n"
end

function A.Csv(coords)
    local o = { "pack,step,type,npc,map,x,y,src,state,questie_yd,cmangos_yd" }
    for _, c in ipairs(coords) do
        local row = {}
        for k, v in ipairs(c) do
            v = tostring(v)
            if v:find("[,\"]") then v = '"' .. v:gsub('"', '""') .. '"' end
            row[k] = v
        end
        o[#o + 1] = table.concat(row, ",")
    end
    return table.concat(o, "\n") .. "\n"
end

function A.Main(argv)
    local opts = { questiedb = "../.addons/QuestieDB", flavor = "Forever", out = "plans/bug-first-step/audit.md",
        csv = "plans/bug-first-step/audit-coords.csv",
        cmangos = "plans/tools/data/cmangos/ClassicDB.sql", files = {} }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--questiedb" or a == "--flavor" or a == "--out" or a == "--csv" or a == "--date" or a == "--cmangos" then
            opts[a:sub(3)] = argv[i + 1]
            i = i + 2
        else
            opts.files[#opts.files + 1] = a
            i = i + 1
        end
    end
    if #opts.files == 0 then
        for _, f in ipairs(L.ListDir("packs-src", "lua")) do opts.files[#opts.files + 1] = "packs-src/" .. f end
    end
    local results, coords, stats, meta, givers = A.Run(opts)
    local md = A.Markdown(results, coords, meta, opts.date or os.date("%Y-%m-%d"), givers, stats.fits)
    local fh = assert(io.open(opts.out, "wb")) fh:write(md) fh:close()
    fh = assert(io.open(opts.csv, "wb")) fh:write(A.Csv(coords)) fh:close()
    for _, r in ipairs(results) do
        local e, w = 0, 0
        for _, it in ipairs(r.items) do
            if it.sev == "ERROR" then e = e + 1 elseif it.sev == "WARN" then w = w + 1 end
        end
        print(("%s: %d errors, %d warnings"):format(r.file, e, w))
    end
    print(("questie-audit: %d coordinates, %d givers listed, cmangos %s, decode errors %d; %s, %s"):format(#coords, #givers,
        stats.fits and "used" or "not found", stats.decodeError, opts.out, opts.csv))
    return stats.decodeError == 0
end

if args[1] == "--lib" then return A end
if not A.Main(args) then os.exit(1) end

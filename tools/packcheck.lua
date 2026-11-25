-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Pack checker (packs-src\FORMAT.md section 6). Uses the addon's own Packs\Format.lua and
-- Packs\Conditions.lua, so it reads packs exactly like the addon.
-- Run (from the repository folder):
--   luajit tools/packcheck.lua [--addon AllinOneGuide] [--exploits packs-src/known-exploits.lua]
--                              [--words <file with one never-use word per line>] [packs-src/x.lua ...]
--                              [--previous <folder with the last release's compiled Routes\*.lua>]
--   WARN lines are route lint (v0.2): they never fail the run.
--   NPC check (PC.NpcCheck): talk steps (PC.TALK) more than 50 yd from the NPC's nearest spawn on that map are
--   errors, more than 15 yd or no spawn data are warnings. Spawns: plans\tools\data\npc-spawns.lua (local only; rerun
--   tools\import\questie-spawns.lua after the packs change); map sizes: tools\data\mapsizes.lua (estimates).
--   Smart arrow step rules (tools\connectors.lua CC.StepCheck, with packs-src\connectors\): a `via` names real
--   connectors; a spot inside a connector room needs a room with an exit; a via detour > 1.5 x without why warns.
--   no pack files given: every pack in packs-src\. Exit code 1 when there is an error.
-- As a library: local PC = assert(loadfile("tools/packcheck.lua"))("--lib", "<tools folder>")
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2]) or (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tools"
local PC = {}

local function Here(rel) return toolsDir .. "/" .. rel end

local Lib
function PC.Lib()
    if not Lib then Lib = assert(loadfile(Here("packlib.lua")))() end
    return Lib
end

-- The smart arrow's connector tool (tools\connectors.lua) and an index of packs-src\connectors\ (nil when the
-- folder is missing or broken: the step rules are then skipped; the connector build reports the problems).
local CCmod
function PC.CC()
    if not CCmod then CCmod = assert(loadfile(Here("connectors.lua")))("--lib", toolsDir) end
    return CCmod
end
function PC.Connectors(dir)
    local list, errs = PC.CC().LoadAll(dir or "packs-src/connectors")
    if #list == 0 or #errs > 0 then return nil end
    return PC.CC().Index(list)
end

local SOURCE_KEYS = { id = true, type = true, quest = true, npc = true, map = true, x = true, y = true, r = true,
    text = true, da = true, flags = true, cond = true, src = true }
local HEADER_NEEDS = { "id", "title", "faction", "levels", "formatVersion", "minFormat", "version", "license" }
local FACTIONS = { Alliance = true, Horde = true, Neutral = true }
-- step texts start with one of these verbs (others are counted in the report as "style")
local VERBS = {}
for w in ([[Accept Hand Turn Kill Loot Pick Collect Gather Go Follow Leave Cross Enter Reach Talk Speak Use Deliver
    Look Find Get Take Fly Ride Travel Run Walk Grind Buy Sell Learn Train Set Open Click Escort Defend Wait Equip
    Bind Fish Cook Mine Skin Craft Repair Swim Climb Jump Search Read Destroy Save Free Kneel Protect Return Head]]):gmatch("%a+") do
    VERBS[w] = true
end

local function Placeholders(s)
    local t, list = {}, {}
    for k in (s or ""):gmatch("{([%w_]+)}") do
        if not t[k] then t[k] = true list[#list + 1] = k end
    end
    table.sort(list)
    return table.concat(list, ",")
end

local function Decimals(n)
    local s = string.format("%.6f", n):gsub("0+$", "")
    local d = s:match("%.(%d*)$") or ""
    return #d
end

-- A long run of letters / digits / +/= with no spaces looks encoded (packs are plain text).
local function Encoded(s)
    return type(s) == "string" and (s:find("[%w%+/=_]" .. ("[%w%+/=_]"):rep(39)) ~= nil)
end

-- UTF-8 length (the addon's U.Utf8Len isn't loaded in the tools).
local function Utf8Len(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Checks one loaded source pack. opts: { ns, exploits, words, name }
-- Returns errors (list of strings), report (table).
function PC.Check(pack, opts)
    local ns, L = opts.ns, PC.Lib()
    local Fm, Cd = ns.Format, ns.Conditions
    local errs = {}
    local report = { steps = 0, grind = 0, zoneChanges = 0, returns = 0, backtracks = 0, travel = {}, long = 0, style = 0 }
    local function Err(where, msg) errs[#errs + 1] = (opts.name or "?") .. ": " .. where .. ": " .. msg end

    -- header
    for _, k in ipairs(HEADER_NEEDS) do
        if pack[k] == nil then Err("header", "missing " .. k) end
    end
    if type(pack.id) == "string" and not pack.id:match("^[a-z0-9][a-z0-9%-]*$") then Err("header", "bad pack id") end
    if pack.faction and not FACTIONS[pack.faction] then Err("header", "faction must be Alliance, Horde or Neutral") end
    if pack.conditions and not Cd.Parse(pack.conditions) then Err("header", "conditions don't parse") end
    if type(pack.formatVersion) == "number" and type(pack.minFormat) == "number" and pack.minFormat > pack.formatVersion then
        Err("header", "minFormat newer than formatVersion")
    end
    for k, v in pairs(pack) do
        if Encoded(v) then Err("header", "encoded-looking string in " .. tostring(k)) end
    end

    local routes, expandErrs = L.Expand(pack)
    for _, e in ipairs(expandErrs) do Err("include", e) end

    local allIds = {}
    for _, r in ipairs(routes) do
        local seen = {}
        local lastMap, mapsLeft, lastPos = nil, {}, {}
        local history = {}
        for i, s in ipairs(r.steps) do
            report.steps = report.steps + 1
            local where = r.id .. " #" .. i .. " " .. tostring(s.id)
            -- id
            if type(s.id) ~= "string" or not s.id:match("^[a-z0-9][a-z0-9%.%-]*$") then
                Err(where, "bad id (a-z 0-9 . -)")
            elseif seen[s.id] then
                Err(where, "duplicate id (also step " .. seen[s.id] .. ")")
            else
                seen[s.id] = i
                allIds[s.id] = true
            end
            -- fields
            for k in pairs(s) do
                if not SOURCE_KEYS[k] and not Fm.EXTRA[k] then Err(where, "unknown field '" .. tostring(k) .. "'") end
            end
            if not Fm.TYPES[s.type] then Err(where, "unknown type '" .. tostring(s.type) .. "'") end
            if (s.type == "accept" or s.type == "turnin") and not s.quest then Err(where, "needs quest") end
            if s.type == "objective" and not s.quest and not s.item then Err(where, "needs quest or item") end
            if s.type == "goto" and not (s.map and s.x and s.y) then Err(where, "needs map, x, y") end
            if s.type == "level" and not s.level then Err(where, "needs level") end
            -- format 2 types
            if s.type == "grind" and not s.level then Err(where, "needs level") end
            if s.type == "grind" and not s.why then Err(where, "grind step without why") end
            if s.type == "fly" and not (s.map and s.x and s.y) then Err(where, "needs map, x, y") end
            if s.minLevel ~= nil and (type(s.minLevel) ~= "number" or s.minLevel < 1) then Err(where, "bad minLevel") end
            if (s.x == nil) ~= (s.y == nil) then Err(where, "x and y go together") end
            if (s.x or s.y) and not s.map then Err(where, "coordinates need a map") end
            for _, c in ipairs({ "x", "y" }) do
                local v = s[c]
                if v ~= nil then
                    if type(v) ~= "number" or v < 0 or v > 100 then Err(where, c .. " outside 0-100")
                    elseif Decimals(v) > 2 then Err(where, c .. " has more than 2 decimals") end
                end
            end
            if s.r ~= nil and (type(s.r) ~= "number" or s.r < 0) then Err(where, "bad radius") end
            for _, f in ipairs(s.flags or {}) do
                if not Fm.FLAGS[f] then Err(where, "unknown flag '" .. tostring(f) .. "'") end
            end
            -- source tag
            if not s.src then Err(where, "missing src")
            elseif not Fm.SOURCES[s.src] then Err(where, "unknown src '" .. tostring(s.src) .. "'") end
            if s.src == "wiki" and not s.seen then Err(where, "wiki fact without seen") end
            if s.src == "wiki" and s.confirmed == nil then Err(where, "wiki fact without confirmed (false until checked)") end
            if s.seen and not tostring(s.seen):match("^%d%d%d%d%-%d%d$") then Err(where, "seen must be YYYY-MM") end
            -- conditions
            if s.cond then
                local ast, e = Cd.Parse(s.cond)
                if not ast then Err(where, "cond: " .. e)
                elseif #ast.info.unknown > 0 then Err(where, "cond: unknown word " .. ast.info.unknown[1])
                elseif next(Cd.Items(ast)) then
                    -- item=<id>[:<count>]: only on optional steps (shown while the item is in the bags)
                    local optional = false
                    for _, f in ipairs(s.flags or {}) do if f == "optional" then optional = true end end
                    if not optional then Err(where, "cond item= needs the optional flag") end
                    for id in pairs(Cd.Items(ast)) do
                        if id <= 0 then Err(where, "cond item= needs an item id above 0") end
                    end
                end
            end
            if s.override then
                local ast, e = Cd.Parse(s.override, true)
                if not ast then Err(where, "override: " .. e)
                elseif #ast.info.unknown > 0 then Err(where, "override: unknown word " .. ast.info.unknown[1]) end
            end
            -- texts
            for _, k in ipairs({ "text", "da", "why", "qname" }) do
                local v = s[k]
                if v ~= nil then
                    if type(v) ~= "string" then Err(where, k .. " must be text")
                    else
                        if v:find("[|\r\n]") then Err(where, "'|' or a line break in " .. k) end
                        if Utf8Len(v) > 90 then report.long = report.long + 1 end
                    end
                end
            end
            -- text style: starts with a verb (verb + target + count + place); others are reported, not errors
            if type(s.text) == "string" then
                if not s.text:match("^%u") then
                    Err(where, "text must start with a capital letter (a verb)")
                elseif not VERBS[s.text:match("^(%a+)")] then
                    report.style = report.style + 1
                end
            end
            if s.text and s.da and Placeholders(s.text) ~= Placeholders(s.da) then
                Err(where, "da has other {placeholders} than text")
            end
            for k, v in pairs(s) do
                if Encoded(v) then Err(where, "encoded-looking string in " .. tostring(k)) end
            end
            -- words: exploits and never-use
            local lower = ((s.text or "") .. " " .. (s.da or "") .. " " .. (s.why or "")):lower()
            for _, x in ipairs(opts.exploits or {}) do
                for _, w in ipairs(x.words or {}) do
                    if lower:find(w) then Err(where, "known exploit '" .. x.id .. "'") end
                end
                for _, key in ipairs({ "quest", "npc", "item" }) do
                    for _, id in ipairs(x[key .. "s"] or {}) do
                        if s[key] == id then Err(where, "known exploit '" .. x.id .. "' (" .. key .. " " .. id .. ")") end
                    end
                end
            end
            for _, w in ipairs(opts.words or {}) do
                if lower:find(w, 1, true) then Err(where, "never-use word '" .. w .. "'") end
            end
            -- grind
            local grind = false
            for _, f in ipairs(s.flags or {}) do if f == "grind" then grind = true end end
            if grind then
                report.grind = report.grind + 1
                if not s.why then Err(where, "grind step without why") end
            end
            -- travel, zone returns, backtracking
            if s.map and s.x and s.y then
                if lastMap and s.map ~= lastMap then
                    report.zoneChanges = report.zoneChanges + 1
                    mapsLeft[lastMap] = true
                    if mapsLeft[s.map] then
                        report.returns = report.returns + 1
                        if not s.why then Err(where, "returns to map " .. s.map .. " without why") end
                    end
                end
                local prev = lastPos[s.map]
                if prev and s.map == lastMap then
                    report.travel[s.map] = (report.travel[s.map] or 0) + Dist(prev, s)
                end
                -- backtrack: back within 3 % of a spot from 3+ steps ago after being 15 % away from it
                for h = #history - 3, 1, -1 do
                    local old = history[h]
                    if old.map == s.map and Dist(old, s) < 3 then
                        local away = false
                        for m = h + 1, #history do
                            if history[m].map == s.map and Dist(old, history[m]) > 15 then away = true break end
                        end
                        if away then report.backtracks = report.backtracks + 1 end
                        break
                    end
                end
                history[#history + 1] = { map = s.map, x = s.x, y = s.y }
                lastPos[s.map], lastMap = s, s.map
            end
            -- the row must come back unchanged through the addon's decoder
            local ok, row = pcall(Fm.EncodeRow, s)
            if not ok then Err(where, "can't encode: " .. tostring(row))
            else
                local d = Fm.DecodeRow(row)
                if not d or d.id ~= s.id or d.type ~= s.type or d.quest ~= s.quest or d.text ~= s.text
                    or d.da ~= s.da or d.cond ~= s.cond or d.why ~= s.why
                    or (s.x and s.y and (not d.x or math.abs(d.x * 100 - s.x) > 1e-9)) then
                    Err(where, "row doesn't decode back to the same step")
                end
            end
        end
        -- targets of whileUntil / leadsTo: a later step in the same route
        for i, s in ipairs(r.steps) do
            for _, k in ipairs({ "whileUntil", "leadsTo" }) do
                local t = s[k]
                if t ~= nil and not (seen[t] and seen[t] > i) then
                    Err(r.id .. " #" .. i .. " " .. tostring(s.id), k .. " '" .. tostring(t) .. "' is not a later step")
                end
            end
        end
    end
    -- renames and retired ids
    for old, new in pairs(pack.renamedSteps or {}) do
        if allIds[old] then Err("renamedSteps", "'" .. old .. "' still exists") end
        if not allIds[new] then Err("renamedSteps", "target '" .. tostring(new) .. "' doesn't exist") end
    end
    for _, id in ipairs(pack.retiredSteps or {}) do
        if allIds[id] then Err("retiredSteps", "retired id '" .. id .. "' is used again") end
    end
    -- smart arrow (opts.connectors = PC.Connectors() index): `via` names real connectors, a spot inside a room
    -- has a way in, a via detour over 1.5 x without why is a warning (report.connectors)
    report.connectors = {}
    if opts.connectors then
        local cerr, cwarn = PC.CC().StepCheck(routes, opts.connectors)
        for _, e in ipairs(cerr) do errs[#errs + 1] = (opts.name or "?") .. ": " .. e end
        report.connectors = cwarn
    end
    report.lint = PC.Lint(pack, routes, opts)
    -- NPC points against the NPC's real spawns (far off = error, a bit off or no data = warning)
    report.npc = {}
    if opts.spawns ~= false then
        local nerr, nwarn = PC.NpcCheck(routes, opts)
        for _, e in ipairs(nerr) do errs[#errs + 1] = (opts.name or "?") .. ": " .. e end
        report.npc = nwarn
    end
    return errs, report, routes
end

-- ------------------------------------------------------------------ NPC distance check
-- Steps where the player talks to an NPC standing at the step's point (format 1 + 2 types).
PC.TALK = { accept = true, turnin = true, train = true, learn = true, sethearth = true, getfp = true }
PC.NPC_WARN, PC.NPC_FAIL = 15, 50   -- yards

local Spawns, MapSizes
-- The spawn data made by tools\import\questie-spawns.lua: a local copy only (plans\tools\data\npc-spawns.lua,
-- never published while the QuestieDB licence ruling is open), else tools\data\npc-spawns.lua; false when
-- neither is there (then the check is skipped quietly).
PC.SPAWN_FILES = { "../plans/tools/data/npc-spawns.lua", "data/npc-spawns.lua" }
function PC.Spawns()
    if Spawns == nil then
        local chunk
        for _, rel in ipairs(PC.SPAWN_FILES) do
            chunk = loadfile(Here(rel))
            if chunk then break end
        end
        Spawns = false
        if chunk then
            setfenv(chunk, {})
            local ok, t = pcall(chunk)
            if ok and type(t) == "table" then Spawns = t end
        end
    end
    return Spawns
end
-- tools\data\mapsizes.lua: Classic map sizes in yards (estimates).
function PC.MapSizes()
    if not MapSizes then MapSizes = assert(loadfile(Here("data/mapsizes.lua")))() end
    return MapSizes
end

-- opts.spawns = a spawns table ({ questie = { [npc] = { map, x, y, ... } }, missing = { ids } }) or nil for the
-- default file; opts.mapSizes likewise. Returns errors, warnings (lists of "route #i id: message").
function PC.NpcCheck(routes, opts)
    opts = opts or {}
    local data = opts.spawns
    if data == nil then data = PC.Spawns() end
    local sizes = opts.mapSizes or PC.MapSizes()
    local errs, warns = {}, {}
    if not data then return errs, warns end   -- no local spawn data (CI, another PC): skipped quietly
    local missing = {}
    for _, id in ipairs(data.missing or {}) do missing[id] = true end
    -- every source table in the file (questie, own, ...) counts
    local function Points(npc)
        local all
        for k, src in pairs(data) do
            if k ~= "missing" and type(src) == "table" and type(src[npc]) == "table" then
                all = all or {}
                local f = src[npc]
                for i = 1, #f - 2, 3 do all[#all + 1] = { f[i], f[i + 1], f[i + 2] } end
            end
        end
        return all
    end
    for _, r in ipairs(routes) do
        for i, s in ipairs(r.steps) do
            if PC.TALK[s.type] and type(s.npc) == "number" and s.map and s.x and s.y then
                local where = r.id .. " #" .. i .. " " .. tostring(s.id)
                local pts = Points(s.npc)
                local size = sizes[s.map]
                if not pts then
                    warns[#warns + 1] = where .. (": npc %d has no spawn data%s"):format(s.npc,
                        missing[s.npc] and " (none in Questie)" or " (not in npc-spawns.lua: rerun the import)")
                elseif not size then
                    warns[#warns + 1] = where .. (": map %d has no size in mapsizes.lua; npc %d not checked"):format(s.map, s.npc)
                else
                    local best, bx, by
                    local other = {}
                    for _, p in ipairs(pts) do
                        if p[1] == s.map then
                            local d = math.sqrt(((s.x - p[2]) / 100 * size[1]) ^ 2 + ((s.y - p[3]) / 100 * size[2]) ^ 2)
                            if not best or d < best then best, bx, by = d, p[2], p[3] end
                        else
                            other[p[1]] = true
                        end
                    end
                    if not best then
                        local ml = {}
                        for m in pairs(other) do ml[#ml + 1] = m end
                        table.sort(ml)
                        warns[#warns + 1] = where .. (": npc %d has no spawn on map %d (spawns on map %s)")
                            :format(s.npc, s.map, table.concat(ml, ", "))
                    elseif best > PC.NPC_FAIL then
                        errs[#errs + 1] = where .. (": npc %d is %.0f yd from its nearest spawn %.2f,%.2f (over %d yd; map size estimated)")
                            :format(s.npc, best, bx, by, PC.NPC_FAIL)
                    elseif best > PC.NPC_WARN then
                        warns[#warns + 1] = where .. (": npc %d is %.0f yd from its nearest spawn %.2f,%.2f (over %d yd; map size estimated)")
                            :format(s.npc, best, bx, by, PC.NPC_WARN)
                    end
                end
            end
        end
    end
    return errs, warns
end

-- ------------------------------------------------------------------ route lint (v0.2, warnings only)
local Facts, Maps
function PC.Facts()
    if not Facts then Facts = assert(loadfile(Here("data/forever-facts.lua")))() end
    return Facts
end
function PC.Maps()
    if not Maps then Maps = assert(loadfile(Here("data/maps.lua")))() end
    return Maps
end

local function HasFlag(s, f)
    for _, x in ipairs(s.flags or {}) do if x == f then return true end end
    return false
end

-- Things a route shouldn't do but that aren't always wrong. opts.previous = { [id] = true } of the step ids
-- in the last release (for "an id went away without retiredSteps / renamedSteps"); opts.extraMaps = more
-- known map ids (tests). Returns a list of "route #i id: message".
function PC.Lint(pack, routes, opts)
    opts = opts or {}
    local F, maps = PC.Facts(), PC.Maps()
    local out = {}
    local function W(where, msg) out[#out + 1] = where .. ": " .. msg end
    local logMax = F.logMax.value
    local jump = F.levelJumpWarn.value
    local repeats = F.dungeonRepeatsWarn.value
    local lv = pack.levels
    local startLevel = tonumber(type(lv) == "table" and lv[1] or type(lv) == "string" and lv:match("^(%d+)") or nil) or 1
    local known = {}
    for _, n in ipairs(pack.knownNodes or {}) do known[n] = true end
    local allIds = {}
    for _, r in ipairs(routes) do
        local accepted, inLog, logN = {}, {}, 0
        local level, bound = startLevel, pack.startInn ~= nil
        local nodes = {}
        for k in pairs(known) do nodes[k] = true end
        local visits = {}
        local lastDungeon
        local xpLevel, xpHave = startLevel, 0
        local turnins = 0
        for i, s in ipairs(r.steps) do
            allIds[s.id or ""] = true
            local where = r.id .. " #" .. i .. " " .. tostring(s.id)
            local q = s.quest
            if s.type == "accept" and q then
                accepted[q] = true
                if not inLog[q] then
                    inLog[q] = true
                    logN = logN + 1
                    if logN > logMax - 2 then W(where, ("quest log at %d of %d (keep 2 free)"):format(logN, logMax)) end
                end
                if s.xp == 0 and not s.why then W(where, "a quest with no XP needs a why") end
            elseif s.type == "turnin" and q then
                if not accepted[q] and not s.from and not s.why then W(where, "turn-in before its accept (add the accept, or from= / why)") end
                if inLog[q] then inLog[q], logN = nil, logN - 1 end
                turnins = turnins + 1
                -- the XP model: quest XP (where known) moves the modelled level on
                if type(s.xp) == "number" then
                    xpHave = xpHave + s.xp
                    while F.xpToNext.value[xpLevel] and xpHave >= F.xpToNext.value[xpLevel] do
                        xpHave = xpHave - F.xpToNext.value[xpLevel]
                        xpLevel = xpLevel + 1
                    end
                end
            end
            -- level steps: no jump of more than `jump` levels at once
            local need = (s.type == "level" or s.type == "grind") and s.level or s.minLevel
            if type(need) == "number" then
                -- more than `jump` levels with few hand-ins since the last level step: likely a grind gap
                if need - level > jump and turnins < (need - level) * 2 then
                    W(where, ("asks for level %d after %d with only %d hand-ins between"):format(need, level, turnins))
                end
                if s.minLevel and pack.xpModel and xpLevel < s.minLevel then
                    W(where, ("the XP model reaches only level %d here, the step needs %d"):format(xpLevel, s.minLevel))
                end
                if need > level then level, turnins = need, 0 end
            end
            if (s.type == "grind" or HasFlag(s, "grind")) and not s.why then W(where, "grind without why") end
            -- hearth and flights
            if s.type == "sethearth" then bound = true end
            if s.type == "hearth" and not bound then W(where, "hearthstone used before any sethearth step (or startInn)") end
            if s.type == "getfp" and s.node then nodes[s.node] = true end
            if s.type == "fly" and s.node and not nodes[s.node] then W(where, "flies to node " .. s.node .. " before a getfp step for it") end
            -- maps
            if s.map and not maps[s.map] and not (opts.extraMaps and opts.extraMaps[s.map]) then
                W(where, "unknown map id " .. tostring(s.map))
            end
            -- R4: the same dungeon more than `repeats` visits in a row, or two dungeons taking turns (A-B-A-B).
            -- A note step inside a run (no dungeon of its own) belongs to that run: it is not a new visit.
            local dg = s.dungeon
            if dg == nil and s.type == "note" then dg = lastDungeon end
            if dg and dg ~= lastDungeon then
                visits[#visits + 1] = dg
                local n, k = 0, #visits
                while k >= 1 and visits[k] == dg do n, k = n + 1, k - 1 end
                if n > repeats then
                    W(where, ("dungeon '%s' %d times in a row (at most %d: the instance limit is a limit, not a target)"):format(dg, n, repeats))
                end
                -- length of the alternating tail (A-B-A-B...): warn from 4 entries on
                k = #visits
                local m = 1
                if k >= 2 and visits[k - 1] ~= dg then
                    m = 2
                    while k - m >= 1 and visits[k - m] == visits[k - m + 2] do m = m + 1 end
                end
                if m >= 4 then
                    W(where, ("dungeons '%s' and '%s' take turns: %d entries in a row (the instance limit is a limit, not a target)")
                        :format(visits[k - 1], dg, m))
                end
            end
            lastDungeon = dg
        end
    end
    -- ids from the last release that went away without retiredSteps / renamedSteps
    if opts.previous then
        local retired = {}
        for _, id in ipairs(pack.retiredSteps or {}) do retired[id] = true end
        for id in pairs(opts.previous) do
            if not allIds[id] and not retired[id] and not (pack.renamedSteps or {})[id] then
                W("ids", "'" .. id .. "' was in the last release; add it to retiredSteps or renamedSteps")
            end
        end
    end
    table.sort(out)
    return out
end

-- Step ids of a compiled route file from an earlier release (the rows' first field).
function PC.PreviousIds(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local text = fh:read("*a")
    fh:close()
    local ids = {}
    for row in text:gmatch('"([^"\n]-)"') do
        local id = row:match("^([a-z0-9][a-z0-9%.%-]*)|%a+|")
        if id then ids[id] = true end
    end
    return ids
end

function PC.LoadWords(path)
    local out = {}
    local fh = path and io.open(path, "r")
    if not fh then return out end
    for line in fh:lines() do
        line = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        if line ~= "" then out[#out + 1] = line:lower() end
    end
    fh:close()
    return out
end

function PC.Main(argv)
    local opts = { addon = "AllinOneGuide", exploits = "packs-src/known-exploits.lua", files = {} }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--addon" or a == "--exploits" or a == "--words" or a == "--previous" then
            opts[a:sub(3)] = argv[i + 1]
            i = i + 2
        else
            opts.files[#opts.files + 1] = a
            i = i + 1
        end
    end
    local L = PC.Lib()
    local ns = L.AddonParts(opts.addon)
    local exploits = assert(L.LoadData(opts.exploits))
    local words = PC.LoadWords(opts.words)
    if #opts.files == 0 then
        for _, f in ipairs(L.ListDir("packs-src", "lua")) do opts.files[#opts.files + 1] = "packs-src/" .. f end
    end
    local total, packs, steps = 0, 0, 0
    local connectors = PC.Connectors()
    for _, f in ipairs(opts.files) do
        local t, err = L.LoadData(f)
        if not t then
            print("ERROR " .. f .. ": " .. tostring(err))
            total = total + 1
        elseif L.IsPack(t) then
            packs = packs + 1
            local prev = opts.previous and PC.PreviousIds(opts.previous .. "/" .. L.OutName(t)) or nil
            local errs, rep = PC.Check(t, { ns = ns, exploits = exploits, words = words, name = f, previous = prev,
                connectors = connectors })
            for _, e in ipairs(errs) do print("ERROR " .. e) end
            total = total + #errs
            steps = steps + rep.steps
            local travel = {}
            for map, d in pairs(rep.travel) do travel[#travel + 1] = map .. "=" .. string.format("%.0f", d) end
            table.sort(travel)
            for _, w in ipairs(rep.lint or {}) do print("WARN " .. f .. ": " .. w) end
            for _, w in ipairs(rep.npc or {}) do print("WARN " .. f .. ": " .. w) end
            for _, w in ipairs(rep.connectors or {}) do print("WARN " .. f .. ": " .. w) end
            print(string.format("%s: %d steps, grind %d, zone changes %d, returns %d, backtracks %d, long texts %d, texts not starting with a verb %d, route warnings %d, npc warnings %d, travel %%: %s",
                f, rep.steps, rep.grind, rep.zoneChanges, rep.returns, rep.backtracks, rep.long, rep.style, #(rep.lint or {}), #(rep.npc or {}), table.concat(travel, " ")))
        end
    end
    print(string.format("packcheck: %d packs, %d steps, %d errors", packs, steps, total))
    return total == 0
end

if args[1] == "--lib" then return PC end
if not PC.Main(args) then os.exit(1) end

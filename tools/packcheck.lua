-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Pack checker (packs-src\FORMAT.md section 6). Uses the addon's own Packs\Format.lua and
-- Packs\Conditions.lua, so it reads packs exactly like the addon.
-- Run (from the repository folder):
--   luajit tools/packcheck.lua [--addon AllinOneGuide] [--exploits packs-src/known-exploits.lua]
--                              [--words <file with one never-use word per line>] [packs-src/x.lua ...]
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
                elseif #ast.info.unknown > 0 then Err(where, "cond: unknown word " .. ast.info.unknown[1]) end
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
    return errs, report, routes
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
        if a == "--addon" or a == "--exploits" or a == "--words" then
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
    for _, f in ipairs(opts.files) do
        local t, err = L.LoadData(f)
        if not t then
            print("ERROR " .. f .. ": " .. tostring(err))
            total = total + 1
        elseif L.IsPack(t) then
            packs = packs + 1
            local errs, rep = PC.Check(t, { ns = ns, exploits = exploits, words = words, name = f })
            for _, e in ipairs(errs) do print("ERROR " .. e) end
            total = total + #errs
            steps = steps + rep.steps
            local travel = {}
            for map, d in pairs(rep.travel) do travel[#travel + 1] = map .. "=" .. string.format("%.0f", d) end
            table.sort(travel)
            print(string.format("%s: %d steps, grind %d, zone changes %d, returns %d, backtracks %d, long texts %d, texts not starting with a verb %d, travel %%: %s",
                f, rep.steps, rep.grind, rep.zoneChanges, rep.returns, rep.backtracks, rep.long, rep.style, table.concat(travel, " ")))
        end
    end
    print(string.format("packcheck: %d packs, %d steps, %d errors", packs, steps, total))
    return total == 0
end

if args[1] == "--lib" then return PC end
if not PC.Main(args) then os.exit(1) end

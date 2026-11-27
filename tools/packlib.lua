-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Shared by tools\build.lua and tools\packcheck.lua: loads pack sources as data, expands includes,
-- and writes the compiled pack files. Uses the addon's own Packs\Format.lua and Packs\Conditions.lua,
-- so the tools read rows exactly like the addon does.
-- Use: local Lib = assert(loadfile(toolsDir .. "/packlib.lua"))()
local Lib = { MAX_DEPTH = 4 }

local function Join(a, b) return a .. "/" .. b end
Lib.Join = Join

-- The addon parts the tools share (a private namespace like the addon's).
function Lib.AddonParts(addonDir)
    local ns = {}
    for _, f in ipairs({ "Packs/Format.lua", "Packs/Conditions.lua" }) do
        local chunk = assert(loadfile(Join(addonDir, f)))
        chunk("AllinOneGuide", ns)
    end
    return ns
end

-- Loads a data file (a source pack or known-exploits.lua): one table, no code can run (empty environment).
function Lib.LoadData(path)
    local chunk, err = loadfile(path)
    if not chunk then return nil, err end
    setfenv(chunk, {})
    local ok, t = pcall(chunk)
    if not ok then return nil, t end
    if type(t) ~= "table" then return nil, "the file must return one table" end
    return t
end

function Lib.IsPack(t) return type(t) == "table" and type(t.routes) == "table" end

function Lib.ListDir(dir, ext)
    local out = {}
    local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.' .. ext .. '" 2>nul')
    if p then
        for line in p:lines() do out[#out + 1] = line end
        p:close()
    end
    table.sort(out)
    return out
end

function Lib.ReadFile(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

-- ------------------------------------------------------------------ include expansion
local function Subst(v, params)
    if type(v) ~= "string" or not params then return v end
    local whole = v:match("^{([%w_]+)}$")
    if whole and params[whole] ~= nil then return params[whole] end
    return (v:gsub("{([%w_]+)}", function(k)
        if params[k] ~= nil then return tostring(params[k]) end
    end))
end

local function JoinCond(a, b)
    if a and b then return "(" .. a .. ") and (" .. b .. ")" end
    return a or b
end

local function ParamText(params)
    local keys = {}
    for k in pairs(params or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local t = {}
    for _, k in ipairs(keys) do t[#t + 1] = k .. ":" .. tostring(params[k]) end
    return table.concat(t, ",")
end

local function Expand(pack, list, depth, prefix, params, cond, inc, out, errs)
    for _, e in ipairs(list) do
        if type(e) ~= "table" then
            errs[#errs + 1] = "a step that is not a table"
        elseif e.include then
            local block = pack.blocks and pack.blocks[e.include]
            if not block then
                errs[#errs + 1] = "missing block '" .. tostring(e.include) .. "'"
            elseif depth >= Lib.MAX_DEPTH then
                errs[#errs + 1] = "include deeper than " .. Lib.MAX_DEPTH .. " at '" .. tostring(e.include) .. "'"
            elseif type(e.id) ~= "string" then
                errs[#errs + 1] = "include of '" .. e.include .. "' has no id"
            else
                local merged = {}
                for k, v in pairs(params or {}) do merged[k] = v end
                for k, v in pairs(e.params or {}) do merged[k] = Subst(v, params) end
                local path = e.include .. "@" .. ParamText(e.params)
                Expand(pack, block, depth + 1, prefix and (prefix .. "." .. e.id) or e.id, merged,
                    JoinCond(cond, e.cond), inc and (inc .. ">" .. path) or path, out, errs)
            end
        else
            local s = {}
            for k, v in pairs(e) do
                if k == "flags" and type(v) == "table" then
                    local f = {}
                    for i, x in ipairs(v) do f[i] = x end
                    s.flags = f
                elseif k == "obj" and type(v) == "table" then
                    local o = {}
                    for i, x in ipairs(v) do o[i] = Subst(x, params) end
                    s.obj = o
                else
                    s[k] = Subst(v, params)
                end
            end
            if prefix and type(s.id) == "string" then s.id = prefix .. "." .. s.id end
            s.cond = JoinCond(cond, s.cond)
            if inc then s.inc = inc end
            if s.flags and #s.flags == 0 then s.flags = nil end
            local ow = s.onWay
            if ow ~= nil then
                s.onWay = nil
                Lib.ExpandOnWay(s, ow, params, inc, out, errs)
            end
            out[#out + 1] = s
        end
    end
end

-- ------------------------------------------------------------------ travel side goals (onWay)
-- A step's `onWay = { { id, quest, obj, any, item, count, useItem, text, da, cond, flags, src, seen,
-- confirmed, whileUntil }, ... }` becomes ordinary background-goal rows placed right before that step: id
-- `<step id>.<entry id>`, type objective (useitem with useItem), the entry's whileUntil or the default (filled
-- in by Lib.Expand: the first later objective step of the same quest that covers it = hand-over, else its
-- turn-in), extra key onWay = <step id>. Not on fly / hearth steps (you can't fight in the air; the
-- hearthstone is instant). ("until" is a Lua keyword, so the entry uses the step field name whileUntil.)
Lib.ONWAY_NO = { fly = true, hearth = true }
Lib.ONWAY_COPY = { quest = true, obj = true, any = true, item = true, count = true, useItem = true, text = true,
    da = true, cond = true, flags = true, src = true, seen = true, confirmed = true, qname = true, whileUntil = true }

function Lib.ExpandOnWay(s, ow, params, inc, out, errs)
    local who = "onWay of '" .. tostring(s.id) .. "'"
    if type(ow) ~= "table" then errs[#errs + 1] = who .. " must be a list" return end
    if Lib.ONWAY_NO[s.type] then errs[#errs + 1] = who .. ": not on a " .. tostring(s.type) .. " step" return end
    for k, w in ipairs(ow) do
        if type(w) ~= "table" or type(w.id) ~= "string" then
            errs[#errs + 1] = who .. ": entry " .. k .. " has no id"
        else
            local side = {}
            for key, v in pairs(w) do
                if key ~= "id" then
                    if not Lib.ONWAY_COPY[key] then errs[#errs + 1] = who .. " '" .. w.id .. "': unknown field '" .. tostring(key) .. "'" end
                    if (key == "obj" or key == "flags") and type(v) == "table" then
                        local c = {}
                        for i, x in ipairs(v) do c[i] = Subst(x, params) end
                        side[key] = c
                    else
                        side[key] = Subst(v, params)
                    end
                end
            end
            side.id = tostring(s.id) .. "." .. w.id
            side.type = side.useItem and "useitem" or "objective"
            side.onWay = s.id
            side.cond = JoinCond(s.cond, side.cond)
            if inc then side.inc = inc end
            if side.flags and #side.flags == 0 then side.flags = nil end
            if type(side.text) ~= "string" then errs[#errs + 1] = who .. " '" .. w.id .. "': needs text" end
            if not side.quest and not side.item then errs[#errs + 1] = who .. " '" .. w.id .. "': needs quest or item" end
            if not side.whileUntil then
                if side.quest then side.untilAuto = true
                else errs[#errs + 1] = who .. " '" .. w.id .. "': an item goal without a quest needs whileUntil" end
            end
            out[#out + 1] = side
        end
    end
end

-- Does objective step `t` cover the objectives of side goal `s`? (an empty obj list = all objectives;
-- the same rule as the addon's Guide:HandOverAt)
function Lib.Covers(t, s)
    local tl, sl = t.obj or {}, s.obj or {}
    if #tl == 0 then return true end
    if #sl == 0 then return false end
    local have = {}
    for _, i in ipairs(tl) do have[i] = true end
    for _, i in ipairs(sl) do if not have[i] then return false end end
    return true
end

-- Fills the default whileUntil of onWay rows (see above) and reports a quest with no later step.
local function OnWayUntil(steps, errs)
    for i, s in ipairs(steps) do
        if s.untilAuto then
            s.untilAuto = nil
            -- the first of: an objective step covering it (hand-over) or the turn-in
            for j = i + 1, #steps do
                local t = steps[j]
                if t.quest == s.quest and not t.onWay and not t.whileUntil
                    and ((t.type == "objective" and Lib.Covers(t, s)) or t.type == "turnin") then
                    s.whileUntil = t.id
                    break
                end
            end
            if not s.whileUntil then
                errs[#errs + 1] = "onWay '" .. tostring(s.id) .. "': no later objective or turn-in step for quest " .. tostring(s.quest)
            end
        end
    end
end

-- ------------------------------------------------------------------ hunt paths (`path = "auto"`)
-- packs-src\paths\<pack id>.lua (written by tools\import\huntpath.lua, a data file like a pack):
--   return { pack = "<pack id>", formatVersion = 1, license = "...",
--            steps = { ["<step id>"] = { src = "gen" | "hand", points = { { x, y }, ... }, open = true?, r = n? } } }
-- Found next to this file (tools\..\packs-src\paths), so it works from any working folder. Lib.PATHS_DIR may be
-- set to another folder (tests); Lib.paths[pack id] caches a loaded file (false = none).
do
    local src = debug and debug.getinfo and debug.getinfo(1, "S").source or ""
    local dir = src:match("^@(.*)[/\\][^/\\]+$")
    Lib.PATHS_DIR = dir and (dir .. "/../packs-src/paths") or "packs-src/paths"
end
Lib.paths = {}

function Lib.LoadPaths(packId)
    if type(packId) ~= "string" then return nil end
    if Lib.paths[packId] == nil then
        local t = Lib.LoadData(Join(Lib.PATHS_DIR, packId .. ".lua"))
        Lib.paths[packId] = (type(t) == "table" and type(t.steps) == "table") and t or false
    end
    return Lib.paths[packId] or nil
end

-- Fills `path = "auto"` steps from the pack's paths file: points (copied), pathSrc, pathOpen, pathR (a value the
-- step sets itself wins). An id with no entry stays "auto" and is an error.
local function FillPaths(pack, steps, errs)
    for _, s in ipairs(steps) do
        if s.path == "auto" then
            local file = Lib.LoadPaths(pack.id)
            local e = file and file.steps[s.id]
            if type(e) ~= "table" or type(e.points) ~= "table" then
                errs[#errs + 1] = "path 'auto' of '" .. tostring(s.id) .. "' has no entry in packs-src/paths/"
                    .. tostring(pack.id) .. ".lua"
            else
                local pts = {}
                for i, p in ipairs(e.points) do pts[i] = type(p) == "table" and { p[1], p[2] } or p end
                s.path = pts
                if s.pathSrc == nil then s.pathSrc = e.src end
                if s.pathOpen == nil and e.open then s.pathOpen = true end
                if s.pathR == nil then s.pathR = e.r end
            end
        end
    end
end
Lib.FillPaths = FillPaths

-- Returns routes = { { id, title, da, sections = { { title, da, first } }, steps = { ... } } }, errors
function Lib.Expand(pack)
    local routes, errs = {}, {}
    for _, r in ipairs(pack.routes) do
        local route = { id = r.id, title = r.title, da = r.da, sections = {}, steps = {} }
        for _, sec in ipairs(r.sections or {}) do
            route.sections[#route.sections + 1] = { title = sec.title, da = sec.da, first = #route.steps + 1 }
            Expand(pack, sec.steps or {}, 0, nil, nil, nil, nil, route.steps, errs)
        end
        OnWayUntil(route.steps, errs)
        FillPaths(pack, route.steps, errs)
        routes[#routes + 1] = route
    end
    return routes, errs
end

-- ------------------------------------------------------------------ writing
local function Lit(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return (string.format("%.4f", v):gsub("0+$", ""))
    end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then error("can't write a " .. t) end
    local parts = {}
    local n = #v
    for i = 1, n do parts[#parts + 1] = Lit(v[i]) end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local key = (type(k) == "string" and k:match("^[%a_][%w_]*$") and k ~= "goto") and k or ("[" .. Lit(k) .. "]")
        parts[#parts + 1] = key .. " = " .. Lit(v[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end
Lib.Lit = Lit

-- Not written into the compiled header: build-only fields. The credits list lives in CREDITS.txt (the build
-- checks every URL is there), so the addon doesn't keep it in memory.
local HEADER_SKIP = { routes = true, blocks = true, file = true, credits = true }

function Lib.UsesWiki(routes)
    for _, r in ipairs(routes) do
        for _, s in ipairs(r.steps) do if s.src == "wiki" then return true end end
    end
    return false
end

-- The compiled file's text (deterministic: same source, same bytes).
function Lib.Compile(ns, pack, routes, srcName)
    local L = {}
    L[#L + 1] = "-- SPDX-License-Identifier: GPL-3.0-or-later"
    L[#L + 1] = "-- Copyright (C) 2026 gettic"
    if Lib.UsesWiki(routes) then
        L[#L + 1] = "-- Contains facts from warcraft.wiki.gg (CC BY-SA 4.0), see CREDITS.txt"
    end
    L[#L + 1] = "-- Compiled by tools\\build.ps1 from packs-src\\" .. srcName .. "; do not edit."
    L[#L + 1] = "-- The readable source and packs-src\\FORMAT.md are in the GitHub repository at the matching tag."
    L[#L + 1] = "-- Row fields: " .. table.concat(ns.Format.FIELDS, "|")
    -- v0.2.5: packs live in their own LoadOnDemand addons, which can't see the guide's private namespace, so they
    -- register through the one public entry (data only: T29)
    L[#L + 1] = Lib.PACK_HEAD[1]
    L[#L + 1] = Lib.PACK_HEAD[2]
    local header = {}
    for k, v in pairs(pack) do if not HEADER_SKIP[k] then header[k] = v end end
    L[#L + 1] = "AOG.RegisterPack(" .. Lit(header) .. ", {"
    for _, r in ipairs(routes) do
        local secs = {}
        for _, s in ipairs(r.sections) do
            secs[#secs + 1] = s.first .. "|" .. ns.Format.Escape(s.title or "") .. "|" .. ns.Format.Escape(s.da or "")
        end
        local head = { id = r.id, title = r.title, da = r.da, sections = secs }
        L[#L + 1] = "    { id = " .. Lit(head.id) .. ", title = " .. Lit(head.title or "") .. ", da = " .. Lit(head.da or "")
            .. ", sections = " .. Lit(secs) .. ", rows = {"
        for _, s in ipairs(r.steps) do
            L[#L + 1] = "        " .. Lit(ns.Format.EncodeRow(s)) .. ","
        end
        L[#L + 1] = "    } },"
    end
    L[#L + 1] = "})"
    return table.concat(L, "\n") .. "\n"
end

-- Output file name for a pack.
function Lib.OutName(pack) return (pack.file or pack.id) .. ".lua" end

-- ------------------------------------------------------------------ v0.2.5 pack folders
-- The two code lines every compiled pack file starts with (after its comments).
Lib.PACK_HEAD = { "local AOG = AllinOneGuide", "if not (AOG and AOG.RegisterPack) then return end" }

-- T29 (plans\roadmap-1-60\tos.md): a compiled pack file is plain readable data. Every line must be a comment, one
-- of the two head lines, the RegisterPack call, a route head, a row string, or a closing bracket; nothing may
-- hide code (loadstring, load(, setfenv, getfenv, \ddd escapes, long base64-like runs). Returns a list of problems.
Lib.SCAN_CODE = { "loadstring", "load%s*%(", "setfenv", "getfenv", "dofile", "require", "%f[%w_]_G%f[^%w_]",
    "function", "%f[%w_]AOG%.[%a_]+" }
Lib.BASE64_RUN = 40   -- a run of base64 letters this long (with + or /) counts as encoded
-- The line with every string literal emptied (so words in step texts never count as code).
local function StripStrings(line)
    local out, i, n = {}, 1, #line
    while i <= n do
        local c = line:sub(i, i)
        if c == '"' then
            local j = i + 1
            while j <= n do
                local d = line:sub(j, j)
                if d == "\\" then j = j + 2 elseif d == '"' then break else j = j + 1 end
            end
            out[#out + 1] = '""'
            i = j + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end
Lib.StripStrings = StripStrings
function Lib.ScanOutput(text, name)
    local out = {}
    local function P(n, msg) out[#out + 1] = (name or "?") .. ":" .. n .. ": " .. msg end
    local n, calls = 0, 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local check = true
        if line:match("^%-%-") or line == Lib.PACK_HEAD[1] or line == Lib.PACK_HEAD[2] then
            check = false
        elseif line:match("^AOG%.RegisterPack%({.*}, {$") then
            calls = calls + 1
        elseif not (line:match('^    { id = "[^"]*", title = .*, rows = {$') or line:match('^        ".*",$')
            or line == "    } }," or line == "})" or line == "") then
            P(n, "not a pack data line")
        end
        if check then
            local code = StripStrings(line)
            if line:match("^AOG%.RegisterPack%(") then code = code:gsub("^AOG%.RegisterPack", "", 1) end
            for _, pat in ipairs(Lib.SCAN_CODE) do
                local hit = code:match(pat)
                if hit then P(n, "looks like code: " .. hit) end
            end
            if line:find("\\%d") then P(n, "a \\ddd byte escape") end
            for run in line:gmatch("[%w%+/=]+") do
                if #run >= Lib.BASE64_RUN and run:find("[%+/]") then P(n, "a long encoded-looking run: " .. run:sub(1, 40)) break end
            end
        end
    end
    if calls ~= 1 then P(n, "needs exactly one AOG.RegisterPack call (has " .. calls .. ")") end
    return out
end

-- The pack addon's .toc (generated; one per folder in tools\data\pack-folders.lua).
function Lib.PackToc(f, interface, files, packIds)
    local L = {
        "# SPDX-License-Identifier: GPL-3.0-or-later",
        "## Interface: " .. interface,
        "## Title: " .. f.title,
        "## Notes: " .. f.notes,
        "## Author: gettic",
        "## Version: " .. f.version,
        "## Dependencies: AllinOneGuide",
        "## LoadOnDemand: 1",
    }
    if f.icon then L[#L + 1] = "## IconTexture: Interface\\AddOns\\" .. f.folder .. "\\" .. f.icon end
    L[#L + 1] = "## X-License: GPL-3.0-or-later"
    L[#L + 1] = "## X-AOG-Packs: " .. table.concat(packIds, ",")
    L[#L + 1] = ""
    for _, file in ipairs(files) do L[#L + 1] = file end
    return table.concat(L, "\n") .. "\n"
end

-- AllinOneGuide\Data\KnownPacks.lua: what the guide knows about the shipped packs without loading their folders
-- (which folder, title, faction, levels, entry, joins). entries = { { id, folder, header } } in build order.
local KNOWN_KEYS = { "title", "da", "faction", "levels", "entry", "conditions", "joins", "kind" }
function Lib.KnownPacks(folders, entries)
    local L = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2026 gettic",
        "-- Generated by tools\\build.lua from tools\\data\\pack-folders.lua and the pack headers. Never edit by hand.",
        "-- The guide pack addons and their packs, known without loading them (Packs\\Loader.lua).",
        "local _, ns = ...",
        "ns.KnownPacks = {",
        "    folders = {",
    }
    for _, f in ipairs(folders) do
        L[#L + 1] = ("        { folder = %q, faction = %q, title = %q },"):format(f.folder, f.faction or "Neutral", f.title)
    end
    L[#L + 1] = "    },"
    L[#L + 1] = "    packs = {"
    local sorted = {}
    for _, e in ipairs(entries) do sorted[#sorted + 1] = e end
    table.sort(sorted, function(a, b) return a.id < b.id end)
    for _, e in ipairs(sorted) do
        local t = { folder = e.folder }
        for _, k in ipairs(KNOWN_KEYS) do t[k] = e.header[k] end
        L[#L + 1] = ("        [%q] = %s,"):format(e.id, Lit(t))
    end
    L[#L + 1] = "    },"
    L[#L + 1] = "}"
    return table.concat(L, "\n") .. "\n"
end

return Lib

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
            out[#out + 1] = s
        end
    end
end

-- Returns routes = { { id, title, da, sections = { { title, da, first } }, steps = { ... } } }, errors
function Lib.Expand(pack)
    local routes, errs = {}, {}
    for _, r in ipairs(pack.routes) do
        local route = { id = r.id, title = r.title, da = r.da, sections = {}, steps = {} }
        for _, sec in ipairs(r.sections or {}) do
            route.sections[#route.sections + 1] = { title = sec.title, da = sec.da, first = #route.steps + 1 }
            Expand(pack, sec.steps or {}, 0, nil, nil, nil, nil, route.steps, errs)
        end
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
    L[#L + 1] = "local _, ns = ..."
    local header = {}
    for k, v in pairs(pack) do if not HEADER_SKIP[k] then header[k] = v end end
    L[#L + 1] = "ns.Packs.Register(" .. Lit(header) .. ", {"
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

return Lib

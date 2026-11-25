-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Pack format v1: the one row decoder / encoder (packs-src\FORMAT.md). Shared by the addon, the build
-- script and the pack checker, so all three read rows the same way. Depends on nothing else in ns.
-- Row: id|type|quest|npc|map|x|y|r|text|da|flags|cond|src|extra   (extra = key=value;key=value)
local _, ns = ...
-- Format 2 (v0.2) adds step types, the `optional` flag and extra keys; rows look the same, so a v0.1 reader
-- shows the new types as manual steps (packs using them write formatVersion = 2, minFormat = 1).
local Fm = { VERSION = 2 }
ns.Format = Fm

Fm.FIELDS = { "id", "type", "quest", "npc", "map", "x", "y", "r", "text", "da", "flags", "cond", "src", "extra" }
Fm.TYPES = { accept = true, turnin = true, objective = true, ["goto"] = true, level = true,
    -- format 2
    learn = true, fly = true, getfp = true, sethearth = true, hearth = true, useitem = true, train = true, note = true,
    grind = true }
Fm.FLAGS = { elite = true, group = true, deadly = true, ahStep = true, tradeStep = true, extra = true, future = true,
    noAutoAccept = true, walk = true, leaveArea = true, grind = true,
    optional = true }   -- format 2
Fm.SOURCES = { own = true, rec = true, lookup = true, wiki = true, client = true, questie = true, forevdb = true,
    codex = true, cmangos = true, lpdb = true, att = true, legacy = true }
-- extra keys and their kinds: "number", "string", "list" (numbers, comma-separated), "bool"
Fm.EXTRA = { obj = "list", any = "number", override = "string", whileUntil = "string", leadsTo = "string",
    why = "string", level = "number", item = "number", count = "number", useItem = "number", targetNpc = "number",
    model = "number", useWhen = "string", classQuest = "number", qname = "string", seen = "string",
    confirmed = "bool", knownIssue = "number", inc = "string",
    -- format 2: any-order group id (`anyOrder`; not the `group` flag, which means "needs a group"), accept
    -- source (npc / item / object), pre-quests, quest XP, minutes, taxi node, inn (the bind location the
    -- route expects), spell, minimum level, dungeon id (for the repeat check)
    anyOrder = "string", from = "string", pre = "list", xp = "number", estMin = "number", node = "number",
    inn = "string", spell = "number", minLevel = "number", dungeon = "string",
    -- smart arrow: the step's own way (connector ids and inline points, or false = straight), and the
    -- connector room the goal is in (written by the build from packs-src\connectors\)
    via = "via", room = "string",
    -- travel side goals: this background goal was written as an `onWay` entry of the step with this id
    onWay = "string" }
Fm.DEFAULT_RADIUS = 10

local tonumber, tostring, concat, sort = tonumber, tostring, table.concat, table.sort

function Fm.Escape(s, inExtra)
    s = tostring(s):gsub("%%", "%%25"):gsub("|", "%%7C")
    if inExtra then s = s:gsub(";", "%%3B"):gsub("=", "%%3D") end
    return s
end

function Fm.Unescape(s)
    if not s:find("%", 1, true) then return s end
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Numbers written plainly: integers as integers, others with at most 2 decimals, no exponent.
function Fm.Num(n)
    n = tonumber(n)
    if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
    local s = string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function Split(row, sep, out)
    local n, pos = 0, 1
    while true do
        local s = row:find(sep, pos, true)
        n = n + 1
        if not s then
            out[n] = row:sub(pos)
            return n
        end
        out[n] = row:sub(pos, s - 1)
        pos = s + 1
    end
end
Fm.Split = Split

-- `via` in a row: "-" = false (point straight); else comma-separated items, each a connector id or an inline
-- point "map/x/y" or "map/x/y/HINT_KEY" (x / y in percent, like the sources).
local function DecodeVia(v)
    if v == "-" then return false end
    local list = {}
    for item in v:gmatch("[^,]+") do
        local map, x, y, rest = item:match("^(%d+)/([%d%.]+)/([%d%.]+)(.*)$")
        if map then
            local hint = rest:match("^/([%w_]+)$")
            list[#list + 1] = { map = tonumber(map), x = tonumber(x), y = tonumber(y), hint = hint }
        else
            list[#list + 1] = item
        end
    end
    return list
end
Fm.DecodeVia = DecodeVia

function Fm.EncodeVia(v)
    if v == false then return "-" end
    local items = {}
    for i, item in ipairs(v) do
        if type(item) == "table" then
            local s = Fm.Num(item.map) .. "/" .. Fm.Num(item.x) .. "/" .. Fm.Num(item.y)
            if item.hint then s = s .. "/" .. tostring(item.hint) end
            items[i] = s
        else
            items[i] = tostring(item)
        end
    end
    return concat(items, ",")
end

local parts, kv = {}, {}

local function Opt(s) if s == "" then return nil end return s end
local function OptNum(s) if s == "" then return nil end return tonumber(s) end

-- Decodes one row into a plain step table. Returns step or nil, error.
-- Forward compatible: extra fields after the 14th and unknown extra keys are ignored; an unknown type
-- becomes "manual" (the original is kept in step.origType).
function Fm.DecodeRow(row)
    if type(row) ~= "string" or row == "" then return nil, "empty row" end
    if row:find("[\r\n]") then return nil, "line break in row" end
    local n = Split(row, "|", parts)
    if n < 2 then return nil, "too few fields" end
    local step = {}
    step.id = parts[1]
    if step.id == "" then return nil, "no id" end
    local t = parts[2]
    if Fm.TYPES[t] then step.type = t else step.type, step.origType = "manual", t end
    step.quest = OptNum(parts[3] or "")
    step.npc = OptNum(parts[4] or "")
    step.map = OptNum(parts[5] or "")
    local x, y = OptNum(parts[6] or ""), OptNum(parts[7] or "")
    if x and y then step.x, step.y = x / 100, y / 100 end
    step.r = OptNum(parts[8] or "")
    local text = Opt(parts[9] or "")
    step.text = text and Fm.Unescape(text)
    local da = Opt(parts[10] or "")
    step.da = da and Fm.Unescape(da)
    local flags = {}
    if (parts[11] or "") ~= "" then
        for f in parts[11]:gmatch("[^,]+") do flags[f] = true end
    end
    step.flags = flags
    local cond = Opt(parts[12] or "")
    step.cond = cond and Fm.Unescape(cond)
    step.src = Opt(parts[13] or "")
    local extra = parts[14] or ""
    if extra ~= "" then
        local m = Split(extra, ";", kv)
        for i = 1, m do
            local k, v = kv[i]:match("^([%w_]+)=(.*)$")
            local kind = k and Fm.EXTRA[k]
            if kind then
                v = Fm.Unescape(v)
                if kind == "number" then
                    step[k] = tonumber(v)
                elseif kind == "bool" then
                    step[k] = (v == "1")
                elseif kind == "via" then
                    step[k] = DecodeVia(v)
                elseif kind == "list" then
                    local list = {}
                    for item in v:gmatch("[^,]+") do list[#list + 1] = tonumber(item) or item end
                    step[k] = list
                else
                    step[k] = v
                end
            end
        end
    end
    for i = 1, n do parts[i] = nil end
    return step
end

-- The id of a row without decoding it (for the id index).
function Fm.RowId(row)
    if type(row) ~= "string" then return nil end
    return row:match("^([^|]*)")
end

-- Encodes a source step (x / y in percent) into a row. Used by the build script.
-- Fields that aren't row fields or known extra keys are an error.
function Fm.EncodeRow(s)
    local out = {}
    local function Field(v, isText)
        if v == nil then return "" end
        if type(v) == "number" then return Fm.Num(v) end
        if isText then return Fm.Escape(v) end
        return tostring(v)
    end
    out[1] = Field(s.id)
    out[2] = Field(s.type)
    out[3] = Field(s.quest)
    out[4] = Field(s.npc)
    out[5] = Field(s.map)
    out[6] = Field(s.x)
    out[7] = Field(s.y)
    out[8] = Field(s.r)
    out[9] = Field(s.text, true)
    out[10] = Field(s.da, true)
    out[11] = s.flags and concat(s.flags, ",") or ""
    out[12] = Field(s.cond, true)
    out[13] = Field(s.src)
    local keys = {}
    for k in pairs(s) do
        if Fm.EXTRA[k] and s[k] ~= nil then keys[#keys + 1] = k end
    end
    sort(keys)
    local ex = {}
    for _, k in ipairs(keys) do
        local v, kind = s[k], Fm.EXTRA[k]
        local text
        if kind == "via" then
            text = Fm.EncodeVia(v)
        elseif kind == "list" then
            local items = {}
            for i, item in ipairs(v) do items[i] = type(item) == "number" and Fm.Num(item) or tostring(item) end
            text = concat(items, ",")
        elseif kind == "bool" then
            text = v and "1" or "0"
        elseif type(v) == "number" then
            text = Fm.Num(v)
        else
            text = tostring(v)
        end
        ex[#ex + 1] = k .. "=" .. Fm.Escape(text, true)
    end
    out[14] = concat(ex, ";")
    return concat(out, "|")
end

-- A pack can be read when its minFormat is not newer than ours (formatVersion may be newer).
function Fm.CanRead(header)
    local minFormat = tonumber(header and header.minFormat) or tonumber(header and header.formatVersion) or 1
    return minFormat <= Fm.VERSION
end

-- v0.2 M5: Adler-32 as 8 hex digits, plain arithmetic (no bit library: the same in the game's Lua 5.1, LuaJIT
-- and the report decoder). Shared by the report string (Data\Report.lua) and plans\tools\report-decode.lua.
function Fm.Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return ("%04x%04x"):format(b, a)
end

-- A step's content hash (8 hex digits): type, quest, map, x, y and English text of a decoded step. A report
-- carries it so the decoder can tell whether the step changed since the report was made.
function Fm.StepHash(step)
    local function F(v)
        if v == nil then return "" end
        if type(v) == "number" then return Fm.Num(v) end
        return tostring(v)
    end
    return Fm.Adler32(concat({ F(step.type), F(step.quest), F(step.map), F(step.x), F(step.y), F(step.text) }, "|"))
end

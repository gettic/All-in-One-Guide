-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Pack format v1: the one row decoder / encoder (packs-src\FORMAT.md). Shared by the addon, the build
-- script and the pack checker, so all three read rows the same way. Depends on nothing else in ns.
-- Row: id|type|quest|npc|map|x|y|r|text|da|flags|cond|src|extra   (extra = key=value;key=value)
local _, ns = ...
local Fm = { VERSION = 1 }
ns.Format = Fm

Fm.FIELDS = { "id", "type", "quest", "npc", "map", "x", "y", "r", "text", "da", "flags", "cond", "src", "extra" }
Fm.TYPES = { accept = true, turnin = true, objective = true, ["goto"] = true, level = true }
Fm.FLAGS = { elite = true, group = true, deadly = true, ahStep = true, tradeStep = true, extra = true, future = true,
    noAutoAccept = true, walk = true, leaveArea = true, grind = true }
Fm.SOURCES = { own = true, rec = true, lookup = true, wiki = true, client = true, questie = true, forevdb = true,
    codex = true, cmangos = true, lpdb = true, att = true, legacy = true }
-- extra keys and their kinds: "number", "string", "list" (numbers, comma-separated), "bool"
Fm.EXTRA = { obj = "list", any = "number", override = "string", whileUntil = "string", leadsTo = "string",
    why = "string", level = "number", item = "number", count = "number", useItem = "number", targetNpc = "number",
    model = "number", useWhen = "string", classQuest = "number", qname = "string", seen = "string",
    confirmed = "bool", knownIssue = "number", inc = "string" }
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
        if Fm.EXTRA[k] then keys[#keys + 1] = k end
    end
    sort(keys)
    local ex = {}
    for _, k in ipairs(keys) do
        local v, kind = s[k], Fm.EXTRA[k]
        local text
        if kind == "list" then
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

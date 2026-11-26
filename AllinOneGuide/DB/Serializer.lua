-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The one serializer for every string that can leave the PC (status line, error copy text; the report
-- string from v0.2). Each kind has an allowlist of fields; anything else is refused. Values are plain
-- numbers, booleans or short strings; "|", ";", "=" and line breaks are escaped. It never reads saves.
local _, ns = ...
local Ser = {}
ns.Serializer = Ser

Ser.kinds = {
    status = { "v", "client", "st", "on", "off", "safe", "ro", "err", "login", "mem" },
    -- v0.2 M5: the report string "AOGR2 ..." (Data\Report.lua; plans\tools\report-decode.lua reads it).
    -- Fields: report id, addon version, client line, self-test line, language, type (about), pack / pack
    -- version / format / route, step id / step hash / include path, quest state, condition result, level,
    -- XP %, faction, race, class, Hardcore, map / x / y / radius / distance, location removed, NPC id
    -- (evidence), knownIssue, other addons, last 3 steps, engine lines, note. Never a name.
    R2 = { "rid", "v", "c", "st", "lang", "ab", "pk", "pv", "fv", "rt", "sid", "sh", "inc", "qs", "cnd", "lv", "xp",
        "fa", "ra", "cl", "hc", "map", "x", "y", "r", "d", "noloc", "npc", "ki", "cf", "l3", "eng", "note" },
    -- v0.2 M6: the dev recorder export "AOGREC1 ..." (Dev\Recorder.lua; tools\recmerge.lua reads it).
    -- Header: h=1, addon version, client line, records on this page, page "i/n". Records: kind, quest,
    -- NPC id, object id, instance id, start item, map, x / y (0-100), sightings, item ids. Never a name.
    REC1 = { "h", "v", "c", "cnt", "pg", "k", "q", "npc", "obj", "ins", "from", "m", "x", "y", "n", "it" },
    -- v0.3 game data pages "AOGD1 ..." (Data\Gather.lua; the Addon Manager and tools\recmerge.lua read them).
    -- Header: page id (random, new per page), h=1, addon version, client build, faction A / H, class token, record
    -- count. Records: ids, map / x / y / cell, counts, XP / money gains, levels, seconds, lists of ids. Never a name.
    D1 = { "rid", "h", "v", "b", "fac", "cls", "race", "realm", "loc", "day", "scr", "ui", "cnt", "k", "q", "npc", "obj", "ins", "from", "m", "x", "y", "c", "n",
        "xp", "mo", "pl", "ql", "it", "loot", "got", "cu", "sh", "gray", "cloth", "herb", "ore", "pk", "s", "t", "fn", "tn",
        "sec", "lo", "hi", "cl", "fa", "gain", "sp", "sk", "lv", "dif", "tries", "ups", "sv", "rc", "sup", "min", "boss", "qs",
        "pz", "pn", "dd", "gs", "gx", "rt", "gph", "ck" },
}
-- kinds whose values are escaped strictly: every byte outside a small plain set becomes %XX (non-ASCII,
-- line breaks, separators), so the string survives any paste
Ser.strict = { R2 = true, REC1 = true, D1 = true }

local function Escape(v)
    local s = tostring(v)
    s = s:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub(";", "%%3B"):gsub("=", "%%3D"):gsub("[\r\n]", " ")
    return s
end
Ser.Escape = Escape

local function StrictEscape(v)
    return (tostring(v):gsub("[^%w %.,:_/%+%(%)'!%?%-]", function(c) return ("%%%02X"):format(c:byte()) end))
end
Ser.StrictEscape = StrictEscape

-- fields = { key = value, ... }; returns "AOG<kind> k=v;k=v" in the allowlist's order.
function Ser.Build(kind, fields)
    local allow = Ser.kinds[kind]
    if not allow then error("serializer: unknown kind " .. tostring(kind), 2) end
    local allowed = {}
    for _, k in ipairs(allow) do allowed[k] = true end
    for k in pairs(fields) do
        if not allowed[k] then error("serializer: field " .. tostring(k) .. " is not allowed in " .. kind, 2) end
    end
    local parts = {}
    for _, k in ipairs(allow) do
        local v = fields[k]
        if v ~= nil then
            local t = type(v)
            if t ~= "string" and t ~= "number" and t ~= "boolean" then
                error("serializer: field " .. k .. " must be plain, got " .. t, 2)
            end
            if t == "boolean" then v = v and 1 or 0 end
            parts[#parts + 1] = k .. "=" .. (Ser.strict[kind] and StrictEscape(v) or Escape(v))
        end
    end
    return "AOG" .. kind .. " " .. table.concat(parts, ";")
end

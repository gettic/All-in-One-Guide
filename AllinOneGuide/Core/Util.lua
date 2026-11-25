-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Small helpers: UTF-8 safe length and cutting, named fields, whole numbers, copies, shown names.
local _, ns = ...
local U = {}
ns.U = U

local byte, sub, floor = string.byte, string.sub, math.floor

-- A real number (not nil, not a string, not NaN).
function U.IsNum(v) return type(v) == "number" and v == v end

-- Number of characters (not bytes) in a UTF-8 string; æ ø å are 2 bytes each.
function U.Utf8Len(s)
    if type(s) ~= "string" then return 0 end
    local n, i, len = 0, 1, #s
    while i <= len do
        local c = byte(s, i)
        i = i + ((c < 0x80 and 1) or (c < 0xE0 and 2) or (c < 0xF0 and 3) or 4)
        n = n + 1
    end
    return n
end

-- Characters first..last (1-based, inclusive), never cutting inside a character.
function U.Utf8Sub(s, first, last)
    if type(s) ~= "string" then return "" end
    first = first or 1
    local n, i, len = 0, 1, #s
    local startByte, endByte = nil, len
    while i <= len do
        n = n + 1
        local c = byte(s, i)
        local size = (c < 0x80 and 1) or (c < 0xE0 and 2) or (c < 0xF0 and 3) or 4
        if n == first then startByte = i end
        if last and n == last then endByte = i + size - 1 break end
        i = i + size
    end
    if not startByte or (last and last < first) then return "" end
    return sub(s, startByte, endByte)
end

-- Cut to at most maxChars characters, ending in "..." when cut. Returns text, wasCut.
function U.Utf8Cut(s, maxChars)
    if type(s) ~= "string" then return "", false end
    if U.Utf8Len(s) <= maxChars then return s, false end
    if maxChars <= 3 then return U.Utf8Sub(s, 1, maxChars), true end
    return U.Utf8Sub(s, 1, maxChars - 3) .. "...", true
end

-- "{count} done" + { count = 3 } -> "3 done". Unknown fields stay visible so tests catch them.
function U.Fill(text, fields)
    if type(text) ~= "string" then return "" end
    if not fields then return text end
    return (text:gsub("{([%w_]+)}", function(k)
        local v = fields[k]
        if v == nil then return "{" .. k .. "}" end
        return tostring(v)
    end))
end

-- Whole numbers only in v0.1 ("123 yd", "63 %"), so no decimal comma is needed for Danish yet.
function U.Whole(n)
    n = tonumber(n)
    if not n or n ~= n then return 0 end
    return floor(n + 0.5)
end

function U.Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Deep copy (cycles kept as cycles). Used for read-only saves and test copies.
function U.Copy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local c = {}
    seen[t] = c
    for k, v in pairs(t) do c[U.Copy(k, seen)] = U.Copy(v, seen) end
    return c
end

-- Every name we ever show goes through here (streamer mode hooks in later). UI code never reads unit
-- names itself (a source check enforces it).
function ns.DisplayName(name)
    if type(name) ~= "string" then return "" end
    return name
end

-- v0.2 M5: takes this character's name and realm (from ns.charKey "Name-Realm") and any GUID out of a
-- text, case-insensitive. Used when a debug line is written and again when a report string is built.
-- Case is ignored for ASCII and for the Latin-1 letters (U+00C0-U+00FE, UTF-8 "\195" + one byte; upper and
-- lower differ by 0x20 in that byte, except the signs x and / at 0x97 / 0xB7). Spaces, hyphens and apostrophes
-- in the text are optional, so "Argent Dawn" also takes "ArgentDawn" and "Argent-Dawn" (the Name-Realm form).
local SEP = "[%s%-']?"
local function PlainPattern(s)
    local out, i, len = {}, 1, #s
    while i <= len do
        local c = byte(s, i)
        if c < 0x80 then
            local ch = sub(s, i, i)
            if ch:match("%a") then
                out[#out + 1] = "[" .. ch:lower() .. ch:upper() .. "]"
            elseif ch == " " or ch == "-" or ch == "'" then
                out[#out + 1] = SEP
            elseif ch:match("%w") then
                out[#out + 1] = ch
            else
                out[#out + 1] = "%" .. ch
            end
            i = i + 1
        else
            local size = (c < 0xE0 and 2) or (c < 0xF0 and 3) or 4
            local ch = sub(s, i, i + size - 1)
            local b2 = byte(s, i + 1)
            if c == 0xC3 and size == 2 and b2 then
                local up, low
                if b2 >= 0x80 and b2 <= 0x9E and b2 ~= 0x97 then up, low = b2, b2 + 0x20
                elseif b2 >= 0xA0 and b2 <= 0xBE and b2 ~= 0xB7 then up, low = b2 - 0x20, b2 end
                if up then ch = "\195[" .. string.char(up) .. string.char(low) .. "]" end
            end
            out[#out + 1] = ch
            i = i + size
        end
    end
    return table.concat(out)
end
U.PlainPattern = PlainPattern
function U.StripNames(s)
    s = tostring(s or "")
    s = s:gsub("%u%a+%-%d+%-[%x%-]+", "<guid>")
    local key = ns.charKey
    if type(key) == "string" then
        local name, realm = key:match("^([^%-]+)%-(.+)$")
        for _, part in ipairs({ name, realm }) do
            if type(part) == "string" and #part >= 2 and part ~= "?" then s = s:gsub(PlainPattern(part), "<me>") end
        end
    end
    return s
end

-- Strips WoW escape codes and line breaks (for one-line, copyable text).
function U.Plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "/"):gsub("[\r\n]+", " ")
    return s
end

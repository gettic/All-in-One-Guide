-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- A parser for Lua table literals, for reading other projects' data dumps as DATA ONLY: nothing in the
-- input is ever run (no loadfile, no loadstring, no environment). It accepts:
--   [return] value          or   name[.name...] = value      (one or more assignments; the last one wins)
--   value := nil | true | false | number | string | table
--   table := { [key] = value, name = value, value, ... }  (separators "," or ";")
--   strings: "..." / '...' with Lua escapes, [[...]] / [==[...]==]; numbers: decimal, hex, a leading "-"
--   comments: -- line, --[[ block ]]
-- Anything else (a function call, an operator, a name used as a value, "..") is refused with a message.
-- Caps (all refusals, never truncation): input size, nesting depth, number of values.
-- Use: local LD = assert(loadfile("tools/import/luadata.lua"))()
--      local value, err = LD.Parse(text, { maxBytes = 16 * 1024 * 1024, maxDepth = 16, maxItems = 2000000 })
local LD = { MAX_BYTES = 16 * 1024 * 1024, MAX_DEPTH = 16, MAX_ITEMS = 2000000 }

local ESC = { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"',
    ["'"] = "'", ["\n"] = "\n" }

function LD.Parse(s, opts)
    opts = opts or {}
    if type(s) ~= "string" then return nil, "input is not text" end
    local maxBytes = opts.maxBytes or LD.MAX_BYTES
    local maxDepth = opts.maxDepth or LD.MAX_DEPTH
    local maxItems = opts.maxItems or LD.MAX_ITEMS
    if #s > maxBytes then return nil, ("input is %d bytes, the cap is %d"):format(#s, maxBytes) end
    local pos, n, items = 1, #s, 0
    if s:sub(1, 3) == "\239\187\191" then pos = 4 end        -- UTF-8 byte order mark

    local function Fail(msg)
        local line = 1
        for _ in s:sub(1, pos):gmatch("\n") do line = line + 1 end
        error({ msg = ("line %d: %s"):format(line, msg) }, 0)
    end

    local function LongBracket()
        local eq = s:match("^%[(=*)%[", pos)
        if not eq then return nil end
        local close = "]" .. eq .. "]"
        local start = pos + #eq + 2
        local stop = s:find(close, start, true)
        if not stop then Fail("long string or comment not closed") end
        local text = s:sub(start, stop - 1)
        if text:sub(1, 2) == "\r\n" then text = text:sub(3) elseif text:sub(1, 1) == "\n" then text = text:sub(2) end
        pos = stop + #close
        return text
    end

    local function Skip()
        while pos <= n do
            local c = s:sub(pos, pos)
            if c == " " or c == "\t" or c == "\r" or c == "\n" or c == "\f" or c == "\v" then
                pos = pos + 1
            elseif s:sub(pos, pos + 1) == "--" then
                pos = pos + 2
                if not (s:sub(pos, pos) == "[" and LongBracket()) then
                    local e = s:find("\n", pos, true)
                    pos = e and e + 1 or n + 1
                end
            else
                return
            end
        end
    end

    local function QuotedString(q)
        pos = pos + 1
        local out = {}
        while true do
            if pos > n then Fail("string not closed") end
            local c = s:sub(pos, pos)
            if c == q then pos = pos + 1 break end
            if c == "\n" then Fail("line break inside a quoted string") end
            if c == "\\" then
                local d = s:sub(pos + 1, pos + 1)
                if ESC[d] then
                    out[#out + 1] = ESC[d]
                    pos = pos + 2
                elseif d:match("%d") then
                    local digits = s:match("^%d%d?%d?", pos + 1)
                    local v = tonumber(digits)
                    if v > 255 then Fail("bad escape \\" .. digits) end
                    out[#out + 1] = string.char(v)
                    pos = pos + 1 + #digits
                else
                    Fail("bad escape \\" .. d)
                end
            else
                local e = s:find("[\\\n" .. q .. "]", pos)
                if not e then Fail("string not closed") end
                out[#out + 1] = s:sub(pos, e - 1)
                pos = e
            end
        end
        return table.concat(out)
    end

    local function Number()
        local neg = false
        if s:sub(pos, pos) == "-" then
            neg = true
            pos = pos + 1
            Skip()
        end
        local hex = s:match("^0[xX]%x+", pos)
        local text = hex or s:match("^%d+%.?%d*[eE][%+%-]?%d+", pos) or s:match("^%d+%.?%d*", pos)
            or s:match("^%.%d+[eE][%+%-]?%d+", pos) or s:match("^%.%d+", pos)
        if not text then Fail("expected a value") end
        pos = pos + #text
        if s:match("^[%w_]", pos) then Fail("bad number") end
        local v = tonumber(text)
        if not v then Fail("bad number " .. text) end
        return neg and -v or v
    end

    local Value

    local function Table(depth)
        if depth > maxDepth then Fail(("nested deeper than %d"):format(maxDepth)) end
        pos = pos + 1
        local t, i = {}, 0
        while true do
            Skip()
            local c = s:sub(pos, pos)
            if c == "" then Fail("table not closed") end
            if c == "}" then pos = pos + 1 return t end
            local key
            if c == "[" and not s:match("^%[=*%[", pos) then
                pos = pos + 1
                Skip()
                key = Value(depth + 1)
                Skip()
                if s:sub(pos, pos) ~= "]" then Fail("expected ]") end
                pos = pos + 1
                Skip()
                if s:sub(pos, pos) ~= "=" then Fail("expected =") end
                pos = pos + 1
                if key == nil then Fail("nil table key") end
                if key ~= key then Fail("NaN table key") end
            else
                local name = s:match("^[%a_][%w_]*", pos)
                if name and s:match("^%s*=[^=]", pos + #name) then
                    key = name
                    pos = pos + #name
                    Skip()
                    pos = pos + 1
                end
            end
            Skip()
            local v = Value(depth + 1)
            if key == nil then
                i = i + 1
                key = i
            end
            t[key] = v
            Skip()
            c = s:sub(pos, pos)
            if c == "," or c == ";" then
                pos = pos + 1
            elseif c ~= "}" then
                Fail("expected , or }")
            end
        end
    end

    Value = function(depth)
        Skip()
        items = items + 1
        if items > maxItems then Fail(("more than %d values"):format(maxItems)) end
        local c = s:sub(pos, pos)
        if c == "{" then return Table(depth) end
        if c == '"' or c == "'" then return QuotedString(c) end
        if c == "[" then
            local text = LongBracket()
            if text then return text end
            Fail("unexpected [")
        end
        local word = s:match("^[%a_][%w_]*", pos)
        if word then
            if word == "true" or word == "false" or word == "nil" then
                pos = pos + #word
                if word == "nil" then return nil end
                return word == "true"
            end
            Fail("not data: the name " .. word .. " (code is never run)")
        end
        if c == "-" or c == "." or c:match("%d") then return Number() end
        Fail("not data: " .. (c == "" and "end of input" or ("'" .. c .. "'")))
    end

    local ok, res = pcall(function()
        Skip()
        local result
        local any = false
        while pos <= n do
            if s:match("^return[^%w_]", pos) or s:sub(pos) == "return" then
                pos = pos + 6
                result = Value(1)
                any = true
                Skip()
                if s:sub(pos, pos) == ";" then pos = pos + 1 end
                Skip()
                if pos <= n then Fail("text after return") end
                break
            end
            local name = s:match("^local%s+[%a_][%w_]*", pos) or s:match("^[%a_][%w_]*[%.%w_]*", pos)
            if not name then Fail("expected return or name = value") end
            pos = pos + #name
            Skip()
            if s:sub(pos, pos) ~= "=" or s:sub(pos + 1, pos + 1) == "=" then Fail("expected = after " .. name) end
            pos = pos + 1
            result = Value(1)
            any = true
            Skip()
            if s:sub(pos, pos) == ";" then pos = pos + 1 end
            Skip()
        end
        if not any then Fail("no data") end
        return result
    end)
    if not ok then
        if type(res) == "table" then return nil, res.msg end
        return nil, tostring(res)
    end
    return res
end

-- Writes a value back as a Lua literal (sorted keys, %q strings): deterministic, and loadable as data only.
function LD.Write(v, indent, depth)
    indent, depth = indent or "", depth or 0
    local t = type(v)
    if t == "string" then return (("%q"):format(v):gsub("\\\n", "\\n")) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("number not writable") end
        if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return ("%d"):format(v) end
        return ("%.14g"):format(v)
    end
    if t == "boolean" or t == "nil" then return tostring(v) end
    if t ~= "table" then error("value not writable: " .. t) end
    if depth > LD.MAX_DEPTH then error("nested too deep to write") end
    local n = #v
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    local parts = {}
    local flat = true
    for i = 1, n do
        if type(v[i]) == "table" then flat = false end
        parts[#parts + 1] = LD.Write(v[i], indent .. "    ", depth + 1)
    end
    for _, k in ipairs(keys) do
        if type(v[k]) == "table" then flat = false end
        local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. LD.Write(k) .. "]")
        parts[#parts + 1] = ks .. " = " .. LD.Write(v[k], indent .. "    ", depth + 1)
    end
    if #parts == 0 then return "{}" end
    if flat then return "{ " .. table.concat(parts, ", ") .. " }" end
    return "{\n" .. indent .. "    " .. table.concat(parts, ",\n" .. indent .. "    ") .. ",\n" .. indent .. "}"
end

return LD

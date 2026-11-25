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
}

local function Escape(v)
    local s = tostring(v)
    s = s:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub(";", "%%3B"):gsub("=", "%%3D"):gsub("[\r\n]", " ")
    return s
end
Ser.Escape = Escape

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
            parts[#parts + 1] = k .. "=" .. Escape(v)
        end
    end
    return "AOG" .. kind .. " " .. table.concat(parts, ";")
end

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Writes AllinOneGuide\Data\ItemNames.lua: item id -> English item name, only for the items the shipped guide packs
-- name: a step's `item` / `useItem`, `item=<id>` in a `cond`, `{item:<id>}` tokens in step texts, and the quest items
-- (Data\QuestItems.lua) of the quests the packs use. The item pictures (UI\ItemIcons.lua) put the item's icon before
-- its name in the step text and use these names when the game hasn't loaded the item yet.
-- Source: a LOCAL CMaNGOS classic-db SQL dump (https://github.com/cmangos/classic-db, GPL-3.0), read as TEXT only:
-- `item_template` entry (field 1) and name (field 4). Forever-only items aren't in it; the game's own name is used.
-- Run from the repository folder:
--   luajit tools/item_names.lua <ClassicDB.sql> [--routes AllinOneGuide/Routes] [--out AllinOneGuide/Data/ItemNames.lua]
--   [--check]   write nothing; fail when the file differs (or is missing)
-- Library mode: local IN = loadfile("tools/item_names.lua")("--lib")
--   IN.PackItems(texts, questItemsText) -> sorted ids   IN.ReadNames(path, want) -> { [id] = name }
--   IN.Clean(name) -> name or nil                       IN.Text(map, ids) -> file text
local argv = { ... }
local IN = { MAX = 80 }

-- A compiled row: id|type|quest|npc|map|x|y|r|text|da|flags|cond|src|extra (texts never hold "|").
local function Fields(row)
    local f, i = {}, 1
    for part in (row .. "|"):gmatch("([^|]*)|") do f[i] = part i = i + 1 end
    return f
end

-- The quest items file: [item]={q=quest ...} or {q={a,b} ...} -> { [quest] = { items } }.
local function QuestItemsByQuest(text)
    local out = {}
    for id, body in (text or ""):gmatch("%[(%d+)%]%s*=%s*(%b{})") do
        local q = body:match("q%s*=%s*(%b{})") or body:match("q%s*=%s*(%d+)")
        for qid in tostring(q or ""):gmatch("%d+") do
            local n = tonumber(qid)
            out[n] = out[n] or {}
            out[n][#out[n] + 1] = tonumber(id)
        end
    end
    return out
end

function IN.PackItems(texts, questItemsText)
    local set, quests = {}, {}
    local function Add(v) local n = tonumber(v) if n and n > 0 then set[n] = true end end
    for _, text in ipairs(texts) do
        for row in text:gmatch('\n%s*"([^"\n]*)",?') do
            if row:find("|", 1, true) and select(2, row:gsub("|", "")) >= 12 then
                local f = Fields(row)
                local extra, cond = f[14] or "", f[12] or ""
                Add(extra:match("%f[%w]item=(%d+)"))
                Add(extra:match("useItem=(%d+)"))
                for id in cond:gmatch("item=(%d+)") do Add(id) end
                for _, t in ipairs({ f[9] or "", f[10] or "" }) do
                    for id in t:gmatch("{item:(%d+)}") do Add(id) end
                end
                local q = tonumber(f[3])
                if q then quests[q] = true end
            end
        end
    end
    local byQuest = QuestItemsByQuest(questItemsText)
    for q in pairs(quests) do
        for _, id in ipairs(byQuest[q] or {}) do set[id] = true end
    end
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- Plain names only: no escape sequences, line breaks or braces; at most IN.MAX characters.
function IN.Clean(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[|{}\r\n%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > IN.MAX then return nil end
    return name
end

-- One SQL field from position i (a quoted string with \ escapes, NULL or a bare number). Returns value, next i.
local function Field(s, i)
    if s:sub(i, i) == "'" then
        local j, buf = i + 1, {}
        while true do
            local c = s:sub(j, j)
            if c == "" then return nil, j end
            if c == "\\" then buf[#buf + 1] = s:sub(j + 1, j + 1) j = j + 2
            elseif c == "'" then return table.concat(buf), j + 1
            else buf[#buf + 1] = c j = j + 1 end
        end
    end
    local j = s:find("[,)]", i)
    if not j then return nil, #s + 1 end
    return s:sub(i, j - 1), j
end

local PREFIX = "INSERT INTO `item_template` VALUES"
function IN.ReadNames(path, want)
    local fh = io.open(path, "rb")
    if not fh then return nil, "can't open " .. tostring(path) end
    local out = {}
    for line in fh:lines() do
        if line:sub(1, #PREFIX) == PREFIX then
            local i = #PREFIX + 2
            while i <= #line do
                if line:sub(i, i) ~= "(" then
                    i = line:find("(", i, true)
                    if not i then break end
                end
                i = i + 1
                local vals, n = {}, 0
                while true do
                    local v, j = Field(line, i)
                    n = n + 1
                    if n <= 4 then vals[n] = v end
                    local c = line:sub(j, j)
                    i = j + 1
                    if c ~= "," then break end
                end
                local entry = tonumber(vals[1])
                if entry and want[entry] then out[entry] = IN.Clean(vals[4]) end
            end
        end
    end
    fh:close()
    return out
end

local function Quote(s) return ("%q"):format(s) end

function IN.Text(map, ids)
    local lines = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2026 gettic",
        "-- Generated by tools\\item_names.lua from a CMaNGOS classic-db dump (https://github.com/cmangos/classic-db,",
        "-- GPL-3.0; item_template name); do not edit. See CREDITS.txt. Game facts: (c) Blizzard Entertainment.",
        "-- Command: luajit tools/item_names.lua <ClassicDB.sql> (reads the items of AllinOneGuide\\Routes\\*.lua).",
        "-- Item id -> English item name, only for the items the shipped guide packs name. Used by the item pictures",
        "-- (UI\\ItemIcons.lua) when the game hasn't loaded the item yet; Forever-only items use the game's name.",
        "local _, ns = ...",
        "ns.ItemNames = {",
    }
    for _, id in ipairs(ids) do
        if map[id] then lines[#lines + 1] = ("    [%d] = %s,"):format(id, Quote(map[id])) end
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

local function ReadFile(p)
    local fh = io.open(p, "rb")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

local function ListLua(dir)
    local out = {}
    local sep = package.config:sub(1, 1)
    local cmd = sep == "\\" and ('dir /b "' .. dir:gsub("/", "\\") .. '\\*.lua" 2>nul') or ('ls "' .. dir .. '"/*.lua 2>/dev/null')
    local p = io.popen(cmd)
    if p then
        for name in p:lines() do
            name = name:match("([^/\\]+)$")
            if name and name ~= "Connectors.lua" then out[#out + 1] = dir .. "/" .. name end
        end
        p:close()
    end
    table.sort(out)
    return out
end

function IN.Main(args)
    local sql, routes, outPath, check = nil, "AllinOneGuide/Routes", "AllinOneGuide/Data/ItemNames.lua", false
    local qiPath = "AllinOneGuide/Data/QuestItems.lua"
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--routes" then routes = args[i + 1] i = i + 1
        elseif a == "--out" then outPath = args[i + 1] i = i + 1
        elseif a == "--check" then check = true
        else sql = a end
        i = i + 1
    end
    if not sql then
        io.stderr:write("use: luajit tools/item_names.lua <ClassicDB.sql> [--routes dir] [--out file] [--check]\n")
        return 2
    end
    local texts = {}
    for _, p in ipairs(ListLua(routes)) do texts[#texts + 1] = assert(ReadFile(p)) end
    local ids = IN.PackItems(texts, ReadFile(qiPath))
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    local map, err = IN.ReadNames(sql, want)
    if not map then io.stderr:write(err .. "\n") return 1 end
    local text = IN.Text(map, ids)
    local found = 0
    for _ in pairs(map) do found = found + 1 end
    if check then
        if ReadFile(outPath) ~= text then
            io.stderr:write(outPath .. " is out of date (run tools/item_names.lua)\n")
            return 1
        end
        print(("item names: up to date (%d of %d pack items)"):format(found, #ids))
        return 0
    end
    local fh = assert(io.open(outPath, "wb"))
    fh:write(text)
    fh:close()
    print(("item names: %d of %d pack items -> %s"):format(found, #ids, outPath))
    return 0
end

if argv[1] == "--lib" then return IN end
os.exit(IN.Main(argv))

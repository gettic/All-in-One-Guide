-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Reader for a Questie-shaped quest / NPC / object dump (positional records with a key table, spawns per
-- zone, data that may itself be stored as a string). Turns it into the importer's plain records.
--
-- IMPORTANT: this reader is built and tested only on our hand-made samples (plans\v0.2\import-samples\,
-- made-up ids). The real Questie layout must be checked and KEYS / Spawns adapted after the user's yes to
-- download it (plans\v0.2\data-update-flow.md). Nothing here was copied from Questie.
--
-- Names in the dump (quest titles, NPC names) are never kept: packs store ids only.
-- Use: local Q = assert(loadfile("tools/import/questie.lua"))(LD)   (LD = tools/import/luadata.lua)
local LD = ...
local Q = {}

-- Default field positions; a dump may bring its own `questKeys` / `npcKeys` / `objectKeys` tables.
-- (Sample layout. Adapt to the real format after the download yes.)
Q.KEYS = {
    quest = { name = 1, startedBy = 2, finishedBy = 3, requiredLevel = 4, questLevel = 5, preQuest = 6, zone = 7, prov = 8 },
    npc = { name = 1, spawns = 2, prov = 3 },
    object = { name = 1, spawns = 2, prov = 3 },
}
Q.MAX_SPAWNS = 20

local function IsId(v) return type(v) == "number" and v >= 1 and v < 1e7 and v == math.floor(v) end

-- A part that may be stored as a string holding a table literal: parsed as data, never run.
local function Part(v, opts)
    if type(v) == "string" then
        local t, err = LD.Parse(v, opts)
        if t == nil then return nil, err end
        return t
    end
    return v
end

local function Ids(list, out)
    out = out or {}
    if type(list) == "number" then
        if IsId(list) then out[#out + 1] = list end
    elseif type(list) == "table" then
        for _, v in ipairs(list) do
            if IsId(v) then out[#out + 1] = v end
        end
    end
    return out
end

-- startedBy / finishedBy = { { npc ids }, { object ids }, { item ids } }
local function Givers(v)
    if type(v) ~= "table" then return nil end
    local g = { npc = Ids(v[1]), obj = Ids(v[2]), item = Ids(v[3]) }
    if #g.npc + #g.obj + #g.item == 0 then return nil end
    for k, list in pairs(g) do if #list == 0 then g[k] = nil end end
    return g
end

-- spawns = { [zoneId] = { { x, y }, ... } }; zones = { [zoneId] = uiMapID } (unknown zone = dropped)
local function Spawns(v, zones, stats)
    local out = {}
    if type(v) ~= "table" then return out end
    local zl = {}
    for z in pairs(v) do if type(z) == "number" then zl[#zl + 1] = z end end
    table.sort(zl)
    for _, z in ipairs(zl) do
        local map = zones[z]
        if not IsId(map) then
            stats.zone = (stats.zone or 0) + 1
        elseif type(v[z]) == "table" then
            for _, p in ipairs(v[z]) do
                local x, y = type(p) == "table" and p[1], type(p) == "table" and p[2]
                if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100
                    and #out < Q.MAX_SPAWNS then
                    out[#out + 1] = { map, math.floor(x * 100 + 0.5) / 100, math.floor(y * 100 + 0.5) / 100 }
                end
            end
        end
    end
    return out
end

-- dump = the parsed top table. Returns meta, records, stats (counts of what was left out and why).
function Q.Read(dump, opts)
    if type(dump) ~= "table" then return nil, "the dump is not a table" end
    local stats = {}
    local zones = Part(dump.zones, opts) or {}
    local recs = {}
    local function Keys(kind)
        local k = dump[kind .. "Keys"]
        return type(k) == "table" and k or Q.KEYS[kind]
    end
    local function Each(kind, part)
        local t, err = Part(dump[part], opts)
        if t == nil then
            if err then error({ msg = part .. ": " .. err }, 0) end
            return
        end
        if type(t) ~= "table" then error({ msg = part .. " is not a table" }, 0) end
        local ids = {}
        for id in pairs(t) do
            if IsId(id) then ids[#ids + 1] = id else stats.invalid = (stats.invalid or 0) + 1 end
        end
        table.sort(ids)
        local K = Keys(kind)
        for _, id in ipairs(ids) do
            local row = t[id]
            if type(row) ~= "table" then
                stats.invalid = (stats.invalid or 0) + 1
            else
                local prov = type(row[K.prov]) == "table" and row[K.prov] or nil
                local r = { kind = kind, id = id, prov = prov }
                if kind == "quest" then
                    local lv, minLv = row[K.questLevel], row[K.requiredLevel]
                    r.level = (type(lv) == "number" and lv >= 1 and lv <= 80) and lv or nil
                    r.minLevel = (type(minLv) == "number" and minLv >= 1 and minLv <= 80) and minLv or nil
                    local pre = Ids(row[K.preQuest])
                    r.pre = #pre > 0 and pre or nil
                    r.start = Givers(row[K.startedBy])
                    r.finish = Givers(row[K.finishedBy])
                else
                    r.spawns = Spawns(row[K.spawns], zones, stats)
                end
                -- every text field except the name is kept for the provenance text check only
                r._text = {}
                for key, pos in pairs(K) do
                    if key ~= "name" and type(row[pos]) == "string" then r._text[#r._text + 1] = row[pos] end
                end
                recs[#recs + 1] = r
            end
        end
    end
    local ok, err = pcall(function()
        Each("quest", "quests")
        Each("npc", "npcs")
        Each("object", "objects")
    end)
    if not ok then return nil, type(err) == "table" and err.msg or tostring(err) end
    return type(dump.meta) == "table" and dump.meta or nil, recs, stats
end

return Q

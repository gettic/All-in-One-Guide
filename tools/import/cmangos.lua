-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Reader for a LOCAL CMaNGOS classic-db SQL dump (https://github.com/cmangos/classic-db, GPL-3.0; its
-- COPYRIGHT.md: Blizzard material is not theirs to license). The dump is parsed as TEXT only (never loaded into a
-- database, never run). Only numbers are kept: creature spawns (entry, map, world x, y) and the quest relations
-- (which creature / game object starts or ends which quest). Used by tools\import\questie-audit.lua as the
-- second source; its output stays local (plans\).
--
-- World coordinates are turned into zone map percent with a per-map linear fit (x% = a + b * worldY,
-- y% = c + d * worldX) made from NPCs that both sources have exactly once; the fit is 4 numbers per map, so a
-- single NPC's cmangos position stays independent of its QuestieDB position.
-- Use: local CM = assert(loadfile("tools/import/cmangos.lua"))()
local CM = {}

-- uiMapID -> continent (0 = Eastern Kingdoms, 1 = Kalimdor)
CM.CONTINENT = {}
for _, m in ipairs({ 1411, 1412, 1413, 1414, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449,
    1450, 1451, 1452, 1454, 1456, 1457 }) do CM.CONTINENT[m] = 1 end
for _, m in ipairs({ 1415, 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429, 1430,
    1431, 1432, 1433, 1434, 1435, 1436, 1437, 1453, 1455, 1458 }) do CM.CONTINENT[m] = 0 end

local NUM = "([%-%d%.eE]+)"

-- Returns db = { creatures = { [entry] = { { map, x, y }, ... } }, cStart = { [quest] = { [entry] = true } },
-- cEnd, oStart, oEnd (same shape) }, or nil, error.
function CM.Read(path)
    local fh = io.open(path, "rb")
    if not fh then return nil, "can't open " .. path end
    local db = { creatures = {}, cStart = {}, cEnd = {}, oStart = {}, oEnd = {} }
    local REL = { creature_questrelation = db.cStart, creature_involvedrelation = db.cEnd,
        gameobject_questrelation = db.oStart, gameobject_involvedrelation = db.oEnd }
    for line in fh:lines() do
        local tbl = line:match("^INSERT INTO `([%w_]+)` VALUES ")
        if tbl == "creature" then
            -- (guid, id, map, spawnMask, position_x, position_y, ...)
            for _, id, map, x, y in line:gmatch("%((%d+),(%d+),(%d+),%d+," .. NUM .. "," .. NUM .. ",") do
                id, map = tonumber(id), tonumber(map)
                if id > 0 and (map == 0 or map == 1) then
                    local list = db.creatures[id] or {}
                    db.creatures[id] = list
                    list[#list + 1] = { map, tonumber(x), tonumber(y) }
                end
            end
        elseif tbl and REL[tbl] then
            local t = REL[tbl]
            for id, quest in line:gmatch("%((%d+),(%d+)%)") do
                quest = tonumber(quest)
                t[quest] = t[quest] or {}
                t[quest][tonumber(id)] = true
            end
        end
    end
    fh:close()
    return db
end

-- Least squares of v = a + b * u. Returns a, b.
local function Fit(pairs_)
    local n, su, sv, suu, suv = 0, 0, 0, 0, 0
    for _, p in ipairs(pairs_) do
        n = n + 1
        su, sv, suu, suv = su + p[1], sv + p[2], suu + p[1] * p[1], suv + p[1] * p[2]
    end
    local den = n * suu - su * su
    if n < 2 or den == 0 then return nil end
    local b = (n * suv - su * sv) / den
    return (sv - b * su) / n, b
end

-- questie = { [npc] = { { uiMap, x%, y% }, ... } } (all NPCs). Returns fits = { [uiMap] = { a, b, c, d, n, rms } }.
function CM.Calibrate(questie, creatures)
    local byMap = {}
    for id, qp in pairs(questie) do
        local cp = creatures[id]
        if #qp == 1 and cp and #cp == 1 then
            local m = qp[1][1]
            if CM.CONTINENT[m] == cp[1][1] and m ~= 1414 and m ~= 1415 then
                byMap[m] = byMap[m] or {}
                local l = byMap[m]
                l[#l + 1] = { wx = cp[1][2], wy = cp[1][3], px = qp[1][2], py = qp[1][3] }
            end
        end
    end
    local fits = {}
    for m, list in pairs(byMap) do
        local use = list
        local a, b, c, d
        for _ = 1, 3 do
            local xs, ys = {}, {}
            for _, p in ipairs(use) do xs[#xs + 1] = { p.wy, p.px } ys[#ys + 1] = { p.wx, p.py } end
            a, b = Fit(xs)
            c, d = Fit(ys)
            if not a or not c then break end
            -- drop pairs more than 1 % off (moved NPCs, wrong zone), then fit again
            local keep = {}
            for _, p in ipairs(use) do
                if math.abs(a + b * p.wy - p.px) <= 1 and math.abs(c + d * p.wx - p.py) <= 1 then keep[#keep + 1] = p end
            end
            if #keep < 5 then break end
            use = keep
        end
        if a and c and #use >= 5 and b < 0 and d < 0 then
            local s = 0
            for _, p in ipairs(use) do s = s + (a + b * p.wy - p.px) ^ 2 + (c + d * p.wx - p.py) ^ 2 end
            local rms = math.sqrt(s / #use)
            -- a fit worse than 1 % (about 35-70 yd) can't confirm anything: leave the map out
            if rms <= 1 then fits[m] = { a, b, c, d, n = #use, rms = rms } end
        end
    end
    return fits
end

-- cmangos spawns of `entry` on uiMap `m` as zone percent { { x, y }, ... } (only points inside 0-100).
function CM.ZonePoints(db, fits, entry, m)
    local f = fits[m]
    local out = {}
    if not f then return out end
    for _, p in ipairs(db.creatures[entry] or {}) do
        if p[1] == CM.CONTINENT[m] then
            local x, y = f[1] + f[2] * p[3], f[3] + f[4] * p[2]
            if x >= 0 and x <= 100 and y >= 0 and y <= 100 then out[#out + 1] = { x, y } end
        end
    end
    return out
end

return CM

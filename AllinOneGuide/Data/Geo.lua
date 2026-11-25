-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Geo service: the player's map position, world positions of map points (cached) and distances
-- in yards. Different continents (or no data) give nil, never a wrong number.
local _, ns = ...
local Co = ns.Compat
local Geo = { cache = {}, cacheSize = 0, CACHE_MAX = 256 }
ns.Geo = Geo

-- map, x, y of the player, or nil.
function Geo.Player()
    if not ns.Feature.IsOn("position") then return nil end
    local map = Co.PlayerMap()
    if not map then return nil end
    local x, y = Co.PlayerPos(map)
    if not x then return nil end
    return map, x, y
end

-- continent, wx, wy (yards) of a map point; cached because step points repeat.
function Geo.World(map, x, y)
    if not ns.Feature.IsOn("worldpos") then return nil end
    if not (ns.U.IsNum(map) and ns.U.IsNum(x) and ns.U.IsNum(y)) then return nil end
    -- x, y are 0-1, so each part is 0..10000: y < 1e5, x * 1e5 < 1e10, map * 1e10 (all exact in a double)
    local key = map * 1e10 + math.floor(x * 1e4 + 0.5) * 1e5 + math.floor(y * 1e4 + 0.5)
    local c = Geo.cache[key]
    if c then return c[1], c[2], c[3] end
    local continent, wx, wy = Co.WorldPos(map, x, y)
    if not continent then return nil end
    if Geo.cacheSize >= Geo.CACHE_MAX then
        Geo.cache, Geo.cacheSize = {}, 0
    end
    Geo.cache[key] = { continent, wx, wy }
    Geo.cacheSize = Geo.cacheSize + 1
    return continent, wx, wy
end

function Geo.Distance(map1, x1, y1, map2, x2, y2)
    local c1, ax, ay = Geo.World(map1, x1, y1)
    local c2, bx, by = Geo.World(map2, x2, y2)
    if not c1 or not c2 or c1 ~= c2 then return nil end
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

-- Direction from point 1 to point 2 in radians, counter-clockwise from north (the same way
-- GetPlayerFacing counts), and the distance in yards; nil when it can't be worked out.
-- World x points north and world y points west.
function Geo.Bearing(map1, x1, y1, map2, x2, y2)
    local c1, ax, ay = Geo.World(map1, x1, y1)
    local c2, bx, by = Geo.World(map2, x2, y2)
    if not c1 or not c2 or c1 ~= c2 then return nil end
    local north, west = bx - ax, by - ay
    return math.atan2(west, north), math.sqrt(north * north + west * west)
end

-- Yards from the player to a map point, or nil.
function Geo.PlayerDistance(map, x, y)
    local pm, px, py = Geo.Player()
    if not pm then return nil end
    return Geo.Distance(pm, px, py, map, x, y)
end

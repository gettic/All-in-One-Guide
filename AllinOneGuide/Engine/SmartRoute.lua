-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Smart arrow (v0.2): leads the arrow through doors, cave mouths, ramps, gates and paths instead of a straight
-- line. The game has no pathfinding, so all routing comes from our own data: connector points ("nodes") joined
-- by walkable links, and "rooms" (polygons you can only leave through a connector). It only shows directions:
-- it never moves the player, and it never reads combat or unit data (tos check 2026-11-25). Inputs are the
-- player's own map position, IsIndoors() (a hint next to the polygons, never alone) and our static data.
--   ns.SmartRoute.Register(data)                 data = { area, connectors = {...}, rooms = {...} } (x / y in %)
--   ns.SmartRoute.Aim(target, map, x, y) -> point, info   (info nil = point straight at the target)
--   ns.SmartRoute.Plan(target, map, x, y, indoors, fromRoom) -> route list, why (fromRoom: a NearRoom snap)
--   ns.SmartRoute.RoomAt(map, x, y, indoors) -> room id | nil
--   ns.SmartRoute.NearRoom(map, x, y, yards, prefer) -> the nearest indoor room id within yards | nil
--   ns.SmartRoute.Hint(point) -> text, .RouteText() -> "Abbey door > Goal", .Straight(target), .Reset()
-- Setting smartArrow off (or the "point straight" choice for one target) = the old arrow exactly.
local _, ns = ...
local SR = {
    nodes = {}, rooms = {}, roomsByMap = {}, sources = {}, order = {}, dirty = false, problems = {},
    state = nil, straightFor = nil, stats = { plans = 0, polls = 0 },
    OFF_YARDS = 40,     -- off the planned leg by more than this ...
    OFF_POLLS = 2,      -- ... for this many polls in a row = re-plan
    OFF_EVERY = 5,      -- but at most once per 5 s while off-route
    PASS_SLACK = 2,     -- yards of slack for "walked past the point" (corner cut)
    ROOM_POLLS = 2,     -- a room change off the route must hold this many polls in a row before a re-plan ...
    ROOM_EVERY = 2,     -- ... and such re-plans come at most once per 2 s (doorway flicker)
    SNAP_YARDS = 12,    -- the game says indoors but no outline holds you: the nearest indoor room this close ...
    SNAP_FRESH = 4,     -- ... (only this close with no plan yet)
    SNAP_EXIT = 4,     -- ... unless you stand in its way out to the open (half the door pair + this many yards)
    HOLD_YARDS = 8,     -- a room the route already left doesn't pull you back while you're this close to the leg
    -- reach radius by kind (yards) when a connector has no r
    RADIUS = { door = 3, stairs = 3, cave = 5, ramp = 5, tram = 5, gate = 6, bridge = 6, path = 10 },
    -- walking cost factor by kind (either end of a link)
    FACTOR = { stairs = 1.2, ramp = 1.2 },
    KINDS = { "door", "cave", "ramp", "bridge", "gate", "tram", "path", "stairs" },
}
ns.SmartRoute = SR

local sqrt, huge = math.sqrt, math.huge

-- Items of a plain list or a frozen pack list (proxies: no # / ipairs).
local function Items(list)
    local out, i = {}, 1
    if type(list) ~= "table" then return out end
    while list[i] ~= nil do
        out[i] = list[i]
        i = i + 1
    end
    return out
end

local function Num(v) return type(v) == "number" and v == v end

-- ------------------------------------------------------------------ data
-- Data stays as given until the first plan (Build); a later Register marks it dirty again.
function SR.Register(data)
    if type(data) ~= "table" or type(data.area) ~= "string" then return false, "bad data" end
    if not SR.sources[data.area] then SR.order[#SR.order + 1] = data.area end
    SR.sources[data.area] = data
    SR.dirty = true
    return true
end

local function Problem(text)
    if #SR.problems < 50 then SR.problems[#SR.problems + 1] = text end
end

local function PolyArea(poly)
    local a = 0
    for i = 1, #poly do
        local p, q = poly[i], poly[i % #poly + 1]
        a = a + p[1] * q[2] - q[1] * p[2]
    end
    return math.abs(a) / 2
end

local function AddEdge(adj, from, to, cost)
    local list = adj[from]
    if not list then list = {} adj[from] = list end
    for _, e in ipairs(list) do
        if e.to == to then
            if cost then e.cost = cost end
            return
        end
    end
    list[#list + 1] = { to = to, cost = cost }
end

-- Turns the registered data into nodes (x / y 0-1), rooms per map and the link list (both ways unless oneWay).
function SR.Build()
    SR.nodes, SR.rooms, SR.roomsByMap, SR.adj, SR.problems = {}, {}, {}, {}, {}
    local byInside = {}
    for _, area in ipairs(SR.order) do
        local data = SR.sources[area]
        for _, c in ipairs(Items(data.connectors)) do
            if type(c) == "table" and type(c.id) == "string" and Num(c.map) and Num(c.x) and Num(c.y) then
                if SR.nodes[c.id] then Problem("duplicate connector " .. c.id) end
                local kind = SR.RADIUS[c.kind] and c.kind or "path"
                SR.nodes[c.id] = { id = c.id, map = c.map, x = c.x / 100, y = c.y / 100, kind = kind,
                    r = Num(c.r) and c.r or SR.RADIUS[kind], hint = type(c.hint) == "string" and c.hint or nil,
                    inside = type(c.inside) == "string" and c.inside or nil, src = c, area = area }
            else
                Problem("bad connector in " .. area)
            end
        end
        for _, r in ipairs(Items(data.rooms)) do
            local poly, ok = {}, type(r) == "table" and type(r.id) == "string" and Num(r.map)
            for _, p in ipairs(ok and Items(r.poly) or {}) do
                if type(p) == "table" and Num(p[1]) and Num(p[2]) then poly[#poly + 1] = { p[1] / 100, p[2] / 100 }
                else ok = false end
            end
            if ok and #poly >= 3 then
                local room = { id = r.id, map = r.map, poly = poly, indoor = r.indoor == true, chain = r.chain == true,
                    area = PolyArea(poly),
                    minx = huge, maxx = -huge, miny = huge, maxy = -huge }
                for _, p in ipairs(poly) do
                    room.minx, room.maxx = math.min(room.minx, p[1]), math.max(room.maxx, p[1])
                    room.miny, room.maxy = math.min(room.miny, p[2]), math.max(room.maxy, p[2])
                end
                SR.rooms[r.id] = room
                local list = SR.roomsByMap[r.map] or {}
                list[#list + 1] = room
                SR.roomsByMap[r.map] = list
            else
                Problem("bad room in " .. area)
            end
        end
    end
    for id, n in pairs(SR.nodes) do
        for _, l in ipairs(Items(n.src.link)) do
            local to, cost, oneWay = l, nil, n.src.oneWay == true
            if type(l) == "table" then to, cost, oneWay = l[1] or l.id, l.cost, oneWay or l.oneWay == true end
            if type(to) == "string" and SR.nodes[to] and to ~= id then
                cost = Num(cost) and cost > 0 and cost or nil
                AddEdge(SR.adj, id, to, cost)
                if not oneWay then AddEdge(SR.adj, to, id, cost) end
            else
                Problem("link " .. id .. " -> " .. tostring(to))
            end
        end
        if n.inside and not SR.rooms[n.inside] then Problem("room " .. n.inside .. " of " .. id) end
        local key = n.inside or ""
        byInside[key] = byInside[key] or {}
        byInside[key][#byInside[key] + 1] = n
    end
    -- nodes per room ("" = outdoors), sorted by id so plans don't depend on table order
    for _, list in pairs(byInside) do table.sort(list, function(a, b) return a.id < b.id end) end
    SR.byInside = byInside
    SR.dirty = false
    SR.state = nil
    return SR.problems
end

local function Ready()
    if SR.dirty or not SR.adj then SR.Build() end
    return next(SR.nodes) ~= nil
end

function SR.Count()
    Ready()
    local n, r = 0, 0
    for _ in pairs(SR.nodes) do n = n + 1 end
    for _ in pairs(SR.rooms) do r = r + 1 end
    return n, r
end

-- ------------------------------------------------------------------ geometry
-- A point's world position, cached on the point (nodes never move; the Geo cache is shared and small).
local function World(p)
    if p.c == nil then
        local c, wx, wy = ns.Geo.World(p.map, p.x, p.y)
        p.c, p.wx, p.wy = c or false, wx, wy
    end
    if not p.c then return nil end
    return p.c, p.wx, p.wy
end

local function Yards(a, b)
    local ca, ax, ay = World(a)
    local cb, bx, by = World(b)
    if not ca or ca ~= cb then return nil end
    local dx, dy = bx - ax, by - ay
    return sqrt(dx * dx + dy * dy)
end
SR.Yards = Yards

local function InPoly(poly, x, y)
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end
SR.InPoly = InPoly

-- The smallest room whose polygon holds the point. An indoor room needs indoors ~= false (nil = unknown, then
-- the polygon decides alone).
function SR.RoomAt(map, x, y, indoors)
    if not (Num(map) and Num(x) and Num(y)) then return nil end
    Ready()
    local best
    for _, r in ipairs(SR.roomsByMap[map] or {}) do
        if x >= r.minx and x <= r.maxx and y >= r.miny and y <= r.maxy and not (r.indoor and indoors == false)
            and InPoly(r.poly, x, y) and (not best or r.area < best.area) then
            best = r
        end
    end
    return best and best.id or nil
end

-- Yards from p (map x / y 0-1) to a room's outline, 0 inside; nil when it can't be measured.
local function RoomYards(r, map, x, y)
    if InPoly(r.poly, x, y) then return 0 end
    local c, px, py = ns.Geo.World(map, x, y)
    if not c then return nil end
    if not r.wpoly then
        r.wpoly = {}
        for i, q in ipairs(r.poly) do
            local cq, qx, qy = ns.Geo.World(r.map, q[1], q[2])
            r.wpoly[i] = cq and { cq, qx, qy } or false
        end
    end
    local best
    for i = 1, #r.wpoly do
        local a, b = r.wpoly[i], r.wpoly[i % #r.wpoly + 1]
        if a and b and a[1] == c and b[1] == c then
            local vx, vy = b[2] - a[2], b[3] - a[3]
            local len2 = vx * vx + vy * vy
            local u = len2 > 0 and math.max(0, math.min(1, ((px - a[2]) * vx + (py - a[3]) * vy) / len2)) or 0
            local dx, dy = px - (a[2] + u * vx), py - (a[3] + u * vy)
            local d = sqrt(dx * dx + dy * dy)
            if not best or d < best then best = d end
        end
    end
    return best
end

-- The game says indoors but no indoor outline holds the point (our outlines are rough, bug 2026-11-27 "it stops
-- working in the middle of the room"): the nearest indoor room on this map within `yards`; `prefer` (the room
-- you were in) wins when it is that close too. A room is skipped while you stand in one of its ways out to the
-- open (within half the pair's length + SNAP_EXIT yards of the middle between its inside point and the outside
-- point it links to): that's someone stepping out of its door while the indoor flag still lags.
local function NearExit(r, map, x, y)
    local p = { map = map, x = x, y = y }
    for _, n in ipairs(SR.byInside and SR.byInside[r.id] or {}) do
        for _, e in ipairs(SR.adj and SR.adj[n.id] or {}) do
            local o = SR.nodes[e.to]
            local orr = o and o.inside and SR.rooms[o.inside]
            if o and o.map == n.map and (not orr or not orr.indoor) then
                local len = Yards(n, o)
                local d = len and Yards(p, { map = n.map, x = (n.x + o.x) / 2, y = (n.y + o.y) / 2 })
                if d and d <= len / 2 + SR.SNAP_EXIT then return true end
            end
        end
    end
    return false
end

function SR.NearRoom(map, x, y, yards, prefer)
    if not (Num(map) and Num(x) and Num(y)) then return nil end
    Ready()
    local best, bestD
    for _, r in ipairs(SR.roomsByMap[map] or {}) do
        if r.indoor then
            local d = RoomYards(r, map, x, y)
            if d and d <= yards and (d == 0 or not NearExit(r, map, x, y)) then
                if r.id == prefer then return r.id end
                if not bestD or d < bestD then best, bestD = r.id, d end
            end
        end
    end
    return best
end

-- ------------------------------------------------------------------ planning
local function Point(n)
    return { id = n.id, map = n.map, x = n.x, y = n.y, r = n.r, kind = n.kind, hint = n.hint, room = n.inside,
        via = true, c = n.c, wx = n.wx, wy = n.wy }
end

local function GoalPoint(t, room)
    return { map = t.map, x = t.x, y = t.y, r = t.r, room = room, goal = true }
end

local function Linked(a, b)
    for _, e in ipairs(SR.adj and SR.adj[a] or {}) do
        if e.to == b then return true end
    end
    return false
end

-- A door (cave mouth, gate) is two linked points, one on each side of the wall, often 10-35 yards apart. Aiming
-- at the near one led to a spot in front of the door (and to its side when you came at an angle), and it only
-- counted within its 3-5 yd radius, so walking straight to the door kept the arrow pointing beside it. The arrow
-- now aims at the doorway itself: the middle between the two points (same map), with the near point's radius.
-- The node's own data is untouched (planning still uses it); only this route's aim point moves.
-- Stairs are not doorways: the bottom and the top of a flight (a landing, a turn) are each a point to walk to
-- (bug 2026-11-27, Deathknell crypt: "i want way points on the stairs").
local function Doorways(route)
    for k = 1, #route - 1 do
        local a, b = route[k], route[k + 1]
        if a.id and b.id and not a.door and a.kind ~= "stairs" and a.room ~= b.room and a.map == b.map
            and Linked(a.id, b.id) then
            a.x, a.y, a.door = (a.x + b.x) / 2, (a.y + b.y) / 2, true
            a.c, a.wx, a.wy = nil, nil, nil
        end
    end
    return route
end
SR.Doorways = Doorways

-- A step's own `via` list: connector ids or inline points { map, x, y (%), hint }.
local function ForcedRoute(t, goalRoom)
    local route = {}
    for _, v in ipairs(Items(t.via)) do
        if type(v) == "string" and SR.nodes[v] then
            route[#route + 1] = Point(SR.nodes[v])
        elseif type(v) == "table" and Num(v.map) and Num(v.x) and Num(v.y) then
            local kind = SR.RADIUS[v.kind] and v.kind or "path"
            route[#route + 1] = { map = v.map, x = v.x / 100, y = v.y / 100, r = Num(v.r) and v.r or SR.RADIUS[kind],
                kind = kind, hint = type(v.hint) == "string" and v.hint or nil, via = true }
        end
    end
    route[#route + 1] = GoalPoint(t, goalRoom)
    return Doorways(route)
end

-- Where the player joins the graph: every node of the player's room, each at its straight distance. A `chain`
-- room (a stairwell: its points are walked in order, a straight line to a later one would cut through a wall)
-- joins at the nearest leg between two of its own points instead: before the leg's first point only that point,
-- past its last only that one, else both, each at the distance along the leg (so the way on wins).
local function StartLinks(start, startRoom)
    local out = {}
    local list = SR.byInside[startRoom or ""] or {}
    local room = startRoom and SR.rooms[startRoom]
    if room and room.chain then
        local cs, sx, sy = World(start)
        local best
        for _, a in ipairs(list) do
            for _, e in ipairs(SR.adj[a.id] or {}) do
                local b = SR.nodes[e.to]
                local ca, ax, ay = World(a)
                local cb, bx, by = World(b)
                if b.inside == startRoom and cs and ca == cs and cb == cs then
                    local vx, vy = bx - ax, by - ay
                    local len = sqrt(vx * vx + vy * vy)
                    local u = len > 0 and ((sx - ax) * vx + (sy - ay) * vy) / (len * len) or 0
                    local cu = math.max(0, math.min(1, u))
                    local dx, dy = sx - (ax + cu * vx), sy - (ay + cu * vy)
                    local d = sqrt(dx * dx + dy * dy)
                    if not best or d < best.d then best = { d = d, u = u, a = a, b = b, len = len } end
                end
            end
        end
        if best then
            if best.u <= 0 then
                out[best.a.id] = Yards(start, best.a)
            elseif best.u >= 1 then
                out[best.b.id] = Yards(start, best.b)
            else
                out[best.a.id] = best.d + best.u * best.len
                out[best.b.id] = best.d + (1 - best.u) * best.len
            end
            return out
        end
    end
    for _, n in ipairs(list) do out[n.id] = Yards(start, n) end
    return out
end

-- Plain Dijkstra (linear-scan minimum; graphs are 20-300 nodes). Start = the player, joined to the player's room
-- ("" = outdoors) by StartLinks; goal linked from every node of the goal's room.
local function Dijkstra(start, goal, startRoom, goalRoom)
    local dist, prev, done = {}, {}, {}
    local open = {}
    for id, d in pairs(StartLinks(start, startRoom)) do
        dist[id], open[id] = d, true
    end
    local goalNodes = {}
    for _, n in ipairs(SR.byInside[goalRoom or ""] or {}) do goalNodes[n.id] = true end
    local bestGoal, bestLast = huge, nil
    while true do
        local cur, cd = nil, huge
        for id in pairs(open) do
            local d = dist[id]
            if d < cd or (d == cd and cur and id < cur) then cur, cd = id, d end
        end
        if not cur or cd >= bestGoal then break end
        open[cur], done[cur] = nil, true
        local node = SR.nodes[cur]
        if goalNodes[cur] then
            local g = Yards(node, goal)
            if g and cd + g < bestGoal then bestGoal, bestLast = cd + g, cur end
        end
        for _, e in ipairs(SR.adj[cur] or {}) do
            if not done[e.to] then
                local to = SR.nodes[e.to]
                local c = e.cost
                if not c then
                    c = Yards(node, to)
                    if c then c = c * (SR.FACTOR[node.kind] or SR.FACTOR[to.kind] or 1) end
                end
                if c and (dist[e.to] == nil or cd + c < dist[e.to]) then
                    dist[e.to], prev[e.to], open[e.to] = cd + c, cur, true
                end
            end
        end
    end
    if not bestLast then return nil end
    local ids, id = {}, bestLast
    while id do
        table.insert(ids, 1, id)
        id = prev[id]
    end
    return ids, bestGoal
end

-- The route from the player to the target: a list of points, the last one the goal. why = "straight" (same
-- room / no data / via = false), "via" (the step's own list), "graph", "nopath" (fell back to straight).
function SR.Plan(t, map, x, y, indoors, fromRoom)
    SR.stats.plans = SR.stats.plans + 1
    if not (type(t) == "table" and Num(t.map) and Num(t.x) and Num(t.y)) then return nil, "notarget" end
    local hasData = Ready()
    local goalRoom = type(t.room) == "string" and SR.rooms[t.room] and t.room or SR.RoomAt(t.map, t.x, t.y, nil)
    if t.via == false then return { GoalPoint(t, goalRoom) }, "straight" end
    if type(t.via) == "table" and t.via[1] ~= nil then return ForcedRoute(t, goalRoom), "via" end
    if not hasData then return { GoalPoint(t, goalRoom) }, "straight" end
    local startRoom = fromRoom or SR.RoomAt(map, x, y, indoors)
    if startRoom == goalRoom then return { GoalPoint(t, goalRoom) }, "straight" end
    local start = { map = map, x = x, y = y }
    local goal = GoalPoint(t, goalRoom)
    local ids = Dijkstra(start, goal, startRoom, goalRoom)
    if not ids then return { goal }, "nopath" end
    local route = {}
    for _, id in ipairs(ids) do route[#route + 1] = Point(SR.nodes[id]) end
    route[#route + 1] = goal
    return Doorways(route), "graph"
end

-- ------------------------------------------------------------------ following the route
function SR.On()
    local S = ns.Settings
    if not (S and S.Get) then return true end
    return S.Get("smartArrow") ~= false
end

local function Key(t) return ("%s:%s:%s"):format(tostring(t.map), tostring(t.x), tostring(t.y)) end

local function Indoors()
    local Co = ns.Compat
    if Co and Co.Indoors then return Co.Indoors() end
    return nil
end

local function Now()
    local Co = ns.Compat
    return (Co and Co.Now and Co.Now()) or 0
end

local function NewPlan(t, player, indoors, room, why, snapped)
    local route, how = SR.Plan(t, player.map, player.x, player.y, indoors, snapped and room or nil)
    SR.state = { target = t, key = Key(t), route = route or { GoalPoint(t, nil) }, i = 1, room = room,
        how = how, why = why, prev = player, off = 0, offAt = SR.state and SR.state.offAt or -huge, c = player.c,
        roomAt = why ~= "target" and SR.state and SR.state.roomAt or -huge, pendN = 0 }
    ns.Bus.Fire("SmartRouteChanged", why)
    return SR.state
end

-- Perpendicular distance from p to the leg a -> b (yards), nil when unknown.
local function OffLeg(p, a, b)
    local ca, ax, ay = World(a)
    local cb, bx, by = World(b)
    local cp, px, py = World(p)
    if not (ca and cb and cp) or ca ~= cb or cb ~= cp then return nil end
    local vx, vy = bx - ax, by - ay
    local len2 = vx * vx + vy * vy
    local u = len2 > 0 and ((px - ax) * vx + (py - ay) * vy) / len2 or 0
    u = math.max(0, math.min(1, u))
    local dx, dy = px - (ax + u * vx), py - (ay + u * vy)
    return sqrt(dx * dx + dy * dy)
end

-- Walked past via point v towards n without touching its radius (corner cut): on n's side of v and not
-- further from n than v is (+ slack). A step that crosses a room wall (v and n in different rooms: door,
-- cave mouth) only counts once the player is in n's room (`room` = the player's room, nil = outdoors), so
-- standing outside next to a cave never moves the arrow on to the point inside.
-- A doorway point (v.door) also counts as passed while the room outline doesn't say so yet (our outlines are
-- rough): stepping over its middle towards the far side, at most its radius + slack to the side.
local function Passed(p, v, n, room)
    local through = v.room ~= n.room and room ~= n.room
    if through and not v.door then return false end
    local cv, vx, vy = World(v)
    local cn, nx, ny = World(n)
    local cp, px, py = World(p)
    if not (cv and cn and cp) or cv ~= cn or cn ~= cp then return false end
    local ex, ey = nx - vx, ny - vy
    local dvn = sqrt(ex * ex + ey * ey)
    if dvn <= 0 then return true end
    local dot = (px - vx) * ex + (py - vy) * ey
    if through then
        local side = math.abs((px - vx) * ey - (py - vy) * ex) / dvn
        return dot > 0 and dot <= dvn * dvn and side <= (v.r or 3) + SR.PASS_SLACK
    end
    local dpn = sqrt((nx - px) ^ 2 + (ny - py) ^ 2)
    return dot > 0 and dpn < dvn + SR.PASS_SLACK
end
SR.Passed = Passed

-- Route length from the player along the rest of the route, nil when a leg can't be measured.
local function Left(st, player)
    local route, total = st.route, Yards(player, st.route[st.i])
    if not total then return nil end
    for k = st.i, #route - 1 do
        local d = Yards(route[k], route[k + 1])
        if not d then return nil end
        total = total + d
    end
    return total
end

-- Per position poll (the arrow's 0.25 s read): the point to aim at and what it is. info = nil means
-- "point straight at the target" (setting off, straight for this target, no route needed, no data).
--   info = { via = true, point, hint, kind, left (via points left), goalYards (along the route), route }
function SR.Aim(t, map, x, y)
    if not (t and SR.On()) or SR.straightFor == t then return t, nil end
    if not (Num(map) and Num(x) and Num(y)) then return t, nil end
    SR.stats.polls = SR.stats.polls + 1
    local player = { map = map, x = x, y = y }
    if not World(player) then return t, nil end
    local indoors = Indoors()
    local room = SR.RoomAt(map, x, y, indoors)
    local st = SR.state
    -- indoors, but just outside every outline (rough outlines, a wide hall): the nearest indoor room, so the
    -- arrow keeps leading to that room's next point instead of falling back to straight through the wall
    -- Only from inside a room (the last poll was in one: up to SNAP_YARDS) or with no plan yet (a /reload, a new
    -- step: up to SNAP_FRESH); someone who was outdoors stays outdoors (a lagging flag near a cave isn't a way in).
    -- An outdoor room (a walled city, the hill over the Deathknell crypt) counts as "no outline" here: indoors
    -- under it you are in a building or crypt below, not on its open ground (2026-11-27, the crypt hill room).
    local snapped = false
    local here = room and SR.rooms[room]
    if (room == nil or not (here and here.indoor)) and indoors == true then
        local fresh = not st or st.target ~= t
        local was = not fresh and st.room and SR.rooms[st.room]
        if fresh or (was and was.indoor) then
            local near = SR.NearRoom(map, x, y, fresh and SR.SNAP_FRESH or SR.SNAP_YARDS, not fresh and st.room or nil)
            if near then room, snapped = near, true end
        end
    end
    -- hysteresis (beta.5 "arrow jumps while I stand still"): IsIndoors flickers in doorways and cave mouths. The
    -- flag alone never takes you out of the room you are in while you still stand inside its outline: only
    -- leaving the outline does (entering an indoor room still needs the flag, as before).
    if st and st.room and room ~= st.room and indoors == false and SR.RoomAt(map, x, y, nil) == st.room then
        room = st.room
    end
    local follow = true
    if not st or st.target ~= t or st.key ~= Key(t) then
        st = NewPlan(t, player, indoors, room, "target", snapped)
        follow = false
    elseif player.c ~= st.c then
        st = NewPlan(t, player, indoors, room, "room", snapped)
        follow = false
    elseif room ~= st.room then
        -- A room the route leads into (a point ahead is in it) re-plans at once. Any other room change
        -- (stepping back over a doorway) must hold for ROOM_POLLS polls in a row, and such re-plans come at
        -- most once per ROOM_EVERY seconds: walking along a room edge flickered the arrow.
        local expected, behind = false, false
        for k = st.i, #st.route do
            if st.route[k].room == room then expected = true break end
        end
        for k = 1, st.i - 1 do
            if room ~= nil and st.route[k].room == room then behind = true break end
        end
        -- A room the route already took you out of, while you still walk the current leg (a way out that runs
        -- over a lower floor: the crypt's last stairs above its hall), doesn't send you back down.
        local hold = false
        if behind and not expected and st.i <= #st.route then
            local off = OffLeg(player, st.prev, st.route[st.i])
            hold = off ~= nil and off <= SR.HOLD_YARDS
        end
        if st.pendRoom == room then st.pendN = st.pendN + 1 else st.pendRoom, st.pendN = room, 1 end
        local now = Now()
        if hold then
            room = st.room
            st.pendRoom, st.pendN = nil, 0
        elseif expected then
            st = NewPlan(t, player, indoors, room, "room", snapped)
            follow = false
        elseif st.pendN >= SR.ROOM_POLLS and now - st.roomAt >= SR.ROOM_EVERY then
            st = NewPlan(t, player, indoors, room, "room", snapped)
            st.roomAt = now
            follow = false
        end
    else
        st.pendRoom, st.pendN = nil, 0
    end
    if follow then
        local route = st.route
        while st.i < #route do
            local p, n = route[st.i], route[st.i + 1]
            local d = Yards(player, p)
            if (d and d <= (p.r or 3)) or Passed(player, p, n, room) then
                st.prev, st.i, st.off = p, st.i + 1, 0
            else
                break
            end
        end
        if st.i < #route then
            local off = OffLeg(player, st.prev, route[st.i])
            if off and off > SR.OFF_YARDS then
                st.off = st.off + 1
                local now = Now()
                if st.off >= SR.OFF_POLLS and now - st.offAt >= SR.OFF_EVERY then
                    st = NewPlan(t, player, indoors, room, "off", snapped)
                    st.offAt = now
                end
            else
                st.off = 0
            end
        end
    end
    local p = st.route[st.i]
    if not p or p.goal then return t, nil end
    return p, { via = true, point = p, hint = SR.Hint(p), kind = p.kind, left = #st.route - st.i,
        goalYards = Left(st, player), route = st.route, index = st.i }
end

-- "Point straight at the goal" for this one target (arrow menu); a new target ends it.
function SR.Straight(t)
    SR.straightFor = t
    ns.Bus.Fire("SmartRouteChanged", "straight")
end

function SR.Reset()
    SR.state = nil
end

-- ------------------------------------------------------------------ texts
function SR.Hint(p)
    local L = ns.L
    if type(p) ~= "table" then return nil end
    local en = ns.Locale and ns.Locale.en or {}
    if p.hint and en[p.hint] ~= nil then return L[p.hint] end
    local key = "VIA_KIND_" .. (p.kind or "path"):upper()
    if en[key] ~= nil then return L[key] end
    return L.VIA_KIND_PATH
end

-- "Abbey door > Yard > Goal" for the arrow's tooltip (from the current point on).
function SR.RouteText()
    local st = SR.state
    if not st or not st.route then return nil end
    local parts = {}
    for k = st.i, #st.route do
        local p = st.route[k]
        parts[#parts + 1] = p.goal and ns.L.VIA_GOAL or SR.Hint(p)
    end
    if #parts < 2 then return nil end
    return table.concat(parts, " > ")
end

if ns.Bus and ns.Bus.On then
    ns.Bus.On("SettingsChanged", SR, function(_, key) if key == "smartArrow" then SR.Reset() end end, "ui", 70)
end

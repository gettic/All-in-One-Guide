-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Hunt path (v0.3, plans\hunt-path\plan.md): on a kill / collect step whose pack data has a `path` (a loop of
-- points round the area where its mobs usually spawn), the arrow leads round that loop once you are there, so you
-- walk past them instead of standing in the middle. Display only (tos, plans\hunt-path\tos.md): our own static
-- pack data and the player's own position; never a live mob position, nameplate, target, mouseover, GUID or the
-- combat log; nothing moves or targets for you. In combat it only holds its point (no "next mob" hint) and
-- picks the nearest point ahead again after the fight (the public regen events, through Data\GameState.lua).
--   ns.Hunt.Aim(t, map, x, y, source) -> point, info | nil   (nil = not hunting: the smart arrow / goal as before)
--     info = { via = true, hunt = true, point, hint, color = "arrowHunt", index, n, route }
--   ns.Hunt.Ahead(t) -> the loop's points from the current one round to it again (for the path line) | nil
--   ns.Hunt.Active(t), .Centre(t) (this target: point at the area's centre), .Reset(), .On(), .state, .stats
-- Setting huntPath (default on). Order in the arrow's 0.25 s poll: corpse / way / show targets never hunt (only
-- source "step"), then Hunt.Aim, then SmartRoute.Aim (which also leads you to the area from afar).
local _, ns = ...
local H = {
    RADIUS = 12,       -- yards that count as "reached" (step pathR overrides)
    ENTER = 10,        -- inside the step's r, or within RADIUS + ENTER of a loop point = hunting starts
    LEAVE = 60,        -- more than this from every loop point ...
    LEAVE_POLLS = 2,   -- ... for this many polls = back to the smart arrow
    OFF = 40,          -- more than this off the current leg ...
    OFF_POLLS = 3,     -- ... for this many polls = pick the nearest point ahead again
    AHEAD = 3,         -- a later point within reach (a short cut through the camp) is jumped to
    state = nil, centreFor = nil, inCombat = false,
    stats = { polls = 0, loads = 0, reached = 0, picks = 0 },
}
ns.Hunt = H

local sqrt = math.sqrt

local function Num(v) return type(v) == "number" and v == v end

function H.On()
    local S = ns.Settings
    if S and S.Get and S.Get("huntPath") == false then return false end
    return ns.Feature.IsOn("huntpath")
end

-- ------------------------------------------------------------------ geometry (world positions cached on our points)
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
    return sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
end
H.Yards = Yards

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
    return sqrt((px - ax - u * vx) ^ 2 + (py - ay - u * vy) ^ 2)
end

-- Walked past v towards n without touching its radius (the smart arrow's corner-cut test, one room).
local function Passed(p, v, n)
    local cv, vx, vy = World(v)
    local cn, nx, ny = World(n)
    local cp, px, py = World(p)
    if not (cv and cn and cp) or cv ~= cn or cn ~= cp then return false end
    local ex, ey = nx - vx, ny - vy
    local dvn = sqrt(ex * ex + ey * ey)
    if dvn <= 0 then return true end
    local dot = (px - vx) * ex + (py - vy) * ey
    local dpn = sqrt((nx - px) ^ 2 + (ny - py) ^ 2)
    local slack = ns.SmartRoute and ns.SmartRoute.PASS_SLACK or 2
    return dot > 0 and dpn < dvn + slack
end

-- ------------------------------------------------------------------ the loop
local function Key(t)
    return ("%s:%s:%s:%s"):format(tostring(t.id), tostring(t.map), tostring(t.x), tostring(t.y))
end

-- The step's loop as our own point tables (pack lists are frozen proxies: no # / ipairs), or nil.
local function Load(t)
    local path = t.path
    if type(path) ~= "table" or not Num(t.map) then return nil end
    local pts, i = {}, 1
    while path[i] ~= nil do
        local p = path[i]
        if type(p) ~= "table" or not (Num(p.x) and Num(p.y)) then return nil end
        pts[i] = { map = t.map, x = p.x, y = p.y, hunt = i }
        i = i + 1
    end
    if #pts < 3 then return nil end
    H.stats.loads = H.stats.loads + 1
    local r = Num(t.pathR) and t.pathR or H.RADIUS
    for _, p in ipairs(pts) do p.r = r end
    return { key = Key(t), target = t, pts = pts, n = #pts, open = t.pathOpen == true, r = r, active = false,
        i = 1, dir = 1, out = 0, off = 0 }
end

-- The point after i (open paths turn round at the ends).
local function NextOf(st, i)
    if st.open then
        local j = i + st.dir
        if j < 1 or j > st.n then return i - st.dir end
        return j
    end
    return (i - 1 + st.dir) % st.n + 1
end

local function Step(st)
    if st.open and (st.i + st.dir < 1 or st.i + st.dir > st.n) then st.dir = -st.dir end
    st.prevPoint = st.pts[st.i]
    st.i = NextOf(st, st.i)
    st.off = 0
end

-- Nearest point; the direction that goes on the way you walk (from your last position), else the stored order;
-- a nearest point you have already walked past is skipped.
local function Pick(st, player)
    H.stats.picks = H.stats.picks + 1
    local best, bd = 1, math.huge
    for k, p in ipairs(st.pts) do
        local d = Yards(player, p)
        if d and d < bd then best, bd = k, d end
    end
    st.i, st.off = best, 0
    local prev = st.prevPos
    local cp, px, py = World(player)
    local cq, qx, qy
    if prev then cq, qx, qy = World(prev) end
    st.dir = 1
    if cp and cq and cp == cq and (px ~= qx or py ~= qy) then
        local mx, my = px - qx, py - qy
        local function Ahead(j)
            local c, x, y = World(st.pts[j])
            if not c then return -math.huge end
            return (x - px) * mx + (y - py) * my
        end
        local fwd = st.open and math.min(best + 1, st.n) or best % st.n + 1
        local back = st.open and math.max(best - 1, 1) or (best - 2) % st.n + 1
        if Ahead(back) > Ahead(fwd) then st.dir = -1 end
    end
    st.prevPoint = nil
    if Passed(player, st.pts[st.i], st.pts[NextOf(st, st.i)]) then Step(st) end
end

local function SetActive(st, on)
    if st.active == on then return end
    st.active = on
    local MV = ns.ModelView
    if MV and type(MV.SetTarget) == "function" then
        local t = st.target
        ns.Errors.Call("model", MV.SetTarget, on and (t.targetNpc or t.npc) or nil, "hunt")
    end
    ns.Bus.Fire("HuntChanged", on and "start" or "stop")
end

function H.Reset()
    local st = H.state
    H.state = nil
    if st then SetActive(st, false) end
end

-- "Point at the area centre" for this one target (arrow menu); a new target ends it.
function H.Centre(t)
    H.centreFor = t
    H.Reset()
    ns.Bus.Fire("HuntChanged", "centre")
end

function H.Active(t)
    local st = H.state
    return st ~= nil and st.active and (t == nil or st.target == t)
end

-- ------------------------------------------------------------------ the poll
local function Hint(st)
    local L = ns.L
    if H.inCombat then return L.HUNT_COMBAT end
    return ns.U.Fill(L.HUNT_HINT, { i = st.i, n = st.n })
end

local function Info(st)
    local p = st.pts[st.i]
    return p, { via = true, hunt = true, point = p, hint = Hint(st), color = "arrowHunt", index = st.i, n = st.n,
        route = st.pts }
end

function H.Aim(t, map, x, y, source)
    if not t or (source ~= nil and source ~= "step") or not H.On() or H.centreFor == t
        or type(t.path) ~= "table" then
        if H.state then H.Reset() end
        return nil
    end
    if not (Num(map) and Num(x) and Num(y)) then return nil end
    H.stats.polls = H.stats.polls + 1
    local st, key = H.state, Key(t)
    if not st or st.key ~= key then
        if H.badFor == t then return nil end   -- a loop that doesn't read: not tried again every poll
        H.Reset()
        st = Load(t)
        H.state = st
        if not st then H.badFor = t return nil end
    end
    st.target = t   -- the same step read again from the pack (a new frozen copy) keeps its place in the loop
    local player = { map = map, x = x, y = y }
    if not World(player) then return nil end
    local near = math.huge
    for _, p in ipairs(st.pts) do
        local d = Yards(player, p)
        if d and d < near then near = d end
    end
    if near == math.huge then   -- another continent / unknown map: not here
        SetActive(st, false)
        st.prevPos = player
        return nil
    end
    if not st.active then
        if not st.spot and Num(t.x) and Num(t.y) then st.spot = { map = t.map, x = t.x, y = t.y } end
        local spot = st.spot and Yards(player, st.spot)
        local r = Num(t.r) and t.r or ns.Format.DEFAULT_RADIUS
        if (spot and spot <= r) or near <= st.r + H.ENTER then
            Pick(st, player)
            st.out = 0
            SetActive(st, true)
        else
            st.prevPos = player
            return nil
        end
    elseif near > H.LEAVE then
        st.out = st.out + 1
        if st.out >= H.LEAVE_POLLS then
            SetActive(st, false)
            st.prevPos = player
            return nil
        end
    else
        st.out = 0
    end
    if H.inCombat then
        st.repick = true   -- holds its point; after the fight the nearest point ahead again
    elseif st.repick then
        st.repick = nil
        Pick(st, player)
    else
        -- a later point within reach (a short cut through the camp): jump there
        local j = st.i
        for _ = 1, H.AHEAD do
            j = NextOf(st, j)
            local d = Yards(player, st.pts[j])
            if d and d <= st.r then
                while st.i ~= j do Step(st) end
                break
            end
        end
        -- reached (radius) or walked past (corner cut): the next point
        local cur = st.pts[st.i]
        local d = Yards(player, cur)
        if (d and d <= st.r) or Passed(player, cur, st.pts[NextOf(st, st.i)]) then
            Step(st)
            H.stats.reached = H.stats.reached + 1
        end
        -- far off the leg (chased a mob): nearest point ahead again
        local from = st.prevPoint
        local off = from and OffLeg(player, from, st.pts[st.i])
        if off and off > H.OFF then
            st.off = st.off + 1
            if st.off >= H.OFF_POLLS then Pick(st, player) end
        else
            st.off = 0
        end
    end
    st.prevPos = player
    return Info(st)
end

-- The loop from the current point round to it again (closed) / to the end and back (open), for the path line.
function H.Ahead(t)
    local st = H.state
    if not (st and st.active and st.target == t) then return nil end
    local out, i = { st.pts[st.i] }, st.i
    if st.open then
        -- on to the end, then back to the other end
        local dir = st.dir
        for _ = 1, 2 do
            while i + dir >= 1 and i + dir <= st.n do
                i = i + dir
                out[#out + 1] = st.pts[i]
            end
            dir = -dir
        end
        return out
    end
    out[1] = nil
    for _ = 1, st.n do
        out[#out + 1] = st.pts[i]
        i = (i - 1 + st.dir) % st.n + 1
    end
    out[#out + 1] = st.pts[st.i]   -- back to the start: the loop closes
    return out
end

-- ------------------------------------------------------------------ wiring
ns.Bus.On("CombatStarted", H, function() H.inCombat = true end, "huntpath")
ns.Bus.On("CombatEnded", H, function() H.inCombat = false end, "huntpath")
-- The arrow's target changed (another step, a step without a spot, the window closed, a corpse / way target): a
-- hunt for any other target ends at once, so the ModelView's hunt mob and Active() never outlive their step
-- (beta.5: a step without coordinates leaves the arrow without a target and without polls).
function H.Check()
    local st, A = H.state, ns.Arrow
    if st and not (A and A.target == st.target and (A.source == nil or A.source == "step")) then H.Reset() end
end
ns.Bus.On("StepChanged", H, function()
    H.centreFor = nil
    H.Check()
end, "huntpath", 99)
ns.Bus.On("WaypointChanged", H, function() H.Check() end, "huntpath", 99)
ns.Bus.On("SettingsChanged", H, function(_, key) if key == "huntPath" then H.Reset() end end, "huntpath", 70)
ns.Bus.On("Login", H, function() H.inCombat = ns.Compat.InCombat() == true end, "huntpath", 60)

-- In-game self-test: the loop state is sane (never more points than the step's loop, an index inside it).
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "hunt", fn = function(h)
    h.Count()
    local st = H.state
    if st and (st.i < 1 or st.i > st.n or #st.pts ~= st.n) then h.Problem("hunt: loop index outside the loop") end
    if st and st.active and not (ns.Arrow and ns.Arrow.target == st.target) then
        h.Problem("hunt: hunting for a target the arrow doesn't have")
    end
    h.Info(("hunt: %s, %d polls, %d points reached"):format(st and (st.active and ("point " .. st.i .. "/" .. st.n)
        or "waiting") or "off", H.stats.polls, H.stats.reached))
end }

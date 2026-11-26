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
    AHEAD = 3,         -- a later point of this lap within reach (a short cut through the camp) is jumped to
    STILL = 1,         -- yards: closer than this to where you last stood = standing still (no advance at all)
    MOVE = 3,          -- yards you must have moved since the last advance before the next one (standing still = no change)
    PASS_SIDE = 2,     -- "walked past": at most this x r to the side of the incoming leg ...
    PASS_FAR = 3,      -- ... and this x r from the point
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

-- v0.3 spawn spots: "auto" (the step's loop where it has one, the nearest spawn spot elsewhere), "spots" or "loops".
function H.Mode()
    local S = ns.Settings
    local m = S and S.Get and S.Get("huntMode") or "auto"
    if not ns.Spots or not ns.Feature.IsOn("spots") then return "loops" end
    return m
end

-- Which way this step hunts: "spots", "loop" or nil. "auto" (Mixed, the default) keeps the step's loop, made by hand
-- or generated, and uses spawn spots only where the step has no loop (beta.7 bug: generated loops gave way to spots,
-- so every shipped loop step showed "Nearest spawn spot" instead of "spot i of n"); "spots" always prefers spots.
function H.Kind(t)
    local mode = H.Mode()
    local loop = type(t.path) == "table"
    if mode ~= "loops" and not (mode == "auto" and loop) and ns.Spots.Has(t) then
        return "spots"
    end
    return loop and "loop" or nil
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

-- Walked on past `cur` along the leg you came in on (prev -> cur) without touching its radius: beyond cur in
-- that leg's direction, at most PASS_SIDE x r to the side of the leg's line and PASS_FAR x r from cur. Only the
-- incoming leg counts (beta.6: a test against the outgoing leg fired near hairpins, where the next leg turns back).
local function PassedAlong(p, prev, cur, r)
    if not prev then return false end
    local ca, ax, ay = World(prev)
    local cc, cx, cy = World(cur)
    local cp, px, py = World(p)
    if not (ca and cc and cp) or ca ~= cc or cc ~= cp then return false end
    local ex, ey = cx - ax, cy - ay
    local len = sqrt(ex * ex + ey * ey)
    if len <= 0 then return false end
    ex, ey = ex / len, ey / len
    local along = (px - cx) * ex + (py - cy) * ey      -- > 0: beyond cur
    local side = math.abs((px - cx) * ey - (py - cy) * ex)
    local far = sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
    return along > 0 and side <= r * H.PASS_SIDE and far <= r * H.PASS_FAR
end
H.PassedAlong = PassedAlong

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
        i = 1, dir = 1, out = 0, off = 0, done = {}, ndone = 0 }
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

-- A new lap: every point counts as "not done" again (closed loop: all points done; open path: it turned round).
local function NewLap(st)
    st.done, st.ndone = {}, 0
end

-- On to the next point; the one left behind is done for this lap.
local function Step(st)
    if not st.done[st.i] then st.done[st.i], st.ndone = true, st.ndone + 1 end
    if st.open and (st.i + st.dir < 1 or st.i + st.dir > st.n) then
        st.dir = -st.dir
        NewLap(st)
    end
    st.prevPoint = st.pts[st.i]
    st.i = NextOf(st, st.i)
    st.off = 0
    if not st.open and st.ndone >= st.n then NewLap(st) end
end

-- One advance (reached, walked past or a short cut), remembered with where you stood: the next one needs MOVE yd
-- of real movement first, so standing still never moves the arrow on.
local function Advance(st, player)
    Step(st)
    st.advPos = player
    H.stats.reached = H.stats.reached + 1
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
    -- a nearest point you have already walked past (along the leg into it): the next one
    local before = st.pts[st.open and math.max(1, math.min(st.n, best - st.dir)) or (best - 1 - st.dir) % st.n + 1]
    st.prevPoint = before ~= st.pts[best] and before or nil
    NewLap(st)
    if PassedAlong(player, st.prevPoint, st.pts[st.i], st.r) then Advance(st, player) end
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
    if ns.Spots then ns.Spots.Reset() end
end

-- "Point at the area centre" for this one target (arrow menu); a new target ends it.
function H.Centre(t)
    H.centreFor = t
    H.Reset()
    ns.Bus.Fire("HuntChanged", "centre")
end

function H.Active(t)
    local st = H.state
    if ns.Spots and ns.Spots.Active(t) then return true end
    return st ~= nil and st.active and (t == nil or st.target == t)
end

-- What the path line is made of now (a change re-lays its dots): the loop and its point, or the spot list and spot.
function H.RouteKey()
    local sp = ns.Spots and ns.Spots.state
    if sp and sp.active then return sp.spots, sp.cur end
    local st = H.state
    if st then return st.pts, st.i end
    return nil, 0
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
    local kind = t and (source == nil or source == "step") and H.On() and H.centreFor ~= t and H.Kind(t) or nil
    if kind == "spots" then
        -- v0.3: the nearest spawn spot (Engine\Spots.lua) instead of a loop
        if H.state then
            local st = H.state
            H.state = nil
            SetActive(st, false)
        end
        return ns.Spots.Aim(t, map, x, y)
    end
    if kind ~= "loop" then
        if H.state or (ns.Spots and ns.Spots.state) then H.Reset() end
        return nil
    end
    if ns.Spots and ns.Spots.state then ns.Spots.Reset() end
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
    -- after a fight: the nearest point ahead again, but only when the fight took you off the way (more than OFF yd
    -- from the current leg); otherwise the point stays (beta.5: every fight's end made a still arrow jump back)
    if not H.inCombat and st.repick then
        st.repick = nil
        local cur = st.pts[st.i]
        local off = st.prevPoint and OffLeg(player, st.prevPoint, cur) or Yards(player, cur)
        if off and off > H.OFF then Pick(st, player) end
    end
    if H.inCombat then
        st.repick = true   -- holds its point
    else
        -- at most one advance per poll, and only after real movement since the last one (beta.6: near a hairpin
        -- the old tests kept moving the point on while the player stood still)
        local moved = true
        if st.advPos then
            local m = Yards(player, st.advPos)
            moved = m == nil or m >= H.MOVE
        end
        -- and you are moving now: more than STILL yd from where you last stood (the anchor follows you only once
        -- you are that far from it), so tiny position jitter at a radius edge can't tip it over either
        local anchor = st.anchor and Yards(player, st.anchor)
        if anchor == nil or anchor > H.STILL then
            st.anchor = player
        else
            moved = false
        end
        if moved then
            local cur = st.pts[st.i]
            local d = Yards(player, cur)
            if (d and d <= st.r) or PassedAlong(player, st.prevPoint, cur, st.r) then
                -- reached, or walked on past it along the leg you came in on
                Advance(st, player)
            else
                -- a short cut: a later point of this lap (not done yet, never wrapping past the lap's end and
                -- never turning round on an open path), at most AHEAD points on, within reach: on past it
                local j, steps = st.i, 0
                for _ = 1, H.AHEAD do
                    if st.open and (j + st.dir < 1 or j + st.dir > st.n) then break end
                    j = NextOf(st, j)
                    if j == st.i or st.done[j] then break end
                    steps = steps + 1
                    local dj = Yards(player, st.pts[j])
                    if dj and dj <= st.r then
                        for _ = 1, steps do Step(st) end
                        Advance(st, player)
                        break
                    end
                end
            end
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
    if ns.Spots and ns.Spots.Active(t) then return ns.Spots.Ahead(t) end
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
    if ns.Spots then ns.Spots.Check() end
    local st, A = H.state, ns.Arrow
    if not st then return end
    -- the same step read again from the pack (a new frozen copy, same key) keeps its place in the loop
    local same = A and A.target ~= nil and (A.target == st.target or Key(A.target) == st.key)
    if st and not (same and (A.source == nil or A.source == "step")) then H.Reset() end
end
ns.Bus.On("StepChanged", H, function()
    H.centreFor = nil
    H.Check()
end, "huntpath", 99)
ns.Bus.On("WaypointChanged", H, function() H.Check() end, "huntpath", 99)
ns.Bus.On("SettingsChanged", H, function(_, key)
    if key == "huntPath" or key == "huntMode" then H.Reset() end
end, "huntpath", 70)
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

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Spawn spot arrow (v0.3, plans\spawn-arrow\plan.md, tos plans\spawn-arrow\tos.md): on a kill / collect step whose
-- mob has spawn spots (Routes\Spots.lua, made by tools\import\spots.lua from CMaNGOS spawn facts), the arrow points
-- at the nearest spot you haven't cleared. A spot is cleared when you have been within its radius and walked away;
-- it stays grey for its respawn time (an estimate from the data), then comes back.
-- Display only, like the hunt loops (plans\_old\hunt-path\tos.md): static pack data + the player's own position.
-- Never a live mob position, unit, nameplate, target, GUID or the combat log; nothing moves or targets for you.
-- In combat the target is held and no new hint shows (no "next spot" in combat); clearing is noted quietly.
-- Steady (the stand-still lessons): at most one decision per poll, a switch to a nearer spot only after real
-- movement (MOVE yd since the last pick, STILL yd anchor) and only when it is clearly nearer (SWITCH_YD / SWITCH_PCT)
-- for SWITCH_POLLS polls in a row.
--   ns.Spots.Register(packId, { ["npc@map"] = "x,y,r;..." })   .For(t) -> spots | nil   .Has(t)
--   ns.Spots.Aim(t, map, x, y) -> point, info | nil   (called by ns.Hunt.Aim)   .Active(t)   .Ahead(t)   .Reset()
--   .List() -> spots of the arrow's step target, target index, open(i) (for UI\SpotDots.lua)   .Cleared(spot)
--   saved: char module "spots" { cleared = { [spot id] = until (server time) } }
local _, ns = ...
local Co = ns.Compat
local SP = {
    CLEAR_R = 25,        -- yards: inside = visited
    LEAVE = 15,          -- ... cleared once you are this much farther away again
    ACTIVE = 60,         -- within this of a spot (or inside the step's radius) = the spot arrow starts
    OUT = 120,           -- farther than this from every spot ...
    OUT_POLLS = 2,       -- ... for this many polls = back to the smart arrow
    MOVE = 3, STILL = 1, -- yards of real movement before another switch (standing still never switches)
    SWITCH_YD = 25, SWITCH_PCT = 0.3, SWITCH_POLLS = 2,
    MIN_RESP = 120, MAX_RESP = 900, MAX_SAVE = 200,
    data = {}, cache = {}, cleared = {}, state = nil, inCombat = false,
    stats = { polls = 0, picks = 0, switches = 0, cleared = 0 },
}
ns.Spots = SP

local sqrt, floor = math.sqrt, math.floor
local function Num(v) return type(v) == "number" and v == v end

-- ------------------------------------------------------------------ data
function SP.Register(packId, targets)
    if type(packId) ~= "string" or type(targets) ~= "table" then return false end
    for k, v in pairs(targets) do
        if type(k) == "string" and type(v) == "string" and k:match("^%d+@%d+$") then SP.data[k] = v end
    end
    SP.cache = {}
    return true
end

-- The step's mobs, in order, no repeats: targetNpc, npc, else (v0.2.10) every mob of its quest from
-- Data\QuestMobs.lua (a kill step that names no mob, like the Tirisfal zombies dk-obj-364), or nil.
function SP.Ids(t)
    if not t or t.type ~= "objective" or not Num(t.map) then return nil end
    local ids, seen = {}, {}
    local function Add(id)
        if Num(id) and id > 0 and not seen[id] then seen[id] = true ids[#ids + 1] = id end
    end
    Add(t.targetNpc)
    Add(t.npc)
    if #ids == 0 and Num(t.quest) and type(ns.QuestMobs) == "table" then
        local mobs = ns.QuestMobs[t.quest]
        if type(mobs) == "table" then for _, id in ipairs(mobs) do Add(id) end end
    end
    return #ids > 0 and ids or nil
end

-- The step's spots (our own tables, cached per mob list + map), or nil.
function SP.For(t)
    local ids = SP.Ids(t)
    if not ids then return nil end
    local key = table.concat(ids, "|") .. "@" .. t.map
    local hit = SP.cache[key]
    if hit ~= nil then return hit or nil end
    local list = {}
    for _, id in ipairs(ids) do
        local s = SP.data[id .. "@" .. t.map]
        if s then
            local i = 0
            for x, y, r in s:gmatch("(%d+),(%d+),(%d+)") do
                i = i + 1
                local resp = math.max(SP.MIN_RESP, math.min(SP.MAX_RESP, tonumber(r) * 10))
                list[#list + 1] = { map = t.map, x = tonumber(x) / 1000, y = tonumber(y) / 1000, resp = resp,
                    id = id .. "@" .. t.map .. "#" .. i, r = SP.CLEAR_R, spot = #list + 1 }
            end
        end
    end
    SP.cache[key] = #list > 0 and list or false
    return #list > 0 and list or nil
end

function SP.Has(t) return SP.For(t) ~= nil end

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
SP.Yards = Yards

-- ------------------------------------------------------------------ cleared marks
local function Now() return Co.Now() end

function SP.Cleared(spot)
    local u = SP.cleared[spot.id]
    return u ~= nil and u > Now()
end

-- seconds until the spot is open again (0 = open)
function SP.Left(spot)
    local u = SP.cleared[spot.id]
    if not u then return 0 end
    return math.max(0, u - Now())
end

local function Clear(spot)
    SP.cleared[spot.id] = Now() + spot.resp
    SP.stats.cleared = SP.stats.cleared + 1
    SP.dirty = true
end

local function Saved(create)
    local root = ns.DB.char
    if not root or type(root.modules) ~= "table" or ns.DB.readOnly.char or ns.safeMode then return nil end
    local m = root.modules.spots
    if type(m) ~= "table" then
        if not create then return nil end
        m = ns.DB.Module("spots", "char", 1)
    end
    return m
end

-- Logout: marks still running, as server time (a /reload keeps them); at most MAX_SAVE.
function SP.Save()
    local st = Co.ServerTime()
    local now = Now()
    local list = {}
    for id, u in pairs(SP.cleared) do
        if type(id) == "string" and Num(u) and u > now then list[#list + 1] = { id = id, left = u - now } end
    end
    local m = Saved(#list > 0)
    if not m then return end
    m.cleared = nil
    if not st or #list == 0 then return end
    table.sort(list, function(a, b) if a.left ~= b.left then return a.left > b.left end return a.id < b.id end)
    m.cleared = {}
    for k = 1, math.min(#list, SP.MAX_SAVE) do m.cleared[list[k].id] = floor(st + list[k].left + 0.5) end
end

function SP.Load()
    local m = Saved(false)
    local st = Co.ServerTime()
    if not m or type(m.cleared) ~= "table" or not st then return end
    local now = Now()
    for id, u in pairs(m.cleared) do
        if type(id) == "string" and Num(u) and u > st and u - st <= SP.MAX_RESP then SP.cleared[id] = now + (u - st) end
    end
end

-- ------------------------------------------------------------------ the poll
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

local function Key(t)
    return ("%s:%s:%s:%s"):format(tostring(t.id), tostring(t.map), tostring(t.x), tostring(t.y))
end

function SP.Reset()
    local st = SP.state
    SP.state = nil
    if st then SetActive(st, false) end
end

function SP.Active(t)
    local st = SP.state
    return st ~= nil and st.active and (t == nil or st.target == t)
end

-- nearest open spot (index, yards); none open = nil
local function NearestOpen(st, d)
    local best, bd
    for i, s in ipairs(st.spots) do
        if d[i] and not SP.Cleared(s) and (not bd or d[i] < bd) then best, bd = i, d[i] end
    end
    return best, bd
end

-- the spot that opens first (all cleared)
local function Soonest(st)
    local best, bl
    for i, s in ipairs(st.spots) do
        local l = SP.Left(s)
        if not bl or l < bl then best, bl = i, l end
    end
    return best
end

local function OpenCount(st)
    local n = 0
    for _, s in ipairs(st.spots) do if not SP.Cleared(s) then n = n + 1 end end
    return n
end

local function Hint(st)
    local L = ns.L
    if SP.inCombat then return L.HUNT_COMBAT end
    local n = OpenCount(st)
    if n == 0 then
        local s = st.spots[st.cur]
        local min = math.max(1, math.ceil(SP.Left(s) / 60))
        return ns.U.Fill(L.SPOT_RESPAWN, { min = min })
    end
    return ns.U.Fill(L.SPOT_HINT, { n = n })
end

local function Info(st)
    local p = st.spots[st.cur]
    return p, { via = true, hunt = true, spot = true, point = p, hint = Hint(st), color = "arrowHunt", index = st.cur,
        n = #st.spots, route = { p } }
end

local function Pick(st, d, player)
    SP.stats.picks = SP.stats.picks + 1
    local i = NearestOpen(st, d)
    st.waiting = i == nil
    st.cur = i or Soonest(st)
    st.pickPos, st.cand, st.candN = player, nil, 0
end

function SP.Aim(t, map, x, y)
    local spots = SP.For(t)
    if not spots then
        if SP.state then SP.Reset() end
        return nil
    end
    if not (Num(map) and Num(x) and Num(y)) then return nil end
    SP.stats.polls = SP.stats.polls + 1
    local st, key = SP.state, Key(t)
    if not st or st.key ~= key then
        SP.Reset()
        st = { key = key, target = t, spots = spots, active = false, out = 0, inside = {} }
        SP.state = st
    end
    st.target = t
    local player = { map = map, x = x, y = y }
    if not World(player) then return nil end
    local d, near = {}, math.huge
    for i, s in ipairs(st.spots) do
        d[i] = Yards(player, s)
        if d[i] and d[i] < near then near = d[i] end
    end
    if near == math.huge then
        SetActive(st, false)
        return nil
    end
    -- visits and clearing (also in combat: noted quietly, shown after the fight)
    for i, s in ipairs(st.spots) do
        if d[i] then
            if d[i] <= s.r then
                st.inside[i] = true
            elseif st.inside[i] and d[i] > s.r + SP.LEAVE then
                st.inside[i] = nil
                Clear(s)
            end
        end
    end
    if not st.active then
        if not st.spot and Num(t.x) and Num(t.y) then st.spot = { map = t.map, x = t.x, y = t.y } end
        local sd = st.spot and Yards(player, st.spot)
        local r = Num(t.r) and t.r or ns.Format.DEFAULT_RADIUS
        if not ((sd and sd <= r) or near <= SP.ACTIVE) then return nil end
        if SP.inCombat then return nil end   -- no new target in combat
        st.out = 0
        Pick(st, d, player)
        st.anchor = player
        SetActive(st, true)
        return Info(st)
    end
    if near > SP.OUT then
        st.out = st.out + 1
        if st.out >= SP.OUT_POLLS then
            SetActive(st, false)
            return nil
        end
    else
        st.out = 0
    end
    if SP.inCombat then return Info(st) end   -- holds its spot, no new hint
    local cur = st.spots[st.cur]
    if st.waiting then
        -- all cleared: wait at the spot that opens first, until one is open again
        if NearestOpen(st, d) then Pick(st, d, player) end
        return Info(st)
    end
    if SP.Cleared(cur) then
        Pick(st, d, player)
        return Info(st)
    end
    -- standing still never switches: real movement since the last pick, and past the anchor
    local moved = true
    if st.pickPos then
        local m = Yards(player, st.pickPos)
        moved = m == nil or m >= SP.MOVE
    end
    local a = st.anchor and Yards(player, st.anchor)
    if a == nil or a > SP.STILL then st.anchor = player else moved = false end
    if moved then
        local b, bd = NearestOpen(st, d)
        local dc = d[st.cur]
        if b and b ~= st.cur and dc and bd < dc - math.max(SP.SWITCH_YD, SP.SWITCH_PCT * dc) then
            st.candN = st.cand == b and (st.candN or 0) + 1 or 1
            st.cand = b
            if st.candN >= SP.SWITCH_POLLS then
                st.cur, st.pickPos, st.cand, st.candN = b, player, nil, 0
                SP.stats.switches = SP.stats.switches + 1
            end
        else
            st.cand, st.candN = nil, 0
        end
    end
    return Info(st)
end

-- For the path line: the way to the current spot (one point).
function SP.Ahead(t)
    local st = SP.state
    if not (st and st.active and st.target == t) then return nil end
    return { st.spots[st.cur] }
end

-- For UI\SpotDots.lua: the arrow's step target's spots (also before the spot arrow starts), the current spot.
function SP.List()
    local A = ns.Arrow
    local t = A and A.target
    if not t or (A.source ~= nil and A.source ~= "step") then return nil end
    local H = ns.Hunt
    if not (H and H.On() and H.centreFor ~= t and H.Kind(t) == "spots") then return nil end
    local spots = SP.For(t)
    if not spots then return nil end
    local st = SP.state
    local cur = st and st.active and st.target == t and st.cur or nil
    return spots, cur, t
end

-- The arrow's target changed: a spot hunt for any other target ends.
function SP.Check()
    local st, A = SP.state, ns.Arrow
    if not st then return end
    local same = A and A.target ~= nil and (A.target == st.target or Key(A.target) == st.key)
    if not (same and (A.source == nil or A.source == "step")) then SP.Reset() end
end

-- ------------------------------------------------------------------ wiring
ns.Bus.On("CombatStarted", SP, function() SP.inCombat = true end, "spots")
ns.Bus.On("CombatEnded", SP, function() SP.inCombat = false end, "spots")
ns.Bus.On("Login", SP, function()
    SP.inCombat = ns.Compat.InCombat() == true
    SP.Load()
end, "spots", 60)
ns.Events.On("PLAYER_LOGOUT", SP, function() SP.Save() end, "spots")

-- In-game self-test: data loaded, the state is sane.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "spots", fn = function(h)
    h.Count()
    local n = 0
    for _ in pairs(SP.data) do n = n + 1 end
    local st = SP.state
    if st and st.active and (not st.cur or st.cur < 1 or st.cur > #st.spots) then h.Problem("spots: target outside the list") end
    if st and st.active and not (ns.Arrow and ns.Arrow.target == st.target) then
        h.Problem("spots: hunting for a target the arrow doesn't have")
    end
    h.Info(("spots: %d targets, %s, %d polls, %d cleared"):format(n, st and st.active and ("spot " .. st.cur .. "/" .. #st.spots)
        or "off", SP.stats.polls, SP.stats.cleared))
end }

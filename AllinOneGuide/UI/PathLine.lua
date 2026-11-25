-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Path line (2026-11-25, plans\path-line\plan.md): the arrow's way as a dotted trail on the world map and the
-- minimap: player -> the smart arrow's door / cave / gate points still ahead -> the goal (the whole route; a
-- straight line when there is no route; while Engine\HuntPath.lua leads round a step's loop, the loop from its
-- current point round to it again). Display only: no mouse on any dot, nothing clicks or moves for you.
-- World map: our own data provider (AddDataProvider only, like UI\Pins.lua) with one holder frame on the canvas
-- and pooled dot textures, counter-scaled so dots and gaps keep their screen size at any map zoom. Minimap: one
-- holder frame on the Minimap (the Minimap itself is never moved, re-parented or rescaled), dots placed by yards
-- from the player (C_Minimap.GetViewRadius covers zoom and the indoor zoom), turned when the minimap rotates,
-- cut at the map's edge for its shape (GetMinimapShape from minimap addons, read through UI\Minimap.lua).
-- Dots keep their place in the world while you walk (laid out from each leg's far end). Caps: WORLD_MAX /
-- MINI_MAX dots, pooled (no new textures after the first draw). Updates: like the minimap pins, every frame
-- only while moving / zooming / a rotating minimap ("follow"), a 0.25 s check when still ("watch"), nothing at
-- all when there is nothing to show. Secret or missing position / facing = no trail (never a guessed one).
-- Settings: pathMap, pathMinimap (both default on). Theme: color.pathNow / pathLater / pathCorpse,
-- size.pathDot / pathGap / pathMiniDot / pathMiniGap.
--   ns.PathLine.Points() -> list of map points (the player first) | nil   .Refresh()   .DrawWorld(map)   .DrawMini()
--   .Check() / .Follow(elapsed) / .Watch() / .mode   .world / .mini = { used = n, dots = {...} }   .provider
local _, ns = ...
local Th, Co = ns.Theme, ns.Compat
local PL = { WORLD_MAX = 120, MINI_MAX = 60, WATCH = 0.25, CALM = 0.3, POLL = 0.25, placed = 0, worldDraws = 0,
    checks = 0, polls = 0 }
ns.PathLine = PL

local sqrt, abs = math.sqrt, math.abs

local function WorldOn() return ns.Settings.Get("pathMap") and ns.Feature.IsOn("mappins") and not ns.safeMode end
local function MiniOn() return ns.Settings.Get("pathMinimap") and ns.Feature.IsOn("minimappins") and not ns.safeMode end
PL.WorldOn, PL.MiniOn = WorldOn, MiniOn

-- ------------------------------------------------------------------ the way
-- The arrow's target, when a trail may show for it: hidden "until the next step" = no trail; only while the
-- guide window is open, like the arrow itself (closing the window clears the arrow's target, corpse and
-- waypoint included: UI.Hide); the arrow setting being off doesn't hide the trail.
local function Target()
    local A = ns.Arrow
    local t = A and A.target
    if not t or (A.hiddenFor ~= nil and A.hiddenFor == t) then return nil end
    if not (ns.UI and ns.UI.IsShown and ns.UI.IsShown()) then return nil end
    return t, A.source
end
PL.Target = Target

-- The points after the player: the smart route's points still ahead (its last one is the goal), or the goal
-- alone (smart arrow off, "point straight", no route for this target yet).
local ahead = {}
local function Ahead(t)
    local SR = ns.SmartRoute
    local st = SR and SR.state
    for k = #ahead, 1, -1 do ahead[k] = nil end
    -- hunt path (v0.3): while the arrow leads round a step's loop, the trail is that loop from the current point
    local loop = ns.Hunt and ns.Hunt.Ahead(t)
    if loop then
        for k = 1, #loop do ahead[k] = loop[k] end
        return ahead
    end
    if SR and SR.On() and SR.straightFor ~= t and st and st.target == t and type(st.route) == "table" and st.i then
        for k = st.i, #st.route do ahead[#ahead + 1] = st.route[k] end
    end
    if #ahead == 0 then ahead[1] = t end
    return ahead
end

-- What the trail is made of, as one key: a change re-lays the dots; the same key only moves them.
local NONE = {}   -- the key for "no target" (one fixed table: a new {} each time looked like a change every frame)
local function RouteKey(t)
    if t == nil then return NONE, 0 end
    local H = ns.Hunt
    if H and H.Active(t) then return H.state.pts, H.state.i end
    local SR = ns.SmartRoute
    local st = SR and SR.state
    local on = SR and SR.On() and SR.straightFor ~= t and st and st.target == t
    return on and st.route or t, on and st.i or 0
end

-- The arrow polls SmartRoute while it is shown; while it isn't (world map open, arrow off) we poll it ourselves
-- at the arrow's rate, so the route still moves on as you walk through a door.
local function Poll(t, pm, px, py)
    local A, SR = ns.Arrow, ns.SmartRoute
    if not SR or (A and A.frame and A.frame:IsShown()) then return end
    PL.polls = PL.polls + 1
    if ns.Hunt then
        local ok, _, v = ns.Errors.Call("huntpath", ns.Hunt.Aim, t, pm, px, py, A and A.source)
        if ok and v then return end
    end
    ns.Errors.Call("smartarrow", SR.Aim, t, pm, px, py)
end

-- Player + the points ahead (map points), or nil when there is no trail to show.
function PL.Points()
    local t = Target()
    if not t then return nil end
    local pm, px, py = ns.Geo.Player()
    if not pm then return nil end
    local out = { { map = pm, x = px, y = py } }
    for _, p in ipairs(Ahead(t)) do out[#out + 1] = p end
    return out
end

-- World position of a point (exact per-map rectangle from UI\Pins.lua; nil when unknown).
local function WorldOf(map, x, y)
    local P = ns.Pins
    if not (P and P.WorldOf) then return nil end
    return P.WorldOf(map, x, y)
end

-- ------------------------------------------------------------------ dots (pooled textures on one holder)
local function NewSet() return { used = 0, dots = {}, made = 0 } end
PL.world, PL.mini = NewSet(), NewSet()

local function Dot(set, holder, i)
    local d = set.dots[i]
    if not d then
        d = holder:CreateTexture(nil, "OVERLAY")
        Th.Glyph(d, "pin.mini")   -- our own round dot (the minimap pin's art), recoloured per leg
        if d.SetSnapToPixelGrid then d:SetSnapToPixelGrid(false) end
        if d.SetTexelSnappingBias then d:SetTexelSnappingBias(0) end
        set.dots[i] = d
        set.made = set.made + 1
    end
    return d
end

local function HideFrom(set, n)
    for i = n + 1, set.used do
        local d = set.dots[i]
        if d then d:Hide() end
    end
    set.used = n
end

local function Clear(set) HideFrom(set, 0) end

-- Liang-Barsky: the part [t0, t1] of a -> b inside the box, nil when none.
local function ClipBox(ax, ay, bx, by, x0, y0, x1, y1)
    local t0, t1 = 0, 1
    local dx, dy = bx - ax, by - ay
    local p = { -dx, dx, -dy, dy }
    local q = { ax - x0, x1 - ax, ay - y0, y1 - ay }
    for k = 1, 4 do
        if p[k] == 0 then
            if q[k] < 0 then return nil end
        else
            local r = q[k] / p[k]
            if p[k] < 0 then
                if r > t1 then return nil end
                if r > t0 then t0 = r end
            else
                if r < t0 then return nil end
                if r < t1 then t1 = r end
            end
        end
    end
    return t0, t1
end
PL.ClipBox = ClipBox

-- Dot distances along a leg of length len (from a), every gap, counted back from b so the dots stay put
-- in the world while a moves; only those in [t0, t1] of the leg. Calls put(x along 0..1) for each.
local function Lay(len, gap, t0, t1, put)
    if len <= 0 or gap <= 0 then return end
    local s = len - math.ceil((len - t1 * len) / gap - 1e-9) * gap   -- the first dot at or before t1, from b
    while s >= t0 * len - 1e-9 do
        if s <= t1 * len + 1e-9 and s > 1e-9 then
            if put(s / len) == false then return end
        end
        s = s - gap
    end
end

local function LegColor(k, corpse)
    if corpse then return "pathCorpse" end
    return k == 1 and "pathNow" or "pathLater"
end

-- ------------------------------------------------------------------ world map
-- Map 0-1 of a world point on one map (the inverse of its rectangle), nil when another continent.
local function ToMap(r, c, wx, wy)
    if c ~= r[1] then return nil end
    local det = r[4] * r[7] - r[5] * r[6]
    if det == 0 then return nil end
    local dx, dy = wx - r[2], wy - r[3]
    return (dx * r[7] - dy * r[6]) / det, (dy * r[4] - dx * r[5]) / det
end
PL.ToMap = ToMap

local function WorldHolder(canvas)
    local h = PL.worldHolder
    if not h then
        h = CreateFrame("Frame", nil, canvas)
        h:EnableMouse(false)
        PL.worldHolder = h
    elseif h:GetParent() ~= canvas then
        h:SetParent(canvas)
    end
    h:ClearAllPoints()
    h:SetAllPoints(canvas)
    h:SetFrameLevel((canvas:GetFrameLevel() or 0) + 190)   -- under our pins (+200)
    h:Show()
    return h
end

function PL.DrawWorld(map)
    PL.worldDraws = PL.worldDraws + 1
    local set = PL.world
    -- tos (hunt path note): no world map redraws in combat; the dots stay as they are and are drawn again once
    -- the fight ends (bus CombatEnded)
    if Co.InCombat() then
        PL.worldWait = true
        return set.used
    end
    PL.worldWait = nil
    if not map or not WorldOn() then Clear(set) return 0 end
    local mapID = map.GetMapID and map:GetMapID()
    local canvas = map.GetCanvas and map:GetCanvas()
    local r = mapID and ns.Pins and ns.Pins.MapRect and ns.Pins.MapRect(mapID)
    if not (canvas and r) then Clear(set) return 0 end
    local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if w <= 0 or h <= 0 then Clear(set) return 0 end
    local cs = (map.GetCanvasScale and map:GetCanvasScale()) or 1
    if type(cs) ~= "number" or cs <= 0 then cs = 1 end
    local pts = PL.Points()
    if not pts then Clear(set) return 0 end
    -- canvas units of every point on this map (nil = another continent / unknown)
    local cx, cy = {}, {}
    for k, p in ipairs(pts) do
        local c, wx, wy = WorldOf(p.map, p.x, p.y)
        if c then
            local mx, my = ToMap(r, c, wx, wy)
            if mx then cx[k], cy[k] = mx * w, my * h end
        end
    end
    -- the legs inside the map, and their length on screen
    local legs, total = {}, 0
    for k = 1, #pts - 1 do
        if cx[k] and cx[k + 1] then
            local t0, t1 = ClipBox(cx[k], cy[k], cx[k + 1], cy[k + 1], 0, 0, w, h)
            if t0 and t1 > t0 then
                local len = sqrt((cx[k + 1] - cx[k]) ^ 2 + (cy[k + 1] - cy[k]) ^ 2)
                legs[#legs + 1] = { k = k, t0 = t0, t1 = t1, len = len }
                total = total + len * (t1 - t0) * cs
            end
        end
    end
    -- screen sizes -> canvas units; a longer way gets wider gaps so it stays within the cap
    local gapPx = math.max(1, Th.Size("pathGap"))
    if total / gapPx > PL.WORLD_MAX then gapPx = total / PL.WORLD_MAX end
    local gap, size = gapPx / cs, Th.Size("pathDot") / cs
    local holder = WorldHolder(canvas)
    local corpse = ns.Arrow and ns.Arrow.source == "corpse"
    local n = 0
    for _, leg in ipairs(legs) do
        local k = leg.k
        local cr, cg, cb, ca = Th.Color(LegColor(k, corpse))
        local ax, ay, bx, by = cx[k], cy[k], cx[k + 1], cy[k + 1]
        Lay(leg.len, gap, leg.t0, leg.t1, function(u)
            if n >= PL.WORLD_MAX then return false end
            n = n + 1
            local d = Dot(set, holder, n)
            d:SetSize(size, size)
            d:SetVertexColor(cr, cg, cb, ca)
            d:ClearAllPoints()
            d:SetPoint("CENTER", holder, "TOPLEFT", ax + (bx - ax) * u, -(ay + (by - ay) * u))
            d:Show()
        end)
    end
    HideFrom(set, n)
    return n
end

local function Provider()
    if PL.provider then return PL.provider end
    local mixin, create = Co.fn.MapProviderMixin, Co.fn.CreateFromMixins
    if not (mixin and create) then return nil end
    local p = create(mixin)
    p.RemoveAllData = function() Clear(PL.world) end
    p.RefreshAllData = function(self) ns.Errors.Call("pathline", PL.DrawWorld, self:GetMap()) end
    p.OnMapChanged = function(self) self:RefreshAllData() end
    p.OnCanvasScaleChanged = function(self) self:RefreshAllData() end
    PL.provider = p
    return p
end

function PL.AttachWorld()
    local wm = Co.fn.WorldMapFrame or Co.Resolve("WorldMapFrame")
    if PL.attached or type(wm) ~= "table" or type(wm.AddDataProvider) ~= "function" then return false end
    local p = Provider()
    if not p then return false end
    wm:AddDataProvider(p)
    PL.attached = wm
    return true
end

local function MapOpen()
    local wm = PL.attached
    return wm ~= nil and wm.IsShown ~= nil and wm:IsShown() == true
end

local function RedrawWorld()
    if MapOpen() and PL.provider then PL.provider:RefreshAllData() else Clear(PL.world) end
end

-- ------------------------------------------------------------------ minimap
-- The map's shape per quarter (1 = bottom-right, 2 = bottom-left, 3 = top-right, 4 = top-left: true = round),
-- from UI\Minimap.lua's reading of GetMinimapShape (read only; round when unknown).
local ROUND = { true, true, true, true }
local function Quarters()
    local MM = ns.MinimapButton
    if not (MM and type(MM.Shape) == "function" and type(MM.SHAPES) == "table") then return ROUND end
    local ok, shape = pcall(MM.Shape)
    local q = ok and type(shape) == "string" and MM.SHAPES[shape]
    return type(q) == "table" and q or ROUND
end
PL.Quarters = Quarters

local function Inside(x, y, hw, hh, quarters)
    local q = (x >= 0 and y < 0 and 1) or (x < 0 and y < 0 and 2) or (x >= 0 and 3) or 4
    if quarters[q] then return (x / hw) ^ 2 + (y / hh) ^ 2 <= 1 end
    return abs(x) <= hw and abs(y) <= hh
end
PL.Inside = Inside

local function MiniHolder(mm)
    local h = PL.miniHolder
    if not h then
        h = CreateFrame("Frame", nil, mm)
        h:EnableMouse(false)
        h:SetAllPoints(mm)
        PL.miniHolder = h
    end
    h:SetFrameLevel((mm:GetFrameLevel() or 0) + 4)   -- under the minimap pins (+5)
    h:Show()
    return h
end

-- Readings for one placement (all in one go, so position, facing and zoom belong to the same frame).
local function Read(mm)
    local pm, px, py = ns.Geo.Player()
    local rotate = Co.CVarBool("rotateMinimap") == true
    local facing = nil
    if rotate then facing = Co.Facing() end
    return pm, px, py, Co.MinimapRadius(), mm:GetWidth() or 0, mm:GetHeight() or 0, facing, rotate
end

local last = {}
PL.last = last

-- Places the minimap dots from one set of readings.
function PL.PlaceMini(mm, pm, px, py, radius, w, h, facing, rotate)
    PL.placed = PL.placed + 1
    local set = PL.mini
    local t = Target()
    -- a rotating minimap without a facing we can read: no trail (never a guessed turn)
    if not t or not pm or type(radius) ~= "number" or radius <= 0 or w <= 0 or h <= 0
        or (rotate and type(facing) ~= "number") then
        Clear(set)
        return 0
    end
    local c0, ox, oy = WorldOf(pm, px, py)
    if not c0 then Clear(set) return 0 end
    local pts = Ahead(t)
    local size = Th.Size("pathMiniDot")
    local hw, hh = w / 2 - size / 2, h / 2 - size / 2
    local cosf, sinf = 1, 0
    if rotate then cosf, sinf = math.cos(facing), math.sin(facing) end
    -- pixel offsets (right, up) from the minimap's centre; the player is 0, 0
    local xs, ys = { 0 }, { 0 }
    for k, p in ipairs(pts) do
        local c, wx, wy = WorldOf(p.map, p.x, p.y)
        if c and c == c0 then
            local east, north = -(wy - oy), wx - ox   -- world y points west
            if rotate then east, north = east * cosf + north * sinf, -east * sinf + north * cosf end
            xs[k + 1], ys[k + 1] = east / radius * (w / 2), north / radius * (h / 2)
        end
    end
    local holder = MiniHolder(mm)
    local quarters = Quarters()
    local gap = math.max(1, Th.Size("pathMiniGap"))
    local corpse = ns.Arrow and ns.Arrow.source == "corpse"
    local n = 0
    for k = 1, #pts do
        local ax, ay, bx, by = xs[k], ys[k], xs[k + 1], ys[k + 1]
        if not (ax and bx) then break end   -- another continent from here on: nothing more to draw
        local t0, t1 = ClipBox(ax, ay, bx, by, -hw, -hh, hw, hh)
        if t0 and t1 > t0 then
            local len = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
            local cr, cg, cb, ca = Th.Color(LegColor(k, corpse))
            Lay(len, gap, t0, t1, function(u)
                local x, y = ax + (bx - ax) * u, ay + (by - ay) * u
                if not Inside(x, y, hw, hh, quarters) then return end
                if n >= PL.MINI_MAX then return false end
                n = n + 1
                local d = Dot(set, holder, n)
                d:SetSize(size, size)
                d:SetVertexColor(cr, cg, cb, ca)
                d:SetPoint("CENTER", mm, "CENTER", x, y)
                d:Show()
            end)
        end
        if n >= PL.MINI_MAX then break end
    end
    HideFrom(set, n)
    return n
end

function PL.DrawMini()
    local mm = Co.fn.Minimap
    if not mm or not MiniOn() then
        Clear(PL.mini)
        for k in pairs(last) do last[k] = nil end
        return 0
    end
    local pm, px, py, radius, w, h, facing, rotate = Read(mm)
    last.pm, last.px, last.py, last.radius, last.w, last.h, last.facing, last.rotate = pm, px, py, radius, w, h, facing, rotate
    last.route, last.i = RouteKey(Target())
    last.shape = Quarters()
    return PL.PlaceMini(mm, pm, px, py, radius, w, h, facing, rotate)
end

-- ------------------------------------------------------------------ keeping it current
-- One look: the own SmartRoute poll (every POLL s while the arrow doesn't poll), the minimap when a reading or
-- the route changed, the open world map when the player or the route changed (at most every POLL s).
-- Returns true when something was placed again.
local sincePoll, sinceWorld = 0, 0
local UpdateDriver
function PL.Check(elapsed)
    PL.checks = PL.checks + 1
    elapsed = tonumber(elapsed) or 0
    sincePoll, sinceWorld = sincePoll + elapsed, sinceWorld + elapsed
    local t = Target()
    if not t then
        -- the target went away without a bus event (arrow menu "Hide until the next step"): drop the dots and
        -- stop the driver; the next target comes with StepChanged / WaypointChanged (Refresh starts it again)
        Clear(PL.mini)
        for k in pairs(last) do last[k] = nil end
        if PL.world.used > 0 then Clear(PL.world) end
        PL.wpm = nil
        UpdateDriver()
        return false
    end
    local changed = false
    local pm, px, py
    if t and sincePoll >= PL.POLL then
        sincePoll = 0
        pm, px, py = ns.Geo.Player()
        if pm then Poll(t, pm, px, py) end
    end
    local route, i = RouteKey(t)
    local mm = Co.fn.Minimap
    if mm and MiniOn() and not (mm.IsVisible and not mm:IsVisible()) then
        local rpm, rpx, rpy, radius, w, h, facing, rotate = Read(mm)
        local quarters = Quarters()
        if rpm ~= last.pm or rpx ~= last.px or rpy ~= last.py or radius ~= last.radius or w ~= last.w or h ~= last.h
            or facing ~= last.facing or rotate ~= last.rotate or route ~= last.route or i ~= last.i
            or quarters ~= last.shape then
            last.pm, last.px, last.py, last.radius, last.w, last.h, last.facing, last.rotate = rpm, rpx, rpy, radius, w, h, facing, rotate
            last.route, last.i, last.shape = route, i, quarters
            PL.PlaceMini(mm, rpm, rpx, rpy, radius, w, h, facing, rotate)
            changed = true
        end
    elseif PL.mini.used > 0 or last.pm ~= nil then
        Clear(PL.mini)
        for k in pairs(last) do last[k] = nil end   -- placed again in full when it shows
    end
    if MapOpen() and WorldOn() and sinceWorld >= PL.POLL then
        sinceWorld = 0
        if not pm then pm, px, py = ns.Geo.Player() end
        if pm ~= PL.wpm or px ~= PL.wpx or py ~= PL.wpy or route ~= PL.wroute or i ~= PL.wi then
            PL.wpm, PL.wpx, PL.wpy, PL.wroute, PL.wi = pm, px, py, route, i
            RedrawWorld()
            changed = true
        end
    end
    return changed
end

-- follow (OnUpdate every frame) / watch (a WATCH s ticker that only checks), like the minimap pins
local driver = CreateFrame("Frame")
PL.driver = driver
local calm = 0

local function OnFrame(_, elapsed) ns.Errors.Call("pathline", PL.Follow, elapsed) end
local function OnWatch() ns.Errors.Call("pathline", PL.Watch) end

function PL.SetMode(mode)
    if mode == PL.mode then return end
    PL.mode = mode
    calm = 0
    driver:SetScript("OnUpdate", mode == "follow" and OnFrame or nil)
    if mode == "watch" then
        if not PL.watcher then PL.watcher = Co.Ticker(PL.WATCH, OnWatch) end
    elseif PL.watcher then
        PL.watcher:Cancel()
        PL.watcher = nil
    end
end

function PL.Follow(elapsed)
    if PL.Check(elapsed) then calm = 0 else calm = calm + (tonumber(elapsed) or 0) end
    if calm >= PL.CALM and not PL.moving and not last.rotate then PL.SetMode("watch") end
end

function PL.Watch()
    if PL.Check(PL.WATCH) then PL.SetMode("follow") end
end

local function OnMoving(event)
    PL.moving = event == "PLAYER_STARTED_MOVING"
    if PL.moving and PL.mode then PL.SetMode("follow") end
end
local function OnZoom()
    if PL.mode then PL.SetMode("follow") end
end
local EVENTS = { PLAYER_STARTED_MOVING = OnMoving, PLAYER_STOPPED_MOVING = OnMoving, MINIMAP_UPDATE_ZOOM = OnZoom }

-- Something to show at all: a target, and the minimap trail on or the world map open with its trail on.
function PL.Wanted()
    if not Target() then return false end
    return (MiniOn() and Co.fn.Minimap ~= nil) or (WorldOn() and MapOpen())
end

function UpdateDriver()
    local want = PL.Wanted()
    if want and not PL.mode then
        for e, fn in pairs(EVENTS) do ns.Events.On(e, PL, fn, "pathline") end
        PL.SetMode("follow")
    elseif not want and PL.mode then
        PL.SetMode(nil)
        for e in pairs(EVENTS) do ns.Events.Off(e, PL) end
        PL.moving = nil
    end
end

function PL.Refresh()
    if not PL.attached and WorldOn() then PL.AttachWorld() end
    PL.wpm = nil
    if WorldOn() then RedrawWorld() else Clear(PL.world) end
    PL.DrawMini()
    UpdateDriver()
end

-- In-game self-test: attached when on, caps kept, no driver running with nothing to show.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "path", fn = function(h)
    h.Count()
    if WorldOn() and not PL.attached then h.Problem("path: world map path line is on but not attached to the world map") end
    if PL.world.used > PL.WORLD_MAX or PL.mini.used > PL.MINI_MAX then h.Problem("path: more dots than the cap") end
    if (PL.driver:GetScript("OnUpdate") ~= nil) ~= (PL.mode == "follow") then
        h.Problem("path: follow OnUpdate doesn't match its mode")
    end
    if PL.mode and not PL.Wanted() then h.Problem("path: follow runs with nothing to show") end
    h.Info(("path: world %d, minimap %d dots, follow %s"):format(PL.world.used, PL.mini.used, tostring(PL.mode or "off")))
end }

local function Later() ns.Errors.Call("pathline", PL.Refresh) end
ns.Bus.On("Login", PL, function()
    PL.AttachWorld()
    for _, ev in ipairs({ "StepChanged", "WaypointChanged", "WindowToggled", "ZoneChanged", "LookChanged",
        "SmartRouteChanged", "HuntChanged", "WorldMapShown", "WorldMapHidden" }) do
        ns.Bus.On(ev, PL, Later, "pathline", 95)
    end
    ns.Bus.On("CombatEnded", PL, function()
        if PL.worldWait then
            PL.wpm = nil
            ns.Errors.Call("pathline", RedrawWorld)
        end
    end, "pathline", 95)
    ns.Bus.On("SettingsChanged", PL, function(_, key)
        if key == "pathMap" or key == "pathMinimap" or key == "smartArrow" or key == "arrow" then Later() end
    end, "pathline", 95)
    Later()
end, "pathline", 86)

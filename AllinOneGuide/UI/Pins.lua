-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Map pins (v0.2 M3): only the step we are on (beta.2: the user's choice; before, the next steps too,
-- numbered 1-12), on the world map and the minimap. An any-order group's other open stops are part of
-- that step and get a pin too (at most 12). A manual / addon / corpse waypoint keeps its own pin.
-- Hover: what it is and "click: point the arrow here"; click sets the arrow (waypoint "show").
-- World map: our own data provider (MapCanvasDataProviderMixin, the way Blizzard's own pins come and
-- go with the map) that places our own pooled frames on the map canvas; no pin template, no XML, no
-- Blizzard pin pools touched. Minimap: our own pooled frames on the Minimap frame, placed by yards from
-- the player (C_Minimap.GetViewRadius), clamped to the edge, turned when the minimap rotates.
-- Minimap follow (beta.2 fix "pins jump / lag when I move"): every frame while the player moves, the
-- zoom changes or the minimap rotates ("follow", an OnUpdate); when nothing has changed for CALM s a
-- WATCH s ticker only looks for a change ("watch": boats, knockbacks). The player's world position comes
-- from a per-map rectangle (no rounding, no cache churn); pins are re-placed only when a reading changed.
-- Settings: mapPins, minimapPins (both default on).
--   ns.Pins.Targets() -> { { map, x, y, title, kind, step } }   .Refresh()   .world / .mini (pools)
--   .Follow(elapsed) / .Watch() / .Check() / .mode ("follow" | "watch" | nil) / .MapRect(map)
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local P = { MAX = 12, WATCH = 0.25, CALM = 0.3, placed = 0, checks = 0 }
ns.Pins = P

local function L() return ns.L end

-- ------------------------------------------------------------------ what to show
-- The waypoint (if it isn't the step), then the current step's spot, then (any-order group) the group's
-- other open stops with a spot. Optimizer #3: the list is kept until something it is made from changes
-- (the window's model table, which is new on every window refresh, the waypoint, its source, the window
-- shown, the cap), so the minimap follow only moves the pins. The caller only reads the list.
local cache = {}
local function HasSpot(s) return s ~= nil and s.map ~= nil and s.x ~= nil and s.y ~= nil end

-- The other open stops of the current step's any-order group (in route order), added to out.
local function GroupSpots(out, m, cur)
    local top = m.top
    local g = cur.anyOrder
    if not (g and top and top.GroupStart and top.IsStop and top.Step and top.Count) then return end
    local n = top:Count()
    local j = top:GroupStart(cur.index or top.pos)
    while j <= n and #out < P.MAX do
        local s = top:Step(j)
        if not s or s.anyOrder ~= g then break end
        if s ~= cur and s.index ~= cur.index and HasSpot(s) and not (s.flags and s.flags.optional) and top:IsStop(s, j) then
            out[#out + 1] = { map = s.map, x = s.x, y = s.y, title = top.Text and top:Text(s) or nil, kind = "group", step = s }
        end
        j = j + 1
    end
end
function P.Targets()
    local wp, src = nil, nil
    if ns.Waypoint then wp, src = ns.Waypoint.Current() end
    local m = ns.UI and ns.UI.model
    local shown = ns.UI ~= nil and ns.UI.IsShown() == true
    if cache.list and cache.m == m and cache.wp == wp and cache.src == src and cache.shown == shown and cache.max == P.MAX then
        return cache.list, true
    end
    local out = {}
    if wp and src ~= "step" then
        out[1] = { map = wp.map, x = wp.x, y = wp.y, title = wp.title or L().MENU_STEP_POINT, kind = src }
    end
    local row = m and m.state == "guide" and shown and m.rows and m.rows[1]
    if row and row.step and #out < P.MAX then
        -- only the step we are on (beta.2, the user's choice); no route numbers on the pins any more
        local cur = row.step
        if HasSpot(cur) then
            out[#out + 1] = { map = cur.map, x = cur.x, y = cur.y, title = row.text, kind = "current", step = cur }
        end
        GroupSpots(out, m, cur)
    end
    cache.list, cache.m, cache.wp, cache.src, cache.shown, cache.max = out, m, wp, src, shown, P.MAX
    return out, false
end
function P.ResetTargets() cache.list = nil end

-- ------------------------------------------------------------------ pools
-- World pin (art: pin body + number plate, 24 px, the tip at the bottom centre) or minimap dot (12 px).
local function MakePin(parent, mini)
    local pin = CreateFrame("Button", nil, parent)
    local size = mini and 12 or 24
    pin:SetSize(size, size)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    Th.Glyph(pin.icon, mini and "pin.mini" or "pin.body")
    pin.ring = pin:CreateTexture(nil, "ARTWORK", nil, 3)
    pin.ring:SetSize(size * 1.5, size * 1.5)
    pin.ring:SetPoint("CENTER", pin, mini and "CENTER" or "TOP", 0, mini and 0 or -size * 0.38)
    Th.Glyph(pin.ring, "pin.ring")
    pin.ring:Hide()
    if mini then
        -- moving by part of a pixel each frame: no snapping to whole pixels, or the dot steps instead of
        -- gliding (Texture:SetSnapToPixelGrid / SetTexelSnappingBias, SimpleTextureBaseAPIDocumentation)
        for _, tex in ipairs({ pin.icon, pin.ring }) do
            if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
            if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
        end
    else
        pin.face = pin:CreateTexture(nil, "ARTWORK", nil, 1)
        pin.face:SetAllPoints()
        Th.Glyph(pin.face, "pin.face")
        pin.face:SetVertexColor(Th.Color("pinFace"))
        pin.num = K.Text(pin, "small", "white", "CENTER")
        pin.num:SetPoint("CENTER", pin, "TOP", 0, -size * 0.38)
    end
    pin:RegisterForClicks("LeftButtonUp")
    pin:SetScript("OnClick", function(self) P.Click(self.target) end)
    pin:SetScript("OnEnter", function(self) P.Hover(self, self.target) end)
    pin:SetScript("OnLeave", K.HideTooltip)
    return pin
end
P.world = K.Pool(function(parent) return MakePin(parent, false) end)
P.mini = K.Pool(function(parent) return MakePin(parent, true) end)

local function Acquire(pool, parent) return pool.Acquire(parent) end

local function ReleaseAll(pool)
    for _, pin in ipairs(pool.used) do pin.target = nil end
    pool.ReleaseAll()
end
P.ReleaseAll = ReleaseAll

local COLOR = { current = "accent", group = "accent", next = "text.dim", show = "icon.goto", external = "icon.goto", corpse = "corpse" }

-- The pin colour: an upcoming step's pin has its row badge's colour (look review #8), else by kind.
function P.ColorKey(t)
    if t.kind == "next" and t.step then
        local b = K.BADGE[K.BadgeKind(t.step)]
        if b then return b[2] end
    end
    return COLOR[t.kind] or "text.dim"
end

local function Look(pin, t)
    pin.target = t
    pin.icon:SetVertexColor(Th.Color(P.ColorKey(t)))
    -- the ring: the current step's main spot and the waypoint pins; an any-order group's other stops have none
    pin.ring:SetShown(t.kind ~= "next" and t.kind ~= "group")
    if pin.num then pin.num:SetText(t.num and tostring(t.num) or "") end
end

function P.Click(t)
    if not t or not ns.Waypoint then return end
    ns.Waypoint.Set("show", { map = t.map, x = t.x, y = t.y, title = t.title })
end

function P.Hover(pin, t)
    if not t then return end
    local where = ("%.1f, %.1f"):format(t.x * 100, t.y * 100)
    local zone = Co.MapName(t.map)
    if zone then where = zone .. " " .. where end
    if t.title then K.Tooltip(pin, t.title, { where, L().PIN_CLICK })
    else K.Tooltip(pin, where, { L().PIN_CLICK }) end
end

-- ------------------------------------------------------------------ world map
local function WorldOn() return ns.Settings.Get("mapPins") and ns.Feature.IsOn("mappins") and not ns.safeMode end

function P.DrawWorld(map)
    ReleaseAll(P.world)
    if not map or not WorldOn() then return 0 end
    local mapID = map.GetMapID and map:GetMapID()
    local canvas = map.GetCanvas and map:GetCanvas()
    if not mapID or not canvas then return 0 end
    local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if w <= 0 or h <= 0 then return 0 end
    local cs = (map.GetCanvasScale and map:GetCanvasScale()) or 1
    if type(cs) ~= "number" or cs <= 0 then cs = 1 end
    local scale = 1 / cs
    local n = 0
    for _, t in ipairs(P.Targets()) do
        if t.map == mapID then
            local pin = Acquire(P.world, canvas)
            Look(pin, t)
            pin:SetScale(scale)
            pin:SetFrameLevel((canvas:GetFrameLevel() or 0) + 200 + (t.kind == "current" and 20 or 0))
            pin:ClearAllPoints()
            -- the pin's tip (bottom centre, 3 px under the art's tip) on the spot
            pin:SetPoint("BOTTOM", canvas, "TOPLEFT", t.x * w / scale, -t.y * h / scale - 3)
            pin:Show()
            n = n + 1
        end
    end
    return n
end

local function Provider()
    if P.provider then return P.provider end
    local mixin, create = Co.fn.MapProviderMixin, Co.fn.CreateFromMixins
    if not (mixin and create) then return nil end
    local p = create(mixin)
    p.RemoveAllData = function() ReleaseAll(P.world) end
    p.RefreshAllData = function(self) ns.Errors.Call("pins", P.DrawWorld, self:GetMap()) end
    p.OnMapChanged = function(self) self:RefreshAllData() end
    p.OnCanvasScaleChanged = function(self) self:RefreshAllData() end
    P.provider = p
    return p
end

function P.AttachWorld()
    local wm = Co.fn.WorldMapFrame or Co.Resolve("WorldMapFrame")
    if P.attached or type(wm) ~= "table" or type(wm.AddDataProvider) ~= "function" then return false end
    local p = Provider()
    if not p then return false end
    wm:AddDataProvider(p)
    P.attached = wm
    return true
end

local function RefreshWorld()
    local wm = P.attached
    if wm and wm.IsShown and wm:IsShown() and P.provider then P.provider:RefreshAllData() end
end

-- ------------------------------------------------------------------ minimap
local function MiniOn() return ns.Settings.Get("minimapPins") and ns.Feature.IsOn("minimappins") and not ns.safeMode end

-- Map 0-1 -> world yards for one map: { continent, origin x, origin y, world step per map x (2), per map y
-- (2) }, from three C_Map.GetWorldPosFromMapPos reads once per map. A uiMap is an axis-aligned rectangle in
-- the world, so this is exact; unlike Geo.World (rounded to 1e-4 and cached per point, fine for fixed step
-- spots) it doesn't round the moving player or fill a cache every frame. false = no world position for that
-- map (dropped again on Refresh).
local rects = {}
P.rects = rects
function P.MapRect(map)
    if type(map) ~= "number" or not ns.Feature.IsOn("worldpos") then return nil end
    local r = rects[map]
    if r == nil then
        r = false
        local c0, ox, oy = Co.WorldPos(map, 0, 0)
        local c1, ex, ey = Co.WorldPos(map, 1, 0)
        local c2, sx, sy = Co.WorldPos(map, 0, 1)
        if c0 and c0 == c1 and c0 == c2 and type(ox) == "number" and type(oy) == "number" and type(ex) == "number"
            and type(ey) == "number" and type(sx) == "number" and type(sy) == "number" then
            r = { c0, ox, oy, ex - ox, ey - oy, sx - ox, sy - oy }
        end
        rects[map] = r
    end
    return r or nil
end

-- continent, world x, world y (yards) of a map point, or nil.
local function WorldOf(map, x, y)
    local r = P.MapRect(map)
    if not r or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return r[1], r[2] + x * r[4] + y * r[6], r[3] + x * r[5] + y * r[7]
end
P.WorldOf = WorldOf

-- A target's world spot, kept on the target (the list is made again when the step changes).
local function TargetWorld(t)
    if t.wc == nil then
        local c, wx, wy = WorldOf(t.map, t.x, t.y)
        t.wc, t.wx, t.wy = c or false, wx, wy
    end
    if not t.wc then return nil end
    return t.wc, t.wx, t.wy
end

-- Minimap offset in pixels (right, up) for a target, and whether it sits on the edge; nil when unknown.
function P.MiniOffset(t, pm, px, py, radius, w, h, facing, rotate)
    local c1, ax, ay = WorldOf(pm, px, py)
    local c2, bx, by = TargetWorld(t)
    if not c1 or not c2 or c1 ~= c2 then return nil end
    local east, north = -(by - ay), bx - ax   -- world y points west
    if rotate and type(facing) == "number" then
        local c, s = math.cos(facing), math.sin(facing)
        east, north = east * c + north * s, -east * s + north * c
    end
    local d = math.sqrt(east * east + north * north)
    local edge = false
    local max = radius * 0.92
    if d > max and d > 0 then
        east, north = east * max / d, north * max / d
        edge = true
    end
    return east / radius * (w / 2), north / radius * (h / 2), edge
end

-- What the last placement used; all nil = nothing placed. Everything is read in one go (Read), so the
-- position, facing and zoom of one placement always belong to the same frame.
local last = {}
P.last = last
local function Remember(pm, px, py, radius, w, h, facing, rotate)
    last.pm, last.px, last.py, last.radius, last.w, last.h, last.facing, last.rotate = pm, px, py, radius, w, h, facing, rotate
end

local function Read(mm)
    local pm, px, py = ns.Geo.Player()
    local rotate = Co.CVarBool("rotateMinimap")
    return pm, px, py, Co.MinimapRadius(), mm:GetWidth() or 0, mm:GetHeight() or 0, rotate and Co.Facing() or nil, rotate
end

local function Clear()
    ReleaseAll(P.mini)
    P.miniList = nil
    Remember()
    return 0
end

-- One pin to its offset; the scale only changes when the pin goes to / leaves the edge.
local function Put(pin, mm, dx, dy, edge)
    local s = edge and 0.75 or 1
    if pin.edge ~= edge then
        pin.edge = edge
        pin:SetScale(s)
    end
    pin:SetPoint("CENTER", mm, "CENTER", dx / s, dy / s)
end

-- Places the minimap pins from one set of readings. Full draw (on Refresh or when the targets changed):
-- acquire, look, level, place. moveOnly (the follow): when the targets are the same list as last drawn,
-- only move the pins already up (one SetPoint each, no ClearAllPoints, no new tables).
function P.Place(moveOnly, mm, pm, px, py, radius, w, h, facing, rotate)
    if not pm or not radius or w <= 0 or h <= 0 then return Clear() end
    Remember(pm, px, py, radius, w, h, facing, rotate)
    P.placed = P.placed + 1
    local list = P.Targets()
    local used = P.mini.used
    if moveOnly and list == P.miniList then
        -- same targets: the pins in P.mini.used are in target order
        local n = 0
        for _, pin in ipairs(used) do
            local t = pin.target
            local dx, dy, edge = nil, nil, false
            if t then dx, dy, edge = P.MiniOffset(t, pm, px, py, radius, w, h, facing, rotate) end
            if dx then
                Put(pin, mm, dx, dy, edge)
                if not pin:IsShown() then pin:Show() end
                n = n + 1
            elseif pin:IsShown() then
                pin:Hide()   -- off this continent now; the next full draw drops it
            end
        end
        -- a target that had no spot before may have one now (another continent -> this one): full draw
        if n == #used then
            if #list == n then return n end
            local all = 0
            for _, t in ipairs(list) do
                if P.MiniOffset(t, pm, px, py, radius, w, h, facing, rotate) then all = all + 1 end
            end
            if all == n then return n end
        end
    end
    ReleaseAll(P.mini)
    P.miniList = list
    local n = 0
    for _, t in ipairs(list) do
        local dx, dy, edge = P.MiniOffset(t, pm, px, py, radius, w, h, facing, rotate)
        if dx then
            local pin = Acquire(P.mini, mm)
            Look(pin, t)
            pin:SetFrameLevel((mm:GetFrameLevel() or 0) + 5 + (t.kind == "current" and 2 or 0))
            pin:ClearAllPoints()
            pin.edge = nil
            Put(pin, mm, dx, dy, edge)
            pin:Show()
            n = n + 1
        end
    end
    return n
end

function P.DrawMini(moveOnly)
    local mm = Co.fn.Minimap
    if not mm or not MiniOn() then return Clear() end
    return P.Place(moveOnly, mm, Read(mm))
end

-- One look: read everything, re-place the pins only when a reading (or the target list) changed.
-- Returns true when the pins were placed again.
function P.Check()
    P.checks = P.checks + 1
    local mm = Co.fn.Minimap
    if not mm or not MiniOn() then
        if P.miniList then Clear() end
        return false
    end
    if mm.IsVisible and not mm:IsVisible() then return false end   -- a hidden minimap: placed when it shows
    local pm, px, py, radius, w, h, facing, rotate = Read(mm)
    if pm == last.pm and px == last.px and py == last.py and radius == last.radius and w == last.w and h == last.h
        and facing == last.facing and rotate == last.rotate and P.miniList == P.Targets() then
        return false
    end
    P.Place(true, mm, pm, px, py, radius, w, h, facing, rotate)
    return true
end

-- ------------------------------------------------------------------ minimap follow
-- "follow": an OnUpdate, every frame (moving, zooming, a rotating minimap). After CALM s with nothing new
-- (and not moving, minimap not rotating): "watch", a WATCH s ticker that only checks. A change seen by
-- the watch, PLAYER_STARTED_MOVING or MINIMAP_UPDATE_ZOOM switch back to follow at once.
local driver = CreateFrame("Frame")
P.driver = driver
local calm = 0

local function OnFrame(_, elapsed) ns.Errors.Call("pins", P.Follow, elapsed) end
local function OnWatch() ns.Errors.Call("pins", P.Watch) end

function P.SetMode(mode)
    if mode == P.mode then return end
    P.mode = mode
    calm = 0
    driver:SetScript("OnUpdate", mode == "follow" and OnFrame or nil)
    if mode == "watch" then
        if not P.watcher then P.watcher = Co.Ticker(P.WATCH, OnWatch) end
    elseif P.watcher then
        P.watcher:Cancel()
        P.watcher = nil
    end
end

function P.Follow(elapsed)
    if P.Check() then calm = 0 else calm = calm + (tonumber(elapsed) or 0) end
    if calm >= P.CALM and not P.moving and not last.rotate then P.SetMode("watch") end
end

function P.Watch()
    if P.Check() then P.SetMode("follow") end
end

local function OnMoving(event)
    P.moving = event == "PLAYER_STARTED_MOVING"
    if P.moving and P.mode then P.SetMode("follow") end
end
local function OnZoom()
    if P.mode then P.SetMode("follow") end
end
-- event, handler (UnitDocumentation PLAYER_STARTED_MOVING / PLAYER_STOPPED_MOVING, MinimapDocumentation
-- MINIMAP_UPDATE_ZOOM; also sent on the indoor / outdoor zoom switch). Registered only while pins follow.
local EVENTS = { PLAYER_STARTED_MOVING = OnMoving, PLAYER_STOPPED_MOVING = OnMoving, MINIMAP_UPDATE_ZOOM = OnZoom }

local function UpdateDriver()
    local want = MiniOn() and Co.fn.Minimap ~= nil and #P.Targets() > 0
    if want and not P.mode then
        for e, fn in pairs(EVENTS) do ns.Events.On(e, P, fn, "pins") end
        P.SetMode("follow")
    elseif not want and P.mode then
        P.SetMode(nil)
        for e in pairs(EVENTS) do ns.Events.Off(e, P) end
        P.moving = nil
    end
end

-- ------------------------------------------------------------------ refresh
function P.Refresh()
    if not P.attached and WorldOn() then P.AttachWorld() end
    if not WorldOn() then ReleaseAll(P.world) else RefreshWorld() end
    for map, r in pairs(rects) do if r == false then rects[map] = nil end end   -- try those maps again
    P.DrawMini()
    UpdateDriver()
end

-- In-game self-test: the map provider is attached, the pin counts stay under the cap, the hooks are in.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "pins", fn = function(h)
    h.Count()
    if ns.Settings.Get("mapPins") and ns.Feature.IsOn("mappins") and not P.attached then
        h.Problem("pins: world map pins are on but not attached to the world map")
    end
    if #P.world.used > P.MAX or #P.mini.used > P.MAX then h.Problem("pins: more than " .. P.MAX .. " pins") end
    -- beta.2: only the step we are on (plus its any-order group and the waypoint)
    for _, t in ipairs(P.Targets()) do
        if t.kind == "next" or t.num ~= nil then h.Problem("pins: a pin for a later step") break end
    end
    -- the minimap follow: an OnUpdate only in "follow", nothing at all while minimap pins have nothing to show
    local onUpdate = P.driver:GetScript("OnUpdate") ~= nil
    if onUpdate ~= (P.mode == "follow") then h.Problem("pins: minimap follow OnUpdate doesn't match its mode") end
    if P.mode and not (MiniOn() and #P.Targets() > 0) then h.Problem("pins: minimap follow runs with nothing to show") end
    h.Info(("pins: world %d, minimap %d, hooks %d, follow %s"):format(#P.world.used, #P.mini.used,
        ns.Hooks and ns.Hooks.Count() or 0, tostring(P.mode or "off")))
end }

local function Later() ns.Errors.Call("pins", P.Refresh) end
ns.Bus.On("Login", P, function()
    P.AttachWorld()
    ns.Bus.On("StepChanged", P, Later, "pins", 90)
    ns.Bus.On("WaypointChanged", P, Later, "pins", 90)
    ns.Bus.On("WindowToggled", P, Later, "pins", 90)
    ns.Bus.On("ZoneChanged", P, Later, "pins", 90)
    ns.Bus.On("LookChanged", P, Later, "pins", 90)   -- the tick only moves pins: a new look redraws them
    ns.Bus.On("SettingsChanged", P, function(_, key)
        if key == "mapPins" or key == "minimapPins" then Later() end
    end, "pins", 90)
    Later()
end, "pins", 85)

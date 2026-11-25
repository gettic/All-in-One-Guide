-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Map pins (v0.2 M3): the current step and the next steps with a spot, numbered, at most 12, on the
-- world map and the minimap; a manual / addon / corpse waypoint gets its own pin. Hover: what it is
-- and "click: point the arrow here"; click sets the arrow (waypoint "show").
-- World map: our own data provider (MapCanvasDataProviderMixin, the way Blizzard's own pins come and
-- go with the map) that places our own pooled frames on the map canvas; no pin template, no XML, no
-- Blizzard pin pools touched. Minimap: our own pooled frames on the Minimap frame, placed by yards from
-- the player (C_Minimap.GetViewRadius), clamped to the edge, turned when the minimap rotates. Updated
-- twice a second only while minimap pins are on and there is something to show.
-- Settings: mapPins, minimapPins (both default on).
--   ns.Pins.Targets() -> { { map, x, y, title, num, kind } }   .Refresh()   .world / .mini (pools)
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local P = { MAX = 12, TICK = 0.5 }
ns.Pins = P

local function L() return ns.L end

-- ------------------------------------------------------------------ what to show
-- The waypoint (if it isn't the step), the current step, then upcoming steps with a spot, in route order.
-- Optimizer #3: the list is kept until something it is made from changes (the window's model table, which
-- is new on every window refresh, the waypoint, its source, the window shown, the cap), so the minimap tick
-- only moves the pins. The caller only reads the list.
local cache = {}
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
    if m and m.state == "guide" and shown then
        -- numbered in route order 1..12 (look review #8: step numbers like 108 didn't fit the pin face)
        local k = 0
        for i, row in ipairs(m.rows) do
            local s = row.step
            if #out >= P.MAX then break end
            if s and s.map and s.x and s.y then
                k = k + 1
                out[#out + 1] = { map = s.map, x = s.x, y = s.y, title = row.text, num = k,
                    kind = i == 1 and "current" or "next", step = s }
            end
        end
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
    if not mini then
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

local COLOR = { current = "accent", next = "text.dim", show = "icon.goto", external = "icon.goto", corpse = "corpse" }

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
    pin.ring:SetShown(t.kind == "current" or (t.kind ~= "next" and t.num == nil))
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

-- Minimap offset in pixels (right, up) for a target, and whether it sits on the edge; nil when unknown.
function P.MiniOffset(t, pm, px, py, radius, w, h, facing, rotate)
    local c1, ax, ay = ns.Geo.World(pm, px, py)
    local c2, bx, by = ns.Geo.World(t.map, t.x, t.y)
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

-- Full draw (on Refresh or when the targets changed): acquire, look, level, place. moveOnly (the tick):
-- when the targets are the same list as last drawn, only scale and place the pins already up.
function P.DrawMini(moveOnly)
    local mm = Co.fn.Minimap
    if not mm or not MiniOn() then
        ReleaseAll(P.mini)
        P.miniList = nil
        return 0
    end
    local pm, px, py = ns.Geo.Player()
    local radius = Co.MinimapRadius()
    local w, h = mm:GetWidth() or 0, mm:GetHeight() or 0
    if not pm or not radius or w <= 0 or h <= 0 then
        ReleaseAll(P.mini)
        P.miniList = nil
        return 0
    end
    local rotate = Co.CVarBool("rotateMinimap")
    local facing = rotate and Co.Facing() or nil
    local list = P.Targets()
    if moveOnly and list == P.miniList then
        -- same targets: the pins in P.mini.used are in target order with their slot noted
        local n = 0
        for _, pin in ipairs(P.mini.used) do
            local t = pin.target
            local dx, dy, edge = nil, nil, false
            if t then dx, dy, edge = P.MiniOffset(t, pm, px, py, radius, w, h, facing, rotate) end
            if dx then
                local s = edge and 0.75 or 1
                pin:SetScale(s)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", mm, "CENTER", dx / s, dy / s)
                pin:Show()
                n = n + 1
            else
                pin:Hide()   -- off this continent now; the next full draw drops it
            end
        end
        -- a target that had no spot before may have one now (another continent -> this one): full draw
        if n == #P.mini.used then
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
            pin:SetScale(edge and 0.75 or 1)
            pin:SetFrameLevel((mm:GetFrameLevel() or 0) + 5 + (t.kind == "current" and 2 or 0))
            pin:ClearAllPoints()
            local s = edge and 0.75 or 1
            pin:SetPoint("CENTER", mm, "CENTER", dx / s, dy / s)
            pin:Show()
            n = n + 1
        end
    end
    return n
end

local function StopTicker()
    if P.ticker then P.ticker:Cancel() P.ticker = nil end
end

local function UpdateTicker()
    local want = MiniOn() and Co.fn.Minimap ~= nil and #P.Targets() > 0
    if want and not P.ticker then
        P.ticker = Co.Ticker(P.TICK, function() ns.Errors.Call("pins", P.DrawMini, true) end)
    elseif not want then
        StopTicker()
    end
end

-- ------------------------------------------------------------------ refresh
function P.Refresh()
    if not P.attached and WorldOn() then P.AttachWorld() end
    if not WorldOn() then ReleaseAll(P.world) else RefreshWorld() end
    P.DrawMini()
    UpdateTicker()
end

-- In-game self-test: the map provider is attached, the pin counts stay under the cap, the hooks are in.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "pins", fn = function(h)
    h.Count()
    if ns.Settings.Get("mapPins") and ns.Feature.IsOn("mappins") and not P.attached then
        h.Problem("pins: world map pins are on but not attached to the world map")
    end
    if #P.world.used > P.MAX or #P.mini.used > P.MAX then h.Problem("pins: more than " .. P.MAX .. " pins") end
    h.Info(("pins: world %d, minimap %d, hooks %d"):format(#P.world.used, #P.mini.used, ns.Hooks and ns.Hooks.Count() or 0))
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

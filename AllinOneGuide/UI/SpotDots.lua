-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Spawn spot dots (v0.3, plans\spawn-arrow\plan.md, tos plans\spawn-arrow\tos.md): the current kill / collect
-- step's spawn spots (Engine\Spots.lua) as dots on the world map and the minimap: open (colour spotOpen), cleared
-- (spotCleared, grey until the estimated respawn) and the spot the arrow points at (spotTarget, bigger).
-- Display only: no mouse on any dot. World map: our own data provider (a 3rd one, like UI\PathLine.lua) with one
-- holder on the canvas, counter-scaled; never redrawn in combat lockdown (drawn again when the fight ends).
-- Minimap: one holder on the Minimap (never moved / re-parented), dots placed by yards from the player, turned
-- with a rotating minimap, cut at its edge (UI\PathLine.lua's helpers). In combat the dots keep their colours and
-- target from the fight's start (no "next spot" hint in combat); only their minimap places follow you.
-- Caps: WORLD_MAX / MINI_MAX dots (the nearest; the arrow's spot always). Settings spotMap / spotMinimap.
--   ns.SpotDots.Items(max) -> list { spot, i, d, color, target } | nil   .Refresh()   .DrawWorld(map)   .DrawMini()
--   .Tick(elapsed)   .world / .mini = { used, dots }   .provider   .frozen (combat)
local _, ns = ...
local Th, Co = ns.Theme, ns.Compat
local SD = { WORLD_MAX = 60, MINI_MAX = 30, TICK = 0.1, WORLD_EVERY = 0.5, worldDraws = 0, placed = 0, ticks = 0 }
ns.SpotDots = SD

local function WorldOn()
    return ns.Settings.Get("spotMap") and ns.Feature.IsOn("mappins") and ns.Feature.IsOn("spots") and not ns.safeMode
end
local function MiniOn()
    return ns.Settings.Get("spotMinimap") and ns.Feature.IsOn("minimappins") and ns.Feature.IsOn("spots") and not ns.safeMode
end
SD.WorldOn, SD.MiniOn = WorldOn, MiniOn

local function NewSet() return { used = 0, dots = {}, made = 0 } end
SD.world, SD.mini = NewSet(), NewSet()

-- ------------------------------------------------------------------ what to show
local function ColorOf(spot, i, cur)
    if i == cur then return "spotTarget", true end
    if ns.Spots.Cleared(spot) then return "spotCleared", false end
    return "spotOpen", false
end

-- The spots to draw: nearest to the player first (route order without a position), at most `max`, the arrow's
-- spot always in. In combat the colours / target come from the fight's start (SD.frozen).
function SD.Items(max)
    local SP = ns.Spots
    if not SP then return nil end
    local spots, cur = SP.List()
    if not spots then return nil end
    local pm, px, py = ns.Geo.Player()
    local me = pm and { map = pm, x = px, y = py } or nil
    local fr = SD.frozen
    if fr then cur = fr.cur end
    local list = {}
    for i, s in ipairs(spots) do
        local d = me and SP.Yards(me, s) or nil
        local color, target
        if fr and fr.colors[s.id] then color, target = fr.colors[s.id], i == cur else color, target = ColorOf(s, i, cur) end
        list[#list + 1] = { spot = s, i = i, d = d or (1e6 + i), color = color, target = target }
    end
    table.sort(list, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.i < b.i end)
    if #list > max then
        local keep = {}
        for k = 1, max do keep[k] = list[k] end
        if cur then
            local has = false
            for _, e in ipairs(keep) do if e.i == cur then has = true end end
            if not has then
                for _, e in ipairs(list) do if e.i == cur then keep[max] = e end end
            end
        end
        list = keep
    end
    return list
end

-- Colours / target at the start of a fight (kept until it ends).
local function Freeze()
    local SP = ns.Spots
    local spots, cur
    if SP then spots, cur = SP.List() end
    if not spots then SD.frozen = { cur = nil, colors = {} } return end
    local colors = {}
    for i, s in ipairs(spots) do colors[s.id] = (ColorOf(s, i, cur)) end
    SD.frozen = { cur = cur, colors = colors }
end

-- ------------------------------------------------------------------ dots
local function Dot(set, holder, i)
    local d = set.dots[i]
    if not d then
        d = holder:CreateTexture(nil, "OVERLAY")
        Th.Glyph(d, "pin.mini")   -- our own round dot (the minimap pin's art)
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

local function WorldOf(map, x, y)
    local P = ns.Pins
    if not (P and P.WorldOf) then return nil end
    return P.WorldOf(map, x, y)
end

-- ------------------------------------------------------------------ world map
local function WorldHolder(canvas)
    local h = SD.worldHolder
    if not h then
        h = CreateFrame("Frame", nil, canvas)
        h:EnableMouse(false)
        SD.worldHolder = h
    elseif h:GetParent() ~= canvas then
        h:SetParent(canvas)
    end
    h:ClearAllPoints()
    h:SetAllPoints(canvas)
    h:SetFrameLevel((canvas:GetFrameLevel() or 0) + 185)   -- under the path line (+190) and our pins (+200)
    h:Show()
    return h
end

function SD.DrawWorld(map)
    SD.worldDraws = SD.worldDraws + 1
    local set = SD.world
    -- tos: no world map redraws in combat lockdown; drawn again when the fight ends
    if Co.InCombat() then
        SD.worldWait = true
        return set.used
    end
    SD.worldWait = nil
    if not map or not WorldOn() then Clear(set) return 0 end
    local PL = ns.PathLine
    local mapID = map.GetMapID and map:GetMapID()
    local canvas = map.GetCanvas and map:GetCanvas()
    local r = mapID and ns.Pins and ns.Pins.MapRect and ns.Pins.MapRect(mapID)
    if not (canvas and r and PL and PL.ToMap) then Clear(set) return 0 end
    local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if w <= 0 or h <= 0 then Clear(set) return 0 end
    local cs = (map.GetCanvasScale and map:GetCanvasScale()) or 1
    if type(cs) ~= "number" or cs <= 0 then cs = 1 end
    local items = SD.Items(SD.WORLD_MAX)
    if not items then Clear(set) return 0 end
    local holder = WorldHolder(canvas)
    local n = 0
    for _, e in ipairs(items) do
        local s = e.spot
        local c, wx, wy = WorldOf(s.map, s.x, s.y)
        local mx, my
        if c then mx, my = PL.ToMap(r, c, wx, wy) end
        if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 and n < SD.WORLD_MAX then
            n = n + 1
            local d = Dot(set, holder, n)
            local size = Th.Size(e.target and "spotTargetDot" or "spotDot") / cs
            d:SetSize(size, size)
            d:SetVertexColor(Th.Color(e.color))
            d:ClearAllPoints()
            d:SetPoint("CENTER", holder, "TOPLEFT", mx * w, -my * h)
            d:Show()
        end
    end
    HideFrom(set, n)
    SD.worldSig = SD.Sig(items)
    return n
end

-- One string for what the world map shows (a change redraws it).
function SD.Sig(items)
    local t = {}
    for k, e in ipairs(items or {}) do t[k] = e.spot.id .. e.color end
    return table.concat(t, ",")
end

local function Provider()
    if SD.provider then return SD.provider end
    local mixin, create = Co.fn.MapProviderMixin, Co.fn.CreateFromMixins
    if not (mixin and create) then return nil end
    local p = create(mixin)
    p.RemoveAllData = function() Clear(SD.world) end
    p.RefreshAllData = function(self) ns.Errors.Call("spots", SD.DrawWorld, self:GetMap()) end
    p.OnMapChanged = function(self) self:RefreshAllData() end
    p.OnCanvasScaleChanged = function(self) self:RefreshAllData() end
    SD.provider = p
    return p
end

function SD.AttachWorld()
    local wm = Co.fn.WorldMapFrame or Co.Resolve("WorldMapFrame")
    if SD.attached or type(wm) ~= "table" or type(wm.AddDataProvider) ~= "function" then return false end
    local p = Provider()
    if not p then return false end
    wm:AddDataProvider(p)
    SD.attached = wm
    return true
end

local function MapOpen()
    local wm = SD.attached
    return wm ~= nil and wm.IsShown ~= nil and wm:IsShown() == true
end

local function RedrawWorld()
    if MapOpen() and SD.provider then SD.provider:RefreshAllData() else Clear(SD.world) end
end

-- ------------------------------------------------------------------ minimap
local function MiniHolder(mm)
    local h = SD.miniHolder
    if not h then
        h = CreateFrame("Frame", nil, mm)
        h:EnableMouse(false)
        h:SetAllPoints(mm)
        SD.miniHolder = h
    end
    h:SetFrameLevel((mm:GetFrameLevel() or 0) + 3)   -- under the path line (+4) and the minimap pins (+5)
    h:Show()
    return h
end

function SD.DrawMini()
    SD.placed = SD.placed + 1
    local set = SD.mini
    local mm, PL = Co.fn.Minimap, ns.PathLine
    if not mm or not MiniOn() or not PL or (mm.IsVisible and not mm:IsVisible()) then Clear(set) return 0 end
    local pm, px, py = ns.Geo.Player()
    local radius, w, h = Co.MinimapRadius(), mm:GetWidth() or 0, mm:GetHeight() or 0
    local rotate = Co.CVarBool("rotateMinimap") == true
    local facing = rotate and Co.Facing() or nil
    if not pm or type(radius) ~= "number" or radius <= 0 or w <= 0 or h <= 0 or (rotate and type(facing) ~= "number") then
        Clear(set)
        return 0
    end
    local c0, ox, oy = WorldOf(pm, px, py)
    local items = c0 and SD.Items(SD.MINI_MAX)
    if not items then Clear(set) return 0 end
    local holder = MiniHolder(mm)
    local quarters = PL.Quarters()
    local cosf, sinf = 1, 0
    if rotate then cosf, sinf = math.cos(facing), math.sin(facing) end
    local n = 0
    for _, e in ipairs(items) do
        local s = e.spot
        local c, wx, wy = WorldOf(s.map, s.x, s.y)
        if c and c == c0 then
            local east, north = -(wy - oy), wx - ox   -- world y points west
            if rotate then east, north = east * cosf + north * sinf, -east * sinf + north * cosf end
            local size = Th.Size("spotMiniDot") * (e.target and 1.5 or 1)
            local hw, hh = w / 2 - size / 2, h / 2 - size / 2
            local x, y = east / radius * (w / 2), north / radius * (h / 2)
            if PL.Inside(x, y, hw, hh, quarters) and n < SD.MINI_MAX then
                n = n + 1
                local d = Dot(set, holder, n)
                d:SetSize(size, size)
                d:SetVertexColor(Th.Color(e.color))
                d:ClearAllPoints()
                d:SetPoint("CENTER", mm, "CENTER", x, y)
                d:Show()
            end
        end
    end
    HideFrom(set, n)
    return n
end

-- ------------------------------------------------------------------ keeping it current
-- Something to show: the arrow's step has spots, and the minimap dots on or the world map open with its dots on.
function SD.Wanted()
    local SP = ns.Spots
    if not (SP and SP.List()) then return false end
    if not (ns.UI and ns.UI.IsShown and ns.UI.IsShown()) then return false end
    return (MiniOn() and Co.fn.Minimap ~= nil) or (WorldOn() and MapOpen())
end

local driver = CreateFrame("Frame")
SD.driver = driver
local since, sinceWorld = 0, 0

function SD.Tick(elapsed)
    since, sinceWorld = since + (tonumber(elapsed) or 0), sinceWorld + (tonumber(elapsed) or 0)
    if since < SD.TICK then return false end
    since = 0
    SD.ticks = SD.ticks + 1
    if not SD.Wanted() then SD.Refresh() return false end
    SD.DrawMini()
    if MapOpen() and WorldOn() and sinceWorld >= SD.WORLD_EVERY and not Co.InCombat() then
        sinceWorld = 0
        if SD.Sig(SD.Items(SD.WORLD_MAX)) ~= SD.worldSig then RedrawWorld() end
    end
    return true
end

local function OnFrame(_, elapsed) ns.Errors.Call("spots", SD.Tick, elapsed) end

function SD.Refresh()
    if not SD.attached and WorldOn() then SD.AttachWorld() end
    local want = SD.Wanted()
    if want then
        if not SD.running then
            SD.running = true
            driver:SetScript("OnUpdate", OnFrame)
        end
        since = SD.TICK
        SD.DrawMini()
        if WorldOn() then RedrawWorld() else Clear(SD.world) end
    else
        if SD.running then
            SD.running = nil
            driver:SetScript("OnUpdate", nil)
        end
        Clear(SD.mini)
        if not Co.InCombat() then Clear(SD.world) end
    end
end

-- In-game self-test: caps kept, attached when on, no driver with nothing to show.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "spot dots", fn = function(h)
    h.Count()
    if SD.world.used > SD.WORLD_MAX or SD.mini.used > SD.MINI_MAX then h.Problem("spot dots: more dots than the cap") end
    if WorldOn() and not SD.attached then h.Problem("spot dots: on but not attached to the world map") end
    if SD.running and not SD.Wanted() then h.Problem("spot dots: running with nothing to show") end
    h.Info(("spot dots: world %d, minimap %d"):format(SD.world.used, SD.mini.used))
end }

local function Later() ns.Errors.Call("spots", SD.Refresh) end
ns.Bus.On("Login", SD, function()
    SD.AttachWorld()
    for _, ev in ipairs({ "StepChanged", "WaypointChanged", "WindowToggled", "ZoneChanged", "LookChanged", "HuntChanged",
        "WorldMapShown", "WorldMapHidden" }) do
        ns.Bus.On(ev, SD, Later, "spots", 96)
    end
    ns.Bus.On("CombatStarted", SD, function() Freeze() end, "spots", 96)
    ns.Bus.On("CombatEnded", SD, function()
        SD.frozen = nil
        SD.worldSig = nil
        Later()
    end, "spots", 96)
    ns.Bus.On("SettingsChanged", SD, function(_, key)
        if key == "spotMap" or key == "spotMinimap" or key == "huntPath" or key == "huntMode" or key == "arrow" then Later() end
    end, "spots", 96)
    if Co.InCombat() then Freeze() end
    Later()
end, "spots", 87)

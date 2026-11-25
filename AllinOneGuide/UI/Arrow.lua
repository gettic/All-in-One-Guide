-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The waypoint arrow: points at the current step's spot. Rotation = bearing to the spot - the
-- player's facing (SetRotation; the 8-argument SetTexCoord when it's missing). Colour runs ahead >
-- side > behind; distance in whole yards; the arrived ring inside the step's radius.
-- Hidden when there's no spot, no facing or no position. OnUpdate runs only while it's shown; the
-- position is read every 0.25 s, the facing every frame. While a spot exists but facing / position
-- can't be read (and their features are on), a 1 s retry ticker checks again; nothing runs otherwise.
--   ns.Arrow.SetTarget(target or nil, source), .Update(), .frame   (targets come from Engine\Waypoint.lua)
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local A = { POLL = 0.25, RETRY = 1, elapsed = 0, onUpdates = 0 }
ns.Arrow = A

local PI, TWO_PI = math.pi, 2 * math.pi

-- Hidden: no target, turned off, window closed, "hide until the next step", while the world map is open,
-- on a flight (taxi). Never hidden for being dead: then the corpse is the target.
function A.HiddenWhy()
    if A.hiddenFor and A.target == A.hiddenFor then return "hidden" end
    if not (ns.Settings.Get("arrow") and not ns.safeMode and ns.UI.IsShown()) then return "off" end
    if ns.Hooks and ns.Hooks.mapOpen then return "map" end
    if A.source ~= "corpse" and Co.OnTaxi() then return "taxi" end
    return nil
end
local function Wanted() return A.HiddenWhy() == nil end

-- Steps for the menu: scale and opacity rows step through these values.
A.SCALES, A.ALPHAS = { 0.8, 1, 1.25, 1.5 }, { 1, 0.8, 0.6, 0.4 }
local function NextIn(list, cur)
    for i, v in ipairs(list) do if math.abs(v - cur) < 0.01 then return list[i % #list + 1] end end
    return list[1]
end

-- The next step with a spot after the current one (for "point at the next step").
local function NextSpot()
    local m = ns.UI.model
    if not (m and m.rows) then return nil end
    for i = 2, #m.rows do
        local s = m.rows[i].step
        if s and s.map and s.x and s.y then return s, m.rows[i].text end
    end
    return nil
end

-- The arrow's right-click menu (v0.2 M3): skip, hide until the next step, clear, point at the next step,
-- copy /way, lock, size, opacity, click-through, walk time, arrival sound.
function A.MenuItems()
    local L, S = ns.L, ns.Settings
    local items = {}
    if A.source == "step" or A.source == nil then
        items[#items + 1] = { text = L.MENU_STEP_SKIP, fn = function() ns.Engine.Skip() end }
    end
    items[#items + 1] = { text = L.MENU_ARROW_HIDE, fn = function()
        A.hiddenFor = A.target
        A.Update()
    end }
    if ns.Waypoint and (ns.Waypoint.targets.show or ns.Waypoint.targets.external) then
        items[#items + 1] = { text = L.MENU_WAY_CLEAR, fn = function() ns.Waypoint.ClearManual() end }
    end
    local nxt, nxtText = NextSpot()
    if nxt and ns.Waypoint then
        items[#items + 1] = { text = L.MENU_ARROW_NEXT, fn = function()
            ns.Waypoint.Set("show", { map = nxt.map, x = nxt.x, y = nxt.y, r = nxt.r, title = nxtText })
        end }
    end
    if A.target and ns.Waypoint then
        items[#items + 1] = { text = L.MENU_STEP_WAY, fn = function()
            local line = ns.Waypoint.WayLine(A.target)
            if line and ns.Popups.Copy then ns.Popups.Copy(L.COPY_WAY, line) end
        end }
    end
    -- smart arrow: on / off, and "point straight" for this one target while it leads through a door first
    items[#items + 1] = { text = L.MENU_ARROW_SMART, checked = S.Get("smartArrow"),
        fn = function() S.Set("smartArrow", not S.Get("smartArrow")) end }
    if A.via and A.target and ns.SmartRoute then
        local t = A.target
        items[#items + 1] = { text = L.MENU_ARROW_STRAIGHT, fn = function()
            ns.SmartRoute.Straight(t)
            A.Update()
        end }
    end
    items[#items + 1] = { text = L.MENU_LOCK, checked = S.Get("locked"), fn = function() S.Set("locked", not S.Get("locked")) end }
    items[#items + 1] = { text = ns.U.Fill(L.MENU_ARROW_SCALE, { n = math.floor(S.Get("arrowScale") * 100 + 0.5) }),
        fn = function() S.Set("arrowScale", NextIn(A.SCALES, S.Get("arrowScale"))) end }
    items[#items + 1] = { text = ns.U.Fill(L.MENU_ARROW_ALPHA, { n = math.floor(S.Get("arrowAlpha") * 100 + 0.5) }),
        fn = function() S.Set("arrowAlpha", NextIn(A.ALPHAS, S.Get("arrowAlpha"))) end }
    items[#items + 1] = { text = L.MENU_ARROW_CLICK, checked = S.Get("arrowClickThrough"),
        fn = function() S.Set("arrowClickThrough", not S.Get("arrowClickThrough")) end }
    items[#items + 1] = { text = L.MENU_ARROW_TIME, checked = S.Get("arrowUnit") == "time",
        fn = function() S.Set("arrowUnit", S.Get("arrowUnit") == "time" and "yards" or "time") end }
    items[#items + 1] = { text = L.MENU_ARROW_SOUND, checked = S.Get("arrivalSound"),
        fn = function() S.Set("arrivalSound", not S.Get("arrivalSound")) end }
    return items
end

-- Distance text: whole yards, or the walk time at run speed (7 yards a second) as "m:ss".
A.RUN_SPEED = 7
function A.DistanceText(yards)
    if ns.Settings.Get("arrowUnit") == "time" then
        return ns.U.Fill(ns.L.WALK_TIME, { t = ns.Locale.Duration(yards / A.RUN_SPEED) })
    end
    return ns.U.Fill(ns.L.YARDS, { n = math.floor(yards + 0.5) })
end

-- Look settings: size, opacity (texture / text colour alpha: the UI never uses SetAlpha), click-through.
function A.ApplyLook()
    local f = A.frame
    if not f then return end
    local S = ns.Settings
    f:SetScale(S.Get("arrowScale"))
    f:EnableMouse(not S.Get("arrowClickThrough"))
    if f.EnableMouseWheel then f:EnableMouseWheel(not S.Get("arrowClickThrough")) end
    A.alpha = S.Get("arrowAlpha")
    A.dirty = true   -- the next frame redraws texts and colours with the new look
    local r, g, b = Th.Color("arrived")
    A.arrived:SetVertexColor(r, g, b, A.alpha)
end

-- Hover: what it points at.
function A.Tip(self)
    local t = A.target
    if not t then return end
    local lines = {}
    lines[#lines + 1] = ("%.1f, %.1f"):format(t.x * 100, t.y * 100)
    local zone = Co.MapName(t.map)
    if zone then lines[1] = zone .. " " .. lines[1] end
    local title = t.title
    if A.source == "step" then
        local m = ns.UI.model
        local text = m and m.rows and m.rows[1] and m.rows[1].text
        if m and text then title = ns.U.Fill(ns.L.ARROW_STEP, { n = m.index or 1, text = text }) end
    end
    -- smart arrow: the way it leads ("Through the abbey door > Goal")
    local way = A.via and ns.SmartRoute and ns.SmartRoute.RouteText()
    if way then lines[#lines + 1] = ns.U.Fill(ns.L.VIA_ROUTE, { route = way }) end
    K.Tooltip(self, title or lines[1], title and lines or nil)
end

-- ------------------------------------------------------------------ position (saved only when moved)
local function SavedPos()
    local m = ns.DB.char and type(ns.DB.char.modules) == "table" and ns.DB.char.modules.arrow
    if type(m) ~= "table" or type(m.x) ~= "number" or type(m.y) ~= "number" then return nil end
    return m
end

local function ApplyPos()
    local f, parent = A.frame, Co.UIParent()
    f:ClearAllPoints()
    local m = SavedPos()
    if m then f:SetPoint("CENTER", parent, "BOTTOMLEFT", m.x, m.y)
    else f:SetPoint("CENTER", parent, "CENTER", 0, 220) end
end
A.ApplyPos = ApplyPos

local function SavePos()
    if ns.safeMode or ns.DB.readOnly.char then return end
    local x, y = A.frame:GetCenter()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local m = ns.DB.Module("arrow", "char", 1)
    m.x, m.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

function A.ResetPos()
    local m = SavedPos()
    if m and not ns.safeMode and not ns.DB.readOnly.char then m.x, m.y = nil, nil end
    if A.frame then ApplyPos() end
end

-- ------------------------------------------------------------------ building
local function Build()
    local size = Th.Size("arrow")
    local f = CreateFrame("Frame", nil, Co.UIParent())
    A.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetSize(size, size)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- locked: Alt+drag still moves it (v0.2 M3)
    f:SetScript("OnDragStart", function(self)
        if not ns.Settings.Get("locked") or Co.Modifier("alt") then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePos() end)
    -- v0.2 M3: right-click menu, hover, mouse wheel = size
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.Errors.Call("ui", function() ns.Menu.Open(self, A.MenuItems()) end) end
    end)
    f:SetScript("OnEnter", function(self) ns.Errors.Call("ui", A.Tip, self) end)
    f:SetScript("OnLeave", K.HideTooltip)
    f:SetScript("OnMouseWheel", function(_, delta)
        if ns.Settings.Get("locked") then return end
        local d = ns.Settings.byKey.arrowScale
        ns.Settings.Set("arrowScale", ns.U.Clamp(math.floor((ns.Settings.Get("arrowScale") + (delta > 0 and 0.1 or -0.1)) * 10 + 0.5) / 10, d.min, d.max))
    end)
    A.tex = f:CreateTexture(nil, "ARTWORK")
    A.tex:SetSize(size, size)
    A.tex:SetPoint("CENTER")
    Th.Glyph(A.tex, "arrow")
    A.arrived = f:CreateTexture(nil, "ARTWORK", nil, 1)
    A.arrived:SetSize(size, size)
    A.arrived:SetPoint("CENTER")
    Th.Glyph(A.arrived, "arrived")
    A.arrived:SetVertexColor(Th.Color("arrived"))
    A.arrived:Hide()
    A.dist = K.Text(f, "arrow", "white", "CENTER")
    A.dist:SetPoint("TOP", f, "BOTTOM", 0, -2)
    -- corpse marker under the distance (v0.2 art)
    A.corpse = f:CreateTexture(nil, "ARTWORK")
    A.corpse:SetSize(20, 20)
    A.corpse:SetPoint("TOP", A.dist, "BOTTOM", 0, -2)
    Th.Glyph(A.corpse, "arrow.corpse")
    A.corpse:SetVertexColor(Th.Color("corpse"))
    A.corpse:Hide()
    -- "Go to <zone>" when the spot is in another zone of the same continent
    A.zone = K.Text(f, "goal", "zone", "CENTER")
    A.zone:SetPoint("TOP", A.dist, "BOTTOM", 0, -2)
    -- smart arrow: the way to take ("Through the abbey door") and the goal's distance along the route
    A.viaText = K.Text(f, "goal", "viaText", "CENTER")
    A.viaText:SetPoint("TOP", A.dist, "BOTTOM", 0, -2)
    A.goalLine = K.Text(f, "goal", "text.dim", "CENTER")
    A.goalLine:SetPoint("TOP", A.viaText, "BOTTOM", 0, -1)
    ApplyPos()
    A.ApplyLook()
    f:Hide()
end

-- ------------------------------------------------------------------ maths
-- Angle to the range -pi..pi.
local function Norm(a)
    a = a % TWO_PI
    if a > PI then a = a - TWO_PI end
    return a
end
A.Norm = Norm

local function Lerp(k1, k2, t)
    local r1, g1, b1 = Th.Color(k1)
    local r2, g2, b2 = Th.Color(k2)
    return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
end

-- Colour for an angle off the facing (0 = straight ahead, pi = behind).
function A.ColorFor(rot)
    local t = math.abs(Norm(rot)) / PI
    if t <= 0.5 then return Lerp("arrowAhead", "arrowSide", t * 2) end
    return Lerp("arrowSide", "arrowBehind", (t - 0.5) * 2)
end

-- 8-argument texture coordinates that rotate the texture by `rot` around its centre.
function A.RotCoords(rot)
    local s, c = math.sin(rot), math.cos(rot)
    local function P(x, y) return 0.5 + x * c - y * s, 0.5 + x * s + y * c end
    local ulx, uly = P(-0.5, -0.5)
    local llx, lly = P(-0.5, 0.5)
    local urx, ury = P(0.5, -0.5)
    local lrx, lry = P(0.5, 0.5)
    return ulx, uly, llx, lly, urx, ury, lrx, lry
end

local function Rotate(rot)
    if A.tex.SetRotation then A.tex:SetRotation(rot)
    else A.tex:SetTexCoord(A.RotCoords(rot)) end
end

-- ------------------------------------------------------------------ updating
local function StopRetry()
    if A.retry then
        A.retry:Cancel()
        A.retry = nil
    end
end

local function StartRetry()
    if A.retry then return end
    -- only when there's a chance: the features are on (an API that is missing never comes back)
    if not (ns.Feature.IsOn("position") and ns.Feature.IsOn("worldpos") and ns.Feature.IsOn("facing")) then return end
    A.retry = Co.Ticker(A.RETRY, function() ns.Errors.Call("ui", A.Update) end)
end

local function SetShown(show)
    local f = A.frame
    if show then
        if not f:IsShown() then
            A.elapsed = A.POLL   -- read the position on the first frame
            f:SetScript("OnUpdate", A.OnUpdate)
            f:Show()
        end
    elseif f:IsShown() then
        f:SetScript("OnUpdate", nil)
        f:Hide()
    end
end

-- The arrow pulse (smart arrow: a door / gate point passed): the arrow itself dips to alpha.arrowPulseLow and
-- back, once, over motion.arrowPulse (0.3 s). Nothing with reduced motion, with the smart arrow off or while it
-- points straight. A.pulses counts the passes (also when nothing animates).
function A.Pulse()
    A.pulses = (A.pulses or 0) + 1
    local d = Th.Motion("arrowPulse")
    local t, SR = A.tex, ns.SmartRoute
    if d <= 0 or not (t and t.CreateAnimationGroup) then return false end
    if not (SR and SR.On()) or (A.target and SR.straightFor == A.target) then return false end
    if not A.pulseAnim then
        local ag = t:CreateAnimationGroup()
        local down, up = ag:CreateAnimation("Alpha"), ag:CreateAnimation("Alpha")
        down:SetOrder(1)
        up:SetOrder(2)
        A.pulseAnim, A.pulseDown, A.pulseUp = ag, down, up
    end
    local low = Th.Alpha("arrowPulseLow", 0.35)
    A.pulseDown:SetFromAlpha(1)
    A.pulseDown:SetToAlpha(low)
    A.pulseDown:SetDuration(d / 2)
    A.pulseUp:SetFromAlpha(low)
    A.pulseUp:SetToAlpha(1)
    A.pulseUp:SetDuration(d / 2)
    A.pulseAnim:Stop()
    A.pulseAnim:Play()
    return true
end

-- Reads the position and works out bearing + yards. false when it can't.
-- Smart arrow: Engine\SmartRoute.lua may hand back a door / gate / path point to aim at first (A.via); on any
-- trouble (error, a point that can't be measured) the arrow points straight at the target as before.
local function ReadPosition()
    local t = A.target
    local pm, px, py = ns.Geo.Player()
    if not pm then return false end
    local aim, via = t, nil
    if ns.SmartRoute then
        local ok, a, v = ns.Errors.Call("smartarrow", ns.SmartRoute.Aim, t, pm, px, py)
        if ok and a and v then aim, via = a, v end
    end
    local bearing, yards = ns.Geo.Bearing(pm, px, py, aim.map, aim.x, aim.y)
    if not bearing and via then
        aim, via = t, nil
        bearing, yards = ns.Geo.Bearing(pm, px, py, t.map, t.x, t.y)
    end
    if not bearing then return false end
    -- passed a via point on the way to the same target: the route moved on, or it was planned again because you
    -- walked through into another room (not after going off the route): pulse the arrow
    local old, st = A.via, ns.SmartRoute and ns.SmartRoute.state
    if old and st and A.viaTarget == t and (not via or via.point ~= old.point) and ns.SmartRoute.On()
        and ns.SmartRoute.straightFor ~= t then
        local moved = st.route == old.route and via and (via.index or 0) > (old.index or 0)
        local through = st.route ~= old.route and st.why == "room"
        local last = st.route == old.route and not via
        if moved or through or last then ns.Errors.Call("ui", A.Pulse) end
    end
    A.viaTarget = via and t or nil
    A.bearing, A.yards, A.playerMap, A.aim, A.via = bearing, yards, pm, aim, via
    A.dirty = true   -- yards / map can only change here (the 0.25 s poll)
    return true
end

-- Draws with the last bearing and the facing now. false when the facing can't be read.
-- Optimizer #2: between position reads (A.dirty false) only the rotation and its colour change; texts, zone
-- line, anchors, shown state and the arrival sound wait for the next read.
local function Draw()
    local facing = Co.Facing()
    if type(facing) ~= "number" or not A.bearing then return false end
    local r = A.target.r or ns.Format.DEFAULT_RADIUS
    local via = A.via
    local here = not via and r > 0 and A.yards <= r   -- a via point is never "there": the goal is
    local alpha = A.alpha or 1
    if not A.dirty then
        if not here then
            local rot = Norm(A.bearing - facing)
            Rotate(rot)
            local cr, cg, cb = A.ColorFor(rot)
            if via then cr, cg, cb = Th.Color("arrowVia") end
            if A.source == "corpse" then cr, cg, cb = Th.Color("corpse") end
            A.tex:SetVertexColor(cr, cg, cb, alpha)
        end
        A.rotation = A.bearing - facing
        return true
    end
    A.dirty = false
    A.tex:SetShown(not here)
    A.arrived:SetShown(here)
    local corpse = A.source == "corpse"
    A.corpse:SetShown(corpse)
    if here then
        A.dist:SetText(ns.L.ARRIVED)
        local tr, tg, tb = Th.Color("arrivedText")
        A.dist:SetTextColor(tr, tg, tb, alpha)
        -- the arrival sound (off by default; once per target)
        if not A.wasHere and ns.Settings.Get("arrivalSound") then Co.PlaySound(Co.SoundKit("MAP_PING")) end
    else
        local rot = Norm(A.bearing - facing)
        Rotate(rot)
        local cr, cg, cb = A.ColorFor(rot)
        if via then cr, cg, cb = Th.Color("arrowVia") end
        if corpse then cr, cg, cb = Th.Color("corpse") end
        A.tex:SetVertexColor(cr, cg, cb, alpha)
        A.dist:SetText(A.DistanceText(A.yards))
        local dr, dg, db = Th.Color("arrowText")
        A.dist:SetTextColor(dr, dg, db, alpha)
    end
    A.wasHere = here
    -- smart arrow: "Through the abbey door" and "Goal: 214 yd" (along the route) while it leads to a point first
    local below = corpse and A.corpse or A.dist
    A.viaText:SetShown(via ~= nil)
    A.goalLine:SetShown(via ~= nil and via.goalYards ~= nil)
    if via then
        A.viaText:SetText(via.hint or "")
        local vr, vg, vb = Th.Color("viaText")
        A.viaText:SetTextColor(vr, vg, vb, alpha)
        A.viaText:ClearAllPoints()
        A.viaText:SetPoint("TOP", below, "BOTTOM", 0, -2)
        below = A.viaText
        if via.goalYards then
            A.goalLine:SetText(ns.U.Fill(ns.L.VIA_GOAL_LINE, { d = A.DistanceText(via.goalYards) }))
            local gr, gg, gb = Th.Color("text.dim")
            A.goalLine:SetTextColor(gr, gg, gb, alpha)
            below = A.goalLine
        end
    end
    -- another zone (same continent): "Go to <zone>"
    local zoneText = ""
    if A.playerMap and A.playerMap ~= A.target.map and not here then
        local name = Co.MapName(A.target.map)
        if name then zoneText = ns.U.Fill(ns.L.WRONG_ZONE, { zone = name }) end
    end
    A.zone:SetText(zoneText)
    A.zone:ClearAllPoints()
    A.zone:SetPoint("TOP", below, "BOTTOM", 0, -2)
    A.rotation = A.bearing - facing
    return true
end

function A.OnUpdate(_, elapsed)
    A.onUpdates = A.onUpdates + 1
    if not A.target then return SetShown(false) end
    A.elapsed = A.elapsed + (elapsed or 0)
    if A.elapsed >= A.POLL then
        A.elapsed = 0
        if not ReadPosition() then
            SetShown(false)
            StartRetry()
            return
        end
        if ns.UI.rows[1] and A.source == "step" then ns.Rows.SetDistance(ns.UI.rows[1], ns.UI.DistText(A.target)) end
    end
    if not Draw() then
        SetShown(false)
        StartRetry()
    end
end

-- Checks whether the arrow can show now (on a new target, or from the retry ticker).
function A.Update()
    if not A.frame then return end
    if not A.target or not Wanted() then
        StopRetry()
        SetShown(false)
        return
    end
    if ReadPosition() and Draw() then
        StopRetry()
        SetShown(true)
    else
        SetShown(false)
        StartRetry()
    end
end

-- source: the waypoint arbiter's source ("step", "show", "external", "corpse"); nil = a step.
function A.SetTarget(step, source)
    if step and not (step.map and step.x and step.y) then step = nil end
    if step ~= A.target then A.hiddenFor, A.wasHere = nil, nil end   -- "hide until the next step" ends with the target
    A.target, A.source = step, step and (source or "step") or nil
    A.bearing, A.yards, A.aim, A.via, A.viaTarget = nil, nil, nil, nil, nil
    if step and not A.frame then Build() end
    A.Update()
end

ns.Bus.On("SettingsChanged", A, function(_, key)
    if key == "arrow" then A.Update()
    elseif key == "arrowScale" or key == "arrowAlpha" or key == "arrowClickThrough" then A.ApplyLook() A.Update()
    elseif key == "arrowUnit" or key == "smartArrow" then A.Update() end
end, "ui", 75)
ns.Bus.On("FeatureChanged", A, function() A.Update() end, "ui", 75)
-- v0.2 M4: high contrast / colour-blind / font size (Theme\Overlay.lua)
ns.Bus.On("LookChanged", A, function() A.ApplyLook() A.Update() end, "ui", 75)
-- v0.2 M3: hide while the world map is open and on a flight
ns.Bus.On("WorldMapShown", A, function() A.Update() end, "ui", 75)
ns.Bus.On("WorldMapHidden", A, function() A.Update() end, "ui", 75)
ns.Events.On("PLAYER_CONTROL_LOST", A, function() A.Update() end, "ui")
ns.Events.On("PLAYER_CONTROL_GAINED", A, function() A.Update() end, "ui")

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The waypoint arrow: points at the current step's spot. Rotation = bearing to the spot - the
-- player's facing (SetRotation; the 8-argument SetTexCoord when it's missing). Colour runs ahead >
-- side > behind; distance in whole yards; the arrived ring inside the step's radius.
-- Hidden when there's no spot, no facing or no position. OnUpdate runs only while it's shown; the
-- position is read every 0.25 s, the facing every frame. While a spot exists but facing / position
-- can't be read (and their features are on), a 1 s retry ticker checks again; nothing runs otherwise.
--   ns.Arrow.SetTarget(step or nil), .Update(), .frame
local _, ns = ...
local Th, K, Co = ns.Theme, ns.UIKit, ns.Compat
local A = { POLL = 0.25, RETRY = 1, elapsed = 0, onUpdates = 0 }
ns.Arrow = A

local PI, TWO_PI = math.pi, 2 * math.pi

local function Wanted()
    return ns.Settings.Get("arrow") and not ns.safeMode and ns.UI.IsShown()
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
    f:SetScript("OnDragStart", function(self) if not ns.Settings.Get("locked") then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePos() end)
    A.tex = f:CreateTexture(nil, "ARTWORK")
    A.tex:SetAllPoints()
    Th.Glyph(A.tex, "arrow")
    A.arrived = f:CreateTexture(nil, "ARTWORK", nil, 1)
    A.arrived:SetAllPoints()
    Th.Glyph(A.arrived, "arrived")
    A.arrived:SetVertexColor(Th.Color("arrived"))
    A.arrived:Hide()
    A.dist = K.Text(f, "arrow", "white", "CENTER")
    A.dist:SetPoint("TOP", f, "BOTTOM", 0, -2)
    ApplyPos()
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

-- Reads the position and works out bearing + yards. false when it can't.
local function ReadPosition()
    local t = A.target
    local pm, px, py = ns.Geo.Player()
    if not pm then return false end
    local bearing, yards = ns.Geo.Bearing(pm, px, py, t.map, t.x, t.y)
    if not bearing then return false end
    A.bearing, A.yards = bearing, yards
    return true
end

-- Draws with the last bearing and the facing now. false when the facing can't be read.
local function Draw()
    local facing = Co.Facing()
    if type(facing) ~= "number" or not A.bearing then return false end
    local r = A.target.r or ns.Format.DEFAULT_RADIUS
    local here = r > 0 and A.yards <= r
    A.tex:SetShown(not here)
    A.arrived:SetShown(here)
    if here then
        A.dist:SetText(ns.L.ARRIVED)
        K.Color(A.dist, "arrivedText")
    else
        local rot = Norm(A.bearing - facing)
        Rotate(rot)
        A.tex:SetVertexColor(A.ColorFor(rot))
        A.dist:SetText(ns.U.Fill(ns.L.YARDS, { n = math.floor(A.yards + 0.5) }))
        K.Color(A.dist, "white")
    end
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
        if ns.UI.rows[1] then ns.Rows.SetDistance(ns.UI.rows[1], ns.UI.DistText(A.target)) end
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

function A.SetTarget(step)
    if step and not (step.map and step.x and step.y) then step = nil end
    A.target = step
    A.bearing, A.yards = nil, nil
    if step and not A.frame then Build() end
    A.Update()
end

ns.Bus.On("SettingsChanged", A, function(_, key) if key == "arrow" then A.Update() end end, "ui", 75)
ns.Bus.On("FeatureChanged", A, function() A.Update() end, "ui", 75)

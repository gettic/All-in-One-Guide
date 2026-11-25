-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The public API for other addons (first user: Gear Set). It sits on the one code global:
--   local API = AllinOneGuide and AllinOneGuide.API
--   if API and API.version >= 1 and API.Has("callbacks") then
--       local handle = API.Register("MyAddon", { StepChanged = fn, GuideOpened = fn, Ready = fn })
--   end
-- Rules (G-B21, T123-T125, T131):
--   * version number + capability checks (API.Has); new things only add capabilities
--   * every call into us and every callback out of us runs under pcall; an owner whose callback errors
--     3 times is cut off (debug line, never a chat line)
--   * owner handles: Register returns a handle, Unregister takes it; one owner name can't see another's
--   * copies out: everything returned is a fresh plain table (changing it changes nothing here)
--   * throttle: at most 20 calls per second per handle (or per "anonymous" caller); extra calls get nil
--   * reads before PLAYER_LOGIN return nil, "not ready" (other addons connect at PLAYER_LOGIN)
--   * deprecated names keep working through a table (old -> new) and log once per name
-- Nothing here acts in the game: it only reads the guide's state and sends notices.
local _, ns = ...
local API = { version = 1 }
AllinOneGuide.API = API
ns.API = API

local THROTTLE = 20       -- calls per second
local MAX_ERRORS = 3
local caps = { callbacks = true, state = true }
local owners = {}         -- handle -> { name, cbs, errors, off }
local buckets = {}        -- handle or "anon" -> { t = second, n = calls }
local seenGuides = {}
local nextHandle = 0
local DEPRECATED = {}     -- old name -> new name (none yet)
API.ready = false

local function Debug(fmt, ...) if ns.Errors then ns.Errors.Debug("api: " .. fmt, ...) end end
local function Now() return ns.Compat.Now() end

-- capabilities: what this version offers (Gear Set checks before using a call)
function API.Has(cap) return caps[cap] == true end
function API.Capabilities()
    local out = {}
    for k in pairs(caps) do out[#out + 1] = k end
    table.sort(out)
    return out
end
-- used by later parts of the addon (e.g. M3 adds "pointTo")
function ns.APIAddCapability(cap) caps[cap] = true end

local function Throttled(handle)
    local key = handle or "anon"
    local b = buckets[key]
    local sec = math.floor(Now())
    if not b or b.t ~= sec then
        b = { t = sec, n = 0 }
        buckets[key] = b
    end
    b.n = b.n + 1
    return b.n > THROTTLE
end

-- Wraps a public function: not ready / throttled / errors give nil + a reason, never an error.
local function Public(name, fn, needsReady)
    API[name] = function(...)
        local handle = ...
        if type(handle) ~= "string" or not owners[handle] then handle = nil end
        if Throttled(handle) then return nil, "throttled" end
        if needsReady and not API.ready then return nil, "not ready" end
        local ok, a, b = pcall(fn, ...)
        if not ok then
            Debug("%s failed: %s", name, tostring(a))
            return nil, "error"
        end
        return a, b
    end
end

-- ------------------------------------------------------------------ owners and callbacks
Public("Register", function(owner, callbacks)
    if type(owner) ~= "string" or owner == "" or #owner > 48 then return nil, "bad owner" end
    if callbacks ~= nil and type(callbacks) ~= "table" then return nil, "bad callbacks" end
    nextHandle = nextHandle + 1
    local handle = "aog-h" .. nextHandle
    local cbs = {}
    for _, ev in ipairs({ "StepChanged", "GuideOpened", "Ready" }) do
        local f = callbacks and callbacks[ev]
        if type(f) == "function" then cbs[ev] = f end
    end
    owners[handle] = { name = owner, cbs = cbs, errors = 0 }
    Debug("registered %s as %s", owner, handle)
    return handle
end)

Public("Unregister", function(handle)
    if type(handle) ~= "string" or not owners[handle] then return false end
    owners[handle] = nil
    buckets[handle] = nil
    return true
end)

Public("IsReady", function() return API.ready end)

-- ------------------------------------------------------------------ pointing the arrow (v0.2, capability pointTo)
-- PointTo(handle, mapID, x, y, title): x / y as 0-1 map fractions. Only registered owners; the arrow shows it
-- above the step (below the corpse) until ClearPoint, the player's "clear", or another PointTo.
caps.pointTo = true
-- a map fraction: a number from 0 to 1
local function IsFraction(v) return ns.U.IsNum(v) and v >= 0 and v <= 1 end
local function GoodPoint(mapID, x, y, title)
    local titleOk = title == nil or type(title) == "string"
    return ns.U.IsNum(mapID) and IsFraction(x) and IsFraction(y) and titleOk
end
Public("PointTo", function(handle, mapID, x, y, title)
    if type(handle) ~= "string" or not owners[handle] then return false, "not registered" end
    if not GoodPoint(mapID, x, y, title) then return false, "bad args" end
    local WP = ns.Waypoint
    if not WP then return false, "no arrow" end
    return WP.Set("external", { map = mapID, x = x, y = y, title = title, owner = handle })
end, true)

Public("ClearPoint", function(handle)
    if type(handle) ~= "string" or not owners[handle] then return false, "not registered" end
    local WP = ns.Waypoint
    local t = WP and WP.targets.external
    if not t or t.owner ~= handle then return false end
    WP.Clear("external")
    return true
end, true)

-- Sends an event to every owner that wants it; each one is isolated.
local function CallOwner(h, ev, ...)
    local o = owners[h]
    local f = o and not o.off and o.cbs[ev]
    if not f then return end
    local ok, err = pcall(f, ...)
    if not ok then
        o.errors = o.errors + 1
        Debug("%s callback %s failed (%d): %s", o.name, ev, o.errors, tostring(err))
        if o.errors >= MAX_ERRORS then
            o.off = true
            Debug("%s cut off after %d errors", o.name, MAX_ERRORS)
        end
    end
end

local function Send(ev, ...)
    local list = {}
    for h in pairs(owners) do list[#list + 1] = h end
    table.sort(list)
    for _, h in ipairs(list) do CallOwner(h, ev, ...) end
end

-- ------------------------------------------------------------------ copies out
local function StepCopy()
    local E = ns.Engine
    local g = E and E.Focused()
    if not g then return nil end
    local s, top = E.Current()
    if not s then return { guide = g.key, finished = true } end
    local text
    local ok, t = pcall(top.Text, top, s)
    if ok then text = t end
    return { guide = g.key, id = s.id, type = s.type, quest = s.quest, map = s.map, x = s.x, y = s.y,
        text = type(text) == "string" and text or nil, index = s.index, count = top:Count() }
end

Public("GetCurrentStep", function() return StepCopy() end, true)

Public("GetState", function()
    local E = ns.Engine
    local g = E and E.Focused()
    local active = {}
    for k in pairs(E and E.guides or {}) do active[#active + 1] = k end
    table.sort(active)
    return { version = API.version, addonVersion = ns.version, focused = g and g.key or nil, active = active }
end, true)

-- ------------------------------------------------------------------ deprecation
-- API.OldName keeps working while it's listed here (one debug line per name).
local warned = {}
setmetatable(API, { __index = function(_, k)
    local new = DEPRECATED[k]
    if not new then return nil end
    if not warned[k] then
        warned[k] = true
        Debug("deprecated name %s, use %s", tostring(k), new)
    end
    return rawget(API, new)
end })
ns.Test.APIDeprecate = function(old, new) DEPRECATED[old] = new end
ns.Test.APIOwners = function() return owners end

-- self-test: a handle comes and goes, copies are copies, a throwing callback is isolated
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "api", fn = function(h)
    h.Count(3)
    local handle = API.Register("AOG-selftest", { Ready = function() error("selftest") end })
    if type(handle) ~= "string" then return h.Problem("API", "register", "no handle") end
    local ok = pcall(CallOwner, handle, "Ready")
    if not ok then h.Problem("API", "callback", "error escaped") end
    if not API.Unregister(handle) or owners[handle] then h.Problem("API", "unregister", "handle kept") end
    if API.ready then
        local a = API.GetState()
        if type(a) == "table" then a.focused = "x" end
        local b = API.GetState()
        if type(b) == "table" and b.focused == "x" then h.Problem("API", "copy", "state not copied") end
    end
end }

-- ------------------------------------------------------------------ wiring (our bus -> owners)
ns.Bus.On("Login", API, function()
    API.ready = true
    Send("Ready")
end, "api", 95)

ns.Bus.On("StepChanged", API, function(_, g)
    if not API.ready or type(g) ~= "table" then return end
    if g.key and not seenGuides[g.key] then
        seenGuides[g.key] = true
        local packId = tostring(g.key):match("^([^/]+)")
        Send("GuideOpened", g.key, packId)
    end
    if ns.Engine and ns.Engine.Focused() == g then
        local copy = StepCopy()
        if copy then Send("StepChanged", copy) end
    end
end, "api", 95)

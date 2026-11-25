-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The waypoint arbiter (v0.2 M3): one target for the arrow, from four sources, highest first:
--   corpse   (dead and released: C_DeathInfo.GetCorpseMapPosition on the player's map, else its parents
--             up to the continent)
--   external (another addon through AllinOneGuide.API.PointTo, e.g. Gear Set)
--   show     (the player: "point here" on a step, /way, /aog way)
--   step     (the current step's spot)
-- "Clear" drops external and show. Targets are copies: { map, x, y (0-1), r, title, source }.
--   ns.Waypoint.Set(source, target) / Clear(source) / Current() / ClearManual()
--   ns.Waypoint.ParseWay(text) -> map, x, y, title | nil, why       bus: WaypointChanged(source)
local _, ns = ...
local Co = ns.Compat
local WP = { PRIO = { "corpse", "external", "show", "step" }, targets = {}, current = nil, source = nil,
    wayOwned = false }
ns.Waypoint = WP

local function Valid(t)
    return type(t) == "table" and type(t.map) == "number" and type(t.x) == "number" and type(t.y) == "number"
        and t.x >= 0 and t.x <= 1 and t.y >= 0 and t.y <= 1
end

function WP.Current() return WP.current, WP.source end

function WP.Apply()
    local best, src
    for _, s in ipairs(WP.PRIO) do
        local t = WP.targets[s]
        if t then best, src = t, s break end
    end
    local changed = best ~= WP.current
    WP.current, WP.source = best, src
    if ns.Arrow then ns.Arrow.SetTarget(best, src) end
    if changed then ns.Bus.Fire("WaypointChanged", src) end
end

-- A step table is used as it is (the arrow reads map / x / y / r); others are copied and checked.
function WP.Set(source, t)
    if source == "step" then
        WP.targets.step = (t and t.map and t.x and t.y) and t or nil
    elseif t == nil then
        WP.targets[source] = nil
    else
        if not Valid(t) then return false end
        WP.targets[source] = { map = t.map, x = t.x, y = t.y, r = tonumber(t.r) or 10,
            title = type(t.title) == "string" and ns.U.Utf8Cut(t.title, 60) or nil, source = source, owner = t.owner }
    end
    WP.Apply()
    return true
end

function WP.Clear(source) return WP.Set(source, nil) end

function WP.ClearManual()
    WP.targets.show, WP.targets.external = nil, nil
    WP.Apply()
end

-- ------------------------------------------------------------------ corpse
-- The corpse on the player's map, else on its parent maps up to the continent (a graveyard across a
-- zone border); nil when the corpse is on another continent or there's no data.
function WP.CorpseTarget()
    local map = ns.Geo.Player()
    for _ = 1, 6 do
        if not map then return nil end
        local x, y = Co.CorpsePosition(map)
        if x then return map, x, y end
        map = Co.MapParent(map)
    end
    return nil
end

WP.RETRY, WP.RETRY_MAX = 2, 5
WP.retries = 0

function WP.CheckCorpse()
    if Co.Dead() and Co.Ghost() then
        local map, x, y = WP.CorpseTarget()
        if map then
            WP.retries = 0
            local c = WP.targets.corpse
            if not (c and c.map == map and c.x == x and c.y == y) then
                WP.Set("corpse", { map = map, x = x, y = y, r = 10, title = ns.L.WAY_CORPSE })
            end
            return
        end
        -- just released: the corpse position can come a moment after the event; ask again a few times
        if WP.retries < WP.RETRY_MAX and not WP.retryWaiting then
            WP.retries, WP.retryWaiting = WP.retries + 1, true
            Co.After(WP.RETRY, function()
                WP.retryWaiting = false
                ns.Errors.Call("waypoint", WP.CheckCorpse)
            end)
        end
    else
        WP.retries = 0
    end
    if WP.targets.corpse then WP.Clear("corpse") end
end

-- ------------------------------------------------------------------ /way
-- "/way 45.2 61.8 title", "/way 1429 45.2 61.8", "/way 45,2 61,8" (comma decimals); coordinates in percent.
function WP.ParseWay(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text == "" then return nil, "empty" end
    local nums, rest = {}, text
    while #nums < 3 do
        local n, r = rest:match("^([%d]+[%.,]?%d*)[%s,]*(.*)$")
        if not n then break end
        nums[#nums + 1] = tonumber((n:gsub(",", "."))) or 0
        rest = r
    end
    local map, x, y
    if #nums == 3 then
        map, x, y = math.floor(nums[1]), nums[2], nums[3]
    elseif #nums == 2 then
        map, x, y = ns.Geo.Player(), nums[1], nums[2]
    else
        return nil, "numbers"
    end
    if not map then return nil, "map" end
    if x < 0 or x > 100 or y < 0 or y > 100 then return nil, "range" end
    local title = rest ~= "" and rest or nil
    return map, x / 100, y / 100, title
end

function WP.Way(arg)
    arg = tostring(arg or "")
    if arg:lower():match("^%s*clear%s*$") or arg:lower():match("^%s*reset%s*$") then
        WP.ClearManual()
        ns.Print(ns.L.WAY_CLEARED)
        return true
    end
    local map, x, y, title = WP.ParseWay(arg)
    if not map then
        ns.Print(ns.L.WAY_USAGE)
        return false
    end
    WP.Set("show", { map = map, x = x, y = y, title = title })
    return true
end

-- The copy line for a target: "/way <map> <x> <y> <title>".
function WP.WayLine(t)
    if not (t and t.map and t.x and t.y) then return nil end
    local line = ("/way %d %.1f %.1f"):format(t.map, t.x * 100, t.y * 100)
    local title = t.title or t.text
    if type(title) == "string" and title ~= "" then line = line .. " " .. title end
    return line
end

-- /way only when no other addon has it (checked at login); /aog way always works.
function WP.RegisterWay()
    local list, hash = _G.SlashCmdList, _G.hash_SlashCmdList
    if type(list) ~= "table" then return false end
    if type(hash) == "table" and hash["/WAY"] ~= nil then return false end
    for name in pairs(list) do
        local i = 1
        while _G["SLASH_" .. name .. i] do
            if tostring(_G["SLASH_" .. name .. i]):upper() == "/WAY" then return false end
            i = i + 1
        end
    end
    _G.SLASH_ALLINONEGUIDEWAY1 = "/way"
    list.ALLINONEGUIDEWAY = function(msg) ns.Errors.Call("slash", WP.Way, msg) end
    WP.wayOwned = true
    return true
end

ns.Slash.Add("way", function(arg) WP.Way(arg) end, "HELP_WAY")

ns.Bus.On("Login", WP, function()
    ns.Bus.On("DeadChanged", WP, function() ns.Errors.Call("waypoint", WP.CheckCorpse) end, "waypoint")
    ns.Bus.On("ZoneChanged", WP, function() ns.Errors.Call("waypoint", WP.CheckCorpse) end, "waypoint")
    -- the release fires PLAYER_ALIVE while still dead (now a ghost): check on every death event
    for _, ev in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        ns.Events.On(ev, WP, function() ns.Errors.Call("waypoint", WP.CheckCorpse) end, "waypoint")
    end
    WP.RegisterWay()
    WP.CheckCorpse()
end, "waypoint", 60)

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Time left on the route (the window's "~ 38 min left" chip; the user's answer: "Estimate, then your pace").
--   * estimate per step still to do: the pack's `estMin`, else a default for its type, plus the walk from the step
--     before it (straight line at P.RUN yards a second; not for fly / hearth steps)
--   * your pace: each finished step's real time against its estimate (char module `pace`, last P.KEEP; a step that
--     took longer than P.CAP is left out: away, dead, a break). From P.PACE_MIN measured steps on, the estimate is
--     scaled by your own ratio (clamped to P.RATIO_MIN..P.RATIO_MAX)
--   * the sums to the end are worked out once per guide (again when its step count or the level changes); a step
--     change only looks one up (never per frame)
--   ns.Pace.Left(top) -> minutes or nil, .Text(top) -> "~ 38 min left" or nil, .Ratio() -> ratio, n
local _, ns = ...
local P = {
    RUN = 7, PACE_MIN = 8, KEEP = 50, CAP = 900, RATIO_MIN = 0.4, RATIO_MAX = 3,
    -- minutes per step type when the pack gives none
    DEFAULT = { accept = 0.4, turnin = 0.4, objective = 4, grind = 6, level = 6, ["goto"] = 0.2, fly = 2, hearth = 1,
        getfp = 0.5, sethearth = 0.5, learn = 1, train = 1, useitem = 1, manual = 1, note = 0.2 },
    NO_WALK = { fly = true, hearth = true },
    cache = setmetatable({}, { __mode = "k" }),
}
ns.Pace = P

-- Minutes for one step (prev = the step before it, for the walk).
function P.StepMinutes(s, prev)
    local m = tonumber(s.estMin) or P.DEFAULT[s.type] or 1
    if prev and not P.NO_WALK[s.type] and s.map and s.x and s.y and prev.map and prev.x and prev.y then
        local yards = ns.Geo.Distance(prev.map, prev.x, prev.y, s.map, s.x, s.y)
        if yards then m = m + yards / P.RUN / 60 end
    end
    return m
end

-- Minutes from each position to the end, worked out once per guide (and again when the step count or the level
-- changes: what applies depends on it), so a step change costs nothing (a 5,000-step pack stays under its budget).
-- Counted: the steps that apply and aren't background (whileUntil) or optional. Skips and steps already done
-- further on are left in (a small overestimate, the pace corrects it).
local function Suffix(top)
    local count = top:Count()
    local lv = ns.Engine.ctx and ns.Engine.ctx.level or 0
    local key = count .. ":" .. tostring(lv)
    local c = P.cache[top]
    if c and c.key == key then return c end
    local mins, steps = {}, {}
    local list, prevOf = {}, {}
    local prev
    for j = 1, count do
        local s = top:Step(j)
        if s and top:Applicable(s) and not s.whileUntil and not (s.flags and s.flags.optional) then
            list[#list + 1] = j
            prevOf[j] = prev
            prev = s
        end
    end
    local est, n = 0, 0
    local k = #list
    for j = count, 1, -1 do
        if k > 0 and list[k] == j then
            est = est + P.StepMinutes(top:Step(j), prevOf[j])
            n = n + 1
            k = k - 1
        end
        mins[j], steps[j] = est, n
    end
    c = { key = key, mins = mins, steps = steps }
    P.cache[top] = c
    return c
end

-- Estimated minutes left (no pace) and how many steps that counts, from the current position.
function P.Estimate(top)
    if not top then return nil end
    local c = Suffix(top)
    local pos = top.pos or 1
    return c.mins[pos] or 0, c.steps[pos] or 0
end

local function Store(write)
    if write and not ns.safeMode and not (ns.DB.readOnly and ns.DB.readOnly.char) then
        return ns.DB.Module("pace", "char", 1)
    end
    local mods = ns.DB.char and ns.DB.char.modules
    return type(mods) == "table" and type(mods.pace) == "table" and mods.pace or nil
end

-- Your pace: real time / estimated time over the measured steps, and how many there are. nil before PACE_MIN.
function P.Ratio()
    local m = Store(false)
    local list = m and type(m.samples) == "table" and m.samples or {}
    local est, real, n = 0, 0, 0
    for _, s in ipairs(list) do
        if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" and s[1] > 0 and s[2] > 0 then
            est, real, n = est + s[1], real + s[2], n + 1
        end
    end
    if n < P.PACE_MIN or est <= 0 then return nil, n end
    return math.max(P.RATIO_MIN, math.min(P.RATIO_MAX, real / est)), n
end

-- Minutes left with your pace (when known), or nil when nothing is left.
function P.Left(top)
    local est, n = P.Estimate(top)
    if not est or n == 0 then return nil end
    local r = P.Ratio()
    return est * (r or 1)
end

function P.Text(top)
    local left = P.Left(top)
    if not left then return nil end
    local mins = math.max(1, math.floor(left + 0.5))
    local L = ns.L
    if mins < 60 then return ns.U.Fill(L.CHIP_TIME_MIN, { n = mins }) end
    return ns.U.Fill(L.CHIP_TIME_HOURS, { h = math.floor(mins / 60), n = mins % 60 })
end

-- Measuring: the time from a step becoming current until the next one does, when it was finished (not skipped,
-- not a jump back). Real seconds and estimated seconds go into the char module.
function P.Record(step, prev, seconds)
    if not (step and seconds and seconds > 0 and seconds <= P.CAP) then return false end
    local est = P.StepMinutes(step, prev) * 60
    if est <= 0 then return false end
    local m = Store(true)
    if not m then return false end
    if type(m.samples) ~= "table" then m.samples = {} end
    table.insert(m.samples, { math.floor(est + 0.5), math.floor(seconds + 0.5) })
    while #m.samples > P.KEEP do table.remove(m.samples, 1) end
    return true
end

local function OnStep()
    local cur, top = ns.Engine.Current()
    local now = ns.Compat.Now()
    local last = P.last
    if last and cur and last.top == top and last.step ~= cur and (cur.index or 0) > (last.step.index or 0)
        and ns.UI and ns.UI.ShownDone and ns.UI.ShownDone(top, last.step) and not top:Skipped(last.step) then
        P.Record(last.step, last.prev, now - last.at)
    end
    if cur then
        if not (last and last.step == cur) then P.last = { step = cur, top = top, at = now, prev = last and last.step } end
    else
        P.last = nil
    end
end
P.OnStep = OnStep

ns.Bus.On("StepChanged", P, function() ns.Errors.Call("pace", OnStep) end, "pace", 60)

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "pace", fn = function(h)
    h.Count()
    local r, n = P.Ratio()
    h.Info(("pace: %d steps measured%s"):format(n or 0, r and (", x%.2f"):format(r) or ""))
    local m = Store(false)
    if m and m.samples ~= nil and type(m.samples) ~= "table" then h.Problem("pace: samples aren't a list") end
end }

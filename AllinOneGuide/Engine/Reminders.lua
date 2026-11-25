-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Reminders (v0.2 M2). Hints only: the player presses the button, talks to the flight master, uses the
-- hearthstone. Nothing here acts in the game.
--   * "use it now": only for the quest item named in the current step (`useItem`, or a `useitem` step's
--     `item`), when it is in the bags and off cooldown, and one of: the target is in the item's range
--     (C_Item.IsItemInRange, skipped when the game can't say), the player is at the step's spot
--     (`useWhen = "area"`), or the item just came into the bags. No target-health trigger (tos R1).
--     Setting "reminder": off / glow (default) / text (glow + notice) / sound (glow + notice + one built-in
--     sound). It fades when the item is used or the step is done.
--   * hearthstone: on `hearth` steps "Hearth to <inn> now" or "ready in N min"; a warning when the hearth
--     step coming up expects another inn than the one the stone is set to (and no sethearth step comes first).
--   * flight paths: "New flight path here" on `getfp` steps, a warning before a `fly` step whose node isn't
--     known, and "Fly to <name>" while the flight master's map is open (a text line: no clicks for the player).
local _, ns = ...
local Co, GS = ns.Compat, ns.GameState
local R = { TICK = 0.5, LOOT_SECONDS = 10, AHEAD = 5, active = false, lastCount = nil, lootedAt = nil, item = nil,
    shown = {}, sounded = false }
ns.Reminders = R

local function L() return ns.L end
local function Fill(s, t) return ns.U.Fill(s, t) end

-- notice icon + its tint per reminder (v0.2 art); danger notices keep the warning triangle
local ICON = { useitem = "notice.useitem", hearth = "notice.hearth", getfp = "notice.flight", flyto = "notice.flight" }
local function Push(id, kind, text, priority)
    R.shown[id] = true
    local icon = kind == "danger" and "notice.danger" or ICON[id] or "notice.tip"
    ns.Notice.Push({ id = id, kind = kind, text = text, priority = priority, icon = icon,
        iconColor = kind ~= "danger" and ICON[id] or nil, source = "reminders" })
end
local function Drop(id)
    if R.shown[id] then
        R.shown[id] = nil
        ns.Notice.Remove(id)
    end
end

-- The quest item the current step wants used (never the hearthstone: that has its own hint).
function R.UseItem(step)
    if not step then return nil end
    if type(step.useItem) == "number" then return step.useItem end
    if step.type == "useitem" and type(step.item) == "number" then return step.item end
    return nil
end

-- Which trigger fires now: "range", "area", "looted" or nil.
function R.Trigger(step, id)
    if Co.ItemCount(id) == 0 then return nil end
    local s, d = Co.ItemCooldown(id)
    if d > 1.5 and s + d > Co.Now() then return nil end
    if Co.ItemInRange(id, "target") == true then return "range" end
    if step.useWhen == "area" and step.map and step.x and step.y and not GS.dead then
        local dist = ns.Geo.PlayerDistance(step.map, step.x, step.y)
        if dist and dist <= (step.r or ns.Format.DEFAULT_RADIUS) then return "area" end
    end
    if R.lootedAt and Co.Now() - R.lootedAt <= R.LOOT_SECONDS then return "looted" end
    return nil
end

local function Glow(on)
    local b = ns.StepButton and ns.StepButton.frame
    if b and b.glow then
        b.glow:SetShown(on)
        ns.StepButton.Look()   -- the edge colour follows the glow at once (look review #9)
    end
end

local function SetActive(on, id)
    local level = ns.Settings.Get("reminder")
    if level == "off" then on = false end
    if on == R.active then return end
    R.active = on
    Glow(on)
    if on then
        if level == "text" or level == "sound" then
            Push("useitem", "tip", Fill(L().REMIND_USE, { item = Co.ItemName(id) or L().REMIND_ITEM }), 70)
        end
        if level == "sound" and not R.sounded then
            R.sounded = true
            local kit = _G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING or 8959
            Co.PlaySound(kit)
        end
    else
        Drop("useitem")
    end
end

-- The 0.5 s check while the current step has an item to use.
function R.Tick()
    local step = ns.Engine.Current()
    local id = R.UseItem(step)
    if not id then
        SetActive(false)
        return
    end
    local n = Co.ItemCount(id)
    if R.lastCount and n > R.lastCount then R.lootedAt = Co.Now() end
    if R.lastCount and n < R.lastCount then R.lootedAt = nil end   -- used: fade
    R.lastCount = n
    SetActive(R.Trigger(step, id) ~= nil, id)
end

local function StartTicker(on)
    if on and not R.ticker then
        R.ticker = Co.Ticker(R.TICK, function() ns.Errors.Call("reminders", R.Tick) end)
    elseif not on and R.ticker then
        R.ticker:Cancel()
        R.ticker = nil
    end
end

-- Steps coming up (current first), at most 1 + AHEAD.
local function Ahead()
    local out = {}
    local g = ns.Engine.Focused()
    if not g then return out end
    local top = g:Top()
    local j, n = top.pos, top:Count()
    while j <= n and #out < 1 + R.AHEAD do
        local s = top:Step(j)
        -- (never Done() here: travel steps latch "reached" when asked, so only the engine may ask)
        if s and top:Applicable(s) and not top:Skipped(s) then out[#out + 1] = s end
        j = j + 1
    end
    return out
end

function R.Hearth(step, list)
    local Lx = L()
    if step and step.type == "hearth" then
        local s, d = Co.ItemCooldown(ns.StepButton.HEARTHSTONE)
        local left = (d > 1.5) and (s + d - Co.Now()) or 0
        local inn = step.inn or GS.bind or Lx.REMIND_INN
        if left > 0 then
            Push("hearth", "tip", Fill(Lx.REMIND_HEARTH_WAIT, { n = math.ceil(left / 60) }), 65)
        else
            Push("hearth", "tip", Fill(Lx.REMIND_HEARTH, { inn = inn }), 65)
        end
    else
        Drop("hearth")
    end
    -- the next hearth step expects another inn, and no sethearth step comes before it
    local warn
    for _, s in ipairs(list) do
        if s.type == "sethearth" then break end
        if s.type == "hearth" then
            if s.inn and GS.bind and s.inn ~= GS.bind then warn = s end
            break
        end
    end
    if warn then
        Push("bind", "danger", Fill(Lx.REMIND_BIND, { inn = warn.inn }), 85)
    else
        Drop("bind")
    end
end

function R.Flights(step, list)
    local Lx, T = L(), ns.Taxi
    if step and step.type == "getfp" and not (T and T.Known(step.node)) then
        Push("getfp", "tip", Lx.REMIND_GETFP, 60)
    else
        Drop("getfp")
    end
    local missing
    for _, s in ipairs(list) do
        if s.type == "fly" and s.node and T and T.Known(s.node) == false then
            -- a getfp step for it before the flight is fine
            local learnt = false
            for _, p in ipairs(list) do
                if p == s then break end
                if p.type == "getfp" and p.node == s.node then learnt = true end
            end
            if not learnt then missing = s end
            break
        end
    end
    if missing then Push("flywarn", "danger", Lx.REMIND_FLY_MISSING, 80) else Drop("flywarn") end
    if step and step.type == "fly" and T and T.open then
        local name = (step.node and T.Name(step.node)) or ns.Engine.Focused():Top():Text(step)
        Push("flyto", "tip", Fill(Lx.REMIND_FLY_TO, { name = name }), 90)
    else
        Drop("flyto")
    end
end

-- Re-checks every hint for the current step.
function R.Update()
    -- nothing before the engine has its first context (conditions would be cached on an empty one); the
    -- engine fires StepChanged once it has evaluated, so that is the first call that does anything
    if not GS.ready or ns.Engine.ctx.class == nil then return end
    local step = ns.Engine.Current()
    local id = R.UseItem(step)
    if id ~= R.item then
        R.item, R.lastCount, R.lootedAt, R.sounded = id, id and Co.ItemCount(id) or nil, nil, false
        SetActive(false)
    end
    StartTicker(id ~= nil and ns.Settings.Get("reminder") ~= "off")
    if id then R.Tick() end
    local list = Ahead()
    R.Hearth(step, list)
    R.Flights(step, list)
end

ns.Bus.On("Login", R, function()
    local function Up() ns.Errors.Call("reminders", R.Update) end
    for _, ev in ipairs({ "StepChanged", "TaxiChanged", "TaxiOpened", "TaxiClosed", "BindChanged" }) do
        ns.Bus.On(ev, R, Up, "reminders")
    end
    ns.Bus.On("ItemsChanged", R, function() if R.item then ns.Errors.Call("reminders", R.Tick) end end, "reminders")
    ns.Bus.On("SettingsChanged", R, function(_, key) if key == "reminder" then SetActive(false) Up() end end, "reminders")
    Up()
end, "reminders", 92)

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Other addons that do some of the same work (by folder name, from the data list below): one quiet notice
-- per account and set of addons, and one offer to turn our map pins off when a quest-map addon also draws
-- pins. Taint watch: ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN naming us go to the debug log and the
-- self-test (the events and their payload: RestrictedActionsDocumentation.lua in the 1.60.1 UI source).
--   ns.Conflicts.Scan() -> { names }    .Check()    .taint (list of "EVENT: function")
-- The list holds free addons only (the project's rule: no paid guide addons are named anywhere).
local _, ns = ...
local Cf = { taint = {}, MAX_TAINT = 10 }
ns.Conflicts = Cf

-- pins = it draws quest pins on the maps too
Cf.LIST = {
    { name = "Questie", pins = true },
    { name = "TomTom" },
    { name = "Guidelime" },
    { name = "Mapster" },
}

function Cf.Scan()
    local found, pins = {}, false
    for _, a in ipairs(Cf.LIST) do
        if ns.Compat.IsAddOnLoaded(a.name) then
            found[#found + 1] = a.name
            pins = pins or a.pins == true
        end
    end
    return found, pins
end

local function PinsOff()
    ns.Settings.Set("mapPins", false)
    ns.Settings.Set("minimapPins", false)
    ns.Notice.Remove("conflict")
end
Cf.PinsOff = PinsOff

-- Once per account for each set of addons found; the pin offer only once ever.
function Cf.Check()
    if ns.safeMode or ns.DB.readOnly.account then return false end
    local found, pins = Cf.Scan()
    if #found == 0 then return false end
    local saved = ns.DB.Module("conflicts", "account", 1)
    if not saved then return false end
    local key = table.concat(found, ",")
    if saved.seen == key then return false end
    saved.seen = key
    local ourPins = ns.Settings.Get("mapPins") or ns.Settings.Get("minimapPins")
    local offer = pins and ourPins and not saved.pinsOffered
    if offer then saved.pinsOffered = true end
    ns.Notice.Push({ id = "conflict", kind = "tip", source = "conflicts", priority = 2,
        text = ns.U.Fill(ns.L.CONFLICT_FOUND, { names = table.concat(found, ", ") }),
        button = offer and { text = ns.L.CONFLICT_PINS_OFF, fn = PinsOff } or nil })
    return true
end

function Cf.OnBlocked(event, who, fn)
    if who ~= ns.ADDON then return end
    local line = tostring(event) .. ": " .. tostring(fn)
    if #Cf.taint < Cf.MAX_TAINT then Cf.taint[#Cf.taint + 1] = line end
    ns.Errors.Debug("taint %s", line)
end

ns.Bus.On("Login", Cf, function()
    ns.Events.On("ADDON_ACTION_BLOCKED", Cf, Cf.OnBlocked, "conflicts")
    ns.Events.On("ADDON_ACTION_FORBIDDEN", Cf, Cf.OnBlocked, "conflicts")
    if not ns.Test.quietFirstRun then
        ns.Compat.After(5, function() ns.Errors.Call("conflicts", Cf.Check) end)
    end
end, "conflicts", 90)

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "taint", fn = function(h)
    h.Count()
    for _, line in ipairs(Cf.taint) do h.Problem("blocked action: " .. line) end
    local found = Cf.Scan()
    h.Info("other addons: " .. (#found > 0 and table.concat(found, ", ") or "none"))
end }

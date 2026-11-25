-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Smart arrow connectors: Orgrimmar (uiMapID 1454). Format: packs-src\FORMAT.md, section "Connectors".
-- Rough first estimates of our own (the city's general layout), src = "own", confirmed = false: none of the
-- current routes goes into the city yet, so these are placed again with /aog rec before a route uses them.
-- The whole city map is one walled "room" (not indoor): you leave it through the gate.
-- No point is copied from any other addon's data. Only normal walkable ways.
return {
    area = "orgrimmar",
    formatVersion = 1,
    license = "GPL-3.0-or-later",
    connectors = {
        -- main gate, city side (the Durotar side is in durotar.lua)
        { id = "org-gate-in", map = 1454, x = 49.0, y = 92.0, r = 6, kind = "gate", hint = "VIA_CITY_GATE",
          inside = "org-city", link = { "dur-org-gate-out", "org-strength" }, src = "own", confirmed = false },
        { id = "org-strength", map = 1454, x = 50.0, y = 72.0, r = 10, kind = "path", hint = "VIA_VALLEY_STRENGTH",
          inside = "org-city", link = { "org-drag", "org-cleft" }, src = "own", confirmed = false },
        { id = "org-cleft", map = 1454, x = 50.0, y = 58.0, r = 6, kind = "ramp", hint = "VIA_CLEFT_RAMP",
          inside = "org-city", src = "own", confirmed = false },
        { id = "org-drag", map = 1454, x = 40.0, y = 50.0, r = 10, kind = "path", hint = "VIA_THE_DRAG",
          inside = "org-city", link = { "org-hold-door-out" }, src = "own", confirmed = false },
        { id = "org-hold-door-out", map = 1454, x = 37.0, y = 41.5, r = 4, kind = "door", hint = "VIA_HOLD_DOOR",
          inside = "org-city", link = { "org-hold-door-in" }, src = "own", confirmed = false },
        { id = "org-hold-door-in", map = 1454, x = 36.0, y = 40.0, r = 4, kind = "door", hint = "VIA_HOLD_DOOR",
          inside = "org-hold", src = "own", confirmed = false },
    },
    rooms = {
        { id = "org-city", map = 1454, indoor = false, subzone = "Orgrimmar",
          poly = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } }, src = "own", confirmed = false },
        { id = "org-hold", map = 1454, indoor = true, subzone = "Grommash Hold",
          poly = { { 30.0, 33.0 }, { 39.0, 33.0 }, { 39.0, 40.5 }, { 30.0, 40.5 } }, src = "own", confirmed = false },
    },
}

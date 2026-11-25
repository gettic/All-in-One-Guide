-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Smart arrow connectors: Stormwind City (uiMapID 1453). Format: packs-src\FORMAT.md, section "Connectors".
-- Rough first estimates of our own (the city's general layout), src = "own", confirmed = false: none of the
-- current routes goes into the city yet, so these are placed again with /aog rec before a route uses them.
-- The whole city map is one walled "room" (not indoor): you leave it through the gate.
-- No point is copied from any other addon's data. Only normal walkable ways.
return {
    area = "stormwind",
    formatVersion = 1,
    license = "GPL-3.0-or-later",
    connectors = {
        -- main gate, city side (the Elwynn side is in elwynn.lua)
        { id = "sw-gate-in", map = 1453, x = 70.0, y = 88.0, r = 6, kind = "gate", hint = "VIA_CITY_GATE",
          inside = "sw-city", link = { "eln-sw-gate-out", "sw-heroes" }, src = "own", confirmed = false },
        { id = "sw-heroes", map = 1453, x = 66.0, y = 80.0, r = 10, kind = "path", hint = "VIA_VALLEY_HEROES",
          inside = "sw-city", link = { "sw-trade" }, src = "own", confirmed = false },
        { id = "sw-trade", map = 1453, x = 62.0, y = 70.0, r = 10, kind = "bridge", hint = "VIA_TRADE_BRIDGE",
          inside = "sw-city", link = { "sw-cathedral-sq" }, src = "own", confirmed = false },
        { id = "sw-cathedral-sq", map = 1453, x = 54.0, y = 52.0, r = 10, kind = "path", hint = "VIA_CATHEDRAL_SQUARE",
          inside = "sw-city", link = { "sw-cathedral-door-out" }, src = "own", confirmed = false },
        { id = "sw-cathedral-door-out", map = 1453, x = 52.5, y = 46.0, r = 4, kind = "door", hint = "VIA_CATHEDRAL_DOOR",
          inside = "sw-city", link = { "sw-cathedral-door-in" }, src = "own", confirmed = false },
        { id = "sw-cathedral-door-in", map = 1453, x = 52.0, y = 43.5, r = 4, kind = "door", hint = "VIA_CATHEDRAL_DOOR",
          inside = "sw-cathedral", src = "own", confirmed = false },
    },
    rooms = {
        { id = "sw-city", map = 1453, indoor = false, subzone = "Stormwind City",
          poly = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } }, src = "own", confirmed = false },
        { id = "sw-cathedral", map = 1453, indoor = true, subzone = "Cathedral of Light",
          poly = { { 49.0, 36.0 }, { 55.0, 36.0 }, { 55.0, 44.0 }, { 49.0, 44.0 } }, src = "own", confirmed = false },
    },
}

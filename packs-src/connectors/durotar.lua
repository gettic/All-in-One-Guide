-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Contains position facts from CMaNGOS classic-db (GPL-3.0), see CREDITS.txt
-- Smart arrow connectors: Valley of Trials and Durotar (uiMapID 1411). Format: packs-src\FORMAT.md, section 8.
-- src = "own": our own estimate from public facts (the step spots in our packs and the general layout);
-- src = "cmangos": a bare position fact from CMaNGOS classic-db (a gate game object, or a cave's size from where
-- its dwellers spawn, snapped to 0.5 %; never paths or waypoints). All confirmed = false until a tester records
-- them on Forever with /aog rec. No point is copied from any other addon's waypoint data.
-- Only normal walkable ways: no jumps, no drops that need tricks, nothing out of bounds.
return {
    area = "durotar",
    formatVersion = 1,
    license = "GPL-3.0-or-later",
    connectors = {
        -- Valley of Trials: the Den (Gornek inside), entrance on the east side.
        { id = "vot-den-in", map = 1411, x = 42.4, y = 68.4, r = 4, kind = "cave", hint = "VIA_DEN_ENTRANCE",
          inside = "vot-den", link = { "vot-den-out" }, src = "own", confirmed = false },
        { id = "vot-den-out", map = 1411, x = 42.8, y = 68.5, r = 4, kind = "cave", hint = "VIA_DEN_ENTRANCE",
          link = { "vot-den-in" }, src = "own", confirmed = false },
        -- Burning Blade Coven (north of the valley): the cave mouth, the warlock at the back.
        { id = "vot-coven-in", map = 1411, x = 44.6, y = 55.4, r = 5, kind = "cave", hint = "VIA_CAVE_ENTRANCE",
          inside = "vot-coven", link = { "vot-coven-out" }, src = "own", confirmed = false },
        { id = "vot-coven-out", map = 1411, x = 45.0, y = 56.2, r = 5, kind = "cave", hint = "VIA_CAVE_ENTRANCE",
          link = { "vot-coven-in" }, src = "own", confirmed = false },
        -- Razor Hill: the inn (innkeeper inside), door on the road side.
        { id = "rzh-inn-door-in", map = 1411, x = 51.8, y = 41.8, r = 3, kind = "door", hint = "VIA_INN_DOOR",
          inside = "rzh-inn", link = { "rzh-inn-door-out" }, src = "own", confirmed = false },
        { id = "rzh-inn-door-out", map = 1411, x = 52.2, y = 41.9, r = 3, kind = "door", hint = "VIA_INN_DOOR",
          link = { "rzh-inn-door-in" }, src = "own", confirmed = false },
        -- Dustwind Cave (north of Razor Hill): the cultists are inside, the mouth faces the road to the south.
        { id = "dur-dustwind-in", map = 1411, x = 52.3, y = 27.3, r = 5, kind = "cave", hint = "VIA_CAVE_ENTRANCE",
          inside = "dur-dustwind", link = { "dur-dustwind-out" }, src = "own", confirmed = false },
        { id = "dur-dustwind-out", map = 1411, x = 52.3, y = 28.2, r = 5, kind = "cave", hint = "VIA_CAVE_ENTRANCE",
          link = { "dur-dustwind-in" }, src = "own", confirmed = false },
        -- Skull Rock (east of Orgrimmar's gate): the Burning Blade inside; the mouth on the east side is our estimate.
        { id = "dur-skullrock-in", map = 1411, x = 52.7, y = 9.5, r = 5, kind = "cave", hint = "VIA_CAVE_ENTRANCE",
          inside = "dur-skullrock", link = { "dur-skullrock-out" }, src = "own", confirmed = false },
        { id = "dur-skullrock-out", map = 1411, x = 53.4, y = 9.5, r = 5, kind = "cave", hint = "VIA_CAVE_ENTRANCE",
          link = { "dur-skullrock-in" }, src = "own", confirmed = false },
        -- Orgrimmar's main gate, Durotar side: the outer "Orgrimmar Main Gate" game object in CMaNGOS. The city side
        -- is in orgrimmar.lua.
        { id = "dur-org-gate-out", map = 1411, x = 42.3, y = 6.7, r = 8, kind = "gate", hint = "VIA_CITY_GATE",
          link = { "org-gate-in" }, src = "cmangos", confirmed = false },
    },
    rooms = {
        { id = "vot-den", map = 1411, indoor = true, subzone = "The Den",
          poly = { { 41.4, 67.7 }, { 42.6, 67.7 }, { 42.6, 68.9 }, { 41.4, 68.9 } }, src = "own", confirmed = false },
        -- sized from where the felstalkers and the warlock spawn (CMaNGOS, 0.5 % grid)
        { id = "vot-coven", map = 1411, indoor = true, subzone = "Burning Blade Coven",
          poly = { { 41.8, 51.0 }, { 45.3, 51.0 }, { 45.3, 55.7 }, { 41.8, 55.7 } }, src = "cmangos", confirmed = false },
        { id = "rzh-inn", map = 1411, indoor = true, subzone = "Razor Hill",
          poly = { { 51.1, 41.1 }, { 52.0, 41.1 }, { 52.0, 42.0 }, { 51.1, 42.0 } }, src = "own", confirmed = false },
        -- sized from where the Burning Blade cultists spawn (CMaNGOS, 0.5 % grid)
        { id = "dur-dustwind", map = 1411, indoor = true, subzone = "Dustwind Cave",
          poly = { { 51.5, 24.0 }, { 53.0, 24.0 }, { 53.0, 27.6 }, { 51.5, 27.6 } }, src = "cmangos", confirmed = false },
        -- sized from where the Burning Blade and their leader spawn (CMaNGOS, 0.5 % grid)
        { id = "dur-skullrock", map = 1411, indoor = true, subzone = "Skull Rock",
          poly = { { 50.8, 7.5 }, { 52.9, 7.5 }, { 52.9, 11.5 }, { 50.8, 11.5 } }, src = "cmangos", confirmed = false },
    },
}

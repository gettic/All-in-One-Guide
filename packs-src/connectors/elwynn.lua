-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Contains position facts from CMaNGOS classic-db (GPL-3.0), see CREDITS.txt
-- Smart arrow connectors: Northshire Valley and Elwynn Forest (uiMapID 1429). Format: packs-src\FORMAT.md,
-- section 8. src = "own": our own estimate from public facts (the step spots in our packs and the general
-- layout); src = "cmangos": a bare position fact from CMaNGOS classic-db (a gate game object, or a mine's size
-- from where its dwellers spawn, snapped to 0.5 %; never paths or waypoints). All confirmed = false until a
-- tester records them on Forever with /aog rec. No point is copied from any other addon's waypoint data.
-- Only normal walkable ways: no jumps, no drops that need tricks, nothing out of bounds.
return {
    area = "elwynn",
    formatVersion = 1,
    license = "GPL-3.0-or-later",
    connectors = {
        -- Northshire Abbey: front door on the yard side (the deputy stands outside it). CMaNGOS has no door
        -- object here (an open doorway), so the door is our estimate.
        { id = "nsh-abbey-door-in", map = 1429, x = 48.7, y = 42.3, r = 3, kind = "door", hint = "VIA_ABBEY_DOOR",
          inside = "nsh-abbey", link = { "nsh-abbey-door-out" }, src = "own", confirmed = false },
        { id = "nsh-abbey-door-out", map = 1429, x = 48.5, y = 42.8, r = 3, kind = "door", hint = "VIA_ABBEY_DOOR",
          link = { "nsh-abbey-door-in" }, src = "own", confirmed = false },
        -- Echo Ridge Mine (north of the abbey): the kobold laborers are inside.
        { id = "nsh-echo-mine-in", map = 1429, x = 47.6, y = 31.2, r = 5, kind = "cave", hint = "VIA_MINE_ENTRANCE",
          inside = "nsh-echo-mine", link = { "nsh-echo-mine-out" }, src = "own", confirmed = false },
        { id = "nsh-echo-mine-out", map = 1429, x = 47.5, y = 32.2, r = 5, kind = "cave", hint = "VIA_MINE_ENTRANCE",
          link = { "nsh-echo-mine-in" }, src = "own", confirmed = false },
        -- Goldshire: the Lion's Pride Inn (innkeeper inside), door on the road side. No door object in CMaNGOS.
        { id = "gsh-inn-door-in", map = 1429, x = 43.4, y = 65.7, r = 3, kind = "door", hint = "VIA_INN_DOOR",
          inside = "gsh-inn", link = { "gsh-inn-door-out" }, src = "own", confirmed = false },
        { id = "gsh-inn-door-out", map = 1429, x = 43.0, y = 65.6, r = 3, kind = "door", hint = "VIA_INN_DOOR",
          link = { "gsh-inn-door-in" }, src = "own", confirmed = false },
        -- Fargodeep Mine (south-west of Goldshire): the tunnelers live inside, the miners work outside its east
        -- mouth; the mouth is our estimate between the two groups.
        { id = "eln-fargodeep-in", map = 1429, x = 39.3, y = 80.8, r = 5, kind = "cave", hint = "VIA_MINE_ENTRANCE",
          inside = "eln-fargodeep", link = { "eln-fargodeep-out" }, src = "own", confirmed = false },
        { id = "eln-fargodeep-out", map = 1429, x = 40.3, y = 80.8, r = 5, kind = "cave", hint = "VIA_MINE_ENTRANCE",
          link = { "eln-fargodeep-in" }, src = "own", confirmed = false },
        -- Jasperlode Mine (north-east of Goldshire): the mine runs north, the camp is south of its mouth.
        { id = "eln-jasperlode-in", map = 1429, x = 61.2, y = 53.0, r = 5, kind = "cave", hint = "VIA_MINE_ENTRANCE",
          inside = "eln-jasperlode", link = { "eln-jasperlode-out" }, src = "own", confirmed = false },
        { id = "eln-jasperlode-out", map = 1429, x = 61.4, y = 54.0, r = 5, kind = "cave", hint = "VIA_MINE_ENTRANCE",
          link = { "eln-jasperlode-in" }, src = "own", confirmed = false },
        -- Stormwind's main gate, Elwynn side: the south-easternmost "Stormwind Gate" game object in CMaNGOS (which
        -- of the gate objects is the main gate is our judgement). The city side is in stormwind.lua.
        { id = "eln-sw-gate-out", map = 1429, x = 26.5, y = 38.5, r = 8, kind = "gate", hint = "VIA_CITY_GATE",
          link = { "sw-gate-in" }, src = "cmangos", confirmed = false },
    },
    rooms = {
        -- the abbey: main hall plus the north wing (the trainers in our packs stand inside)
        { id = "nsh-abbey", map = 1429, indoor = true, subzone = "Northshire Abbey",
          poly = { { 48.4, 40.8 }, { 49.3, 40.8 }, { 49.3, 39.3 }, { 50.2, 39.3 }, { 50.2, 40.8 }, { 50.7, 40.8 },
              { 50.7, 42.5 }, { 48.4, 42.5 } }, src = "own", confirmed = false },
        { id = "nsh-echo-mine", map = 1429, indoor = true, subzone = "Echo Ridge Mine",
          poly = { { 46.5, 27.0 }, { 50.5, 27.0 }, { 50.5, 31.4 }, { 46.5, 31.4 } }, src = "own", confirmed = false },
        { id = "gsh-inn", map = 1429, indoor = true, subzone = "Lion's Pride Inn",
          poly = { { 43.2, 65.0 }, { 44.6, 65.0 }, { 44.6, 66.6 }, { 43.2, 66.6 } }, src = "own", confirmed = false },
        -- sized from where the kobold tunnelers spawn (CMaNGOS, 0.5 % grid)
        { id = "eln-fargodeep", map = 1429, indoor = true, subzone = "Fargodeep Mine",
          poly = { { 35.5, 78.5 }, { 39.6, 78.5 }, { 39.6, 87.5 }, { 35.5, 87.5 } }, src = "cmangos", confirmed = false },
        -- sized from where the kobold miners and geomancers spawn north of the camp (CMaNGOS, 0.5 % grid)
        { id = "eln-jasperlode", map = 1429, indoor = true, subzone = "Jasperlode Mine",
          poly = { { 59.8, 48.5 }, { 62.2, 48.5 }, { 62.2, 53.3 }, { 59.8, 53.3 } }, src = "cmangos", confirmed = false },
    },
}

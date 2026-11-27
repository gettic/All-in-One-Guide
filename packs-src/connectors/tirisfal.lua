-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Contains position facts from CMaNGOS classic-db (GPL-3.0) and from Shortest Path Forever's baked walking grid
-- (GPL-3.0-or-later, Cillian Berragan), see CREDITS.txt
-- Smart arrow connectors: Deathknell and Tirisfal Glades (uiMapID 1420). Format: packs-src\FORMAT.md, section 8.
-- All confirmed = false until a tester records them on Forever with /aog rec. No point is copied from any other
-- addon's waypoint data. Only normal walkable ways.
return {
    area = "tirisfal",
    formatVersion = 1,
    license = "GPL-3.0-or-later",
    connectors = {
        -- Deathknell start crypt (bug fix round 2, 2026-11-27: "it just tells me 'take the stairs', points me to the
        -- right of the stairs and stops working in the middle of the room! i want way points on the stairs").
        -- Geometry (src = "spf"): Shortest Path Forever's walking grid (8 yd cells with every floor's height), read
        -- with its own decoder, two bakes (SPF v1.41.0 and v1.49.2) agree: the undead spawn (CMaNGOS
        -- playercreateinfo, z 121.7) is at the north end of a hall (z 121); the only way up leaves the hall's south
        -- wall straight south (z 125), up to a landing (z 128); the stairs turn back (left) and the next flight
        -- climbs north along the east side (z 134-138); its top opens north onto the ground over the hall (z 142),
        -- and Undertaker Mordo stands about 20 yd further north (z 135.9). Our own placement on those cells (+-4 yd):
        -- each point is the middle of its cell side; the top of the second flight is where its z 138 cell meets the
        -- z 136 opening (the newer bake marks that cell as ground). Stairs points are walked to one by one (no
        -- doorway middle).
        { id = "dkn-crypt-stairs-foot", map = 1420, x = 30.068, y = 72.330, r = 4, kind = "stairs",
          inside = "dkn-crypt", link = { "dkn-crypt-landing" }, src = "spf", confirmed = false },
        { id = "dkn-crypt-landing", map = 1420, x = 30.068, y = 72.793, r = 4, kind = "stairs", hint = "VIA_STAIRS_UP",
          inside = "dkn-crypt-stairs", link = { "dkn-crypt-landing-turn" }, src = "spf", confirmed = false },
        { id = "dkn-crypt-landing-turn", map = 1420, x = 30.242, y = 72.793, r = 4, kind = "stairs",
          hint = "VIA_STAIRS_TURN_LEFT", inside = "dkn-crypt-stairs-2", link = { "dkn-crypt-stairs-top" },
          src = "spf", confirmed = false },
        { id = "dkn-crypt-stairs-top", map = 1420, x = 30.313, y = 72.495, r = 4, kind = "stairs", hint = "VIA_STAIRS_NEXT",
          inside = "dkn-crypt-stairs-2", link = { "dkn-crypt-way-out" }, src = "spf", confirmed = false },
        -- outdoors, on the ground just past the top of the stairs (over the hall: IsIndoors tells the two apart)
        { id = "dkn-crypt-way-out", map = 1420, x = 30.346, y = 72.231, r = 5, kind = "path", hint = "VIA_CRYPT_OUT",
          src = "spf", confirmed = false },
    },
    rooms = {
        -- the hall (z 121) with the spawn spot at its north end; kept 3 yd short of Mordo's spot above it
        { id = "dkn-crypt", map = 1420, indoor = true, subzone = "Deathknell",
          poly = { { 30.501, 72.379 }, { 30.501, 71.850 }, { 30.136, 71.850 }, { 30.136, 71.552 }, { 29.627, 71.552 },
              { 29.627, 72.644 }, { 29.970, 72.644 }, { 29.970, 72.379 } },
          src = "spf", confirmed = false },
        -- the first flight (south of the hall) and its landing
        { id = "dkn-crypt-stairs", map = 1420, indoor = true, subzone = "Deathknell",
          poly = { { 30.156, 72.925 }, { 30.156, 72.379 }, { 29.970, 72.379 }, { 29.970, 72.925 } },
          src = "spf", confirmed = false },
        -- the second flight (back north, east of the first) and the floor round its top; chain: from the landing
        -- the arrow goes to the turn first, never straight across to the top
        { id = "dkn-crypt-stairs-2", map = 1420, indoor = true, chain = true, subzone = "Deathknell",
          poly = { { 30.501, 72.925 }, { 30.501, 72.644 }, { 30.413, 72.644 }, { 30.413, 72.379 }, { 30.156, 72.379 },
              { 30.156, 72.925 } },
          src = "spf", confirmed = false },
    },
}

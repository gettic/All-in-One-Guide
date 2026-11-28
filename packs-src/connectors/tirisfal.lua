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
        -- and Undertaker Mordo stands about 20 yd further north (z 135.9), straight ahead of the way out. Our own
        -- placement: every point sits on its flight's centre line (round 3, v0.2.8 report "it pointed to the left
        -- corner of the stairs to start and on the way out to the right corner"). Flight 1 + landing: y 1679.6 world
        -- (its z 124-128 cells span two 8 yd columns); flight 2 + way out: y 1667.7 (one column, out onto the ground
        -- the same column). Stairs points are walked to one by one (no doorway middle).
        { id = "dkn-crypt-stairs-foot", map = 1420, x = 29.979, y = 72.346, r = 4, kind = "stairs",
          inside = "dkn-crypt", link = { "dkn-crypt-landing" }, src = "spf", confirmed = false },
        { id = "dkn-crypt-landing", map = 1420, x = 29.979, y = 72.793, r = 3, kind = "stairs", hint = "VIA_STAIRS_UP",
          inside = "dkn-crypt-stairs", link = { "dkn-crypt-landing-turn" }, src = "spf", confirmed = false },
        { id = "dkn-crypt-landing-turn", map = 1420, x = 30.242, y = 72.793, r = 3, kind = "stairs",
          hint = "VIA_STAIRS_TURN_LEFT", inside = "dkn-crypt-stairs-2", link = { "dkn-crypt-stairs-top" },
          src = "spf", confirmed = false },
        { id = "dkn-crypt-stairs-top", map = 1420, x = 30.242, y = 72.446, r = 4, kind = "stairs", hint = "VIA_STAIRS_NEXT",
          inside = "dkn-crypt-stairs-2", link = { "dkn-crypt-way-out" }, src = "spf", confirmed = false },
        -- outdoors, on the ground just past the top of the stairs (over the hall: IsIndoors tells the two apart);
        -- on the hill (room dkn-crypt-hill) since the fence fix below
        { id = "dkn-crypt-way-out", map = 1420, x = 30.242, y = 72.231, r = 5, kind = "path", hint = "VIA_CRYPT_OUT",
          inside = "dkn-crypt-hill", link = { "dkn-fence-west-in", "dkn-fence-east-in" }, src = "spf", confirmed = false },
        -- The fence between the hill and the chapel (bug fix 2026-11-27, v0.2.8 report "for step 2 there a fence in
        -- the way of my path": Mordo > Sarvis pointed straight through it). Shortest Path Forever's walking grid
        -- (src = "spf", 8 yd cells, own decoder, plans\tirisfal-fences\): a closed east-west line at y 67.12 from
        -- x 30.5 to 31.9, open at x 30.42 (west, the way SPF's own walk takes) and x 32.0 (east, by the square);
        -- a walled box south of it (x 30.5-30.9, y 67.3-67.9). The chapel (z 97-98, Sarvis, Elreth, Duesten,
        -- Isabella, Venya, Kayla: CMaNGOS spawns) is walled on all sides but its east door at x 31.39, y 66.20.
        -- Each pair is placed on one line through the middle of its gap (one cell centre column / row).
        { id = "dkn-fence-west-in", map = 1420, x = 30.42, y = 67.32, r = 5, kind = "gate",
          inside = "dkn-crypt-hill", link = { "dkn-fence-west-out" }, src = "spf", confirmed = false },
        { id = "dkn-fence-west-out", map = 1420, x = 30.42, y = 66.93, r = 5, kind = "gate",
          link = { "dkn-chapel-yard" }, src = "spf", confirmed = false },
        { id = "dkn-fence-east-in", map = 1420, x = 32.00, y = 67.32, r = 5, kind = "gate",
          inside = "dkn-crypt-hill", link = { "dkn-fence-east-out" }, src = "spf", confirmed = false },
        { id = "dkn-fence-east-out", map = 1420, x = 32.00, y = 66.93, r = 5, kind = "gate",
          link = { "dkn-chapel-door-out" }, src = "spf", confirmed = false },
        -- along the yard south of the chapel (its south wall and the walled strip by it block the straight way)
        { id = "dkn-chapel-yard", map = 1420, x = 31.40, y = 66.73, r = 6, kind = "path",
          link = { "dkn-chapel-door-out" }, src = "spf", confirmed = false },
        { id = "dkn-chapel-door-out", map = 1420, x = 31.50, y = 66.20, r = 3, kind = "door",
          link = { "dkn-chapel-door-in" }, src = "spf", confirmed = false },
        { id = "dkn-chapel-door-in", map = 1420, x = 31.28, y = 66.20, r = 3, kind = "door",
          inside = "dkn-chapel", src = "spf", confirmed = false },
    },
    rooms = {
        -- the hall (z 121) with the spawn spot at its north end; kept 3 yd short of Mordo's spot above it
        { id = "dkn-crypt", map = 1420, indoor = true, subzone = "Deathknell",
          poly = { { 30.501, 72.379 }, { 30.501, 71.850 }, { 30.136, 71.850 }, { 30.136, 71.552 }, { 29.627, 71.552 },
              { 29.627, 72.644 }, { 29.804, 72.644 }, { 29.804, 72.379 } },
          src = "spf", confirmed = false },
        -- the first flight (south of the hall) and its landing
        { id = "dkn-crypt-stairs", map = 1420, indoor = true, subzone = "Deathknell",
          poly = { { 30.156, 72.925 }, { 30.156, 72.379 }, { 29.804, 72.379 }, { 29.804, 72.925 } },
          src = "spf", confirmed = false },
        -- the second flight (back north, east of the first) and the floor round its top; chain: from the landing
        -- the arrow goes to the turn first, never straight across to the top
        { id = "dkn-crypt-stairs-2", map = 1420, indoor = true, chain = true, subzone = "Deathknell",
          poly = { { 30.424, 72.925 }, { 30.424, 72.379 }, { 30.156, 72.379 }, { 30.156, 72.925 } },
          src = "spf", confirmed = false },
        -- the open hill from the crypt's way out and Mordo up to the fence (outdoors): a straight line from here to
        -- the chapel or the square would cross the fence, so you leave it through one of its two gaps. Its sides
        -- are open ground: walking out of them simply ends the room (the arrow goes straight again). It holds the
        -- whole hill (west slope to x 29.4, east side to x 32.6, down to the cliffs at y 73.6; SPF grid): someone
        -- on the hill just outside a narrower wedge was sent round through a gap to reach Mordo in it
        { id = "dkn-crypt-hill", map = 1420, indoor = false, subzone = "Deathknell",
          poly = { { 30.30, 67.18 }, { 32.10, 67.18 }, { 32.60, 73.60 }, { 29.40, 73.60 }, { 29.40, 69.50 } },
          src = "spf", confirmed = false },
        -- the chapel: hall, altar end (west) and the walled side strip (south)
        { id = "dkn-chapel", map = 1420, indoor = true, subzone = "Deathknell",
          poly = { { 30.68, 65.82 }, { 31.39, 65.82 }, { 31.39, 66.58 }, { 30.68, 66.58 } },
          src = "spf", confirmed = false },
    },
}

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Contains position facts from CMaNGOS classic-db (GPL-3.0), see CREDITS.txt
-- Smart arrow connectors: Deathknell and Tirisfal Glades (uiMapID 1420). Format: packs-src\FORMAT.md, section 8.
-- src = "own": our own estimate from public facts; all confirmed = false until a tester records them on Forever
-- with /aog rec. No point is copied from any other addon's waypoint data. Only normal walkable ways.
return {
    area = "tirisfal",
    formatVersion = 1,
    license = "GPL-3.0-or-later",
    connectors = {
        -- Deathknell start crypt (bug fix 2026-11-27: "the first waypoint walks me into a wall"). An undead character
        -- wakes up in the crypt's lower room (CMaNGOS playercreateinfo: 30.03, 71.71, about 14 yd below Undertaker
        -- Mordo, who stands up at the crypt's way out at 30.24, 71.62), facing south-south-west, towards the stairs
        -- up. A straight arrow to Mordo points east-north-east, into the crypt wall. So the arrow first leads up the
        -- stairs the game faces you to, to the top of the first flight (the pair's middle, about 13 yd ahead of the
        -- spawn spot: our estimate along that facing), then on to Mordo. The kind's own text: "Take the stairs".
        { id = "dkn-crypt-stairs-in", map = 1420, x = 29.919, y = 72.051, r = 3, kind = "stairs",
          inside = "dkn-crypt", link = { "dkn-crypt-stairs-out" }, src = "own", confirmed = false },
        { id = "dkn-crypt-stairs-out", map = 1420, x = 29.891, y = 72.141, r = 3, kind = "stairs",
          link = { "dkn-crypt-stairs-in" }, src = "own", confirmed = false },
    },
    rooms = {
        -- the crypt's lower room round the spawn spot plus the first flight of stairs (about 16 x 8 yd, turned to the
        -- spawn facing, ending just short of the landing); kept narrow and off the side where the way back up to
        -- Mordo runs, so walking up there doesn't count as "in the crypt"
        { id = "dkn-crypt", map = 1420, indoor = true, subzone = "Deathknell",
          poly = { { 29.964, 71.516 }, { 30.125, 71.628 }, { 29.97, 72.123 }, { 29.81, 72.011 } },
          src = "own", confirmed = false },
    },
}

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Guide packs we plan to ship (the main window's Guides page shows them dimmed: "Coming in vX"). Information
-- about our own free guides only: text, no links (tos: no ads, no donations). Ids match packs-src\; the updater
-- keeps the list current; a planned id that is installed is not shown here.
--   ns.PlannedGuides = { { id, title, faction ("Alliance" / "Horde" / nil = both), levels = { a, b }, version, area } }
local _, ns = ...

ns.PlannedGuides = {
    { id = "normal-alliance", title = "Alliance 1-20", faction = "Alliance", levels = { 1, 20 }, version = "0.3",
        area = "Elwynn, Westfall and more" },
    { id = "normal-horde", title = "Horde 1-20", faction = "Horde", levels = { 1, 20 }, version = "0.3",
        area = "Durotar, the Barrens and more" },
    { id = "normal-start-dunmorogh", title = "Dun Morogh 1-11", faction = "Alliance", levels = { 1, 11 }, version = "0.3" },
    { id = "normal-start-teldrassil", title = "Teldrassil, Darkshore and Ashenvale 1-18", faction = "Alliance",
        levels = { 1, 18 }, version = "0.3" },
    { id = "normal-start-mulgore", title = "Mulgore 1-11", faction = "Horde", levels = { 1, 11 }, version = "0.3" },
    { id = "normal-start-tirisfal", title = "Tirisfal and Silverpine 1-14", faction = "Horde", levels = { 1, 14 },
        version = "0.3" },
}

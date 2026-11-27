-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Guide packs we plan to ship (the main window's Guides page shows them dimmed: "Coming in vX"). Information
-- about our own free guides only: text, no links (tos: no ads, no donations). Ids match packs-src\; the updater
-- keeps the list current; a planned id that is installed is not shown here.
--   ns.PlannedGuides = { { id, title, faction ("Alliance" / "Horde" / nil = both), levels = { a, b }, version, area } }
-- v0.2.5: every planned Normal route (1-60, both factions) ships now, so the list is empty and the Guides page
-- shows no "Coming soon" chip or cards.
local _, ns = ...

ns.PlannedGuides = {}

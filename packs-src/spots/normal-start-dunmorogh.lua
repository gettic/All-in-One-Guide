-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Spawn spots of pack normal-start-dunmorogh (packs-src\FORMAT.md "Spawn spots"): { x %, y %, respawn s } per
-- target (npc @ uiMapID), nearest to the step spot first. Generated from CMaNGOS classic-db spawn position and
-- respawn time facts (GPL-3.0), camps grid-snapped by tools\import\spots.lua. Never edit by hand.
return {
    pack = "normal-start-dunmorogh", formatVersion = 1, license = "GPL-3.0-or-later",
    targets = {
        ["1116@1426"] = { { 72.6, 53.8, 180 }, { 72.1, 55.1, 180 }, { 73.5, 55.1, 180 }, { 71.3, 54.3, 180 }, { 72.6, 55.8, 180 }, { 73.6, 52.8, 180 }, { 70.9, 53.2, 180 }, { 73.5, 51.2, 180 }, { 74.0, 51.5, 180 }, { 70.4, 52.3, 180 }, { 74.7, 56.3, 180 }, { 75.0, 56.6, 180 }, { 75.7, 57.8, 180 }, { 75.8, 58.7, 180 }, { 77.2, 58.2, 180 }, { 77.3, 59.8, 180 } },
        ["1117@1426"] = { { 70.8, 54.6, 180 }, { 70.6, 53.2, 180 }, { 71.0, 53.2, 180 }, { 70.6, 55.4, 180 }, { 70.4, 52.5, 180 }, { 71.2, 52.8, 180 }, { 70.8, 52.3, 180 }, { 71.2, 55.7, 180 }, { 70.7, 56.6, 180 }, { 71.8, 52.2, 180 }, { 72.4, 52.9, 180 }, { 71.7, 51.2, 180 }, { 72.9, 54.1, 180 }, { 72.5, 51.4, 180 }, { 72.9, 52.2, 180 }, { 71.8, 50.3, 180 }, { 72.2, 50.6, 180 }, { 72.0, 49.9, 180 } },
    },
}

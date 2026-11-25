-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Game facts the route checks use (packcheck's lint, the route test). Every entry says where it comes from
-- and when it was written down; "unchecked on Forever" means it is the Classic Era value and nobody has
-- confirmed it on the WoW Forever server yet (the updater agent re-checks these).
return {
    logMax = { value = 20, src = "Classic Era quest log size (C_QuestLog.GetMaxNumQuestsCanAccept)", seen = "2026-11",
        note = "unchecked on Forever; the addon reads the real value in game" },
    maxLevel = { value = 60, src = "Classic Era level cap", seen = "2026-11", note = "unchecked on Forever" },
    -- R4 (plans\v0.2\tos-plan.md): the instance lock is a limit, not a target. Routes never plan runs up
    -- to it; packcheck warns when the same dungeon is visited more than 2 times in a row.
    instancesPerHour = { value = 5, src = "Classic Era instance limit", seen = "2026-11",
        note = "a limit, not a target; unchecked on Forever" },
    dungeonRepeatsWarn = { value = 2, src = "our rule (tos R4)", seen = "2026-11" },
    -- XP from level n to n + 1 (Classic Era table), for the route test's XP model; only quests with an
    -- `xp` value count, so the model is a floor, not a forecast.
    xpToNext = { src = "Classic Era experience table", seen = "2026-11", note = "unchecked on Forever",
        value = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
                  8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200 } },
    levelJumpWarn = { value = 3, src = "our rule: a route never asks for more than 3 levels at once", seen = "2026-11" },
}

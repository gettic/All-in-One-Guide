-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- uiMapIDs of the Classic Era world (continents, zones, capital cities) that routes may use. packcheck warns on
-- a map id that isn't here (a typo, or a map not listed yet: add it). Ids only; the game gives the names.
-- Source: the Classic Era UiMap ids (warcraft.wiki.gg, UiMapID); seen 2026-11. 1414-1415 are the continents,
-- 1411-1458 the zones and cities.
local maps = {}
for id = 1411, 1458 do maps[id] = true end
return maps

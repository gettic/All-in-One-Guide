-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- uiMapIDs of the Classic Era world (continents, zones, capital cities) that routes may use. packcheck warns on
-- a map id that isn't here (a typo, or a map not listed yet: add it). Ids only; the game gives the names.
-- Source: the Classic Era UiMap ids (warcraft.wiki.gg, UiMapID); seen 2026-11. 1414-1415 are the continents,
-- 1411-1458 the zones and cities.
-- WoW Forever's new zone maps (not on the wiki yet): 2482 (Mount Hyjal), 2548 (the Riverglades). Source: QuestieDB
-- (GPL-3.0), flavour Forever, support\Forever\Zones\areaIdToUiMapId.lua (areas 616 and 16591); seen 2026-11-27.
local maps = {}
for id = 1411, 1458 do maps[id] = true end
maps[2482] = true
maps[2548] = true
return maps

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Forever-only quest items (not in CMaNGOS classic-db), input for tools\import\questitems.lua. Bare ids only.
-- Every row was read by hand from the foreverdb.net item page in `from` (item, what it starts, what drops it,
-- unique) and the quest page of `q` (objective item named there); 2026-11-25. QuestieDB Forever was used only
-- to find which item ids to look up, never as the source. Nothing here is confirmed in game yet.
-- again: false when one named mob drops it (a single unique source) or the quest hands it out.
-- Left out (unclear): 247857 (second Nibbled-On Book; foreverdb: source unknown, no quest named),
-- 279935 (91775 hand-out item: not on foreverdb), and the item ids of the other Forever quests in
-- plans\forever-new-quests\report.md section C (not looked up yet).
return {
    -- Elwynn, the Paxton book chain
    { item = 247834, q = 91741, r = "start", kind = "drop", again = true, from = "https://foreverdb.net/item/247834" },
    { item = 247839, q = 91743, r = "obj", kind = "drop", again = true, from = "https://foreverdb.net/item/247839" },
    { item = 247886, q = 91752, r = "obj", kind = "drop", again = false, from = "https://foreverdb.net/item/247886" },
    { item = 247970, q = 91772, r = "use", kind = "given", again = false, from = "https://foreverdb.net/item/247970" },
    { item = 248001, q = 91775, r = "obj", kind = "drop", again = true, from = "https://foreverdb.net/item/248001" },
    { item = 248002, q = 91775, r = "obj", kind = "drop", again = false, from = "https://foreverdb.net/item/248002" },
    { item = 248003, q = 91777, r = "obj", kind = "drop", again = false, from = "https://foreverdb.net/item/248003" },
    { item = 248004, q = 91777, r = "obj", kind = "drop", again = false, from = "https://foreverdb.net/item/248004" },
    -- Elwynn, other
    { item = 286214, q = 99130, r = "obj", kind = "object", again = true, from = "https://foreverdb.net/item/286214" },
    { item = 286215, q = 99130, r = "obj", kind = "drop", again = true, from = "https://foreverdb.net/item/286215" },
    { item = 247826, q = 91740, r = "start", kind = "drop", again = false, from = "https://foreverdb.net/item/247826" },
    { item = 247862, q = 91746, r = "start", kind = "drop", again = false, from = "https://foreverdb.net/item/247862" },
    -- Durotar
    { item = 275722, q = 96876, r = "start", kind = "drop", again = false, from = "https://foreverdb.net/item/275722" },
    { item = 277661, q = 97281, r = "start", kind = "drop", again = true, from = "https://foreverdb.net/item/277661" },
    { item = 275723, q = 96877, r = "start", kind = "drop", again = false, from = "https://foreverdb.net/item/275723" },
    -- Dun Morogh
    { item = 268548, q = 95213, r = "start", kind = "drop", again = true, from = "https://foreverdb.net/item/268548" },
    { item = 274268, q = 96391, r = "start", kind = "drop", again = true, from = "https://foreverdb.net/item/274268" },
    -- Teldrassil
    { item = 277190, q = 97236, r = "start", kind = "drop", again = false, from = "https://foreverdb.net/item/277190" },
    -- Tirisfal
    { item = 268812, q = 95328, r = "start", kind = "drop", again = false, from = "https://foreverdb.net/item/268812" },
    -- Mulgore
    { item = 281031, q = 98424, r = "start", kind = "drop", again = false, from = "https://foreverdb.net/item/281031" },
    -- Loch Modan
    { item = 278049, q = 86613, r = "start", kind = "object", again = true, from = "https://foreverdb.net/item/278049" },
    -- The Barrens
    { item = 253710, q = 92706, r = "obj", kind = "drop", again = false, from = "https://foreverdb.net/item/253710" },
}

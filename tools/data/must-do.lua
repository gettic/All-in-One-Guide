-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Must-do quests: quests every Normal route should fit in, whatever the mode (for example a quest line that gives
-- something every player wants). The updater keeps the list current; the route-writer places each one with the
-- least travel. Checker data only: it is not in the addon (the "Must-do" page comes in v0.4).
-- tools\packcheck.lua: a pack of the quest's faction whose `levels` overlap the entry's `levels` and that has no
-- accept + turn-in for it (and no `mustDoSkip = { [quest] = "why" }` in its header) gets a WARN; in the chain check
-- of the build (all shipped packs of a faction together) a quest that no pack has is an ERROR.
--   { quest = <id>, faction = "Alliance" | "Horde" | nil (both), levels = { a, b }, cond = "<condition>" (optional,
--     e.g. "class=WARLOCK"), why = "<short reason>", src = "<source tag>", seen = "YYYY-MM" }
return {
}

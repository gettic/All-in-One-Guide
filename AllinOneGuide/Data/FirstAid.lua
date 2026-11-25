-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 First Aid facts for the dynamic "level up" steps (Engine\FirstAid.lua). Bare ids and numbers only;
-- names come from the game. Sources: the Classic First Aid recipe and trainer pages on warcraft.wiki.gg
-- and the Forever notes in plans\v0.3\class-blocks\blocks-weapons.lua (Minor Healing Potion is a First Aid
-- recipe on Forever; First Aid Kit at 20 from the camping quest). Game facts (c) Blizzard Entertainment.
-- confirmed = false: not checked on Forever yet (ranges, caps, costs and the Expert trainers especially).
local _, ns = ...

ns.FirstAidData = {
    skillLine = 129,                    -- First Aid's skill line id (SkillLineAttributes.skillID)
    cloth = { linen = 2589, wool = 2592, silk = 4306 },
    -- the bandage to make from `from` until `to` (where it stops giving points reliably), cloth per craft
    recipes = {
        { item = 1251, cloth = 2589, per = 1, from = 1, to = 40, confirmed = false },     -- Linen Bandage
        { item = 2581, cloth = 2589, per = 2, from = 40, to = 80, confirmed = false },    -- Heavy Linen Bandage
        { item = 3530, cloth = 2592, per = 1, from = 80, to = 115, confirmed = false },   -- Wool Bandage
        { item = 3531, cloth = 2592, per = 2, from = 115, to = 150, confirmed = false },  -- Heavy Wool Bandage
        { item = 6450, cloth = 4306, per = 1, from = 150, to = 180, confirmed = false },  -- Silk Bandage
        { item = 6451, cloth = 4306, per = 2, from = 180, to = 210, confirmed = false },  -- Heavy Silk Bandage
    },
    -- ranks: train `name` once the skill reaches `at`; it lifts the cap to `cap`. trainers = npc ids
    -- (Journeyman: the capital First Aid trainers; Expert: a book from these two, Classic facts)
    ranks = {
        { key = "JOURNEYMAN", at = 50, cap = 150, trainers = { 2327, 5150, 4211, 3373, 4591, 2798 }, confirmed = false },
        { key = "EXPERT", at = 125, cap = 225, trainers = { 2805, 4878 }, book = true, confirmed = false },
        { key = "ARTISAN", at = 200, cap = 300, trainers = {}, confirmed = false },
    },
    apprenticeCap = 75,                 -- confirmed = false (Forever may differ)
}

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The guide pack addons (v0.2.5): which packs ship, and in which folder. tools\build.lua writes each folder next to
-- AllinOneGuide\ (its .toc, Routes\*.lua, LICENSE, CREDITS.txt) and the index AllinOneGuide\Data\KnownPacks.lua.
-- A pack that isn't listed here doesn't ship (it is still checked; --all builds it into its faction's folder).
-- Each folder is LoadOnDemand and depends on AllinOneGuide: the guide loads only the folder a character needs.
-- `version` is the folder's own version (/commit sets it at a release, tag prefix `alliance-v` / `horde-v`).
-- `icon` (optional): a texture path in the folder (own art only); without it the .toc has no IconTexture line.
return {
    {
        folder = "AllinOneGuide_Alliance", faction = "Alliance", tag = "alliance-v", version = "1.0.0",
        title = "All-in-One Guide: Alliance routes",
        notes = "Alliance leveling routes for All-in-One Guide. Loaded only when the guide needs them.",
        packs = { "demo-elwynn", "normal-start-dunmorogh", "normal-start-teldrassil", "normal-alliance", "normal-alliance-20-30", "normal-alliance-30-40", "normal-alliance-40-50", "normal-alliance-50-60" },   -- (demo kept one more version: beta saves)
    },
    {
        folder = "AllinOneGuide_Horde", faction = "Horde", tag = "horde-v", version = "1.0.0",
        title = "All-in-One Guide: Horde routes",
        notes = "Horde leveling routes for All-in-One Guide. Loaded only when the guide needs them.",
        packs = { "demo-durotar", "normal-start-mulgore", "normal-start-tirisfal", "normal-horde", "normal-horde-20-30", "normal-horde-30-40", "normal-horde-40-50", "normal-horde-50-60" },   -- (demo kept one more version: beta saves)
    },
}

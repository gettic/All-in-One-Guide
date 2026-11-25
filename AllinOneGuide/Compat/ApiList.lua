-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The game API we use, as data. Source of truth: plans\api-16001.md (filled from Blizzard's UI source
-- 1.60.1.70959; "doc" = the Blizzard_APIDocumentationGenerated file, "xml" = a FrameXML file).
-- Compat.lua resolves these once at load; the self-test probe (M4) reads the same list and only checks
-- that each one exists and has the right type. It never calls anything protected.
--   feature: the feature that is switched off when this entry is missing (nil = report only)
--   kind:    "function", "table" or "value"
--   secret:  "args" = SecretArguments AllowedWhenUntainted (fine from our own untainted code),
--            "returns" = may return secret values (guard with issecretvalue)
--   later:   recorded now, used from that version on
local _, ns = ...

ns.ApiList = {
    -- core and timers
    { id = "GetTime", path = "GetTime", feature = "core", kind = "function", src = "doc SystemTimeDocumentation" },
    { id = "debugprofilestop", path = "debugprofilestop", feature = "core", kind = "function", src = "doc FrameScriptDocumentation" },
    { id = "CreateFrame", path = "CreateFrame", feature = "core", kind = "function", src = "xml (used everywhere)" },
    { id = "TimerAfter", path = "C_Timer.After", feature = "core", kind = "function", src = "doc UITimerDocumentation" },
    { id = "TimerTicker", path = "C_Timer.NewTicker", feature = "core", kind = "function", src = "doc UITimerDocumentation" },
    { id = "InCombatLockdown", path = "InCombatLockdown", feature = "core", kind = "function", src = "doc RestrictedActionsDocumentation" },
    { id = "GetBuildInfo", path = "GetBuildInfo", kind = "function", src = "doc BuildDocumentation" },
    { id = "GetLocale", path = "GetLocale", kind = "function", src = "doc LocaleDocumentation" },
    { id = "IsLoggedIn", path = "IsLoggedIn", kind = "function", src = "doc PlayerScriptDocumentation" },
    { id = "issecretvalue", path = "issecretvalue", kind = "function", src = "doc FrameScriptDocumentation" },
    { id = "ProjectID", path = "WOW_PROJECT_ID", kind = "value", src = "xml Blizzard_ProjectConstants\\Camelot\\ProjectConstants.lua (= 18)" },
    { id = "ProjectCamelot", path = "WOW_PROJECT_CAMELOT", kind = "value", src = "xml Blizzard_ProjectConstants\\Camelot\\ProjectConstants.lua" },

    -- add-ons (module registry, own version)
    { id = "AddOnMetadata", path = "C_AddOns.GetAddOnMetadata", kind = "function", secret = "args", src = "doc AddOnsDocumentation" },
    { id = "IsAddOnLoaded", path = "C_AddOns.IsAddOnLoaded", feature = "modules", kind = "function", src = "doc AddOnsDocumentation" },
    { id = "LoadAddOn", path = "C_AddOns.LoadAddOn", feature = "modules", kind = "function", secret = "args", src = "doc AddOnsDocumentation" },

    -- the player
    { id = "UnitLevel", path = "UnitLevel", feature = "player", kind = "function", src = "doc UnitDocumentation" },
    { id = "UnitClass", path = "UnitClass", feature = "player", kind = "function", src = "doc UnitDocumentation" },
    { id = "UnitRace", path = "UnitRace", feature = "player", kind = "function", src = "doc UnitDocumentation" },
    { id = "UnitFactionGroup", path = "UnitFactionGroup", feature = "player", kind = "function", src = "doc UnitDocumentation" },
    { id = "UnitSex", path = "UnitSex", feature = "player", kind = "function", src = "doc UnitDocumentation" },
    { id = "UnitName", path = "UnitName", feature = "player", kind = "function", src = "doc UnitDocumentation" },
    { id = "RealmName", path = "GetNormalizedRealmName", feature = "player", kind = "function", src = "doc PlayerScriptDocumentation" },
    { id = "UnitOnTaxi", path = "UnitOnTaxi", kind = "function", src = "doc UnitDocumentation" },
    { id = "IsIndoors", path = "IsIndoors", kind = "function", src = "doc PlayerScriptDocumentation" },

    -- quest log
    { id = "QuestNumEntries", path = "C_QuestLog.GetNumQuestLogEntries", feature = "questlog", kind = "function", src = "doc QuestLogDocumentation" },
    { id = "QuestInfo", path = "C_QuestLog.GetInfo", feature = "questlog", kind = "function", secret = "args", src = "doc QuestLogDocumentation" },
    { id = "QuestObjectives", path = "C_QuestLog.GetQuestObjectives", feature = "questlog", kind = "function", secret = "args", src = "doc QuestLogDocumentation" },
    { id = "QuestIsComplete", path = "C_QuestLog.IsComplete", feature = "questlog", kind = "function", secret = "args", src = "doc QuestLogDocumentation" },
    { id = "QuestReady", path = "C_QuestLog.ReadyForTurnIn", feature = "questlog", kind = "function", secret = "args", src = "doc QuestLogDocumentation" },
    { id = "QuestOnQuest", path = "C_QuestLog.IsOnQuest", feature = "questlog", kind = "function", src = "doc QuestLogDocumentation" },
    { id = "QuestFlagged", path = "C_QuestLog.IsQuestFlaggedCompleted", feature = "questlog", kind = "function", secret = "args", src = "doc QuestLogDocumentation" },
    { id = "QuestLogIndex", path = "C_QuestLog.GetLogIndexForQuestID", kind = "function", secret = "args", src = "doc QuestLogDocumentation" },
    { id = "QuestFailed", path = "C_QuestLog.IsFailed", kind = "function", src = "doc QuestLogDocumentation" },
    { id = "QuestMax", path = "C_QuestLog.GetMaxNumQuestsCanAccept", feature = "questlimit", kind = "function", src = "doc QuestLogDocumentation" },
    { id = "QuestTitle", path = "C_QuestLog.GetTitleForQuestID", feature = "names", kind = "function", src = "doc QuestLogDocumentation" },
    { id = "QuestRequest", path = "C_QuestLog.RequestLoadQuestByID", feature = "names", kind = "function", src = "doc QuestLogDocumentation" },

    -- position (only the player's own position, only these calls; nothing else is used when they return nil)
    { id = "MapForUnit", path = "C_Map.GetBestMapForUnit", feature = "position", kind = "function", secret = "args", src = "doc MapDocumentation" },
    { id = "MapPlayerPos", path = "C_Map.GetPlayerMapPosition", feature = "position", kind = "function", secret = "args", src = "doc MapDocumentation" },
    { id = "Vector2D", path = "CreateVector2D", feature = "worldpos", kind = "function", src = "xml Blizzard_SharedXML\\Vector2D.lua" },
    { id = "MapWorldPos", path = "C_Map.GetWorldPosFromMapPos", feature = "worldpos", kind = "function", secret = "args", src = "doc MapDocumentation" },
    { id = "PlayerFacing", path = "GetPlayerFacing", feature = "facing", kind = "function", src = "doc PlayerScriptDocumentation (nilable)" },

    -- v0.2 M1: XP, death, instance, hearthstone bind (plans\v0.2\api-16001-v0.2.md)
    { id = "UnitXP", path = "UnitXP", feature = "xp", kind = "function", src = "doc UnitDocumentation" },
    { id = "UnitXPMax", path = "UnitXPMax", feature = "xp", kind = "function", src = "doc UnitDocumentation" },
    { id = "DeadOrGhost", path = "UnitIsDeadOrGhost", kind = "function", src = "doc UnitDocumentation" },
    { id = "InInstance", path = "IsInInstance", kind = "function", src = "doc InstanceDocumentation" },
    { id = "BindLocation", path = "GetBindLocation", feature = "hearth", kind = "function", src = "doc PlayerScriptDocumentation" },

    -- v0.2 M2: the step button, reminders, flight paths (plans\v0.2\api-16001-v0.2.md)
    { id = "ItemIcon", path = "C_Item.GetItemIconByID", feature = "stepbutton", kind = "function", secret = "args", src = "doc ItemDocumentation" },
    { id = "ItemName", path = "C_Item.GetItemNameByID", kind = "function", secret = "args", src = "doc ItemDocumentation" },
    { id = "ItemCooldown", path = "C_Item.GetItemCooldown", kind = "function", secret = "args", src = "doc ItemDocumentation" },
    { id = "ItemInRange", path = "C_Item.IsItemInRange", kind = "function", secret = "args", src = "doc ItemDocumentation (nilable)" },
    { id = "TaxiForMap", path = "C_TaxiMap.GetTaxiNodesForMap", feature = "taxi", kind = "function", src = "doc TaxiMapDocumentation" },
    { id = "TaxiAllNodes", path = "C_TaxiMap.GetAllTaxiNodes", kind = "function", src = "doc TaxiMapDocumentation" },
    { id = "BindingKey", path = "GetBindingKey", kind = "function", src = "xml Blizzard_ActionBar\\Shared\\ActionButton.lua" },
    { id = "PlaySound", path = "PlaySound", kind = "function", src = "doc SoundDocumentation" },

    -- v0.2 M3: the corpse arrow
    { id = "UnitIsGhost", path = "UnitIsGhost", kind = "function", src = "doc UnitDocumentation" },
    { id = "CorpsePos", path = "C_DeathInfo.GetCorpseMapPosition", kind = "function", secret = "args", src = "doc DeathInfoDocumentation (nilable vector2)" },

    -- v0.2 M3 part 2: hooks, map pins, minimap pins, step clicks, notice snooze (plans\v0.2\api-16001-v0.2.md)
    { id = "hooksecurefunc", path = "hooksecurefunc", feature = "hooks", kind = "function", src = "xml (used across FrameXML; not in the docs)" },
    { id = "WorldMapFrame", path = "WorldMapFrame", feature = "mappins", kind = "table", src = "xml Blizzard_WorldMap\\Blizzard_WorldMap.xml" },
    { id = "MapProviderMixin", path = "MapCanvasDataProviderMixin", feature = "mappins", kind = "table", src = "xml Blizzard_MapCanvas\\MapCanvas_DataProviderBase.lua" },
    { id = "CreateFromMixins", path = "CreateFromMixins", feature = "mappins", kind = "function", src = "xml Blizzard_SharedXMLBase\\Mixin.lua" },
    { id = "Minimap", path = "Minimap", feature = "minimappins", kind = "table", src = "xml Blizzard_Minimap\\Mainline\\Minimap.xml" },
    { id = "MinimapRadius", path = "C_Minimap.GetViewRadius", feature = "minimappins", kind = "function", src = "doc MinimapDocumentation" },
    { id = "CVarBool", path = "C_CVar.GetCVarBool", kind = "function", src = "doc CVarDocumentation" },
    { id = "MapInfo", path = "C_Map.GetMapInfo", kind = "function", src = "doc MapDocumentation" },
    { id = "QuestLink", path = "GetQuestLink", kind = "function", src = "xml Blizzard_ChatFrameBase\\Shared\\ChatFrameUtil.lua (not in the docs)" },
    { id = "ChatInsertLink", path = "ChatFrameUtil.InsertLink", kind = "function", src = "xml Blizzard_ChatFrameBase\\Mainline\\ChatFrameUtilOverrides.lua" },
    { id = "ChatActiveWindow", path = "ChatFrameUtil.GetActiveWindow", kind = "function", src = "xml Blizzard_ChatFrameBase\\Shared\\ChatFrameUtil.lua" },
    { id = "OpenWorldMap", path = "OpenWorldMap", kind = "function", src = "xml Blizzard_WorldMap\\Blizzard_WorldMap.lua" },
    { id = "IsShiftKeyDown", path = "IsShiftKeyDown", kind = "function", src = "doc InputDocumentation" },
    { id = "IsControlKeyDown", path = "IsControlKeyDown", kind = "function", src = "doc InputDocumentation" },
    { id = "IsAltKeyDown", path = "IsAltKeyDown", kind = "function", src = "doc InputDocumentation" },
    { id = "GetCursorPosition", path = "GetCursorPosition", kind = "function", src = "doc InputDocumentation" },
    { id = "GetServerTime", path = "GetServerTime", kind = "function", src = "doc SystemTimeDocumentation" },

    -- v0.2 M4: our one entry in Options > AddOns (Blizzard_Settings_Shared\Blizzard_Settings.lua, loaded with
    -- the UI, not on demand: its .toc has no LoadOnDemand), the button initializer (Blizzard_SettingControls.lua).
    -- 2026-11-25: the settings themselves moved into the main window, so the proxy / control calls are gone.
    { id = "SetRegCat", path = "Settings.RegisterVerticalLayoutCategory", feature = "settings", kind = "function", src = "xml Blizzard_Settings_Shared\\Blizzard_Settings.lua" },
    { id = "SetRegAddOn", path = "Settings.RegisterAddOnCategory", feature = "settings", kind = "function", src = "xml Blizzard_Settings_Shared\\Blizzard_Settings.lua" },
    { id = "SetButtonInit", path = "CreateSettingsButtonInitializer", kind = "function", src = "xml Blizzard_Settings_Shared\\Blizzard_SettingControls.lua" },
    -- v0.2 M4: the minimap button (Minimap's size / scale; the cursor for dragging around the ring)
    { id = "MinimapButton", path = "Minimap", feature = "minimap", kind = "table", src = "xml Blizzard_Minimap\\Mainline\\Minimap.xml" },
    -- (GetMinimapShape is not listed: minimap addons define it, not Blizzard; UI\Minimap.lua looks it up each time.)

    -- v0.2 M5 / M6: NPC ids from a GUID (report evidence, dev recorder; never Player- or Pet- GUIDs)
    { id = "UnitGUID", path = "UnitGUID", kind = "function", secret = "returns", src = "doc UnitDocumentation" },
    -- v0.2 M6: dev recorder and /aog where (report only: a missing one just records less)
    { id = "LootNum", path = "GetNumLootItems", kind = "function", src = "xml Blizzard_UIPanels_Game\\Mainline\\LootFrame.lua" },
    { id = "LootLink", path = "GetLootSlotLink", kind = "function", src = "xml Blizzard_UIPanels_Game\\Mainline\\LootFrame.lua" },
    { id = "LootSource", path = "GetLootSourceInfo", kind = "function", secret = "returns", src = "warcraft.wiki.gg API_GetLootSourceInfo (lists Forever 1.60.1; not used in the UI source)" },
    { id = "InstanceInfo", path = "GetInstanceInfo", kind = "function", src = "xml Blizzard_FrameXML\\InstanceDifficulty.lua (8th return = instance map id)" },
    { id = "QuestSelected", path = "C_QuestLog.GetSelectedQuest", kind = "function", src = "doc QuestLogDocumentation" },

    -- NPC talk helper (plans\npc-talk-helper\plan.md): read only; hooked with hooksecurefunc / HookScript, never
    -- clicked. A missing frame = that window gets no marks; a missing quest-id read = the helper is off.
    { id = "GossipFrame", path = "GossipFrame", kind = "table", src = "xml Blizzard_UIPanels_Game\\Mainline\\GossipFrame.xml (GossipFrameMixin:Update)" },
    { id = "QuestGreetingPanel", path = "QuestFrameGreetingPanel", kind = "table", src = "xml Blizzard_UIPanels_Game\\Mainline\\QuestFrame.xml (titleButtonPool)" },
    { id = "QuestDetailPanel", path = "QuestFrameDetailPanel", kind = "table", src = "xml Blizzard_UIPanels_Game\\Mainline\\QuestFrame.xml:196" },
    { id = "QuestID", path = "GetQuestID", feature = "npchelper", kind = "function", src = "xml Blizzard_UIPanels_Game\\Mainline\\QuestFrame.lua:48 (not in the docs)" },
    { id = "ActiveQuestID", path = "GetActiveQuestID", feature = "npchelper", kind = "function", src = "xml Blizzard_UIPanels_Game\\Mainline\\QuestFrame.lua:362 (not in the docs)" },
    { id = "AvailQuestInfo", path = "GetAvailableQuestInfo", feature = "npchelper", kind = "function", src = "xml Blizzard_UIPanels_Game\\Mainline\\QuestFrame.lua:393 (5th return = questID; not in the docs)" },
    { id = "ScrollInitCb", path = "ScrollUtil.AddInitializedFrameCallback", kind = "function", src = "xml Blizzard_SharedXML\\Shared\\Scroll\\ScrollUtil.lua:21 (callbacks run through secureexecuterange)" },
    { id = "GossipAvail", path = "C_GossipInfo.GetAvailableQuests", kind = "function", src = "doc GossipInfoDocumentation.lua:33 (self-check only)" },
    { id = "GossipActive", path = "C_GossipInfo.GetActiveQuests", kind = "function", src = "doc GossipInfoDocumentation.lua:24 (self-check only)" },

    -- Tooltip step line (plans\tooltip-step\plan.md): our own lines after Blizzard builds a unit / object tooltip.
    -- Enum.TooltipDataType / TooltipDataLineType are read in UI\TooltipStep.lua (pcall; missing = no post-call).
    { id = "TipPostCall", path = "TooltipDataProcessor.AddTooltipPostCall", feature = "tooltipstep", kind = "function", src = "xml Blizzard_SharedXMLGame\\Tooltip\\TooltipDataHandler.lua:199 (insecure callers forced insecure, 181-193)" },

    -- bags, rules
    { id = "ItemCount", path = "C_Item.GetItemCount", feature = "bags", kind = "function", secret = "args", src = "doc ItemDocumentation" },
    { id = "ItemCountOld", path = "GetItemCount", kind = "function", src = "xml (global before C_Item; fallback only)" },
    -- v0.2 First Aid: skill lines, read only (never Expand / CollapseSkillHeader; tos plans\first-aid)
    { id = "SkillLines", path = "C_SkillInfo.GetNumSkillLines", kind = "function", src = "doc SkillInfoDocumentation (line 41); Camelot SkillsFrame.lua:153" },
    { id = "SkillLineInfo", path = "C_SkillInfo.GetSkillLineInfo", kind = "function", secret = "args", src = "doc SkillInfoDocumentation (line 59); Camelot SkillsFrame.lua:154" },
    { id = "SkillLineByID", path = "C_SkillInfo.GetSkillLineInfoByID", kind = "function", secret = "args", src = "doc SkillInfoDocumentation (line 74); Camelot PaperDollFrame.lua:730" },
    -- v0.2 quest items in the bags (read only; missing = no quest-item advice, nothing else changes)
    { id = "BagSlots", path = "C_Container.GetContainerNumSlots", kind = "function", secret = "args", src = "doc ContainerDocumentation (line 313)" },
    { id = "BagItemID", path = "C_Container.GetContainerItemID", kind = "function", secret = "args", src = "doc ContainerDocumentation (line 175)" },
    { id = "BagQuestInfo", path = "C_Container.GetContainerItemQuestInfo", kind = "function", secret = "args", src = "doc ContainerDocumentation (line 281; ItemQuestInfo line 817)" },
    { id = "Hardcore", path = "C_GameRules.IsHardcoreActive", feature = "hardcore", kind = "function", secret = "returns", src = "doc GameRulesDocumentation" },

    -- the window and arrow (M3)
    { id = "UIParent", path = "UIParent", feature = "ui", kind = "table", src = "xml (parent across the UI source)" },
    { id = "CreateColor", path = "CreateColor", feature = "ui", kind = "function", src = "xml Blizzard_SharedXMLBase\\Color.lua" },
    { id = "GameTooltip", path = "GameTooltip", kind = "table", src = "xml Blizzard_GameTooltip\\Mainline\\GameTooltip.xml" },
    -- ReloadUI / C_UI.Reload: PROTECTED on 16001 (ADDON_ACTION_BLOCKED from addon code, beta.1). Not listed so
    -- it is never resolved; the player types /reload. The offline tester traps both (world\interact.lua).
    { id = "SpecialFrames", path = "UISpecialFrames", kind = "table", src = "xml Blizzard_UIParentPanelManager\\Shared\\UIParentPanelManager.lua" },

    -- the self-test's perf check (M4; only when the player runs it or once per new version)
    { id = "UpdateMemory", path = "UpdateAddOnMemoryUsage", kind = "function", src = "doc PerformanceDocumentation" },
    { id = "AddOnMemory", path = "GetAddOnMemoryUsage", kind = "function", secret = "args", src = "doc PerformanceDocumentation" },

    -- recorded for later versions (probe only)
    { id = "SetUserWaypoint", path = "C_Map.SetUserWaypoint", kind = "function", later = "v0.2", src = "doc MapDocumentation" },
    { id = "SuperTrack", path = "C_SuperTrack.SetSuperTrackedUserWaypoint", kind = "function", later = "v0.2", src = "doc SuperTrackManagerDocumentation" },
    { id = "AtlasInfo", path = "C_Texture.GetAtlasInfo", kind = "function", src = "doc TextureUtilsDocumentation (atlas check helper, v0.1.1)" },
    { id = "Spec", path = "C_SpecializationInfo.GetSpecialization", kind = "function", later = "v0.4", src = "doc SpecializationInfoDocumentation" },
    { id = "UnitHealth", path = "UnitHealth", kind = "function", secret = "returns", later = "not used (tos R1)", src = "doc UnitDocumentation" },
    { id = "ConfirmBinder", path = "ConfirmBinder", kind = "function", later = "v0.3 (player's click only)", src = "doc UnitDocumentation" },
    { id = "BinderInteraction", path = "C_PlayerInteractionManager.ConfirmationInteraction", kind = "function", later = "v0.3 (player's click only)", src = "doc PlayerInteractionManagerDocumentation" },
    { id = "issecurevariable", path = "issecurevariable", kind = "function", later = "v0.1 probe (not in the UI source docs)", src = "not found in the 1.60.1 UI source" },
}

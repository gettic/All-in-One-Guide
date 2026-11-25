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

    -- bags, rules
    { id = "ItemCount", path = "C_Item.GetItemCount", feature = "bags", kind = "function", secret = "args", src = "doc ItemDocumentation" },
    { id = "Hardcore", path = "C_GameRules.IsHardcoreActive", feature = "hardcore", kind = "function", secret = "returns", src = "doc GameRulesDocumentation" },

    -- the window and arrow (M3)
    { id = "UIParent", path = "UIParent", feature = "ui", kind = "table", src = "xml (parent across the UI source)" },
    { id = "CreateColor", path = "CreateColor", feature = "ui", kind = "function", src = "xml Blizzard_SharedXMLBase\\Color.lua" },
    { id = "GameTooltip", path = "GameTooltip", kind = "table", src = "xml Blizzard_GameTooltip\\Mainline\\GameTooltip.xml" },
    { id = "ReloadUI", path = "ReloadUI", kind = "function", src = "xml Blizzard_ChatFrameBase\\Shared\\SlashCommands.lua" },
    { id = "SpecialFrames", path = "UISpecialFrames", kind = "table", src = "xml Blizzard_UIParentPanelManager\\Shared\\UIParentPanelManager.lua" },

    -- the self-test's perf check (M4; only when the player runs it or once per new version)
    { id = "UpdateMemory", path = "UpdateAddOnMemoryUsage", kind = "function", src = "doc PerformanceDocumentation" },
    { id = "AddOnMemory", path = "GetAddOnMemoryUsage", kind = "function", secret = "args", src = "doc PerformanceDocumentation" },

    -- recorded for later versions (probe only)
    { id = "SetUserWaypoint", path = "C_Map.SetUserWaypoint", kind = "function", later = "v0.2", src = "doc MapDocumentation" },
    { id = "SuperTrack", path = "C_SuperTrack.SetSuperTrackedUserWaypoint", kind = "function", later = "v0.2", src = "doc SuperTrackManagerDocumentation" },
    { id = "AtlasInfo", path = "C_Texture.GetAtlasInfo", kind = "function", later = "v0.3", src = "doc TextureUtilsDocumentation" },
    { id = "Spec", path = "C_SpecializationInfo.GetSpecialization", kind = "function", later = "v0.4", src = "doc SpecializationInfoDocumentation" },
    { id = "UnitHealth", path = "UnitHealth", kind = "function", secret = "returns", later = "v0.2", src = "doc UnitDocumentation" },
    { id = "ConfirmBinder", path = "ConfirmBinder", kind = "function", later = "v0.3 (player's click only)", src = "doc UnitDocumentation" },
    { id = "BinderInteraction", path = "C_PlayerInteractionManager.ConfirmationInteraction", kind = "function", later = "v0.3 (player's click only)", src = "doc PlayerInteractionManagerDocumentation" },
    { id = "issecurevariable", path = "issecurevariable", kind = "function", later = "v0.1 probe (not in the UI source docs)", src = "not found in the 1.60.1 UI source" },
}

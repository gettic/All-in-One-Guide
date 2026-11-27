-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- One declarative settings schema. It feeds the title menu, slash commands and the settings panel
-- (UI\Settings.lua), and the reset per page and the export allowlist. Defaults are read through a
-- metatable, so only values the player changed are written to the save.
--   key, scope ("account" | "char"), kind ("bool" | "number" | "choice"), default, min / max / step / choices,
--   export (may go into a settings export later; never for personal things)
--   v0.2 M4: page ("general" | "window" | "arrow" | "map" | "steps" | "advanced"; nil = not on a settings page;
--   the pages are the main window's Settings group, UI\HubSettings.lua),
--   label / tip (locale keys; default "SET_<KEY>" / "SETTIP_<KEY>"; the panel adds the default to the tip),
--   combat (true = only changed out of combat: the change waits for the combat queue),
--   choiceLabels (choice value -> locale key)
-- Recommended defaults (BUILD-PLAN M4): arrow on, small window off, sounds off, minimap button on.
local _, ns = ...
local S = {}
ns.Settings = S

S.PAGES = { "general", "window", "arrow", "map", "steps", "advanced" }

S.schema = {
    { key = "lang", scope = "account", kind = "choice", default = "auto", choices = { "auto", "en", "da" }, export = true,
        page = "general", choiceLabels = { auto = "CHOICE_LANG_AUTO", en = "CHOICE_LANG_EN", da = "CHOICE_LANG_DA" } },
    { key = "useOnChar", scope = "char", kind = "bool", default = true, export = false, page = "general" },
    { key = "minimap", scope = "account", kind = "bool", default = true, export = true, page = "general" },
    { key = "quiet", scope = "account", kind = "bool", default = false, export = true, page = "general" },
    { key = "reminder", scope = "account", kind = "choice", default = "glow", choices = { "off", "glow", "text", "sound" }, export = true,
        page = "steps", choiceLabels = { off = "REMINDER_OFF", glow = "REMINDER_GLOW", text = "REMINDER_TEXT", sound = "REMINDER_SOUND" } },
    { key = "offInBG", scope = "account", kind = "bool", default = false, export = true, page = "general" },
    { key = "offInRaid", scope = "account", kind = "bool", default = false, export = true, page = "general" },
    { key = "reducedMotion", scope = "account", kind = "bool", default = false, export = true, page = "general" },
    -- v0.2: optional First Aid "level up" lines from your cloth and skill (Engine\FirstAid.lua)
    { key = "firstAidSteps", scope = "account", kind = "bool", default = true, export = true, page = "steps" },
    -- NPC talk helper (UI\NpcHelper.lua): marks route quests in NPC windows. "mark" = tags + accept line only,
    -- "dim" = also dims quests that aren't on your route (display only: every row stays clickable)
    { key = "npcHelper", scope = "account", kind = "choice", default = "dim", choices = { "off", "mark", "dim" }, export = true,
        page = "steps", choiceLabels = { off = "NPC_MODE_OFF", mark = "NPC_MODE_MARK", dim = "NPC_MODE_DIM" } },
    -- Tooltip step line (UI\TooltipStep.lua): "full" = with counts, "short" = only that it's part of the step
    { key = "tooltipStep", scope = "account", kind = "choice", default = "full", choices = { "off", "short", "full" }, export = true,
        page = "steps", choiceLabels = { off = "TIPSTEP_MODE_OFF", short = "TIPSTEP_MODE_SHORT", full = "TIPSTEP_MODE_FULL" } },
    -- quest giver check (Engine\QuestGiver.lua): a route quest the NPC doesn't offer is skipped for now
    { key = "questGiverCheck", scope = "account", kind = "bool", default = true, export = true, page = "steps" },
    -- beta.8 step notes (plans\note-line\plan.md): the current step's `why` as a dim line under its goals
    { key = "noteLine", scope = "char", kind = "bool", default = true, export = true, page = "steps" },
    -- beta.9 item pictures (UI\ItemIcons.lua): item icons in the step text, goal lines and next lines
    { key = "itemIcons", scope = "char", kind = "bool", default = true, export = true, page = "steps" },

    { key = "locked", scope = "char", kind = "bool", default = false, export = true, page = "window" },
    { key = "small", scope = "char", kind = "bool", default = false, export = true, page = "window" },
    { key = "opacity", scope = "char", kind = "number", default = 0.9, min = 0.2, max = 1, step = 0.1, export = true, page = "window" },
    -- width / followUIScale move the window the secure step button docks to (beta.3 fix: combat like scale)
    { key = "width", scope = "char", kind = "number", default = 272, min = 240, max = 420, step = 4, export = true, page = "window",
        combat = true },
    -- the next steps under the step block, in step lines (the bottom / corner grip; one window 2026-11-26: default
    -- 3 like the mock-up, min 1; a saved 4..30 keeps its value). Before: the whole step area, default 10 = the fixed height
    -- before the grip (Theme size.stepLines), so saves without it look the same. Height only: the item button
    -- docks to the window's top, so no combat wait.
    { key = "lines", scope = "char", kind = "number", default = 3, min = 1, max = 30, step = 1, export = true, page = "window",
        whole = true },   -- whole lines only (Get / Set round)
    { key = "scale", scope = "char", kind = "number", default = 1, min = 0.6, max = 1.6, step = 0.05, export = true, page = "window",
        combat = true },   -- moves the window the secure step button docks to
    -- the target button above the window (UI\TargetButton.lua, English clients only); secure: waits for combat end
    { key = "targetButton", scope = "char", kind = "bool", default = true, export = true, page = "window", combat = true },
    -- the item button above the window (UI\StepButton.lua: step items, hearthstone, quest-starting items); secure
    { key = "itemButton", scope = "char", kind = "bool", default = true, export = true, page = "window", combat = true },
    { key = "followUIScale", scope = "account", kind = "bool", default = true, export = true, page = "window", combat = true },
    -- the 3D viewer (UI\ModelView.lua, v0.3): the step's NPC / mob next to the guide window. Position and size
    -- sit next to the window size (the user's wish). Not secure: no combat wait.
    { key = "modelViewer", scope = "char", kind = "bool", default = true, export = true, page = "window" },
    -- "now" (default since the NOW-window viewer, the user's yes 2026-11-26): inside the NOW window; a saved
    -- left / right / below / free stays as the player picked it
    { key = "modelPos", scope = "char", kind = "choice", default = "now", choices = { "now", "left", "right", "below", "free" },
        export = true, page = "window", choiceLabels = { now = "CHOICE_MODEL_NOW", left = "CHOICE_MODEL_LEFT", right = "CHOICE_MODEL_RIGHT",
        below = "CHOICE_MODEL_BELOW", free = "CHOICE_MODEL_FREE" } },
    { key = "modelScale", scope = "char", kind = "number", default = 1, min = 0.6, max = 1.6, step = 0.05, export = true,
        page = "window" },
    { key = "modelHideCombat", scope = "account", kind = "bool", default = true, export = true, page = "window" },
    -- go-to steps show a walking murloc (Azurky, else Murky) instead of the go-to picture (the user, 2026-11-26)
    { key = "modelMurloc", scope = "account", kind = "bool", default = true, export = true, page = "window" },
    { key = "fontSize", scope = "account", kind = "number", default = 2, min = -4, max = 4, step = 1, export = true, page = "window" },  -- min -4 (was -2; font size fix 2026-11-25): 8 pt step text; default +2 (was 0; the user, 2026-11-25)
    -- text font (Theme\Media.lua Md.FONTS; the user, 2026-11-26: Open Sans by default, Easy-read and Classic as
    -- choices); a save without it or with an unknown value reads as Open Sans (the save is kept as is)
    { key = "font", scope = "account", kind = "choice", default = "opensans", choices = { "opensans", "dyslexic", "classic" },
        export = true, page = "window", choiceLabels = { opensans = "CHOICE_FONT_OPENSANS", dyslexic = "CHOICE_FONT_DYSLEXIC",
        classic = "CHOICE_FONT_CLASSIC" } },
    { key = "highContrast", scope = "account", kind = "bool", default = false, export = true, page = "window" },
    { key = "colorBlind", scope = "account", kind = "bool", default = false, export = true, page = "window" },
    -- the old NOW window (before the one window, 2026-11-26): no meaning any more; kept (no page, no texts) so old
    -- saves keep their values. UI.Migrate reads nowWindow / nowAttached once; nowLocked / nowScale are only kept.
    { key = "nowWindow", scope = "char", kind = "bool", default = true, export = false },
    { key = "nowAttached", scope = "char", kind = "bool", default = true, export = false },
    { key = "nowLocked", scope = "char", kind = "bool", default = false, export = false },
    { key = "nowScale", scope = "char", kind = "number", default = 1, min = 0.6, max = 1.6, step = 0.05, export = false },

    { key = "arrow", scope = "char", kind = "bool", default = true, export = true, page = "arrow" },
    { key = "arrowScale", scope = "char", kind = "number", default = 1, min = 0.6, max = 1.6, step = 0.05, export = true, page = "arrow" },
    { key = "arrowAlpha", scope = "char", kind = "number", default = 1, min = 0.3, max = 1, step = 0.1, export = true, page = "arrow" },
    { key = "arrowClickThrough", scope = "char", kind = "bool", default = false, export = true, page = "arrow" },
    { key = "arrowUnit", scope = "account", kind = "choice", default = "yards", choices = { "yards", "time" }, export = true,
        page = "arrow", choiceLabels = { yards = "CHOICE_YARDS", time = "CHOICE_TIME" } },
    { key = "arrivalSound", scope = "account", kind = "bool", default = false, export = true, page = "arrow" },
    -- smart arrow: lead through doors, gates and paths (Engine\SmartRoute.lua); off = the straight arrow
    { key = "smartArrow", scope = "account", kind = "bool", default = true, export = true, page = "arrow" },
    { key = "huntPath", scope = "account", kind = "bool", default = true, export = true, page = "arrow" },
    -- v0.3 spawn spots (Engine\Spots.lua): "auto" = the step's loop where it has one, the nearest spawn spot elsewhere;
    -- "spots" / "loops" = only that kind. huntPath off still turns both off (a saved off stays off).
    { key = "huntMode", scope = "account", kind = "choice", default = "auto", choices = { "auto", "spots", "loops" },
        export = true, page = "arrow", choiceLabels = { auto = "HUNT_MODE_AUTO", spots = "HUNT_MODE_SPOTS", loops = "HUNT_MODE_LOOPS" } },

    { key = "mapPins", scope = "account", kind = "bool", default = true, export = true, page = "map" },
    { key = "minimapPins", scope = "account", kind = "bool", default = true, export = true, page = "map" },
    -- path line (UI\PathLine.lua): the arrow's way as dots on the world map / the minimap
    { key = "pathMap", scope = "account", kind = "bool", default = true, export = true, page = "map" },
    { key = "pathMinimap", scope = "account", kind = "bool", default = true, export = true, page = "map" },
    -- spawn spots (UI\SpotDots.lua): the current step's spots as dots
    { key = "spotMap", scope = "account", kind = "bool", default = true, export = true, page = "map" },
    { key = "spotMinimap", scope = "account", kind = "bool", default = true, export = true, page = "map" },

    { key = "chatTab", scope = "account", kind = "number", default = 1, min = 1, max = 10, step = 1, export = true, page = "advanced" },
    { key = "gearSetLink", scope = "account", kind = "bool", default = true, export = true, page = "advanced" },
    { key = "debug", scope = "account", kind = "bool", default = false, export = false, page = "advanced" },
    -- v0.3 game data recording (Data\Gather.lua): on your PC only; off = "Don't record" (tos T3a). No settings page row:
    -- the switch is on the Game data page (only there while ns.GATHER is on)
    { key = "gatherData", scope = "account", kind = "bool", default = true, export = false },

    -- not in the panel
    { key = "hintLang", scope = "account", kind = "bool", default = false, export = false },   -- first-run "Dansk?" hint shown
    { key = "shown", scope = "char", kind = "bool", default = true, export = false },          -- guide window open
    { key = "theme", scope = "account", kind = "choice", default = "Dark", choices = { "Dark" }, export = true },
    { key = "minimapAngle", scope = "account", kind = "number", default = 210, min = 0, max = 360, export = true },
}
local byKey = {}
for _, d in ipairs(S.schema) do
    byKey[d.key] = d
    if d.page then
        d.label = d.label or ("SET_" .. d.key:upper())
        d.tip = d.tip or ("SETTIP_" .. d.key:upper())
    end
end
S.byKey = byKey

local function Valid(d, v)
    if d.kind == "bool" then return type(v) == "boolean" end
    if d.kind == "number" then return type(v) == "number" and v == v and v >= d.min and v <= d.max end
    if d.kind == "choice" then
        for _, c in ipairs(d.choices) do if c == v then return true end end
        return false
    end
    return false
end
S.Valid = Valid

local function Store(scope)
    local root = scope == "char" and ns.DB.char or ns.DB.account
    return root.settings
end

-- Called after DB.Init: defaults by metatable; saved values of the wrong form are ignored (kept as they are).
function S.Init()
    for _, scope in ipairs({ "account", "char" }) do
        local t = Store(scope)
        setmetatable(t, nil)
        local defaults = {}
        for _, d in ipairs(S.schema) do
            if d.scope == scope then defaults[d.key] = d.default end
        end
        setmetatable(t, { __index = defaults })
    end
end

function S.Get(key)
    local d = byKey[key]
    if not d then error("unknown setting " .. tostring(key), 2) end
    local v = Store(d.scope)[key]
    if not Valid(d, v) then return d.default end
    if d.whole then return math.floor(v + 0.5) end   -- an edited save's 12.5 lines = 13 (the save is kept as is)
    return v
end

function S.Set(key, value)
    local d = byKey[key]
    if not d then error("unknown setting " .. tostring(key), 2) end
    if d.whole and type(value) == "number" and value == value then value = math.floor(value + 0.5) end
    if not Valid(d, value) then return false end
    -- settings that touch secure parts wait for the end of combat (last change wins)
    if d.combat and ns.Compat.InCombat() and ns.CombatQueue then
        S.pending[key] = value
        ns.CombatQueue.Run("setting." .. key, S.Set, key, value)
        S.TellWaits()
        return true
    end
    S.pending[key] = nil
    local t = Store(d.scope)
    if value == d.default then rawset(t, key, nil) else rawset(t, key, value) end
    ns.Bus.Fire("SettingsChanged", key, value)
    return true
end

-- A change that waits for the end of combat says so in chat, once per fight (beta.3 fix: the control
-- snapped back with no word why). S.pending[key] = the waiting value (the settings page shows it).
S.pending = {}
function S.TellWaits()
    if S.told then return end
    S.told = true
    if ns.Print and ns.L then ns.Print(ns.L.SETTINGS_COMBAT) end
end
if ns.Bus then
    ns.Bus.On("CombatEnded", S, function() S.told = nil end, "core", 5)
end

-- The value a setting will have: a change waiting for the end of combat, else the saved one.
function S.Shown(key)
    if ns.CombatQueue and ns.CombatQueue.Pending("setting." .. key) and S.pending[key] ~= nil then return S.pending[key] end
    return S.Get(key)
end

-- The entries on one panel page, in schema order.
function S.Page(page)
    local out = {}
    for _, d in ipairs(S.schema) do if d.page == page then out[#out + 1] = d end end
    return out
end

-- "Reset this page": every setting on the page back to its default (only those that differ, so nothing
-- else in the save is touched). Returns how many changed.
function S.ResetPage(page)
    -- a page with combat-only settings (Window) resets as a whole after combat (beta.3 fix: its other
    -- settings - small, font size - would move the window under the waiting ones and leave the item button
    -- out of place); the count is what will change
    if ns.Compat.InCombat() and ns.CombatQueue then
        local waits, n = false, 0
        for _, d in ipairs(S.Page(page)) do
            if d.combat then waits = true end
            if S.Get(d.key) ~= d.default then n = n + 1 end
        end
        if waits then
            ns.CombatQueue.Run("reset." .. page, S.ResetPage, page)
            S.TellWaits()
            return n
        end
    end
    local n = 0
    for _, d in ipairs(S.Page(page)) do
        if S.Get(d.key) ~= d.default then
            S.Set(d.key, d.default)
            n = n + 1
        end
    end
    return n
end

-- The default as the player reads it ("on", "off", "80%", a choice's name).
function S.DefaultText(d)
    local L = ns.L
    if d.kind == "bool" then return d.default and L.SET_ON or L.SET_OFF end
    if d.kind == "choice" then
        local k = d.choiceLabels and d.choiceLabels[d.default]
        return k and L[k] or tostring(d.default)
    end
    return S.NumberText(d, d.default)
end

-- A number setting's value as shown next to its slider.
function S.NumberText(d, v)
    if d.key == "opacity" or d.key == "arrowAlpha" or d.key == "scale" or d.key == "arrowScale"
        or d.key == "modelScale" then
        return ("%d%%"):format(math.floor(v * 100 + 0.5))
    end
    if d.key == "fontSize" and v > 0 then return "+" .. v end
    return tostring(math.floor(v + 0.5))
end

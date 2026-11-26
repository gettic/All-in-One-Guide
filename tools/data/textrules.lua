-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Text rules for tools\textlint.lua (data only; the ui-text agent owns the wording rules behind it,
-- plans\v0.2\ui-text-review.md). Lengths count characters without {placeholders}; Danish gets 40 % more room
-- (da = en * 1.4, rounded down).
return {
    -- per spot: the first pattern that matches a locale key gives its English cap
    lengths = {
        { key = "^NOTICE_", en = 24, why = "notice-line menu words" },
        { key = "^POPUP_", en = 12, why = "dialog buttons" },
        { key = "^MENU_", en = 32, why = "drop-down rows" },
        { key = "^TIP_", en = 44, why = "one-line tooltips" },
        { key = "^CHIP_", en = 20, why = "a chip" },
        { key = "^COUNTER$", en = 14, why = "window corner" },
        { key = "^TITLE$", en = 28, why = "window title" },
        { key = "^NEXT_LINE$", en = 10, why = "small mode prefix" },
        { key = "^YARDS$", en = 8, why = "distance" },
        { key = "^ARRIVED$", en = 16, why = "under the arrow" },
        { key = "^FEAT_", en = 24, why = "part name inside ERROR_LINE" },
        { key = "^STEP_", en = 40, why = "default step texts" },
        { key = "^STATE_", en = 90, why = "window state line (wraps)" },
        { key = "^HELP_", en = 90, why = "help lines" },
        -- v0.2 M4: the settings panel (Blizzard's control rows; the label column is about 220 units wide)
        { key = "^SET_", en = 32, why = "settings names" },
        { key = "^PAGE_", en = 20, why = "settings page names" },
        { key = "^CHOICE_", en = 24, why = "drop-down choices" },
        -- v0.2 M5: the Hub
        -- v0.2 look review: nav text has about 114 units (da 19 by the factor); a type column about 172
        { key = "^HUB_", en = 14, why = "Hub nav rows (114 units after the icon)" },
        { key = "^REPORT_TYPE_", en = 22, why = "report type choices (a column after box and icon)" },
        { key = "^REPORT_", en = 180, why = "Report page lines (they wrap)" },
        { key = "^ABOUT_", en = 200, why = "About page lines (they wrap)" },
        { key = ".", en = 120, why = "chat lines" },
    },
    daFactor = 1.4,
    stepText = 90,            -- pack step `text`
    stepTextDa = 126,         -- pack step `da` (90 * 1.4)
    whyText = 126,            -- pack step `why` (a note, may run a little longer)
    -- chat lines: start lower case after the "All-in-One Guide:" prefix
    chatKeys = { "^ERROR_", "^SAFE_MODE$", "^SAVE_", "^LANG_", "^GUIDE_", "^SLASH_", "^DEBUG_", "^STATUS_HEAD$",
        "^UNDO_NONE$", "^HELP_" },
    -- tooltips and menu rows: no full stop at the end
    noStopKeys = { "^TIP_", "^MENU_", "^SET_", "^SETTIP_", "^PAGE_", "^CHOICE_" },
    -- words that never appear in our texts (lower case, plain find, so "official" also blocks "unofficial");
    -- the paid guide names come from the private list given with --words
    neverUse = {
        "zygor", "official", "endorsed", "approved by blizzard", "no ban risk", "ban-safe", "ban safe",
        "exploit", "glitch", "wall jump", "wall-jump", "duping", "out of bounds",
        "tradeskillmaster is recommended", "donate", "patreon", "paypal",
        -- claims
        "guaranteed", "fastest", "best route", "100%",
    },
    -- whole words only
    neverUseWhole = { "dupe" },
    -- player texts in the locale: no blame or alarm words
    localeAlarm = { "invalid", "illegal", "fatal", "you failed", "you must", "!!" },
    -- player texts in the locale: no programmer words (whole words; "error" is allowed)
    jargon = { "api", "lua", "cache", "savedvariables", "taint", "nil", "traceback", "callback", "namespace",
        "frame", "hook" },
    -- Danish never-use words (same idea)
    neverUseDa = { "officiel", "godkendt af blizzard", "udnyt fejl", "donér", "doner til", "garanteret", "hurtigste" },
    -- pack step texts (English) start with one of these (warning); v0.2 step kinds added
    firstWords = { "Accept", "Turn in", "Kill", "Loot", "Collect", "Pick up", "Go", "Follow", "Leave", "Reach",
        "Use", "Fly", "Learn", "Train", "Set", "Talk to", "Get", "Cross" },
    -- kill / collect steps say how many and where, unless they name one target ("Kill the big scorpid")
    countVerbs = { "Kill", "Loot", "Collect", "Pick up" },
    placeWords = { "in", "at", "near", "around", "from", "by", "inside", "outside", "on", "as you go", "along" },
    -- signs a step text was copied from quest text (Blizzard tokens, narration, first person)
    copied = {
        tokens = { "%$[A-Za-z]", "<name>", "<class>", "<race>" },
        narration = { "brave ", "adventurer", "hero,", "champion,", "my friend", "you there", "greetings", "please hurry",
            "i need you", "we need you", "thank you", "for the horde", "for the alliance" },
        -- English only (Danish "i" means "in")
        firstPerson = { " i ", " i'm ", " we ", " my " },
        maxSentences = 2,
    },
}

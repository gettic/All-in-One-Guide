-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- English texts (the source language). Keys are stable; Danish lives in daDK.lua (M4).
-- Named fields in {braces} must stay the same in every language. Context notes after "--".
local _, ns = ...

ns.Locale.Add("enUS", {
    -- chat lines (each starts with "All-in-One Guide:" in our colour)
    ERROR_LINE = "something went wrong in {feature}. Type /aog error to see the details.", -- {feature} = internal feature name
    ERROR_NONE = "no errors this session.",
    ERROR_DETAILS = "error details (copy them from here):",
    SAFE_MODE = "safe mode: the last loads didn't finish, so this session uses default settings and loads nothing extra. Your saved data is untouched.",
    SAVE_NEWER = "your saved data is from a newer version. It is kept as it is and not changed this session.",
    SAVE_REPAIRED = "some saved data had the wrong form. It was kept aside and replaced with defaults.",

    -- slash help (command words stay English in every language)
    HELP_TITLE = "commands:",
    HELP_TITLE_ALL = "all commands:",
    HELP_ALL = "show every command",
    HELP_STATUS = "version, self-test result and switched-off features",
    HELP_DEBUG = "debug log: on, off or show",
    HELP_ERROR = "details of the last error",
    HELP_SKIP = "skip the current step",
    HELP_BACK = "go back one step",
    HELP_RESETPOS = "put the guide window and the arrow back in their start places",
    HELP_LANG = "language: en, da or auto (used after a reload)",
    HELP_GUIDE = "open a guide: elwynn or durotar",
    HELP_SELFTEST = "let the addon check itself (a short English report to copy)",

    -- language (the language names "English" / "Dansk" are never translated)
    LANG_RELOAD = "The new language is used after a reload. Reload now?",
    LANG_LATER = "the new language is used after your next /reload.",
    LANG_SAME = "that language is already in use.",
    LANG_USAGE = "type /aog lang en, /aog lang da or /aog lang auto.",

    -- picking a guide; {guide} = the guide's title
    GUIDE_OPENED = "{guide} is open. Type /aog guide to pick another one.",
    GUIDE_NONE = "no guide fits this character yet. Type /aog guide elwynn or /aog guide durotar.",
    GUIDE_USAGE = "type /aog guide elwynn or /aog guide durotar.",
    GUIDE_UNKNOWN = "there is no guide called \"{word}\". Try elwynn or durotar.",

    -- the guide window
    TITLE = "All-in-One Guide",
    COUNTER = "step {i}/{n}",                   -- top right of the window
    CHIP_DONE_ONE = "{n} step done",            -- the chip above the steps (1)
    CHIP_DONE_MANY = "{n} steps done",          -- (2 or more)
    NEXT_LINE = "Next: {text}",                 -- small mode, under the current step
    GOAL_ITEMS = "Items",                       -- goal line of an item step
    YARDS = "{n} yd",                           -- distance, whole yards
    ARRIVED = "You're there",                   -- under the arrow, inside the step's spot
    STATE_NONE = "No guide is open.",
    STATE_FINISHED = "Route finished. Well done!",
    STATE_ERROR = "This guide hit a problem. Type /aog error for the details.",
    STATE_SAFE = "Safe mode: the guide is paused this session. Type /reload to try again.",
    TIP_CLOSE = "Close the guide (/aog opens it again)",
    TIP_LOCK = "Lock the window in place",
    TIP_UNLOCK = "Unlock the window",
    TIP_SMALL = "Small mode",
    TIP_EXPAND = "Full window",
    TIP_MENU = "Menu",
    TIP_BACK = "Back one step",
    TIP_NEXT = "Next step",

    -- the title menu
    MENU_SMALL = "Small mode",
    MENU_LOCK = "Lock the window",
    MENU_QUIET = "Quiet mode (only danger hints)",
    MENU_ARROW = "Show the arrow",
    MENU_MOTION = "Less motion",
    MENU_OPACITY = "Background {n}%",
    MENU_RESETPOS = "Reset positions",

    -- the notice line's right-click menu
    NOTICE_LATER = "Later",
    NOTICE_HIDE_CHAR = "Hide on this character",
    NOTICE_HIDE_KIND = "Hide hints like this",

    -- dialogs
    POPUP_YES = "Yes",
    POPUP_NO = "No",
    COPY_HINT = "Press Ctrl+C to copy, then Esc.",

    -- default step texts (when a pack step has no text of its own); {quest} = quest name from the game
    STEP_ACCEPT = "Accept {quest}",
    STEP_TURNIN = "Turn in {quest}",
    STEP_OBJECTIVE = "Do {quest}",
    STEP_GOTO = "Go to the marked spot",
    STEP_LEVEL = "Reach level {level}",
    STEP_MANUAL = "Do this step, then skip it",
    SLASH_UNKNOWN = "unknown command \"{word}\". Type /aog help.",

    -- /aog debug
    DEBUG_ON = "debug log on.",
    DEBUG_OFF = "debug log off.",
    DEBUG_EMPTY = "the debug log is empty.",

    -- /aog status (the status line itself stays English so anyone can read it)
    STATUS_HEAD = "status (copy this line if you report a problem):",
})

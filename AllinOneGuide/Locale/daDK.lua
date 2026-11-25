-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Danske tekster. Nøglerne er de samme som i enUS.lua; {felter} i klammer må ikke ændres.
-- Spil-navne (quests, NPC'er, områder) kommer fra klienten og oversættes ikke.
local _, ns = ...

ns.Locale.Add("daDK", {
    -- chat lines (each starts with "All-in-One Guide:" in our colour)
    ERROR_LINE = "noget gik galt i {feature}. Skriv /aog error for detaljer.",
    ERROR_NONE = "ingen fejl i denne session.",
    ERROR_DETAILS = "fejldetaljer (kopier dem herfra):",
    SAFE_MODE = "sikker tilstand: de sidste indlæsninger blev ikke færdige, så denne session bruger standardindstillinger og indlæser ikke andet. Dine gemte data er urørt.",
    SAVE_NEWER = "dine gemte data er fra en nyere version. De beholdes som de er og ændres ikke i denne session.",
    SAVE_REPAIRED = "nogle gemte data havde den forkerte form. De er lagt til side og erstattet med standardværdier.",

    -- slash help (command words stay English in every language)
    HELP_TITLE = "kommandoer:",
    HELP_TITLE_ALL = "alle kommandoer:",
    HELP_ALL = "vis alle kommandoer",
    HELP_STATUS = "version, selvtest og slåede-fra funktioner",
    HELP_DEBUG = "debuglog: on, off eller show",
    HELP_ERROR = "detaljer om den sidste fejl",
    HELP_SKIP = "spring det nuværende trin over",
    HELP_BACK = "gå et trin tilbage",
    HELP_LANG = "sprog: en, da eller auto (bruges efter reload)",
    HELP_GUIDE = "åbn en guide: elwynn eller durotar",
    HELP_SELFTEST = "lad addonet tjekke sig selv (kort engelsk rapport at kopiere)",
    LANG_RELOAD = "Det nye sprog bruges efter et reload. Reload nu?",
    LANG_LATER = "det nye sprog bruges efter dit næste /reload.",
    LANG_SAME = "det sprog er allerede i brug.",
    LANG_USAGE = "skriv /aog lang en, /aog lang da eller /aog lang auto.",
    GUIDE_OPENED = "{guide} er åben. Skriv /aog guide for at vælge en anden.",
    GUIDE_NONE = "ingen guide passer til denne karakter endnu. Skriv /aog guide elwynn eller /aog guide durotar.",
    GUIDE_USAGE = "skriv /aog guide elwynn eller /aog guide durotar.",
    GUIDE_UNKNOWN = "der er ingen guide med navnet \"{word}\". Prøv elwynn eller durotar.",
    HELP_RESETPOS ="sæt guidevinduet og pilen tilbage på startpladsen",

    -- the guide window
    TITLE = "All-in-One Guide",
    COUNTER = "trin {i}/{n}",
    CHIP_DONE_ONE = "{n} trin klaret",
    CHIP_DONE_MANY = "{n} trin klaret",
    NEXT_LINE = "Næste: {text}",
    GOAL_ITEMS = "Ting",
    YARDS = "{n} yd",
    ARRIVED = "Du er fremme",
    STATE_NONE = "Ingen guide er åben.",
    STATE_FINISHED = "Ruten er færdig. Godt gået!",
    STATE_ERROR = "Guiden stødte på et problem. Skriv /aog error for detaljer.",
    STATE_SAFE = "Sikker tilstand: guiden er sat på pause. Skriv /reload for at prøve igen.",
    TIP_CLOSE = "Luk guiden (/aog åbner den igen)",
    TIP_LOCK = "Lås vinduet",
    TIP_UNLOCK = "Lås vinduet op",
    TIP_SMALL = "Lille visning",
    TIP_EXPAND = "Fuldt vindue",
    TIP_MENU = "Menu",
    TIP_BACK = "Et trin tilbage",
    TIP_NEXT = "Næste",

    -- the title menu
    MENU_SMALL = "Lille visning",
    MENU_LOCK = "Lås vinduet",
    MENU_QUIET = "Stille (kun farevarsler)",
    MENU_ARROW = "Vis pilen",
    MENU_MOTION = "Mindre bevægelse",
    MENU_OPACITY = "Baggrund {n}%",
    MENU_RESETPOS = "Nulstil positioner",

    -- the notice line's right-click menu
    NOTICE_LATER = "Senere",
    NOTICE_HIDE_CHAR = "Skjul på denne karakter",
    NOTICE_HIDE_KIND = "Skjul tips som dette",

    -- dialogs
    POPUP_YES = "Ja",
    POPUP_NO = "Nej",
    COPY_HINT = "Tryk Ctrl+C for at kopiere, derefter Esc.",

    -- default step texts (when a pack step has no text of its own); {quest} = quest name from the game
    STEP_ACCEPT = "Tag imod {quest}",
    STEP_TURNIN = "Aflever {quest}",
    STEP_OBJECTIVE = "Udfør {quest}",
    STEP_GOTO = "Gå til det markerede sted",
    STEP_LEVEL = "Nå level {level}",
    STEP_MANUAL = "Gør dette, og spring så over",
    SLASH_UNKNOWN = "ukendt kommando \"{word}\". Skriv /aog help.",

    -- /aog debug
    DEBUG_ON = "debuglog slået til.",
    DEBUG_OFF = "debuglog slået fra.",
    DEBUG_EMPTY = "debugloggen er tom.",

    -- /aog status
    STATUS_HEAD = "status (kopier denne linje, hvis du melder et problem):",
})

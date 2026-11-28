-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The default theme "Dark": black and red, slim, rounded; our own colours and art (plans\default-theme\theme-notes.md,
-- plans\guide-window-look\ 4e / 4f). Dimming is always by colour, never by text alpha. Whole-number font sizes.
-- A new theme: ns.Theme.Register("Name", { base = "Dark", ... }) and set at least the keys in ns.Theme.REQUIRED
-- (everything else falls back to its base); ns.Theme.MissingKeys("Name") lists what it lacks (self-check "theme"). size.corner 0 (or no
-- slot.frame.panel) = the flat panel + hairline instead of the rounded frame; art = our own media slots or the
-- game's own atlases / files referenced by name.
local _, ns = ...

ns.Theme.Register("Dark", {
    -- colours: { "#rrggbb", alpha } or "=other.key"
    ["color.panel"] = { "#0A0A0B", 0.95 },   -- (its alpha = the opacity setting)
    ["color.titleTop"] = { "#1A1314", 1 },
    ["color.titleBottom"] = { "#0F0B0C", 1 },
    ["color.border"] = { "#3A2A2C", 1 },
    ["color.divider"] = { "#FFFFFF", 0.07 },
    ["color.text"] = { "#F1ECEA", 1 },
    ["color.title"] = { "#F1ECEA", 1 },
    ["color.accent"] = { "#C8102E", 1 },    -- crimson: edges, bars, rings; never text (accentText)
    ["color.accentGlow"] = { "#C8102E", 0.18 },
    ["color.accentGlowEnd"] = { "#C8102E", 0.03 },
    ["color.barFrom"] = { "#E0314A", 1 },
    ["color.barTo"] = { "#8E0E22", 1 },
    ["color.barTrack"] = { "#1C1718", 1 },
    ["color.zone"] = { "#F1ECEA", 1 },
    ["color.titleCoords"] = "=text.dim",      -- beta.14: the step's coordinates + distance in the title bar
    ["color.counter"] = { "#A8A2A2", 1 },
    ["color.quest"] = { "#F3D58C", 1 },
    ["color.npc"] = { "#9FD8FF", 1 },
    ["color.coord"] = { "#7FB8F0", 1 },
    ["color.text.dim"] = { "#8C8C92", 1 },
    ["color.done"] = { "#7A8390", 1 },
    ["color.upcoming"] = { "#CFCBCB", 1 },  -- next steps (the verb carries the colour)
    ["color.stepNumber"] = { "#7A8390", 1 },
    ["color.goal"] = { "#E4E0DE", 1 },
    ["color.goalCount"] = "=text",
    ["color.goalDone"] = { "#58C46E", 1 },
    ["color.goalDoneBox"] = { "#1E5E3E", 1 },
    ["color.goalDoneEdge"] = { "#3FAF74", 1 },
    ["color.goalBoxEmpty"] = { "#56606D", 1 },
    ["color.flash"] = { "#6FD39A", 0.45 },
    ["color.button"] = { "#B8B4B4", 1 },
    ["color.buttonHover"] = { "#FFFFFF", 1 },
    ["color.buttonHoverBg"] = { "#FFFFFF", 0.08 },
    ["color.icon.accept"] = { "#F4C542", 1 },
    ["color.icon.turnin"] = { "#F4C542", 1 },
    ["color.icon.glyphDark"] = { "#2A1F00", 1 },
    ["color.icon.kill"] = { "#E0524A", 1 },
    ["color.icon.collect"] = { "#E39A3B", 1 },
    ["color.icon.goto"] = { "#4DA3F0", 1 },
    ["color.icon.level"] = "=accent",
    ["color.icon.manual"] = "=counter",
    ["color.arrowAhead"] = { "#43D18C", 1 },
    ["color.arrowSide"] = { "#E8C547", 1 },
    ["color.arrowBehind"] = { "#F0625A", 1 },
    ["color.arrived"] = { "#43D18C", 1 },
    ["color.arrivedText"] = { "#7FE3AE", 1 },
    ["color.notice"] = "=text",
    ["color.notice.danger"] = { "#F0625A", 1 },
    ["color.white"] = { "#FFFFFF", 1 },
    -- v0.2 badge colours (art-src\MANIFEST.md suggestions; changeable)
    ["color.icon.learn"] = { "#9C7CF0", 1 },
    ["color.icon.train"] = "=icon.learn",
    ["color.icon.note"] = { "#6B7686", 1 },
    ["color.icon.useitem"] = { "#C86BD6", 1 },
    ["color.icon.grind"] = { "#8C2F4A", 1 },   -- ui look check (2026-11-28): wine
    ["color.icon.fly"] = { "#3BA9D9", 1 },
    ["color.icon.getfp"] = "=icon.fly",
    ["color.icon.hearth"] = { "#D8643C", 1 },
    ["color.icon.sethearth"] = "=icon.hearth",
    -- v0.2 glyph tints
    ["color.notice.hearth"] = { "#E9B65C", 1 },
    ["color.notice.flight"] = { "#9FD8FF", 1 },
    ["color.notice.useitem"] = { "#F4C542", 1 },
    ["color.notice.snooze"] = "=text.dim",
    ["color.corpse"] = { "#C9D3DF", 1 },
    ["color.pinFace"] = { "#0B0E13", 1 },
    ["color.stepFrame"] = { "#4A4A50", 1 },
    ["color.endButtonEdge"] = "=stepFrame",   -- v0.2.5: the end card button's 1 px edge (the accent under the mouse)
    ["color.stepFrameMissing"] = { "#E0524A", 1 },
    ["color.stepReminder"] = { "#F4C542", 1 },   -- icon review #1: "use it now" ring + glow (gold; red = missing)
    -- v0.2 look review: the Hub, dialog, copy box and menu (text over the world; the guide window keeps
    -- color.panel and the opacity setting)
    ["color.panelSolid"] = { "#0A0A0B", 0.95 },
    ["color.arrowText"] = "=white",           -- the distance under the arrow
    -- smart arrow: while it leads to a door / gate / path point first (not the goal itself)
    ["color.arrowVia"] = { "#5CC8F0", 1 },    -- the arrow
    ["color.arrowHunt"] = { "#F0A65C", 1 },   -- the arrow while it leads round a hunt loop
    ["color.viaText"] = { "#8FD8F5", 1 },     -- "Through the abbey door" under the distance
    -- path line (UI\PathLine.lua): dots along the arrow's way on the world map and the minimap
    ["color.pathNow"] = "=arrowVia",          -- the leg the arrow points along now
    ["color.pathLater"] = { "#5CC8F0", 0.55 },  -- the legs after it
    ["color.pathCorpse"] = "=corpse",         -- the way to your corpse
    -- spawn spots (UI\SpotDots.lua): the current kill / collect step's spots on the world map and the minimap
    ["color.spotOpen"] = { "#F0A65C", 0.85 },   -- a spot you haven't cleared
    ["color.spotCleared"] = { "#8A8A8A", 0.5 }, -- cleared: grey until its mobs respawn
    ["color.spotTarget"] = "=arrowHunt",      -- the spot the arrow points at
    ["color.wait"] = "=notice.hearth",        -- the step button's hourglass
    ["color.minimap"] = "=white",             -- the minimap button while the guide is shown
    ["color.minimapDim"] = { "#999999", 1 },  -- ... and while it is hidden
    ["color.thumb"] = "=accent",              -- Hub scroll thumb
    ["color.thumbTrack"] = "=barTrack",
    -- v0.2 look review #5 / #6 / #7: shared buttons, radio rows, Hub nav selection, the done chip
    ["color.buttonFill"] = "=barTrack",       -- K.Button / the chip: the fill
    ["color.buttonPrimary"] = "=accentText",      -- the primary button's text (Move, Yes)
    ["color.radio"] = "=goalBoxEmpty",        -- radio ring, not picked
    ["color.radioOn"] = "=accent",            -- radio ring + dot, picked
    ["color.navSelected"] = "=buttonHoverBg", -- the open Hub page's row box
    ["color.navBar"] = "=accent",             -- ... and its bar on the left
    -- the NOW box (current step in its own panel) and the NEXT section under it
    -- the main window: guide cards, faction tags, filter chips, slider, search box
    ["color.cardBg"] = { "#161D26", 0.95 },   -- a guide card
    ["color.cardEdge"] = "=accent",           -- the active guide's card edge
    ["color.cardBorder"] = { "#2A3340", 1 },  -- the other cards' edge (= color.border)
    ["color.tagAlliance"] = { "#4F8FE0", 1 }, -- faction tag text / edge
    ["color.tagHorde"] = { "#D9534F", 1 },
    ["color.tagBoth"] = "=text.dim",
    ["color.chipOn"] = "=accentText",             -- a picked filter chip's text and edge
    ["color.sliderTrack"] = "=barTrack",
    ["color.sliderFill"] = "=accent",
    ["color.sliderThumb"] = { "#E6EBF0", 1 },
    ["color.searchBg"] = { "#0E141A", 1 },
    -- NPC talk helper: tags on quest rows in NPC windows and the line under the accept window
    ["color.npcRoute"] = "=accentText",           -- on your route / hand in
    ["color.npcLater"] = "=counter",          -- in a later guide
    ["color.npcDim"] = "=text.dim",           -- skipped / not on your route
    ["color.npcTagBg"] = { "#0B0E13", 0.85 }, -- the tag's own small backing
    -- tooltip step line (on Blizzard's dark tooltip)
    ["color.tipStep"] = "=accentText",            -- part of the current step
    ["color.tipOnWay"] = "=counter",          -- an on-the-way / optional goal
    ["color.tipDone"] = "=text.dim",          -- that objective is already full
    -- 3D viewer (UI\ModelView.lua): the box around the NPC / mob model, its "No 3D view" card text
    ["color.modelBg"] = { "#08090B", 0.95 },
    ["color.modelEdge"] = { "#2A2A2E", 1 },
    ["color.modelText"] = "=text.dim",
    -- the one window (4f, plans\guide-window-look\): black / red, rounded
    ["color.accentText"] = { "#FF7A8A", 1 },  -- red for text (crimson is too dark to read)
    ["color.shadow"] = { "#000000", 0.6 },    -- soft shadow round the window
    ["color.titleBg"] = { "#151011", 1 },     -- the rounded header (flat)
    ["color.headLine"] = { "#C8102E", 0.67 }, -- the line under the header
    ["color.goalNowBg"] = "=accentGlow",      -- the goal to do now: tint ...
    ["color.goalNowEdge"] = "=accent",        -- ... and its 2 px edge
    ["color.goalDoneBg"] = { "#3FBF5F", 0.15 },
    ["color.goalDoneDim"] = { "#58C46E", 0.7 },  -- finished goals in an opened fold
    ["color.goalFlashBg"] = { "#3FBF5F", 0.35 }, -- a goal that just finished (~1.5 s, then it folds in)
    ["color.chipBg"] = { "#FFFFFF", 0.055 },  -- the info chips
    ["color.chipText"] = { "#B8B4B4", 1 },
    ["color.barFill"] = { "#C41F38", 1 },     -- the progress fill (rounded: one colour)
    ["color.barRim"] = { "#2A1416", 1 },
    ["color.barText"] = "=white",
    ["color.buttonSquare"] = { "#FFFFFF", 0.07 },  -- the header buttons' soft squares
    ["color.targetBg"] = { "#221C1A", 1 },    -- the target button's backing
    ["color.target"] = { "#FF8C7A", 1 },      -- its crosshair
    ["color.sub"] = "=text.dim",              -- "for <quest>" / place line under the step text
    ["color.note"] = "=text.dim",             -- beta.8 step note line (the step's `why`) under the goals
    ["color.itemLink"] = { "#9CC8F0", 1 },    -- beta.12 item pictures: an item's name in the current step (hover = tooltip)
    ["size.noteGap"] = 3,                     -- its gap above
    -- verbs (coloured first word of a step) and tiles (base tint / symbol tint)
    ["color.verb.accept"] = { "#F4C542", 1 },
    ["color.verb.turnin"] = { "#F4C542", 1 },
    ["color.verb.kill"] = { "#FF8C7A", 1 },
    ["color.verb.loot"] = { "#E39A3B", 1 },
    ["color.verb.use"] = { "#5CC8D8", 1 },
    ["color.verb.goto"] = { "#4DA3F0", 1 },
    ["color.verb.talk"] = { "#B48CF0", 1 },
    -- icon review #4 (2026-11-28): train magenta, fly pale sky (dark symbol), hearth brown-amber: no two alike
    ["color.verb.train"] = { "#D46BC8", 1 },
    ["color.verb.fly"] = { "#9FD8FF", 1 },
    ["color.verb.hearth"] = { "#B59A72", 1 },   -- ui look check (2026-11-28): stone tan, apart from loot orange
    ["color.verb.note"] = { "#A8A2A2", 1 },
    -- next lines only (beta.13, the user: "Lighter blue and red text"): the same hue mixed toward white, >= 4.5:1 on
    -- #0A0A0B at the faintest row fade (64 %): go to 4.61:1 (was 3.57), kill 4.51:1 (was 4.08)
    ["color.next.goto"] = { "#82BFF5", 1 },
    ["color.next.kill"] = { "#FF9D8E", 1 },
    ["color.tile.accept"] = "=verb.accept",
    ["color.tile.turnin"] = "=verb.turnin",
    ["color.tile.kill"] = "=verb.kill",
    ["color.tile.loot"] = "=verb.loot",
    ["color.tile.use"] = "=verb.use",
    ["color.tile.goto"] = "=verb.goto",
    ["color.tile.talk"] = "=verb.talk",
    ["color.tile.train"] = "=verb.train",
    ["color.tile.fly"] = "=verb.fly",
    ["color.tile.hearth"] = "=verb.hearth",
    ["color.tile.note"] = { "#6B7686", 1 },
    ["color.tile.done"] = { "#3FBF5F", 1 },
    -- icon review #6: own tiles (level teal, grind wine, get-fp / set-hearth like fly / hearth)
    ["color.tile.level"] = { "#2FC4A8", 1 },
    ["color.tile.grind"] = { "#8C2F4A", 1 },   -- ui look check (2026-11-28): wine, apart from kill red
    ["color.verb.grind"] = { "#D46A8A", 1 },   -- grind verb: a lighter wine (~5.9:1 on #0A0A0B; the tile's 2.5:1 was too dark)
    ["color.verb.level"] = "=tile.level",
    ["color.tile.getfp"] = "=verb.fly",
    ["color.tile.sethearth"] = "=verb.hearth",
    ["color.tile.open"] = { "#8A8F98", 1 },
    ["color.tileDark"] = { "#2A1F00", 1 },    -- symbol on the light (yellow / orange) tiles

    -- fonts: sizes in Arial Narrow points (the text font setting scales them, Theme\Media.lua Md.FONTS);
    -- numbers = true: outlined number texts (Easy-read draws them with Open Sans)
    lineSpacing = 1.35,
    ["font.title"] = { size = 12, shadow = true },
    ["font.header"] = { size = 12, shadow = true },
    ["font.step"] = { size = 12, shadow = true },
    ["font.goal"] = { size = 11, shadow = true },
    ["font.small"] = { size = 10 },
    ["font.bar"] = { size = 10, shadow = true },    -- the footer's step text (1 px dark shadow: readable on the red fill)
    ["font.arrow"] = { size = 15, flags = "OUTLINE", numbers = true },
    ["font.buttonText"] = { size = 10, flags = "OUTLINE", numbers = true },  -- count / key on the step button (busy icons)
    ["font.sectionHead"] = { size = 10, shadow = true },     -- the "NOW" / "NEXT" headers

    -- sizes (UI units)
    ["size.width"] = 272,
    ["size.pad"] = 8,
    ["size.badge"] = 14,
    ["size.box"] = 10,
    ["size.button"] = 16,
    ["size.navButton"] = 18,
    ["size.bar"] = 6,
    ["size.barSmall"] = 5,
    ["size.arrow"] = 64,
    ["size.stepLines"] = 3,       -- next steps under the step block (the "lines" setting's default; the grip changes it)
    ["size.smallLines"] = 5,      -- in small mode
    ["size.border"] = 1,
    ["size.thumb"] = 3,           -- Hub scroll thumb width
    ["size.title"] = 22,          -- the one title bar (guide window, Hub, dialog, copy box)
    ["size.titleLogo"] = 16,
    ["size.buttonMin"] = 90,      -- K.Button: width = max(this, text + 24)
    ["size.navBar"] = 2,          -- the open Hub page's bar
    ["size.sectionGap"] = 4,      -- space between the NOW box and the NEXT header
    ["size.card"] = 66,           -- main window: a guide card's height
    ["size.cardEmblem"] = 44,     -- ... its shield
    ["size.navIndent"] = 14,      -- main window: a sub-page's nav row indent
    ["size.slider"] = 140,        -- our own slider's width
    ["size.sliderThumb"] = 10,
    ["size.search"] = 170,        -- the search box's width
    ["size.pathDot"] = 6,         -- path line: a dot on the world map (screen units, kept at any map zoom)
    ["size.pathGap"] = 14,        -- ... the space between dots on the world map
    ["size.pathMiniDot"] = 4,     -- ... a dot on the minimap
    ["size.pathMiniGap"] = 8,     -- ... the space between dots on the minimap
    ["size.pathMiniLine"] = 2,    -- ... the way to a goal on the minimap: a solid line this thick (the hunt loop stays dots)
    ["size.spotDot"] = 8,         -- spawn spots: a spot on the world map (screen units)
    ["size.spotTargetDot"] = 12,  -- ... the spot the arrow points at
    ["size.spotMiniDot"] = 5,     -- ... a spot on the minimap
    -- 3D view: one fixed 3:4 portrait (2026-11-28, the user's pick "B"); every model is fitted by its camera
    ["size.modelW"] = 132,        -- 3D viewer docked: width / height at size 100 %
    ["size.modelH"] = 176,
    ["size.modelGap"] = 6,        -- ... gap to the guide window (window units)
    ["size.modelInset"] = 2,      -- ... the model inside its box
    ["size.modelInside"] = 72,    -- ... inside the step block: width (x the 3D view size setting)
    ["size.modelInsideH"] = 96,   -- ... and height
    ["size.modelInsideMin"] = 60, -- ... width under 272 wide (the height keeps the 3:4 shape: 80)
    -- the one window: rounded corners (0 = the flat panel + hairline, e.g. a Blizzard-style theme)
    ["size.corner"] = 10,         -- the window's corners
    ["size.shadow"] = 8,          -- its soft shadow (outside the window)
    ["size.cornerButton"] = 6,    -- item / target buttons, the 3D square
    ["size.cornerChip"] = 4,      -- info chips
    ["size.cornerSquare"] = 3,    -- header buttons, the goal-to-do-now line
    ["size.cornerBar"] = 5,       -- the progress bar
    ["size.numberCol"] = 0,       -- step numbers in the list (0 = none)
    ["size.tile"] = 12,           -- step / goal tiles
    ["size.blockPad"] = 6,        -- space above the step block
    ["size.blockGoals"] = 2,      -- goal lines the window keeps room for (more = it grows up)
    ["size.focusEdge"] = 2,       -- the goal-to-do-now's edge
    ["size.foldIndent"] = 12,     -- finished goals in an opened fold
    ["motion.goalFlash"] = 1.5,   -- a just-finished goal stays green this long before it folds in
    ["size.barH"] = 12,           -- the progress bar
    ["size.navH"] = 20,           -- the row with back / bar / next
    ["size.chipGap"] = 4,         -- between the info chips
    ["size.buttonRowGap"] = 10,   -- item / target buttons above the window's top (their frame sticks out 8)

    -- alphas (0..1) and built-in game files (v0.2 look review)
    ["alpha.hover"] = 0.35,       -- the minimap button's highlight
    ["alpha.pulseLow"] = 0.4,     -- the step button's reminder glow pulses between this and 1
    ["alpha.arrowPulseLow"] = 0.35,  -- smart arrow: the arrow dips to this and back when a door / gate is passed
    ["alpha.npcDim"] = 0.45,      -- NPC talk helper: a quest row that isn't on your route (still clickable)
    ["file.itemUnknown"] = "Interface\\Icons\\INV_Misc_QuestionMark",  -- step button: item icon not known yet

    -- slot keys (resolved by Theme\Media.lua)
    ["slot.badge.disc"] = "glyph.step.disc",
    ["slot.badge.accept"] = "glyph.step.accept",
    ["slot.badge.turnin"] = "glyph.step.turnin",
    ["slot.badge.objective"] = "glyph.step.kill",
    ["slot.badge.collect"] = "glyph.step.collect",
    ["slot.badge.goto"] = "glyph.step.goto",
    ["slot.badge.level"] = "glyph.step.level",
    ["slot.badge.manual"] = "glyph.step.ring",
    ["slot.done"] = "glyph.step.done",
    ["slot.check.tick"] = "glyph.check.tick",
    ["slot.check.box"] = "glyph.check.box",
    ["slot.check.fill"] = "glyph.check.fill",
    ["slot.btn.menu"] = "glyph.btn.menu",
    ["slot.btn.small"] = "glyph.btn.small",
    ["slot.btn.expand"] = "glyph.btn.expand",
    ["slot.btn.lock"] = "glyph.btn.lock",
    ["slot.btn.unlock"] = "glyph.btn.unlock",
    ["slot.btn.close"] = "glyph.btn.close",
    ["slot.btn.prev"] = "glyph.btn.prev",
    ["slot.btn.next"] = "glyph.btn.next",
    ["slot.btn.caret"] = "glyph.btn.caret",
    -- NOW window (glyphs2.tga)
    ["slot.btn.grip"] = "glyph.btn.grip",
    ["slot.btn.attach"] = "glyph.btn.attach",
    ["slot.btn.detach"] = "glyph.btn.detach",
    -- the guide window's bottom-right size grip (glyphs2.tga)
    ["slot.btn.resize"] = "glyph.btn.resize",
    -- main window (glyphs2.tga, emblems.tga)
    ["slot.btn.search"] = "glyph.btn.search",
    ["slot.emblem.alliance"] = "emblem.alliance",
    ["slot.emblem.horde"] = "emblem.horde",
    ["slot.emblem.neutral"] = "emblem.neutral",
    ["slot.emblem.soon"] = "emblem.soon",
    ["slot.notice.danger"] = "glyph.notice.danger",
    ["slot.notice.tip"] = "glyph.notice.tip",
    ["slot.state.none"] = "glyph.state.none",
    ["slot.state.finished"] = "glyph.state.finished",
    ["slot.state.error"] = "glyph.state.error",
    ["slot.arrow"] = "tex.arrow",
    ["slot.arrived"] = "tex.arrived",
    ["slot.logo"] = "tex.logo",
    ["slot.logo.title"] = "tex.logo.title",   -- 16 px title-bar logo (logo_64 shrunk 4:1 looked jagged)
    -- v0.2 art
    ["slot.badge.learn"] = "glyph.step.learn",
    ["slot.badge.train"] = "glyph.step.train",
    ["slot.badge.note"] = "glyph.step.note",
    ["slot.badge.useitem"] = "glyph.step.useitem",
    ["slot.badge.grind"] = "glyph.step.grind",
    ["slot.badge.fly"] = "glyph.step.fly",
    ["slot.badge.hearth"] = "glyph.step.hearth",
    ["slot.badge.getfp"] = "glyph.step.getfp",
    ["slot.badge.sethearth"] = "glyph.step.sethearth",
    ["slot.notice.hearth"] = "glyph.notice.hearth",
    ["slot.notice.flight"] = "glyph.notice.flight",
    ["slot.notice.useitem"] = "glyph.notice.useitem",
    ["slot.notice.snooze"] = "glyph.notice.snooze",
    ["slot.btn.keybind"] = "glyph.btn.keybind",
    ["slot.btn.copy"] = "glyph.btn.copy",
    ["slot.state.wait"] = "glyph.notice.legacy",   -- icon review #10: a plain hourglass (the circled one read as "reload")
    ["slot.arrow.corpse"] = "glyph.arrow.corpse",
    ["slot.pin.body"] = "glyph.pin.body",
    ["slot.pin.face"] = "glyph.pin.face",
    ["slot.pin.mini"] = "glyph.pin.mini",
    ["slot.pin.ring"] = "glyph.pin.ring",
    ["slot.hub.report"] = "glyph.hub.report",
    ["slot.hub.about"] = "glyph.hub.about",
    ["slot.hub.settings"] = "glyph.hub.settings",
    ["slot.report.coords"] = "glyph.report.coords",
    ["slot.report.order"] = "glyph.report.order",
    ["slot.report.missing"] = "glyph.report.missing",
    ["slot.report.notick"] = "glyph.report.notick",
    ["slot.report.text"] = "glyph.report.text",
    ["slot.report.other"] = "glyph.report.other",
    ["slot.frame.stepbutton"] = "frame.stepbutton",
    ["slot.frame.glow"] = "frame.glow",
    ["slot.minimap"] = "tex.minimap",
    -- radio rows (look review #5): the ring and disc glyphs we already ship
    ["slot.radio.ring"] = "glyph.step.ring",
    ["slot.radio.dot"] = "glyph.step.disc",
    -- the one window (round.tga): 9-slices (a theme without them gets the flat panel), tiles, target button
    ["slot.frame.panel"] = "frame.panel",
    ["slot.frame.border"] = "frame.border",
    ["slot.frame.shadow"] = "frame.shadow",
    ["slot.round"] = "round.s",
    ["slot.btn.target"] = "btn.target",
    ["slot.frame.button"] = "frame.stepbutton2",
    ["slot.tile.base"] = "tile.base",
    ["slot.tile.open"] = "tile.open",
    ["slot.tile.accept"] = "tile.accept",
    ["slot.tile.turnin"] = "tile.turnin",
    ["slot.tile.kill"] = "tile.kill",
    ["slot.tile.loot"] = "tile.loot",
    ["slot.tile.use"] = "tile.use",
    ["slot.tile.goto"] = "tile.goto",
    ["slot.tile.talk"] = "tile.talk",
    ["slot.tile.train"] = "tile.train",
    ["slot.tile.fly"] = "tile.fly",
    ["slot.tile.hearth"] = "tile.hearth",
    ["slot.tile.note"] = "tile.note",
    ["slot.tile.done"] = "tile.done",
    ["slot.tile.level"] = "tile.level",
    ["slot.tile.grind"] = "tile.grind",
    ["slot.tile.getfp"] = "tile.getfp",
    ["slot.tile.sethearth"] = "tile.sethearth",

    -- motion (seconds; 0 with reduced motion)
    ["motion.flash"] = 0.7,
    ["motion.pulse"] = 1.0,       -- one loop of the step button's glow pulse (low -> 1 -> low)
    ["motion.arrowPulse"] = 0.3,  -- smart arrow: one arrow pulse (1 -> low -> 1) when a door / gate is passed
})

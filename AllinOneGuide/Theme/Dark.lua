-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The default theme "Dark": dark, slim, modern; our own colours and art (plans\default-theme\theme-notes.md).
-- Dimming is always by colour, never by text alpha. Whole-number font sizes.
local _, ns = ...

ns.Theme.Register("Dark", {
    -- colours: { "#rrggbb", alpha } or "=other.key"
    ["color.panel"] = { "#0B0E13", 0.80 },
    ["color.titleTop"] = { "#1B222C", 1 },
    ["color.titleBottom"] = { "#11161D", 1 },
    ["color.border"] = { "#2A3340", 1 },
    ["color.divider"] = { "#FFFFFF", 0.05 },
    ["color.text"] = { "#E4E8EE", 1 },
    ["color.title"] = { "#DCE2EA", 1 },
    ["color.accent"] = { "#2FC4A8", 1 },
    ["color.accentGlow"] = { "#2FC4A8", 0.17 },
    ["color.accentGlowEnd"] = { "#2FC4A8", 0.03 },
    ["color.barFrom"] = { "#1F9E86", 1 },
    ["color.barTo"] = { "#3AD9B8", 1 },
    ["color.barTrack"] = { "#1A212A", 1 },
    ["color.zone"] = { "#E9B65C", 1 },
    ["color.counter"] = { "#9AA4B2", 1 },
    ["color.quest"] = { "#F3D58C", 1 },
    ["color.npc"] = { "#9FD8FF", 1 },
    ["color.coord"] = { "#7FB8F0", 1 },
    ["color.text.dim"] = { "#8D97A4", 1 },
    ["color.done"] = { "#7A8390", 1 },
    ["color.upcoming"] = "=text.dim",
    ["color.stepNumber"] = { "#7A8390", 1 },
    ["color.goal"] = { "#C3CAD4", 1 },
    ["color.goalCount"] = "=text",
    ["color.goalDone"] = { "#6FD39A", 1 },
    ["color.goalDoneBox"] = { "#1E5E3E", 1 },
    ["color.goalDoneEdge"] = { "#3FAF74", 1 },
    ["color.goalBoxEmpty"] = { "#56606D", 1 },
    ["color.flash"] = { "#6FD39A", 0.45 },
    ["color.button"] = { "#A3ADBA", 1 },
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
    ["color.icon.grind"] = { "#B84A63", 1 },
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
    ["color.stepFrame"] = { "#56606D", 1 },
    ["color.stepFrameMissing"] = { "#E0524A", 1 },
    -- v0.2 look review: the Hub, dialog, copy box and menu (text over the world; the guide window keeps
    -- color.panel and the opacity setting)
    ["color.panelSolid"] = { "#0B0E13", 0.95 },
    ["color.arrowText"] = "=white",           -- the distance under the arrow
    -- smart arrow: while it leads to a door / gate / path point first (not the goal itself)
    ["color.arrowVia"] = { "#5CC8F0", 1 },    -- the arrow
    ["color.viaText"] = { "#8FD8F5", 1 },     -- "Through the abbey door" under the distance
    ["color.wait"] = "=notice.hearth",        -- the step button's hourglass
    ["color.minimap"] = "=white",             -- the minimap button while the guide is shown
    ["color.minimapDim"] = { "#999999", 1 },  -- ... and while it is hidden
    ["color.thumb"] = "=accent",              -- Hub scroll thumb
    ["color.thumbTrack"] = "=barTrack",
    -- v0.2 look review #5 / #6 / #7: shared buttons, radio rows, Hub nav selection, the done chip
    ["color.buttonFill"] = "=barTrack",       -- K.Button / the chip: the fill
    ["color.buttonPrimary"] = "=accent",      -- the primary button's text (Move, Yes)
    ["color.radio"] = "=goalBoxEmpty",        -- radio ring, not picked
    ["color.radioOn"] = "=accent",            -- radio ring + dot, picked
    ["color.navSelected"] = "=buttonHoverBg", -- the open Hub page's row box
    ["color.navBar"] = "=accent",             -- ... and its bar on the left
    -- the NOW box (current step in its own panel) and the NEXT section under it
    ["color.nowBg"] = { "#16202A", 0.90 },    -- the NOW box's own panel
    ["color.nowEdge"] = { "#2A3340", 1 },     -- its 1-unit border (= color.border)
    ["color.nowBar"] = "=accent",             -- its accent edge on the left
    ["color.nowHead"] = "=accent",            -- the small "NOW" header
    ["color.nextHead"] = "=text.dim",         -- the small "NEXT" header

    -- fonts (Blizzard's narrow font file on Western clients)
    fontFile = "Fonts\\ARIALN.TTF",
    lineSpacing = 1.35,
    ["font.title"] = { size = 12, shadow = true },
    ["font.header"] = { size = 12, shadow = true },
    ["font.step"] = { size = 12, shadow = true },
    ["font.goal"] = { size = 11, shadow = true },
    ["font.small"] = { size = 10 },
    ["font.arrow"] = { size = 15, flags = "OUTLINE" },
    ["font.buttonText"] = { size = 10, flags = "OUTLINE" },  -- count / key on the step button (busy icons)
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
    ["size.stepLines"] = 10,      -- the fixed step area in full mode, in step-font lines
    ["size.smallLines"] = 5,      -- in small mode
    ["size.border"] = 1,
    ["size.thumb"] = 3,           -- Hub scroll thumb width
    ["size.stepButtonGap"] = 10,  -- step button <-> guide window (the button frame sticks out 8)
    ["size.title"] = 22,          -- the one title bar (guide window, Hub, dialog, copy box)
    ["size.titleLogo"] = 16,
    ["size.buttonMin"] = 90,      -- K.Button: width = max(this, text + 24)
    ["size.navBar"] = 2,          -- the open Hub page's bar
    ["size.chipPad"] = 4,         -- the done chip's inner padding
    ["size.nowMargin"] = 4,       -- NOW box: inset from the step area's sides and top
    ["size.nowBar"] = 2,          -- NOW box: the accent edge's width
    ["size.nowPadBottom"] = 4,    -- NOW box: space under the current step
    ["size.sectionGap"] = 4,      -- space between the NOW box and the NEXT header

    -- alphas (0..1) and built-in game files (v0.2 look review)
    ["alpha.hover"] = 0.35,       -- the minimap button's highlight
    ["alpha.pulseLow"] = 0.4,     -- the step button's reminder glow pulses between this and 1
    ["alpha.arrowPulseLow"] = 0.35,  -- smart arrow: the arrow dips to this and back when a door / gate is passed
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
    ["slot.notice.danger"] = "glyph.notice.danger",
    ["slot.notice.tip"] = "glyph.notice.tip",
    ["slot.state.none"] = "glyph.state.none",
    ["slot.state.finished"] = "glyph.state.finished",
    ["slot.state.error"] = "glyph.state.error",
    ["slot.arrow"] = "tex.arrow",
    ["slot.arrived"] = "tex.arrived",
    ["slot.logo"] = "tex.logo",
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
    ["slot.state.wait"] = "glyph.state.wait",
    ["slot.arrow.corpse"] = "glyph.arrow.corpse",
    ["slot.pin.body"] = "glyph.pin.body",
    ["slot.pin.face"] = "glyph.pin.face",
    ["slot.pin.mini"] = "glyph.pin.mini",
    ["slot.pin.ring"] = "glyph.pin.ring",
    ["slot.hub.report"] = "glyph.hub.report",
    ["slot.hub.about"] = "glyph.hub.about",
    ["slot.hub.news"] = "glyph.hub.news",
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

    -- motion (seconds; 0 with reduced motion)
    ["motion.flash"] = 0.7,
    ["motion.pulse"] = 1.0,       -- one loop of the step button's glow pulse (low -> 1 -> low)
    ["motion.arrowPulse"] = 0.3,  -- smart arrow: one arrow pulse (1 -> low -> 1) when a door / gate is passed
})

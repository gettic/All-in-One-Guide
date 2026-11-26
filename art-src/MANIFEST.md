<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Art manifest

All art in `AllinOneGuide/media/` is our own (the OFL fonts in `media/fonts/` are not art and not ours: see "Fonts"), drawn in code by the scripts in this folder (GPL-3.0-or-later). Rebuild with plain Python 3 from the repository root (`python -B art-src/<script>.py`; `-B` keeps `__pycache__` out). The scripts are deterministic: same bytes every run. `aog_art.py` holds the shared drawing helpers.

All files: TGA, 32-bit BGRA, straight alpha, uncompressed (type 2), bottom-left origin, power-of-two sizes. In-game path: `Interface\AddOns\AllinOneGuide\media\<name>` (no extension).

| File (in `AllinOneGuide/media/`) | Size | Raw memory | Built by | Used for | Version / theme |
|---|---|---|---|---|---|
| `logo_64.tga` | 64x64 | 16 KB | `build_logo.py` | .toc `IconTexture`, About page (48 px); not the 16 px title bar (see "Title-bar logo") | v0.1, all themes |
| `glyphs.tga` | 256x256 | 256 KB | `build_glyphs.py` | step badges, notice glyphs, buttons, states, pins, Hub / report icons (slots below) | v0.1 + v0.2, Dark (Blizzard theme fallback) |
| `arrow.tga` | 128x128 | 64 KB | `build_arrow.py` | waypoint arrow, shown 64x64 | v0.1, Dark |
| `arrived.tga` | 128x128 | 64 KB | `build_arrow.py` | arrived marker (tick ring), shown 64x64 | v0.1, Dark |
| `frames.tga` | 128x64 | 32 KB | `build_frames.py` | step button frame + reminder glow (regions below) | v0.2, Dark |
| `minimap.tga` | 32x32 | 4 KB | `build_minimap.py` | minimap button (whole round button, full colour) | v0.2, all themes |
| `glyphs2.tga` | 256x32 | 32 KB | `build_window_art.py` | NOW window + main window buttons: grip, attach, detach, search, resize (cells below); cell 7: the title-bar logo (full colour) | NOW + main window, Dark (Blizzard theme fallback) |
| `emblems.tga` | 256x64 | 64 KB | `build_window_art.py` | guide emblems (shields) on the main window's Guides cards (regions below) | main window, all themes |
| `round.tga` | 256x64 | 64 KB | `build_round.py` | rounded window look (4e): window panel / border / shadow 9-slices, small rounded 9-slice, target crosshair, rounded button frame, tile icons (regions below) | one-window look, Dark |

**Total raw texture memory: 660 KB** (old budget 600 KB: `round.tga` (64 KB, asked for by the guide-window-look build plan) goes 60 KB over it; zipped it adds only ~6 KB).

Note for the `.toc`: the build plan says `IconTexture: ...\media\logo`, but the file is `logo_64` (no `logo.tga` exists). Point `IconTexture` at `Interface\AddOns\AllinOneGuide\media\logo_64`.

## Fonts (`AllinOneGuide/media/fonts/`, not our art)

The text fonts are not drawn by us: they are subsets of two SIL Open Font License 1.1 fonts (they stay under the OFL; licence and copyright notices in `media/fonts/OFL.txt`), built by `tools/build_fonts.py` (`python -B tools/build_fonts.py --opensans <ttf> --opensans-ofl <OFL.txt> --dyslexic <otf> --dyslexic-ofl <OFL.txt> --out AllinOneGuide/media/fonts`; same bytes every run; `--check <dir>` is run by the release zip check). Used through `Theme/Media.lua` `Md.FONTS` (text font setting).

- `OpenSans.ttf` (38,896 bytes): Open Sans SemiBold, static, hinted. Source: https://github.com/googlefonts/opensans `fonts/ttf/OpenSans-SemiBold.ttf` and `OFL.txt`, commit `bd7e37632246368c60fdcbd374dbf9bad11969b6` (2023-11-16); source file SHA-256 `4A413711684A9DD564EF0F1C10CB62B5D9F7EB6DF2CFF962F5341A6ECD5F64AE`. No Reserved Font Name.
- `AOGReadable.ttf` (45,964 bytes): OpenDyslexic Regular, CFF outlines turned into TrueType outlines (no hinting), renamed "AOG Readable" because "OpenDyslexic" is the font's OFL Reserved Font Name. Source: https://github.com/antijingoist/opendyslexic `compiled/OpenDyslexic-Regular.otf`, commit `77bda89f3f2069c78d81d33de43b461c2de6c48e` (2025-04-10), and `OFL.txt` (commit `681cad29afcaf1f11b4952b07c7a0fbb776d6f9c`); source file SHA-256 `32F5840FB2BF844BDABAFE372591DDFB9286E98117F5B21950AAF54EA856919A`.
- Both keep U+0020-007E, U+00A0-017F, dashes, quotes, bullet, ellipsis, euro, TM and arrows where the font has them.

## Logo

Design "Waypoint" (direction A, in use): round dark badge, teal ring, two-tone teal arrow pointing up-right with three route dots behind it. Single image, texture coordinates (0, 1, 0, 1); transparent outside the circle. Direction B ("Guide book") is a preview only (not in `media/`).

## minimap.tga

The whole minimap button: round dark badge, thicker teal ring, logo mark simplified for ~31 px (A: bigger arrow, two route dots). Full colour, **not tinted**; texture coordinates (0, 1, 0, 1); transparent outside the circle (no extra border needed; highlight: the same texture with blend mode `ADD` at ~0.35 alpha). **Swapping the logo:** `build_minimap.py` has `LOGO = "A"`; set it to `"B"` (or run `python -B art-src/build_minimap.py B`) for the Guide-book mark in the same round badge. Same file name, size and coords, so no code change.

## round.tga regions

256x64, white / grey, tinted with `SetVertexColor`. 9-slice pieces: for (l, r, t, b) with corner (du, dv) use u = l, l+du, r-du, r and v = t, t+dv, b-dv, b; corners fixed on screen, edges and centre stretched.

| Key | l | r | t | b | Corner du / dv | Shown |
|---|---|---|---|---|---|---|
| `frame.panel` | 0.000 | 0.125 | 0.000 | 0.500 | 0.0546875 / 0.21875 (14 px, r 14) | corner `size.corner` 10, tint `color.panel` |
| `frame.border` | 0.000 | 0.125 | 0.500 | 1.000 | 0.0546875 / 0.21875 | same shape, 1.5 px ring (1 px at corner 10), tint `color.border` |
| `frame.shadow` | 0.250 | 0.500 | 0.000 | 1.000 | 0.10546875 / 0.421875 (27 px) | hollow soft shadow; corner `size.shadow + size.corner` (18), frame = window + `size.shadow` (8) each side, tint `color.shadow` |
| `round.s` | 0.125 | 0.250 | 0.000 | 0.500 | 0.03125 / 0.125 (8 px, r 8) | corner = wanted radius (buttons 6, chips 4, header buttons 3, bar 5) |
| `btn.target` | 0.125 | 0.250 | 0.500 | 1.000 | single | crosshair glyph (white + 1 px dark rim), ~28 px, #FF8C7A |
| `frame.stepbutton2` | 0.500 | 0.750 | 0.000 | 1.000 | single | 52x52 centred on the 36x36 button; 34 px see-through hole r 5, dark band baked in, tinted ring (#4A4A50, reminder #C8102E) |

Tiles: 4 x 4 cells of 16x16 at x 192-255; cell c: l = 0.75 + 0.0625 * (c % 4), r = l + 0.0625, t = 0.25 * floor(c / 4), b = t + 0.25. `tile.base` (c 0, tinted with the step colour) with a symbol on top (white, or dark #2A1F00 on yellow): 2 `tile.accept` (!), 3 `tile.turnin` (?), 4 `tile.kill` (X), 5 `tile.loot` (sack), 6 `tile.use` (flask), 7 `tile.goto` (arrowhead), 8 `tile.talk` (bubble), 9 `tile.train` (double chevron), 10 `tile.fly` (bird), 11 `tile.hearth` (house), 12 `tile.note` (i), 13 `tile.done` (tick). 1 `tile.open`: whole empty tile (ring + dark middle). 14-15 spare. Shown 12-16 px.
## glyphs2.tga cells

One row of 8 cells, 32x32 each; cell `i`: l = `i/8`, r = `(i+1)/8`, **t = 0, b = 1**. Same style as `glyphs.tga`: white with a baked 1 px dark rim, inside the middle 28x28 (2 px clear padding), coloured with `SetVertexColor` (suggested: #A3ADBA, hover white, active / selected accent #2FC4A8).

| Cell | Key | Glyph | l | r | t | b | Shown |
|---|---|---|---|---|---|---|---|
| 0 | `glyph.btn.grip` | drag handle: 2 x 3 dots (NOW strip, left) | 0.000 | 0.125 | 0.000 | 1.000 | 14-16 px |
| 1 | `glyph.btn.attach` | whole chain, two linked links (shown while the NOW window is free: click = attach) | 0.125 | 0.250 | 0.000 | 1.000 | 14 px |
| 2 | `glyph.btn.detach` | broken chain, two links apart + break marks (shown while attached: click = detach) | 0.250 | 0.375 | 0.000 | 1.000 | 14 px |
| 3 | `glyph.btn.search` | magnifier (main window search box) | 0.375 | 0.500 | 0.000 | 1.000 | 12 px, #A3ADBA |
| 4 | `glyph.btn.resize` | resize corner: 6 dots in a triangle, bottom-right (optional) | 0.500 | 0.625 | 0.000 | 1.000 | 14 px |
| 5-6 | (spare) | empty | | | | | |
| 7 | (logo) | the title-bar logo, full colour, see "Title-bar logo" below (not a slot) | | | | | |

The lock in the NOW strip reuses `glyph.btn.lock` / `glyph.btn.unlock` (`glyphs.tga` slots 26 / 27).

## Title-bar logo (glyphs2.tga cell 7)

The same "Waypoint" logo as `logo_64.tga` (same drawing, `build_logo.logo_waypoint()`), rendered at **28x28** with an even 16x16 box filter, placed in the middle of cell 7 with **2 px clear padding**, transparent pixels given their neighbours' colour (alpha 0) so filtering never pulls black into the edge. Full colour, **not tinted**. Region key (use these coords, not the full cell, so it stays the same visible size as before):

| Key | File | l | r | t | b | Shown |
|---|---|---|---|---|---|---|
| `tex.logo.title` | glyphs2 | 0.8828125 | 0.9921875 | 0.0625 | 0.9375 | 16x16 UI units (title bar, `size.titleLogo`); also fine up to ~28 |

Why: `logo_64.tga` shown at 16 units is shrunk 2.8:1 to 4:1 on screen; the game samples it with plain bilinear filtering (no smaller copies), so most texels are skipped and the thin ring, route dots and arrow edges come out jagged. 28 texels for 16-30 screen px keeps every shrink under 2:1. In code: a `Md.REGIONS` entry with these coords, `slot.logo.title` in the theme, and the texture drawn without pixel-grid / texel snapping.

## emblems.tga regions

Four 64x64 shields, full colour, **not tinted**; our own shield shape (arched-in top, bevelled metal rim, field lit left / shaded right), not the game's faction crests. Transparent outside the shield with a soft 2 px shadow. Shown ~40x40 on the Guides cards; for a dimmed card use alpha (~0.55) or `SetDesaturated`.

| Key | Emblem | l | r | t | b |
|---|---|---|---|---|---|
| `emblem.alliance` | blue field, gold rim, four-point star | 0.000 | 0.250 | 0.000 | 1.000 |
| `emblem.horde` | red field, gold rim, chevron + diamond | 0.250 | 0.500 | 0.000 | 1.000 |
| `emblem.neutral` | both factions: teal field, silver rim, route arrow | 0.500 | 0.750 | 0.000 | 1.000 |
| `emblem.soon` | coming soon: grey field and rim, plus | 0.750 | 1.000 | 0.000 | 1.000 |

## frames.tga regions

| Key | Region | l | r | t | b | Shown | Tint |
|---|---|---|---|---|---|---|---|
| `frame.stepbutton` | step button frame: rounded square, top-lit bevel, see-through middle | 0.000 | 0.500 | 0.000 | 1.000 | 52x52 centred on the 36x36 button (the hole is ~36 px) | normal #56606D, reminder #2FC4A8, item missing #E0524A |
| `frame.glow` | reminder glow: soft rounded-square halo, white, alpha only | 0.500 | 1.000 | 0.000 | 1.000 | 72x72 centred on the button, layer below the frame, blend `ADD` (or `BLEND`), pulse with alpha | #2FC4A8 |

## arrow.tga / arrived.tga

- Single image each, texture coordinates (0, 1, 0, 1). White / grey in the file; colour with `SetVertexColor` (ahead #43D18C, side #E8C547, behind #F0625A; arrived #43D18C). Colour-blind scale (v0.2 M4) is tint data only, no new art: blue #4DA3F0 to orange #F08A3C. Corpse arrow: tint #C9D3DF and show `glyph.arrow.corpse` (20 px) under it.
- `arrow.tga` points **straight up** at rotation 0, rotation centre = texture centre. Everything (dart, 2 px dark rim, soft round shadow) stays inside the inscribed circle, so `SetRotation` or the 8-argument `SetTexCoord` rotation never clips it. Lit left half (white), shaded right half (grey ~70 %).
- `arrived.tga`: tick inside a ring, over a dark see-through disc (stays dark when tinted), 2 px dark rim, soft round shadow.

## glyphs.tga slots

8 x 8 grid of 32x32 slots; slot `i` is at column `i % 8`, row `i // 8`, row 0 at the **top** of the picture (WoW texture coordinate t = 0 is the top). Each glyph is white with a baked 1 px dark rim and sits in the middle 28x28 of its slot (2 px clear padding), so the full-slot coordinates below are safe with bilinear filtering. Colour with `SetVertexColor`.

**Badges:** draw `glyph.step.disc` tinted with the step colour, and the step glyph on top (same size, same coords set). Accept / turn in: disc #F4C542, glyph #2A1F00. Kill: #E0524A + white. Collect: #E39A3B + white. Goto: #4DA3F0 + white. Level: accent #2FC4A8 + white.
**v0.2 badges** (white glyph on each; colours are suggestions for the theme table, changeable): learn / train #9C7CF0, note #6B7686, useitem #C86BD6, grind #B84A63, fly / getfp #3BA9D9, hearth / sethearth #D8643C.
**Ticked goal box:** `glyph.check.fill` #1E5E3E, `glyph.check.box` #3FAF74, `glyph.check.tick` (white or #6FD39A). Open box: `glyph.check.box` #56606D.
**Caret:** points right; for "open" (down) rotate 90 degrees with `SetRotation` or swap coords.

| Slot | Key | Glyph | l | r | t | b |
|---|---|---|---|---|---|---|
| 0 | `glyph.step.disc` | badge disc (soft top-to-bottom light) | 0.000 | 0.125 | 0.000 | 0.125 |
| 1 | `glyph.step.ring` | badge ring / outline | 0.125 | 0.250 | 0.000 | 0.125 |
| 2 | `glyph.step.accept` | "!" | 0.250 | 0.375 | 0.000 | 0.125 |
| 3 | `glyph.step.turnin` | "?" | 0.375 | 0.500 | 0.000 | 0.125 |
| 4 | `glyph.step.kill` | target | 0.500 | 0.625 | 0.000 | 0.125 |
| 5 | `glyph.step.collect` | sack | 0.625 | 0.750 | 0.000 | 0.125 |
| 6 | `glyph.step.goto` | map pin | 0.750 | 0.875 | 0.000 | 0.125 |
| 7 | `glyph.step.done` | done tick (done step, done chip) | 0.875 | 1.000 | 0.000 | 0.125 |
| 8 | `glyph.check.tick` | bold tick for the 10 px goal box | 0.000 | 0.125 | 0.125 | 0.250 |
| 9 | `glyph.step.level` | level up: arrow on a bar | 0.125 | 0.250 | 0.125 | 0.250 |
| 10 | `glyph.check.box` | goal checkbox outline (rounded) | 0.250 | 0.375 | 0.125 | 0.250 |
| 11 | `glyph.check.fill` | goal checkbox fill (rounded) | 0.375 | 0.500 | 0.125 | 0.250 |
| 12 | `glyph.step.learn` | learn: open book (v0.2) | 0.500 | 0.625 | 0.125 | 0.250 |
| 13 | `glyph.step.train` | train: double chevron up (v0.2) | 0.625 | 0.750 | 0.125 | 0.250 |
| 14 | `glyph.step.note` | note: page with folded corner (v0.2) | 0.750 | 0.875 | 0.125 | 0.250 |
| 15 | `glyph.step.useitem` | use item: potion flask (v0.2) | 0.875 | 1.000 | 0.125 | 0.250 |
| 16 | `glyph.notice.danger` | warning triangle | 0.000 | 0.125 | 0.250 | 0.375 |
| 17 | `glyph.notice.usenow` | bolt (use item now) | 0.125 | 0.250 | 0.250 | 0.375 |
| 18 | `glyph.notice.travel` | wing (hearth / flight) | 0.250 | 0.375 | 0.250 | 0.375 |
| 19 | `glyph.notice.class` | shield | 0.375 | 0.500 | 0.250 | 0.375 |
| 20 | `glyph.notice.legacy` | hourglass | 0.500 | 0.625 | 0.250 | 0.375 |
| 21 | `glyph.notice.tip` | light bulb | 0.625 | 0.750 | 0.250 | 0.375 |
| 22 | `glyph.notice.new` | sparkle | 0.750 | 0.875 | 0.250 | 0.375 |
| 23 | `glyph.notice.hidden` | eye, slashed (hidden hints count) | 0.875 | 1.000 | 0.250 | 0.375 |
| 24 | `glyph.btn.menu` | three lines | 0.000 | 0.125 | 0.375 | 0.500 |
| 25 | `glyph.btn.small` | bar (small mode) | 0.125 | 0.250 | 0.375 | 0.500 |
| 26 | `glyph.btn.lock` | padlock, closed | 0.250 | 0.375 | 0.375 | 0.500 |
| 27 | `glyph.btn.unlock` | padlock, open | 0.375 | 0.500 | 0.375 | 0.500 |
| 28 | `glyph.btn.close` | X | 0.500 | 0.625 | 0.375 | 0.500 |
| 29 | `glyph.btn.prev` | "<" | 0.625 | 0.750 | 0.375 | 0.500 |
| 30 | `glyph.btn.next` | ">" | 0.750 | 0.875 | 0.375 | 0.500 |
| 31 | `glyph.btn.caret` | small ">" (done chip) | 0.875 | 1.000 | 0.375 | 0.500 |
| 32 | `glyph.state.none` | dashed ring with a dot (no guide) | 0.000 | 0.125 | 0.500 | 0.625 |
| 33 | `glyph.state.finished` | flag (route finished) | 0.125 | 0.250 | 0.500 | 0.625 |
| 34 | `glyph.state.error` | circle with X cut out | 0.250 | 0.375 | 0.500 | 0.625 |
| 35 | `glyph.btn.expand` | window box (expand from small mode) | 0.375 | 0.500 | 0.500 | 0.625 |
| 36 | `glyph.step.grind` | grind: crossed swords (v0.2) | 0.500 | 0.625 | 0.500 | 0.625 |
| 37 | `glyph.step.fly` | fly: bird in flight (v0.2) | 0.625 | 0.750 | 0.500 | 0.625 |
| 38 | `glyph.step.hearth` | hearth: house (v0.2) | 0.750 | 0.875 | 0.500 | 0.625 |
| 39 | `glyph.step.getfp` | get flight path: bird + plus (v0.2) | 0.875 | 1.000 | 0.500 | 0.625 |
| 40 | `glyph.step.sethearth` | set hearth: house + plus (v0.2) | 0.000 | 0.125 | 0.625 | 0.750 |
| 41 | `glyph.notice.hearth` | hearthstone reminder: stone with a house (v0.2) | 0.125 | 0.250 | 0.625 | 0.750 |
| 42 | `glyph.notice.flight` | flight path reminder: route dots + bird (v0.2) | 0.250 | 0.375 | 0.625 | 0.750 |
| 43 | `glyph.notice.useitem` | use-it-now reminder: item slot with a bolt (v0.2) | 0.375 | 0.500 | 0.625 | 0.750 |
| 44 | `glyph.btn.keybind` | keybind: key cap (v0.2) | 0.500 | 0.625 | 0.625 | 0.750 |
| 45 | `glyph.state.wait` | waiting for combat to end: hourglass in a circular arrow (v0.2) | 0.625 | 0.750 | 0.625 | 0.750 |
| 46 | `glyph.notice.snooze` | snooze: moon + z (v0.2) | 0.750 | 0.875 | 0.625 | 0.750 |
| 47 | `glyph.arrow.corpse` | corpse marker: gravestone (v0.2) | 0.875 | 1.000 | 0.625 | 0.750 |
| 48 | `glyph.pin.body` | map pin body, tip at the bottom centre (v0.2) | 0.000 | 0.125 | 0.750 | 0.875 |
| 49 | `glyph.pin.face` | map pin number plate, same size and anchor as the body, on top (v0.2) | 0.125 | 0.250 | 0.750 | 0.875 |
| 50 | `glyph.pin.mini` | minimap pin: dot in a ring (v0.2) | 0.250 | 0.375 | 0.750 | 0.875 |
| 51 | `glyph.pin.ring` | target ring: four arcs (current target pin) (v0.2) | 0.375 | 0.500 | 0.750 | 0.875 |
| 52 | `glyph.hub.report` | Hub: Report a mistake, bubble with "!" (v0.2) | 0.500 | 0.625 | 0.750 | 0.875 |
| 53 | `glyph.hub.about` | Hub: About, "i" in a circle (v0.2) | 0.625 | 0.750 | 0.750 | 0.875 |
| 54 | `glyph.hub.news` | Hub: What's new, megaphone (v0.2) | 0.750 | 0.875 | 0.750 | 0.875 |
| 55 | `glyph.hub.settings` | Hub / menu: settings, gear (v0.2) | 0.875 | 1.000 | 0.750 | 0.875 |
| 56 | `glyph.report.coords` | report type wrong coords: pin + x (v0.2) | 0.000 | 0.125 | 0.875 | 1.000 |
| 57 | `glyph.report.order` | report type wrong order: swap arrows (v0.2) | 0.125 | 0.250 | 0.875 | 1.000 |
| 58 | `glyph.report.missing` | report type quest missing / not available: "!" crossed out (v0.2) | 0.250 | 0.375 | 0.875 | 1.000 |
| 59 | `glyph.report.notick` | report type step won't tick: box + x (v0.2) | 0.375 | 0.500 | 0.875 | 1.000 |
| 60 | `glyph.report.text` | report type text wrong: "T" with a wavy line (v0.2) | 0.500 | 0.625 | 0.875 | 1.000 |
| 61 | `glyph.report.other` | report type other: three dots (v0.2) | 0.625 | 0.750 | 0.875 | 1.000 |
| 62 | `glyph.btn.copy` | copy (copy box): two sheets (v0.2) | 0.750 | 0.875 | 0.875 | 1.000 |
| 63 | (spare) | empty | | | | |

Slots 9, 10, 11 and 35 are extras beyond the theme-notes list (level step type, rounded goal box, expand button); the code may draw the goal box with `SetColorTexture` instead.

### v0.2 glyph use (suggested tints and sizes, changeable)

| Keys | Shown | Tint |
|---|---|---|
| `glyph.notice.hearth`, `glyph.state.wait` | 16 px (wait: on the step button's top-right corner) | #E9B65C |
| `glyph.notice.flight` | 16 px | #9FD8FF |
| `glyph.notice.useitem` | 16 px | #F4C542 |
| `glyph.btn.keybind`, `glyph.btn.copy` | 16 px | #A3ADBA (hover white) |
| `glyph.notice.snooze` | 16 px | #8D97A4 |
| `glyph.arrow.corpse` | 20 px under the arrow | #C9D3DF |
| `glyph.pin.body` + `glyph.pin.face` | 24 px, anchor the slot's bottom centre ~4 px below the spot (tip at 88 % of the slot height); number text white, bold ~10 px, centred 38 % from the top | body: step colour or #2FC4A8; face #0B0E13 |
| `glyph.pin.mini` | 12 px on the minimap | #2FC4A8 |
| `glyph.pin.ring` | 1.5x the pin / dot size, centred on the pin head | #FFFFFF |
| `glyph.hub.*` | 18 px nav icons | #A3ADBA, selected page #2FC4A8 |
| `glyph.report.*` | 16 px in the type list | #C3CAD4; the "danger" type uses `glyph.notice.danger` #F0625A |

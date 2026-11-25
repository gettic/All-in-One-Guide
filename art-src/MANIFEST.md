<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Art manifest

All art in `AllinOneGuide/media/` is our own, drawn in code by the scripts in this folder (GPL-3.0-or-later). Rebuild with plain Python 3 from the repository root (`python -B art-src/<script>.py`; `-B` keeps `__pycache__` out). The scripts are deterministic: same bytes every run. `aog_art.py` holds the shared drawing helpers.

All files: TGA, 32-bit BGRA, straight alpha, uncompressed (type 2), bottom-left origin, power-of-two sizes. In-game path: `Interface\AddOns\AllinOneGuide\media\<name>` (no extension).

| File (in `AllinOneGuide/media/`) | Size | Raw memory | Built by | Used for | Version / theme |
|---|---|---|---|---|---|
| `logo_64.tga` | 64x64 | 16 KB | `build_logo.py` | .toc `IconTexture`, About page | v0.1, all themes |
| `glyphs.tga` | 256x256 | 256 KB | `build_glyphs.py` | step badges, notice glyphs, buttons, states, pins, Hub / report icons (slots below) | v0.1 + v0.2, Dark (Blizzard theme fallback) |
| `arrow.tga` | 128x128 | 64 KB | `build_arrow.py` | waypoint arrow, shown 64x64 | v0.1, Dark |
| `arrived.tga` | 128x128 | 64 KB | `build_arrow.py` | arrived marker (tick ring), shown 64x64 | v0.1, Dark |
| `frames.tga` | 128x64 | 32 KB | `build_frames.py` | step button frame + reminder glow (regions below) | v0.2, Dark |
| `minimap.tga` | 32x32 | 4 KB | `build_minimap.py` | minimap button (whole round button, full colour) | v0.2, all themes |

**Total raw texture memory: 500 KB** (budget at v0.1-v0.2: 600 KB; 100 KB left).

Note for the `.toc`: the build plan says `IconTexture: ...\media\logo`, but the file is `logo_64` (no `logo.tga` exists). Point `IconTexture` at `Interface\AddOns\AllinOneGuide\media\logo_64`.

## Logo

Design "Waypoint" (direction A, in use): round dark badge, teal ring, two-tone teal arrow pointing up-right with three route dots behind it. Single image, texture coordinates (0, 1, 0, 1); transparent outside the circle. Direction B ("Guide book") is a preview only (not in `media/`).

## minimap.tga

The whole minimap button: round dark badge, thicker teal ring, logo mark simplified for ~31 px (A: bigger arrow, two route dots). Full colour, **not tinted**; texture coordinates (0, 1, 0, 1); transparent outside the circle (no extra border needed; highlight: the same texture with blend mode `ADD` at ~0.35 alpha). **Swapping the logo:** `build_minimap.py` has `LOGO = "A"`; set it to `"B"` (or run `python -B art-src/build_minimap.py B`) for the Guide-book mark in the same round badge. Same file name, size and coords, so no code change.

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

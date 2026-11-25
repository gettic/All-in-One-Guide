<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Art manifest

All art in `AllinOneGuide/media/` is our own, drawn in code by the scripts in this folder (GPL-3.0-or-later). Rebuild with plain Python 3 from the repository root (`python -B art-src/<script>.py`; `-B` keeps `__pycache__` out). The scripts are deterministic: same bytes every run. `aog_art.py` holds the shared drawing helpers.

All files: TGA, 32-bit BGRA, straight alpha, uncompressed (type 2), bottom-left origin, power-of-two sizes. In-game path: `Interface\AddOns\AllinOneGuide\media\<name>` (no extension).

| File (in `AllinOneGuide/media/`) | Size | Raw memory | Built by | Used for | Version / theme |
|---|---|---|---|---|---|
| `logo_64.tga` | 64x64 | 16 KB | `build_logo.py` | .toc `IconTexture`, minimap button (~20 px), About page | v0.1, all themes |
| `logo_128.tga` | 128x128 | 64 KB | `build_logo.py` | About page / larger displays | v0.1, all themes |
| `glyphs.tga` | 256x256 | 256 KB | `build_glyphs.py` | step badges, notice glyphs, window buttons, states (slots below) | v0.1, Dark (Blizzard theme fallback) |
| `arrow.tga` | 128x128 | 64 KB | `build_arrow.py` | waypoint arrow, shown 64x64 | v0.1, Dark |
| `arrived.tga` | 128x128 | 64 KB | `build_arrow.py` | arrived marker (tick ring), shown 64x64 | v0.1, Dark |

**Total raw texture memory: 464 KB** (budget at v0.1-v0.2: 600 KB).

Note for the `.toc`: the build plan says `IconTexture: ...\media\logo`, but the file is `logo_64` (no `logo.tga` exists). Point `IconTexture` at `Interface\AddOns\AllinOneGuide\media\logo_64`.

## Logo

Design "Waypoint" (direction A, in use): round dark badge, teal ring, two-tone teal arrow pointing up-right with three route dots behind it. Single image, texture coordinates (0, 1, 0, 1); transparent outside the circle. Direction B ("Guide book") is a preview only (not in `media/`).

## arrow.tga / arrived.tga

- Single image each, texture coordinates (0, 1, 0, 1). White / grey in the file; colour with `SetVertexColor` (ahead #43D18C, side #E8C547, behind #F0625A; arrived #43D18C).
- `arrow.tga` points **straight up** at rotation 0, rotation centre = texture centre. Everything (dart, 2 px dark rim, soft round shadow) stays inside the inscribed circle, so `SetRotation` or the 8-argument `SetTexCoord` rotation never clips it. Lit left half (white), shaded right half (grey ~70 %).
- `arrived.tga`: tick inside a ring, over a dark see-through disc (stays dark when tinted), 2 px dark rim, soft round shadow.

## glyphs.tga slots

8 x 8 grid of 32x32 slots; slot `i` is at column `i % 8`, row `i // 8`, row 0 at the **top** of the picture (WoW texture coordinate t = 0 is the top). Each glyph is white with a baked 1 px dark rim and sits in the middle 28x28 of its slot (2 px clear padding), so the full-slot coordinates below are safe with bilinear filtering. Colour with `SetVertexColor`.

**Badges:** draw `glyph.step.disc` tinted with the step colour, and the step glyph on top (same size, same coords set). Accept / turn in: disc #F4C542, glyph #2A1F00. Kill: #E0524A + white. Collect: #E39A3B + white. Goto: #4DA3F0 + white. Level: accent #2FC4A8 + white.
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
| 12-15 | (spare) | empty | | | | |
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
| 36-63 | (spare) | empty | | | | |

Slots 9, 10, 11 and 35 are extras beyond the theme-notes list (level step type, rounded goal box, expand button); the code may draw the goal box with `SetColorTexture` instead.

# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - glyph sheet builder (default "Dark" theme, v0.1 slots).
# Copyright (C) 2026 All-in-One Guide contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU
# General Public License for details: <https://www.gnu.org/licenses/>.
#
# Plain Python 3, deterministic. Run: python art-src/build_glyphs.py
# Writes only AllinOneGuide/media/glyphs.tga: 256x256, 8x8 grid of 32x32
# slots, slot i at column i % 8, row i // 8 (row 0 = top). Every glyph is
# white (tinted in game with SetVertexColor) with a baked 1 px dark rim;
# content stays inside the slot's middle 28x28 (2 px clear padding).
# Slot list and texture coordinates: art-src/MANIFEST.md.
import math, os
from aog_art import (MEDIA, Mask, arc, capsule, circle, compose, down, lens, poly,
                     polyline, ring, rrect, write_tga)

SS = 4                 # supersampling per output pixel
CELL = 32              # slot size in the file
N = CELL * SS          # supersampled slot size
RIM = (0.02, 0.03, 0.04, 0.88)   # baked dark rim colour / alpha


def disc_shade(x, y):  # soft top-to-bottom light on the badge disc
    return 1.0 - 0.14 * max(0.0, min(1.0, (y - 0.1) / 0.8))


def shield(sc=1.0, cx=0.5, cy=0.5):
    pts = [(0.24, 0.16), (0.76, 0.16), (0.76, 0.46)]
    for k in range(1, 9):              # right curve down to the point
        t = k / 8
        x = (1 - t) ** 2 * 0.76 + 2 * (1 - t) * t * 0.76 + t * t * 0.5
        y = (1 - t) ** 2 * 0.46 + 2 * (1 - t) * t * 0.74 + t * t * 0.88
        pts.append((x, y))
    left = [(1 - x, y) for x, y in reversed(pts[3:-1])]
    pts = pts + left + [(0.24, 0.46)]
    return poly([(cx + (x - cx) * sc, cy + (y - cy) * sc) for x, y in pts])


def lock_body(m):
    m.add(rrect(0.25, 0.46, 0.75, 0.84, 0.06))
    m.sub(circle(0.5, 0.61, 0.055))
    m.sub(capsule((0.5, 0.62), (0.5, 0.72), 0.05))


# ------------------------------------------------------------------ glyphs
def g_disc(m): m.add(circle(0.5, 0.5, 0.40), disc_shade)
def g_ring(m): m.add(ring(0.5, 0.5, 0.31, 0.40))


def g_accept(m):
    m.add(capsule((0.5, 0.27), (0.5, 0.55), 0.13))
    m.add(circle(0.5, 0.72, 0.075))


def g_turnin(m):
    m.add(arc(0.5, 0.38, 0.135, 0.12, 180, 410))
    m.add(capsule((0.5 + 0.135 * math.cos(math.radians(50)), 0.38 + 0.135 * math.sin(math.radians(50))),
                  (0.5, 0.56), 0.12))
    m.add(circle(0.5, 0.73, 0.075))


def g_kill(m):
    m.add(ring(0.5, 0.5, 0.155, 0.245))
    m.add(circle(0.5, 0.5, 0.065))
    for a, b in (((0.5, 0.21), (0.5, 0.13)), ((0.5, 0.79), (0.5, 0.87)),
                 ((0.21, 0.5), (0.13, 0.5)), ((0.79, 0.5), (0.87, 0.5))):
        m.add(capsule(a, b, 0.075))


def g_collect(m):
    m.add(circle(0.5, 0.63, 0.21))
    m.add(poly([(0.43, 0.38), (0.57, 0.38), (0.63, 0.48), (0.37, 0.48)]))
    m.add(poly([(0.34, 0.22), (0.5, 0.29), (0.66, 0.22), (0.6, 0.36), (0.4, 0.36)]))
    m.sub(rrect(0.37, 0.355, 0.63, 0.395, 0.0))


def g_goto(m):
    m.add(circle(0.5, 0.41, 0.18))
    m.add(poly([(0.345, 0.50), (0.655, 0.50), (0.5, 0.80)]))
    m.sub(circle(0.5, 0.41, 0.07))


def g_done(m): m.add(polyline([(0.28, 0.52), (0.43, 0.67), (0.73, 0.35)], 0.115))
def g_tick(m): m.add(polyline([(0.19, 0.52), (0.41, 0.74), (0.82, 0.28)], 0.16))


def g_level(m):
    m.add(poly([(0.5, 0.17), (0.79, 0.47), (0.21, 0.47)]))
    m.add(rrect(0.40, 0.45, 0.60, 0.70, 0.02))
    m.add(rrect(0.27, 0.75, 0.73, 0.84, 0.03))


def g_box(m):
    m.add(rrect(0.16, 0.16, 0.84, 0.84, 0.12))
    m.sub(rrect(0.255, 0.255, 0.745, 0.745, 0.05))


def g_boxfill(m): m.add(rrect(0.16, 0.16, 0.84, 0.84, 0.12))


def g_danger(m):
    m.add(poly([(0.5, 0.12), (0.89, 0.83), (0.11, 0.83)]))
    m.add(polyline([(0.5, 0.12), (0.89, 0.83), (0.11, 0.83), (0.5, 0.12)], 0.06))
    m.sub(capsule((0.5, 0.37), (0.5, 0.59), 0.13))
    m.sub(circle(0.5, 0.71, 0.07))


def g_usenow(m):
    m.add(poly([(0.60, 0.11), (0.25, 0.55), (0.47, 0.55), (0.39, 0.89),
                (0.76, 0.42), (0.54, 0.42), (0.64, 0.11)]))


def g_travel(m):  # wing: travel by flight path / going home
    m.add(capsule((0.25, 0.68), (0.82, 0.22), 0.14))
    m.add(capsule((0.27, 0.70), (0.83, 0.43), 0.12))
    m.add(capsule((0.29, 0.72), (0.76, 0.63), 0.10))
    m.add(circle(0.27, 0.70, 0.10))
    m.sub(capsule((0.40, 0.535), (0.86, 0.30), 0.035))
    m.sub(capsule((0.42, 0.645), (0.84, 0.53), 0.03))


def g_class(m):
    m.add(shield())
    m.sub(shield(0.80, 0.5, 0.47))
    m.add(shield(0.60, 0.5, 0.46))


def g_legacy(m):  # hourglass
    m.add(poly([(0.31, 0.20), (0.69, 0.20), (0.53, 0.5), (0.69, 0.80), (0.31, 0.80), (0.47, 0.5)]))
    m.add(rrect(0.24, 0.13, 0.76, 0.22, 0.03))
    m.add(rrect(0.24, 0.78, 0.76, 0.87, 0.03))
    m.sub(poly([(0.39, 0.27), (0.61, 0.27), (0.5, 0.42)]))


def g_tip(m):  # light bulb
    m.add(circle(0.5, 0.40, 0.23))
    m.add(poly([(0.37, 0.52), (0.63, 0.52), (0.59, 0.67), (0.41, 0.67)]))
    m.add(capsule((0.42, 0.73), (0.58, 0.73), 0.07))
    m.add(capsule((0.45, 0.82), (0.55, 0.82), 0.06))
    m.sub(arc(0.5, 0.40, 0.14, 0.045, 200, 255))


def g_new(m):  # four-point sparkle
    c, R, r = (0.46, 0.54), 0.36, 0.085
    pts = []
    for k in range(8):
        a = math.radians(-90 + 45 * k)
        rad = R if k % 2 == 0 else r
        pts.append((c[0] + rad * math.cos(a), c[1] + rad * math.sin(a)))
    m.add(poly(pts))
    pts = []
    for k in range(8):
        a = math.radians(-90 + 45 * k)
        rad = 0.13 if k % 2 == 0 else 0.035
        pts.append((0.75 + rad * math.cos(a), 0.25 + rad * math.sin(a)))
    m.add(poly(pts))


def g_hidden(m):  # eye with a slash
    m.add(lens(0.5, 0.5, 0.44, 0.27))
    m.sub(circle(0.5, 0.5, 0.125))
    m.add(circle(0.5, 0.5, 0.065))
    m.sub(capsule((0.18, 0.84), (0.82, 0.16), 0.17))
    m.add(capsule((0.22, 0.80), (0.78, 0.20), 0.075))


def g_menu(m):
    for y in (0.30, 0.5, 0.70):
        m.add(capsule((0.24, y), (0.76, y), 0.095))


def g_small(m): m.add(capsule((0.27, 0.66), (0.73, 0.66), 0.10))


def g_lock(m):
    m.add(arc(0.5, 0.40, 0.145, 0.085, 180, 360))
    m.add(capsule((0.355, 0.40), (0.355, 0.50), 0.085))
    m.add(capsule((0.645, 0.40), (0.645, 0.50), 0.085))
    lock_body(m)


def g_unlock(m):
    m.add(arc(0.5, 0.30, 0.145, 0.085, 180, 360))
    m.add(capsule((0.355, 0.30), (0.355, 0.36), 0.085))
    m.add(capsule((0.645, 0.30), (0.645, 0.50), 0.085))
    lock_body(m)


def g_close(m):
    m.add(capsule((0.29, 0.29), (0.71, 0.71), 0.105))
    m.add(capsule((0.71, 0.29), (0.29, 0.71), 0.105))


def g_prev(m): m.add(polyline([(0.60, 0.25), (0.36, 0.5), (0.60, 0.75)], 0.115))
def g_next(m): m.add(polyline([(0.40, 0.25), (0.64, 0.5), (0.40, 0.75)], 0.115))
def g_caret(m): m.add(polyline([(0.42, 0.33), (0.585, 0.5), (0.42, 0.67)], 0.10))


def g_none(m):
    for a in range(0, 360, 45):
        m.add(arc(0.5, 0.5, 0.29, 0.08, a + 8, a + 30))
    m.add(circle(0.5, 0.5, 0.075))


def g_finished(m):  # flag
    m.add(capsule((0.29, 0.15), (0.29, 0.87), 0.075))
    m.add(poly([(0.31, 0.16), (0.81, 0.21), (0.66, 0.35), (0.81, 0.50), (0.31, 0.47)]))


def g_error(m):
    m.add(circle(0.5, 0.5, 0.37))
    m.sub(capsule((0.37, 0.37), (0.63, 0.63), 0.12))
    m.sub(capsule((0.63, 0.37), (0.37, 0.63), 0.12))


def g_expand(m):
    m.add(rrect(0.24, 0.28, 0.76, 0.76, 0.05))
    m.sub(rrect(0.32, 0.41, 0.68, 0.68, 0.01))


# slot, theme key, drawing, short description (MANIFEST.md)
SLOTS = [
    (0, "glyph.step.disc", g_disc, "badge disc (tint per step type, glyph on top)"),
    (1, "glyph.step.ring", g_ring, "badge ring / outline"),
    (2, "glyph.step.accept", g_accept, "accept '!'"),
    (3, "glyph.step.turnin", g_turnin, "turn in '?'"),
    (4, "glyph.step.kill", g_kill, "kill: target"),
    (5, "glyph.step.collect", g_collect, "collect: sack"),
    (6, "glyph.step.goto", g_goto, "goto: map pin"),
    (7, "glyph.step.done", g_done, "done tick (done step, done chip)"),
    (8, "glyph.check.tick", g_tick, "goal checkbox tick (bold, for 10 px)"),
    (9, "glyph.step.level", g_level, "level up: arrow on a bar"),
    (10, "glyph.check.box", g_box, "goal checkbox, empty (rounded)"),
    (11, "glyph.check.fill", g_boxfill, "goal checkbox, filled (rounded)"),
    (16, "glyph.notice.danger", g_danger, "danger: warning triangle"),
    (17, "glyph.notice.usenow", g_usenow, "use item now: bolt"),
    (18, "glyph.notice.travel", g_travel, "hearth / flight: wing"),
    (19, "glyph.notice.class", g_class, "class: shield"),
    (20, "glyph.notice.legacy", g_legacy, "Legacy: hourglass"),
    (21, "glyph.notice.tip", g_tip, "tip: light bulb"),
    (22, "glyph.notice.new", g_new, "new: sparkle"),
    (23, "glyph.notice.hidden", g_hidden, "hidden hints count: eye, slashed"),
    (24, "glyph.btn.menu", g_menu, "menu: three lines"),
    (25, "glyph.btn.small", g_small, "small mode: bar"),
    (26, "glyph.btn.lock", g_lock, "locked"),
    (27, "glyph.btn.unlock", g_unlock, "unlocked"),
    (28, "glyph.btn.close", g_close, "close: X"),
    (29, "glyph.btn.prev", g_prev, "previous step"),
    (30, "glyph.btn.next", g_next, "next step"),
    (31, "glyph.btn.caret", g_caret, "done-chip caret (right; rotate for down)"),
    (32, "glyph.state.none", g_none, "no guide: dashed ring"),
    (33, "glyph.state.finished", g_finished, "route finished: flag"),
    (34, "glyph.state.error", g_error, "error: circle with X"),
    (35, "glyph.btn.expand", g_expand, "expand from small mode: window box"),
]


def uv(slot):
    col, row = slot % 8, slot // 8
    return col / 8, (col + 1) / 8, row / 8, (row + 1) / 8


def build():
    W = 256
    sheet = [(0, 0, 0, 0)] * (W * W)
    for slot, key, fn, _ in SLOTS:
        m = Mask(N)
        fn(m)
        cell = down(compose(m, SS, RIM), N, CELL)
        ox, oy = (slot % 8) * CELL, (slot // 8) * CELL
        for j in range(CELL):
            sheet[(oy + j) * W + ox:(oy + j) * W + ox + CELL] = cell[j * CELL:(j + 1) * CELL]
    return sheet


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    write_tga(os.path.join(MEDIA, "glyphs.tga"), 256, 256, build())
    print("glyphs.tga written (%d slots)" % len(SLOTS))

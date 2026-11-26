# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - rounded window art (one-window look 4e): round.tga.
# Copyright (C) 2026 All-in-One Guide contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU
# General Public License for details: <https://www.gnu.org/licenses/>.
#
# Plain Python 3, deterministic. Run: python -B art-src/build_round.py
# Writes only AllinOneGuide/media/round.tga (256x64), white / grey (tinted in
# game with SetVertexColor):
#   x   0- 31, y  0-31  frame.panel   32x32 rounded rect, r 14, 9-slice corner 14
#   x   0- 31, y 32-63  frame.border  same shape, 1.5 px ring on its edge
#   x  32- 63, y  0-31  round.s       32x32 rounded rect, r 8, 9-slice corner 8
#   x  32- 63, y 32-63  btn.target    crosshair glyph (white + 1 px dark rim)
#   x  64-127           frame.shadow  64x64 soft shadow ring, hollow middle,
#                                     9-slice corner 27 (12 falloff + r 15)
#   x 128-191           frame.stepbutton2  rounded button frame, shown 52x52
#   x 192-255           tiles: 4 x 4 cells of 16x16 (tile.base, tile.open and
#                                     the tile symbols, drawn on top of tile.base)
# Coordinates: art-src/MANIFEST.md.
import math, os
from aog_art import MEDIA, Mask, capsule, circle, compose, down, poly, polyline, ring, rrect, arc, write_tga

W, H = 256, 64


# ------------------------------------------------------------------ helpers
def sd_rrect(x, y, x0, y0, x1, y1, r):
    """Signed distance to a rounded rectangle (negative inside), same units as the input."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def field(w, h, fn, ss=8):
    """Supersampled w x h picture; fn(x, y) in pixel units -> straight (r, g, b, a) floats."""
    out = []
    k = ss * ss
    for j in range(h):
        for i in range(w):
            r = g = b = a = 0.0
            for sj in range(ss):
                y = j + (sj + 0.5) / ss
                for si in range(ss):
                    pr, pg, pb, pa = fn(i + (si + 0.5) / ss, y)
                    r += pr * pa; g += pg * pa; b += pb * pa; a += pa
            if a > 0:
                c = (r / a, g / a, b / a, a / k)
                out.append(tuple(int(round(max(0.0, min(1.0, t)) * 255)) for t in c))
            else:
                out.append((0, 0, 0, 0))
    return out


CLEAR = (0.0, 0.0, 0.0, 0.0)
WHITE = (1.0, 1.0, 1.0, 1.0)


# ------------------------------------------------------------------ 9-slice pieces
def panel(x, y):     # 32x32, radius 14, fills the cell
    return WHITE if sd_rrect(x, y, 0, 0, 32, 32, 14) <= 0 else CLEAR


def border(x, y):    # same shape, 1.5 px ring just inside the edge
    d = sd_rrect(x, y, 0, 0, 32, 32, 14)
    return WHITE if -1.5 <= d <= 0 else CLEAR


def round_s(x, y):   # 32x32, radius 8
    return WHITE if sd_rrect(x, y, 0, 0, 32, 32, 8) <= 0 else CLEAR


SH_F, SH_R = 12, 15  # shadow falloff and radius in texels (corner piece 27 = 8 + 10 units at 1.5 texels / unit)


def shadow(x, y):    # hollow: full strength at the panel edge (1.5 px under it), fades out over SH_F
    d = sd_rrect(x, y, SH_F, SH_F, 64 - SH_F, 64 - SH_F, SH_R)
    if d < -1.5:
        return CLEAR
    if d <= 0:
        return (0.0, 0.0, 0.0, 1.0)
    t = d / SH_F
    if t >= 1:
        return CLEAR
    return (0.0, 0.0, 0.0, (1 - t) ** 2.2)


# ------------------------------------------------------------------ rounded button frame
BU = 64 / 52.0       # texels per screen unit (shown 52x52, 36x36 button centred = units 8..44)
DARK = (0.043, 0.043, 0.047)


def stepbutton2(x, y):
    u, v = x / BU, y / BU
    d_hole = sd_rrect(u, v, 9, 9, 43, 43, 5)      # see-through middle (icon shows 34 px, corners rounded)
    if d_hole < 0:
        return CLEAR
    d_band = sd_rrect(u, v, 6, 6, 46, 46, 8)      # dark band, stays dark when tinted
    if d_band <= 0:
        return DARK + (1.0,)
    d_ring = sd_rrect(u, v, 4.8, 4.8, 47.2, 47.2, 9.2)  # 1.2 unit ring, tinted (grey ring in 4e)
    if d_ring <= 0:
        s = 1.0 - 0.28 * max(0.0, min(1.0, (v - 6) / 40))   # lit top, darker bottom
        return (s, s, s, 1.0)
    t = d_ring / 2.5                              # soft dark outer edge, 2.5 units
    return (0.0, 0.0, 0.0, 0.45 * (1 - t) ** 2) if t < 1 else CLEAR


# ------------------------------------------------------------------ tiles (16x16 cells)
def tile_base(x, y):  # rounded square 1..15, r 3; lit top, 1 px darker edge (multiplies with the tint)
    d = sd_rrect(x, y, 1, 1, 15, 15, 3)
    if d > 0:
        return CLEAR
    s = 1.0 if y < 7 else (1.0 - 0.14 * min(1.0, (y - 7) / 2.0))
    if d > -0.9:
        s *= 0.55
    return (s, s, s, 1.0)


def tile_open(x, y):  # empty tile: 1.2 px ring + dark see-through middle
    d = sd_rrect(x, y, 1, 1, 15, 15, 3)
    if d > 0:
        return CLEAR
    if d > -1.2:
        return WHITE
    return (0.0, 0.0, 0.0, 0.55)


TSS = 8              # supersampling for the tile symbols
TN = 16 * TSS


def s_accept(m):
    m.add(capsule((0.5, 0.25), (0.5, 0.55), 0.16))
    m.add(circle(0.5, 0.74, 0.09))


def s_turnin(m):
    m.add(arc(0.5, 0.37, 0.135, 0.14, 190, 400))
    a = math.radians(400)
    m.add(capsule((0.5 + 0.135 * math.cos(a), 0.37 + 0.135 * math.sin(a)), (0.5, 0.57), 0.14))
    m.add(circle(0.5, 0.75, 0.09))


def s_kill(m):
    m.add(capsule((0.31, 0.31), (0.69, 0.69), 0.14))
    m.add(capsule((0.69, 0.31), (0.31, 0.69), 0.14))


def s_loot(m):       # sack with a tied neck
    m.add(poly([(0.37, 0.42), (0.63, 0.42), (0.77, 0.64), (0.72, 0.79), (0.28, 0.79), (0.23, 0.64)]))
    m.add(poly([(0.42, 0.33), (0.58, 0.33), (0.62, 0.42), (0.38, 0.42)]))
    m.add(poly([(0.33, 0.20), (0.5, 0.29), (0.67, 0.20), (0.62, 0.34), (0.38, 0.34)]))
    m.sub(capsule((0.36, 0.385), (0.64, 0.385), 0.05))


def s_use(m):        # potion flask
    m.add(circle(0.5, 0.61, 0.21))
    m.add(capsule((0.5, 0.25), (0.5, 0.45), 0.15))
    m.add(capsule((0.38, 0.22), (0.62, 0.22), 0.09))


def s_goto(m):       # route arrowhead
    m.add(poly([(0.5, 0.18), (0.77, 0.80), (0.5, 0.66), (0.23, 0.80)]))


def s_talk(m):       # speech bubble
    m.add(rrect(0.19, 0.22, 0.81, 0.62, 0.11))
    m.add(poly([(0.30, 0.58), (0.50, 0.58), (0.28, 0.82)]))


def s_train(m):      # double chevron up
    m.add(polyline([(0.27, 0.48), (0.5, 0.27), (0.73, 0.48)], 0.13))
    m.add(polyline([(0.27, 0.73), (0.5, 0.52), (0.73, 0.73)], 0.13))


def s_fly(m):        # bird in flight (gull)
    m.add(polyline([(0.17, 0.42), (0.31, 0.37), (0.5, 0.60), (0.69, 0.37), (0.83, 0.42)], 0.12))


def s_hearth(m):     # house with a door
    m.add(poly([(0.5, 0.18), (0.84, 0.48), (0.16, 0.48)]))
    m.add(rrect(0.27, 0.44, 0.73, 0.81, 0.03))
    m.sub(rrect(0.43, 0.59, 0.57, 0.82, 0.02))


def s_note(m):       # "i"
    m.add(circle(0.5, 0.27, 0.09))
    m.add(capsule((0.5, 0.44), (0.5, 0.76), 0.16))


def s_done(m):       # tick
    m.add(polyline([(0.26, 0.52), (0.43, 0.69), (0.75, 0.32)], 0.15))


def symbol(fn):
    m = Mask(TN)
    fn(m)
    return down([(v, v, v, 1.0) if v > 0 else (0.0, 0.0, 0.0, 0.0) for v in m.v], TN, 16)


# cell, key, what, picture
TILES = [
    (0, "tile.base", "tile background: rounded square, lit top, darker edge (tint = step colour)", lambda: field(16, 16, tile_base)),
    (1, "tile.open", "empty tile: ring + dark see-through middle (open goal)", lambda: field(16, 16, tile_open)),
    (2, "tile.accept", "symbol: !", lambda: symbol(s_accept)),
    (3, "tile.turnin", "symbol: ?", lambda: symbol(s_turnin)),
    (4, "tile.kill", "symbol: X", lambda: symbol(s_kill)),
    (5, "tile.loot", "symbol: sack", lambda: symbol(s_loot)),
    (6, "tile.use", "symbol: flask", lambda: symbol(s_use)),
    (7, "tile.goto", "symbol: route arrowhead", lambda: symbol(s_goto)),
    (8, "tile.talk", "symbol: speech bubble", lambda: symbol(s_talk)),
    (9, "tile.train", "symbol: double chevron up", lambda: symbol(s_train)),
    (10, "tile.fly", "symbol: bird", lambda: symbol(s_fly)),
    (11, "tile.hearth", "symbol: house", lambda: symbol(s_hearth)),
    (12, "tile.note", "symbol: i", lambda: symbol(s_note)),
    (13, "tile.done", "symbol: tick", lambda: symbol(s_done)),
]


# ------------------------------------------------------------------ crosshair (glyph style)
GSS = 4
RIM = (0.02, 0.03, 0.04, 0.88)


def crosshair():
    n = 32 * GSS
    m = Mask(n)
    m.add(ring(0.5, 0.5, 0.215, 0.30))
    for a, b in (((0.5, 0.145), (0.5, 0.36)), ((0.5, 0.64), (0.5, 0.855)),
                 ((0.145, 0.5), (0.36, 0.5)), ((0.64, 0.5), (0.855, 0.5))):
        m.add(capsule(a, b, 0.085))
    m.add(circle(0.5, 0.5, 0.065))
    cell = down(compose(m, GSS, RIM), n, 32)
    bad = [1 for j in range(32) for i in range(32)
           if (min(i, j) < 2 or max(i, j) > 29) and cell[j * 32 + i][3] > 0]
    if bad:
        raise SystemExit("crosshair touches its 2 px padding (%d px)" % len(bad))
    return cell


# ------------------------------------------------------------------ sheet
def build():
    out = [(0, 0, 0, 0)] * (W * H)

    def put(ox, oy, w, h, px):
        for j in range(h):
            out[(oy + j) * W + ox:(oy + j) * W + ox + w] = px[j * w:(j + 1) * w]

    put(0, 0, 32, 32, field(32, 32, panel))
    put(0, 32, 32, 32, field(32, 32, border))
    put(32, 0, 32, 32, field(32, 32, round_s))
    put(32, 32, 32, 32, crosshair())
    put(64, 0, 64, 64, field(64, 64, shadow, ss=4))
    put(128, 0, 64, 64, field(64, 64, stepbutton2, ss=4))
    for cell, _, _, make in TILES:
        put(192 + (cell % 4) * 16, (cell // 4) * 16, 16, 16, make())
    return out


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    write_tga(os.path.join(MEDIA, "round.tga"), W, H, build())
    print("round.tga written (%d tile cells)" % len(TILES))

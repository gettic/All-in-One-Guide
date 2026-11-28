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
#                                     the tile symbols, drawn on top of tile.base;
#                                     tile.getfp / tile.sethearth live in glyphs.tga slot 63)
# Coordinates: art-src/MANIFEST.md.
import math, os
from aog_art import MEDIA, Mask, capsule, circle, compose, corner_mark, down, kill_sword, poly, polyline, ring, rrect, arc, write_tga

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


def u(v):            # 16 px grid -> unit
    return v / 16.0


def s_accept(m):     # "!" on the 16 px grid: bar 3 x 6.5 px, a clear 1.5 px gap, dot 3 x 2.5 px (2026-11-28)
    m.add(rrect(u(6.5), u(2.5), u(9.5), u(9.0), u(0.6)))
    m.add(rrect(u(6.5), u(10.5), u(9.5), u(13.0), u(0.6)))


def s_turnin(m):     # bolder "?": open hook, short stem, square dot (2026-11-28)
    m.add(arc(u(8), u(5.6), u(2.7), u(2.5), 185, 400))
    a = math.radians(400)
    m.add(capsule((u(8 + 2.7 * math.cos(a)), u(5.6 + 2.7 * math.sin(a))), (u(8), u(9.0)), u(2.5)))
    m.add(rrect(u(6.75), u(10.6), u(9.25), u(13.0), u(0.6)))

def s_kill(m):       # one sword, tip top right (was an X until 2026-11-28: it read as "don't do this")
    m.add(kill_sword())


def s_loot(m):       # sack with a tied neck
    m.add(poly([(0.37, 0.42), (0.63, 0.42), (0.77, 0.64), (0.72, 0.79), (0.28, 0.79), (0.23, 0.64)]))
    m.add(poly([(0.42, 0.33), (0.58, 0.33), (0.62, 0.42), (0.38, 0.42)]))
    m.add(poly([(0.33, 0.20), (0.5, 0.29), (0.67, 0.20), (0.62, 0.34), (0.38, 0.34)]))
    m.sub(capsule((0.36, 0.385), (0.64, 0.385), 0.05))


def s_use(m):        # potion flask
    m.add(circle(0.5, 0.61, 0.21))
    m.add(capsule((0.5, 0.25), (0.5, 0.45), 0.15))
    m.add(capsule((0.38, 0.22), (0.62, 0.22), 0.09))


def s_goto(m):       # map pin with a hole (was an arrowhead until 2026-11-28: it read as "A")
    m.add(circle(0.5, 0.40, 0.27))
    m.add(poly([(0.27, 0.52), (0.73, 0.52), (0.5, 0.88)]))
    m.sub(circle(0.5, 0.40, 0.10))


def s_talk(m):       # speech bubble
    m.add(rrect(0.19, 0.22, 0.81, 0.62, 0.11))
    m.add(poly([(0.30, 0.58), (0.50, 0.58), (0.28, 0.82)]))


def s_train(m):      # double chevron up
    m.add(polyline([(0.27, 0.48), (0.5, 0.27), (0.73, 0.48)], 0.13))
    m.add(polyline([(0.27, 0.73), (0.5, 0.52), (0.73, 0.73)], 0.13))


def qcurve(p0, c, p1, n=10):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]) for t in (k / n for k in range(n + 1))]


def s_fly(m):        # bird, side view, flying up-right: big swept wing, head, beak, tail (2026-11-28; was a thin gull)
    m.add(capsule((0.30, 0.68), (0.66, 0.52), 0.21))
    m.add(circle(0.72, 0.47, 0.12))
    m.add(poly([(0.80, 0.41), (0.95, 0.43), (0.82, 0.51)]))
    m.add(poly([(0.34, 0.64), (0.06, 0.70), (0.14, 0.82), (0.36, 0.76)]))
    m.add(poly(qcurve((0.40, 0.62), (0.22, 0.30), (0.14, 0.12)) + qcurve((0.14, 0.12), (0.50, 0.22), (0.62, 0.55))[1:]))

def s_hearth(m):     # house with a door
    m.add(poly([(0.5, 0.18), (0.84, 0.48), (0.16, 0.48)]))
    m.add(rrect(0.27, 0.44, 0.73, 0.81, 0.03))
    m.sub(rrect(0.43, 0.59, 0.57, 0.82, 0.02))


def s_note(m):       # "i"
    m.add(circle(0.5, 0.27, 0.09))
    m.add(capsule((0.5, 0.44), (0.5, 0.76), 0.16))


def s_done(m):       # tick
    m.add(polyline([(0.26, 0.52), (0.43, 0.69), (0.75, 0.32)], 0.15))


def s_level(m):      # arrow up on a bar (reach a level)
    m.add(poly([(u(8), u(2.6)), (u(12.4), u(7.2)), (u(3.6), u(7.2))]))
    m.add(rrect(u(6.6), u(6.8), u(9.4), u(10.2), u(0.3)))
    m.add(rrect(u(3.4), u(11.2), u(12.6), u(13.2), u(0.6)))


def s_grind(m):      # bold round loop arrow (2 px) round a small sword: "keep killing" (2026-11-28; the
    # old corner loop on the diagonal kill sword read as kill at 12 px, so the outline is round now)
    cx, cy, r, w = u(8), u(8.3), u(4.6), u(2.0)
    a0, a1 = 10.0, 262.0                       # y down: the gap is at the top right, the head ends the loop there
    m.add(arc(cx, cy, r, w, a0, a1))
    t = math.radians(a1)
    rad = (math.cos(t), math.sin(t))           # outward
    tan = (-math.sin(t), math.cos(t))          # along the loop (growing angle)
    bx, by = cx + r * rad[0], cy + r * rad[1]
    hw, hl = u(2.3), u(2.7)
    m.add(poly([(bx + rad[0] * u(1.8), by + rad[1] * u(1.8)), (bx - rad[0] * hw, by - rad[1] * hw),   # (outer side short: stays off the tile edge)
                (bx + tan[0] * hl, by + tan[1] * hl)]))
    # small sword in the middle, tip top right like the kill sword (so it never reads as a power button)
    m.add(kill_sword(tip=(u(9.8), u(6.4)), blade=u(3.6), blade_w=u(1.8), guard_half=u(1.5), guard_w=u(1.2),
                     grip=u(1.0), grip_w=u(1.1), pommel=u(0.6)))


def s_getfp(m):      # bird + "+" (get the flight path)
    corner_mark(m, s_fly, "+")


def s_sethearth(m):  # house + "+" (set your hearth here)
    corner_mark(m, s_hearth, "+")

def symbol(fn):
    m = Mask(TN)
    fn(m)
    return down([(v, v, v, 1.0) if v > 0 else (0.0, 0.0, 0.0, 0.0) for v in m.v], TN, 16)


# cell, key, what, picture
TILES = [
    (0, "tile.base", "tile background: rounded square, lit top, darker edge (tint = step colour)", lambda: field(16, 16, tile_base)),
    (1, "tile.open", "empty tile: ring + dark see-through middle (open goal)", lambda: field(16, 16, tile_open)),
    (2, "tile.accept", "symbol: ! (pixel-aligned)", lambda: symbol(s_accept)),
    (3, "tile.turnin", "symbol: ?", lambda: symbol(s_turnin)),
    (4, "tile.kill", "symbol: sword", lambda: symbol(s_kill)),
    (5, "tile.loot", "symbol: sack", lambda: symbol(s_loot)),
    (6, "tile.use", "symbol: flask", lambda: symbol(s_use)),
    (7, "tile.goto", "symbol: map pin", lambda: symbol(s_goto)),
    (8, "tile.talk", "symbol: speech bubble", lambda: symbol(s_talk)),
    (9, "tile.train", "symbol: double chevron up", lambda: symbol(s_train)),
    (10, "tile.fly", "symbol: bird, side view", lambda: symbol(s_fly)),
    (11, "tile.hearth", "symbol: house", lambda: symbol(s_hearth)),
    (12, "tile.note", "symbol: i", lambda: symbol(s_note)),
    (13, "tile.done", "symbol: tick", lambda: symbol(s_done)),
    (14, "tile.level", "symbol: arrow up on a bar", lambda: symbol(s_level)),
    (15, "tile.grind", "symbol: round loop arrow round a small sword", lambda: symbol(s_grind)),
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

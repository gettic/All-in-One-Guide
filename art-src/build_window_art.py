# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - NOW window + main window art: glyphs2.tga and emblems.tga.
# Copyright (C) 2026 All-in-One Guide contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU
# General Public License for details: <https://www.gnu.org/licenses/>.
#
# Plain Python 3, deterministic. Run: python -B art-src/build_window_art.py
# Writes only AllinOneGuide/media/glyphs2.tga and AllinOneGuide/media/emblems.tga:
#   glyphs2.tga  256x32   32x32 cells in one row: 0 grip, 1 attach, 2 detach,
#                         3 search, 4 resize, 5 talk bubble, 6 note 'i'. White + 1 px dark rim
#                         (tinted in game), same style as glyphs.tga.
#                         7: the title-bar logo, full colour, NOT tinted: the
#                         "Waypoint" logo of build_logo.py rendered at 28x28
#                         inside the cell (2 px clear padding), for the 16 px
#                         title-bar logo (logo_64 shrunk 4:1 looked jagged).
#   emblems.tga  256x64   4 shields 64x64, full colour: alliance, horde,
#                         neutral, soon.
# Coordinates: art-src/MANIFEST.md.
import math, os
from aog_art import MEDIA, Mask, capsule, circle, compose, dist2, down, poly, ring, rrect, write_tga
import build_glyphs as BG
import build_logo as BL

SS, CELL = BG.SS, BG.CELL
N = CELL * SS

# ------------------------------------------------------------------ shape helpers
def stadium_ring(c, u, a, R, r):
    """Chain link: stadium outline centred at c along unit vector u, half length a."""
    p = (c[0] - u[0] * a, c[1] - u[1] * a)
    q = (c[0] + u[0] * a, c[1] + u[1] * a)
    outer = capsule(p, q, 2 * R)
    inner = capsule(p, q, 2 * r)
    (bb, fo), (_, fi) = outer, inner
    return bb, lambda x, y: fo(x, y) and not fi(x, y)


def clip(shape, cx, cy, rad):
    """Shape limited to a circle (used for the chain's over / under crossings)."""
    bb, f = shape
    return bb, lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad and f(x, y)


# ------------------------------------------------------------------ new glyphs (white + 1 px dark rim)
def g_grip(m):  # drag handle: 2 x 3 dots
    for x in (0.39, 0.61):
        for y in (0.27, 0.5, 0.73):
            m.add(circle(x, y, 0.08))


def g_resize(m):  # resize corner: 6 dots in a triangle (bottom-right)
    for x, y in ((0.74, 0.30), (0.74, 0.52), (0.52, 0.52), (0.74, 0.74), (0.52, 0.74), (0.30, 0.74)):
        m.add(circle(x, y, 0.072))


U = (1 / math.sqrt(2), -1 / math.sqrt(2))   # diagonal, bottom-left to top-right
LA, LR, LRI = 0.10, 0.155, 0.083            # link half length, outer / inner radius


def link(off, a=LA):
    c = (0.5 + U[0] * off, 0.5 + U[1] * off)
    return stadium_ring(c, U, a, LR, LRI), c


def g_attach(m):  # two linked chain links (woven: over at one crossing, under at the other)
    (l1, c1), (l2, c2) = link(-0.165), link(0.165)
    m.add(l1)
    g = stadium_ring(c2, U, LA, LR + 0.045, LRI - 0.045)
    m.sub(g)
    m.add(l2)
    # crossing on the upper-left side: link 1 goes over link 2 there
    nx, ny = -U[1], U[0]                       # normal to the chain (points down-right)
    kx, ky = 0.5 - nx * 0.12, 0.5 - ny * 0.12
    m.sub(clip(stadium_ring(c1, U, LA, LR + 0.045, LRI - 0.045), kx, ky, 0.12))
    m.add(clip(l1, kx, ky, 0.12))


def g_detach(m):  # two smaller links pulled apart, a clear gap, two break marks across the gap
    for off in (-0.245, 0.245):
        c = (0.5 + U[0] * off, 0.5 + U[1] * off)
        m.add(stadium_ring(c, U, 0.045, 0.14, 0.07))
    nx, ny = -U[1], U[0]
    for s in (-1, 1):
        m.add(capsule((0.5 + nx * s * 0.10, 0.5 + ny * s * 0.10), (0.5 + nx * s * 0.19, 0.5 + ny * s * 0.19), 0.065))


def g_search(m):  # magnifier
    m.add(ring(0.43, 0.43, 0.17, 0.255))
    m.add(capsule((0.62, 0.62), (0.79, 0.79), 0.135))


def g_talk(m):  # speech bubble with three dots cut out (3D view: only the last fallback)
    m.add(rrect(0.15, 0.19, 0.85, 0.65, 0.15))
    m.add(poly([(0.28, 0.60), (0.50, 0.60), (0.24, 0.85)]))
    for x in (0.34, 0.5, 0.66):
        m.sub(circle(x, 0.42, 0.055))


def g_info(m):  # "i" (3D view: only the last fallback)
    m.add(circle(0.5, 0.26, 0.085))
    m.add(capsule((0.5, 0.43), (0.5, 0.76), 0.15))

def render_cell(fn):
    m = Mask(N)
    fn(m)
    cell = down(compose(m, SS, BG.RIM), N, CELL)
    bad = [1 for j in range(CELL) for i in range(CELL)
           if (min(i, j) < 2 or max(i, j) > CELL - 3) and cell[j * CELL + i][3] > 0]
    if bad:
        raise SystemExit("%s touches its 2 px padding (%d px)" % (fn.__name__, len(bad)))
    return cell


G2 = [  # cell, key, drawing, what (7 = title-bar logo, drawn separately)
    (0, "glyph.btn.grip", g_grip, "drag handle (NOW strip, left)"),
    (1, "glyph.btn.attach", g_attach, "attach: whole chain"),
    (2, "glyph.btn.detach", g_detach, "detach: broken chain"),
    (3, "glyph.btn.search", g_search, "search box magnifier"),
    (4, "glyph.btn.resize", g_resize, "resize corner (bottom-right), extra / optional"),
    (5, "glyph.step.talk", g_talk, "talk: speech bubble (3D view last fallback)"),
    (6, "glyph.step.info", g_info, "note: 'i' (3D view last fallback, same symbol as tile.note)"),
]


# ------------------------------------------------------------------ emblems (full colour, 64x64 each)
E = 64
ES = 4
EN = E * ES


def hexc(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def shade(c, k):  # k > 0 lighter, k < 0 darker
    return mix(c, (1, 1, 1), k) if k > 0 else mix(c, (0, 0, 0), -k)


def shield_pts():
    """Our own shield: arched-in top edge with raised corners, straight sides, curved point."""
    pts = []
    for k in range(9):                          # top edge, left to right, dips in the middle
        t = k / 8
        x = 0.15 + 0.70 * t
        y = 0.085 + 0.045 * math.sin(math.pi * t)
        pts.append((x, y))
    pts.append((0.85, 0.50))
    for k in range(1, 11):                      # right side curve to the point
        t = k / 10
        x = (1 - t) ** 2 * 0.85 + 2 * (1 - t) * t * 0.84 + t * t * 0.5
        y = (1 - t) ** 2 * 0.50 + 2 * (1 - t) * t * 0.80 + t * t * 0.935
        pts.append((x, y))
    right = pts[9:-1]
    pts += [(1 - x, y) for x, y in reversed(right)]
    return pts


def star4(cx, cy, R, r):
    pts = []
    for k in range(8):
        a = math.radians(-90 + 45 * k)
        rad = R if k % 2 == 0 else r
        pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    return poly(pts)


def rot(pts, cx, cy, deg):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def mark_alliance(m):
    m.add(star4(0.5, 0.47, 0.25, 0.075))


def mark_horde(m):
    m.add(poly([(0.27, 0.36), (0.5, 0.58), (0.73, 0.36), (0.73, 0.50), (0.5, 0.72), (0.27, 0.50)]))
    m.add(poly([(0.5, 0.20), (0.585, 0.285), (0.5, 0.37), (0.415, 0.285)]))


def mark_neutral(m):  # route arrow, pointing up-right (the addon's own waypoint idea)
    m.add(poly(rot([(0, -0.25), (0.17, 0.17), (0, 0.07), (-0.17, 0.17)], 0.5, 0.49, 45)))


def mark_soon(m):
    m.add(capsule((0.5, 0.32), (0.5, 0.64), 0.12))
    m.add(capsule((0.34, 0.48), (0.66, 0.48), 0.12))


# field lit / shade, rim top / bottom, mark top / bottom
EMBLEMS = [
    ("emblem.alliance", "Alliance: blue field, gold rim, four-point star", mark_alliance,
     "#3C6FB8", "#2B5291", "#EBCF7E", "#A9843A", "#FFF3CF", "#E6C87F"),
    ("emblem.horde", "Horde: red field, gold rim, chevron + diamond", mark_horde,
     "#B83A30", "#8E2A24", "#EBCF7E", "#A9843A", "#FFF3CF", "#E6C87F"),
    ("emblem.neutral", "Both factions / neutral: teal field, silver rim, route arrow", mark_neutral,
     "#25A88F", "#1A7F6C", "#E2E8EE", "#8E98A5", "#FFFFFF", "#CFEFE7"),
    ("emblem.soon", "Coming soon: grey field, grey rim, plus", mark_soon,
     "#46505D", "#363E49", "#8A939F", "#59616C", "#B7BFC9", "#8D97A4"),
]


def render_emblem(spec):
    _, _, markfn, f_lit, f_sh, r_top, r_bot, m_top, m_bot = spec
    f_lit, f_sh, r_top, r_bot, m_top, m_bot = map(hexc, (f_lit, f_sh, r_top, r_bot, m_top, m_bot))
    sm = Mask(EN).add(poly(shield_pts()))
    out_m = Mask(EN)
    out_m.v = [0.0 if v > 0 else 1.0 for v in sm.v]
    d_in = dist2(out_m, 8 * ES)                 # distance to the outside, inside the shield
    d_out = dist2(sm, 3 * ES)                   # distance to the shield, outside it
    mk = Mask(EN)
    markfn(mk)
    d_mk = dist2(mk, int(1.5 * ES))
    big = 10 ** 9
    px = []
    for idx in range(EN * EN):
        j, i = divmod(idx, EN)
        x, y = (i + 0.5) / EN, (j + 0.5) / EN
        if sm.v[idx] <= 0:                      # outside: soft shadow
            d = d_out[idx]
            if d >= big:
                px.append((0, 0, 0, 0)); continue
            t = math.sqrt(d) / ES / 2.5
            a = 0.5 * (1 - t) ** 2 if t < 1 else 0.0
            px.append((0, 0, 0, a)); continue
        d = math.sqrt(d_in[idx]) / ES if d_in[idx] < big else 99.0
        lit = x < 0.5
        if d < 1.1:                             # dark outline
            c = (0.03, 0.035, 0.05)
        elif d < 4.6:                           # metal rim with a bevel
            c = mix(r_top, r_bot, min(1.0, max(0.0, (y - 0.08) / 0.85)))
            if d < 2.1:
                c = shade(c, 0.30 if y < 0.5 else 0.12)
            elif d > 3.7:
                c = shade(c, -0.28)
            if not lit:
                c = shade(c, -0.10)
        elif d < 5.5:                           # dark line between rim and field
            c = (0.04, 0.05, 0.07)
        else:                                   # the field: lit left half, shaded right half
            c = f_lit if lit else f_sh
            if abs(x - 0.5) < 0.5 / E:          # 1 px soft seam
                c = mix(f_lit, f_sh, 0.5)
            c = shade(c, 0.10 * max(0.0, 1 - (y - 0.12) / 0.3)) if y < 0.42 else shade(c, -0.18 * (y - 0.42) / 0.5)
            if d < 6.6:                         # inset shadow along the rim
                c = shade(c, -0.25)
            if mk.v[idx] > 0:                   # the mark
                c = mix(m_top, m_bot, min(1.0, max(0.0, (y - 0.2) / 0.55)))
                if not lit:
                    c = shade(c, -0.12)
            elif d_mk[idx] < big:               # mark's dark rim
                t = math.sqrt(d_mk[idx]) / ES
                k = 0.75 if t <= 1.0 else 0.75 * max(0.0, 1.5 - t) / 0.5
                c = mix(c, (0.02, 0.025, 0.035), k)
        px.append((c[0], c[1], c[2], 1.0))
    # premultiply for down()
    pm = [(r * a, g * a, b * a, a) for r, g, b, a in px]
    return down(pm, EN, E)


def sheet(w, h, tiles):
    out = [(0, 0, 0, 0)] * (w * h)
    for ox, oy, size, px in tiles:
        for j in range(size):
            out[(oy + j) * w + ox:(oy + j) * w + ox + size] = px[j * size:(j + 1) * size]
    return out


# ------------------------------------------------------------------ title-bar logo (glyphs2 cell 7)
LOGO_CELL, LOGO_PAD = 7, 2
LOGO_IN = CELL - 2 * LOGO_PAD     # 28: shown at 16 UI units (16-30 screen px), never shrunk more than 2:1


def bleed(px, w):
    """Give fully transparent pixels the colour of their nearest visible neighbours (alpha stays 0),
    so bilinear filtering never pulls black into the anti-aliased edge (straight alpha)."""
    out = list(px)
    h = len(px) // w
    for _ in range(3):
        nxt = list(out)
        for j in range(h):
            for i in range(w):
                p = out[j * w + i]
                if p[3] or p[:3] != (0, 0, 0):
                    continue
                acc = [0, 0, 0, 0]
                for dj, di in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
                    jj, ii = j + dj, i + di
                    if 0 <= jj < h and 0 <= ii < w:
                        q = out[jj * w + ii]
                        if q[3] or q[:3] != (0, 0, 0):
                            wt = q[3] + 1
                            acc[0] += q[0] * wt; acc[1] += q[1] * wt; acc[2] += q[2] * wt; acc[3] += wt
                if acc[3]:
                    nxt[j * w + i] = (acc[0] // acc[3], acc[1] // acc[3], acc[2] // acc[3], 0)
        out = nxt
    return out


def render_logo_cell():
    BL.N = LOGO_IN * 16               # 448: an even 16 x 16 box per output pixel
    inner = BL.logo_waypoint().down(LOGO_IN)   # same drawing as logo_64.tga (unit coordinates)
    cell = [(0, 0, 0, 0)] * (CELL * CELL)
    for j in range(LOGO_IN):
        for i in range(LOGO_IN):
            cell[(j + LOGO_PAD) * CELL + i + LOGO_PAD] = inner[j * LOGO_IN + i]
    return bleed(cell, CELL)


def build_glyphs2():
    tiles = [(slot * CELL, 0, CELL, render_cell(fn)) for slot, _, fn, _ in G2]
    tiles.append((LOGO_CELL * CELL, 0, CELL, render_logo_cell()))
    return sheet(256, 32, tiles)


def build_emblems():
    return sheet(256, 64, [(k * E, 0, E, render_emblem(spec)) for k, spec in enumerate(EMBLEMS)])


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    write_tga(os.path.join(MEDIA, "glyphs2.tga"), 256, 32, build_glyphs2())
    write_tga(os.path.join(MEDIA, "emblems.tga"), 256, 64, build_emblems())
    print("glyphs2.tga (%d cells) and emblems.tga (%d emblems) written" % (len(G2), len(EMBLEMS)))
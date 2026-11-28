# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - glyph sheet builder (default "Dark" theme, v0.1 + v0.2 slots).
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
# slots, slot i at column i % 8, row i // 8 (row 0 = top). Slot 63 holds four
# 16x16 tile symbols instead (tile.getfp, tile.sethearth). Every glyph is
# white (tinted in game with SetVertexColor) with a baked 1 px dark rim;
# content stays inside the slot's middle 28x28 (2 px clear padding).
# Slot list and texture coordinates: art-src/MANIFEST.md.
import math, os
from aog_art import (MEDIA, Mask, arc, capsule, circle, compose, down, kill_sword, lens, poly,
                     polyline, ring, rrect, write_tga)

SS = 4                 # supersampling per output pixel
CELL = 32              # slot size in the file
N = CELL * SS          # supersampled slot size
RIM = (0.02, 0.03, 0.04, 0.88)   # baked dark rim colour / alpha


def disc_shade(x, y):  # soft top-to-bottom light on the badge disc
    return 1.0 - 0.14 * max(0.0, min(1.0, (y - 0.1) / 0.8))


def xf(shape, sc, ox, oy):
    """Scale a shape (or list of shapes) by sc about (0.5, 0.5), centred at (ox, oy)."""
    if isinstance(shape, list):
        return [xf(s, sc, ox, oy) for s in shape]
    (x0, y0, x1, y1), inside = shape
    return (ox + (x0 - 0.5) * sc, oy + (y0 - 0.5) * sc, ox + (x1 - 0.5) * sc, oy + (y1 - 0.5) * sc), \
        lambda x, y: inside(0.5 + (x - ox) / sc, 0.5 + (y - oy) / sc)


class XMask:
    """Draw a glyph function smaller / moved: forwards add / sub to a Mask through xf."""

    def __init__(s, m, sc, ox, oy):
        s.m, s.sc, s.ox, s.oy = m, sc, ox, oy

    def add(s, shape, shade=1.0):
        s.m.add(xf(shape, s.sc, s.ox, s.oy), 1.0 if callable(shade) else shade)
        return s

    def sub(s, shape):
        s.m.sub(xf(shape, s.sc, s.ox, s.oy))
        return s


def corner(m, mark):
    """Small '+' or 'x' mark in the top-right corner, cut free from the main shape."""
    cx, cy, h, w = 0.735, 0.265, 0.085, 0.085
    m.sub(circle(cx, cy, 0.175))
    if mark == "+":
        m.add(capsule((cx, cy - h), (cx, cy + h), w))
        m.add(capsule((cx - h, cy), (cx + h, cy), w))
    else:
        d = h * 0.8
        m.add(capsule((cx - d, cy - d), (cx + d, cy + d), w))
        m.add(capsule((cx + d, cy - d), (cx - d, cy + d), w))


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


# ------------------------------------------------------------------ glyphs (v0.1)
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


def g_kill(m):  # one sword, the same shape as tile.kill (was a target until 2026-11-28)
    m.add(kill_sword())


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


def g_danger(m):  # scaled 0.94 so the outline and rim stay inside the 2 px padding
    danger_body(XMask(m, 0.94, 0.5, 0.51))


def danger_body(m):
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


# ------------------------------------------------------------------ glyphs (v0.2)
def g_learn(m):  # open book
    left = [(0.15, 0.31), (0.25, 0.27), (0.38, 0.28), (0.475, 0.34),
            (0.475, 0.78), (0.38, 0.72), (0.25, 0.71), (0.15, 0.75)]
    m.add(poly(left))
    m.add(poly([(1 - x, y) for x, y in left]))


def g_train(m):  # double chevron up (rank up at a trainer)
    m.add(polyline([(0.24, 0.49), (0.5, 0.25), (0.76, 0.49)], 0.13))
    m.add(polyline([(0.24, 0.75), (0.5, 0.51), (0.76, 0.75)], 0.13))


def g_note(m):  # note page with a folded corner and text lines
    m.add(poly([(0.24, 0.15), (0.58, 0.15), (0.76, 0.33), (0.76, 0.85), (0.24, 0.85)]))
    m.sub(poly([(0.555, 0.20), (0.555, 0.355), (0.71, 0.355)]))
    for y, x1 in ((0.50, 0.65), (0.62, 0.65), (0.74, 0.55)):
        m.sub(capsule((0.35, y), (x1, y), 0.065))


def g_useitem(m):  # potion flask
    m.add(rrect(0.36, 0.13, 0.64, 0.21, 0.03))
    m.add(rrect(0.425, 0.18, 0.575, 0.40, 0.02))
    m.add(circle(0.5, 0.61, 0.25))
    m.sub(arc(0.5, 0.61, 0.165, 0.05, 195, 250))


def sword(tip, end, grow=0.0):
    tx, ty = tip; ex, ey = end
    L = math.hypot(ex - tx, ey - ty)
    ux, uy = (ex - tx) / L, (ey - ty) / L
    nx, ny = -uy, ux
    gx, gy = tx + ux * L * 0.66, ty + uy * L * 0.66
    hw = 0.05 + grow
    blade = poly([(tx - ux * grow, ty - uy * grow),
                  (tx + ux * 0.09 + nx * hw, ty + uy * 0.09 + ny * hw),
                  (gx + nx * hw, gy + ny * hw), (gx - nx * hw, gy - ny * hw),
                  (tx + ux * 0.09 - nx * hw, ty + uy * 0.09 - ny * hw)])
    guard = capsule((gx + nx * 0.12, gy + ny * 0.12), (gx - nx * 0.12, gy - ny * 0.12), 0.075 + 2 * grow)
    grip = capsule((gx, gy), (ex, ey), 0.07 + 2 * grow)
    return [blade, guard, grip, circle(ex, ey, 0.05 + grow)]


def g_grind(m):  # crossed swords (last-resort grind)
    a, b = ((0.19, 0.19), (0.79, 0.79)), ((0.81, 0.19), (0.21, 0.79))
    m.add(sword(*a))
    m.sub(sword(*b, grow=0.03))
    m.add(sword(*b))


def qcurve(p0, c, p1, steps=8):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1])
            for t in (k / steps for k in range(steps + 1))]


def bird(m):  # bird in flight, side view, flying right; wing raised
    body = qcurve((0.89, 0.47), (0.80, 0.33), (0.64, 0.45)) + \
        qcurve((0.64, 0.45), (0.42, 0.56), (0.12, 0.46))[1:] + \
        [(0.20, 0.58), (0.13, 0.70)] + \
        qcurve((0.13, 0.70), (0.52, 0.76), (0.89, 0.47))[1:]
    m.add(poly(body))
    wing = qcurve((0.40, 0.56), (0.36, 0.30), (0.22, 0.13)) + \
        qcurve((0.22, 0.13), (0.56, 0.24), (0.66, 0.52))[1:]
    m.sub(poly([(x + 0.0, y - 0.035) for x, y in wing]))
    m.add(poly(wing))


def house(m):
    m.add(poly([(0.5, 0.16), (0.86, 0.49), (0.14, 0.49)]))
    m.add(rrect(0.64, 0.20, 0.74, 0.40, 0.02))
    m.add(rrect(0.25, 0.44, 0.75, 0.82, 0.03))
    m.sub(rrect(0.43, 0.59, 0.57, 0.90, 0.05))


def g_fly(m): bird(m)
def g_hearth(m): house(m)


def g_getfp(m):  # bird + new
    bird(XMask(m, 0.80, 0.42, 0.58))
    corner(m, "+")


def g_sethearth(m):  # house + new (bind here)
    house(XMask(m, 0.80, 0.43, 0.57))
    corner(m, "+")


def g_n_hearth(m):  # hearthstone: rounded stone with a carved house
    m.add(rrect(0.20, 0.13, 0.80, 0.87, 0.25))
    house_cut = XMask(m, 0.48, 0.5, 0.51)
    house_cut.sub(poly([(0.5, 0.16), (0.86, 0.49), (0.14, 0.49)]))
    house_cut.sub(rrect(0.25, 0.44, 0.75, 0.82, 0.03))
    house_cut.add(rrect(0.42, 0.59, 0.58, 0.82, 0.05))


def g_n_flight(m):  # route dots up to a bird
    for x, y, r in ((0.20, 0.80, 0.055), (0.31, 0.69, 0.06), (0.43, 0.60, 0.065)):
        m.add(circle(x, y, r))
    bird(XMask(m, 0.62, 0.62, 0.36))


def g_n_useitem(m):  # item slot with a bolt: press the item
    m.add(rrect(0.14, 0.14, 0.86, 0.86, 0.13))
    m.sub(rrect(0.225, 0.225, 0.775, 0.775, 0.07))
    g_usenow(XMask(m, 0.56, 0.5, 0.5))


def g_keybind(m):  # key cap
    m.add(rrect(0.15, 0.15, 0.85, 0.85, 0.12))
    m.sub(rrect(0.225, 0.215, 0.775, 0.685, 0.08))
    m.add(rrect(0.265, 0.25, 0.735, 0.645, 0.055))


def g_wait(m):  # small hourglass inside a circular arrow (waits for combat to end)
    r, w, a0, a1 = 0.355, 0.075, -60, 240
    m.add(arc(0.5, 0.5, r, w, a0, a1))
    a = math.radians(a1)
    ex, ey = 0.5 + r * math.cos(a), 0.5 + r * math.sin(a)
    tx, ty = -math.sin(a), math.cos(a)      # direction of travel at the end
    nx, ny = math.cos(a), math.sin(a)
    m.add(poly([(ex + tx * 0.12, ey + ty * 0.12), (ex + nx * 0.095, ey + ny * 0.095),
                (ex - nx * 0.095, ey - ny * 0.095)]))
    g_legacy(XMask(m, 0.50, 0.5, 0.52))


def g_snooze(m):  # crescent moon + z
    m.add(circle(0.43, 0.56, 0.30))
    m.sub(circle(0.60, 0.43, 0.25))
    m.add(polyline([(0.61, 0.16), (0.82, 0.16), (0.61, 0.38), (0.82, 0.38)], 0.075))


def g_corpse(m):  # gravestone
    m.add(circle(0.5, 0.38, 0.23))
    m.add(rrect(0.27, 0.38, 0.73, 0.80, 0.0))
    m.add(rrect(0.17, 0.76, 0.83, 0.87, 0.03))
    m.sub(capsule((0.5, 0.27), (0.5, 0.60), 0.075))
    m.sub(capsule((0.39, 0.38), (0.61, 0.38), 0.075))


def g_pin(m):  # map pin body, tip at (0.5, 0.88)
    m.add(circle(0.5, 0.38, 0.25))
    m.add(poly([(0.284, 0.505), (0.716, 0.505), (0.5, 0.88)]))


def g_pinface(m): m.add(circle(0.5, 0.38, 0.165))  # number plate on the pin


def g_pinmini(m):  # minimap dot
    m.add(circle(0.5, 0.5, 0.19))
    m.add(ring(0.5, 0.5, 0.28, 0.37))


def g_pinring(m):  # target reticle ring (current target)
    for a in (45, 135, 225, 315):
        m.add(arc(0.5, 0.5, 0.36, 0.075, a - 30, a + 30))


def g_hub_report(m):  # speech bubble with "!"
    m.add(rrect(0.13, 0.17, 0.87, 0.67, 0.13))
    m.add(poly([(0.27, 0.60), (0.45, 0.60), (0.24, 0.85)]))
    m.sub(capsule((0.5, 0.27), (0.5, 0.45), 0.095))
    m.sub(circle(0.5, 0.56, 0.05))


def g_hub_about(m):  # "i" in a circle
    m.add(circle(0.5, 0.5, 0.37))
    m.sub(circle(0.5, 0.31, 0.06))
    m.sub(capsule((0.5, 0.45), (0.5, 0.69), 0.11))


def g_hub_news(m):  # megaphone
    m.add(poly([(0.16, 0.40), (0.32, 0.40), (0.60, 0.20), (0.60, 0.76), (0.32, 0.58), (0.16, 0.58)]))
    m.add(capsule((0.27, 0.60), (0.33, 0.79), 0.09))
    m.add(arc(0.62, 0.48, 0.12, 0.055, -50, 50))
    m.add(arc(0.62, 0.48, 0.225, 0.055, -42, 42))


def g_hub_settings(m):  # gear
    c = 0.5
    m.add(circle(c, c, 0.28))
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        ux, uy = math.cos(a), math.sin(a)
        nx, ny = -uy, ux
        r0, r1, hw = 0.22, 0.385, 0.068
        m.add(poly([(c + ux * r0 + nx * hw, c + uy * r0 + ny * hw), (c + ux * r1 + nx * hw * 0.8, c + uy * r1 + ny * hw * 0.8),
                    (c + ux * r1 - nx * hw * 0.8, c + uy * r1 - ny * hw * 0.8), (c + ux * r0 - nx * hw, c + uy * r0 - ny * hw)]))
    m.sub(circle(c, c, 0.11))


def g_r_coords(m):  # map pin + x (wrong coordinates)
    pin = XMask(m, 0.85, 0.42, 0.55)
    pin.add(circle(0.5, 0.41, 0.20))
    pin.add(poly([(0.33, 0.50), (0.67, 0.50), (0.5, 0.84)]))
    pin.sub(circle(0.5, 0.41, 0.08))
    corner(m, "x")


def g_r_order(m):  # swap arrows (wrong order)
    m.add(capsule((0.34, 0.24), (0.34, 0.82), 0.10))
    m.add(polyline([(0.20, 0.38), (0.34, 0.22), (0.48, 0.38)], 0.10))
    m.add(capsule((0.66, 0.18), (0.66, 0.76), 0.10))
    m.add(polyline([(0.52, 0.62), (0.66, 0.78), (0.80, 0.62)], 0.10))


def g_r_missing(m):  # "!" crossed out (quest missing / not available)
    m.add(capsule((0.5, 0.24), (0.5, 0.56), 0.13))
    m.add(circle(0.5, 0.74, 0.075))
    m.sub(capsule((0.16, 0.80), (0.84, 0.20), 0.17))
    m.add(capsule((0.20, 0.76), (0.80, 0.24), 0.075))


def g_r_notick(m):  # goal box with an x (step won't tick)
    g_box(m)
    m.add(capsule((0.37, 0.37), (0.63, 0.63), 0.085))
    m.add(capsule((0.63, 0.37), (0.37, 0.63), 0.085))


def g_r_text(m):  # "T" with a wavy underline (text wrong)
    m.add(capsule((0.27, 0.22), (0.73, 0.22), 0.11))
    m.add(capsule((0.5, 0.22), (0.5, 0.62), 0.11))
    m.add(polyline([(0.18, 0.80), (0.29, 0.72), (0.40, 0.80), (0.5, 0.72),
                    (0.60, 0.80), (0.71, 0.72), (0.82, 0.80)], 0.07))


def g_r_other(m):  # three dots
    for x in (0.25, 0.5, 0.75):
        m.add(circle(x, 0.5, 0.085))


def g_copy(m):  # two sheets
    m.add(rrect(0.32, 0.14, 0.82, 0.66, 0.07))
    m.sub(rrect(0.40, 0.22, 0.74, 0.58, 0.03))
    m.sub(rrect(0.13, 0.25, 0.75, 0.93, 0.10))
    m.add(rrect(0.19, 0.31, 0.69, 0.86, 0.06))


# slot, theme key, drawing, short description (MANIFEST.md)
SLOTS = [
    (0, "glyph.step.disc", g_disc, "badge disc (tint per step type, glyph on top)"),
    (1, "glyph.step.ring", g_ring, "badge ring / outline"),
    (2, "glyph.step.accept", g_accept, "accept '!'"),
    (3, "glyph.step.turnin", g_turnin, "turn in '?'"),
    (4, "glyph.step.kill", g_kill, "kill: sword (same as tile.kill)"),
    (5, "glyph.step.collect", g_collect, "collect: sack"),
    (6, "glyph.step.goto", g_goto, "goto: map pin"),
    (7, "glyph.step.done", g_done, "done tick (done step, done chip)"),
    (8, "glyph.check.tick", g_tick, "goal checkbox tick (bold, for 10 px)"),
    (9, "glyph.step.level", g_level, "level up: arrow on a bar"),
    (10, "glyph.check.box", g_box, "goal checkbox, empty (rounded)"),
    (11, "glyph.check.fill", g_boxfill, "goal checkbox, filled (rounded)"),
    (12, "glyph.step.learn", g_learn, "learn: open book"),
    (13, "glyph.step.train", g_train, "train: double chevron up"),
    (14, "glyph.step.note", g_note, "note: page with folded corner"),
    (15, "glyph.step.useitem", g_useitem, "use item: potion flask"),
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
    (36, "glyph.step.grind", g_grind, "grind: crossed swords"),
    (37, "glyph.step.fly", g_fly, "fly: bird in flight"),
    (38, "glyph.step.hearth", g_hearth, "hearth: house"),
    (39, "glyph.step.getfp", g_getfp, "get flight path: bird + plus"),
    (40, "glyph.step.sethearth", g_sethearth, "set hearth: house + plus"),
    (41, "glyph.notice.hearth", g_n_hearth, "hearthstone reminder: stone with a house"),
    (42, "glyph.notice.flight", g_n_flight, "flight path reminder: route dots + bird"),
    (43, "glyph.notice.useitem", g_n_useitem, "use-it-now reminder: item slot with a bolt"),
    (44, "glyph.btn.keybind", g_keybind, "keybind: key cap"),
    (45, "glyph.state.wait", g_wait, "waiting for combat to end: hourglass in a circular arrow"),
    (46, "glyph.notice.snooze", g_snooze, "snooze: moon + z"),
    (47, "glyph.arrow.corpse", g_corpse, "corpse marker: gravestone"),
    (48, "glyph.pin.body", g_pin, "map pin body (tip at the bottom)"),
    (49, "glyph.pin.face", g_pinface, "map pin number plate (same coords, on top)"),
    (50, "glyph.pin.mini", g_pinmini, "minimap pin: dot in a ring"),
    (51, "glyph.pin.ring", g_pinring, "target ring (current target pin)"),
    (52, "glyph.hub.report", g_hub_report, "Hub: Report a mistake (bubble with !)"),
    (53, "glyph.hub.about", g_hub_about, "Hub: About (i)"),
    (54, "glyph.hub.news", g_hub_news, "Hub: What's new (megaphone)"),
    (55, "glyph.hub.settings", g_hub_settings, "Hub / menu: settings (gear)"),
    (56, "glyph.report.coords", g_r_coords, "report type: wrong coords (pin + x)"),
    (57, "glyph.report.order", g_r_order, "report type: wrong order (swap arrows)"),
    (58, "glyph.report.missing", g_r_missing, "report type: quest missing / not available"),
    (59, "glyph.report.notick", g_r_notick, "report type: step won't tick (box + x)"),
    (60, "glyph.report.text", g_r_text, "report type: text wrong (T, wavy line)"),
    (61, "glyph.report.other", g_r_other, "report type: other (three dots)"),
    (62, "glyph.btn.copy", g_copy, "copy (copy box)"),
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
        pad = [(i, j) for j in range(CELL) for i in range(CELL)
               if (min(i, j) < 2 or max(i, j) > CELL - 3) and cell[j * CELL + i][3] > 0]
        if pad:
            raise SystemExit("slot %d (%s) touches its 2 px padding (%d px)" % (slot, key, len(pad)))
        ox, oy = (slot % 8) * CELL, (slot // 8) * CELL
        for j in range(CELL):
            sheet[(oy + j) * W + ox:(oy + j) * W + ox + CELL] = cell[j * CELL:(j + 1) * CELL]
    # slot 63: four 16 x 16 tile-symbol cells (round.tga style, no rim; drawn on tile.base), because round.tga's
    # 4 x 4 tile grid is full: top left tile.getfp, top right tile.sethearth, bottom row spare (empty)
    import build_round as BR
    for q, fn in TILE_QUADS:
        px = BR.symbol(fn(BR))
        ox, oy = 224 + (q % 2) * 16, 224 + (q // 2) * 16
        for j in range(16):
            sheet[(oy + j) * W + ox:(oy + j) * W + ox + 16] = px[j * 16:(j + 1) * 16]
    return sheet


# slot 63 quadrant (0 TL, 1 TR, 2 BL, 3 BR) -> tile symbol (key, coords: art-src/MANIFEST.md)
TILE_QUADS = [
    (0, lambda BR: BR.s_getfp),       # tile.getfp: bird + "+"
    (1, lambda BR: BR.s_sethearth),   # tile.sethearth: house + "+"
]


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    write_tga(os.path.join(MEDIA, "glyphs.tga"), 256, 256, build())
    print("glyphs.tga written (%d slots)" % len(SLOTS))

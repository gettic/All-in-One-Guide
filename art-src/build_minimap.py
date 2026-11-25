# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - minimap button icon (default "Dark" theme, v0.2).
# Copyright (C) 2026 All-in-One Guide contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU
# General Public License for details: <https://www.gnu.org/licenses/>.
#
# Plain Python 3, deterministic. Run: python art-src/build_minimap.py [A|B]
# Writes only AllinOneGuide/media/minimap.tga (32x32): the whole round
# minimap button (dark badge, accent ring, logo mark), simplified from the
# logo so it reads at 31 px. Full colour, not tinted; transparent outside
# the circle. LOGO picks the mark: "A" = Waypoint arrow (default),
# "B" = Guide book. Swapping the logo = change LOGO (or pass B) and rebuild.
import math, os, sys
from aog_art import MEDIA, write_tga
from build_logo import (ACC, BAR0, BAR1, BORDER, BOT, TOP, TXT, Canvas, circle,
                        hexc, mixc, poly, ring, rot)

LOGO = "A"
N = 512


def capsule(p, q, w):
    (ax, ay), (bx, by) = p, q
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy or 1e-12
    h = w / 2

    def inside(x, y):
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / L))
        px, py = ax + dx * t - x, ay + dy * t - y
        return px * px + py * py <= h * h
    return (min(ax, bx) - h, min(ay, by) - h, max(ax, bx) + h, max(ay, by) + h), inside


def badge():
    c = Canvas(N)
    c.layer(circle(.5, .5, .48), BORDER)
    c.layer(circle(.5, .5, .455), lambda x, y: mixc(TOP, BOT, (y - .05) / .9))
    c.layer(circle(.5, .5, .40), lambda x, y: ACC[:3] + (
        0.18 * max(0, 1 - math.hypot(x - .5, y - .5) / .40),))
    c.layer(ring(.5, .5, .385, .435), ACC[:3] + (0.95,))   # thicker than the logo's ring
    return c


def mark_a(c):  # Waypoint: bigger arrow, two route dots
    for (x, y, r, a) in [(.27, .735, .045, .70), (.37, .655, .05, .95)]:
        c.layer(circle(x, y, r), TXT[:3] + (a,))
    ctr = (.56, .45)
    tip, rw, notch, lw = (0, -.31), (.20, .15), (0, .045), (-.20, .15)
    ang = math.radians(45)
    c.layer(poly(rot([tip, rw, notch, lw], ang, (ctr[0] + .02, ctr[1] + .028))), (0, 0, 0, .5))
    c.layer(poly(rot([tip, notch, lw], ang, ctr)), BAR1)
    c.layer(poly(rot([tip, rw, notch], ang, ctr)), BAR0)


def mark_b(c):  # Guide book: open book with a tick
    def page(outer_x, spine_x, ytop0, ytop1, ybot0, ybot1, sag, steps=10):
        top, bot = [], []
        for k in range(steps + 1):
            t = k / steps
            x = outer_x + (spine_x - outer_x) * t
            s = sag * math.sin(math.pi * t)
            top.append((x, ytop0 + (ytop1 - ytop0) * t - s))
            bot.append((x, ybot0 + (ybot1 - ybot0) * t - s))
        return top + bot[::-1]
    for side in (0, 1):
        p = page(.19, .5, .34, .40, .70, .76, .03)
        c.layer(poly([(1 - x, y) if side else (x, y) for x, y in p]), BAR0)
    lp = page(.215, .5, .30, .355, .675, .73, .035)
    c.layer(poly(lp), TXT)
    c.layer(poly([(1 - x, y) for x, y in lp]), hexc("#C3CAD4"))
    c.layer(capsule((.5, .355), (.5, .73), .02), hexc("#7A8390"))
    w = .075
    c.layer(capsule((.585, .52), (.645, .585), w), BAR0)
    c.layer(capsule((.645, .585), (.76, .43), w), BAR0)


def build(logo):
    c = badge()
    (mark_b if logo == "B" else mark_a)(c)
    return c.down(32)


if __name__ == "__main__":
    logo = sys.argv[1].upper() if len(sys.argv) > 1 else LOGO
    os.makedirs(MEDIA, exist_ok=True)
    write_tga(os.path.join(MEDIA, "minimap.tga"), 32, 32, build(logo))
    print("minimap.tga written (logo %s)" % logo)

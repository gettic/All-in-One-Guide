# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - logo builder ("Waypoint" design, default "Dark" theme).
# Copyright (C) 2026 All-in-One Guide contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU
# General Public License for details: <https://www.gnu.org/licenses/>.
#
# Plain Python 3 (math + struct only). Run: python art-src/build_logo.py
# Writes only to AllinOneGuide/media/: logo_64.tga, logo_128.tga
# (32-bit BGRA with alpha, uncompressed, bottom-up rows).
import math, os, struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "AllinOneGuide", "media")
N = 512  # master render size, box-filtered down to the output sizes


def hexc(h, a=1.0):
    return (int(h[1:3], 16) / 255, int(h[3:5], 16) / 255, int(h[5:7], 16) / 255, a)


def mixc(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(4))


class Canvas:
    def __init__(s, n):
        s.n = n
        s.px = [[0.0, 0.0, 0.0, 0.0] for _ in range(n * n)]  # premultiplied

    def layer(s, shape, color):
        (x0, y0, x1, y1), inside = shape
        n = s.n
        i0, i1 = max(0, int(x0 * n) - 1), min(n, int(x1 * n) + 2)
        j0, j1 = max(0, int(y0 * n) - 1), min(n, int(y1 * n) + 2)
        fn = callable(color)
        for j in range(j0, j1):
            y = (j + 0.5) / n
            for i in range(i0, i1):
                x = (i + 0.5) / n
                if inside(x, y):
                    r, g, b, a = color(x, y) if fn else color
                    if a <= 0:
                        continue
                    p = s.px[j * n + i]
                    k = 1 - a
                    p[0] = r * a + p[0] * k
                    p[1] = g * a + p[1] * k
                    p[2] = b * a + p[2] * k
                    p[3] = a + p[3] * k

    def down(s, m):
        n = s.n
        acc = [[0.0, 0.0, 0.0, 0.0, 0] for _ in range(m * m)]
        idx = [i * m // n for i in range(n)]
        for j in range(n):
            oj = idx[j] * m
            for i in range(n):
                p = s.px[j * n + i]
                q = acc[oj + idx[i]]
                q[0] += p[0]; q[1] += p[1]; q[2] += p[2]; q[3] += p[3]; q[4] += 1
        out = []
        for q in acc:
            c = q[4]
            a = q[3] / c
            if a > 0:
                px = (q[0] / c / a, q[1] / c / a, q[2] / c / a, a)
            else:
                px = (0, 0, 0, 0)
            out.append(tuple(int(round(max(0, min(1, v)) * 255)) for v in px))
        return out


# shapes in unit coordinates (0..1, y down)
def circle(cx, cy, r):
    return (cx - r, cy - r, cx + r, cy + r), lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def ring(cx, cy, r0, r1):
    return (cx - r1, cy - r1, cx + r1, cy + r1), \
        lambda x, y: r0 * r0 <= (x - cx) ** 2 + (y - cy) ** 2 <= r1 * r1


def poly(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]

    def inside(x, y):
        c = False
        for a in range(len(pts)):
            x1, y1 = pts[a]; x2, y2 = pts[a - 1]
            if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                c = not c
        return c
    return (min(xs), min(ys), max(xs), max(ys)), inside


def rot(pts, ang, c):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(c[0] + x * ca - y * sa, c[1] + x * sa + y * ca) for x, y in pts]


# Dark theme colours (theme table)
ACC = hexc("#2FC4A8"); BAR0 = hexc("#1F9E86"); BAR1 = hexc("#3AD9B8")
BORDER = hexc("#2A3340"); TXT = hexc("#E4E8EE")
TOP = hexc("#1E2630"); BOT = hexc("#0C1016")


def logo_waypoint():
    c = Canvas(N)
    c.layer(circle(.5, .5, .47), BORDER)
    c.layer(circle(.5, .5, .455), lambda x, y: mixc(TOP, BOT, (y - .05) / .9))
    c.layer(circle(.5, .5, .40), lambda x, y: ACC[:3] + (
        0.16 * max(0, 1 - math.hypot(x - .5, y - .5) / .40),))
    c.layer(ring(.5, .5, .405, .425), ACC[:3] + (0.9,))
    for (x, y, r, a) in [(.255, .745, .024, .55), (.305, .675, .029, .75), (.385, .635, .034, .95)]:
        c.layer(circle(x, y, r), TXT[:3] + (a,))
    ctr = (.56, .46)
    tip, rw, notch, lw = (0, -.30), (.19, .14), (0, .04), (-.19, .14)
    ang = math.radians(45)
    c.layer(poly(rot([tip, rw, notch, lw], ang, (ctr[0] + .018, ctr[1] + .024))), (0, 0, 0, .45))
    c.layer(poly(rot([tip, notch, lw], ang, ctr)), BAR1)  # lit half
    c.layer(poly(rot([tip, rw, notch], ang, ctr)), BAR0)  # shaded half
    return c


def write_tga(path, size, px):
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
    body = bytearray()
    for j in range(size - 1, -1, -1):
        for r, g, b, a in px[j * size:(j + 1) * size]:
            body += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(hdr + body)


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    art = logo_waypoint()
    for m in (64, 128):
        write_tga(os.path.join(MEDIA, "logo_%d.tga" % m), m, art.down(m))
    print("logo_64.tga, logo_128.tga written")

# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - shared drawing helpers for the art build scripts.
# Copyright (C) 2026 All-in-One Guide contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU
# General Public License for details: <https://www.gnu.org/licenses/>.
#
# Plain Python 3 (math + struct only), deterministic (no randomness).
# Shapes are (bbox, inside) pairs in unit coordinates (0..1, y down).
# Pictures are drawn supersampled into a Mask, outlined with an exact
# distance transform and box-filtered down to the output size.
import math, os, struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "AllinOneGuide", "media")


# ------------------------------------------------------------------ shapes
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


def capsule(p, q, w):
    r = w / 2.0
    x1, y1 = p; x2, y2 = q
    dx, dy = x2 - x1, y2 - y1
    l2 = dx * dx + dy * dy or 1e-12

    def inside(x, y):
        t = ((x - x1) * dx + (y - y1) * dy) / l2
        t = 0.0 if t < 0 else (1.0 if t > 1 else t)
        px, py = x1 + t * dx - x, y1 + t * dy - y
        return px * px + py * py <= r * r
    return (min(x1, x2) - r, min(y1, y2) - r, max(x1, x2) + r, max(y1, y2) + r), inside


def polyline(pts, w):
    return [capsule(pts[i], pts[i + 1], w) for i in range(len(pts) - 1)]


def arc(cx, cy, r, w, a0, a1):
    """Stroke along a circle from angle a0 to a1 (degrees, y down, a1 > a0), round caps."""
    h = w / 2.0
    span = a1 - a0

    def inside(x, y):
        d = math.hypot(x - cx, y - cy)
        if abs(d - r) > h:
            return False
        a = (math.degrees(math.atan2(y - cy, x - cx)) - a0) % 360.0
        return a <= span
    out = [((cx - r - h, cy - r - h, cx + r + h, cy + r + h), inside)]
    for a in (a0, a1):
        t = math.radians(a)
        out.append(circle(cx + r * math.cos(t), cy + r * math.sin(t), h))
    return out


def rrect(x0, y0, x1, y1, rad):
    def inside(x, y):
        qx = min(max(x, x0 + rad), x1 - rad)
        qy = min(max(y, y0 + rad), y1 - rad)
        return (x - qx) ** 2 + (y - qy) ** 2 <= rad * rad
    return (x0, y0, x1, y1), inside


def lens(cx, cy, rad, k):
    """Eye shape: intersection of two circles offset up and down by k."""
    hw = math.sqrt(rad * rad - k * k)
    return (cx - hw, cy - (rad - k), cx + hw, cy + (rad - k)), \
        lambda x, y: (x - cx) ** 2 + (y - cy - k) ** 2 <= rad * rad and \
        (x - cx) ** 2 + (y - cy + k) ** 2 <= rad * rad


# ------------------------------------------------------------------ mask
class Mask:
    """n x n supersampled mask; value 0 = empty, > 0 = filled with that shade."""

    def __init__(s, n):
        s.n = n
        s.v = [0.0] * (n * n)

    def _apply(s, shape, val):
        if isinstance(shape, list):
            for sh in shape:
                s._apply(sh, val)
            return
        (x0, y0, x1, y1), inside = shape
        n = s.n
        i0, i1 = max(0, int(x0 * n) - 1), min(n, int(x1 * n) + 2)
        j0, j1 = max(0, int(y0 * n) - 1), min(n, int(y1 * n) + 2)
        fn = callable(val)
        v = s.v
        for j in range(j0, j1):
            y = (j + 0.5) / n
            for i in range(i0, i1):
                x = (i + 0.5) / n
                if inside(x, y):
                    v[j * n + i] = val(x, y) if fn else val

    def add(s, shape, shade=1.0):
        s._apply(shape, shade)
        return s

    def sub(s, shape):
        s._apply(shape, 0.0)
        return s


def dist2(mask, rmax):
    """Exact squared distance (in supersampled px) to the nearest filled pixel,
    capped: values above rmax^2 are returned as a large number."""
    n = mask.n
    big = 10 ** 9
    v = mask.v
    # 1-D distance along each row
    row = [0] * (n * n)
    for j in range(n):
        base = j * n
        last = -big
        for i in range(n):
            if v[base + i] > 0:
                last = i
            row[base + i] = i - last
        last = big
        for i in range(n - 1, -1, -1):
            if v[base + i] > 0:
                last = i
            d = last - i
            if d < row[base + i]:
                row[base + i] = d
    r2 = rmax * rmax
    out = [big] * (n * n)
    for j in range(n):
        lo, hi = max(0, j - rmax), min(n - 1, j + rmax)
        base = j * n
        for i in range(n):
            best = big
            for jj in range(lo, hi + 1):
                d = row[jj * n + i]
                if d <= rmax:
                    dd = (jj - j) * (jj - j) + d * d
                    if dd < best:
                        best = dd
            out[base + i] = best if best <= r2 else big
    return out


def compose(mask, rim_px, rim_rgba, glow_px=0, glow_a=0.0, under=None):
    """Supersampled premultiplied RGBA: white shapes (shade = grey level),
    a dark rim rim_px wide, an optional soft dark glow beyond it, and an
    optional `under(x, y) -> rgba` layer below the rim/glow."""
    n = mask.n
    d2 = dist2(mask, rim_px + glow_px)
    rr, rg, rb, ra = rim_rgba
    out = []
    v = mask.v
    for idx in range(n * n):
        s = v[idx]
        if s > 0:
            out.append((s, s, s, 1.0))
            continue
        d = d2[idx]
        px = (0.0, 0.0, 0.0, 0.0)
        if under is not None:
            j, i = divmod(idx, n)
            ur, ug, ub, ua = under((i + 0.5) / n, (j + 0.5) / n)
            px = (ur * ua, ug * ua, ub * ua, ua)
        a = 0.0
        if d <= rim_px * rim_px:
            a = ra
        elif glow_px and d < 10 ** 9:
            t = (math.sqrt(d) - rim_px) / glow_px
            a = glow_a * (1 - t) ** 2 if t < 1 else 0.0
        if a > 0:
            k = 1 - a
            px = (rr * a + px[0] * k, rg * a + px[1] * k, rb * a + px[2] * k, a + px[3] * k)
        out.append(px)
    return out


def down(px, n, m):
    """Box-filter n x n premultiplied floats to m x m straight 8-bit RGBA."""
    k = n // m
    out = []
    kk = k * k
    for oj in range(m):
        for oi in range(m):
            r = g = b = a = 0.0
            for j in range(oj * k, oj * k + k):
                base = j * n + oi * k
                for p in px[base:base + k]:
                    r += p[0]; g += p[1]; b += p[2]; a += p[3]
            a /= kk
            if a > 0:
                c = (r / kk / a, g / kk / a, b / kk / a, a)
            else:
                c = (0.0, 0.0, 0.0, 0.0)
            out.append(tuple(int(round(max(0.0, min(1.0, t)) * 255)) for t in c))
    return out


# ------------------------------------------------------------------ files
def write_tga(path, w, h, px):
    """32-bit BGRA, straight alpha, uncompressed (type 2), bottom-left origin."""
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    body = bytearray()
    for j in range(h - 1, -1, -1):
        for r, g, b, a in px[j * w:(j + 1) * w]:
            body += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(hdr + body)

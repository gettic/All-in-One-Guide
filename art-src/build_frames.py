# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - step button frame, reminder glow and progress ring (default "Dark" theme, v0.2).
# Copyright (C) 2026 All-in-One Guide contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU
# General Public License for details: <https://www.gnu.org/licenses/>.
#
# Plain Python 3, deterministic. Run: python art-src/build_frames.py
# Writes only AllinOneGuide/media/frames.tga (128x64) and ring.tga (64x64).
# frames.tga left 64x64: step button frame (rounded square, top-lit bevel,
#   see-through middle), shown 52x52 centred on the 36x36 button.
# frames.tga right 64x64: reminder glow (soft rounded-square halo, white,
#   alpha only), shown 72x72 centred on the 36x36 button.
# ring.tga: progress ring (white, 1 px dark rim), shown 80x80 centred on the
#   64x64 arrow; usable as a Cooldown swipe texture for a radial fill.
# All white / grey; colour in game with SetVertexColor. Coords: MANIFEST.md.
import math, os
from aog_art import MEDIA, Mask, compose, down, ring, rrect, write_tga

SS = 4
RIM = (0.02, 0.03, 0.04, 0.90)


def frame_shade(x, y):  # bevel: lit at the top, darker at the bottom
    return 1.0 - 0.30 * max(0.0, min(1.0, (y - 0.08) / 0.84))


def build_frame():
    n = 64 * SS
    m = Mask(n)
    # outer 5..59 px, hole 10..54 px of 64 (at 52 px on screen the hole is ~36 px)
    m.add(rrect(5 / 64, 5 / 64, 59 / 64, 59 / 64, 0.13), frame_shade)
    m.sub(rrect(10 / 64, 10 / 64, 54 / 64, 54 / 64, 0.06))
    return down(compose(m, SS, RIM), n, 64)


def rrect_dist(x, y, x0, y0, x1, y1, r):
    """Signed distance to a rounded rectangle (negative inside)."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
    out = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return out + min(max(qx, qy), 0.0) - r


def build_glow():
    # button edge at 16..48 px of 64 (36 px on screen at 72 px); halo fades out
    # over 14 px, a thin 3 px fringe fades in over the button edge
    out = []
    S = 8
    for j in range(64):
        for i in range(64):
            acc = 0.0
            for sj in range(S):
                for si in range(S):
                    x = (i + (si + 0.5) / S) / 64
                    y = (j + (sj + 0.5) / S) / 64
                    d = rrect_dist(x, y, 0.25, 0.25, 0.75, 0.75, 0.10) * 64   # in px
                    if d >= 0:
                        t = d / 14.0
                        a = 0.95 * (1 - t) ** 2 if t < 1 else 0.0
                    else:
                        a = 0.95 * max(0.0, 1 + d / 3.0)
                    acc += a
            a = acc / (S * S)
            out.append((255, 255, 255, int(round(a * 255))) if a > 0 else (0, 0, 0, 0))
    return out


def build_ring():
    n = 64 * SS
    m = Mask(n)
    m.add(ring(0.5, 0.5, 0.405, 0.465))
    return down(compose(m, SS, RIM), n, 64)


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    frame, glow = build_frame(), build_glow()
    sheet = []
    for j in range(64):
        sheet += frame[j * 64:(j + 1) * 64] + glow[j * 64:(j + 1) * 64]
    write_tga(os.path.join(MEDIA, "frames.tga"), 128, 64, sheet)
    write_tga(os.path.join(MEDIA, "ring.tga"), 64, 64, build_ring())
    print("frames.tga, ring.tga written")

# SPDX-License-Identifier: GPL-3.0-or-later
# All-in-One Guide - waypoint arrow and arrived marker (default "Dark" theme).
# Copyright (C) 2026 All-in-One Guide contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU
# General Public License for details: <https://www.gnu.org/licenses/>.
#
# Plain Python 3, deterministic. Run: python art-src/build_arrow.py
# Writes only AllinOneGuide/media/arrow.tga and arrived.tga (128x128).
# arrow.tga: white / grey two-tone dart pointing straight up, centred on the
#   texture centre and kept inside the inscribed circle, so SetRotation (or
#   the 8-argument SetTexCoord rotation) never clips it. Tinted in game.
# arrived.tga: tick inside a ring over a dark see-through disc. Tinted in game.
# Both have a baked 2 px dark rim and a soft dark glow (round, so it looks
# the same at every rotation).
import os
from aog_art import MEDIA, Mask, compose, down, poly, polyline, ring, write_tga

SS = 4
OUT = 128
N = OUT * SS
RIM = (0.02, 0.03, 0.04, 0.90)
RIM_PX = 2 * SS
GLOW_PX = 5 * SS
GLOW_A = 0.45

TIP, LW, NOTCH, RW = (0.5, 0.09), (0.21, 0.81), (0.5, 0.64), (0.79, 0.81)


def arrow_shade(x, y):
    t = max(0.0, min(1.0, (y - TIP[1]) / (RW[1] - TIP[1])))
    if x < 0.5:
        return 1.0 - 0.10 * t      # lit half
    return 0.70 - 0.08 * t         # shaded half


def build_arrow():
    m = Mask(N)
    m.add(poly([TIP, RW, NOTCH, LW]), arrow_shade)
    return down(compose(m, RIM_PX, RIM, GLOW_PX, GLOW_A), N, OUT)


def build_arrived():
    m = Mask(N)
    m.add(ring(0.5, 0.5, 0.335, 0.405))
    m.add(polyline([(0.335, 0.515), (0.455, 0.635), (0.675, 0.385)], 0.085))
    fill = (0.04, 0.05, 0.07, 0.55)

    def under(x, y):
        return fill if (x - 0.5) ** 2 + (y - 0.5) ** 2 <= 0.34 ** 2 else (0, 0, 0, 0)
    return down(compose(m, RIM_PX, RIM, GLOW_PX, GLOW_A, under), N, OUT)


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    write_tga(os.path.join(MEDIA, "arrow.tga"), OUT, OUT, build_arrow())
    write_tga(os.path.join(MEDIA, "arrived.tga"), OUT, OUT, build_arrived())
    print("arrow.tga, arrived.tga written")

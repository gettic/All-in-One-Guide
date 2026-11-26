# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 gettic
#
# Builds the guide fonts shipped in AllinOneGuide/media/fonts/ from the original OFL font files, and checks them.
# Sources, commits and hashes: art-src/MANIFEST.md ("Fonts").
#
#   build: python -B tools/build_fonts.py --opensans OpenSans-SemiBold.ttf --opensans-ofl OFL.txt \
#                 --dyslexic OpenDyslexic-Regular.otf --dyslexic-ofl OFL.txt --out AllinOneGuide/media/fonts
#   check: python -B tools/build_fonts.py --check AllinOneGuide/media/fonts      (exit 1 on a problem)
#
# Open Sans SemiBold (static, ttfautohint-hinted): https://github.com/googlefonts/opensans  fonts/ttf/
# OpenDyslexic Regular (CFF .otf):                 https://github.com/antijingoist/opendyslexic  compiled/
# Both are SIL OFL 1.1. OpenDyslexic has the Reserved Font Name "OpenDyslexic": a subset is a Modified Version,
# so ours is named "AOG Readable" and --check fails when a shipped font's name says "OpenDyslexic".
# Open Sans has no Reserved Font Name.
#
# What the build does: keeps only the characters the addon and Western WoW clients need (Latin-1 + Latin
# Extended-A, quotes, dashes, ellipsis, bullet, euro, arrows where present), keeps the TrueType hinting (Open
# Sans) and the kerning, turns the OpenDyslexic CFF outlines into TrueType outlines (WoW draws TTF), writes
# .ttf files plus one OFL.txt with both copyright notices. Needs fontTools (pip install fonttools).
import argparse
import os
import sys

from fontTools.ttLib import TTFont, newTable
from fontTools import subset
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen

UNICODES = (
    list(range(0x20, 0x7F))            # Basic Latin
    + list(range(0xA0, 0x180))         # Latin-1 Supplement + Latin Extended-A (Danish, German, French, Spanish, ...)
    + [0x2013, 0x2014,                 # en / em dash
       0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E,  # quotes
       0x2022, 0x2026,                 # bullet, ellipsis
       0x2039, 0x203A, 0x20AC, 0x2122,
       0x2190, 0x2191, 0x2192, 0x2193,  # arrows (only where the font has them)
       0xFFFD]
)
MUST_HAVE = list(range(0x20, 0x7F)) + [0xB7, 0xC5, 0xC6, 0xC9, 0xD8, 0xE5, 0xE6, 0xE9, 0xF8, 0x2026]

RESERVED = "opendyslexic"          # OFL Reserved Font Name (lower case), never in a shipped font's name
RENAMED = "AOG Readable"
RENAMED_PS = "AOGReadable-Regular"
OUT_NAMES = {"opensans": "OpenSans.ttf", "dyslexic": "AOGReadable.ttf"}
NAME_IDS = (1, 3, 4, 6, 16, 17, 18, 21, 22)


def cff_to_glyf(font, max_err=1.0):
    """CFF (cubic) outlines -> TrueType glyf (quadratic), the fontTools otf2ttf way."""
    glyph_order = font.getGlyphOrder()
    gs = font.getGlyphSet()
    glyf = newTable("glyf")
    glyf.glyphOrder = glyph_order
    glyf.glyphs = {}
    for name in glyph_order:
        pen = TTGlyphPen(gs)
        gs[name].draw(Cu2QuPen(pen, max_err, reverse_direction=True))
        glyf[name] = pen.glyph()
    font["glyf"] = glyf
    font["loca"] = newTable("loca")
    del font["CFF "]
    if "VORG" in font:
        del font["VORG"]
    maxp = font["maxp"]
    maxp.tableVersion = 0x00010000
    for k in ("maxZones", "maxTwilightPoints", "maxStorage", "maxFunctionDefs", "maxInstructionDefs",
              "maxStackElements", "maxSizeOfInstructions", "maxComponentElements"):
        setattr(maxp, k, 0)
    maxp.maxZones = 1
    maxp.maxComponentDepth = 0
    post = font["post"]
    post.formatType = 2.0
    post.extraNames = []
    post.mapping = {}
    post.glyphOrder = glyph_order
    font["head"].glyphDataFormat = 0
    font.sfntVersion = "\x00\x01\x00\x00"


def rename(font, family, ps):
    name = font["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 16, 21):
            name.setName(family, rec.nameID, rec.platformID, rec.platEncID, rec.langID)
        elif rec.nameID == 3:
            name.setName(family + "; subset", 3, rec.platformID, rec.platEncID, rec.langID)
        elif rec.nameID in (4, 18):
            name.setName(family + " Regular", rec.nameID, rec.platformID, rec.platEncID, rec.langID)
        elif rec.nameID == 6:
            name.setName(ps, 6, rec.platformID, rec.platEncID, rec.langID)
        elif rec.nameID in (17, 22):
            name.setName("Regular", rec.nameID, rec.platformID, rec.platEncID, rec.langID)
    # where it came from (the copyright and licence records stay as they are)
    name.setName("Renamed subset of a font by Abbie Gonzalez (SIL OFL 1.1), see OFL.txt.", 10, 3, 1, 0x409)


def do_subset(font):
    opts = subset.Options()
    opts.hinting = True                    # keep TrueType instructions (fpgm / prep / cvt / glyph programs)
    opts.layout_features = ["kern"]
    opts.legacy_kern = True
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.drop_tables += ["DSIG"]
    s = subset.Subsetter(opts)
    s.populate(unicodes=UNICODES)
    s.subset(font)


def split_ofl(path):
    """(notice lines before the licence, licence text from its first dashed line)"""
    with open(path, encoding="utf-8-sig") as f:
        lines = [l.rstrip() for l in f.read().replace("\r\n", "\n").split("\n")]
    i = next(n for n, l in enumerate(lines) if l.startswith("-----"))
    notice = [l for l in lines[:i] if l.strip()]
    return notice, "\n".join(lines[i:]).strip() + "\n"


def write_ofl(out, opensans_ofl, dyslexic_ofl):
    n1, body = split_ofl(opensans_ofl)
    n2, _ = split_ofl(dyslexic_ofl)
    text = ("Fonts in this folder, both under the SIL Open Font License 1.1 (below).\n\n"
            "OpenSans.ttf: a subset of Open Sans SemiBold.\n" + "\n".join(n1) + "\n\n"
            "AOGReadable.ttf: a subset of OpenDyslexic Regular with TrueType outlines, renamed as the\n"
            "Reserved Font Name below asks.\n" + "\n".join(n2) + "\n\n" + body)
    with open(os.path.join(out, "OFL.txt"), "w", encoding="ascii", newline="\r\n") as f:
        f.write(text)


def check(folder):
    problems = []
    ttfs = sorted(n for n in os.listdir(folder) if n.lower().endswith((".ttf", ".otf")))
    if ttfs and not os.path.exists(os.path.join(folder, "OFL.txt")):
        problems.append("OFL.txt missing next to the fonts")
    for n in ttfs:
        f = TTFont(os.path.join(folder, n))
        for rec in f["name"].names:
            if rec.nameID in NAME_IDS and RESERVED in rec.toUnicode().lower().replace(" ", ""):
                problems.append("%s: name %d says %r (OFL Reserved Font Name)" % (n, rec.nameID, rec.toUnicode()))
        if n.lower() == "aogreadable.ttf" and f["name"].getDebugName(1) != RENAMED:
            problems.append("%s: family name is %r, not %r" % (n, f["name"].getDebugName(1), RENAMED))
        cmap = f.getBestCmap()
        miss = ["U+%04X" % u for u in MUST_HAVE if u not in cmap]
        if miss:
            problems.append("%s: lacks %s" % (n, ", ".join(miss)))
        if "glyf" not in f:
            problems.append("%s: no TrueType outlines" % n)
        print("ok   font %s (%d bytes, %s)" % (n, os.path.getsize(os.path.join(folder, n)), f["name"].getDebugName(1)))
    for p in problems:
        print("FAIL font " + p)
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check")
    ap.add_argument("--opensans")
    ap.add_argument("--opensans-ofl")
    ap.add_argument("--dyslexic")
    ap.add_argument("--dyslexic-ofl")
    ap.add_argument("--out")
    a = ap.parse_args()
    if a.check:
        return check(a.check)
    if not (a.opensans and a.opensans_ofl and a.dyslexic and a.dyslexic_ofl and a.out):
        ap.error("build needs --opensans, --opensans-ofl, --dyslexic, --dyslexic-ofl and --out")
    os.makedirs(a.out, exist_ok=True)

    f = TTFont(a.opensans, recalcTimestamp=False)   # same bytes every build
    do_subset(f)
    p = os.path.join(a.out, OUT_NAMES["opensans"])
    f.save(p)
    print("%-16s %7d bytes, %d glyphs" % (OUT_NAMES["opensans"], os.path.getsize(p), len(f.getGlyphOrder())))

    f = TTFont(a.dyslexic, recalcTimestamp=False)
    if "CFF " in f:
        cff_to_glyf(f)
    do_subset(f)
    rename(f, RENAMED, RENAMED_PS)
    p = os.path.join(a.out, OUT_NAMES["dyslexic"])
    f.save(p)
    print("%-16s %7d bytes, %d glyphs" % (OUT_NAMES["dyslexic"], os.path.getsize(p), len(f.getGlyphOrder())))

    write_ofl(a.out, a.opensans_ofl, a.dyslexic_ofl)
    return check(a.out)


if __name__ == "__main__":
    sys.exit(main())

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Slot keys -> { file, l, r, t, b }. Our own art only (art-src\, written to media\); the layout here must
-- match art-src\MANIFEST.md (an offline test compares them). glyphs.tga is 256 x 256 with 32 x 32 slots,
-- 8 per row, slot 0 at the top left.
--   ns.Media.Get(key) -> file, l, r, t, b      ns.Media.Apply(texture, key [, flipV]) -> true / false
local _, ns = ...
local Md = { PATH = "Interface\\AddOns\\AllinOneGuide\\media\\" }
ns.Media = Md

-- Files (width, height in pixels: the raw texture budget is counted from these).
Md.FILES = {
    glyphs = { w = 256, h = 256 },
    arrow = { w = 128, h = 128 },
    arrived = { w = 128, h = 128 },
    logo_64 = { w = 64, h = 64 },
    logo_128 = { w = 128, h = 128 },
}

-- glyphs.tga slot numbers (plans\default-theme\theme-notes.md, "Art files")
Md.SLOTS = {
    ["glyph.step.disc"] = 0, ["glyph.step.ring"] = 1, ["glyph.step.accept"] = 2, ["glyph.step.turnin"] = 3,
    ["glyph.step.kill"] = 4, ["glyph.step.collect"] = 5, ["glyph.step.goto"] = 6, ["glyph.step.done"] = 7,
    ["glyph.check.tick"] = 8, ["glyph.step.level"] = 9, ["glyph.check.box"] = 10, ["glyph.check.fill"] = 11,
    ["glyph.btn.expand"] = 35,
    ["glyph.notice.danger"] = 16, ["glyph.notice.usenow"] = 17, ["glyph.notice.travel"] = 18, ["glyph.notice.class"] = 19,
    ["glyph.notice.legacy"] = 20, ["glyph.notice.tip"] = 21, ["glyph.notice.new"] = 22, ["glyph.notice.hidden"] = 23,
    ["glyph.btn.menu"] = 24, ["glyph.btn.small"] = 25, ["glyph.btn.lock"] = 26, ["glyph.btn.unlock"] = 27,
    ["glyph.btn.close"] = 28, ["glyph.btn.prev"] = 29, ["glyph.btn.next"] = 30, ["glyph.btn.caret"] = 31,
    ["glyph.state.none"] = 32, ["glyph.state.finished"] = 33, ["glyph.state.error"] = 34,
}
-- Whole-file textures.
Md.WHOLE = { ["tex.arrow"] = "arrow", ["tex.arrived"] = "arrived", ["tex.logo"] = "logo_64" }

local PER_ROW, CELL = 8, 1 / 8

function Md.Get(key)
    local whole = Md.WHOLE[key]
    if whole then return Md.PATH .. whole, 0, 1, 0, 1 end
    local n = Md.SLOTS[key]
    if not n then return nil end
    local col, row = n % PER_ROW, math.floor(n / PER_ROW)
    return Md.PATH .. "glyphs", col * CELL, (col + 1) * CELL, row * CELL, (row + 1) * CELL
end

function Md.Apply(tex, key, flipV)
    local file, l, r, t, b = Md.Get(key)
    if not file then
        if ns.Errors then ns.Errors.Debug("media key %s missing", tostring(key)) end
        tex:SetColorTexture(1, 1, 1, 0.3)   -- visible placeholder, never an error
        return false
    end
    tex:SetTexture(file)
    if flipV then tex:SetTexCoord(l, r, b, t) else tex:SetTexCoord(l, r, t, b) end
    return true
end

-- Raw texture memory of the shipped art in bytes (32-bit: 4 bytes per pixel).
function Md.RawBytes()
    local n = 0
    for _, f in pairs(Md.FILES) do n = n + f.w * f.h * 4 end
    return n
end

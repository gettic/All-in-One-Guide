-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Slot keys -> { file, l, r, t, b }. Our own art only (art-src\, written to media\); the layout here must
-- match art-src\MANIFEST.md (an offline test compares them). glyphs.tga is 256 x 256 with 32 x 32 slots,
-- 8 per row, slot 0 at the top left.
--   ns.Media.Get(key) -> file, l, r, t, b      ns.Media.Apply(texture, key [, flipV | "cw"]) -> true / false
local _, ns = ...
local Md = { PATH = "Interface\\AddOns\\AllinOneGuide\\media\\" }
ns.Media = Md

-- Files (width, height in pixels: the raw texture budget is counted from these).
Md.FILES = {
    glyphs = { w = 256, h = 256 },
    arrow = { w = 128, h = 128 },
    arrived = { w = 128, h = 128 },
    logo_64 = { w = 64, h = 64 },
    -- v0.2 (art agent, 2026-11-25)
    frames = { w = 128, h = 64 },
    minimap = { w = 32, h = 32 },
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
    -- v0.2 (art-src\MANIFEST.md)
    ["glyph.step.learn"] = 12, ["glyph.step.train"] = 13, ["glyph.step.note"] = 14, ["glyph.step.useitem"] = 15,
    ["glyph.step.grind"] = 36, ["glyph.step.fly"] = 37, ["glyph.step.hearth"] = 38, ["glyph.step.getfp"] = 39,
    ["glyph.step.sethearth"] = 40, ["glyph.notice.hearth"] = 41, ["glyph.notice.flight"] = 42,
    ["glyph.notice.useitem"] = 43, ["glyph.btn.keybind"] = 44, ["glyph.state.wait"] = 45, ["glyph.notice.snooze"] = 46,
    ["glyph.arrow.corpse"] = 47, ["glyph.pin.body"] = 48, ["glyph.pin.face"] = 49, ["glyph.pin.mini"] = 50,
    ["glyph.pin.ring"] = 51, ["glyph.hub.report"] = 52, ["glyph.hub.about"] = 53, ["glyph.hub.news"] = 54,
    ["glyph.hub.settings"] = 55, ["glyph.report.coords"] = 56, ["glyph.report.order"] = 57,
    ["glyph.report.missing"] = 58, ["glyph.report.notick"] = 59, ["glyph.report.text"] = 60,
    ["glyph.report.other"] = 61, ["glyph.btn.copy"] = 62,
}
-- Whole-file textures.
Md.WHOLE = { ["tex.arrow"] = "arrow", ["tex.arrived"] = "arrived", ["tex.logo"] = "logo_64",
    ["tex.minimap"] = "minimap" }
-- Regions of other files: key -> { file, l, r, t, b } (frames.tga, MANIFEST "frames.tga regions").
Md.REGIONS = {
    ["frame.stepbutton"] = { "frames", 0, 0.5, 0, 1 },
    ["frame.glow"] = { "frames", 0.5, 1, 0, 1 },
}

local PER_ROW, CELL = 8, 1 / 8

function Md.Get(key)
    local whole = Md.WHOLE[key]
    if whole then return Md.PATH .. whole, 0, 1, 0, 1 end
    local reg = Md.REGIONS[key]
    if reg then return Md.PATH .. reg[1], reg[2], reg[3], reg[4], reg[5] end
    local n = Md.SLOTS[key]
    if not n then return nil end
    local col, row = n % PER_ROW, math.floor(n / PER_ROW)
    return Md.PATH .. "glyphs", col * CELL, (col + 1) * CELL, row * CELL, (row + 1) * CELL
end

-- Keys asked for that resolve to no art (the self-test names them: a placeholder is never silent).
Md.missed = {}

function Md.Apply(tex, key, flipV)
    local file, l, r, t, b = Md.Get(key)
    if not file then
        Md.missed[tostring(key)] = true
        if ns.Errors then ns.Errors.Debug("media key %s missing", tostring(key)) end
        tex:SetColorTexture(1, 1, 1, 0.3)   -- visible placeholder, never an error
        return false
    end
    tex:SetTexture(file)
    if flipV == "cw" then
        -- turned a quarter clockwise (a ">" becomes a "v"): 8-value form, corners UL, LL, UR, LR
        tex:SetTexCoord(l, b, r, b, l, t, r, t)
    elseif flipV then
        tex:SetTexCoord(l, r, b, t)
    else
        tex:SetTexCoord(l, r, t, b)
    end
    return true
end

-- Self-test: no texture so far asked for a key that has no art (it would show a grey placeholder).
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "media keys", fn = function(h)
    h.Count()
    local list = {}
    for k in pairs(Md.missed) do list[#list + 1] = k end
    table.sort(list)
    if #list > 0 then h.Problem("media: no art for " .. table.concat(list, ", ", 1, math.min(#list, 4))) end
end }

-- Raw texture memory of the shipped art in bytes (32-bit: 4 bytes per pixel).
function Md.RawBytes()
    local n = 0
    for _, f in pairs(Md.FILES) do n = n + f.w * f.h * 4 end
    return n
end

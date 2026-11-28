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
    -- NOW window + main window (art agent, 2026-11-25): one row of 32 x 32 cells; four 64 x 64 shields
    glyphs2 = { w = 256, h = 32 },
    emblems = { w = 256, h = 64 },
    -- one-window look (art agent, 2026-11-26; plans\guide-window-look\art-map.md): 9-slices, tiles, target
    round = { w = 256, h = 64 },
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
    ["glyph.pin.ring"] = 51, ["glyph.hub.report"] = 52, ["glyph.hub.about"] = 53, ["glyph.hub.news"] = 54,  -- (54: unused since the What's new page went, 2026-11-25; kept in step with art-src\MANIFEST.md)
    ["glyph.hub.settings"] = 55, ["glyph.report.coords"] = 56, ["glyph.report.order"] = 57,
    ["glyph.report.missing"] = 58, ["glyph.report.notick"] = 59, ["glyph.report.text"] = 60,
    ["glyph.report.other"] = 61, ["glyph.btn.copy"] = 62,
    -- glyphs2.tga (one row of 8 cells; MANIFEST "glyphs2.tga cells")
    ["glyph.btn.grip"] = 0, ["glyph.btn.attach"] = 1, ["glyph.btn.detach"] = 2, ["glyph.btn.search"] = 3,
    ["glyph.btn.resize"] = 4,
    -- icon review 2026-11-28 (plans\icon-review\art-slots.md): 32 px talk bubble and "i" (3D view, last fallback)
    ["glyph.step.talk"] = 5, ["glyph.step.info"] = 6,
}
-- Slots that live in another grid file than glyphs.tga: key -> file; Md.GRIDS: file -> rows (8 cells a row).
Md.SLOT_FILE = { ["glyph.btn.grip"] = "glyphs2", ["glyph.btn.attach"] = "glyphs2", ["glyph.btn.detach"] = "glyphs2",
    ["glyph.btn.search"] = "glyphs2", ["glyph.btn.resize"] = "glyphs2", ["glyph.step.talk"] = "glyphs2",
    ["glyph.step.info"] = "glyphs2" }
Md.GRIDS = { glyphs = 8, glyphs2 = 1 }
-- Whole-file textures.
Md.WHOLE = { ["tex.arrow"] = "arrow", ["tex.arrived"] = "arrived", ["tex.logo"] = "logo_64",
    ["tex.minimap"] = "minimap" }
-- Regions of other files: key -> { file, l, r, t, b } (frames.tga, MANIFEST "frames.tga regions").
Md.REGIONS = {
    ["frame.stepbutton"] = { "frames", 0, 0.5, 0, 1 },
    ["frame.glow"] = { "frames", 0.5, 1, 0, 1 },
    -- emblems.tga (MANIFEST "emblems.tga regions")
    ["emblem.alliance"] = { "emblems", 0, 0.25, 0, 1 },
    ["emblem.horde"] = { "emblems", 0.25, 0.5, 0, 1 },
    ["emblem.neutral"] = { "emblems", 0.5, 0.75, 0, 1 },
    ["emblem.soon"] = { "emblems", 0.75, 1, 0, 1 },
    -- glyphs2.tga cell 7, inner 28 x 28 (MANIFEST "Title-bar logo"): the logo for the 16 px title bar
    ["tex.logo.title"] = { "glyphs2", 0.8828125, 0.9921875, 0.0625, 0.9375 },
    -- round.tga (MANIFEST "round.tga regions"): 9-slice pieces (corners in Md.SLICE) and single pieces
    ["frame.panel"] = { "round", 0, 0.125, 0, 0.5 },
    ["frame.border"] = { "round", 0, 0.125, 0.5, 1 },
    ["frame.shadow"] = { "round", 0.25, 0.5, 0, 1 },
    ["round.s"] = { "round", 0.125, 0.25, 0, 0.5 },
    ["btn.target"] = { "round", 0.125, 0.25, 0.5, 1 },
    ["frame.stepbutton2"] = { "round", 0.5, 0.75, 0, 1 },
    -- icon review #6: the get-flight-path and set-hearth tile symbols (glyphs.tga slot 63, its top 16 px quadrants)
    ["tile.getfp"] = { "glyphs", 0.875, 0.9375, 0.875, 0.9375 },
    ["tile.sethearth"] = { "glyphs", 0.9375, 1.0, 0.875, 0.9375 },
}
-- 9-slice corner sizes in texture coordinates (du, dv) for the round.tga pieces.
Md.SLICE = {
    ["frame.panel"] = { 0.0546875, 0.21875 },
    ["frame.border"] = { 0.0546875, 0.21875 },
    ["frame.shadow"] = { 0.10546875, 0.421875 },
    ["round.s"] = { 0.03125, 0.125 },
}
-- Tiles: 16 x 16 cells, 4 x 4 at the right end of round.tga (cell c: l = 0.75 + 0.0625 * (c % 4), t = 0.25 * floor(c / 4)).
Md.TILES = { ["tile.base"] = 0, ["tile.open"] = 1, ["tile.accept"] = 2, ["tile.turnin"] = 3, ["tile.kill"] = 4,
    ["tile.loot"] = 5, ["tile.use"] = 6, ["tile.goto"] = 7, ["tile.talk"] = 8, ["tile.train"] = 9, ["tile.fly"] = 10,
    ["tile.hearth"] = 11, ["tile.note"] = 12, ["tile.done"] = 13, ["tile.level"] = 14, ["tile.grind"] = 15 }
for key, c in pairs(Md.TILES) do
    local l, t = 0.75 + 0.0625 * (c % 4), 0.25 * math.floor(c / 4)
    Md.REGIONS[key] = { "round", l, l + 0.0625, t, t + 0.25 }
end

local PER_ROW, CELL = 8, 1 / 8

function Md.Get(key)
    local whole = Md.WHOLE[key]
    if whole then return Md.PATH .. whole, 0, 1, 0, 1 end
    local reg = Md.REGIONS[key]
    if reg then return Md.PATH .. reg[1], reg[2], reg[3], reg[4], reg[5] end
    local n = Md.SLOTS[key]
    if not n then return nil end
    local file = Md.SLOT_FILE[key] or "glyphs"
    local rowH = 1 / (Md.GRIDS[file] or 8)
    local col, row = n % PER_ROW, math.floor(n / PER_ROW)
    return Md.PATH .. file, col * CELL, (col + 1) * CELL, row * rowH, (row + 1) * rowH
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

-- Text fonts (setting "font"; plans\font\plan.md). file = ours in media\fonts\ (SIL OFL 1.1, built by
-- tools\build_fonts.py, see media\fonts\OFL.txt), game = a built-in game font. scale: on every font size (same
-- look size as the old Arial Narrow), line: on the line height, numbers: the font for outlined number texts.
Md.FONTS = {
    opensans = { file = "fonts\\OpenSans.ttf", scale = 0.9, line = 1 },
    dyslexic = { file = "fonts\\AOGReadable.ttf", scale = 0.75, line = 1.15, numbers = "opensans" },
    classic = { game = "Fonts\\FRIZQT__.TTF", scale = 0.93, line = 1 },
}
Md.FONT_ORDER = { "opensans", "dyslexic", "classic" }
Md.FONT_DEFAULT = "opensans"

-- The game path of a Md.FONTS entry.
function Md.FontPath(d)
    d = d or Md.FONTS[Md.FONT_DEFAULT]
    if d.file then return Md.PATH .. d.file end
    return d.game
end

-- An addon font can draw blank the first time it is used: one hidden font string per shipped font loads each
-- file while the addon loads (UIKit refreshes the texts once more one frame after login, see below).
function Md.PreloadFonts()
    if Md.preload then return end
    local CF = rawget(_G, "CreateFrame")
    if not CF then return end
    local f = CF("Frame")
    f:Hide()
    Md.preload = {}
    for _, id in ipairs(Md.FONT_ORDER) do
        local d = Md.FONTS[id]
        if d.file then
            local fs = f:CreateFontString(nil, "BACKGROUND")
            Md.preload[id] = fs:SetFont(Md.FontPath(d), 12, "") and true or false
            fs:SetText("Wa")
        end
    end
end
Md.PreloadFonts()
-- once more after login: texts made before the file was ready get their font again (blank first draws). One
-- frame later and after the guide window (Login order 80) and the options entry (90) are built, so their texts
-- are covered too (at order 50 in the same frame it covered none).
Md.REFRESH_ORDER = 95
function Md.RefreshAfterLogin()
    local _, d = ns.Theme.FontFile()
    if d and d.file and ns.UIKit then
        ns.UIKit.RefreshFonts()
        Md.refreshed = #ns.UIKit.texts
    end
end
if ns.Bus then   -- (check-zip loads this file alone)
    ns.Bus.On("Login", Md, function()
        ns.Compat.After(0, function() ns.Errors.Call("ui", Md.RefreshAfterLogin) end)
    end, "ui", Md.REFRESH_ORDER)
end

-- Self-test: does font entry d load? true, or false + why. A hidden probe of our own (text cleared after).
function Md.FontLoaded(d)
    local CF = rawget(_G, "CreateFrame")
    if not CF then return false, "no CreateFrame" end
    if not Md.probe then
        local f = CF("Frame")
        f:Hide()
        Md.probe = f:CreateFontString(nil, "BACKGROUND")
    end
    local fs, path = Md.probe, Md.FontPath(d)
    if not fs:SetFont(path, 12, "") then return false, "SetFont failed" end
    local got = fs:GetFont()
    if type(got) ~= "string" or got:lower() ~= path:lower() then return false, "font is " .. tostring(got) end
    fs:SetText("Wa")
    local w = fs:GetStringWidth()
    fs:SetText("")
    if type(w) ~= "number" or w <= 0 then return false, "draws nothing" end
    return true
end

-- Raw texture memory of the shipped art in bytes (32-bit: 4 bytes per pixel).
function Md.RawBytes()
    local n = 0
    for _, f in pairs(Md.FILES) do n = n + f.w * f.h * 4 end
    return n
end

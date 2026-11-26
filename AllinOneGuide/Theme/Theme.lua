-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Themes are data. A theme is one table of semantic keys (colours, fonts, sizes, slot keys, motion);
-- anything it doesn't set comes from its `base` theme. UI code asks for keys, never for values:
--   ns.Theme.Color(key) -> r, g, b, a      ns.Theme.Hex(key) -> "ffrrggbb" (for |c codes)
--   ns.Theme.Font(fs, key [, shadow])      ns.Theme.LineHeight(key)   ns.Theme.Size(key)
--   ns.Theme.Glyph(tex, key [, flip])      (slot key -> media through Theme\Media.lua)
-- Fonts: the text font setting picks one of Theme\Media.lua's Md.FONTS (our OFL fonts in media\fonts\ or a
-- built-in game font) with its own size scale; non-Western clients keep the game's own font.
local _, ns = ...
-- overlays (v0.2 M4, Theme\Overlay.lua): tables laid over any theme (high contrast, colour-blind), last
-- one wins; fontDelta: points added to every font size (font size setting, large text).
-- MIN_FONT 8 (was 9; font size fix 2026-11-25, the user: "cant go low enough"): the smallest setting -4 gives
-- 8 pt step text, and the small texts stop at 8 pt too.
-- face: the text font id (setting "font", Md.FONTS key; set by Overlay.Apply through SetOverlays).
local Th = { themes = {}, name = nil, cache = {}, MIN_FONT = 8, MAX_FONT = 24, overlays = {}, fontDelta = 0,
    face = "opensans" }
ns.Theme = Th

function Th.Register(name, t)
    t.name = name
    Th.themes[name] = t
end

-- A key from the active overlays, then the current theme, then its base chain. nil when none knows it.
-- With an explicit theme name the overlays are skipped (the "every key resolves" checks).
function Th.Raw(key, name)
    if not name then
        local o = Th.overlays
        for i = #o, 1, -1 do
            local v = o[i][key]
            if v ~= nil then return v end
        end
    end
    local t = Th.themes[name or Th.name or "Dark"]
    for _ = 1, 8 do
        if not t then return nil end
        local v = t[key]
        if v ~= nil then return v end
        t = t.base and Th.themes[t.base]
    end
    return nil
end

function Th.Use(name)
    if not Th.themes[name] then name = "Dark" end
    Th.name = name
    Th.cache, Th.num = {}, {}
    if ns.Bus then ns.Bus.Fire("ThemeChanged", name) end
end

local function Missing(key)
    if ns.Errors then ns.Errors.Debug("theme key %s missing", tostring(key)) end
end

-- "#2FC4A8" + alpha -> { r, g, b, a } (parsed once per theme).
local function Parse(v)
    if type(v) == "table" then
        local hex, a = v[1], v[2]
        local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
        if not r then return nil end
        return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, a or 1, hex = hex:gsub("^#", "") }
    elseif type(v) == "string" then
        return Parse({ v, 1 })
    end
    return nil
end

local function ColorEntry(key)
    local c = Th.cache[key]
    if c then return c end
    local v = Th.Raw("color." .. key)
    -- "= other.key": the same colour as another key
    if type(v) == "string" and v:sub(1, 1) == "=" then return ColorEntry(v:sub(2)) end
    c = Parse(v)
    if not c then
        Missing("color." .. key)
        c = { 1, 1, 1, 1, hex = "FFFFFF" }
    end
    Th.cache[key] = c
    return c
end

function Th.Color(key)
    local c = ColorEntry(key)
    return c[1], c[2], c[3], c[4]
end

function Th.Hex(key) return "ff" .. ColorEntry(key).hex end

-- Wraps text in a colour code from the theme.
function Th.Wrap(key, text) return "|c" .. Th.Hex(key) .. tostring(text) .. "|r" end

function Th.Has(key) return Th.Raw(key) ~= nil end

-- Th.num: sizes and line heights already looked up (perf: hundreds per window refresh); cleared with the colour
-- cache (Use, SetOverlays). Missing keys are never kept, so they are still reported every time.
Th.num = {}
function Th.Size(key)
    local c = Th.num[key]
    if c then return c end
    local v = Th.Raw("size." .. key)
    if type(v) ~= "number" then Missing("size." .. key) return 0 end
    Th.num[key] = v
    return v
end

-- An alpha (0..1) from "alpha.<key>"; `fallback` (or 1) when the theme has none.
function Th.Alpha(key, fallback)
    local v = Th.Raw("alpha." .. key)
    if type(v) ~= "number" then Missing("alpha." .. key) return fallback or 1 end
    return math.max(0, math.min(1, v))
end

-- A built-in game file path from "file.<key>" (never our media: those go through slot keys).
function Th.File(key)
    local v = Th.Raw("file." .. key)
    if type(v) ~= "string" or v == "" then Missing("file." .. key) return nil end
    return v
end

local function FontSpec(key)
    local f = Th.Raw("font." .. key)
    if type(f) ~= "table" then
        Missing("font." .. key)
        f = { size = 12 }
    end
    return f
end

-- The font in use for a font key: file path and its Md.FONTS entry, or (game font file, nil) on a client
-- whose alphabet our fonts don't have. A key with `numbers = true` (arrow distance, button counts) uses the
-- face's `numbers` font when it names one (Easy-read: Open Sans for outlined digits).
local WESTERN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, ptBR = true, itIT = true }
Th.WESTERN = WESTERN
-- (kept in Th.num until the next Use / SetOverlays: every Font / FontSize call asks)
function Th.Western()
    local w = Th.num["\1western"]
    if w == nil then
        w = WESTERN[ns.Compat.Locale()] and true or false
        Th.num["\1western"] = w
    end
    return w
end
function Th.Face(key)
    local Md = ns.Media
    local id = Md.FONTS[Th.face] and Th.face or Md.FONT_DEFAULT
    if key and Md.FONTS[id].numbers and FontSpec(key).numbers then id = Md.FONTS[id].numbers end
    return id, Md.FONTS[id]
end
function Th.FontFile(key)
    if Th.Western() then
        local _, d = Th.Face(key)
        return ns.Media.FontPath(d), d
    end
    local base = rawget(_G, "GameFontNormal")
    if base and base.GetFont then
        local f = base:GetFont()
        if f then return f end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- Size: the theme's size + the font size setting (whole points, MIN_FONT..MAX_FONT), times the font's scale
-- (one decimal), never under MIN_FONT.
function Th.FontSize(key)
    local size = math.floor((FontSpec(key).size or 12) + (Th.fontDelta or 0))
    size = math.min(Th.MAX_FONT, math.max(Th.MIN_FONT, size))
    local _, d = Th.FontFile(key)
    local scale = d and d.scale or 1
    if scale ~= 1 then size = math.max(Th.MIN_FONT, math.floor(size * scale * 10 + 0.5) / 10) end
    return size
end

-- Sets the overlays, the font delta and the text font (Theme\Overlay.lua); colours are parsed again.
function Th.SetOverlays(list, fontDelta, face)
    Th.overlays = list or {}
    Th.fontDelta = fontDelta or 0
    if face then Th.face = face end
    Th.cache, Th.num = {}, {}
end

-- Row height from the font size x line spacing (whole units), so bigger text never clips.
-- (kept in Th.num under "\1lh.<key>", only when the font key exists)
local LH_KEY = {}
function Th.LineHeight(key)
    local k = LH_KEY[key]
    if not k then k = "\1lh." .. tostring(key) LH_KEY[key] = k end
    local c = Th.num[k]
    if c then return c end
    local _, d = Th.FontFile(key)
    c = math.ceil(Th.FontSize(key) * (Th.Raw("lineSpacing") or 1.35) * (d and d.line or 1))
    if type(Th.Raw("font." .. tostring(key))) == "table" then Th.num[k] = c end
    return c
end

-- Sets a font string's font from a theme font key. shadow = true forces a drop shadow
-- (used when the panel is very see-through, so text stays readable).
function Th.Font(fs, key, shadow)
    local spec = FontSpec(key)
    -- a font file that fails to load falls back to the client's own font object (never "font not set")
    if not fs:SetFont((Th.FontFile(key)), Th.FontSize(key), spec.flags) then
        local base = rawget(_G, "GameFontHighlight")
        if base then fs:SetFontObject(base) end
    end
    if spec.shadow or shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- A texture from a slot key (glyph.*, tex.*) through Theme\Media.lua.
function Th.Glyph(tex, key, flip)
    local slot = Th.Raw("slot." .. key) or key
    return ns.Media.Apply(tex, slot, flip)
end

-- Motion: durations in seconds, 0 when the player asked for reduced motion.
function Th.Motion(key)
    if ns.Settings and ns.Settings.Get("reducedMotion") then return 0 end
    local v = Th.Raw("motion." .. key)
    return type(v) == "number" and v or 0
end

-- The keys a new theme should set itself (the rest falls back to its base theme): the window's look.
Th.REQUIRED = {
    "color.panel", "color.panelSolid", "color.border", "color.shadow", "color.text", "color.text.dim", "color.upcoming",
    "color.accent", "color.accentText", "color.accentGlow", "color.zone", "color.titleBg", "color.goalNowBg",
    "color.goalNowEdge", "color.barTrack", "color.barFill", "color.chipBg", "color.chipText", "color.button",
    "color.buttonHover", "color.verb.accept", "color.verb.turnin", "color.verb.kill", "color.verb.loot",
    "color.verb.goto", "font.step", "font.goal", "font.title", "font.small", "size.corner", "size.pad", "size.title",
}

-- The REQUIRED keys theme `name` resolves to nothing (base chain included, overlays left out). {} = complete.
function Th.MissingKeys(name)
    local out = {}
    for _, key in ipairs(Th.REQUIRED) do
        if Th.Raw(key, name) == nil then out[#out + 1] = key end
    end
    return out
end

-- Every key a theme uses (for the "every key resolves" test and the self-test).
function Th.Keys(name)
    local out, seen = {}, {}
    local t = Th.themes[name or Th.name or "Dark"]
    while t do
        for k in pairs(t) do
            if type(k) == "string" and k:find(".", 1, true) and not seen[k] then
                seen[k] = true
                out[#out + 1] = k
            end
        end
        t = t.base and Th.themes[t.base]
    end
    table.sort(out)
    return out
end

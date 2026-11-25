-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Text style lint (v0.1.1, T19 / G-B56 / G-B59): our own texts only, short and in our own words.
--   locale files: English / Danish key parity, {placeholder} parity, per-spot length caps (Danish +40 %),
--                 never-use words, no "&", no version numbers, no "%s"-style formats
--   pack steps:   text / da / why length cap, starts with a capital, never-use words, signs of copied
--                 quest text (Blizzard tokens like $N, narration words, more than 2 sentences, quotes)
-- Run (from the repository folder):
--   luajit tools/textlint.lua [--addon AllinOneGuide] [--words <private never-use list>] [--locale-only]
--                             [packs-src/x.lua ...]       (no packs given: every pack in packs-src\)
--   Exit code 1 on an error. Pack findings are warnings unless the pack says strict = true.
-- As a library: local TL = assert(loadfile("tools/textlint.lua"))("--lib", "<tools folder>")
local args = { ... }
local toolsDir = (args[1] == "--lib" and args[2]) or (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tools"
local TL = {}

local function Here(rel) return toolsDir .. "/" .. rel end

function TL.Rules()
    local chunk = assert(loadfile(Here("data/textrules.lua")))
    setfenv(chunk, {})
    return chunk()
end

local function Utf8Len(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end
TL.Utf8Len = Utf8Len

local function Fields(s)
    local t = {}
    for f in tostring(s):gmatch("{([%w_]+)}") do t[#t + 1] = f end
    table.sort(t)
    return table.concat(t, ",")
end

local function Bare(s) return (tostring(s):gsub("{[%w_]+}", "")) end

function TL.CapFor(rules, key, lang)
    for _, l in ipairs(rules.lengths) do
        if key:match(l.key) then
            if lang == "da" then return math.floor(l.en * (rules.daFactor or 1.4)), l.why end
            return l.en, l.why
        end
    end
    return nil
end

-- Words, signs and formats shared by locale and pack texts. Returns a list of messages.
function TL.Words(rules, text, lang, extraWords)
    local out = {}
    local lower = text:lower()
    for _, w in ipairs(rules.neverUse) do
        if lower:find(w, 1, true) then out[#out + 1] = "never-use word '" .. w .. "'" end
    end
    if lang == "da" then
        for _, w in ipairs(rules.neverUseDa or {}) do
            if lower:find(w, 1, true) then out[#out + 1] = "never-use word '" .. w .. "'" end
        end
    end
    for _, w in ipairs(rules.neverUseWhole or {}) do
        if lower:find("%f[%a]" .. w .. "%f[%A]") then out[#out + 1] = "never-use word '" .. w .. "'" end
    end
    for _, w in ipairs(extraWords or {}) do
        if lower:find(w, 1, true) then out[#out + 1] = "never-use word (private list)" end
    end
    if text:find("&", 1, true) then out[#out + 1] = "'&' (write 'and' / 'og')" end
    if text:find("%f[%w]v?%d+%.%d+%.%d+") or text:find("%f[%w]v%d+%.%d+") then out[#out + 1] = "version number in a player text" end
    if text:find("%%[sdif]") then out[#out + 1] = "'%s'-style format (use {named} fields)" end
    return out
end

local function Matches(key, list)
    for _, p in ipairs(list or {}) do if key:match(p) then return true end end
    return false
end

-- Locale-only rules: no programmer words, no blame / alarm words, chat lines start lower case,
-- tooltips and menu rows have no full stop. Returns a list of messages.
function TL.LocaleOnly(rules, key, text)
    local out = {}
    local lower = Bare(text):lower()
    for _, w in ipairs(rules.jargon or {}) do
        if lower:find("%f[%a]" .. w .. "%f[%A]") then out[#out + 1] = "programmer word '" .. w .. "'" end
    end
    for _, w in ipairs(rules.localeAlarm or {}) do
        if lower:find(w, 1, true) then out[#out + 1] = "alarm word '" .. w .. "'" end
    end
    if Matches(key, rules.chatKeys) and text:find("^%u") then out[#out + 1] = "chat line starts with a capital (it follows the prefix)" end
    if Matches(key, rules.noStopKeys) and text:find("%.$") then out[#out + 1] = "full stop at the end of a tooltip / menu row" end
    return out
end

-- en, da: key -> text tables. Returns errors, warnings.
function TL.LintLocale(rules, en, da, extraWords)
    local errs, warns = {}, {}
    local function E(k, m) errs[#errs + 1] = k .. ": " .. m end
    local keys = {}
    for k in pairs(en) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local e = en[k]
        if type(e) ~= "string" then E(k, "not text")
        else
            local cap = TL.CapFor(rules, k, "en")
            if cap and Utf8Len(Bare(e)) > cap then E(k, ("English %d characters, the spot holds %d"):format(Utf8Len(Bare(e)), cap)) end
            for _, m in ipairs(TL.Words(rules, e, "en", extraWords)) do E(k, m) end
            for _, m in ipairs(TL.LocaleOnly(rules, k, e)) do E(k, m) end
            local d = da and da[k]
            -- Danish is written in one batch before each release (the user's rule, 2026-11-25): until then a
            -- missing key falls back to English, so it's a warning, not an error
            if da and d == nil then warns[#warns + 1] = k .. ": not in Danish yet (English shows until the release batch)"
            elseif type(d) == "string" then
                if Fields(d) ~= Fields(e) then E(k, "Danish {fields} differ") end
                local dcap = TL.CapFor(rules, k, "da")
                if dcap and Utf8Len(Bare(d)) > dcap then E(k, ("Danish %d characters, the spot holds %d"):format(Utf8Len(Bare(d)), dcap)) end
                for _, m in ipairs(TL.Words(rules, d, "da", extraWords)) do E(k, "da " .. m) end
                for _, m in ipairs(TL.LocaleOnly(rules, k, d)) do E(k, "da " .. m) end
            end
        end
    end
    for k in pairs(da or {}) do
        if en[k] == nil then warns[#warns + 1] = k .. ": Danish key with no English" end
    end
    return errs, warns
end

local function StartsWith(text, list)
    for _, w in ipairs(list or {}) do
        if text:sub(1, #w) == w and not text:sub(#w + 1, #w + 1):find("%a") then return w end
    end
    return nil
end

-- One step text. kind: "text" (English, default), "da" or "why". Returns a list of messages.
function TL.LintStepText(rules, text, lang, extraWords, kind)
    local out = {}
    kind = kind or (lang == "da" and "da" or "text")
    local cap = (kind == "da" and rules.stepTextDa) or (kind == "why" and rules.whyText) or rules.stepText
    local len = Utf8Len(Bare(text))
    if len > cap then out[#out + 1] = ("%d characters (max %d)"):format(len, cap) end
    if kind == "text" and rules.firstWords then
        local first = StartsWith(text, rules.firstWords)
        if not first then
            out[#out + 1] = "doesn't start with a step verb (" .. tostring(text:match("^(%S+)")) .. ")"
        elseif StartsWith(text, rules.countVerbs) then
            local low = " " .. Bare(text):lower() .. " "
            local place = false
            for _, w in ipairs(rules.placeWords or {}) do
                if low:find(" " .. w .. " ", 1, true) then place = true break end
            end
            if not text:find("%d") and not place and not low:find(" the ", 1, true) then
                out[#out + 1] = "kill / collect step without a count or a place"
            end
        end
    end
    for _, m in ipairs(TL.Words(rules, text, lang, extraWords)) do out[#out + 1] = m end
    local c = rules.copied
    for _, p in ipairs(c.tokens) do
        if text:find(p) then out[#out + 1] = "quest-text token '" .. p .. "' (copied text?)" end
    end
    local lower = " " .. text:lower() .. " "
    for _, w in ipairs(c.narration) do
        if lower:find(w, 1, true) then out[#out + 1] = "narration '" .. w .. "' (our own short words only)" end
    end
    if lang ~= "da" then
        for _, w in ipairs(c.firstPerson or {}) do
            if lower:find(w, 1, true) then out[#out + 1] = "first person '" .. w .. "' (copied text?)" end
        end
    end
    local _, sentences = (text .. " "):gsub("[%.!?]+%s", "")
    if sentences > c.maxSentences then out[#out + 1] = sentences .. " sentences (copied text?)" end
    if text:find('"', 1, true) or text:find("\226\128\156", 1, true) then out[#out + 1] = "quote marks (copied text?)" end
    if text:find("%u%u%u%u+%s+%u%u%u%u+") then out[#out + 1] = "capital-letter run" end
    return out
end

-- A loaded source pack (after include expansion: routes). Returns errors, warnings.
function TL.LintPack(rules, pack, routes, name, extraWords)
    local errs, warns = {}, {}
    local list = pack.strict and errs or warns
    for _, r in ipairs(routes) do
        for i, s in ipairs(r.steps) do
            for _, k in ipairs({ "text", "da", "why" }) do
                local v = s[k]
                if type(v) == "string" then
                    for _, m in ipairs(TL.LintStepText(rules, v, k == "da" and "da" or "en", extraWords, k)) do
                        list[#list + 1] = ("%s: %s #%d %s %s: %s"):format(name, r.id, i, tostring(s.id), k, m)
                    end
                end
            end
        end
    end
    return errs, warns
end

-- Loads Locale\enUS.lua and daDK.lua with a stub namespace (they only call ns.Locale.Add).
function TL.LoadLocales(addonDir)
    local tables = {}
    local ns = { Locale = { Add = function(code, t) tables[code] = t end } }
    for _, f in ipairs({ "enUS", "daDK" }) do
        local chunk = loadfile(addonDir .. "/Locale/" .. f .. ".lua")
        if chunk then
            setfenv(chunk, {})
            pcall(chunk, "AllinOneGuide", ns)
        end
    end
    return tables.enUS, tables.daDK
end

-- Encoding check of one file's bytes: BOM, invalid UTF-8, mojibake (UTF-8 read as Windows-1252 and saved
-- again: "Ã" + a byte from 0x80-0xBF, "Â" before a symbol, "â€"). Returns a list of messages with line numbers.
local CP1252 = { "\226\130\172", "\226\128\154", "\198\146", "\226\128\158", "\226\128\166", "\226\128\160",
    "\226\128\161", "\203\134", "\226\128\176", "\197\160", "\226\128\185", "\197\146", "\197\189",
    "\226\128\152", "\226\128\153", "\226\128\156", "\226\128\157", "\226\128\162", "\226\128\147",
    "\226\128\148", "\203\156", "\226\132\162", "\197\161", "\226\128\186", "\197\147", "\197\190", "\197\184" }

local function MojibakeAt(line)
    -- "Ã" (C3 83) then C2 80-BF (a byte 0x80-0xBF) or a Windows-1252 symbol standing for 0x80-0x9F
    local from = 1
    while true do
        local a = line:find("\195\131", from, true)
        if not a then break end
        local nxt = line:sub(a + 2, a + 3)
        if nxt:find("^\194[\128-\191]") then return "Ã" .. nxt end
        for _, c in ipairs(CP1252) do
            if line:sub(a + 2, a + 1 + #c) == c then return "Ã" .. c end
        end
        from = a + 2
    end
    local b = line:find("\195\130\194[\128-\191]")      -- "Â" before a symbol
    if b then return line:sub(b, b + 3) end
    if line:find("\195\162\226\130\172", 1, true) then return "â€" end
    return nil
end

function TL.LintEncoding(bytes)
    local out = {}
    if bytes:sub(1, 3) == "\239\187\191" then out[#out + 1] = "byte order mark (BOM) at the start" end
    local n = 0
    for line in (bytes .. "\n"):gmatch("(.-)\r?\n") do
        n = n + 1
        local i, len, bad = 1, #line, false
        while i <= len do
            local c = line:byte(i)
            local l = c < 0x80 and 1 or (c >= 0xC2 and c <= 0xDF) and 2 or (c >= 0xE0 and c <= 0xEF) and 3
                or (c >= 0xF0 and c <= 0xF4) and 4 or nil
            if not l or i + l - 1 > len then bad = true break end
            for j = i + 1, i + l - 1 do
                local b = line:byte(j)
                if b < 0x80 or b > 0xBF then bad = true end
            end
            if bad then break end
            i = i + l
        end
        if bad then out[#out + 1] = ("line %d: invalid UTF-8"):format(n)
        else
            local m = MojibakeAt(line)
            if m then out[#out + 1] = ("line %d: mojibake '%s' (UTF-8 saved as Windows-1252)"):format(n, m) end
        end
    end
    return out
end

function TL.LintEncodingFile(path)
    local fh = io.open(path, "rb")
    if not fh then return { "cannot read file" } end
    local bytes = fh:read("*a")
    fh:close()
    return TL.LintEncoding(bytes)
end

function TL.LoadWords(path)
    local out = {}
    local fh = path and io.open(path, "r")
    if not fh then return out end
    for line in fh:lines() do
        line = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        if line ~= "" then out[#out + 1] = line:lower() end
    end
    fh:close()
    return out
end

function TL.Main(argv)
    local opts = { addon = "AllinOneGuide", files = {} }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--addon" or a == "--words" then
            opts[a:sub(3)] = argv[i + 1]
            i = i + 2
        elseif a == "--locale-only" then
            opts.localeOnly = true
            i = i + 1
        else
            opts.files[#opts.files + 1] = a
            i = i + 1
        end
    end
    local rules = TL.Rules()
    local words = TL.LoadWords(opts.words)
    local nErr, nWarn = 0, 0
    local en, da = TL.LoadLocales(opts.addon)
    if not en then
        print("ERROR locale: Locale/enUS.lua not found")
        return false
    end
    local Lib0 = assert(loadfile(Here("packlib.lua")))()
    local encFiles = { opts.addon .. "/Locale/enUS.lua", opts.addon .. "/Locale/daDK.lua" }
    if not opts.localeOnly then
        for _, f in ipairs(Lib0.ListDir("packs-src", "lua")) do encFiles[#encFiles + 1] = "packs-src/" .. f end
        for _, f in ipairs(Lib0.ListDir(opts.addon .. "/Routes", "lua")) do encFiles[#encFiles + 1] = opts.addon .. "/Routes/" .. f end
    end
    for _, f in ipairs(encFiles) do
        for _, m in ipairs(TL.LintEncodingFile(f)) do
            print("ERROR encoding " .. f .. ": " .. m)
            nErr = nErr + 1
        end
    end
    local errs, warns = TL.LintLocale(rules, en, da, words)
    for _, e in ipairs(errs) do print("ERROR locale " .. e) end
    for _, w in ipairs(warns) do print("WARN locale " .. w) end
    nErr, nWarn = nErr + #errs, nWarn + #warns
    if not opts.localeOnly then
        local Lib = assert(loadfile(Here("packlib.lua")))()
        if #opts.files == 0 then
            for _, f in ipairs(Lib.ListDir("packs-src", "lua")) do opts.files[#opts.files + 1] = "packs-src/" .. f end
        end
        for _, f in ipairs(opts.files) do
            local t = Lib.LoadData(f)
            if Lib.IsPack(t) then
                local routes = Lib.Expand(t)
                local pe, pw = TL.LintPack(rules, t, routes, f, words)
                for _, e in ipairs(pe) do print("ERROR " .. e) end
                for _, w in ipairs(pw) do print("WARN " .. w) end
                nErr, nWarn = nErr + #pe, nWarn + #pw
            end
        end
    end
    print(("textlint: %d errors, %d warnings"):format(nErr, nWarn))
    return nErr == 0
end

if args[1] == "--lib" then return TL end
if not TL.Main(args) then os.exit(1) end

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- /aog selftest [full]: the addon checks itself in the running game (from the wowforever-kit's
-- self-test starter, .claude\tools\selftest\GUIDE.md, filled in for this addon).
-- What it checks: the guide window's parts (shown, placed, sized, on screen, not covered, art loads),
-- the arrow / notice line / chip when they are up, the saved data through our own repair + migration
-- (on a copy only), every API in Compat\ApiList.lua (exists / missing / not secure / secret), that every
-- theme key resolves, Texture:SetRotation, the width of "æøå" against "aoa" (the font has the letters),
-- the language table, and the budgets (memory, login ms, no load-on-demand module loaded at login,
-- no OnUpdate while hidden, save sizes).
-- It also runs by itself once per new addon version / client build, out of combat, a little after
-- login (then it never opens the window and shows no box; one chat line only when something failed).
-- The line "AOG selftest: N ok, M fail" is kept for /aog status and the error copy text.
-- Safety: reads only. It shows and hides only our own frames and puts them back (even after an error);
-- no Blizzard function is replaced or hooked; nothing protected. Every value read from a frame goes
-- through Read() (secret = "skipped (secret)"). In combat it waits; combat mid-run stops it and puts
-- everything back. Saved data is checked on deep copies. The report is English, with no player,
-- character, realm or guild names and no item links: counts, codes and our frame names only.
local ADDON_NAME, ns = ...
local Co = ns.Compat

local ST = { RUN_DELAY = 4 }
ns.SelfTest = ST

local MAX_LIST = 8          -- skipped names listed in the report
local COVER_SHARE = 0.3     -- a part counts as covered when this much of it is under another frame
local SCREEN_SLACK = 2      -- px
local COPY_MAX = 4000       -- report length
local LINE_MAX = 200        -- the stored line
-- budgets (plans\v0.1\BUILD-PLAN.md section 8); the self-test fails at twice the budget, so a slow
-- PC or a busy login doesn't fail it, but a real leak or a runaway save does
local BUDGET = { memKB = 1536, loginMs = 20, charKB = 10, accKB = 20 }
local SLACK = 2

local run                   -- the run in progress (nil when idle)

-- ---------------------------------------------------------------------------
-- Safe reads

local function IsSecret(v)
    local ok, s = pcall(Co.IsSecret, v)
    return ok and s and true or false
end

local function Pack(...) return { n = select("#", ...), ... } end

-- obj:method(...) -> "ok", results... | "noapi" | "err" | "secret" (any result secret).
local function Read(obj, method, ...)
    if type(obj) ~= "table" then return "noapi" end
    local f = obj[method]
    if type(f) ~= "function" then return "noapi" end
    local r = Pack(pcall(f, obj, ...))
    if not r[1] then return "err" end
    for i = 2, r.n do
        if IsSecret(r[i]) then return "secret" end
    end
    return "ok", unpack(r, 2, r.n)
end
ST.Read = Read

local function InCombat() return Co.InCombat() end
local function Short(err) return "error: " .. tostring(err):gsub("^.-:%d+: ", ""):sub(1, 80) end

-- ---------------------------------------------------------------------------
-- Results

local function Count(n) run.checks = run.checks + (n or 1) end
local function Problem(code, name, text) run.problems[#run.problems + 1] = code .. " " .. name .. ": " .. text end
local function Skip(name, why) run.skips[#run.skips + 1] = name .. " " .. why end
local function Info(text) run.info[#run.info + 1] = text end

-- Runs fn in pcall; a throw becomes one "ERR" line.
local function Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Problem("ERR", label, Short(err)) end
    return ok
end

-- ---------------------------------------------------------------------------
-- Frame geometry (screen pixels, so frames with other scales compare)

local function ScreenRect(o)
    local st, l, b, w, h = Read(o, "GetRect")
    if st == "secret" then return "secret" end
    if st ~= "ok" or l == nil or b == nil or w == nil or h == nil then return nil end
    local s2, es = Read(o, "GetEffectiveScale")
    if s2 == "secret" then return "secret" end
    if s2 ~= "ok" or type(es) ~= "number" then es = 1 end
    return { l = l * es, b = b * es, r = (l + w) * es, t = (b + h) * es, w = w, h = h }
end

local function Overlap(a, b)
    local w = math.min(a.r, b.r) - math.max(a.l, b.l)
    local h = math.min(a.t, b.t) - math.max(a.b, b.b)
    if w <= 0 or h <= 0 then return 0 end
    return w * h
end

-- Frame level of a frame, or of a texture's / font string's frame. nil = can't tell, "secret".
local function Level(o)
    local st, lv = Read(o, "GetFrameLevel")
    if st == "secret" then return "secret" end
    if st == "ok" and type(lv) == "number" then return lv end
    local s2, p = Read(o, "GetParent")
    if s2 == "secret" then return "secret" end
    st, lv = Read(p, "GetFrameLevel")
    if st == "secret" then return "secret" end
    return st == "ok" and type(lv) == "number" and lv or nil
end

local STRATA = { WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function Strata(o)
    local st, s = Read(o, "GetFrameStrata")
    if st == "noapi" then st, s = Read(select(2, Read(o, "GetParent")), "GetFrameStrata") end
    if st == "secret" then return "secret" end
    return st == "ok" and STRATA[s] or nil
end

-- true when a is b or one is inside the other (parent chain); nil = can't tell.
local function Related(a, b)
    for _, pair in ipairs({ { a, b }, { b, a } }) do
        local p, n = pair[1], 0
        while p and n < 25 do
            if p == pair[2] then return true end
            local st, q = Read(p, "GetParent")
            if st ~= "ok" then return nil end
            p, n = q, n + 1
        end
    end
    return false
end

-- nil = the texture's art loads; else a short reason.
local function ArtMissing(tex)
    if type(tex) ~= "table" then return "missing" end
    local st, atlas = Read(tex, "GetAtlas")
    if st == "secret" then return "secret" end
    if st == "ok" and type(atlas) == "string" and atlas ~= "" then
        local get = Co.fn.AtlasInfo
        if type(get) ~= "function" then return nil end
        local ok, info = pcall(get, atlas)
        if not ok or type(info) ~= "table" then return "atlas " .. atlas .. " gone" end
        return nil
    end
    local id
    st, id = Read(tex, "GetTextureFileID")
    if st == "secret" then return "secret" end
    if st ~= "ok" or id == nil then
        st, id = Read(tex, "GetTexture")
        if st == "secret" then return "secret" end
    end
    if id == nil or id == 0 or id == "" then return "no file" end
    return nil
end

-- ---------------------------------------------------------------------------
-- UI parts

-- Our window has no Blizzard template art; parts of a group may not cover each other.
local function Coverers(parts)
    local list = {}
    for _, p in ipairs(parts) do if p.obj then list[#list + 1] = p end end
    return list
end

-- One part = { name, obj, opt = may be missing, shownOnly = only checked while shown, thin = a line,
--   art = { texture keys whose art must load }, artSelf = obj is a texture }.
-- At most one problem line per part: the first check that fails.
local function CheckPart(p, coverers)
    local o = p.obj
    Count()
    if o == nil then
        if p.opt then return end
        return Problem("UI", p.name, "missing")
    end
    local st, shown = Read(o, "IsShown")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st ~= "ok" then return Problem("UI", p.name, "can't read (" .. st .. ")") end
    if not shown then
        if p.shownOnly then return end
        return Problem("UI", p.name, "hidden")
    end
    local vis
    st, vis = Read(o, "IsVisible")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and not vis then
        if p.shownOnly then return end
        return Problem("UI", p.name, "shown but its parent is hidden")
    end

    Count()
    local valid
    st, valid = Read(o, "IsRectValid")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and valid == false then return Problem("UI", p.name, "no position") end
    local rect = ScreenRect(o)
    if rect == "secret" then return Skip(p.name, "(secret)") end
    if rect == nil then return Problem("UI", p.name, "no position") end

    Count()
    if not (rect.w > 1 and rect.h > 1) and not p.thin then
        return Problem("UI", p.name, ("size %dx%d"):format(math.floor(rect.w), math.floor(rect.h)))
    end

    Count()
    local screen = ScreenRect(Co.UIParent())
    if type(screen) == "table" and (rect.l < screen.l - SCREEN_SLACK or rect.b < screen.b - SCREEN_SLACK
        or rect.r > screen.r + SCREEN_SLACK or rect.t > screen.t + SCREEN_SLACK) then
        return Problem("UI", p.name, "off screen")
    end

    Count()
    local alpha
    st, alpha = Read(o, "GetEffectiveAlpha")
    if st == "secret" then return Skip(p.name, "(secret)") end
    if st == "ok" and type(alpha) == "number" and alpha < 0.05 then
        return Problem("UI", p.name, ("invisible (alpha %.2f)"):format(alpha))
    end

    local lv, ss = Level(o), Strata(o)
    if lv == "secret" or ss == "secret" then return Skip(p.name, "(secret)") end

    -- Not under another part that covers a good share of it (p.behind: a background meant to sit behind them).
    if type(lv) == "number" and not p.behind then
        Count()
        for _, c in ipairs(coverers or {}) do
            if c.obj ~= o and Related(o, c.obj) == false and select(2, Read(c.obj, "IsVisible")) == true then
                local clv, cs = Level(c.obj), Strata(c.obj)
                if clv == "secret" or cs == "secret" then
                    Skip(p.name, "cover (secret)")
                elseif type(clv) == "number" and clv > lv and (cs == nil or ss == nil or cs == ss) then
                    local cr = ScreenRect(c.obj)
                    local area = (rect.r - rect.l) * (rect.t - rect.b)
                    if type(cr) == "table" and area > 0 and Overlap(rect, cr) / area >= COVER_SHARE then
                        return Problem("UI", p.name, ("covered by %s (%d>%d)"):format(c.name, clv, lv))
                    end
                end
            end
        end
    end

    -- Its art really loads.
    for _, key in ipairs(p.art or {}) do
        Count()
        local miss = ArtMissing(o[key])
        if miss == "secret" then Skip(p.name .. "." .. key, "(secret)")
        elseif miss then return Problem("TEX", p.name .. "." .. key, miss) end
    end
    if p.artSelf then
        Count()
        local miss = ArtMissing(o)
        if miss == "secret" then Skip(p.name, "art (secret)")
        elseif miss then return Problem("TEX", p.name, miss) end
    end
end

local function CheckGroup(parts)
    local cov = Coverers(parts)
    for _, p in ipairs(parts) do Guard("UI " .. p.name, CheckPart, p, cov) end
end

local function Win() return ns.UI and ns.UI.frame end

-- The guide window's parts (the one window). Every new UI feature adds a line here (and a scenario offline).
function ST.MainParts()
    local UI = ns.UI or {}
    local tb, ft, nl, ch = UI.title or {}, UI.footer or {}, UI.noticeLine or {}, UI.chips or {}
    local small = ns.Settings.Get("small")
    local guide = UI.model and UI.model.state == "guide"
    local full = guide and not small
    return {
        { name = "window", obj = UI.frame },
        { name = "title", obj = UI.title },
        { name = "title.logo", obj = tb.logo, artSelf = true },
        { name = "title.menu", obj = tb.menu, art = { "icon" } },
        { name = "title.small", obj = tb.small, art = { "icon" } },
        { name = "title.lock", obj = tb.lock, art = { "icon" } },
        { name = "title.close", obj = tb.close, art = { "icon" } },
        -- beta.14: the step's distance at the title's right (hidden without a spot or on a narrow title)
        { name = "title.dist", obj = tb.dist, opt = true, shownOnly = true },
        -- the rounded corners (our own art; a flat panel stands in without it)
        { name = "panel.round", obj = UI.frame and UI.frame.round and UI.frame.round.panel and UI.frame.round.panel.pieces.c, opt = true, shownOnly = true, behind = true },
        { name = "area", obj = UI.area },
        { name = "row1", obj = UI.rows and UI.rows[1], opt = not guide, shownOnly = not guide },
        { name = "row1.tile", obj = UI.rows and UI.rows[1] and UI.rows[1].badge.disc, opt = true, shownOnly = true, artSelf = true },
        { name = "divider", obj = UI.divider, opt = true, shownOnly = true, thin = true },
        { name = "state", obj = UI.stateText, shownOnly = true },
        { name = "state.icon", obj = UI.stateIcon, shownOnly = true, artSelf = true },
        -- v0.2.5 end card / missing pack card: the dim line and the button (Play next / Turn on)
        { name = "end.line", obj = UI.endLine, opt = true, shownOnly = true },
        { name = "end.button", obj = UI.endButton, opt = true, shownOnly = true },
        -- v0.2.5 waits countdown line (on the current step when it waits)
        { name = "wait.line", obj = UI.rows and UI.rows[1] and UI.rows[1].waitLine and UI.rows[1].waitLine.text, opt = true, shownOnly = true },
        { name = "notice", obj = UI.noticeLine, shownOnly = true },
        { name = "notice.icon", obj = nl.icon, opt = true, shownOnly = true, artSelf = true },
        -- the info chips (route / level / time left; a chip that doesn't fit hides)
        { name = "chips", obj = UI.chips, opt = not full, shownOnly = not full },
        { name = "chip.range", obj = ch.range, opt = true, shownOnly = true },
        { name = "chip.level", obj = ch.level, opt = true, shownOnly = true },
        { name = "chip.time", obj = ch.time, opt = true, shownOnly = true },
        -- back / progress bar / next
        { name = "footer", obj = UI.footer, shownOnly = small },
        { name = "footer.back", obj = ft.prev, opt = not guide, shownOnly = small or not guide, art = { "icon" } },
        { name = "footer.next", obj = ft.next, opt = not guide, shownOnly = small or not guide, art = { "icon" } },
        { name = "footer.bar", obj = ft.bar, shownOnly = small },
        { name = "footer.text", obj = ft.text, opt = not guide, shownOnly = small or not guide },
        -- v0.2 M3: the width grip (hidden while locked)
        { name = "grip", obj = UI.grip, opt = true, shownOnly = true },
        -- beta.4: the height grip (bottom edge) and the size corner (hidden while locked and in small mode)
        { name = "grip.height", obj = UI.gripH, opt = true, shownOnly = true },
        { name = "grip.corner", obj = UI.gripC, opt = true, shownOnly = true, art = { "icon" } },
    }
end

-- The row of buttons above the window's top-left: the target button (when the current step names a mob and the
-- client is English). The item button has its own check (UI\StepButton.lua self-check).
function ST.ButtonParts()
    local TB = ns.TargetButton or {}
    local want = TB.Wanted and TB.Wanted() or false
    local o = not want
    return {
        { name = "target", obj = TB.frame, opt = o, shownOnly = o },
        { name = "target.icon", obj = TB.frame and TB.frame.icon, opt = o, shownOnly = o, artSelf = true },
    }
end
ST.NowParts = ST.ButtonParts

-- The main window (full run: opened on Guides for a moment, without remembering the page): frame, title bar,
-- nav, heading, version, the Guides page's search box, chips and first card with its shield.
function ST.HubParts()
    local Hub, HG = ns.Hub or {}, ns.HubGuides or {}
    local f = Hub.frame or {}
    local tb = f.titleBar or {}
    local s = HG.search or {}
    local chips = HG.chips or {}
    local card = HG.cards and HG.cards[1]
    local hasCard = (HG.shown or 0) > 0
    return {
        { name = "main.window", obj = Hub.frame },
        { name = "main.title", obj = f.titleBar },
        { name = "main.close", obj = tb.close, art = { "icon" } },
        { name = "main.nav", obj = f.nav },
        { name = "main.nav1", obj = Hub.navButtons and Hub.navButtons[1], art = { "icon" } },
        { name = "main.heading", obj = f.heading },
        { name = "main.version", obj = f.version },
        { name = "guides.search", obj = HG.search },
        { name = "guides.search.icon", obj = s.icon, artSelf = true },
        { name = "guides.chip.all", obj = chips.all },
        { name = "guides.chip.soon", obj = chips.soon, opt = not HG.soonShown, shownOnly = not HG.soonShown },
        { name = "guides.card1", obj = card, opt = not hasCard, shownOnly = not hasCard },
        { name = "guides.card1.emblem", obj = card and card.emblem, opt = not hasCard, shownOnly = not hasCard, artSelf = true },
    }
end

-- NPC talk helper: the line under the accept window and a gossip row's tag (only while an NPC window shows
-- them; the "npchelper" self-check covers parent, mouse and dimming the rest of the time).
function ST.NpcParts()
    local NT = ns.NpcHelper or {}
    local tag
    for _, t in pairs(NT.tags or {}) do
        if t:IsShown() then tag = t break end
    end
    return {
        { name = "npc.line", obj = NT.line, opt = true, shownOnly = true },
        { name = "npc.line.text", obj = NT.line and NT.line.text, opt = true, shownOnly = true },
        { name = "npc.tag", obj = tag, opt = true, shownOnly = true },
    }
end

-- The 3D viewer (v0.3, UI\ModelView.lua): its box must show whenever nothing hides it; the model or the
-- "No 3D view" card inside it (one of them at a time). Docking and load result: the "model" self-check.
function ST.ModelParts()
    local MV = ns.ModelView or {}
    local f = MV.frame
    local need = f ~= nil and MV.Why and MV.Why() == nil or false
    local card = f and f.card
    return {
        { name = "model", obj = f, opt = not need, shownOnly = not need },
        { name = "model.view", obj = f and f.model, opt = true, shownOnly = true },
        { name = "model.card", obj = card, opt = true, shownOnly = true },
        { name = "model.card.badge", obj = card and card.badge and card.badge.disc, opt = true, shownOnly = true, artSelf = true },
        { name = "model.card.text", obj = card and card.text, opt = true, shownOnly = true },
        -- beta.13 the big step picture (a step without a unit): the item's icon or the kind tile
        { name = "model.picture", obj = f and f.pic, opt = true, shownOnly = true },
        { name = "model.picture.icon", obj = f and f.pic and f.pic.icon, opt = true, shownOnly = true, artSelf = true },
        { name = "model.picture.tile", obj = f and f.pic and f.pic.tile.base, opt = true, shownOnly = true, artSelf = true },
        -- 2026-11-27 the crisp kind picture: plate (9-slice) + the kind's glyph at its own size
        { name = "model.picture.plate", obj = f and f.pic and f.pic.plateFrame, opt = true, shownOnly = true },
        { name = "model.picture.glyph", obj = f and f.pic and f.pic.glyph, opt = true, shownOnly = true, artSelf = true },
        -- v0.2.8 the game's own quest marker (atlas by name) on accept / turn-in steps
        { name = "model.picture.marker", obj = f and f.pic and f.pic.marker, opt = true, shownOnly = true },
    }
end

-- The arrow is its own frame (only up while a step has a spot): checked on its own.
function ST.ArrowParts()
    local A = ns.Arrow or {}
    return {
        { name = "arrow", obj = A.frame, opt = true, shownOnly = true },
        { name = "arrow.tex", obj = A.tex, opt = true, shownOnly = true, artSelf = true },
        { name = "arrow.ring", obj = A.arrived, opt = true, shownOnly = true, artSelf = true },
        -- smart arrow: the way line and the goal line (only while it leads to a door / gate first)
        { name = "arrow.via", obj = A.viaText, opt = true, shownOnly = true },
        { name = "arrow.goal", obj = A.goalLine, opt = true, shownOnly = true },
    }
end

-- ---------------------------------------------------------------------------
-- Saved data (on copies only: the real SavedVariables are never written)

local function DeepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local c = {}
    seen[v] = c
    for k, x in pairs(v) do c[DeepCopy(k, seen)] = DeepCopy(x, seen) end
    return c
end

local function CheckSaved()
    local prep = ns.DB.PrepareCopy
    for _, kind in ipairs({ "account", "char" }) do
        Count()
        local ok, t = pcall(prep, DeepCopy(ns.DB[kind] or {}), kind)
        if not ok then Problem("DB", kind, Short(t))
        elseif type(t.modules) ~= "table" or type(t.settings) ~= "table" then Problem("DB", kind, "repair left no settings / modules") end
    end
    -- broken data and a save from a newer version: repaired or opened, never an error
    local broken = {
        { "char", { dbVersion = "x", guides = 3, settings = 5, active = "y" } },
        { "account", { dbVersion = 99, settings = {}, modules = {} } },
        { "account", 7 },
    }
    for i, b in ipairs(broken) do
        Count()
        local ok, err = pcall(prep, b[2], b[1])
        if not ok then Problem("DB", "broken" .. i, Short(err)) end
    end
end

-- ---------------------------------------------------------------------------
-- Checks that need no window

-- Every API from ApiList: missing (with a feature = that feature is off), not secure (another addon
-- replaced it), secret. Nothing is called.
local function CheckApi()
    local missing, later, tainted = {}, 0, {}
    local secure = Co.fn.issecurevariable
    for _, e in ipairs(ns.ApiList) do
        Count()
        local v = Co.Resolve(e.path)
        if IsSecret(v) then
            Skip("api " .. e.id, "(secret)")
        elseif not Co.KindOk(v, e.kind) then
            if e.later then later = later + 1
            elseif e.feature then missing[#missing + 1] = e.id
            else Info("api " .. e.id .. " missing") end
        elseif type(secure) == "function" and not e.path:find(".", 1, true) then
            local ok, isSecure = pcall(secure, e.path)
            if ok and isSecure == false then tainted[#tainted + 1] = e.id end
        end
    end
    for _, id in ipairs(missing) do Problem("API", id, "missing (its feature is off)") end
    if #tainted > 0 then Info("api not secure: " .. table.concat(tainted, ",")) end
    if later > 0 then Info("api for later missing: " .. later) end
    if type(secure) ~= "function" then Skip("api", "secure check (no issecurevariable)") end
    local _, off = ns.Feature.Summary()
    if #off > 0 then Info("off: " .. table.concat(off, ",")) end
end

-- Every key the current theme sets resolves (colours parse, slots reach a media slot, fonts and sizes).
local function CheckTheme()
    local Th, Md = ns.Theme, ns.Media
    for _, key in ipairs(Th.Keys()) do
        Count()
        local kind, rest = key:match("^(%a+)%.(.+)$")
        local bad
        if kind == "color" then
            local v = Th.Raw(key)
            if type(v) == "string" and v:sub(1, 1) == "=" then
                if Th.Raw("color." .. v:sub(2)) == nil then bad = "points at nothing" end
            else
                local hex = type(v) == "table" and v[1] or v
                if type(hex) ~= "string" or not hex:match("^#?%x%x%x%x%x%x$") then bad = "colour doesn't parse" end
            end
        elseif kind == "slot" then
            if Md.Get(Th.Raw(key)) == nil then bad = "no media slot" end
        elseif kind == "font" then
            local s = Th.FontSize(rest)
            -- the text font's scale gives tenths (Open Sans x0.9): only the floor is checked
            if s < Th.MIN_FONT or math.abs(s * 10 - math.floor(s * 10 + 0.5)) > 1e-6 then bad = "font size " .. tostring(s) end
        elseif kind == "size" then
            if type(Th.Raw(key)) ~= "number" then bad = "not a number" end
        elseif kind == "alpha" then
            local v = Th.Raw(key)
            if type(v) ~= "number" or v < 0 or v > 1 then bad = "not an alpha 0..1" end
        elseif kind == "file" then
            local v = Th.Raw(key)
            if type(v) ~= "string" or not v:find("^Interface\\") then bad = "not a game file path" end
        end
        if bad then Problem("THEME", key, bad) end
    end
end

-- The language table: every English key is there, with the same {fields}.
local function Fields(s)
    local t = {}
    for f in tostring(s):gmatch("{(%w+)}") do t[#t + 1] = f end
    table.sort(t)
    return table.concat(t, ",")
end
local function CheckLocale()
    local Lo = ns.Locale
    Count()
    if not Lo.en then return Problem("LOC", "enUS", "missing") end
    local cur = Lo.current or Lo.en
    if cur == Lo.en then return end
    local missing, fields = 0, {}
    for k, v in pairs(Lo.en) do
        local d = cur[k]
        if d == nil then missing = missing + 1
        elseif type(v) == "string" and Fields(v) ~= Fields(d) then fields[#fields + 1] = k end
    end
    Count()
    if missing > 0 then Problem("LOC", Lo.code, missing .. " text(s) missing (English shown)") end
    Count()
    if #fields > 0 then
        table.sort(fields)
        Problem("LOC", Lo.code, "fields differ: " .. table.concat(fields, ",", 1, math.min(#fields, 4)))
    end
end

-- Rough save size in bytes (keys, values, punctuation), like the SavedVariables file.
local function Size(v, seen)
    local t = type(v)
    if t == "string" then return #v + 2 end
    if t == "number" or t == "boolean" then return #tostring(v) end
    if t ~= "table" then return 3 end
    seen = seen or {}
    if seen[v] then return 0 end
    seen[v] = true
    local n = 2
    for k, x in pairs(v) do n = n + Size(k, seen) + Size(x, seen) + 6 end
    return n
end
ST.Size = Size

-- Budgets: memory, login time, load-on-demand modules at login, OnUpdate while hidden, save sizes.
local function CheckPerf()
    Count()
    local kb = Co.MemoryKB(ADDON_NAME)
    if kb then
        Info(("mem %d KB"):format(math.floor(kb + 0.5)))
        if kb > BUDGET.memKB * SLACK then Problem("PERF", "memory", ("%d KB"):format(math.floor(kb))) end
    else
        Skip("memory", "(no API)")
    end
    Count()
    local ms = ns.Perf.loginMs
    if type(ms) == "number" then
        Info(("login %d ms"):format(math.floor(ms + 0.5)))
        if ms > BUDGET.loginMs * SLACK then Problem("PERF", "login", ("%d ms"):format(math.floor(ms))) end
    end
    Count()
    local lod = ns.Perf.loadedAtLogin or 0
    if lod > 0 then Problem("PERF", "modules", lod .. " loaded at login") end
    -- nothing runs per frame while hidden
    Count()
    local A = ns.Arrow
    if A and A.frame then
        local st, shown = Read(A.frame, "IsShown")
        local s2, script = Read(A.frame, "GetScript", "OnUpdate")
        if st == "ok" and s2 == "ok" and not shown and script ~= nil then Problem("PERF", "arrow", "OnUpdate while hidden") end
    end
    local w = Win()
    if w then
        Count()
        local st, shown = Read(w, "IsShown")
        local s2, script = Read(w, "GetScript", "OnUpdate")
        if st == "ok" and s2 == "ok" and not shown and script ~= nil then Problem("PERF", "window", "OnUpdate while hidden") end
    end
    -- save sizes (the alt index lives in the account save)
    local acc, char = Size(ns.DB.account or {}), Size(ns.DB.char or {})
    -- v0.3 game data recording: its own capped part (Data\Gather.lua, up to ~115 KB) is not counted in the budget
    local mods = ns.DB.account and ns.DB.account.modules
    if type(mods) == "table" and type(mods.gather) == "table" then acc = acc - Size(mods.gather) end
    Info(("saves %.1f/%.1f KB"):format(acc / 1024, char / 1024))
    Count()
    if acc > BUDGET.accKB * 1024 * SLACK then Problem("PERF", "account save", ("%d KB"):format(math.floor(acc / 1024))) end
    Count()
    if char > BUDGET.charKB * 1024 * SLACK then Problem("PERF", "char save", ("%d KB"):format(math.floor(char / 1024))) end
end

-- The arrow turns with SetRotation (else the 8-argument SetTexCoord fallback is used).
local function CheckRotation()
    Count()
    local tex = (ns.Arrow and ns.Arrow.tex) or (ns.UI and ns.UI.title and ns.UI.title.logo)
    if type(tex) ~= "table" then return Skip("SetRotation", "(no texture yet)") end
    if type(tex.SetRotation) ~= "function" then Problem("API", "Texture:SetRotation", "missing (texcoord fallback used)") end
end

-- The font draws æøå: a string of them must be about as wide as "aoa" (a font without them draws
-- nothing, or much narrower boxes). A hidden probe string of our own; the text is cleared after.
local function CheckLetters()
    local w = Win()
    if not w then return Skip("letters", "(no window)") end
    if not ST.probe then
        ST.probe = w:CreateFontString(nil, "OVERLAY")
        ST.probe:Hide()
    end
    local fs = ST.probe
    ns.Theme.Font(fs, "step")   -- every run: the text font setting may have changed since the last one
    Count()
    fs:SetText("æøåæøåÆØÅ")
    local s1, w1 = Read(fs, "GetStringWidth")
    fs:SetText("aoaaoaAOA")
    local s2, w2 = Read(fs, "GetStringWidth")
    fs:SetText("")
    if s1 == "secret" or s2 == "secret" then return Skip("letters", "(secret)") end
    if s1 ~= "ok" or s2 ~= "ok" or type(w1) ~= "number" or type(w2) ~= "number" or w2 <= 0 then
        return Skip("letters", "(can't measure)")
    end
    Info(("aeoa width %d/%d"):format(math.floor(w1 + 0.5), math.floor(w2 + 0.5)))
    if w1 < w2 * 0.6 then Problem("FONT", "æøå", ("too narrow (%d vs %d)"):format(math.floor(w1), math.floor(w2))) end
end

-- ---------------------------------------------------------------------------
-- Steps (each runs some frames later, so the UI has laid out; combat stops the run)

local Finish

local function Later(frames, fn)
    local function Tick()
        if not run then return end
        frames = frames - 1
        if frames > 0 then return Co.After(0, Tick) end
        if InCombat() then
            run.stopped = true
            return Finish()
        end
        local ok, err = pcall(fn)
        if not ok then
            Problem("ERR", "step", Short(err))
            Finish()
        end
    end
    Co.After(0, Tick)
end

local function StepHub()
    CheckGroup(ST.HubParts())
    Info("main window parts checked")
    Finish()
end

local function StepFull2()
    CheckGroup({ { name = "menu", obj = ns.Menu.frame }, { name = "menu.item1", obj = ns.Menu.buttons[1] } })
    if run.state.notice then
        CheckGroup({ { name = "notice", obj = ns.UI.noticeLine }, { name = "notice.icon", obj = ns.UI.noticeLine.icon, artSelf = true } })
    end
    -- the main window on Guides (only when it wasn't open: an open one is the player's, left as it is)
    local Hub = ns.Hub
    if Hub and Hub.Available() then
        ns.Menu.Close()
        run.state.menu = nil
        if Hub.IsShown() then
            if Hub.current == "guides" then return Later(2, StepHub) end
            return Finish()
        end
        Hub.Open("guides", true)
        run.state.hub = true
        return Later(2, StepHub)
    end
    Finish()
end

local function StepMain()
    if run.ui then
        CheckGroup(ST.MainParts())
        CheckGroup(ST.ButtonParts())
        CheckGroup(ST.ArrowParts())
        CheckGroup(ST.NpcParts())
        CheckGroup(ST.ModelParts())
        Guard("letters", CheckLetters)
    end
    if run.mode == "full" and run.ui then
        -- the title menu, and a notice line when none is up
        local UI = ns.UI
        ns.Menu.Open(UI.title.menu, UI.MenuItems(), { right = true })
        run.state.menu = true
        if not ns.Notice.Top() then
            ns.Notice.Push({ id = "selftest", kind = "danger", text = "Self-test", priority = 1 })
            run.state.notice = true
        end
        return Later(2, StepFull2)
    end
    Finish()
end

-- ---------------------------------------------------------------------------
-- Restore and output

local function Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and run then Problem("ERR", "restore " .. label, Short(err)) end
end

-- Puts back everything the run opened (only what it opened), whatever happened.
local function Restore()
    local s = run.state
    if s.menu then Try("menu", ns.Menu.Close) end
    if s.notice then Try("notice", ns.Notice.Remove, "selftest") end
    if s.hub then Try("main window", ns.Hub.Close) end
    if s.openedWindow then Try("window", ns.UI.Hide, true) end
end

-- The short line kept for /aog status and the error copy text.
function ST.Line(r)
    local line = ("AOG selftest: %d ok, %d fail"):format(math.max(0, r.checks - #r.problems), #r.problems)
    if r.stopped then line = line .. " (stopped: combat)" end
    if #r.problems > 0 then
        line = line .. " (" .. table.concat(r.problems, "; ", 1, math.min(#r.problems, 3)) .. ")"
    end
    if #line > LINE_MAX then line = line:sub(1, LINE_MAX - 3) .. "..." end
    return line
end

-- The report: header, one line per problem, skips, info. No names, realms, guilds or links.
function ST.Text(r)
    r = r or run
    local head = ("AOG selftest %s | %s | %s | %d ok, %d fail"):format(tostring(ns.version), Co.ClientLine(),
        r.mode, math.max(0, r.checks - #r.problems), #r.problems)
    if r.stopped then head = head .. " | stopped: combat" end
    local parts = { head }
    for _, p in ipairs(r.problems) do parts[#parts + 1] = p end
    if #r.skips > 0 then
        parts[#parts + 1] = ("skipped %d: %s"):format(#r.skips, table.concat(r.skips, ", ", 1, math.min(#r.skips, MAX_LIST)))
    end
    for _, i in ipairs(r.info) do parts[#parts + 1] = i end
    local text = table.concat(parts, " | ")
    if #text > COPY_MAX then text = text:sub(1, COPY_MAX - 3) .. "..." end
    return text
end

Finish = function()
    if not run then return end
    local ok, err = pcall(Restore)
    if not ok then Problem("ERR", "restore", Short(err)) end
    local r = run
    run = nil
    ST.last = r
    if not r.stopped then
        local _, build = Co.Build()
        ns.DB.SetSelfTest(ns.version, build, ST.Line(r))
    end
    if r.mode == "auto" then
        if #r.problems > 0 then
            ns.Print(("self-test found %d problem(s). Type /aog selftest for the report."):format(#r.problems))
        end
        return
    end
    if r.stopped then
        ns.Print("self-test stopped (combat). Nothing was changed.")
    elseif #r.problems == 0 then
        ns.Print(("self-test OK (%d checks)."):format(r.checks))
    else
        ns.Print(("self-test found %d problem(s) in %d checks. Copy the text and send it."):format(#r.problems, r.checks))
    end
    pcall(ns.Popups.Copy, "All-in-One Guide self-test", ST.Text(r))
end

-- ---------------------------------------------------------------------------
-- Start

local function AfterCombat(mode)
    ns.Events.On("PLAYER_REGEN_ENABLED", ST, function()
        ns.Events.Off("PLAYER_REGEN_ENABLED", ST)
        ST:Start(mode)
    end, "selftest")
end

function ST.NewRun(mode)
    return { mode = mode or "quick", checks = 0, problems = {}, skips = {}, info = {}, state = {} }
end

function ST.Running() return run ~= nil end

-- mode: "quick" (the window), "full" (also the menu and the notice line) or "auto" (by itself:
-- never opens the window, no box).
function ST:Start(mode)
    if run then
        if mode ~= "auto" then ns.Print("self-test is already running.") end
        return
    end
    if InCombat() then
        if mode ~= "auto" then ns.Print("self-test waits until combat ends.") end
        return AfterCombat(mode)
    end
    run = ST.NewRun(mode)
    Guard("db", CheckSaved)
    Guard("api", CheckApi)
    Guard("theme", CheckTheme)
    Guard("locale", CheckLocale)
    Guard("perf", CheckPerf)
    Guard("rotation", CheckRotation)
    -- checks added by later modules (API, Gear Set link, atlases ...)
    local h = { Count = Count, Problem = Problem, Skip = Skip, Info = Info }
    for _, c in ipairs(ns.SelfChecks) do Guard(c.label, c.fn, h) end
    if ns.safeMode then
        Skip("ui", "(safe mode)")
        return Finish()
    end
    local ok, err = pcall(function()
        local UI = ns.UI
        if UI.IsShown() then
            run.ui = true
        elseif mode ~= "auto" then
            run.state.openedWindow = true
            run.ui = true
            UI.Show(true)
        else
            Skip("ui", "(window closed)")
        end
    end)
    if not ok then
        Problem("ERR", "window", Short(err))
        return Finish()
    end
    Later(2, StepMain)
end

-- Once per new addon version / client build, a little after login, out of combat.
function ST.Auto()
    if ns.safeMode or ns.Test.quietFirstRun then return end
    local s = ns.DB.account and ns.DB.account.selftest
    local _, build = Co.Build()
    if type(s) == "table" and s.version == ns.version and s.build == build then return end
    ST:Start("auto")
end
ns.Bus.On("Login", ST, function()
    Co.After(ST.RUN_DELAY, function() ns.Errors.Call("selftest", ST.Auto) end)
end, "selftest", 90)

ns.Slash.Add("selftest", function(arg)
    ST:Start(tostring(arg or ""):lower() == "full" and "full" or "quick")
end, "HELP_SELFTEST", { main = true })

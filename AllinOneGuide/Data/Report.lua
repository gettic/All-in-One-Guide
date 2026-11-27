-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M5: "Report a mistake", report string v2 (FR-25). One line the player copies and pastes into a
-- GitHub issue; nothing is ever sent by the addon. Built through ns.Serializer kind R2 (allowlist, strict
-- %XX escaping of anything outside a plain set, so non-ASCII, line breaks, "=", ";" and "|" survive),
-- then ";ck=<Adler-32 of everything before it>" (Packs\Format.lua Fm.Adler32, the decoder uses the same).
--   AOGR2 rid=k3x9qa;v=0.2.0;c=16001 1.60.1.70959 forever enUS;...;note=...;ck=1a2b3c4d
-- Never a name: debug lines are stripped when written (Errors.Debug) and every value again here
-- (U.StripNames); the GUID is never kept (only the NPC id part, and only when the player ticks "add my
-- target"). "Remove my location" drops map / x / y / distance, facing and the arrow's spot / yards / bearing.
-- Better reports (2026-11-27): also step state, quest progress, the quest log, the arrow, realm, spec (R2 list in
-- DB\Serializer.lua). Cap 1,500 characters: dropped in the order R.DROP (engine lines > quest log ids > last
-- steps > ...), then the note is shortened. Never the realm (the report worker drops it). The last 20 strings are kept
-- (account module `reports`, size cap) so the player can copy one again.
--   ns.Report.Build(opts) -> string, fields     opts = { about, stepId, note, noloc, evidence }
--   ns.Report.Steps() (current + last 3), .TYPES, .Keep(s), .Saved(), .Title(fields), .Checksum(s), .Verify(s)
--   ns.Report.Queue(s) -> how, dropped / .Outbox() / .Push(list, s, protect) / .WireOk(s) / .queued / .dropped:
--   "Send" (the Addon Manager sends it; outbox cap R.OUTBOX, never drops this session's reports)
local _, ns = ...
local Co, U = ns.Compat, ns.U
local R = { recent = {}, MAX_LEN = 1500, NOTE_MAX = 200, KEEP = 20, KEEP_BYTES = 24000 }
ns.Report = R

-- report types (Hub page buttons, the issue form's drop-down and the labels in .github\labels.md)
R.TYPES = { "coords", "order", "missing", "notick", "text", "danger", "other" }

function R.Checksum(s) return ns.Format.Adler32(s) end

-- true when the string's checksum matches (the decoder does the same).
function R.Verify(s)
    local body, ck = tostring(s):match("^(.*);ck=(%x%x%x%x%x%x%x%x)$")
    return body ~= nil and R.Checksum(body) == ck
end

local function RandomId()
    local chars, out = "abcdefghijklmnopqrstuvwxyz0123456789", {}
    for i = 1, 6 do
        local n = math.random(1, #chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end

-- A new report id (the Report page takes one when it opens, so the preview keeps it while typing).
function R.NewId()
    R.rid = RandomId()
    return R.rid
end

-- ------------------------------------------------------------------ the last steps and how each ended
local function How(g, step)
    if not (g and step) then return "moved" end
    local why = g:SkipReason(step)
    if why then return why end
    if g:Done(step) then return "done" end
    return "moved"
end

local function OnStep(_, g)
    if not g or g ~= ns.Engine.Focused() then return end
    -- another guide: its steps start a new list
    if R.lastKey ~= g.key then R.recent, R.lastId, R.lastStep, R.lastKey = {}, nil, nil, g.key end
    local cur = g:Top():Current()
    local id = cur and cur.id
    if id == R.lastId then return end
    R.since = Co.Now()   -- seconds on this step (`ts`); only a clock stamp, read when the report is built
    if R.lastId and R.lastStep then
        table.insert(R.recent, 1, { id = R.lastId, how = How(g:Top(), R.lastStep) })
        while #R.recent > 3 do table.remove(R.recent) end
    end
    R.lastId, R.lastStep = id, cur
end
ns.Bus.On("StepChanged", R, function(...) ns.Errors.Call("report", OnStep, ...) end, "report", 95)

-- The steps a report can be about: the current one, then the last 3 (newest first).
function R.Steps()
    local out = {}
    local cur = ns.Engine.Current()
    if cur then out[1] = { id = cur.id, current = true, step = cur } end
    for _, r in ipairs(R.recent) do
        if #out >= 4 then break end
        if not cur or r.id ~= cur.id then out[#out + 1] = { id = r.id, how = r.how } end
    end
    return out
end

-- ------------------------------------------------------------------ building
-- colour start (|cAARRGGBB) and end (|r) codes: dropped from the note, everything else is kept
local COLOUR_CODES = { "|c" .. ("%x"):rep(8), "|r" }

local function Pct(v) if type(v) ~= "number" then return nil end return ("%.1f"):format(v * 100) end

local function StepById(g, id)
    if not (g and id) then return nil end
    local top = g:Top()
    local i = top:IndexOf(id)
    if i then return top:Step(i), top end
    return nil
end

-- ------------------------------------------------------------------ more facts (better reports, 2026-11-27)
-- Read once, when the report is built (tos B1). Every game read goes through Compat with its secret check (B7);
-- each group runs on its own (pcall), so one bad read only leaves its fields out.
local function Deg(rad)
    local v = Co.Num(rad)
    if not v then return nil end
    return math.floor(math.deg(v) % 360 + 0.5) % 360
end

local function Word(s, max) return (tostring(s or ""):gsub("[^%w_%-]", ""):sub(1, max or 16)) end

-- now / done / skip / notdoing / na / notoffered / future / level<n> / wait / open, "+pin" when pinned
-- (steps compared by id: a route step's table may be made again on each read)
local function IsCur(step, cur) return cur ~= nil and step.id == cur.id end

local function StepState(top, step, cur)
    local s = top:SkipReason(step)
    if not s then
        if top:Done(step) then s = "done"
        elseif top:IsFuture(step) then s = "future"
        else
            local lv = top:UnderLevel(step)
            if lv then s = "level" .. lv
            elseif IsCur(step, cur) then
                local raw = top:Step(top.pos)
                s = (raw and raw.id ~= step.id) and "wait" or "now"
            else
                s = "open"
            end
        end
    end
    if IsCur(step, cur) and top.pinned then s = s .. "+pin" end
    return s
end

local function StepFacts(f, g, top, step, cur)
    f.ss = StepState(top, step, cur)
    f.ty = step.type
    local i = top:IndexOf(step.id)
    if i then f.pos = i .. "/" .. top:Count() end
    if top ~= g then
        local depth, x = 0, g
        while x.child do depth, x = depth + 1, x.child end
        f.dt = Word(top.save and top.save.kind or "detour") .. ":" .. depth
    end
    if IsCur(step, cur) then
        local ids = {}
        for _, b in ipairs(top:Background()) do
            if #ids >= 3 then break end
            if b.id then ids[#ids + 1] = b.id end
        end
        if #ids > 0 then f.bg = table.concat(ids, ",") end
        local t0, now = R.since, Co.Now()
        if type(t0) == "number" and type(now) == "number" and now >= t0 then
            f.ts = math.min(99990, math.floor((now - t0) / 10 + 0.5) * 10)
        end
    end
    local items = {}
    for _, id in ipairs({ step.item, step.useItem }) do
        if type(id) == "number" and #items < 3 then items[#items + 1] = id .. ":" .. Co.ItemCount(id) end
    end
    if #items > 0 then f.it = table.concat(items, ",") end
end

local function QuestFacts(f, top, step)
    local GS = ns.GameState
    local q = step and top and step.quest
    if q then
        local e = GS.Quest(q)
        if e then
            if e.failed == true then f.qs = "failed" elseif e.complete == true then f.qs = "ready" end
            local o = {}
            for i = 1, math.min(#e.have, 8) do o[i] = (e.have[i] or 0) .. "/" .. (e.need[i] or 0) end
            if #o > 0 then f.qo = table.concat(o, ",") end
        end
        local pre = {}
        for _, p in ipairs(top:PreMap()[q] or {}) do
            if #pre >= 6 then break end
            if type(p) == "number" then
                pre[#pre + 1] = p .. (GS.IsDone(p) and "d" or (GS.InLog(p) and "l" or "n"))
            end
        end
        if #pre > 0 then f.pre = table.concat(pre, ",") end
    end
    local max = GS.LogMax()
    f.ql = GS.LogCount() .. "/" .. (type(max) == "number" and max or "?")
    local ids = {}
    for id in pairs(GS.quests) do if type(id) == "number" then ids[#ids + 1] = id end end
    table.sort(ids)
    for i, id in ipairs(ids) do
        local e = GS.quests[id]
        ids[i] = id .. ((e.failed == true and "f") or (e.complete == true and "c") or "")
    end
    if #ids > 0 then f.qi = table.concat(ids, ",") end
end

local SOURCE = { step = "step", show = "show", external = "ext", corpse = "corpse" }

local function ArrowFacts(f, noloc, cur)
    local A = ns.Arrow
    if not A then return end
    local t = A.target
    if not t then
        f.ah = "none"
        return
    end
    local src = SOURCE[A.source] or "step"
    local aw = src
    if src == "step" then
        local id = t.id or (cur and cur.id)
        if id then aw = aw .. ":" .. tostring(id) end
    end
    -- the target's own spot when it isn't the step's own point (a spot of the step, a /way or another addon's
    -- point; never its title). Compared by value, so the same target always gives the same line.
    -- "<src>:<map>,<x>,<y>" (the form the report worker rounds to whole percent on the public issue); a spot of
    -- the step reads "spot:<map>,<x>,<y>" (the step itself is `sid`)
    local own = src == "step" and cur and t.map == cur.map and t.x == cur.x and t.y == cur.y
    local px, py = Pct(t.x), Pct(t.y)
    if not own and src == "step" then aw = "spot" end
    if not noloc and not own and type(t.map) == "number" and px and py then
        aw = (src == "step" and "spot" or src) .. ":" .. t.map .. "," .. px .. "," .. py
    end
    f.aw = aw
    local why = A.HiddenWhy()
    if why then f.ah = why end
    if noloc then return end
    local v = A.via
    if type(v) == "table" then
        local kind = v.spot and "spot" or (v.hunt and "hunt") or Word(v.kind or "via", 10)
        f.av = kind .. ":" .. tostring(Co.Num(v.index) or "?")
    end
    local y = Co.Num(A.yards)
    if y then f.ay = math.floor(y + 0.5) end
    f.br = Deg(A.bearing)
end

local function PlayerFacts(f, opts)
    local GS = ns.GameState
    local ps = {}
    if GS.ghost then ps[#ps + 1] = "ghost" elseif GS.dead or Co.Dead() then ps[#ps + 1] = "dead" end
    if GS.instance or Co.InInstance() then ps[#ps + 1] = "inst" end
    if GS.taxi or Co.OnTaxi() then ps[#ps + 1] = "taxi" end
    if Co.InCombat() then ps[#ps + 1] = "fight" end
    if not GS.ready then ps[#ps + 1] = "notready" end
    if #ps > 0 then f.ps = table.concat(ps, ",") end
    f.sp = Co.Spec()   -- left out when GetSpecialization is missing or gives nothing (tos)
    local S = ns.Settings
    if S and S.Get then
        f.set = "sa" .. (S.Get("smartArrow") and 1 or 0) .. ",hm" .. Word(S.Get("huntMode"), 8)
    end
    if not opts.noloc then f.fc = Deg(Co.Facing()) end
end

-- each group on its own: one that fails leaves only its fields out (the report is always made)
local function Safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and ns.Errors.Debug then ns.Errors.Debug("report facts: %s", tostring(err)) end
end

local function Fields(opts)
    local f = {}
    local g = ns.Engine.Focused()
    local cur = ns.Engine.Current()
    local step, top = cur, g and g:Top()
    if opts.stepId and g then
        local s, t = StepById(g, opts.stepId)
        if s then step, top = s, t end
    end
    f.rid = R.rid or RandomId()
    f.v = ns.version
    f.c = Co.ClientLine()
    f.st = ns.DB.SelfTestLine() or "not run"
    f.lang = ns.Locale.code
    f.ab = opts.about or "other"
    if g then
        local h = g.header or {}
        f.pk = g.key:match("^([^/]+)")
        f.rt = g.key:match("/(.+)$")
        f.pv = h.version
        f.fv = h.formatVersion or 1
    end
    if step then
        f.sid = step.id
        f.sh = ns.Format.StepHash(step)
        f.inc = step.inc
        f.ki = step.knownIssue
        if step.quest then
            local GS = ns.GameState
            f.qs = GS.IsDone(step.quest) and "done" or (GS.InLog(step.quest) and "log" or "none")
        end
        if step.cond and top then f.cnd = top:Applicable(step) and "yes" or "no" end
        f.r = step.r
        if top then Safe(StepFacts, f, g, top, step, cur) end
    end
    Safe(QuestFacts, f, top, step)
    Safe(ArrowFacts, f, opts.noloc, cur)
    Safe(PlayerFacts, f, opts)
    local p = Co.Player()
    f.lv = p.level
    local GS = ns.GameState
    if GS.xp and GS.xpMax and GS.xpMax > 0 then f.xp = math.floor(GS.xp / GS.xpMax * 100 + 0.5) end
    f.fa = p.faction and p.faction:sub(1, 1)
    f.ra, f.cl = p.race, p.class
    local hc = Co.Hardcore()
    if hc ~= nil then f.hc = hc end
    if opts.noloc then
        f.noloc = true
    else
        local map, x, y = ns.Geo.Player()
        if map then f.map, f.x, f.y = map, Pct(x), Pct(y) end
        if step and step.map and step.x and step.y then
            local d = ns.Geo.PlayerDistance(step.map, step.x, step.y)
            if d then f.d = math.floor(d + 0.5) end
        end
    end
    if opts.evidence then
        local id, kind = Co.UnitNpcId("target")
        f.npc = id
        -- dead only next to an NPC id (tos B2); objects never count as dead
        if id and kind == "npc" and Co.UnitDead("target") then f.nd = 1 end
    end
    local cf = ns.Conflicts and ns.Conflicts.Scan() or {}
    if #cf > 0 then f.cf = table.concat(cf, ",") end
    local l3 = {}
    for i = 1, math.min(3, #R.recent) do l3[#l3 + 1] = R.recent[i].id .. ":" .. R.recent[i].how end
    if #l3 > 0 then f.l3 = table.concat(l3, ",") end
    local eng = ns.Errors.DebugLines(10)
    if #eng > 0 then f.eng = table.concat(eng, " / ") end
    -- the note keeps its line breaks and separators (escaped as %XX); only colour codes go
    local note = tostring(opts.note or "")
    for _, code in ipairs(COLOUR_CODES) do note = note:gsub(code, "") end
    if note ~= "" then f.note = U.Utf8Cut(note, R.NOTE_MAX) end
    -- names out, the second time (every text field)
    local keys = {}
    for k in pairs(f) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do
        local text = f[k]
        if type(text) == "string" then f[k] = U.StripNames(text) end
    end
    -- no realm (2026-11-27: the report worker never stores or shows it, so it isn't sent at all)
    return f
end
R.Fields = Fields

local function Assemble(f)
    local body = ns.Serializer.Build("R2", f)
    return body .. ";ck=" .. R.Checksum(body)
end

-- What goes first when the line is too long (then the note is shortened).
R.DROP = { "eng", "qi", "l3", "it", "pre", "bg", "inc", "cf" }

-- The report string (and its fields). Cut to MAX_LEN in the drop order.
function R.Build(opts)
    opts = opts or {}
    local f = Fields(opts)
    local s = Assemble(f)
    for _, k in ipairs(R.DROP) do
        if #s <= R.MAX_LEN then break end
        f[k] = nil
        s = Assemble(f)
    end
    while #s > R.MAX_LEN and f.note and f.note ~= "" do
        f.note = U.Utf8Cut(f.note, math.max(0, U.Utf8Len(f.note) - 20))
        if f.note == "" then f.note = nil end
        s = Assemble(f)
    end
    return s, f
end

-- "[Report] demo-elwynn/e5: wrong coordinates" (the GitHub issue title line).
function R.Title(f)
    local L = ns.L
    return U.Fill(L.REPORT_TITLE_LINE, { where = (f.pk or "?") .. "/" .. (f.sid or "?"),
        what = L["REPORT_TYPE_" .. tostring(f.ab):upper()] or tostring(f.ab) })
end

-- ------------------------------------------------------------------ the last 20 (account module `reports`)
local function Store(create)
    if ns.safeMode or ns.DB.readOnly.account then return nil end
    if create then return ns.DB.Module("reports", "account", 1) end
    local m = type(ns.DB.account.modules) == "table" and ns.DB.account.modules.reports
    return type(m) == "table" and m or nil
end

-- The first index of a newest-first list that falls past `keep` entries / `keepBytes` (nil = all fit).
local function CutAt(list, keep, keepBytes)
    local bytes = 0
    for i = 1, #list do
        bytes = bytes + #tostring(list[i])
        if i > keep or bytes > keepBytes then return i end
    end
    return nil
end

-- Cuts a newest-first list to keep entries / keepBytes (default the last-20 list's caps); returns how many went.
local function Trim(list, keep, keepBytes)
    local cut = CutAt(list, keep or R.KEEP, keepBytes or R.KEEP_BYTES)
    if not cut then return 0 end
    local n = #list - cut + 1
    for j = #list, cut, -1 do list[j] = nil end
    return n
end

function R.Keep(s)
    local m = Store(true)
    if not m then return false end
    m.list = type(m.list) == "table" and m.list or {}
    for _, old in ipairs(m.list) do if old == s then return true end end
    table.insert(m.list, 1, s)
    Trim(m.list)
    return true
end

function R.Saved()
    local m = Store(false)
    local out = {}
    if m and type(m.list) == "table" then
        for _, s in ipairs(m.list) do if type(s) == "string" then out[#out + 1] = s end end
    end
    return out
end

-- ------------------------------------------------------------------ the outbox (the Addon Manager sends it)
-- "Send" puts the report into `reports.outbox` (newest first, same caps as the list). The addon never sends
-- anything itself: the Addon Manager reads this list from the saved file when the game is closed (text only,
-- it never runs or writes the file), sends each report once and keeps its own list of sent report ids. The
-- addon can't know what was sent, so the list rolls over, but never silently and never over this session's
-- reports: R.OUTBOX entries / R.OUTBOX_BYTES; a Send that would push out a report sent this session (not on
-- disk yet, so the Addon Manager can't have it) is refused ("full"); older ones that make room are counted
-- (R.dropped) and the Send says so. R.queued = reports sent this session that are in the outbox (written to
-- disk at logout or /reload).
R.queued, R.dropped, R.session = 0, 0, {}
R.OUTBOX, R.OUTBOX_BYTES = 40, 60000

-- Same report apart from its id, checksum and the seconds on the step (a second click on Send with nothing
-- changed, a few seconds later).
local function Core(s)
    return (tostring(s):gsub("^AOGR2 rid=[%w]+;", "AOGR2 "):gsub(";ts=%d+", ""):gsub(";ck=%x+$", ""))
end

-- The pattern the Addon Manager and the web page check too (allowed characters, checksum at the end).
R.WIRE = "^AOGR2 rid=[%l%d]+;[%w %.,:_/%+%(%)'!%?%-%%=;]+;ck=%x%x%x%x%x%x%x%x$"
function R.WireOk(s)
    return type(s) == "string" and #s <= R.MAX_LEN and s:find(R.WIRE) ~= nil and R.Verify(s)
end

-- Adds s to a newest-first outbox list (caps R.OUTBOX / R.OUTBOX_BYTES). Returns "added" + how many older
-- entries left to make room, "same" (already there, or the same report with a new id), "full" (making room
-- would push out an entry in `protect`, a set of strings; nothing changed) or nil (not a valid report line).
function R.Push(list, s, protect)
    if not R.WireOk(s) then return nil end
    local core = Core(s)
    for _, old in ipairs(list) do
        if old == s or Core(old) == core then return "same" end
    end
    table.insert(list, 1, s)
    local cut = CutAt(list, R.OUTBOX, R.OUTBOX_BYTES)
    if cut and protect then
        for j = cut, #list do
            if protect[list[j]] then
                table.remove(list, 1)
                return "full"
            end
        end
    end
    return "added", Trim(list, R.OUTBOX, R.OUTBOX_BYTES)
end

-- "Send": into the outbox (and the last-20 list, so it can be copied again). "added" (+ older reports that
-- left the outbox), "same", "full" (this session's reports fill it) or nil.
function R.Queue(s)
    local m = Store(true)
    if not m then return nil end
    m.outbox = type(m.outbox) == "table" and m.outbox or {}
    local how, dropped = R.Push(m.outbox, s, R.session)
    if how == "added" then
        R.session[s] = true
        R.dropped = R.dropped + (dropped or 0)
    end
    -- the count is what's really waiting from this session (never more than the outbox holds)
    local n = 0
    for _, old in ipairs(m.outbox) do if R.session[old] then n = n + 1 end end
    R.queued = n
    if how == "added" or how == "same" then R.Keep(s) end
    return how, dropped
end

-- The reports in the outbox (strings only, a copy).
function R.Outbox()
    local m = Store(false)
    local out = {}
    if m and type(m.outbox) == "table" then
        for _, s in ipairs(m.outbox) do if type(s) == "string" then out[#out + 1] = s end end
    end
    return out
end

-- Self-test: a worst-case report (long note, every field) stays under the cap and checks out; it passes the
-- Addon Manager's / web page's line check; the outbox logic (on a scratch list, never the saved one) adds,
-- skips a second click and caps.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "report", fn = function(h)
    h.Count()
    local s = R.Build({ about = "other", note = ("æøå=;|\n"):rep(60) })
    if #s > R.MAX_LEN then h.Problem(("report: %d characters, cap %d"):format(#s, R.MAX_LEN)) end
    if not R.Verify(s) then h.Problem("report: checksum") end
    if s:find("[\r\n|]") then h.Problem("report: not one plain line") end
    if not R.WireOk(s) then h.Problem("report: fails the send check") end
    local scratch = {}
    local rid = R.rid
    if R.Push(scratch, s) ~= "added" or R.Push(scratch, s) ~= "same" then h.Problem("report: outbox add / same") end
    R.NewId()
    if R.Push(scratch, R.Build({ about = "other", note = ("æøå=;|\n"):rep(60) })) ~= "same" then
        h.Problem("report: a second click with a new id is queued twice")
    end
    R.rid = rid
    for i = 1, R.OUTBOX + 5 do R.Push(scratch, R.Build({ about = "other", note = "self-test " .. i })) end
    if #scratch > R.OUTBOX then h.Problem(("report: outbox holds %d, cap %d"):format(#scratch, R.OUTBOX)) end
    local guard = {}
    for _, old in ipairs(scratch) do guard[old] = true end
    if R.Push(scratch, R.Build({ about = "other", note = "self-test full" }), guard) ~= "full" then
        h.Problem("report: a full outbox drops this session's reports")
    end
    if R.Push(scratch, "AOGR2 rid=x;ck=00000000") ~= nil then h.Problem("report: a bad line is queued") end
    h.Info(("report: worst case %d characters, kept %d, outbox %d"):format(#s, #R.Saved(), #R.Outbox()))
end }

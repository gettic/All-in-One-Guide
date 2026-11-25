-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M5: "Report a mistake", report string v2 (FR-25). One line the player copies and pastes into a
-- GitHub issue; nothing is ever sent by the addon. Built through ns.Serializer kind R2 (allowlist, strict
-- %XX escaping of anything outside a plain set, so non-ASCII, line breaks, "=", ";" and "|" survive),
-- then ";ck=<Adler-32 of everything before it>" (Packs\Format.lua Fm.Adler32, the decoder uses the same).
--   AOGR2 rid=k3x9qa;v=0.2.0;c=16001 1.60.1.70959 forever enUS;...;note=...;ck=1a2b3c4d
-- Never a name: debug lines are stripped when written (Errors.Debug) and every value again here
-- (U.StripNames); the GUID is never kept (only the NPC id part, and only when the player ticks "add my
-- target"). "Remove my location" drops map / x / y / distance. Cap 1,500 characters: dropped in the order
-- engine lines > last steps > include path, then the note is shortened. The last 20 strings are kept
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
    end
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
    if opts.evidence then f.npc = Co.UnitNpcId("target") end
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
    return f
end
R.Fields = Fields

local function Assemble(f)
    local body = ns.Serializer.Build("R2", f)
    return body .. ";ck=" .. R.Checksum(body)
end

-- The report string (and its fields). Cut to MAX_LEN in the drop order.
function R.Build(opts)
    opts = opts or {}
    local f = Fields(opts)
    local s = Assemble(f)
    for _, k in ipairs({ "eng", "l3", "inc", "cf" }) do
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

-- Same report apart from its id and checksum (a second click on Send with nothing changed).
local function Core(s)
    return (tostring(s):gsub("^AOGR2 rid=[%w]+;", "AOGR2 "):gsub(";ck=%x+$", ""))
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

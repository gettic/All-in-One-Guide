-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M6: the dev-only recorder for guide makers (tos R3). Reachable only by "/aog dev on", then
-- "/aog rec on / off / export [part] / clear / status". It records where quests are taken and handed
-- in, loot and gather spots, vendors, trainers and dungeon entrances, as map id + x / y and the
-- NPC / object id. Rules:
--   * NPC / object ids only from Creature- / Vehicle- / GameObject- GUIDs (Compat.GuidNpcId); Player-
--     and Pet- GUIDs give nothing; a GUID itself is never kept; no unit name is ever read.
--   * no events are registered and nothing is saved unless dev mode is on and the recorder is on
--     (AllinOneGuideRecDB stays nil until the first "/aog dev on").
--   * dedupe per record key, caps (records, positions per record, items per record).
--   * the export is plain "AOGREC1 k=v;..." records (built by ns.Serializer, strict escaping) in the copy
--     box, with the contributor-grant line in chat; tools\recmerge.lua reads it.
-- "/aog dev off" and "/aog rec off" keep what was recorded; only "/aog rec clear" (typed twice) deletes it.
local _, ns = ...
local Co, U, L = ns.Compat, ns.U, ns.L
local Rec = { on = false, CAP = 2000, POS = 5, ITEMS = 8, NPC_AGE = 30, PAGE = 3000, GRID = 2, CLEAR_WAIT = 10 }
ns.Recorder = Rec

-- events the recorder listens to (all checked in the 1.60.1 UI source, plans\v0.2\api-16001-v0.2.md)
Rec.EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_ACCEPTED",
    "QUEST_TURNED_IN", "LOOT_OPENED", "MERCHANT_SHOW", "TRAINER_SHOW", "LOADING_SCREEN_ENABLED",
    "PLAYER_ENTERING_WORLD" }
Rec.KINDS = { accept = true, turnin = true, loot = true, gather = true, merchant = true, trainer = true, entrance = true }

-- ------------------------------------------------------------------ the saved table
-- Opens AllinOneGuideRecDB (creates it only when `create`). Unknown or broken parts are kept aside in
-- `_bad`, never dropped.
-- (rawget: the saved value or nil, never anything a metatable on _G might hand out)
function Rec.Open(create)
    local t = rawget(_G, "AllinOneGuideRecDB")
    if type(t) ~= "table" then
        if not create then return nil end
        t = { _bad = t }
        AllinOneGuideRecDB = t
    end
    if type(t.recs) ~= "table" or type(t.order) ~= "table" then
        if t.recs ~= nil or t.order ~= nil then t._bad = { recs = t.recs, order = t.order, old = t._bad } end
        t.recs, t.order = {}, {}
    end
    t.v = t.v or 1
    Rec.db = t
    return t
end

function Rec.Dev()
    local t = Rec.db or Rec.Open(false)
    return t ~= nil and t.dev == true
end

function Rec.Count() return Rec.db and #Rec.db.order or 0 end

-- Listeners this file has on the event hub (the test checks it is 0 while off).
function Rec.Listening()
    local n = 0
    for _, ev in ipairs(Rec.EVENTS) do
        for _, l in ipairs(ns.Events.listeners[ev] or {}) do
            if l.owner == Rec then n = n + 1 end
        end
    end
    return n
end

-- ------------------------------------------------------------------ recording
local function Coord(v) return math.floor(v * 10000 + 0.5) / 100 end   -- 0-1 -> 0-100, 2 decimals

-- map, x, y (x / y 0-100) of the player now, or nil.
function Rec.Where()
    local map = Co.PlayerMap()
    if not map then return nil end
    local x, y = Co.PlayerPos(map)
    if not x then return map end
    return map, Coord(x), Coord(y)
end

local function Key(kind, f, map, x, y)
    local k = table.concat({ kind, f.q or "", f.npc or "", f.obj or "", f.ins or "", map or "" }, ":")
    -- gather spots (herbs, ore, chests) repeat across a zone: one record per 2 % grid cell
    if kind == "gather" and x then k = k .. ":" .. math.floor(x / Rec.GRID) .. "," .. math.floor(y / Rec.GRID) end
    return k
end

-- Adds one sighting. f = { q, npc, obj, ins, from, items = { ids } }; at = { map, x, y } (default: now).
function Rec.Add(kind, f, at)
    local db = Rec.db
    if not (Rec.on and db and Rec.KINDS[kind]) then return nil end
    local map, x, y
    if at then map, x, y = at[1], at[2], at[3] else map, x, y = Rec.Where() end
    local key = Key(kind, f, map, x, y)
    local r = db.recs[key]
    if not r then
        if #db.order >= Rec.CAP then
            if not Rec.fullSaid then
                Rec.fullSaid = true
                ns.Print(U.Fill(L.REC_FULL, { n = Rec.CAP }))
            end
            return nil
        end
        r = { k = kind, q = f.q, npc = f.npc, obj = f.obj, ins = f.ins, from = f.from, m = map, n = 0, pos = {} }
        db.recs[key] = r
        db.order[#db.order + 1] = key
    end
    r.n = r.n + 1
    if x and #r.pos < Rec.POS then r.pos[#r.pos + 1] = { x, y } end
    for _, id in ipairs(f.items or {}) do
        r.it = r.it or {}
        local have = false
        for _, v in ipairs(r.it) do if v == id then have = true break end end
        if not have and #r.it < Rec.ITEMS then r.it[#r.it + 1] = id end
    end
    return r
end

-- Who we are talking to (quest dialog / gossip): id + kind, kept NPC_AGE seconds for accept / turn-in.
local function Talk(startItem)
    local id, kind = Co.UnitNpcId("npc")
    Rec.talk = { id = id, kind = kind, item = startItem, t = Co.Now() }
end

local function Giver()
    local tk = Rec.talk
    if not tk or Co.Now() - tk.t > Rec.NPC_AGE then return {} end
    if tk.item then return { from = tk.item } end
    if tk.kind == "object" then return { obj = tk.id } end
    return { npc = tk.id }
end

local function Quest(kind, questID)
    if type(questID) ~= "number" or Co.IsSecret(questID) then return end
    local f = Giver()
    f.q = questID
    Rec.Add(kind, f)
end

local function Loot(_, _, fromItem)
    if fromItem == true then return end          -- lockboxes, bags: no place in the world
    local list = Co.LootSources()
    if not list then return end
    local by, order = {}, {}
    for _, e in ipairs(list) do
        for _, s in ipairs(e.sources) do
            local key = s[2] .. s[1]
            local b = by[key]
            if not b then
                b = { kind = s[2], id = s[1], items = {} }
                by[key] = b
                order[#order + 1] = key
            end
            if e.item then b.items[#b.items + 1] = e.item end
        end
    end
    for _, key in ipairs(order) do
        local b = by[key]
        if b.kind == "object" then Rec.Add("gather", { obj = b.id, items = b.items })
        else Rec.Add("loot", { npc = b.id, items = b.items }) end
    end
end

local function Vendor(kind)
    local id, what = Co.UnitNpcId("npc")
    if id and what == "npc" then Rec.Add(kind, { npc = id }) end
end

local HANDLERS = {
    QUEST_DETAIL = function(_, startItem) Talk(type(startItem) == "number" and startItem > 0 and startItem or nil) end,
    QUEST_PROGRESS = function() Talk() end,
    QUEST_COMPLETE = function() Talk() end,
    GOSSIP_SHOW = function() Talk() end,
    QUEST_ACCEPTED = function(_, questID) Quest("accept", questID) end,
    QUEST_TURNED_IN = function(_, questID) Quest("turnin", questID) end,
    LOOT_OPENED = Loot,
    MERCHANT_SHOW = function() Vendor("merchant") end,
    TRAINER_SHOW = function() Vendor("trainer") end,
    -- the last outdoor spot before a loading screen; inside an instance it becomes the entrance
    LOADING_SCREEN_ENABLED = function()
        if Co.InInstance() then Rec.out = nil return end
        local m, x, y = Rec.Where()
        Rec.out = x and { m, x, y } or nil
    end,
    PLAYER_ENTERING_WORLD = function()
        local out = Rec.out
        Rec.out = nil
        if out and Co.InInstance() then Rec.Add("entrance", { ins = Co.InstanceId() }, out) end
    end,
}
Rec.HANDLERS = HANDLERS

function Rec.Start()
    if not Rec.Dev() then return false end
    Rec.on = true
    Rec.db.on = true
    for _, ev in ipairs(Rec.EVENTS) do ns.Events.On(ev, Rec, HANDLERS[ev], "recorder") end
    return true
end

function Rec.Stop()
    Rec.on = false
    if Rec.db then Rec.db.on = false end
    for _, ev in ipairs(Rec.EVENTS) do ns.Events.Off(ev, Rec) end
    Rec.talk, Rec.out = nil, nil
end

-- ------------------------------------------------------------------ export
local function Median(list, i)
    local t = {}
    for _, p in ipairs(list) do t[#t + 1] = p[i] end
    if #t == 0 then return nil end
    table.sort(t)
    local mid = math.floor((#t + 1) / 2)
    if #t % 2 == 0 then return Coord((t[mid] + t[mid + 1]) / 200) end
    return t[mid]
end

-- One record as an "AOGREC1 ..." line (nil for a broken saved record).
function Rec.Line(r)
    if type(r) ~= "table" or not Rec.KINDS[r.k] then return nil end
    local it
    if type(r.it) == "table" and #r.it > 0 then it = table.concat(r.it, ",") end
    local pos = type(r.pos) == "table" and r.pos or {}
    return ns.Serializer.Build("REC1", { k = r.k, q = r.q, npc = r.npc, obj = r.obj, ins = r.ins, from = r.from,
        m = r.m, x = Median(pos, 1), y = Median(pos, 2), n = r.n, it = it })
end

-- Export pages (each at most PAGE characters, every page starts with its own header record).
function Rec.Pages()
    local db = Rec.db
    local lines = {}
    for _, key in ipairs(db and db.order or {}) do
        local line = Rec.Line(db.recs[key])
        if line then lines[#lines + 1] = line end
    end
    if #lines == 0 then return {} end
    local pages, cur, len = {}, {}, 0
    for _, line in ipairs(lines) do
        if #cur > 0 and len + #line + 1 > Rec.PAGE - 120 then
            pages[#pages + 1] = cur
            cur, len = {}, 0
        end
        cur[#cur + 1] = line
        len = len + #line + 1
    end
    pages[#pages + 1] = cur
    local out = {}
    for i, p in ipairs(pages) do
        local head = ns.Serializer.Build("REC1", { h = 1, v = ns.version, c = Co.ClientLine(), cnt = #p,
            pg = i .. "/" .. #pages })
        out[i] = head .. " " .. table.concat(p, " ")
    end
    return out
end

function Rec.Export(page)
    local pages = Rec.Pages()
    if #pages == 0 then ns.Print(L.REC_EMPTY) return nil end
    page = U.Clamp(tonumber(page) or 1, 1, #pages)
    ns.Print(L.REC_GRANT)
    ns.Popups.Copy(U.Fill(L.REC_EXPORT_TITLE, { page = page, pages = #pages }), pages[page])
    return pages[page]
end

-- "/aog rec clear" twice within CLEAR_WAIT seconds deletes the records (the only way they go).
function Rec.Clear()
    local n = Rec.Count()
    local now = Co.Now()
    if not (Rec.clearAsked and now - Rec.clearAsked <= Rec.CLEAR_WAIT) then
        Rec.clearAsked = now
        ns.Print(U.Fill(L.REC_CLEAR_ASK, { n = n }))
        return false
    end
    Rec.clearAsked = nil
    if Rec.db then Rec.db.recs, Rec.db.order = {}, {} end
    Rec.fullSaid = nil
    ns.Print(U.Fill(L.REC_CLEARED, { n = n }))
    return true
end

-- ------------------------------------------------------------------ commands (dev only, not in the help)
function Rec.DevCommand(arg)
    arg = strtrim(tostring(arg or "")):lower()
    if arg == "on" then
        local db = Rec.Open(true)
        db.dev = true
        ns.Print(L.DEV_ON)
    elseif arg == "off" then
        Rec.Stop()
        local db = Rec.Open(false)
        if db then db.dev = false end
        ns.Print(L.DEV_OFF)
    else
        ns.Print(Rec.Dev() and L.DEV_STATE_ON or L.DEV_STATE_OFF)
    end
end

function Rec.Command(arg)
    if not Rec.Dev() then ns.Print(L.DEV_NEEDED) return end
    local word, rest = strtrim(tostring(arg or "")):lower():match("^(%S*)%s*(.-)$")
    if word == "on" then
        Rec.Start()
        ns.Print(L.REC_ON)
    elseif word == "off" then
        Rec.Stop()
        ns.Print(U.Fill(L.REC_OFF, { n = Rec.Count() }))
    elseif word == "export" then
        Rec.Export(rest)
    elseif word == "clear" then
        Rec.Clear()
    elseif word == "status" then
        ns.Print(U.Fill(L.REC_STATUS, { state = Rec.on and L.SET_ON or L.SET_OFF, n = Rec.Count() }))
    else
        ns.Print(L.REC_USAGE)
    end
end

-- ------------------------------------------------------------------ /aog where (for everyone)
-- Chat lines: map id + zone + x / y, the quest selected in the log, the target's NPC / object id (only
-- from an NPC / object GUID: another player as the target gives no line). Returns the lines.
function Rec.WhereLines()
    local Lo, out = ns.Locale, {}
    local map, x, y = Rec.Where()
    if map and x then
        out[#out + 1] = U.Fill(L.WHERE_POS, { map = map, zone = Co.MapName(map) or "?",
            x = Lo.Number(x, 2), y = Lo.Number(y, 2) })
    else
        out[#out + 1] = L.WHERE_NOPOS
    end
    local q = Co.SelectedQuest()
    if q then out[#out + 1] = U.Fill(L.WHERE_QUEST, { id = q }) end
    local id, kind = Co.UnitNpcId("target")
    if id then out[#out + 1] = U.Fill(kind == "object" and L.WHERE_OBJECT or L.WHERE_NPC, { id = id }) end
    return out
end

ns.Slash.Add("where", function()
    for _, line in ipairs(Rec.WhereLines()) do ns.Print(line) end
end, "HELP_WHERE")

ns.Slash.Add("dev", Rec.DevCommand, nil, { hidden = true })
ns.Slash.Add("rec", Rec.Command, nil, { hidden = true })

-- After a /reload in dev mode with the recorder on, it carries on; otherwise nothing is registered.
ns.Bus.On("Login", Rec, function()
    local db = Rec.Open(false)
    if db and db.dev == true and db.on == true then Rec.Start() end
end, "recorder", 90)

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "recorder", fn = function(h)
    h.Count()
    local n = Rec.Listening()
    if not Rec.on and n > 0 then h.Problem(("recorder: %d events while off"):format(n)) end
    if Rec.on and n ~= #Rec.EVENTS then h.Problem(("recorder: %d of %d events"):format(n, #Rec.EVENTS)) end
    h.Info(("recorder: %s, %d records"):format(Rec.on and "on" or "off", Rec.Count()))
end }

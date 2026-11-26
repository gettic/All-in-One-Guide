-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The notice line: the window's only hint row. A priority queue; one notice shows at a time (icon +
-- text cut to 30 characters in English / 42 in Danish, full text on hover, at most one button).
-- Right-click: Later (this session) / Hide on this character / Hide hints like this.
-- Quiet mode shows only danger notices; in combat only danger notices show, the rest wait.
--   ns.Notice.Push{ id, kind, text, icon = slot key, priority, button = { text, fn } }
--   ns.Notice.Remove(id), .Top(), .Later(id), .HideChar(id), .HideKind(kind), .Cut(text)
--   bus: NoticeChanged
local _, ns = ...
local N = { list = {}, later = {}, MAX_EN = 30, MAX_DA = 42 }
ns.Notice = N

local DANGER = "danger"

-- Saved hides (written only when the player hides something).
local function Saved(scope, name, create)
    local root = scope == "char" and ns.DB.char or ns.DB.account
    if not root then return nil end
    if create then return (ns.DB.Module(name, scope, 1)) end
    local m = type(root.modules) == "table" and root.modules[name]
    return type(m) == "table" and m or nil
end

local function Snoozed(id)
    local c = Saved("char", "notice")
    local untilT = c and type(c.snooze) == "table" and c.snooze[id]
    if type(untilT) ~= "number" then return false end
    local now = ns.Compat.ServerTime()
    if not now then return false end
    return now < untilT
end
N.Snoozed = Snoozed

local function Hidden(n)
    if n.kind == DANGER then return false end
    if Snoozed(n.id) then return true end
    local c = Saved("char", "notice")
    if c and type(c.hidden) == "table" and c.hidden[n.id] then return true end
    local a = Saved("account", "noticeKinds")
    if a and type(a.hidden) == "table" and a.hidden[n.kind] then return true end
    return false
end

local function Changed() ns.Bus.Fire("NoticeChanged") end

-- quiet = true: no NoticeChanged (perf: the caller fires StepChanged right after, and that redraw shows it)
function N.Push(n, quiet)
    if type(n) ~= "table" or type(n.id) ~= "string" or type(n.text) ~= "string" then return false end
    n.kind = n.kind or "tip"
    n.priority = n.priority or (n.kind == DANGER and 100 or 10)
    for i, old in ipairs(N.list) do
        if old.id == n.id then
            N.list[i] = n
            if not quiet then Changed() end
            return true
        end
    end
    N.list[#N.list + 1] = n
    if not quiet then Changed() end
    return true
end

function N.Remove(id)
    for i, n in ipairs(N.list) do
        if n.id == id then
            table.remove(N.list, i)
            Changed()
            return true
        end
    end
    return false
end

-- The notice to show now, or nil.
function N.Top()
    local quiet = ns.Settings.Get("quiet")
    local combat = ns.Compat.InCombat()
    local best
    for _, n in ipairs(N.list) do
        local ok = not N.later[n.id] and not Hidden(n)
        if ok and n.kind ~= DANGER and (quiet or combat) then ok = false end
        if ok and (not best or n.priority > best.priority) then best = n end
    end
    return best
end

-- Later: "session" (default, not saved), "hour" or "day" (saved per character with the server time;
-- without a server time it falls back to this session). Old snoozes are dropped when a new one is set.
N.SNOOZE = { hour = 3600, day = 86400 }
function N.Later(id, how)
    local secs = N.SNOOZE[how or "session"]
    local now = secs and ns.Compat.ServerTime()
    if not secs or not now or ns.safeMode or ns.DB.readOnly.char then
        N.later[id] = true
        Changed()
        return "session"
    end
    local c = Saved("char", "notice", true)
    if not c then N.later[id] = true Changed() return "session" end
    c.snooze = type(c.snooze) == "table" and c.snooze or {}
    for k, v in pairs(c.snooze) do if type(v) ~= "number" or v <= now then c.snooze[k] = nil end end
    c.snooze[id] = now + secs
    Changed()
    return how
end

-- "Why am I seeing this?": which part sent it and its off switch (lines for the hover tooltip).
local SOURCE = { reminders = "STEPS", logfull = "QUESTS", undo = "STEPS", lang = "OTHER", selftest = "SELFTEST", conflicts = "LINK",
    questitems = "QUESTS", questgiver = "NPC" }
function N.Why(n)
    local L = ns.L
    local part = SOURCE[n.source or ""] or SOURCE[n.id] or SOURCE[n.kind] or "OTHER"
    local lines = { L.NOTICE_WHY, ns.U.Fill(L.NOTICE_FROM, { part = L["FEAT_" .. part] or L.FEAT_OTHER }) }
    if n.kind ~= DANGER then
        local how = n.source == "reminders" and n.id == "useitem"
            and ns.U.Fill(L.MENU_REMINDER, { level = L.REMINDER_OFF }) or L.NOTICE_HIDE_KIND
        lines[#lines + 1] = ns.U.Fill(L.NOTICE_OFF, { how = how })
    end
    return lines
end

function N.HideChar(id)
    local c = Saved("char", "notice", true)
    if not c then return end
    c.hidden = type(c.hidden) == "table" and c.hidden or {}
    c.hidden[id] = true
    Changed()
end

function N.HideKind(kind)
    if kind == DANGER then return false end
    local a = Saved("account", "noticeKinds", true)
    if not a then return false end
    a.hidden = type(a.hidden) == "table" and a.hidden or {}
    a.hidden[kind] = true
    Changed()
    return true
end

function N.MaxChars() return ns.Locale.code == "daDK" and N.MAX_DA or N.MAX_EN end

-- The shown text: cut by characters (UTF-8 safe), "..." when cut.
function N.Cut(text) return (ns.U.Utf8Cut(text or "", N.MaxChars())) end

-- The right-click menu items for a notice.
function N.MenuItems(n)
    local L = ns.L
    local items = {
        { text = L.NOTICE_LATER_HOUR, fn = function() N.Later(n.id, "hour") end, disabled = n.kind == DANGER },
        { text = L.NOTICE_LATER_SESSION, fn = function() N.Later(n.id, "session") end },
        { text = L.NOTICE_LATER_DAY, fn = function() N.Later(n.id, "day") end, disabled = n.kind == DANGER },
        { text = L.NOTICE_HIDE_CHAR, fn = function() N.HideChar(n.id) end, disabled = n.kind == DANGER },
        { text = L.NOTICE_HIDE_KIND, fn = function() N.HideKind(n.kind) end, disabled = n.kind == DANGER },
    }
    -- a notice's own rows (n.menu = { { text, fn } }) come first (quest giver check: "Show it again")
    if type(n.menu) == "table" then
        for k = #n.menu, 1, -1 do
            local m = n.menu[k]
            if type(m) == "table" and type(m.text) == "string" and type(m.fn) == "function" then
                table.insert(items, 1, { text = m.text, fn = m.fn })
            end
        end
    end
    return items
end

-- Combat start / end and Quiet mode change what may show.
ns.Bus.On("CombatStarted", N, Changed, "ui")
ns.Bus.On("CombatEnded", N, Changed, "ui")
ns.Bus.On("SettingsChanged", N, function(_, key) if key == "quiet" then Changed() end end, "ui")

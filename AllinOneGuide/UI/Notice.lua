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

local function Hidden(n)
    if n.kind == DANGER then return false end
    local c = Saved("char", "notice")
    if c and type(c.hidden) == "table" and c.hidden[n.id] then return true end
    local a = Saved("account", "noticeKinds")
    if a and type(a.hidden) == "table" and a.hidden[n.kind] then return true end
    return false
end

local function Changed() ns.Bus.Fire("NoticeChanged") end

function N.Push(n)
    if type(n) ~= "table" or type(n.id) ~= "string" or type(n.text) ~= "string" then return false end
    n.kind = n.kind or "tip"
    n.priority = n.priority or (n.kind == DANGER and 100 or 10)
    for i, old in ipairs(N.list) do
        if old.id == n.id then N.list[i] = n Changed() return true end
    end
    N.list[#N.list + 1] = n
    Changed()
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

function N.Later(id) N.later[id] = true Changed() end

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
    return {
        { text = L.NOTICE_LATER, fn = function() N.Later(n.id) end },
        { text = L.NOTICE_HIDE_CHAR, fn = function() N.HideChar(n.id) end, disabled = n.kind == DANGER },
        { text = L.NOTICE_HIDE_KIND, fn = function() N.HideKind(n.kind) end, disabled = n.kind == DANGER },
    }
end

-- Combat start / end and Quiet mode change what may show.
ns.Bus.On("CombatStarted", N, Changed, "ui")
ns.Bus.On("CombatEnded", N, Changed, "ui")
ns.Bus.On("SettingsChanged", N, function(_, key) if key == "quiet" then Changed() end end, "ui")

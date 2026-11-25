-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Error safety: every call into a feature runs in xpcall; an error is shown once as one chat line
-- and kept for the copy box (with the stored self-test line). A feature that errors 3 times turns
-- itself off (reason in /aog status). Debug log: a ring buffer, off by default (/aog debug on).
-- Safe mode core: after two loads in a row that never finished, the next load runs on defaults in
-- memory, touches no saves (except the small boot record) and loads nothing on demand.
local _, ns = ...
local U = ns.U
local E = { list = {}, counts = {}, shown = {}, log = {}, logSize = 200, logPos = 0, debug = false, last = nil }
ns.Errors = E

local MAX_ERRORS = 3
local MAX_KEPT = 20

local function Handler(msg)
    local stack = _G.debugstack and _G.debugstack(2, 6, 0) or ""
    return tostring(msg) .. "\n" .. tostring(stack)
end
E.Handler = Handler

function E.Record(feature, msg)
    feature = feature or "core"
    local text = U.Plain(msg)
    E.counts[feature] = (E.counts[feature] or 0) + 1
    if #E.list < MAX_KEPT then E.list[#E.list + 1] = { feature = feature, msg = text } end
    E.last = { feature = feature, msg = text }
    E.Debug("error in %s: %s", feature, text)
    if not E.shown[feature] then
        E.shown[feature] = true
        local L = ns.L
        local line = L and L.ERROR_LINE or "something went wrong in {feature}. Type /aog error to copy the details."
        ns.Print(U.Fill(line, { feature = feature }))
    end
    if E.counts[feature] >= MAX_ERRORS and ns.Feature and feature ~= "core" then
        ns.Feature.Set(feature, "errors", "3 errors")
    end
end

-- Runs fn(...) safely for a feature. Returns ok, results...
function E.Call(feature, fn, ...)
    if ns.Feature and feature and not ns.Feature.IsOn(feature) then return false end
    local ok, a, b, c, d = xpcall(fn, Handler, ...)
    if not ok then
        E.Record(feature, a)
        return false
    end
    return true, a, b, c, d
end

-- The text for the copy box: version, client, the stored self-test line, then the last error.
function E.CopyText()
    local parts = { "AOG " .. tostring(ns.version) }
    if ns.Compat and ns.Compat.ClientLine then parts[#parts + 1] = ns.Compat.ClientLine() end
    parts[#parts + 1] = "selftest=" .. tostring(ns.DB and ns.DB.SelfTestLine and ns.DB.SelfTestLine() or "not run")
    if E.last then parts[#parts + 1] = "error=" .. E.last.feature .. ": " .. E.last.msg end
    return table.concat(parts, " | ")
end

-- ------------------------------------------------------------------ debug ring buffer
function E.Debug(fmt, ...)
    if not E.debug then return end
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = tostring(fmt) end
    E.logPos = E.logPos % E.logSize + 1
    E.log[E.logPos] = U.Plain(line)
end

function E.DebugLines(n)
    local out, count = {}, 0
    local pos = E.logPos
    while count < (n or 20) and E.log[pos] do
        out[#out + 1] = E.log[pos]
        count = count + 1
        pos = pos - 1
        if pos < 1 then pos = E.logSize end
        if pos == E.logPos then break end
    end
    return out
end

-- ------------------------------------------------------------------ crash-during-load / safe mode
-- boot = account save's small boot record { pending = true while loading, crashes = n }.
function E.BootStart(boot)
    if type(boot) ~= "table" then return false end
    if boot.pending then boot.crashes = (tonumber(boot.crashes) or 0) + 1 else boot.crashes = 0 end
    boot.pending = true
    ns.safeMode = (boot.crashes or 0) >= 2
    return ns.safeMode
end

function E.BootDone(boot)
    if type(boot) ~= "table" then return end
    boot.pending = nil
    if ns.safeMode then boot.crashes = 0 end   -- one safe session, then the next load tries normally
end

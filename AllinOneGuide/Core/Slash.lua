-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Slash command registry: /aog <word> [args]. Help is built from the registry; adding the same
-- word twice is an error (clash check). Command words never change with the language.
--   ns.Slash.Add("status", fn, "HELP_STATUS", { main = true })   main = shown in the short /aog help
local _, ns = ...
local Sl = { words = {}, order = {}, default = nil }
ns.Slash = Sl

function Sl.Add(word, fn, helpKey, opts)
    word = word:lower()
    assert(not Sl.words[word], "slash word registered twice: " .. word)
    Sl.words[word] = { fn = fn, help = helpKey, main = opts and opts.main, hidden = opts and opts.hidden }
    Sl.order[#Sl.order + 1] = word
end

-- What a bare /aog does (the guide window toggles it from M3 on; until then: help).
function Sl.SetDefault(fn) Sl.default = fn end

function Sl.Help(all)
    local L = ns.L
    ns.Print(all and L.HELP_TITLE_ALL or L.HELP_TITLE)
    for _, w in ipairs(Sl.order) do
        local c = Sl.words[w]
        if not c.hidden and (all or c.main) then
            ns.Print("/aog " .. w .. " - " .. (c.help and L[c.help] or ""))
        end
    end
    if not all then ns.Print("/aog help all - " .. L.HELP_ALL) end
end

function Sl.Run(msg)
    msg = strtrim(tostring(msg or ""))
    local word, rest = msg:match("^(%S+)%s*(.-)$")
    word = word and word:lower() or ""
    if word == "" then
        if Sl.default then return Sl.default() end
        return Sl.Help(false)
    end
    if word == "help" then return Sl.Help(rest:lower() == "all") end
    local c = Sl.words[word]
    if not c then
        ns.Print(ns.U.Fill(ns.L.SLASH_UNKNOWN, { word = word }))
        return
    end
    return c.fn(rest)
end

SLASH_AOG1 = "/aog"
SlashCmdList.AOG = function(msg) ns.Errors.Call("slash", Sl.Run, msg) end

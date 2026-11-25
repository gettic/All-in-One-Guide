-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Provenance filter for the offline importer (FR-21 / FR-22). Decides, from data only, which sources and
-- which records we may take into All-in-One Guide (GPL-3.0-or-later):
--   * a source must name its exact SPDX licence id and a pinned version (never "latest" / a branch);
--     only licences in RULES.licences are taken, everything else (incl. "all rights reserved") is refused;
--   * a record is dropped when it says it came from a site whose data we may not use (RULES.dropFrom, e.g.
--     Wowhead-derived), when any of its text mentions such a site (RULES.dropText), when its contributor
--     has not agreed (RULES.noConsent, or the record says consent = false), or when the source marks it
--     as kept "all rights reserved" by its owners;
--   * every kept record gets a source tag (FORMAT.md `src`) and the source's SPDX id.
-- The licence list is for the licence agent to confirm before the first real import (plans\v0.2\data-update-flow.md).
-- Use: local P = assert(loadfile("tools/import/provenance.lua"))()
local P = {}

P.RULES = {
    -- SPDX ids whose data can go into a GPL-3.0-or-later project (inbound-compatible), to confirm by the
    -- licence agent. CC-BY-SA-4.0 is one-way compatible with GPLv3 (Creative Commons' compatibility list).
    licences = {
        ["GPL-3.0-or-later"] = true, ["GPL-3.0-only"] = true, ["GPL-2.0-or-later"] = true,
        ["CC0-1.0"] = true, ["CC-BY-SA-4.0"] = true, ["MIT"] = true, ["BSD-2-Clause"] = true, ["BSD-3-Clause"] = true,
    },
    -- record-level origin tags (lower case) we never take
    dropFrom = {
        wowhead = "Wowhead-derived", wh = "Wowhead-derived", ["wowhead.com"] = "Wowhead-derived",
        thottbot = "copied from a closed site", allakhazam = "copied from a closed site",
        ["paid-guide"] = "from a paid guide",
        -- ForeverDB recordings without a licence (licence agent, plans\v0.2\licence-import.md)
        commandcenter = "an unlicensed recording", ["command center"] = "an unlicensed recording",
        ["command-center"] = "an unlicensed recording", ["command_center"] = "an unlicensed recording",
        questicus = "an unlicensed recording",
    },
    -- text anywhere in a record that marks it as copied from a site or recording we never take
    dropText = { "wowhead%.com", "wowhead", "thottbot", "allakhazam", "questicus", "commandcenter" },
    -- contributors (lower case, as the source names them) who have not agreed to reuse
    noConsent = {},
    -- contributors who have agreed (lower case); filled from the source's provenance file
    consent = {},
    -- record ids per kind (quest / npc / object) from the source's provenance file
    reserved = { quest = {}, npc = {}, object = {} },   -- kept all rights reserved by their owners: dropped
    released = { quest = {}, npc = {}, object = {} },   -- released under the source's licence: positive provenance
    -- fail closed (licence agent, note B): for these source tags a record is only kept with POSITIVE provenance
    -- (prov.consent = true, a contributor on the consent list, or its id on the released list); no provenance =
    -- dropped (bucket "noprov"). Questie / QuestieDB are GPL only for consenting contributors.
    failClosed = { questie = true },
    -- version strings that are not a pin
    notPinned = { latest = true, master = true, main = true, head = true, dev = true, [""] = true },
    -- source names -> FORMAT.md `src` tag
    tags = { questie = "questie", ["questie-sample"] = "questie", forevdb = "forevdb", codex = "codex",
        cmangos = "cmangos", rec = "rec", sample = "own" },
}

local function Lower(s) return type(s) == "string" and s:lower() or nil end

-- meta = { source, version, spdx }; returns ok, reason.
function P.Source(meta, rules)
    rules = rules or P.RULES
    if type(meta) ~= "table" then return false, "no source header" end
    local spdx = meta.spdx
    if type(spdx) ~= "string" or spdx == "" then return false, "the source names no SPDX licence id" end
    if spdx:lower():find("all rights reserved", 1, true) or spdx:lower():find("proprietary", 1, true) then
        return false, "the source is all rights reserved"
    end
    if not rules.licences[spdx] then return false, "licence " .. spdx .. " is not on the list we may take" end
    local v = meta.version
    if type(v) ~= "string" or rules.notPinned[v:lower()] then
        return false, "the source version is not pinned (got " .. tostring(v) .. ")"
    end
    if not rules.tags[Lower(meta.source) or ""] then return false, "unknown source " .. tostring(meta.source) end
    return true
end

local function Texts(v, out, depth)
    depth = depth or 0
    if depth > 8 then return out end
    if type(v) == "string" then out[#out + 1] = v:lower()
    elseif type(v) == "table" then
        for k, x in pairs(v) do
            if type(k) == "string" then out[#out + 1] = k:lower() end
            Texts(x, out, depth + 1)
        end
    end
    return out
end

local function Listed(lists, kind, id)
    local l = type(lists) == "table" and lists[kind]
    return type(l) == "table" and id ~= nil and l[id] == true
end

-- rec = { kind, id, ..., prov = { from, by, consent, reserved } }; tag = the source's tag (P.Tag) for the
-- fail-closed rule. Returns ok, reason (the drop bucket), why.
function P.Record(rec, rules, tag)
    rules = rules or P.RULES
    if type(rec) ~= "table" then return false, "invalid" end
    local prov = type(rec.prov) == "table" and rec.prov or {}
    local from = Lower(prov.from)
    if from and rules.dropFrom[from] then return false, "wowhead", rules.dropFrom[from] end
    if prov.reserved == true or Listed(rules.reserved, rec.kind, rec.id) then
        return false, "reserved", "kept all rights reserved by its owners"
    end
    if prov.consent == false then return false, "consent", "the contributor has not agreed" end
    local by = Lower(prov.by)
    if by and rules.noConsent[by] then return false, "consent", "the contributor has not agreed" end
    for _, s in ipairs(Texts(rec, {})) do
        for _, pat in ipairs(rules.dropText) do
            if s:find(pat) then return false, "wowhead", "mentions a site we never take" end
        end
    end
    if tag and rules.failClosed and rules.failClosed[tag] then
        local positive = prov.consent == true or (by ~= nil and rules.consent ~= nil and rules.consent[by] == true)
            or Listed(rules.released, rec.kind, rec.id)
        if not positive then return false, "noprov", "no positive provenance (fail closed)" end
    end
    return true
end

-- The source's provenance file, read AS DATA (tools/import/luadata.lua, never run). Sample layout (our own,
-- plans\v0.2\import-samples\questie-provenance.lua; adapt to Questie's real file after the download yes):
--   return { format = "provenance-1",
--            consent = { "<contributor>", ... },          -- agreed to reuse under the source's licence
--            noConsent = { "<contributor>", ... },        -- did not agree
--            reserved = { quests = { ids }, npcs = { ids }, objects = { ids } },   -- all rights reserved
--            released = { quests = { ids }, npcs = { ids }, objects = { ids } } }  -- released by their makers
-- Also takes a plain text list ("# comment" lines; "consent: <name>", "no-consent: <name>",
-- "reserved: quest <id>", "released: npc <id>"). Returns lists = { consent, noConsent, reserved, released } or nil, err.
local KINDS = { quests = "quest", npcs = "npc", objects = "object", quest = "quest", npc = "npc", object = "object" }
local function IsId(v) return type(v) == "number" and v >= 1 and v < 1e7 and v == math.floor(v) end
function P.LoadProvenance(text, LD, opts)
    if type(text) ~= "string" then return nil, "no provenance text" end
    local out = { consent = {}, noConsent = {}, reserved = { quest = {}, npc = {}, object = {} },
        released = { quest = {}, npc = {}, object = {} } }
    local function Name(list, n) if type(n) == "string" and n ~= "" then list[n:lower()] = true end end
    -- a data file (a table literal) or else the text list; a file that is neither gives empty lists, and empty
    -- lists keep nothing from a fail-closed source (safe)
    local t = LD.Parse(text, opts)
    if type(t) == "table" then
        for _, n in ipairs(type(t.consent) == "table" and t.consent or {}) do Name(out.consent, n) end
        for _, n in ipairs(type(t.noConsent) == "table" and t.noConsent or {}) do Name(out.noConsent, n) end
        for _, part in ipairs({ "reserved", "released" }) do
            local p = t[part]
            if type(p) == "table" then
                for key, ids in pairs(p) do
                    local kind = KINDS[key]
                    if kind and type(ids) == "table" then
                        for _, id in ipairs(ids) do if IsId(id) then out[part][kind][id] = true end end
                    end
                end
            end
        end
        return out
    end
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:find("^#") then
            local what, rest = line:match("^([%a%-]+):%s*(.+)$")
            what = what and what:lower()
            if what == "consent" then Name(out.consent, rest)
            elseif what == "no-consent" then Name(out.noConsent, rest)
            elseif what == "reserved" or what == "released" then
                local k, id = rest:match("^(%a+)%s+(%d+)$")
                local kind = k and KINDS[k:lower()]
                id = tonumber(id)
                if kind and IsId(id) then out[what][kind][id] = true end
            end
        end
    end
    return out
end

-- The tag a kept record gets (FORMAT.md `src`).
function P.Tag(meta, rules)
    rules = rules or P.RULES
    return rules.tags[Lower(meta.source) or ""] or "own"
end

return P

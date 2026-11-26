-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Compares the merged game data (tools/recmerge.lua game data output, src = "gather") with the imported facts
-- (tools/import/import.lua output: quests / npcs / objects) and lists where WoW Forever seems to differ: a quest's
-- level, a quest offered below its minLevel, a giver / turn-in NPC the facts don't name, a giver standing far from
-- every known spawn of that NPC. Nothing is changed or applied: a person (the data agent) reads the list.
-- Both files are read as data only (tools/import/luadata.lua, no code runs).
-- Run (from the repository folder):
--   luajit tools/gatherdiff.lua --gather <merged.lua> --facts <facts.lua> [--far 3] [--out <diff.txt>]
-- As a library: local GD = assert(loadfile("tools/gatherdiff.lua"))("--lib", "<tools folder>")
local args = { ... }
local here = (args[1] == "--lib" and args[2]) or (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tools"
local GD = { FAR = 3 }
local LD = assert(loadfile(here .. "/import/luadata.lua"))()

local function Near(spawns, m, x, y, far)
    if not (m and x and y) then return true end
    local any = false
    for _, p in ipairs(spawns or {}) do
        if p[1] == m then
            any = true
            if math.abs(p[2] - x) <= far and math.abs(p[3] - y) <= far then return true end
        end
    end
    return not any      -- no spawn on that map in the facts: nothing to compare
end

local function Has(list, id)
    for _, v in ipairs(list or {}) do if v == id then return true end end
    return false
end

-- gather = list of merged facts; facts = { quests, npcs, objects }; opts = { far = 3 }. Returns lines (sorted).
function GD.Diff(gather, facts, opts)
    opts = opts or {}
    local far = opts.far or GD.FAR
    local quests, npcs, objects = facts.quests or {}, facts.npcs or {}, facts.objects or {}
    local out = {}
    local function Say(fmt, ...) out[#out + 1] = fmt:format(...) end
    for _, r in ipairs(gather) do
        local q = r.q and quests[r.q]
        if r.k == "qxp" and q and r.ql and q.level and r.ql ~= q.level then
            Say("quest %d: level %d on Forever, %d in the facts (%d pages)", r.q, r.ql, q.level, r.batches or 0)
        elseif r.k == "offer" and q and r.pl and q.minLevel and r.pl < q.minLevel then
            Say("quest %d: offered at level %d, minLevel %d in the facts (%d pages)", r.q, r.pl, q.minLevel, r.batches or 0)
        elseif (r.k == "accept" or r.k == "turnin") and q then
            local side = q[r.k == "accept" and "start" or "finish"] or {}
            if r.npc and side.npc and not Has(side.npc, r.npc) then
                Say("quest %d: %s at NPC %d, the facts name %s", r.q, r.k, r.npc, table.concat(side.npc, ","))
            elseif r.obj and side.obj and not Has(side.obj, r.obj) then
                Say("quest %d: %s at object %d, the facts name %s", r.q, r.k, r.obj, table.concat(side.obj, ","))
            end
            local who = r.npc and npcs[r.npc] or (r.obj and objects[r.obj])
            if who and not Near(who.spawns, r.m, r.x, r.y, far) then
                Say("quest %d: %s spot %d %.2f,%.2f is far from every known spawn of %s %d", r.q, r.k, r.m, r.x, r.y,
                    r.npc and "NPC" or "object", r.npc or r.obj)
            end
        elseif (r.k == "merchant" or r.k == "trainer" or r.k == "inn" or r.k == "fm") and r.npc and npcs[r.npc]
            and not Near(npcs[r.npc].spawns, r.m, r.x, r.y, far) then
            Say("NPC %d (%s): seen at %d %.2f,%.2f, far from every known spawn", r.npc, r.k, r.m, r.x, r.y)
        end
    end
    table.sort(out)
    return out
end

local function Load(path)
    local fh = io.open(path, "rb")
    if not fh then return nil, "cannot read " .. path end
    local text = fh:read("*a")
    fh:close()
    return LD.Parse(text, { maxBytes = 64 * 1024 * 1024 })
end

function GD.Main(a)
    local o = {}
    local i = 1
    while i <= #a do
        local k = a[i]
        if k == "--gather" or k == "--facts" or k == "--out" or k == "--far" then o[k:sub(3)] = a[i + 1] i = i + 1 end
        i = i + 1
    end
    if not (o.gather and o.facts) then
        print("usage: luajit tools/gatherdiff.lua --gather <merged.lua> --facts <facts.lua> [--far 3] [--out <diff.txt>]")
        return false
    end
    local gather, e1 = Load(o.gather)
    local facts, e2 = Load(o.facts)
    if type(gather) ~= "table" or type(facts) ~= "table" then print(tostring(e1 or e2)) return false end
    local lines = GD.Diff(gather, facts, { far = tonumber(o.far) })
    local text = table.concat(lines, "\n") .. "\n"
    if o.out then
        local fh = assert(io.open(o.out, "wb"))
        fh:write(text)
        fh:close()
    else
        io.write(text)
    end
    print(("gatherdiff: %d differences (never applied; a person checks each)"):format(#lines))
    return true
end

if args[1] == "--lib" then return GD end
if not GD.Main(args) then os.exit(1) end

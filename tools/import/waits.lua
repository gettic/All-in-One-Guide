-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Writes tools\data\quest-waits.lua: the timed quests (the quest's own timer) from a LOCAL CMaNGOS classic-db SQL
-- dump (https://github.com/cmangos/classic-db, GPL-3.0), read as TEXT only (never loaded into a database, never
-- run). Only two numbers per quest are kept: the quest id and quest_template.LimitTime (seconds -> minutes).
-- Escort / event / respawn quests have no reliable flag in the dump: they are added by hand in the file's
-- `manual` part (kept as it is when the file is written again).
-- Run (from the repository folder):
--   luajit tools/import/waits.lua --sql <ClassicDB.sql> [--check] [--out tools/data/quest-waits.lua]
--   --check: write nothing, fail when the file would change.
local W = {}

-- quest_template's first columns are numbers: entry (0) ... LimitTime (19), see the dump's CREATE TABLE.
W.LIMIT_COLUMN = 19

-- Returns { [quest] = minutes } of every quest with LimitTime > 0, or nil, error.
function W.Read(path)
    local fh = io.open(path, "rb")
    if not fh then return nil, "can't open " .. path end
    local out = {}
    local numbers = "(" .. string.rep("%-?%d+,", W.LIMIT_COLUMN + 1) .. ")"
    for line in fh:lines() do
        if line:match("^INSERT INTO `quest_template` VALUES ") then
            for head in line:gmatch("%(" .. numbers) do
                local vals = {}
                for v in head:gmatch("(%-?%d+),") do vals[#vals + 1] = tonumber(v) end
                local id, limit = vals[1], vals[W.LIMIT_COLUMN + 1]
                if id and id > 0 and limit and limit > 0 then out[id] = math.max(1, math.floor(limit / 60 + 0.5)) end
            end
        end
    end
    fh:close()
    return out
end

-- The kept `manual` entries of an existing file (text between the markers), or the empty default.
local MARK_A, MARK_B = "-- manual (kept when written again)", "-- end of manual"
function W.Manual(text)
    local body = text and text:match(MARK_A .. "\n(.-)" .. MARK_B)
    return body or ""
end

function W.Text(timed, manual)
    local ids = {}
    for id in pairs(timed) do ids[#ids + 1] = id end
    table.sort(ids)
    local L = {
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2026 gettic",
        "-- Known quests that make the player wait (packcheck warns when a route step for one has no `waits`).",
        "-- Timed: quest id -> the quest's timer in minutes, from CMaNGOS classic-db quest_template.LimitTime",
        "-- (GPL-3.0; numbers only), written by tools\\import\\waits.lua. Escort / event / respawn: added by hand",
        "-- in the manual part, each with where it was seen.",
        "local T = {}",
        "local function timed(id, min) T[id] = { kind = \"timed\", timeLimit = min, src = \"cmangos\" } end",
        "local function wait(id, kind, src, seen) T[id] = { kind = kind, src = src, seen = seen } end",
    }
    for _, id in ipairs(ids) do L[#L + 1] = ("timed(%d, %d)"):format(id, timed[id]) end
    L[#L + 1] = MARK_A
    L[#L + 1] = (manual or "") .. MARK_B
    L[#L + 1] = "local _ = wait"
    L[#L + 1] = "return T"
    return table.concat(L, "\n") .. "\n"
end

function W.Main(argv)
    local opts = { out = "tools/data/quest-waits.lua" }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--check" then opts.check, i = true, i + 1
        elseif a == "--sql" or a == "--out" then opts[a:sub(3)], i = argv[i + 1], i + 2
        else i = i + 1 end
    end
    if not opts.sql then print("usage: luajit tools/import/waits.lua --sql <ClassicDB.sql> [--check]") return false end
    local timed, err = W.Read(opts.sql)
    if not timed then print("ERROR " .. err) return false end
    local fh = io.open(opts.out, "rb")
    local old = fh and fh:read("*a")
    if fh then fh:close() end
    local text = W.Text(timed, W.Manual(old))
    local n = 0
    for _ in pairs(timed) do n = n + 1 end
    if old == text then print(("waits: %d timed quests, unchanged"):format(n)) return true end
    if opts.check then print("DIFFERS " .. opts.out .. ": run tools/import/waits.lua --sql <dump>") return false end
    local out = assert(io.open(opts.out, "wb"))
    out:write(text)
    out:close()
    print(("waits: %d timed quests written to %s"):format(n, opts.out))
    return true
end

local args = { ... }
if args[1] == "--lib" then return W end
if not W.Main(args) then os.exit(1) end

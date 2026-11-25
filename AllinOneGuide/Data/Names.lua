-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Names service: names of game things come from the client by id, in the client's language.
-- Not cached yet -> ask the client once and show the fallback; when it arrives, "NameReady" goes on
-- the bus so the window can redraw. Fallback order: client name > our own short wording > "...".
-- A small LRU keeps only recently used names.
local _, ns = ...
local Co = ns.Compat
local N = { quests = {}, order = {}, asked = {}, MAX = 200 }
ns.Names = N

local function Remember(id, name)
    if N.quests[id] == nil then
        N.order[#N.order + 1] = id
        if #N.order > N.MAX then
            local old = table.remove(N.order, 1)
            N.quests[old] = nil
        end
    end
    N.quests[id] = name
end

-- Quest name for an id; `fallback` is our own wording from the pack (may be nil).
function N.Quest(id, fallback)
    local name = N.quests[id]
    if name then return name, true end
    if ns.Feature.IsOn("names") then
        name = Co.QuestTitle(id)
        if name then
            Remember(id, name)
            return name, true
        end
        if not N.asked[id] then
            N.asked[id] = true
            -- through the one rate-limited request queue (tos R2)
            ns.QuestData.Request(id)
        end
    end
    return fallback or "...", false
end

function N.Start()
    ns.Events.On("QUEST_DATA_LOAD_RESULT", N, function(_, id, ok)
        if type(id) ~= "number" or not N.asked[id] then return end
        N.asked[id] = nil
        if ok then
            local name = Co.QuestTitle(id)
            if name then
                Remember(id, name)
                ns.Bus.Fire("NameReady", "quest", id)
            end
        end
    end, "names")
end

-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Atlas check helper (v0.1.1, T66). Blizzard atlases are used only by name, never copied, and always
-- with a fallback, because a name may be missing on this client:
--   ns.Atlas.Has(name)                     cached C_Texture.GetAtlasInfo check
--   ns.Atlas.Apply(tex, name, fallback)    the atlas, else our media slot `fallback`, else a flat fill
--   ns.Atlas.Missing()                     sorted list of "theme:key=name" for atlases a theme names but
--                                          the client lacks (the self-test lists them)
-- Theme keys "atlas.<role>" hold atlas names; "atlas.<role>.fallback" may name a media slot key.
local _, ns = ...
local At = { cache = {} }
ns.Atlas = At

function At.Has(name)
    if type(name) ~= "string" or name == "" then return false end
    local v = At.cache[name]
    if v == nil then
        v = ns.Compat.AtlasInfo(name) ~= nil
        At.cache[name] = v
    end
    return v
end

-- Returns "atlas", "media" or "fill" (what was used).
function At.Apply(tex, name, fallback)
    if At.Has(name) and tex.SetAtlas then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(name)
        return "atlas"
    end
    if fallback and ns.Media.Get(fallback) then
        ns.Media.Apply(tex, fallback)
        return "media"
    end
    tex:SetColorTexture(1, 1, 1, 0.3)
    return "fill"
end

-- Applies the atlas a theme key names (with its ".fallback" key). Returns what was used.
function At.ApplyKey(tex, key)
    local name = ns.Theme.Raw(key)
    local fb = ns.Theme.Raw(key .. ".fallback")
    return At.Apply(tex, name, fb)
end

function At.Missing()
    local out = {}
    for themeName, t in pairs(ns.Theme.themes) do
        for key, v in pairs(t) do
            if type(key) == "string" and key:match("^atlas%.") and not key:match("%.fallback$") and type(v) == "string"
                and not At.Has(v) then
                out[#out + 1] = themeName .. ":" .. key .. "=" .. v
            end
        end
    end
    table.sort(out)
    return out
end

function At.Reset() At.cache = {} end

ns.SelfChecks[#ns.SelfChecks + 1] = { label = "atlas", fn = function(h)
    h.Count()
    if not ns.Compat.has.AtlasInfo then
        h.Skip("atlas", "(no C_Texture.GetAtlasInfo)")
        return
    end
    local miss = At.Missing()
    if #miss > 0 then h.Info("atlases missing (fallback used): " .. table.concat(miss, ",", 1, math.min(#miss, 5))) end
end }

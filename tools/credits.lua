-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Credit check for the build (the user's rule, 2026-11-27: "if we use a site credit them ONE time"):
-- CREDITS.txt holds ONE entry per source site (name, licence, link), never a line per page. A pack passes when
-- every site it uses has its entry: the sites of its `credits` URLs (the per-page list stays in the readable pack
-- source as our notes) and the sites behind its steps' `src` tags.
-- Use: local CR = dofile("tools/credits.lua"); local errs = CR.Problems(pack, routes, creditsText, name)
local CR = {}

-- src tag -> the site's link as CREDITS.txt writes it ("own" / "lookup" / placeholders need no site entry)
CR.SRC_SITES = {
    wiki = "warcraft.wiki.gg",
    cmangos = "github.com/cmangos/classic-db",
    questie = "github.com/Questie/Questie",
    forevdb = "foreverdb.net",
}

-- The site part of a URL: the host, and for GitHub the owner / repository too (two projects can share the host).
function CR.SiteOf(url)
    local host, path = tostring(url):match("^%a+://([^/]+)(.*)$")
    if not host then return nil end
    host = host:lower():gsub("^www%.", "")
    if host == "github.com" then
        local owner, repo = path:match("^/([^/]+)/([^/#?]+)")
        if owner then return host .. "/" .. owner .. "/" .. repo end
    end
    return host
end

local function Each(routes, fn)
    local function List(t) return type(t) == "table" and t or {} end
    for _, r in ipairs(List(routes)) do
        for _, s in ipairs(List(type(r) == "table" and r.steps)) do
            if type(s) == "table" then
                fn(s)
                for _, w in ipairs(List(s.onWay)) do if type(w) == "table" then fn(w) end end
            end
        end
    end
end

-- Problems as text lines (empty = fine). One line per missing site, not per URL.
function CR.Problems(pack, routes, creditsText, name)
    local text, missing, out = (creditsText or ""):lower(), {}, {}
    local function Need(site, why)
        if site and not text:find(site:lower(), 1, true) and not missing[site] then
            missing[site] = true
            out[#out + 1] = ("%s: credits: no entry for %s in CREDITS.txt (%s); add ONE line for the site"):format(name, site, why)
        end
    end
    for _, url in ipairs(pack.credits or {}) do
        local site = CR.SiteOf(url)
        if not site then out[#out + 1] = name .. ": credits: not a link: " .. tostring(url) end
        Need(site, "credits list")
    end
    Each(routes, function(s)
        if type(s.src) == "string" then Need(CR.SRC_SITES[s.src], "src = \"" .. s.src .. "\"") end
    end)
    return out
end

return CR

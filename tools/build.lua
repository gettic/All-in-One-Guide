-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Compiles the readable pack sources (packs-src\*.lua) into readable rows (AllinOneGuide\Routes\*.lua).
-- The pack checker runs first; any error stops the build. Same source, same bytes (LF line ends).
-- Also builds the smart arrow's connectors (packs-src\connectors\ -> Routes\Connectors.lua, tools\connectors.lua)
-- and writes each step's connector room (`room`) into its row.
-- Run (from the repository folder; tools\build.ps1 does this):
--   luajit tools/build.lua [--check] [--out <folder>] [--all] [--addon AllinOneGuide] [--words <file>] [packs-src/x.lua ...]
--   --check: write nothing, fail when a compiled file differs from its source (or is missing).
--   --out: write to another folder (a trial build); packs not in the .toc yet are skipped, as always.
--   --all: also build the packs not in the .toc yet (their problems then fail the build).
local argv = { ... }
local toolsDir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tools"
local PC = assert(loadfile(toolsDir .. "/packcheck.lua"))("--lib", toolsDir)
local L = PC.Lib()

local opts = { addon = "AllinOneGuide", files = {}, exploits = "packs-src/known-exploits.lua" }
local i = 1
while i <= #argv do
    local a = argv[i]
    if a == "--check" then
        opts.check = true
        i = i + 1
    elseif a == "--all" then
        opts.all = true
        i = i + 1
    elseif a == "--out" or a == "--addon" or a == "--words" or a == "--exploits" then
        opts[a:sub(3)] = argv[i + 1]
        i = i + 2
    else
        opts.files[#opts.files + 1] = a
        i = i + 1
    end
end
opts.out = opts.out or (opts.addon .. "/Routes")
if #opts.files == 0 then
    for _, f in ipairs(L.ListDir("packs-src", "lua")) do opts.files[#opts.files + 1] = "packs-src/" .. f end
end

local ns = L.AddonParts(opts.addon)
local exploits = assert(L.LoadData(opts.exploits))
local words = PC.LoadWords(opts.words)
local credits = L.ReadFile(opts.addon .. "/CREDITS.txt") or ""
local toc = L.ReadFile(opts.addon .. "/AllinOneGuide_Forever.toc") or ""

local failed, built, same, skipped = 0, 0, 0, 0
-- smart arrow connectors (packs-src\connectors\): the step rules in the checker, and step.room in the rows
local connectors = PC.Connectors()
for _, f in ipairs(opts.files) do
    local pack, err = L.LoadData(f)
    if not pack then
        print("ERROR " .. f .. ": " .. tostring(err))
        failed = failed + 1
    elseif L.IsPack(pack) then
        local errs, _, routes = PC.Check(pack, { ns = ns, exploits = exploits, words = words, name = f,
            connectors = connectors })
        if connectors then PC.CC().SetRooms(routes, connectors) end
        local src = f:match("([^/\\]+)$")
        local outName = L.OutName(pack)
        if L.UsesWiki(routes) and #(pack.credits or {}) == 0 then
            errs[#errs + 1] = f .. ": header: wiki facts but no credits list"
        end
        for _, url in ipairs(pack.credits or {}) do
            if not credits:find(url, 1, true) then
                errs[#errs + 1] = f .. ": credits: " .. url .. " is not in CREDITS.txt"
            end
        end
        if not outName:match("^[%w%-_]+%.lua$") then errs[#errs + 1] = f .. ": header: bad file name" end
        -- a pack whose compiled file isn't in the .toc yet doesn't ship: work in progress. It is still
        -- checked (and reported), but it doesn't fail the build and isn't written. The same with --out (a trial
        -- build to another folder); --all builds the unshipped packs too (and then their problems fail it).
        local shipped = opts.all or toc:find("Routes\\" .. outName, 1, true) ~= nil
        if not shipped then
            print(("SKIP %s: not in the .toc yet (%d problem(s) to fix before it ships)"):format(f, #errs))
            errs = {}
            pack = nil
        end
        for _, e in ipairs(errs) do print("ERROR " .. e) end
        if not pack then
            skipped = skipped + 1
        elseif #errs > 0 then
            failed = failed + 1
        else
            local text = L.Compile(ns, pack, routes, src)
            local path = opts.out .. "/" .. outName
            local old = L.ReadFile(path)
            if old == text then
                same = same + 1
            elseif opts.check then
                print("DIFFERS " .. path .. (old and "" or " (missing)") .. ": run tools\\build.ps1")
                failed = failed + 1
            else
                local fh = io.open(path, "wb")
                if not fh then
                    -- first build: make the output folder (one level), then try again
                    local dir = opts.out
                    if package.config:sub(1, 1) == "\\" then dir = dir:gsub("/", "\\") end
                    os.execute('mkdir "' .. dir .. '"')
                    fh = assert(io.open(path, "wb"))
                end
                fh:write(text)
                fh:close()
                built = built + 1
                print("built " .. path)
            end
            if opts.out == opts.addon .. "/Routes" and not toc:find("Routes\\" .. outName, 1, true) then
                print("NOTE add 'Routes\\" .. outName .. "' to the .toc")
            end
        end
    end
end
-- smart arrow connectors -> <out>\Connectors.lua (tools\connectors.lua: its own checks; --check compares)
do
    local code = PC.CC().Run({ addon = opts.addon, out = opts.out .. "/Connectors.lua", check = opts.check,
        exploits = opts.exploits })
    if code ~= 0 then failed = failed + 1 end
end
-- text style lint of the addon's own texts (tools\textlint.lua; v0.1.1): any error fails the build
local TL = assert(loadfile(toolsDir .. "/textlint.lua"))("--lib", toolsDir)
local en, da = TL.LoadLocales(opts.addon)
if en then
    local lerrs = TL.LintLocale(TL.Rules(), en, da, words)
    for _, e in ipairs(lerrs) do print("ERROR locale " .. e) end
    if #lerrs > 0 then failed = failed + 1 end
end
print(string.format("build: %d built, %d unchanged, %d failed%s", built, same, failed,
    skipped > 0 and (", " .. skipped .. " not shipped yet") or ""))
if failed > 0 then os.exit(1) end

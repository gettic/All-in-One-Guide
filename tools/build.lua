-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Compiles the readable pack sources (packs-src\*.lua) into readable rows in the guide pack addons (v0.2.5):
-- <folder>\Routes\*.lua next to AllinOneGuide\, one folder per entry of tools\data\pack-folders.lua, each with a
-- generated .toc (LoadOnDemand, depends on AllinOneGuide), LICENSE and CREDITS.txt; plus the index
-- AllinOneGuide\Data\KnownPacks.lua. The pack checker runs first; any error stops the build. Every compiled pack
-- file must pass the T29 scan (plain data only, packlib ScanOutput). Same source, same bytes (LF line ends).
-- Also builds the smart arrow's connectors (packs-src\connectors\ -> AllinOneGuide\Routes\Connectors.lua,
-- tools\connectors.lua) and writes each step's connector room (`room`) into its row. The spawn spots
-- (packs-src\spots\ -> AllinOneGuide\Routes\Spots.lua, tools\import\spots.lua) too.
-- Run (from the repository folder; tools\build.ps1 does this):
--   luajit tools/build.lua [--check] [--out <folder>] [--all] [--addon AllinOneGuide] [--words <file>] [packs-src/x.lua ...]
--   --check: write nothing, fail when a generated file differs from its source (or is missing).
--   --out: a trial build: every folder goes under <folder>\ (<folder>\AllinOneGuide\..., <folder>\AllinOneGuide_Alliance\...).
--   --all: also build the packs not in pack-folders.lua yet, into their faction's folder (their problems then fail).
local argv = { ... }
local toolsDir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tools"
local PC = assert(loadfile(toolsDir .. "/packcheck.lua"))("--lib", toolsDir)
local L = PC.Lib()
local CR = assert(loadfile(toolsDir .. "/credits.lua"))()

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
-- the main addon's generated files (Routes\Connectors.lua, Routes\Spots.lua, Data\KnownPacks.lua): in the addon,
-- or with --out under <out>\AllinOneGuide\
local mainOut = opts.out and (opts.out .. "/" .. (opts.addon:match("([^/\\]+)$") or opts.addon)) or opts.addon
if #opts.files == 0 then
    for _, f in ipairs(L.ListDir("packs-src", "lua")) do opts.files[#opts.files + 1] = "packs-src/" .. f end
end

local ns = L.AddonParts(opts.addon)
local exploits = assert(L.LoadData(opts.exploits))
local words = PC.LoadWords(opts.words)
local credits = L.ReadFile(opts.addon .. "/CREDITS.txt") or ""
local toc = L.ReadFile(opts.addon .. "/AllinOneGuide_Forever.toc") or ""

local failed, built, same, skipped = 0, 0, 0, 0
-- v0.2.5 pack folders (tools\data\pack-folders.lua): which packs ship, and in which LoadOnDemand addon
local folders = assert(L.LoadData(toolsDir .. "/data/pack-folders.lua"))
local folderOf, folderByFaction = {}, {}
-- Addon Manager v0.24.0 rules: folder AllinOneGuide_<Word>, .toc <folder>_Forever.toc (written below), tag
-- <word>-v<version> with a version that starts with a digit; the zip is <folder>-v<version>.zip (check-zip.ps1)
for _, fd in ipairs(folders) do
    local word = type(fd.folder) == "string" and fd.folder:match("^AllinOneGuide_(%a+)$")
    if not word then print("ERROR pack-folders: bad folder name " .. tostring(fd.folder)) failed = failed + 1 end
    if not (type(fd.version) == "string" and fd.version:match("^%d+%.%d+%.%d+[%w%.%-]*$")) then
        print("ERROR pack-folders: " .. tostring(fd.folder) .. ": version must start with a digit (x.y.z)") failed = failed + 1
    end
    if word and fd.tag ~= word:lower() .. "-v" then
        print("ERROR pack-folders: " .. fd.folder .. ": tag must be '" .. word:lower() .. "-v'") failed = failed + 1
    end
end
for _, fd in ipairs(folders) do
    fd.files, fd.ids = {}, {}
    folderByFaction[fd.faction] = folderByFaction[fd.faction] or fd
    for _, id in ipairs(fd.packs or {}) do folderOf[id] = fd end
end
-- where a folder's files go: next to the main addon (repository root), or under --out
local function Root(folder)
    if opts.out then return opts.out .. "/" .. folder end
    return (opts.addon:match("^(.*)[/\\][^/\\]+$") and (opts.addon:match("^(.*)[/\\][^/\\]+$") .. "/") or "") .. folder
end
local interface = toc:match("## Interface: (%d+)") or "16001"
-- writes (or, with --check, compares) one generated file; makes its folder (two levels) on first use
local function Out(path, text)
    local old = L.ReadFile(path)
    if old == text then
        same = same + 1
        return
    end
    if opts.check then
        print("DIFFERS " .. path .. (old and "" or " (missing)") .. ": run tools\\build.ps1")
        failed = failed + 1
        return
    end
    local fh = io.open(path, "wb")
    if not fh then
        local dir = path:match("^(.*)[/\\][^/\\]+$")
        if package.config:sub(1, 1) == "\\" then dir = dir:gsub("/", "\\") end
        os.execute('mkdir "' .. dir .. '" 2>nul')
        fh = assert(io.open(path, "wb"))
    end
    fh:write(text)
    fh:close()
    built = built + 1
    print("built " .. path)
end
local shippedHeaders = {}   -- { id, folder, header, routes } of every pack built (KnownPacks, the chain check)
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
        -- one CREDITS.txt entry per source site, not per page (tools\credits.lua; the user's rule, 2026-11-27).
        -- A pack's own `credits` list (per page) is optional: it stays in the readable source as notes.
        for _, e in ipairs(CR.Problems(pack, routes, credits, f)) do errs[#errs + 1] = e end
        if not outName:match("^[%w%-_]+%.lua$") then errs[#errs + 1] = f .. ": header: bad file name" end
        -- a pack that isn't listed in tools\data\pack-folders.lua doesn't ship: work in progress. It is still
        -- checked (and reported), but it doesn't fail the build and isn't written; --all builds the unshipped packs
        -- too, into their faction's folder (and then their problems fail it).
        local fd = folderOf[pack.id] or (opts.all and folderByFaction[pack.faction]) or nil
        if fd and fd.faction ~= pack.faction then
            errs[#errs + 1] = f .. ": header: faction " .. tostring(pack.faction) .. " in the " .. fd.folder .. " folder"
        end
        if not fd then
            print(("SKIP %s: not in tools\\data\\pack-folders.lua yet (%d problem(s) to fix before it ships)"):format(f, #errs))
            errs = {}
            pack = nil
        end
        if pack then
            local text = L.Compile(ns, pack, routes, src)
            for _, e in ipairs(L.ScanOutput(text, fd.folder .. "/Routes/" .. outName)) do errs[#errs + 1] = "T29 " .. e end
            pack.compiled = text
        end
        for _, e in ipairs(errs) do print("ERROR " .. e) end
        if not pack then
            skipped = skipped + 1
        elseif #errs > 0 then
            failed = failed + 1
        else
            Out(Root(fd.folder) .. "/Routes/" .. outName, pack.compiled)
            fd.files[#fd.files + 1] = "Routes\\" .. outName
            fd.ids[#fd.ids + 1] = pack.id
            shippedHeaders[#shippedHeaders + 1] = { id = pack.id, folder = fd.folder, header = pack, routes = routes }
            if toc:find("Routes\\" .. outName, 1, true) then
                print("ERROR the main .toc still lists Routes\\" .. outName .. ": it ships in " .. fd.folder .. " now")
                failed = failed + 1
            end
        end
    end
end
-- the pack folders: .toc (generated), LICENSE and CREDITS.txt (copies: each zip carries its licence and credits)
local license = L.ReadFile("LICENSE")
for _, fd in ipairs(folders) do
    if #fd.files > 0 then
        local root = Root(fd.folder)
        Out(root .. "/" .. fd.folder .. "_Forever.toc", L.PackToc(fd, interface, fd.files, fd.ids))
        if license then Out(root .. "/LICENSE", license) end
        Out(root .. "/CREDITS.txt", credits)
    end
end
-- the chain check over every pack built (tools\packcheck.lua): joins targets, must-do quests per faction
if #shippedHeaders > 0 then
    local cerrs, cwarns = PC.ChainCheck(shippedHeaders)
    for _, w in ipairs(cwarns) do print("WARN chain " .. w) end
    for _, e in ipairs(cerrs) do print("ERROR chain " .. e) end
    if #cerrs > 0 then failed = failed + 1 end
end
-- the index the guide reads without loading the folders -> <addon>\Data\KnownPacks.lua
Out(mainOut .. "/Data/KnownPacks.lua", L.KnownPacks(folders, shippedHeaders))
if not toc:find("Data\\KnownPacks.lua", 1, true) then print("NOTE add 'Data\\KnownPacks.lua' to the main .toc") end
-- smart arrow connectors -> <out>\Connectors.lua (tools\connectors.lua: its own checks; --check compares)
do
    if opts.out and not opts.check then
        local dir = mainOut .. "/Routes"
        if package.config:sub(1, 1) == "\\" then dir = dir:gsub("/", "\\") end
        os.execute('mkdir "' .. dir .. '" 2>nul')
    end
    local code = PC.CC().Run({ addon = opts.addon, out = mainOut .. "/Routes/Connectors.lua", check = opts.check,
        exploits = opts.exploits })
    if code ~= 0 then failed = failed + 1 end
end
-- spawn spots (packs-src\spots\*.lua, tools\import\spots.lua) -> <out>\Spots.lua: checked, then compiled into one
-- file; --check compares
do
    local SP = assert(loadfile(toolsDir .. "/import/spots.lua"))("--lib", toolsDir)
    local files, bad = {}, false
    for _, f in ipairs(L.ListDir("packs-src/spots", "lua")) do
        local path = "packs-src/spots/" .. f
        local d, err = L.LoadData(path)
        local errs = d and SP.Check(d, path) or { path .. ": " .. tostring(err) }
        for _, e in ipairs(errs) do print("ERROR spots " .. e) end
        if #errs > 0 then bad = true else files[#files + 1] = path end
    end
    if bad then
        failed = failed + 1
    elseif #files > 0 then
        -- spots are per mob and map (shared by every pack), so they stay in the main addon
        Out(mainOut .. "/Routes/Spots.lua", SP.Compile(files))
    end
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

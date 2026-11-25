# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 gettic
# Builds the guide packs: packs-src\*.lua -> AllinOneGuide\Routes\*.lua (readable rows), after the pack checker.
# Needs LuaJIT (https://luajit.org) as `luajit` on the PATH, or -LuaJit <path to luajit.exe>.
# Run from anywhere:  powershell -NoProfile -File tools\build.ps1 [-Check] [-Words <file>] [-Out <folder>]
#   -Check   write nothing; fail when a compiled file is out of date
param([switch]$Check, [string]$Words, [string]$Out, [string]$LuaJit)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $LuaJit) {
    $cmd = Get-Command luajit -ErrorAction SilentlyContinue
    if ($cmd) { $LuaJit = $cmd.Source }
    elseif (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\LuaJIT\bin\luajit.exe')) {
        $LuaJit = Join-Path $env:LOCALAPPDATA 'Programs\LuaJIT\bin\luajit.exe'
    } else { throw 'LuaJIT not found: put luajit on the PATH or pass -LuaJit <path>' }
}
$argList = @('tools/build.lua')
if ($Check) { $argList += '--check' }
if ($Words) { $argList += @('--words', $Words) }
if ($Out) { $argList += @('--out', $Out) }
Push-Location $repo
try {
    & $LuaJit @argList
    $code = $LASTEXITCODE
} finally { Pop-Location }
exit $code

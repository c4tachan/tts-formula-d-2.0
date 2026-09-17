<#
.SYNOPSIS
    One-time machine setup: make require("fd.…") resolvable by the TTS extension.

.DESCRIPTION
    The extension builds its module search path from three sources:

        ~/Documents/Tabletop Simulator       always
        TTSLua.includeOtherFilesPaths        workspace setting
        each open VS Code workspace folder   whatever is open

    The last two depend on VS Code having this repo open as its workspace root,
    which is easy to get wrong -- entry scripts are usually opened from the temp
    folder instead. Junctioning src/fd into the Documents folder makes module
    resolution work regardless of which folder is open.

    Safe to re-run.

.EXAMPLE
    pwsh tools/setup-dev.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repo 'src\fd'
# Hard-coded in the extension as homedir()/Documents/Tabletop Simulator; it is
# not OneDrive-aware, so do not substitute a redirected Documents folder.
$docs = Join-Path $env:USERPROFILE 'Documents\Tabletop Simulator'
$link = Join-Path $docs 'fd'

if (-not (Test-Path $target)) { throw "Missing module tree: $target" }

if (-not (Test-Path $docs)) {
    New-Item -ItemType Directory -Path $docs -Force | Out-Null
    Write-Host "created $docs" -ForegroundColor Green
}

$existing = Get-Item $link -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Target -and ($existing.Target -contains $target)) {
        Write-Host "junction already correct: $link" -ForegroundColor DarkGray
    }
    else {
        throw "$link already exists and does not point at $target. Remove it and re-run."
    }
}
else {
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Write-Host "junction $link -> $target" -ForegroundColor Green
}

$probe = Join-Path $link 'data\maps.lua'
if (Test-Path $probe) {
    Write-Host "ok: require('fd.data.maps') resolves" -ForegroundColor Green
}
else {
    throw "Junction created but $probe is not readable."
}

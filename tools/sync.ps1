<#
.SYNOPSIS
    Move entry scripts between this repo and the folder the TTS extension watches.

.DESCRIPTION
    The Tabletop Simulator Lua extension reads and writes scripts in a temp
    folder that Windows may clear at any time, so the repo is the source of
    truth. Push before "Save & Play"; pull after editing in game or after
    "Get Lua Scripts".

    Generated files are skipped on pull so a round trip through TTS cannot
    overwrite them with its bundled output -- regenerate them instead with
    tools/extract/gen_registry.py. Pass -Force to pull them anyway.

.EXAMPLE
    pwsh tools/sync.ps1 push
    pwsh tools/sync.ps1 pull
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('push', 'pull', 'status')]
    [string]$Direction,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $repo 'src\entry'
$tts = Join-Path $env:TEMP 'TabletopSimulator\Tabletop Simulator Lua'

# Regenerate these from maps.json rather than pulling them back out of TTS.
$generated = @('Custom Board.9e2fe8.xml')

if (-not (Test-Path $tts)) {
    throw "TTS script folder not found: $tts`nOpen the mod in Tabletop Simulator and run 'Get Lua Scripts' once."
}

function Copy-Set {
    param([string]$From, [string]$To, [string[]]$Skip)

    $copied = 0
    $skipped = 0
    foreach ($f in Get-ChildItem -Path $From -File -Include '*.lua', '*.xml' -Recurse) {
        if ($Skip -contains $f.Name) {
            Write-Host ("  skip  {0}  (generated)" -f $f.Name) -ForegroundColor DarkYellow
            $skipped++
            continue
        }
        $dest = Join-Path $To $f.Name
        $same = (Test-Path $dest) -and
                ((Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash)
        if ($same) { continue }
        Copy-Item $f.FullName $dest -Force
        Write-Host ("  copy  {0}" -f $f.Name) -ForegroundColor Green
        $copied++
    }
    Write-Host ("{0} file(s) copied, {1} skipped, rest already identical." -f $copied, $skipped)
}

switch ($Direction) {
    'push' {
        Write-Host "repo -> TTS  ($tts)" -ForegroundColor Cyan
        Copy-Set -From $entry -To $tts -Skip @()
        Write-Host "Now run 'TTSLua: Save And Play' in VS Code." -ForegroundColor Cyan
    }
    'pull' {
        Write-Host "TTS -> repo  ($entry)" -ForegroundColor Cyan
        Copy-Set -From $tts -To $entry -Skip $(if ($Force) { @() } else { $generated })
    }
    'status' {
        Write-Host "repo : $entry"
        Write-Host "tts  : $tts`n"
        foreach ($f in Get-ChildItem -Path $entry -File -Include '*.lua', '*.xml' -Recurse) {
            $dest = Join-Path $tts $f.Name
            $state = if (-not (Test-Path $dest)) { 'missing in TTS' }
                     elseif ((Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash) { 'same' }
                     else { 'DIFFERS' }
            Write-Host ("  {0,-14} {1}" -f $state, $f.Name)
        }
    }
}

# ==============================================
# ISMD Compose Wrapper (PowerShell)
# ==============================================
# Ergonomic frontend over the modular docker-compose stack.
#
# Usage:
#   .\compose.ps1 up                            # BE stack, all pulled from GHCR
#   .\compose.ps1 up --frontends                # also run containerized frontends
#   .\compose.ps1 up --build tool-be            # build tool backend locally
#   .\compose.ps1 up --build tool-be fuseki     # build multiple targets
#   .\compose.ps1 up --build all                # build everything locally
#   .\compose.ps1 up --no-tool-be               # BE dev mode (skip tool BE)
#   .\compose.ps1 down                          # tear down
#   .\compose.ps1 logs -f backend               # pass-through to docker compose
#   .\compose.ps1 ps
#
# Build targets:
#   tool-be, validator-be, fuseki, tool-fe, validator-fe, all
#
# Repo path overrides (read from .env or shell env):
#   VALIDATOR_BACKEND_PATH   (default: ../ismd-validator-backend)
#   TOOL_BACKEND_PATH        (default: ../ismd-tool-backend)
#   VALIDATOR_FRONTEND_PATH  (default: ../ismd-validator-frontend)
#   TOOL_FRONTEND_PATH       (default: ../ismd-tool-frontend)
# ==============================================

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# Load .env if present (compose reads it too; this lets the script see paths).
if (Test-Path .env) {
    Get-Content .env | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
        }
    }
}

function Get-OrDefault($name, $default) {
    $v = [System.Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrEmpty($v)) { return $default }
    return $v
}

$validatorBackendPath  = Get-OrDefault 'VALIDATOR_BACKEND_PATH'  '../ismd-validator-backend'
$toolBackendPath       = Get-OrDefault 'TOOL_BACKEND_PATH'       '../ismd-tool-backend'
$validatorFrontendPath = Get-OrDefault 'VALIDATOR_FRONTEND_PATH' '../ismd-validator-frontend'
$toolFrontendPath      = Get-OrDefault 'TOOL_FRONTEND_PATH'      '../ismd-tool-frontend'

function Show-Usage {
    Get-Content $PSCommandPath | Select-Object -First 26 | Select-Object -Skip 1 |
        ForEach-Object { $_ -replace '^#\s?', '' }
    exit 0
}

if (-not $Command -or $Command -in @('-h', '--help')) { Show-Usage }

$composeFiles  = @('-f', 'docker-compose.yml')
$profileArgs   = @('--profile', 'full-backend')
$includeFE     = $false
$buildTargets  = @()
$passthrough   = @()

# Parse $Rest
$i = 0
while ($i -lt $Rest.Count) {
    $arg = $Rest[$i]
    switch -Regex ($arg) {
        '^--build$' {
            $i++
            while ($i -lt $Rest.Count -and -not $Rest[$i].StartsWith('-')) {
                $buildTargets += $Rest[$i]
                $i++
            }
            if ($buildTargets.Count -eq 0) {
                Write-Error '--build requires at least one target'
                exit 1
            }
        }
        '^--no-tool-be$' {
            $profileArgs = @()
            $i++
        }
        '^--frontends$' {
            $includeFE = $true
            $i++
        }
        '^(-h|--help)$' { Show-Usage }
        default {
            $passthrough += $arg
            $i++
        }
    }
}

if ($buildTargets -contains 'all') {
    $buildTargets = @('tool-be', 'validator-be', 'fuseki', 'tool-fe', 'validator-fe')
    $includeFE = $true
}

if ($buildTargets -contains 'tool-fe' -or $buildTargets -contains 'validator-fe') {
    $includeFE = $true
}

if ($includeFE) {
    $composeFiles += @('-f', 'docker-compose.frontends.yml')
}

foreach ($t in $buildTargets) {
    switch ($t) {
        'tool-be'      { $composeFiles += @('-f', "$toolBackendPath/docker-compose.build.yml") }
        'fuseki'       { $composeFiles += @('-f', "$toolBackendPath/docker-compose.fuseki-build.yml") }
        'validator-be' { $composeFiles += @('-f', "$validatorBackendPath/docker-compose.build.yml") }
        'tool-fe'      { $composeFiles += @('-f', "$toolFrontendPath/docker-compose.build.yml") }
        'validator-fe' { $composeFiles += @('-f', "$validatorFrontendPath/docker-compose.build.yml") }
        default {
            Write-Error "Unknown build target '$t'. Valid: tool-be, validator-be, fuseki, tool-fe, validator-fe, all"
            exit 1
        }
    }
}

$extra = @()
if ($Command -eq 'up' -and $buildTargets.Count -gt 0) {
    $extra += '--build'
}

$finalArgs = @($composeFiles + $profileArgs + @($Command) + $extra + $passthrough)
Write-Host ("docker compose " + ($finalArgs -join ' ')) -ForegroundColor Cyan
Write-Host ""

& docker compose @finalArgs
exit $LASTEXITCODE

# terraw - terraform wrapper. Just run it:
#   .\terraw.ps1 switch dev
#   .\terraw.ps1 plan -out=tfplan
#   .\terraw.ps1 apply tfplan
#   .\terraw.ps1 plan test          # switch to test, then plan
#   .\terraw.ps1 apply dev          # switch to dev, then apply
#   .\terraw.ps1 env
#
# Optional alias for less typing (per-shell):
#   Set-Alias terraw "$PWD\terraw.ps1"
#   then: terraw switch dev
#
# State (current env) persists in .terraw-env (gitignored).
#
# Secrets do NOT belong in .env.<env>. Any TF_VAR listed in .terraw-vault-map is
# pulled from ismd-kv-<env> into this process on every plan/apply and dies with it -
# never written to disk, echoed, or passed as an argument. An entry already set in
# the environment wins, so a one-off override still works.
# In a directory without environments/<env>/terraform.tfvars (e.g. shared-global),
# plan/apply pass through with no var-file - works as plain terraform.

param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RestArgs
)

if (-not $Command) { $Command = '' }

$ScriptDir = $PSScriptRoot
# Path as it would be typed from the cwd, e.g. ..\terraw.ps1 from keycloak-config.
$Invoked   = Resolve-Path -Relative $PSCommandPath
$StateFile = Join-Path $ScriptDir ".terraw-env"
$VaultMap  = Join-Path $ScriptDir ".terraw-vault-map"

# Names of mapped TF_VARs that could not be resolved. Gates apply; see Test-VaultGuard.
$script:VaultMissing = @()

# Env vars this run created. `& .\terraw.ps1` runs INSIDE the caller's session, so
# anything set with Set-Item env: outlives the script - Key Vault secrets included.
# Because an already-set variable wins over the vault, "plan dev" then "plan test" in
# one window gave test the DEV passwords. Everything recorded here is removed in the
# finally block at the bottom, however the script exits.
$script:SetByTerraw = @()

function Set-TerrawEnv {
    param([string]$Name, [string]$Value)
    if (-not (Test-Path "env:$Name")) { $script:SetByTerraw += $Name }
    Set-Item -Path "env:$Name" -Value $Value
}

function Get-CurrentEnv {
    if (Test-Path $StateFile) { (Get-Content $StateFile -Raw).Trim() } else { "" }
}

function Import-EnvFile {
    param([string]$EnvName)
    $envFile = Join-Path $ScriptDir ".env.$EnvName"
    if (-not (Test-Path $envFile)) {
        Write-Error "[terraw] ERROR: $envFile not found"
        return $false
    }
    $count = 0
    Get-Content $envFile | ForEach-Object {
        $name, $value = $_.Split('=', 2)
        if ($name -and $value) {
            Set-TerrawEnv $name $value
            $count++
        }
    }
    Write-Host "[terraw] loaded $count vars from .env.$EnvName"
    return $true
}

# Pull the Class B secrets listed in .terraw-vault-map out of ismd-kv-<env> and into
# this process. Deliberately not a file: the value only ever exists as a process
# environment variable that dies with the terraform run.
#
# Anything already set (or present in .env.<env>) is left alone, so an operator can
# still override one value for a single invocation without touching the vault.
function Resolve-VaultSecrets {
    param([string]$EnvName)

    $script:VaultMissing = @()
    if (-not (Test-Path $VaultMap)) { return }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Warning "[terraw] az CLI not found - skipping Key Vault resolution"
        return
    }

    $vault = "ismd-kv-$EnvName"
    $fetched = 0
    $preset = 0

    foreach ($line in (Get-Content $VaultMap)) {
        $line = $line.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith('#')) { continue }

        $parts = $line.Split('=', 2)
        if ($parts.Count -lt 2) { continue }
        $name = $parts[0].Trim()
        $secret = $parts[1].Trim()
        if (-not $name -or -not $secret) { continue }

        if ([Environment]::GetEnvironmentVariable($name)) {
            $preset++
            continue
        }

        # az writes the value to stdout and it goes straight into the variable -
        # no temp file, and never an argument to anything.
        $value = az keyvault secret show --vault-name $vault --name $secret --query value -o tsv 2>$null
        if ($value -is [array]) { $value = $value -join "`n" }
        if ([string]::IsNullOrWhiteSpace($value)) {
            $script:VaultMissing += "$name ($vault/$secret)"
            continue
        }

        Set-TerrawEnv $name $value
        Remove-Variable value
        $fetched++
    }

    Write-Host "[terraw] vault ${vault}: $fetched fetched, $preset already set, $($script:VaultMissing.Count) unresolved"
}

# Every sensitive root variable declares a default of "", so an unresolved secret does
# not fail - it applies an empty value. Refuse to let that reach a mutating command.
function Test-VaultGuard {
    param([string]$Cmd)

    if ($script:VaultMissing.Count -eq 0) { return $true }

    Write-Host "[terraw] unresolved Key Vault secrets:"
    foreach ($item in $script:VaultMissing) { Write-Host "[terraw]   - $item" }

    if ($Cmd -in 'apply', 'destroy', 'import') {
        Write-Warning "[terraw] refusing '$Cmd': these variables default to empty and would overwrite live values."
        Write-Warning "[terraw] the fetch runs as your 'az login' identity against the vault's access policy (not PIM)."
        Write-Warning "[terraw] check 'az account show', then that the secret exists in this env's vault."
        return $false
    }

    Write-Warning "[terraw] '$Cmd' is read-only, continuing - but it will read these as empty."
    return $true
}

# Resolve the per-env tfvars file relative to the current dir. Supports both
# layouts: the main state (environments/<env>/terraform.tfvars, run from root)
# and per-dir states like keycloak-config (<env>.tfvars, run from inside the dir).
# Returns the path if found, empty otherwise. shared-global has neither -> pass-through.
function Resolve-Tfvars {
    param([string]$EnvName)
    if (Test-Path "environments/$EnvName/terraform.tfvars") { return "environments/$EnvName/terraform.tfvars" }
    if (Test-Path "$EnvName.tfvars") { return "$EnvName.tfvars" }
    return ""
}

# .terraw-env lives next to this script; the selected workspace lives in the cwd's
# .terraform/environment. Nothing ties the two together, so a workspace selected any
# other way (bare terraform, another worktree's terraw) leaves them disagreeing - and
# plan then applies <env> variables to another env's state. Seen 2026-09-11: workspace
# dev, .terraw-env test, plan proposed replacing every ismd-*-dev resource group.
#
# Only where an env tfvars resolves: shared-global has one state in the default
# workspace, so there is nothing to mismatch.
function Test-WorkspaceGuard {
    param([string]$EnvName, [string]$Cmd)
    if (-not (Resolve-Tfvars $EnvName)) { return $true }

    $ws = (terraform workspace show 2>$null | Out-String).Trim()
    if ($ws -eq $EnvName) { return $true }

    $shown = if ($ws) { $ws } else { '<unknown>' }
    $target = if ($ws) { $ws } else { 'another' }
    Write-Host "[terraw] ERROR: env/workspace mismatch in $(Get-Location)"
    Write-Host "[terraw]   .terraw-env         = $EnvName"
    Write-Host "[terraw]   terraform workspace = $shown"
    Write-Host "[terraw] refusing '$Cmd': it would apply $EnvName variables to $target state."
    Write-Host "[terraw] fix: $Invoked switch <env>   (e.g. $Invoked switch $EnvName)"
    return $false
}

# Several git worktrees of this repo exist side by side, each with its own
# shared-global/ and keycloak-config/. A plan from the wrong one quietly reports
# "No changes" (seen 2026-09-18), so every state-touching run says where it is.
function Write-CheckoutBanner {
    $top = git -C $ScriptDir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $top) { return }
    $branch = git -C $ScriptDir branch --show-current 2>$null
    if (-not $branch) { $branch = '<detached>' }
    $dirty = @(git -C $ScriptDir status --porcelain 2>$null).Count
    Write-Host "[terraw] checkout: $(Split-Path -Leaf $top) @ $branch ($dirty uncommitted)"
}

# An env name is anything with a .env.<name> next to this script - so "plan dev"
# switches, while "apply tfplan" (a saved plan file) still passes through.
function Test-KnownEnv {
    param([string]$Name)
    return ($Name -cmatch '^[a-z0-9-]+$') -and (Test-Path (Join-Path $ScriptDir ".env.$Name"))
}

# The persisting half of 'switch', for "plan <env>" / "apply <env>". Env vars and
# secrets are loaded by the plan/apply path itself, so they are not fetched twice.
# Only selects a workspace where an env tfvars resolves: shared-global has one state
# in the default workspace.
function Select-Env {
    param([string]$EnvName)
    Set-Content -Path $StateFile -Value $EnvName -NoNewline
    Write-Host "[terraw] env -> $EnvName (persisted to .terraw-env)"
    if (-not (Resolve-Tfvars $EnvName)) { return $true }
    terraform workspace select $EnvName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[terraw] ERROR: could not select workspace '$EnvName'"
        return $false
    }
    Write-Host "[terraw] workspace selected: $EnvName"
    return $true
}

# Pass-through subcommands that never read or write state, so they skip the guard.
# 'workspace' in particular must stay usable to repair a mismatch.
$StatelessCmds = 'init', 'workspace', 'version', '-version', '--version', 'fmt', 'validate',
                 'providers', 'get', 'graph', 'login', 'logout', 'metadata', 'test'

try {
switch ($Command) {
    'switch' {
        $envName = if ($RestArgs.Count -gt 0) { $RestArgs[0] } else { 'dev' }
        Write-Host "[terraw] switch -> $envName"
        if (-not (Import-EnvFile $envName)) { exit 1 }
        # Env vars die with this process - this call is here to fail fast on a missing
        # secret or a lapsed PIM activation, rather than at the next plan.
        Resolve-VaultSecrets $envName
        Test-VaultGuard $Command | Out-Null
        Set-Content -Path $StateFile -Value $envName -NoNewline
        Write-Host "[terraw] persisted current env to $StateFile"
        Write-Host "[terraw] running: terraform workspace select $envName"
        terraform workspace select $envName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[terraw] workspace selected: $envName"
        } else {
            Write-Warning "[terraw] could not select workspace '$envName' (run 'terraform workspace new $envName' if it doesn't exist yet)"
        }
    }
    'env' {
        $envName = Get-CurrentEnv
        $display = if ($envName) { $envName } else { '<unset>' }
        Write-Host "TERRAW_ENV=$display"
        Write-Host "STATE_FILE=$StateFile"
        Write-Host "CWD=$(Get-Location)"
        if ($envName) {
            $tfv = Resolve-Tfvars $envName
            if ($tfv) { Write-Host "tfvars   = $tfv (would auto-inject)" }
            else { Write-Host "tfvars   = none in $(Get-Location) (pass-through, e.g. shared-global)" }
            # Names only, and no vault call - this is a "what would happen" view.
            if (Test-Path $VaultMap) {
                Write-Host "vault    = ismd-kv-$envName, via .terraw-vault-map:"
                foreach ($line in (Get-Content $VaultMap)) {
                    $line = $line.Trim()
                    if (-not $line) { continue }
                    if ($line.StartsWith('#')) { continue }
                    $parts = $line.Split('=', 2)
                    if ($parts.Count -lt 2) { continue }
                    Write-Host "           $($parts[0].Trim()) <- $($parts[1].Trim())"
                }
            }
        }
    }
    { $_ -in 'plan', 'apply', 'destroy', 'refresh', 'import', 'console' } {
        Write-CheckoutBanner
        if ($RestArgs.Count -gt 0 -and (Test-KnownEnv $RestArgs[0])) {
            if (-not (Select-Env $RestArgs[0])) { exit 1 }
            $RestArgs = @($RestArgs | Select-Object -Skip 1)
        }
        $envName = Get-CurrentEnv
        if ($envName -eq 'prod' -and $Command -in 'apply', 'destroy', 'import') {
            Write-Warning "[terraw] *** PROD *** '$Command' against production"
        }
        $tfArgs = @()
        if (-not $envName) {
            Write-Warning "[terraw] no env set - running plain 'terraform $Command'. Run 'terraw switch <env>' first if you wanted env-scoped vars."
        } else {
            if (-not (Test-WorkspaceGuard $envName $Command)) { exit 1 }
            if (-not (Import-EnvFile $envName)) { exit 1 }
            Resolve-VaultSecrets $envName
            if (-not (Test-VaultGuard $Command)) { exit 1 }
            $tfv = Resolve-Tfvars $envName
            if ($tfv) {
                $tfArgs += "-var-file=$tfv"
                Write-Host "[terraw] $Command -> injecting -var-file=$tfv"
            } else {
                Write-Host "[terraw] $Command -> no env tfvars in $(Get-Location) (pass-through, e.g. shared-global)"
            }
        }
        terraform $Command @tfArgs @RestArgs
        exit $LASTEXITCODE
    }
    { $_ -in '', 'help', '-h', '--help' } {
        $envName = Get-CurrentEnv
        $display = if ($envName) { $envName } else { '<unset>' }
        Write-Host @"
Usage:
  .\terraw.ps1 switch <env>     Persist <env> + load .env.<env> + select workspace
  .\terraw.ps1 env              Show current env + tfvars resolution
  .\terraw.ps1 plan|apply|...   terraform with auto-injected -var-file
  .\terraw.ps1 plan <env> ...   switch to <env> first, then plan (same for apply etc.)
  .\terraw.ps1 <other>          Pass-through to terraform

Secrets: TF_VARs listed in .terraw-vault-map are read from ismd-kv-<env> into this
process on each run. Nothing is written to disk; apply is refused if one is missing.

Tip: Set-Alias terraw "$ScriptDir\terraw.ps1"

Current state:
  TERRAW_ENV=$display
  CWD=$(Get-Location)
"@
    }
    default {
        # Pass-through. Re-load env vars from current env so e.g. 'output'
        # or 'state list' have TF_VAR_* available.
        $envName = Get-CurrentEnv
        if ($envName) {
            if ($Command -notin $StatelessCmds -and -not (Test-WorkspaceGuard $envName $Command)) { exit 1 }
            Import-EnvFile $envName | Out-Null
            Resolve-VaultSecrets $envName | Out-Null
        }
        terraform $Command @RestArgs
        exit $LASTEXITCODE
    }
}
} finally {
    foreach ($name in $script:SetByTerraw) {
        Remove-Item -Path "env:$name" -ErrorAction SilentlyContinue
    }
}

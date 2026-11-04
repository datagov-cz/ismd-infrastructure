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
#
# EXCEPT when the values belong to a DIFFERENT environment. A .ps1 runs IN the caller's
# session, so Set-Item env: survives after terraw exits: after `switch dev`, dev's
# secrets sit in the shell, and a later `switch test` saw them "already set", skipped
# the vault, and planned TEST against DEV's secrets. On 2026-10-05 that produced
# `~ administrator_password` on the test Postgres server — an apply would have
# overwritten test's admin password with dev's, invisibly, because the value is masked.
# (terraw.sh does not have this failure mode: it runs as a child process.)
#
# TERRAW_SECRETS_ENV records which environment the resolved values came from. When it
# disagrees with the target environment, the stale values are refetched rather than
# honoured. A manual override still works: export the var yourself with no marker set,
# or stay within one environment.
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
    $stale = 0

    # Set by a previous terraw run in this session. Empty on a fresh shell.
    $secretsEnv = [Environment]::GetEnvironmentVariable('TERRAW_SECRETS_ENV')
    $crossEnv = $secretsEnv -and ($secretsEnv -ne $EnvName)
    if ($crossEnv) {
        Write-Host "[terraw] secrets in this session came from '$secretsEnv', target is '$EnvName' - refetching"
    }

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
            if ($crossEnv) {
                # Belongs to another environment - drop it and refetch below.
                Set-Item -Path "env:$name" -Value $null
                $stale++
            } else {
                $preset++
                continue
            }
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

    $staleNote = if ($stale -gt 0) { ", $stale refetched from another env" } else { "" }
    Write-Host "[terraw] vault ${vault}: $fetched fetched, $preset already set$staleNote, $($script:VaultMissing.Count) unresolved"

    # Mark which environment this session's secrets belong to, so the next switch can
    # tell stale values from a deliberate override.
    Set-Item -Path "env:TERRAW_SECRETS_ENV" -Value $EnvName
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

# -- Dev on/off switch ---------------------------------------------------------
# One value, ismd-kv-dev/dev-enabled ("true"|"false"), drives both roots that own a
# piece of dev: the infra root's dev workspace (replicas, uptime probe, alert
# suppression) and shared-global (the four dev App Gateway pools). It is read on
# every run of either, so a plain apply always matches the switch and never undoes
# it. Always from ismd-kv-dev, whatever env is selected - shared-global has no env.
#
# az queries here fetch JSON and filter in PowerShell: az.cmd goes through cmd.exe,
# which mangles JMESPath's &&, >, | and {} (see terraw.sh for the one-line forms).
$DevSwitchVault  = 'ismd-kv-dev'
$DevSwitchSecret = 'dev-enabled'
$DevApps  = @('ismd-validator-dev/ismd-validator-frontend-dev', 'ismd-validator-dev/ismd-validator-backend-dev',
              'ismd-tool-dev/ismd-tool-frontend-dev', 'ismd-tool-dev/ismd-tool-backend-dev',
              'ismd-tool-dev/ismd-tool-keycloak-dev', 'ismd-tool-dev/ismd-tool-fuseki-dev', 'ismd-ai-dev/ismd-ai-dev')
$DevPools = @('validator-dev-fe-pool', 'tool-dev-fe-pool', 'tool-dev-keycloak-pool', 'tool-dev-be-pool')
$FusekiRg  = 'ismd-tool-dev'
$FusekiApp = 'ismd-tool-fuseki-dev'

function Get-AzJson {
    $out = & az @args -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    return ($out | Out-String | ConvertFrom-Json)
}

# True where Terraform reads var.dev_enabled: shared-global, or the infra root on dev.
function Test-DevSwitchApplies {
    param([string]$EnvName)
    $sg = Join-Path $ScriptDir 'shared-global'
    if ((Test-Path $sg) -and ((Resolve-Path .).Path -eq (Resolve-Path $sg).Path)) { return $true }
    return ($EnvName -eq 'dev') -and ((Resolve-Tfvars $EnvName) -eq 'environments/dev/terraform.tfvars')
}

# Set TF_VAR_dev_enabled from the vault. An explicit value still wins (one-off
# override). Missing or not true|false -> recorded as unresolved, so Test-VaultGuard
# refuses apply: there is deliberately no default to fall back to.
function Resolve-DevSwitch {
    param([string]$EnvName)
    if (-not (Test-DevSwitchApplies $EnvName)) { return }
    $preset = [Environment]::GetEnvironmentVariable('TF_VAR_dev_enabled')
    if ($preset) {
        Write-Host "[terraw] dev switch: $preset (from the environment, not the vault)"
        return
    }
    $v = (az keyvault secret show --vault-name $DevSwitchVault --name $DevSwitchSecret --query value -o tsv 2>$null | Out-String).Trim()
    if ($v -in 'true', 'false') {
        Set-TerrawEnv 'TF_VAR_dev_enabled' $v
        $state = if ($v -eq 'true') { 'ON' } else { 'OFF' }
        Write-Host "[terraw] dev switch: $state ($DevSwitchVault/$DevSwitchSecret)"
    } else {
        $script:VaultMissing += "TF_VAR_dev_enabled ($DevSwitchVault/$DevSwitchSecret, must be true|false)"
    }
}

# Fuseki keeps a single-writer TDB2 lock on its Azure Files share. Switching off
# changes min_replicas, which creates a new revision; that revision first scales to
# the old replica count and can never take the lock - a deadlock. 'terraw dev off'
# deactivates the running revision first. Refuse a plain dev apply that would
# switch off while Fuseki still runs.
function Get-FusekiRunningRevisions {
    $revs = Get-AzJson containerapp revision list -g $FusekiRg -n $FusekiApp
    @($revs | Where-Object { $_.properties.active -and $_.properties.replicas -gt 0 } | ForEach-Object { $_.name })
}

function Test-FusekiGuard {
    param([string]$EnvName, [string]$Cmd)
    if ($Cmd -ne 'apply') { return $true }
    if (-not ($EnvName -eq 'dev' -and (Test-DevSwitchApplies $EnvName))) { return $true }
    if ([Environment]::GetEnvironmentVariable('TF_VAR_dev_enabled') -ne 'false') { return $true }
    if ([Environment]::GetEnvironmentVariable('TERRAW_FUSEKI_STOPPED') -eq '1') { return $true }
    if ((Get-FusekiRunningRevisions).Count -eq 0) { return $true }
    Write-Host "[terraw] ERROR: dev switch is OFF but $FusekiApp is still running."
    Write-Host "[terraw] Applying now would deadlock Fuseki on its TDB2 lock. Use: $Invoked dev off"
    return $false
}

function Show-DevStatus {
    $kv = (az keyvault secret show --vault-name $DevSwitchVault --name $DevSwitchSecret --query value -o tsv 2>$null | Out-String).Trim()
    if (-not $kv) { $kv = '<missing>' }
    Write-Host "dev switch ($DevSwitchVault/$DevSwitchSecret): $kv"
    Write-Host "gateway pools (address count):"
    foreach ($p in $DevPools) {
        $pool = Get-AzJson network application-gateway address-pool show -g ismd-shared-global --gateway-name ismd-app-gateway -n $p
        Write-Host "  ${p}: $(@($pool.backendAddresses).Count)"
    }
    Write-Host "apps (min replicas / running replicas):"
    foreach ($a in $DevApps) {
        $rg, $name = $a.Split('/')
        $app = Get-AzJson containerapp show -g $rg -n $name
        $reps = Get-AzJson containerapp replica list -g $rg -n $name
        Write-Host "  ${name}: $($app.properties.template.scale.minReplicas) / $(@($reps).Count)"
    }
    $wf = Get-AzJson resource show -g ismd-shared-dev -n logic-dia-uptime-dev --resource-type Microsoft.Logic/workflows
    Write-Host "uptime probe logic-dia-uptime-dev: $($wf.properties.state)"
    $apr = Get-AzJson resource show -g ismd-shared-dev -n apr-dia-env-off-dev --resource-type Microsoft.AlertsManagement/actionRules
    Write-Host "alert suppression apr-dia-env-off-dev enabled: $($apr.properties.enabled)"
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
            Resolve-DevSwitch ''
            if (-not (Test-VaultGuard $Command)) { exit 1 }
        } else {
            if (-not (Test-WorkspaceGuard $envName $Command)) { exit 1 }
            if (-not (Import-EnvFile $envName)) { exit 1 }
            Resolve-VaultSecrets $envName
            Resolve-DevSwitch $envName
            if (-not (Test-VaultGuard $Command)) { exit 1 }
            if (-not (Test-FusekiGuard $envName $Command)) { exit 1 }
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
    'dev' {
        $action = if ($RestArgs.Count -gt 0) { $RestArgs[0] } else { 'status' }
        if ($action -notin 'on', 'off', 'status') { Write-Host "Usage: $Invoked dev on|off|status"; exit 2 }
        if ($action -eq 'status') { Show-DevStatus; exit 0 }

        # Each toggle applies shared-global, i.e. rewrites the App Gateway that also
        # serves test and prod. From a branch missing other gateway changes, that apply
        # reverts them on prod. Refuse a dirty tree; make anything but an up-to-date
        # dev checkout an explicit choice.
        if (@(git -C $ScriptDir status --porcelain 2>$null).Count -gt 0) {
            Write-Host "[terraw] ERROR: uncommitted changes in $ScriptDir - commit or discard before 'dev $action'."
            exit 1
        }
        git -C $ScriptDir fetch -q origin dev 2>$null
        if ((git -C $ScriptDir rev-parse HEAD) -ne (git -C $ScriptDir rev-parse origin/dev 2>$null)) {
            Write-Warning "[terraw] checkout is $(git -C $ScriptDir branch --show-current), not an up-to-date origin/dev."
            Write-Warning "[terraw] The shared-global apply will push THIS branch's gateway config - including to prod's routes."
            if ((Read-Host "[terraw] Read both plans carefully. Continue? [y/N]") -ne 'y') { exit 1 }
        }

        $value = if ($action -eq 'on') { 'true' } else { 'false' }
        # The vault holds the DESIRED state. If an apply below is declined, the next
        # apply of either root (plain or 'dev $action') completes the switch.
        az keyvault secret set --vault-name $DevSwitchVault --name $DevSwitchSecret --value $value -o none
        if ($LASTEXITCODE -ne 0) { Write-Host "[terraw] ERROR: could not write $DevSwitchVault/$DevSwitchSecret"; exit 1 }
        Write-Host "[terraw] desired state: dev $action ($DevSwitchVault/$DevSwitchSecret=$value)"

        $self = Join-Path $ScriptDir 'terraw.ps1'
        $unfinished = "[terraw] stopped: dev is only partly switched $action. Run '$Invoked dev $action' again to finish."
        $applySg = {
            Write-Host "[terraw] -- shared-global (dev gateway pools) --"
            Push-Location (Join-Path $ScriptDir 'shared-global')
            try { & $self apply } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { Write-Host $unfinished; exit 1 }
        }
        $applyDev = {
            Write-Host "[terraw] -- dev workspace (apps, uptime probe, alerts) --"
            Push-Location $ScriptDir
            try { & $self apply dev } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { Write-Host $unfinished; exit 1 }
        }

        if ($action -eq 'off') {
            # Gateway first: traffic and probes stop before the apps go.
            . $applySg
            # Fuseki: stop the running revision so the new min-0 revision has no
            # replica count to match and never contends for the TDB2 lock.
            foreach ($rev in (Get-FusekiRunningRevisions)) {
                Write-Host "[terraw] deactivating Fuseki revision $rev (TDB2 lock)"
                az containerapp revision deactivate -g $FusekiRg -n $FusekiApp --revision $rev -o none
                if ($LASTEXITCODE -ne 0) { Write-Host $unfinished; exit 1 }
            }
            Set-TerrawEnv 'TERRAW_FUSEKI_STOPPED' '1'
            . $applyDev
        } else {
            # Apps first, so the gateway never routes to replicas that aren't up.
            . $applyDev
            . $applySg
        }
        Write-Host ""
        Show-DevStatus
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
  .\terraw.ps1 dev on|off       Switch dev on/off: sets $DevSwitchVault/$DevSwitchSecret, then
                                applies shared-global and the dev workspace (interactive plans)
  .\terraw.ps1 dev status       Switch value and live state (pools, replicas, probe, alerts)
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
        if ($Command -notin $StatelessCmds) { Resolve-DevSwitch $envName | Out-Null }
        terraform $Command @RestArgs
        exit $LASTEXITCODE
    }
}
} finally {
    foreach ($name in $script:SetByTerraw) {
        Remove-Item -Path "env:$name" -ErrorAction SilentlyContinue
    }
}

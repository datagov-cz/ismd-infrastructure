# terraw - terraform wrapper. Just run it:
#   .\terraw.ps1 switch dev
#   .\terraw.ps1 plan -out=tfplan
#   .\terraw.ps1 apply tfplan
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
$StateFile = Join-Path $ScriptDir ".terraw-env"
$VaultMap  = Join-Path $ScriptDir ".terraw-vault-map"

# Names of mapped TF_VARs that could not be resolved. Gates apply; see Test-VaultGuard.
$script:VaultMissing = @()

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
            Set-Item -Path "env:$name" -Value $value
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

        Set-Item -Path "env:$name" -Value $value
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
            $tfv = "environments/$envName/terraform.tfvars"
            if (Test-Path $tfv) { Write-Host "tfvars   = $tfv (would auto-inject)" }
            else { Write-Host "tfvars   = $tfv (NOT FOUND - pass-through)" }
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
        $envName = Get-CurrentEnv
        $tfArgs = @()
        if (-not $envName) {
            Write-Warning "[terraw] no env set - running plain 'terraform $Command'. Run 'terraw switch <env>' first if you wanted env-scoped vars."
        } else {
            if (-not (Import-EnvFile $envName)) { exit 1 }
            Resolve-VaultSecrets $envName
            if (-not (Test-VaultGuard $Command)) { exit 1 }
            $tfv = "environments/$envName/terraform.tfvars"
            if (Test-Path $tfv) {
                $tfArgs += "-var-file=$tfv"
                Write-Host "[terraw] $Command -> injecting -var-file=$tfv"
            } else {
                Write-Host "[terraw] $Command -> no $tfv in $(Get-Location) (pass-through, e.g. shared-global)"
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
            Import-EnvFile $envName | Out-Null
            Resolve-VaultSecrets $envName | Out-Null
        }
        terraform $Command @RestArgs
        exit $LASTEXITCODE
    }
}

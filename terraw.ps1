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

switch ($Command) {
    'switch' {
        $envName = if ($RestArgs.Count -gt 0) { $RestArgs[0] } else { 'dev' }
        Write-Host "[terraw] switch -> $envName"
        if (-not (Import-EnvFile $envName)) { exit 1 }
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
        }
    }
    { $_ -in 'plan', 'apply', 'destroy', 'refresh', 'import', 'console' } {
        $envName = Get-CurrentEnv
        $tfArgs = @()
        if (-not $envName) {
            Write-Warning "[terraw] no env set - running plain 'terraform $Command'. Run 'terraw switch <env>' first if you wanted env-scoped vars."
        } else {
            if (-not (Import-EnvFile $envName)) { exit 1 }
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
        if ($envName) { Import-EnvFile $envName | Out-Null }
        terraform $Command @RestArgs
        exit $LASTEXITCODE
    }
}

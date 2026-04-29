# Usage: . .\load_env_vars.ps1 [dev|test|prod]
# Loads .env.<environment> and switches Terraform workspace to match.
# Defaults to dev if no argument given.

param([string]$Environment = "dev")

$EnvFile = ".env.$Environment"

if (-not (Test-Path $EnvFile)) {
    Write-Error "Error: $EnvFile not found"
    return
}

Get-Content $EnvFile | ForEach-Object {
    $name, $value = $_.split('=')
    if ($name -and $value) {
        Set-Item -Path "env:$name" -Value $value
    }
}

Write-Host "Loaded $EnvFile"

terraform workspace select $Environment 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Switched to workspace: $Environment"
} else {
    Write-Warning "Could not switch workspace to $Environment (run 'terraform workspace new $Environment' if it doesn't exist yet)"
}

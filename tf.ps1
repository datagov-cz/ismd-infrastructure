param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$TerraformArgs = @()
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Set subscription ID from Azure CLI
Write-Host "Setting up Azure subscription..."
$subscriptionId = az account show --query "id" -o tsv
if (-not $subscriptionId) {
    Write-Error "Not logged into Azure. Please run 'az login' first."
    exit 1
}

# Set environment variable for current session
$env:ARM_SUBSCRIPTION_ID = $subscriptionId
Write-Host "Using subscription ID: $subscriptionId"

# Initialize Terraform if not already done
if (-not (Test-Path ".terraform")) {
    Write-Host "Initializing Terraform..."
    terraform init
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Terraform initialization failed"
        exit 1
    }
}

# Execute Terraform command
Write-Host "Running 'terraform $($TerraformArgs -join ' ')' for environment: $Environment"

# Add environment-specific variable
$env:TF_VAR_environment = $Environment

# Run Terraform with all arguments
terraform @TerraformArgs

# Capture and return the exit code
$exitCode = $LASTEXITCODE

# Clean up environment variables if needed
Remove-Item Env:\ARM_SUBSCRIPTION_ID -ErrorAction SilentlyContinue
Remove-Item Env:\TF_VAR_environment -ErrorAction SilentlyContinue

exit $exitCode

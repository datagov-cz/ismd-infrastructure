#!/bin/bash

# Default values
COMMAND=${1:-plan}
ENVIRONMENT=${2:-dev}

# Set error handling
set -euo pipefail

# Set subscription ID from Azure CLI
echo "Setting up Azure subscription..."
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: Not logged into Azure. Please run 'az login' first." >&2
    exit 1
fi

# Set environment variable for current session
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
echo "Using subscription ID: $SUBSCRIPTION_ID"

# Initialize Terraform if not already done
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
    if [ $? -ne 0 ]; then
        echo "Error: Terraform initialization failed" >&2
        exit 1
    fi
fi

# Execute Terraform command
echo "Running 'terraform $COMMAND' for environment: $ENVIRONMENT"

# Add environment-specific variables if needed
export TF_VAR_environment="$ENVIRONMENT"

# Run the Terraform command with all remaining arguments
shift 2  # Remove the first two arguments (command and environment)
terraform "$COMMAND" "$@"

# Capture and return the exit code
EXIT_CODE=$?

# Clean up environment variables if needed
unset ARM_SUBSCRIPTION_ID
unset TF_VAR_environment

exit $EXIT_CODE

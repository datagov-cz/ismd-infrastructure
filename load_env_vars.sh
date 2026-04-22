#!/usr/bin/env bash
# Usage: source load_env_vars.sh [dev|test|prod]
# Loads .env.<environment> and switches Terraform workspace to match.
# Defaults to dev if no argument given.

ENV="${1:-dev}"
ENV_FILE=".env.$ENV"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found" >&2
    return 1
fi

while IFS='=' read -r name value; do
    name="${name//$'\r'/}"
    value="${value//$'\r'/}"
    if [ -n "$name" ] && [ -n "$value" ]; then
        export "$name=$value"
    fi
done < "$ENV_FILE"

echo "Loaded $ENV_FILE"

terraform workspace select "$ENV" 2>/dev/null && echo "Switched to workspace: $ENV" || echo "Warning: could not switch workspace to $ENV (run 'terraform workspace new $ENV' if it doesn't exist yet)"

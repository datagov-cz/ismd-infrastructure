#!/usr/bin/env bash
# terraw — terraform wrapper. Just run it:
#   ./terraw.sh switch dev
#   ./terraw.sh plan -out=tfplan
#   ./terraw.sh apply tfplan
#   ./terraw.sh env
#
# Optional: add an alias for less typing —
#   alias terraw="$(pwd)/terraw.sh"      # bash/zsh
#   then: terraw switch dev
#
# State (current env) persists in .terraw-env (gitignored).
# In a directory without environments/<env>/terraform.tfvars (e.g. shared-global),
# plan/apply pass through with no var-file — works as plain terraform.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.terraw-env"

current_env() {
    [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo ""
}

load_env_file() {
    local env="$1"
    local env_file="$SCRIPT_DIR/.env.$env"
    if [ ! -f "$env_file" ]; then
        echo "[terraw] ERROR: $env_file not found" >&2
        return 1
    fi
    local count=0
    while IFS='=' read -r name value; do
        name="${name//$'\r'/}"
        value="${value//$'\r'/}"
        if [ -n "$name" ] && [ -n "$value" ]; then
            export "$name=$value"
            count=$((count + 1))
        fi
    done < "$env_file"
    echo "[terraw] loaded $count vars from .env.$env" >&2
}

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
    switch)
        env="${1:-dev}"
        echo "[terraw] switch → $env"
        load_env_file "$env" || exit 1
        echo "$env" > "$STATE_FILE"
        echo "[terraw] persisted current env to $STATE_FILE"
        echo "[terraw] running: terraform workspace select $env"
        if terraform workspace select "$env"; then
            echo "[terraw] workspace selected: $env"
        else
            echo "[terraw] WARN: could not select workspace '$env' — run 'terraform workspace new $env' if it doesn't exist yet" >&2
        fi
        ;;
    env)
        env="$(current_env)"
        echo "TERRAW_ENV=${env:-<unset>}"
        echo "STATE_FILE=$STATE_FILE"
        echo "CWD=$(pwd)"
        if [ -n "$env" ]; then
            tfv="environments/$env/terraform.tfvars"
            if [ -f "$tfv" ]; then
                echo "tfvars   = $tfv (would auto-inject)"
            else
                echo "tfvars   = $tfv (NOT FOUND — pass-through)"
            fi
        fi
        ;;
    plan|apply|destroy|refresh|import|console)
        env="$(current_env)"
        args=()
        if [ -z "$env" ]; then
            echo "[terraw] WARN: no env set — running plain 'terraform $cmd'. Run 'terraw switch <env>' first if you wanted env-scoped vars." >&2
        else
            load_env_file "$env" || exit 1
            tfv="environments/$env/terraform.tfvars"
            if [ -f "$tfv" ]; then
                args+=(-var-file="$tfv")
                echo "[terraw] $cmd → injecting -var-file=$tfv"
            else
                echo "[terraw] $cmd → no $tfv in $(pwd) (pass-through, e.g. shared-global)"
            fi
        fi
        exec terraform "$cmd" "${args[@]}" "$@"
        ;;
    ""|help|-h|--help)
        env="$(current_env)"
        cat <<EOF
Usage:
  ./terraw.sh switch <env>     Persist <env> + load .env.<env> + select workspace
  ./terraw.sh env              Show current env + tfvars resolution
  ./terraw.sh plan|apply|...   terraform with auto-injected -var-file
  ./terraw.sh <other>          Pass-through to terraform

Tip: alias terraw="$SCRIPT_DIR/terraw.sh"

Current state:
  TERRAW_ENV=${env:-<unset>}
  CWD=$(pwd)
EOF
        ;;
    *)
        # Pass-through. Still re-load env vars from current env so e.g. 'output'
        # or 'state list' have TF_VAR_* available.
        env="$(current_env)"
        [ -n "$env" ] && load_env_file "$env" >/dev/null 2>&1
        exec terraform "$cmd" "$@"
        ;;
esac

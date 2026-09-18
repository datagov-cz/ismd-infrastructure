#!/usr/bin/env bash
# terraw — terraform wrapper. Just run it:
#   ./terraw.sh switch dev
#   ./terraw.sh plan -out=tfplan
#   ./terraw.sh apply tfplan
#   ./terraw.sh plan test          # switch to test, then plan
#   ./terraw.sh apply dev          # switch to dev, then apply
#   ./terraw.sh env
#
# Optional: add an alias for less typing —
#   alias terraw="$(pwd)/terraw.sh"      # bash/zsh
#   then: terraw switch dev
#
# State (current env) persists in .terraw-env (gitignored).
#
# Auto-injected var-file resolves per directory:
#   - infra root:      environments/<env>/terraform.tfvars   (main state)
#   - keycloak-config: <env>.tfvars                          (run ../terraw.sh from inside)
#   - shared-global:   neither → pass-through (plain terraform)
# .env.<env> (TF_VAR_*) is loaded from the infra root regardless of cwd, so
# keycloak-config picks up the same vars from .env.<env> too.
#
# Secrets do NOT belong in .env.<env>. Any TF_VAR listed in .terraw-vault-map is
# pulled from ismd-kv-<env> into this process on every plan/apply and dies with it —
# never written to disk, echoed, or passed as an argument. An entry already set in
# the environment wins, so a one-off override still works.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.terraw-env"
VAULT_MAP="$SCRIPT_DIR/.terraw-vault-map"

# Names of mapped TF_VARs that could not be resolved. Gates apply; see vault_guard.
VAULT_MISSING=()

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
    # `|| [ -n "$name" ]` processes a final line that lacks a trailing newline,
    # which `read` otherwise returns non-zero on and the loop would skip.
    while IFS='=' read -r name value || [ -n "$name" ]; do
        name="${name//$'\r'/}"
        value="${value//$'\r'/}"
        if [ -n "$name" ] && [ -n "$value" ]; then
            export "$name=$value"
            count=$((count + 1))
        fi
    done < "$env_file"
    echo "[terraw] loaded $count vars from .env.$env" >&2
}

# Pull the Class B secrets listed in .terraw-vault-map out of ismd-kv-<env> and into
# this process. Deliberately not a file: the value only ever exists as a shell
# variable in the terraform process's own environment.
#
# Anything already exported (or present in .env.<env>) is left alone, so an operator
# can still override one value for a single invocation without touching the vault.
resolve_vault_secrets() {
    local env="$1"
    [ -f "$VAULT_MAP" ] || return 0
    if ! command -v az >/dev/null 2>&1; then
        echo "[terraw] WARN: az CLI not found — skipping Key Vault resolution" >&2
        return 0
    fi

    local vault="ismd-kv-$env"
    local fetched=0 preset=0
    VAULT_MISSING=()

    while IFS='=' read -r name secret || [ -n "$name" ]; do
        name="${name//$'
'/}"
        secret="${secret//$'
'/}"
        case "$name" in ''|'#'*) continue ;; esac
        [ -n "$secret" ] || continue

        if [ -n "${!name-}" ]; then
            preset=$((preset + 1))
            continue
        fi

        # Command substitution, not a temp file or an argument: az writes the value
        # to this subshell's stdout and it goes straight into the variable.
        #
        # tr -d '\r\n' is load-bearing too: under WSL the Windows az emits CRLF, and
        # command substitution strips trailing newlines but NOT carriage returns. The
        # secret would be exported as "value" — an invisible extra byte that made the
        # Keycloak provider fail with a bare 401 Unauthorized. Confirmed 2026-08-28.
        #
        # </dev/null is load-bearing: under WSL az reads stdin, which inside this
        # loop is the vault map itself. Without it az swallows the remaining lines,
        # so only the FIRST map entry is ever fetched — silently, since the rest are
        # never reached and never recorded as unresolved. A variable with
        # default = "" would then be applied empty with no prompt and no error.
        local value
        value="$(az keyvault secret show --vault-name "$vault" --name "$secret"                      --query value -o tsv 2>/dev/null </dev/null | tr -d '\r\n')"
        if [ -z "$value" ]; then
            VAULT_MISSING+=("$name ($vault/$secret)")
            continue
        fi
        # export is a builtin — the assignment never reaches the process list.
        export "$name=$value"
        unset value
        fetched=$((fetched + 1))
    done < "$VAULT_MAP"

    echo "[terraw] vault $vault: $fetched fetched, $preset already set, ${#VAULT_MISSING[@]} unresolved" >&2
}

# Every sensitive root variable declares `default = ""`, so an unresolved secret does
# not fail — it applies an empty value. Refuse to let that reach a mutating command.
vault_guard() {
    local cmd="$1"
    [ "${#VAULT_MISSING[@]}" -eq 0 ] && return 0

    echo "[terraw] unresolved Key Vault secrets:" >&2
    printf '[terraw]   - %s
' "${VAULT_MISSING[@]}" >&2

    case "$cmd" in
        apply|destroy|import)
            echo "[terraw] refusing '$cmd': these variables default to \"\" and would overwrite live values with empty." >&2
            echo "[terraw] the fetch runs as your 'az login' identity against the vault's access" >&2
            echo "[terraw] policy (not PIM). Check 'az account show', then the secret exists in $env." >&2
            return 1
            ;;
        *)
            echo "[terraw] '$cmd' is read-only, continuing — but it will read these as empty." >&2
            return 0
            ;;
    esac
}

# Resolve the per-env tfvars file relative to the current dir. Supports both
# layouts: the main state (environments/<env>/terraform.tfvars, run from root)
# and per-dir states like keycloak-config (<env>.tfvars, run from inside the dir).
# Prints the path if found, empty otherwise. shared-global has neither → pass-through.
resolve_tfvars() {
    local env="$1"
    if [ -f "environments/$env/terraform.tfvars" ]; then
        echo "environments/$env/terraform.tfvars"
    elif [ -f "$env.tfvars" ]; then
        echo "$env.tfvars"
    fi
}

# .terraw-env lives next to this script; the selected workspace lives in the cwd's
# .terraform/environment. Nothing ties the two together, so a workspace selected any
# other way (bare terraform, another worktree's terraw) leaves them disagreeing — and
# plan then applies <env> variables to another env's state. Seen 2026-09-11: workspace
# dev, .terraw-env test, plan proposed replacing every ismd-*-dev resource group.
#
# Only where an env tfvars resolves: shared-global has one state in the default
# workspace, so there is nothing to mismatch.
workspace_guard() {
    local env="$1"
    [ -n "$(resolve_tfvars "$env")" ] || return 0

    local ws
    ws="$(terraform workspace show 2>/dev/null | tr -d '\r\n')"
    [ "$ws" = "$env" ] && return 0

    echo "[terraw] ERROR: env/workspace mismatch in $(pwd)" >&2
    echo "[terraw]   .terraw-env         = $env" >&2
    echo "[terraw]   terraform workspace = ${ws:-<unknown>}" >&2
    echo "[terraw] refusing '$cmd': it would apply $env variables to ${ws:-another} state." >&2
    echo "[terraw] fix: $0 switch <env>   (e.g. $0 switch $env)" >&2
    return 1
}

# Pass-through subcommands that never read or write state, so they skip the guard.
# 'workspace' in particular must stay usable to repair a mismatch.
stateless_cmd() {
    case "$1" in
        init|workspace|version|-version|--version|fmt|validate|providers|get|graph|login|logout|metadata|test) return 0 ;;
        *) return 1 ;;
    esac
}

# Several git worktrees of this repo exist side by side, each with its own
# shared-global/ and keycloak-config/. A plan from the wrong one quietly reports
# "No changes" (seen 2026-09-18), so every state-touching run says where it is.
checkout_banner() {
    local top branch dirty
    top="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || return 0
    branch="$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null)"
    dirty="$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    echo "[terraw] checkout: $(basename "$top") @ ${branch:-<detached>} ($dirty uncommitted)" >&2
}

# An env name is anything with a .env.<name> next to this script — so "plan dev"
# switches, while "apply tfplan" (a saved plan file) still passes through.
known_env() {
    [[ "$1" =~ ^[a-z0-9-]+$ ]] && [ -f "$SCRIPT_DIR/.env.$1" ]
}

# The persisting half of 'switch', for "plan <env>" / "apply <env>". Env vars and
# secrets are loaded by the plan/apply path itself, so they are not fetched twice.
# Only selects a workspace where an env tfvars resolves: shared-global has one state
# in the default workspace.
select_env() {
    local env="$1"
    echo "$env" > "$STATE_FILE"
    echo "[terraw] env → $env (persisted to .terraw-env)" >&2
    [ -n "$(resolve_tfvars "$env")" ] || return 0
    if ! terraform workspace select "$env" >/dev/null; then
        echo "[terraw] ERROR: could not select workspace '$env'" >&2
        return 1
    fi
    echo "[terraw] workspace selected: $env" >&2
}

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
    switch)
        env="${1:-dev}"
        echo "[terraw] switch → $env"
        load_env_file "$env" || exit 1
        # Exports die with this process — this call is here to fail fast on a missing
        # secret or a lapsed PIM activation, rather than at the next plan.
        resolve_vault_secrets "$env"
        vault_guard "$cmd" || true
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
            tfv="$(resolve_tfvars "$env")"
            if [ -n "$tfv" ]; then
                echo "tfvars   = $tfv (would auto-inject)"
            else
                echo "tfvars   = none in $(pwd) (pass-through, e.g. shared-global)"
            fi
            # Names only, and no vault call — this is a "what would happen" view.
            if [ -f "$VAULT_MAP" ]; then
                echo "vault    = ismd-kv-$env, via .terraw-vault-map:"
                while IFS='=' read -r name secret || [ -n "$name" ]; do
                    name="${name//$'
'/}"
                    secret="${secret//$'
'/}"
                    case "$name" in ''|'#'*) continue ;; esac
                    [ -n "$secret" ] || continue
                    echo "           $name <- $secret"
                done < "$VAULT_MAP"
            fi
        fi
        ;;
    plan|apply|destroy|refresh|import|console)
        checkout_banner
        if [ $# -gt 0 ] && known_env "$1"; then
            select_env "$1" || exit 1
            shift
        fi
        env="$(current_env)"
        if [ "$env" = "prod" ]; then
            case "$cmd" in
                apply|destroy|import) echo "[terraw] *** PROD *** '$cmd' against production" >&2 ;;
            esac
        fi
        args=()
        if [ -z "$env" ]; then
            echo "[terraw] WARN: no env set — running plain 'terraform $cmd'. Run 'terraw switch <env>' first if you wanted env-scoped vars." >&2
        else
            workspace_guard "$env" || exit 1
            load_env_file "$env" || exit 1
            resolve_vault_secrets "$env"
            vault_guard "$cmd" || exit 1
            tfv="$(resolve_tfvars "$env")"
            if [ -n "$tfv" ]; then
                args+=(-var-file="$tfv")
                echo "[terraw] $cmd → injecting -var-file=$tfv"
            else
                echo "[terraw] $cmd → no env tfvars in $(pwd) (pass-through, e.g. shared-global)"
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
  ./terraw.sh plan <env> ...   switch to <env> first, then plan (same for apply etc.)
  ./terraw.sh <other>          Pass-through to terraform

Secrets: TF_VARs listed in .terraw-vault-map are read from ismd-kv-<env> into this
process on each run. Nothing is written to disk; apply is refused if one is missing.

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
        if [ -n "$env" ]; then
            stateless_cmd "$cmd" || workspace_guard "$env" || exit 1
            load_env_file "$env" >/dev/null 2>&1
            resolve_vault_secrets "$env" >/dev/null 2>&1
        fi
        exec terraform "$cmd" "$@"
        ;;
esac

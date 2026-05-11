#!/usr/bin/env bash
# ==============================================
# ISMD Compose Wrapper
# ==============================================
# Ergonomic frontend over the modular docker-compose stack.
#
# Usage:
#   ./compose.sh up                          # full stack, all pulled from GHCR
#   ./compose.sh up --build tool-be          # build tool backend locally
#   ./compose.sh up --build tool-be fuseki   # build multiple targets
#   ./compose.sh up --build all              # build everything locally
#   ./compose.sh up --no-tool-be             # BE dev mode (skip tool BE)
#   ./compose.sh up --frontends              # also run containerized frontends
#   ./compose.sh down                        # tear down
#   ./compose.sh logs -f backend             # pass-through to docker compose
#   ./compose.sh ps
#
# Build targets:
#   tool-be, validator-be, fuseki, tool-fe, validator-fe, all
#
# Repo path overrides (read from .env or shell env):
#   VALIDATOR_BACKEND_PATH   (default: ../ismd-validator-backend)
#   TOOL_BACKEND_PATH        (default: ../ismd-tool-backend)
#   VALIDATOR_FRONTEND_PATH  (default: ../ismd-validator-frontend)
#   TOOL_FRONTEND_PATH       (default: ../ismd-tool-frontend)
# ==============================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if present so *_PATH and credential vars are available here too.
# Docker compose will also read it automatically for variable substitution.
# Parse manually (rather than `source`) to tolerate CRLF line endings and
# values containing characters that would confuse the shell.
if [ -f .env ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ''|\#*) continue ;;
    esac
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    fi
  done < .env
fi

: "${VALIDATOR_BACKEND_PATH:=../ismd-validator-backend}"
: "${TOOL_BACKEND_PATH:=../ismd-tool-backend}"
: "${VALIDATOR_FRONTEND_PATH:=../ismd-validator-frontend}"
: "${TOOL_FRONTEND_PATH:=../ismd-tool-frontend}"

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage 0
fi

COMMAND="$1"
shift

COMPOSE_FILES=(-f docker-compose.yml)
PROFILE_ARGS=(--profile full-backend)
INCLUDE_FRONTENDS=false
BUILD_TARGETS=()
PASSTHROUGH=()

while [ $# -gt 0 ]; do
  case "$1" in
    --build)
      shift
      # Consume positional build targets until the next flag.
      while [ $# -gt 0 ] && [[ "$1" != -* ]]; do
        BUILD_TARGETS+=("$1")
        shift
      done
      if [ ${#BUILD_TARGETS[@]} -eq 0 ]; then
        echo "Error: --build requires at least one target" >&2
        exit 1
      fi
      ;;
    --no-tool-be)
      PROFILE_ARGS=()
      shift
      ;;
    --frontends)
      INCLUDE_FRONTENDS=true
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      PASSTHROUGH+=("$1")
      shift
      ;;
  esac
done

# Expand "all" -> every known target, and turn on frontends.
for t in "${BUILD_TARGETS[@]}"; do
  if [ "$t" = "all" ]; then
    BUILD_TARGETS=(tool-be validator-be fuseki tool-fe validator-fe)
    INCLUDE_FRONTENDS=true
    break
  fi
done

# A frontend build target implies the frontends are in the graph.
for t in "${BUILD_TARGETS[@]}"; do
  case "$t" in
    tool-fe|validator-fe) INCLUDE_FRONTENDS=true ;;
  esac
done

if $INCLUDE_FRONTENDS; then
  COMPOSE_FILES+=(-f docker-compose.frontends.yml)
fi

for t in "${BUILD_TARGETS[@]}"; do
  case "$t" in
    tool-be)
      COMPOSE_FILES+=(-f "$TOOL_BACKEND_PATH/docker-compose.build.yml")
      ;;
    fuseki)
      COMPOSE_FILES+=(-f "$TOOL_BACKEND_PATH/docker-compose.fuseki-build.yml")
      ;;
    validator-be)
      COMPOSE_FILES+=(-f "$VALIDATOR_BACKEND_PATH/docker-compose.build.yml")
      ;;
    tool-fe)
      COMPOSE_FILES+=(-f "$TOOL_FRONTEND_PATH/docker-compose.build.yml")
      ;;
    validator-fe)
      COMPOSE_FILES+=(-f "$VALIDATOR_FRONTEND_PATH/docker-compose.build.yml")
      ;;
    *)
      echo "Error: unknown build target '$t'" >&2
      echo "Valid targets: tool-be, validator-be, fuseki, tool-fe, validator-fe, all" >&2
      exit 1
      ;;
  esac
done

# Auto-pass --build when invoking `up` with build targets set.
EXTRA=()
if [ "$COMMAND" = "up" ] && [ ${#BUILD_TARGETS[@]} -gt 0 ]; then
  EXTRA+=(--build)
fi

# Echo the resolved command so users learn the underlying invocation.
printf 'docker compose'
for arg in "${COMPOSE_FILES[@]}" "${PROFILE_ARGS[@]}" "$COMMAND" "${EXTRA[@]}" "${PASSTHROUGH[@]}"; do
  printf ' %q' "$arg"
done
printf '\n\n'

exec docker compose "${COMPOSE_FILES[@]}" "${PROFILE_ARGS[@]}" "$COMMAND" "${EXTRA[@]}" "${PASSTHROUGH[@]}"

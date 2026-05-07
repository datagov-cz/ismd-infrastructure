# Local Dev Stack (Docker Compose)

Aggregates per-repo compose files into a single dev environment.

## Which Repos Do I Need?

| I'm working on... | Repos needed | Compose entrypoint |
|-------------------|--------------|-------------------|
| **Validator backend** | `ismd-validator-backend/` only | `cd ismd-validator-backend && docker compose up` |
| **Tool backend** | `ismd-tool-backend/` only | `cd ismd-tool-backend && docker compose --profile full-backend up` |
| **Validator frontend** | `ismd-validator-backend/` + your FE repo | `cd ismd-validator-backend && docker compose up` then `npm run dev` in `ismd-validator-frontend/` |
| **Tool frontend** | `ismd-tool-backend/` + your FE repo | `cd ismd-tool-backend && docker compose --profile full-backend up` then `npm run dev` in `ismd-tool-frontend/` |
| **Both frontends** (or full stack) | **All repos** + `ismd-infrastructure/` | `cd ismd-infrastructure && docker compose -f docker-compose.full-stack.yml --profile full-backend up` |

Backend repos are **self-sufficient** — you only need `ismd-infrastructure/` when aggregating multiple repos.

## Prerequisites

- **Docker Compose v2.20+** (for the `include:` directive — Docker Desktop ≥ 4.22)
- All four app repos cloned as **siblings** of `ismd-infrastructure/`:
  ```
  <parent>/
  ├── ismd-validator-backend/   # validator BE
  ├── ismd-tool-backend/        # tool BE + postgres + keycloak + fuseki
  ├── ismd-validator-frontend/  # validator FE
  ├── ismd-tool-frontend/     # tool FE
  └── ismd-infrastructure/    # this repo
  ```
  If your local folders use different names, override the paths in `.env`:
  ```
  VALIDATOR_BACKEND_PATH=../backend
  TOOL_BACKEND_PATH=../tool-backend
  VALIDATOR_FRONTEND_PATH=../frontend
  TOOL_FRONTEND_PATH=../tool-frontend
  ```

## Quick Start (Frontend Developer)

Run both backends + shared deps in containers, develop frontends locally:

```bash
cp compose.env.example .env   # one-time
docker compose --profile full-backend up
```

Then in your FE repo (`ismd-validator-frontend/` or `ismd-tool-frontend/`) run `npm run dev` against:
- Validator BE: `http://localhost:8082`
- Tool BE: `http://localhost:8081`
- Keycloak: `http://localhost:8080`

Stop:
```bash
docker compose --profile full-backend down
```

## Full Stack (Both Backends + Both Frontends)

Requires all four app repos cloned as siblings.

```bash
docker compose -f docker-compose.full-stack.yml --profile full-backend up
```

- Validator FE: `http://localhost:3000`
- Tool FE: `http://localhost:3001`
- Validator BE: `http://localhost:8082`
- Tool BE: `http://localhost:8081`
- Keycloak: `http://localhost:8080`

Stop:
```bash
docker compose -f docker-compose.full-stack.yml --profile full-backend down
```

### Add Frontends to a BE-Only Stack

If you're already using the base `docker-compose.yml` and want to layer frontends on top without switching to `docker-compose.full-stack.yml`:

```bash
docker compose -f docker-compose.yml \
               -f docker-compose.frontends.yml \
               --profile full-backend up
```

## Build All Images Locally (No GHCR pulls)

Requires `GITHUB_TOKEN` + `GITHUB_ACTOR` in `.env` (Maven access to GitHub Packages):

```bash
docker compose -f docker-compose.yml \
               -f ../ismd-validator-backend/docker-compose.build.yml \
               -f ../ismd-tool-backend/docker-compose.build.yml \
               --profile full-backend up --build
```

## Standalone Per-Repo Use

Each repo's `docker-compose.yml` works on its own:

| Repo | `docker compose up` runs |
|------|---------------------------|
| `ismd-validator-backend/` | validator BE only |
| `ismd-tool-backend/` | postgres + keycloak + fuseki (no BE; add `--profile full-backend` for BE) |
| `ismd-validator-frontend/` | validator FE only |
| `ismd-tool-frontend/` | tool FE only |

Add `-f docker-compose.build.yml` in any repo to build instead of pull.

## Environment Variables

Copy `compose.env.example` to `.env`. Compose auto-loads it.

| Var | Default | Purpose |
|---|---|---|
| `VALIDATOR_BACKEND_PATH` / `TOOL_BACKEND_PATH` / `VALIDATOR_FRONTEND_PATH` / `TOOL_FRONTEND_PATH` | `../ismd-<svc>-<role>` | Sibling repo paths — override if your local folder names differ from the canonical `ismd-*` layout |
| `VALIDATOR_BACKEND_IMAGE` / `TOOL_BACKEND_IMAGE` | `ghcr.io/datagov-cz/ismd-<svc>-backend-dev:latest` | Backend image override (pin a tag, swap to a fork, etc.) |
| `VALIDATOR_FRONTEND_IMAGE` / `TOOL_FRONTEND_IMAGE` | `ghcr.io/datagov-cz/ismd-<svc>-frontend-dev:latest` | Frontend image override (only used with `docker-compose.frontends.yml`) |
| `*_PULL_POLICY` | `missing` | `missing` = pull only if absent, `always` = re-pull every `up`, `never` = require local image |
| `GITHUB_TOKEN` / `GITHUB_ACTOR` | — | Required for build overrides (Maven → GitHub Packages). PAT needs `read:packages` scope. |
| `KEYCLOAK_CLIENT_SECRET` | `secret123` | Must match the secret configured for the tool BE client in your Keycloak realm |
| `CAAIS_CLIENT_ID` | — | Optional — set when federating Keycloak to the CAAIS IdP |

Mix per service: e.g. pin tool BE to `:1.0.3` while keeping validator BE on `:latest`, by setting only `TOOL_BACKEND_IMAGE` in `.env`.

## Port Map

| Service | Host Port | Notes |
|---------|-----------|-------|
| Keycloak | 8080 | unchanged |
| Tool BE | 8081 | |
| Validator BE | **8082** | moved from 8080 to avoid keycloak conflict |
| Validator FE | 3000 | |
| Tool FE | 3001 | |
| PostgreSQL | 5432 | |
| Fuseki | 3030 | bound to 127.0.0.1 (no auth) |

## Troubleshooting

- **`include:` not recognized** → upgrade Docker Compose to v2.20+
- **`network ismd-network not found`** → all repo files declare it with `name: ismd-network`; first `docker compose up` creates it. If stuck, `docker network prune`.
- **Tool BE can't reach validator** → use service name `http://ismd-validator-backend:8080/validujeme` (internal port 8080), not `localhost:8082`.
- **Build override needs GITHUB_TOKEN** → set in `.env` with `read:packages` scope.

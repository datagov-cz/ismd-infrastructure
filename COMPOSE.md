# Local Dev Stack (Docker Compose)

Aggregates per-repo compose files into a single dev environment.

## Prerequisites

- **Docker Compose v2.20+** (for the `include:` directive — Docker Desktop ≥ 4.22)
- All four app repos cloned as **siblings** of `infrastructure/`:
  ```
  <parent>/
  ├── backend/             # validator BE
  ├── tool-backend/        # tool BE + postgres + keycloak + fuseki
  ├── frontend/            # validator FE
  ├── tool-frontend/       # tool FE
  └── infrastructure/      # this repo
  ```

## Quick Start (Frontend Developer)

Run both backends + shared deps in containers, develop frontends locally:

```bash
cp compose.env.example .env   # one-time
docker compose --profile full-backend up
```

Then in your FE repo (`frontend/` or `tool-frontend/`) run `npm run dev` against:
- Validator BE: `http://localhost:8082`
- Tool BE: `http://localhost:8081`
- Keycloak: `http://localhost:8080`

## Optional: Run Frontends in Containers Too

```bash
docker compose -f docker-compose.yml \
               -f docker-compose.frontends.yml \
               --profile full-backend up
```

- Validator FE: `http://localhost:3000`
- Tool FE: `http://localhost:3001`

## Build All Images Locally (No GHCR pulls)

Requires `GITHUB_TOKEN` + `GITHUB_ACTOR` in `.env` (Maven access to GitHub Packages):

```bash
docker compose -f docker-compose.yml \
               -f ../backend/docker-compose.build.yml \
               -f ../tool-backend/docker-compose.build.yml \
               --profile full-backend up --build
```

## Standalone Per-Repo Use

Each repo's `docker-compose.yml` works on its own:

| Repo | `docker compose up` runs |
|------|---------------------------|
| `backend/` | validator BE only |
| `tool-backend/` | postgres + keycloak + fuseki (no BE; add `--profile full-backend` for BE) |
| `frontend/` | validator FE only |
| `tool-frontend/` | tool FE only |

Add `-f docker-compose.build.yml` in any repo to build instead of pull.

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

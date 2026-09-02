# Azure Infrastructure as Terraform Code

This repository contains Terraform configurations for managing Azure Container Apps infrastructure with Application Gateway across multiple environments (dev, test, prod).

## Common Gotchas

> Read this before your first `terraform plan` — these are the things that have actually caught us out.

- **Use `terraw.sh` / `terraw.ps1` instead of raw `terraform`.** It's a thin wrapper that picks up `.env.<env>` secrets and the right `-var-file` automatically. No sourcing needed — just execute:
  ```bash
  ./terraw.sh switch dev         # persist current env, load .env.dev, select workspace
  ./terraw.sh plan -out=tfplan   # auto-injects -var-file=environments/dev/terraform.tfvars
  ./terraw.sh apply tfplan
  ./terraw.sh env                # show current env + tfvars resolution
  ./terraw.sh <anything>         # pass-through to terraform (e.g. ./terraw.sh output)
  ```
  ```powershell
  .\terraw.ps1 switch dev
  .\terraw.ps1 plan -out=tfplan
  ```
  Optional one-time alias for less typing:
  ```bash
  alias terraw="$(pwd)/terraw.sh"          # bash/zsh — add to ~/.bashrc to persist
  Set-Alias terraw "$PWD\terraw.ps1"       # PowerShell — add to $PROFILE to persist
  ```
  Then just `terraw switch dev`, `terraw plan`, etc.

  State lives in `.terraw-env` (gitignored). `.env.<env>` is re-read on every `plan`/`apply`, so editing secrets does NOT require a re-`switch`. Re-`switch` only when changing target environment.

  In `shared-global/` (no environments/workspaces) just use `./terraw.sh plan` — no `environments/<env>/terraform.tfvars` exists, so it passes through to plain terraform.

  Symptom if you forget `terraw switch <env>` before `plan`: `terraform plan` fails with `expected "administrator_password" to not be an empty string` (or similar empty-var errors).

- **Secrets are not kept on disk.** Any `TF_VAR_*` listed in `.terraw-vault-map` (names only, committed) is read from `ismd-kv-<env>` into the terraform process on every `switch`/`plan`/`apply` and dies with it — never written to a file, echoed, or passed as an argument. `.env.<env>` holds only non-secret ops config now.

  A value already exported (or still present in `.env.<env>`) is left alone, so a one-off override works without touching the vault. If a mapped secret cannot be resolved — expired login, PIM activation lapsed, secret missing in that env's vault — `terraw` **refuses `apply`/`destroy`/`import`** and only warns on read-only commands. That guard exists because every sensitive root variable declares `default = ""`, so an unresolved secret would otherwise apply an empty value rather than fail.

  Requires `az login` and Get on the vault's secrets. `./terraw.sh env` prints the mapping without contacting the vault.

- **PowerShell and WSL bash have separate environments.** `.terraw-env` state file is shared (same path), but env var exports happen per-process — so just keep using whichever shell variant of `terraw` you started in for a given session.

- **Verify env vars before planning:**
  ```bash
  env | grep TF_VAR_
  ```
  If this is empty, you forgot to source the loader.

- **Workspace must match the environment.** The loader handles this automatically, but if you run `terraform workspace select` manually, make sure you're on the right one (`dev` / `test` / `prod`) before planning or applying.

- **`validator_use_bff` must match the deployed frontend image.** The validator app supports two wiring modes:

  | `validator_use_bff` | Frontend env | Backend ingress | Required image |
  |---|---|---|---|
  | `true` (BFF) | `BE_URL` → internal `http://ismd-validator-backend-<env>/validujeme` | internal-only | image with BFF refactor (post-PR #91 / v1.0.4+) |
  | `false` (legacy) | `NEXT_PUBLIC_BE_URL` → public `https://<hostname>/validujeme` | external + AppGW IP allowlist | any image |

  Flipping `use_bff = true` while the running image still reads `NEXT_PUBLIC_BE_URL` at build time → frontend can't reach backend → outage as soon as the gate is `live`.

  **Launch sequence when ready to enable BFF on TEST/PROD:** (1) cut a release that includes the BFF refactor, (2) deploy the new image via the relevant `trigger-deployment` workflow, (3) verify the frontend talks to backend while still gated, (4) flip `validator_use_bff = true` and `terraw apply`, (5) flip `validator_site_status = "live"` and `terraw apply`.

  Current state (2026-05-07): DEV = `true` (uses `-dev` images that have BFF), TEST/PROD = `false` (running v1.0.3 cherry-pick which intentionally excluded the BFF refactor).

## Architecture Overview

- **Shared Container App Environment**: Consolidated environment for all applications (validator and tool) across dev, test, and prod
- **Azure Container Apps**: Serverless container platform with auto-scaling and dedicated workload profiles
- **Application Gateway (WAF_v2)**: Shared global load balancer with a Microsoft Default Rule Set (DRS) 2.2 WAF policy, rate limiting, and dual-stack (IPv4 + IPv6) support
- **Multi-Environment**: Dev, Test, and Prod environments with consistent configuration
- **Networking**: Shared VNet with properly sized subnets for Container Apps, Tool Apps, and App Gateway
- **Decoupled Deployments**: Infrastructure managed via Terraform, container images deployed directly from application repositories
- **State Management**: Azure Storage backend with workspace-based environment isolation
- **Resource Protection**: Critical shared resources protected with prevent_destroy lifecycle rules

## State Management

State is stored in Azure Storage. Each environment has its own blob, isolated via Terraform workspaces (`ismd.tfstateenv:dev`, `ismd.tfstateenv:test`, `ismd.tfstateenv:prod`).

- **Resource Group**: `ismd-shared-tfstate`
- **Storage Account**: `ismdtfstate`
- **Container**: `tfstate`

Use `./terraw.sh switch <env>` to switch workspaces — it calls `terraform workspace select`, persists the env in `.terraw-env`, and subsequent `./terraw.sh plan` / `apply` auto-inject the right `-var-file` and re-load `.env.<env>` secrets.

## Directory Structure

```
├── environments/
│   ├── dev/                 # Development environment configuration
│   │   ├── main.tf          # Module calls and workspace wiring
│   │   ├── networking.tf    # VNet peering
│   │   ├── outputs.tf       # Environment outputs
│   │   ├── resource_groups.tf  # Resource group definitions
│   │   └── variables.tf     # Environment-specific variable defaults
│   ├── test/                # Test environment configuration (same structure)
│   └── prod/                # Production environment configuration (same structure)
├── modules/
│   ├── shared/                  # Shared Container App Environment & networking
│   │   ├── main.tf              # Container App Environment, Log Analytics, VNet
│   │   ├── outputs.tf           # Module outputs
│   │   └── variables.tf         # Module variables
│   ├── shared_global/           # Global shared resources (App Gateway, VNet)
│   │   ├── appgw_base_config.tf       # App Gateway base configuration
│   │   ├── appgw_validator_config.tf  # Validator app routing configuration
│   │   ├── appgw_tool_config.tf       # Tool app routing configuration
│   │   ├── appgw_resource.tf          # App Gateway resource (dynamic blocks)
│   │   ├── waf_policy.tf              # WAF policy (Microsoft DRS 2.2 + rate limit)
│   │   ├── error_pages.tf            # Custom AppGW error pages (e.g. 403)
│   │   ├── acs_email.tf              # Azure Communication Services email resource
│   │   ├── monitoring.tf            # AppGW diagnostic settings + log storage
│   │   ├── networking.tf              # VNet, subnets, public IPs
│   │   ├── resource_group.tf          # Global resource group
│   │   ├── outputs.tf                 # Module outputs
│   │   └── variables.tf               # Module variables
│   ├── validator_apps/          # Validator Frontend & Backend Container Apps
│   │   ├── backend.tf           # Backend container app
│   │   ├── frontend.tf          # Frontend container app
│   │   ├── outputs.tf           # Module outputs
│   │   ├── variables.tf         # Module variables
│   │   └── main.tf              # Documentation
│   ├── tool_apps/               # Tool Frontend, Backend, Database & Keycloak Container Apps
│   │   ├── backend.tf           # Tool backend container app
│   │   ├── frontend.tf          # Tool frontend container app
│   │   ├── database.tf          # PostgreSQL flexible server
│   │   ├── keycloak.tf          # Keycloak container app
│   │   ├── outputs.tf           # Module outputs
│   │   ├── variables.tf         # Core module variables
│   │   ├── variables_database.tf  # Database-specific variables
│   │   ├── variables_keycloak.tf  # Keycloak-specific variables
│   │   └── main.tf              # Documentation
│   ├── monitoring/              # Azure Monitor alerts + Logic App → Teams routing (per-env)
│   │   ├── action_groups.tf     # Quiet (Teams) and paging (Teams + email) action groups
│   │   ├── alerts_*.tf          # Alert rules: container apps, AppGW, Postgres, GHCR, self
│   │   ├── availability_tests.tf  # Custom availability probe alerts
│   │   ├── logic_app*.tf        # Logic App that posts Adaptive Cards to Teams
│   │   ├── README.md            # Module docs + one-time Teams OAuth step
│   │   └── variables.tf         # Module variables
│   └── keycloak_realm/          # ismd realm definition (clients, flags, SMTP) via Keycloak API
├── keycloak-config/             # Stage-2 Keycloak config root (separate state; see its README)
│   ├── main.tf                  # Calls modules/keycloak_realm for the ismd realm
│   ├── providers.tf             # keycloak + azurerm providers
│   ├── backend.tf               # Separate tfstate, workspace-per-env
│   ├── {dev,test,prod}.tfvars   # Non-secret per-env realm settings (committed)
│   └── README.md                # Usage, state model, SMTP gating
├── docs/
│   └── runbooks/                # One short runbook per alert rule
├── shared-global/               # Shared global infrastructure state
│   ├── main.tf                  # Shared global module configuration
│   ├── backend.tf               # Backend configuration
│   ├── variables.tf             # Input variables
│   └── terraform.tfvars         # Global configuration values (gitignored — not committed)
├── .github/workflows/           # CI/CD pipelines
│   ├── terraform.yml                  # Manual infrastructure updates
│   ├── terraform-plan.yml             # Plan-only run (e.g. on PRs)
│   ├── terraform-shared-global.yml    # App Gateway management
│   └── trivy-reusable.yml             # Reusable Trivy IaC scan (see docs/security-scanning.md)
├── main.tf                      # Root configuration with environment module calls
├── backend.tf                   # Azure Storage backend configuration
├── variables.tf                 # Input variable definitions
├── outputs.tf                   # Root module outputs
├── terraform.tfvars.example     # Example variables (copy to terraform.tfvars)
├── docker-compose.yml           # Base services (backends, postgres, keycloak, fuseki)
├── docker-compose.frontends.yml # Frontend services (chained by the compose wrapper)
├── docker-compose.full-stack.yml # Standalone full-stack entrypoint (raw `docker compose`)
├── compose.sh / compose.ps1     # Recommended wrapper around the chained compose files
└── compose.env.example          # Copy to .env for the compose wrapper
```

## Modules

### Shared Global Module (`modules/shared_global/`)

Manages the Application Gateway, global VNet, and public IPs — resources shared across all environments.

#### Files:

- **`appgw_base_config.tf`**: Static base configuration
  - Frontend ports (80, 443)
  - Frontend IP configurations (IPv4 + IPv6)
  - SSL certificates
  - Default HTTP listeners and routing rules
  
- **`appgw_validator_config.tf`**: Validator application configuration
  - Backend address pools (dev, test, prod)
  - Health probes (frontend and backend)
  - Backend HTTP settings (API, Swagger, pass-through)
  - HTTP/HTTPS listeners (hostname-based)
  - URL path maps (path-based routing rules)
  - Request routing rules
  
- **`appgw_resource.tf`**: Main Application Gateway resource
  - Uses dynamic blocks to generate configuration from data files
  - Combines base config + validator config + tool config
  
- **`networking.tf`**: Network resources
  - Global VNet with dedicated CIDR (IPv4 + IPv6 dual-stack)
  - App Gateway subnet (`/24` IPv4, `/64` IPv6)
  - Public IP addresses (IPv4 + IPv6) with prevent_destroy protection
  
- **`resource_group.tf`**: Resource group definition
  - Global shared resources container (`ismd-shared-global`)

To add routing for a new application, create a new `appgw_<app>_config.tf` file and update `appgw_resource.tf` to include it — existing configs are unchanged.

### Shared Module (`modules/shared/`)

Manages the shared Container App Environment and networking infrastructure for each environment:

- **Resource Group**: Environment-specific shared resources (`ismd-shared-{env}`)
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Virtual Network**: Environment-specific VNet with VNet peering to shared global VNet
  - Validator subnet (`/23`) - Hosts validator backend and frontend
  - Tool subnet (`/23`) - Hosts tool backend, frontend, and Keycloak
- **Container App Environment**: Single environment per region shared by all applications
  - Dedicated D4 workload profile with VNet integration
  - Zone redundancy enabled in production

### Validator Apps Module (`modules/validator_apps/`)

Manages the validator frontend and backend container apps.

#### Files:

- **`backend.tf`**: Spring Boot API — Spring Actuator health checks, ingress restricted to App Gateway IP, CORS, port 8080
- **`frontend.tf`**: Next.js app — ingress restricted to App Gateway IP, backend URL injected via env var
- **`outputs.tf`**: FQDNs, URLs, and resource names for both apps
- **`variables.tf`**: Input variables

`create_apps` can be set to `false` to skip container app creation while still provisioning networking — useful for bootstrapping a new environment before images are ready.

Container images are intentionally excluded from Terraform management via `lifecycle { ignore_changes = [template[0].container[0].image] }`. Images are deployed independently from application repositories using `az containerapp update`. Terraform only manages infrastructure (networking, env vars, ingress, resource allocation).

### Tool Apps Module (`modules/tool_apps/`)

Manages the full tool application stack: frontend, backend, PostgreSQL Flexible Server, Apache Jena Fuseki (triple store), and Keycloak.

#### Files:

- **`backend.tf`**: Tool backend container app (Spring Boot, path `/popisujeme`)
- **`frontend.tf`**: Tool frontend container app (Next.js, path `/popisujeme`)
- **`database.tf`**: PostgreSQL Flexible Server for tool data, plus the Apache Jena Fuseki triple store container app and its persistent storage (toggled by `deploy_fuseki`)
- **`keycloak.tf`**: Keycloak container app for tool authentication (path `/popisujeme/auth`)
- **`outputs.tf`**: Module outputs (FQDNs, URLs, resource names)
- **`variables.tf`**: Core module variables
- **`variables_database.tf`**: Database-specific variables (password, SKU, storage)
- **`variables_keycloak.tf`**: Keycloak-specific variables (admin password, client secret, realm config)

Keycloak runs as a Container App in the same environment as the tool and is routed by the App Gateway at `/popisujeme/auth`. It can be disabled via `deploy_keycloak = false`.

Apache Jena Fuseki runs as a Container App (internal ingress) backing the tool backend as its RDF triple store, with data persisted to an Azure File Share. It is toggled by `deploy_fuseki`.

Same `lifecycle { ignore_changes }` image pattern as the validator module — see above.

### Monitoring Module (`modules/monitoring/`)

Per-env module that wires Azure Monitor alert routing to Teams and email. Gated by `deploy_monitoring` and ingestion-capped.

- **Action Groups**: `ag-dia-quiet-{env}` (Teams webhook only) and `ag-dia-paging-{env}` (Teams + email, created only when `paging_email_recipients` is non-empty — primarily PROD).
- **Logic App**: receives the Azure Monitor common alert schema and posts an Adaptive Card to the configured Teams channel (`teams_group_id` / `teams_channel_id`).
- **Alert rules**: Container Apps (replicas-zero, 5xx, CPU, memory, restart-count), App Gateway (backend-unhealthy, 5xx), PostgreSQL (db-alive, CPU, memory, storage, connection-failures), GHCR pull failures, Log Analytics ingestion cap, and custom availability probes. Each alert links a runbook under `docs/runbooks/`.

One-time manual step after first apply: OAuth-authorize the Teams connector in the portal (Microsoft requires a user identity; terraform can't). See [`modules/monitoring/README.md`](modules/monitoring/README.md).

### Keycloak Realm Config (`keycloak-config/` + `modules/keycloak_realm/`)

Stage-2 configuration that manages the `ismd` realm **inside** the running Keycloak via its admin API — clients, login/registration flags, and SMTP. It does not deploy Keycloak (that's the `azurerm` container in `tool_apps`). Separate state, workspace-per-env, applied after Keycloak is reachable. See [`keycloak-config/README.md`](keycloak-config/README.md).

### Application Gateway Architecture

The Application Gateway is part of the `shared_global` module. Routing configuration is split across per-application files (`appgw_*_config.tf`) which define locals; `appgw_resource.tf` consumes them via dynamic blocks to produce a single `azurerm_application_gateway` resource.

#### Features:

- **WAF_v2 SKU** with autoscaling (1-10 instances), a WAF policy running Microsoft Default Rule Set (DRS) 2.2 with rate limiting, and a pinned modern SSL policy
- **Zone Redundancy**: Deployed across availability zones 1, 2, 3
- **Dual-Stack Support**: IPv4 + IPv6 frontend configurations
- **TLS 1.2+ enforcement** with Key Vault certificate integration
- **Health Probes**: Custom paths (`/actuator/health` for Spring Boot backends)
- **Path-Based Routing**: Environment-specific URL path maps
  - `/validujeme/api/*` → Validator backend API
  - `/validujeme/*` → Validator frontend
  - `/popisujeme/auth`, `/popisujeme/auth/*` → Tool Keycloak
  - `/popisujeme/api/*` → Tool frontend (Next.js API routes incl. NextAuth)
  - `/popisujeme/*` → Tool frontend
  > Note: On TEST/PROD the tool backend uses internal ingress only (pure BFF) — not reachable from App Gateway; Swagger UI and API docs are proxied through the tool frontend via Next.js rewrites. DEV is an exception: `backend_external_enabled = true` and App Gateway exposes a dedicated `/popisujeme/be/*` route (stripped to `/popisujeme/*` by the backend HTTP setting) for the local-frontend → DEV-backend dev loop. See the header comment in `appgw_tool_config.tf`.
- **Hostname-Based Routing**: Support for custom domains per environment
- **Lifecycle Protection**: `prevent_destroy` enabled on gateway and public IPs

#### Adding a New Application:

To add a new application:

1. Create a new configuration file in `modules/shared_global/` (e.g., `appgw_newapp_config.tf`) — see `appgw_tool_config.tf` as a reference
2. Update `modules/shared_global/appgw_resource.tf` to include the new config in dynamic blocks
3. No changes needed to existing application configurations

## Environments

The infrastructure supports three environments with consolidated architecture:

| Environment | Container App Environment | Workload Profile | VNet CIDR | Use Case |
|-------------|--------------------------|------------------|-----------|----------|
| **dev** | `ismd-shared-environment-dev` | Dedicated D4 | 10.0.0.0/16 | Development, shared environment |
| **test** | `ismd-shared-environment-test` | Dedicated D4 | 10.2.0.0/16 | Testing, staging |
| **prod** | `ismd-shared-environment-prod` | Dedicated D4 | 10.3.0.0/16 | Production workloads |

### Shared Resources Per Environment:

- **Container App Environment**: Single shared environment for all applications in each environment
- **VNet**: Environment-specific with two subnets:
  - Validator subnet (`/23`) - Hosts validator backend and frontend
  - Tool subnet (`/23`) - Hosts tool backend, frontend, and Keycloak
- **Application Gateway**: Global, shared across all environments
- **Resource Groups**: 
  - `ismd-shared-{env}` - Shared Container App Environment and networking
  - `ismd-validator-{env}` - Validator-specific resources
  - `ismd-tool-{env}` - Tool-specific resources (container apps, database, Keycloak)
  - `ismd-shared-global` - Application Gateway and global networking

All environments use dedicated D4 workload profiles with VNet integration for consistent performance and security. The shared environment architecture provides cost efficiency while maintaining environment isolation.

## Usage

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (logged in)
- [Terraform CLI](https://www.terraform.io/downloads) (v1.0+)
- Access to the Azure subscription

### Initial Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd <repo-directory>
   ```

2. **Authenticate to Azure**:

   ```bash
   az login                          # interactive login
   az login --tenant <tenant-id>     # if you need to specify tenant
   az account show                   # verify correct subscription
   ```

   **Required Azure RBAC permissions:**
   - `Contributor` role on the subscription
   - `Storage Blob Data Contributor` on the tfstate storage account (`ismdtfstate`)

   > **Note:** If `ARM_CLIENT_SECRET` is present in your environment it will override `az login` and authenticate as a service principal instead. This is intentional in CI but should not be set for local development.

3. **Configure variables**:

   Non-sensitive config (resource group names, image tags, hostnames) lives in `environments/<env>/terraform.tfvars` and is committed to the repo. No setup needed here.

   Non-secret ops config (operator IPs, alert recipients, Teams ids) lives in a gitignored `.env.<env>` file. Secrets are not put there — `terraw` pulls those from `ismd-kv-<env>` per `.terraw-vault-map`:
   ```bash
   # bash
   cp .env.example .env.dev
   ```
   ```powershell
   # PowerShell
   Copy-Item .env.example .env.dev
   ```
   Fill in values in `.env.dev`.

4. **Switch env via the wrapper**:

   ```bash
   # bash
   ./terraw.sh switch dev
   ```
   ```powershell
   # PowerShell
   .\terraw.ps1 switch dev
   ```

   `switch` exports all `TF_VAR_*` from `.env.<env>`, resolves the mapped secrets from Key Vault, runs `terraform workspace select <env>`, and persists the env name in `.terraw-env` so subsequent `plan`/`apply` auto-inject `-var-file=environments/<env>/terraform.tfvars` and re-load secrets.

   In CI, secrets are injected automatically from GitHub Actions secrets — `terraw` is not used.

### Deployment

#### Initial Deployment (First Time Setup)

**Step 1: Deploy Shared Global Infrastructure**

Deploy the Application Gateway and global networking:

```bash
cd shared-global  # subdirectory within the repo root
terraform init
terraform plan
terraform apply
```

This creates:
- Application Gateway (with base configuration and validator routing)
- Global VNet and subnets
- Public IP addresses (IPv4 + IPv6)

**Step 2: Deploy Environment Infrastructure**

Deploy each environment to create the shared Container App Environment and applications:

```bash
# Return to repo root
cd ..

# Initialize Terraform (only needed once)
terraform init

# Switch env (if not already done)
./terraw.sh switch dev    # bash — or: .\terraw.ps1 switch dev (PowerShell)

# Plan and apply changes (var-file + .env.dev auto-loaded by the wrapper)
./terraw.sh plan -out=tfplan
./terraw.sh apply tfplan
```

This creates:
- Shared Container App Environment (`ismd-shared-environment-{env}`)
- Container Apps (validator frontend, validator backend, tool frontend, tool backend, Keycloak) with auto-generated FQDNs
- PostgreSQL Flexible Server for the tool
- Environment-specific VNet with validator and tool subnets
- VNet peering to global VNet

**Step 3: Update Application Gateway with Container App FQDNs**

After deploying the apps, update the App Gateway backend pools with actual FQDNs:

```bash
# Read the environment domains straight from Azure
az containerapp env list --query "[].{name:name,domain:properties.defaultDomain}" -o table

# These belong in shared-global/terraform.tfvars, which IS committed:
#   container_app_environment_domain_dev/test/prod
#   dev_hostname / test_hostname / prod_hostname

cd shared-global
../terraw.sh plan -out=tfplan   # Review the routing changes
../terraw.sh apply tfplan
```

> **Do not plan here without `shared-global/terraform.tfvars` present.**
> Every variable it sets defaults to `""`. If the file is missing — it was
> gitignored until 2026-08-31, so older clones and any worktree created before
> then will not have it — Terraform builds the App Gateway with empty backend
> pools and empty listener host names, and proposes disconnecting **every app in
> dev, test and prod** under a headline of `0 to add, 2 to change, 0 to destroy`.
>
> The destroy count does not catch this. Read the attribute lines: if you see
> `fqdns = [...] -> null` or `host_name` going empty on
> `azurerm_application_gateway.appgw`, stop and restore the tfvars file.

This updates the Application Gateway backend pools to route traffic to the deployed container apps.

#### Subsequent Deployments

After initial setup, deployments are simplified:

- **Infrastructure changes** (environment variables, ingress, etc.):
  ```bash
  ./terraw.sh switch <env>     # bash — or: .\terraw.ps1 switch <env> (PowerShell)
  ./terraw.sh plan -out=tfplan
  ./terraw.sh apply tfplan
  ```
  
- **Container image updates**: Handled automatically by application repositories via `az containerapp update`
  - No Terraform apply needed
  - Images deploy independently from infrastructure
  
- **Application Gateway updates** (new routing rules):
  ```bash
  cd shared-global
  terraform plan
  terraform apply
  ```

### Container Image Management

Container images are **deployed independently from Terraform** using `az containerapp update`:

#### Image Deployment Strategy:

**Development Images** (`-dev` suffix):
- Validator: `ghcr.io/org/ismd-validator-{backend|frontend}-dev:latest`
- Tool: `ghcr.io/org/ismd-tool-{backend|frontend}-dev:latest`
- Tag: `latest` (rolling tag)
- Deployed automatically on push to dev branch

**Production Images** (test/prod):
- Validator: `ghcr.io/org/ismd-validator-{backend|frontend}:<version>`
- Tool: `ghcr.io/org/ismd-tool-{backend|frontend}:<version>`
- Tag: Version numbers (e.g., `1.0.0`, `1.0.0-abc1234`)
- TEST: Deployed automatically when pushed to main branch
- PROD: Deployed manually via workflow_dispatch

Note: Keycloak uses an upstream image managed via the `keycloak_image` Terraform variable, not a built image.

Image tag variables validate that the value is either `latest` or a valid semver string (e.g. `1.0.0`, `1.0.0-abc1234`). Initial values are set in `environments/<env>/terraform.tfvars` and are only used on first `terraform apply` — subsequent image updates go through `az containerapp update`.

### GitHub Actions CI/CD

The infrastructure uses a **decoupled deployment architecture** where infrastructure and application images are managed independently.

#### Infrastructure Repository Workflows:

- **`terraform.yml`**: Manual infrastructure updates via `workflow_dispatch`
  - Manages Container App infrastructure (environment variables, ingress, probes, resource allocation)
  - Does NOT manage container images (handled by `lifecycle ignore_changes`)
  - Runs: `shared_global_pre` → `terraform` → `shared_global_post`
  - Triggered manually when infrastructure changes are needed
  
- **`terraform-shared-global.yml`**: Application Gateway management
  - Reusable workflow for updating App Gateway routing
  - Called by `terraform.yml` after infrastructure changes
  - Can also be triggered manually for gateway-only updates

#### Application Repository Workflows:

Each of the four application repositories (validator-backend, validator-frontend, tool-backend, tool-frontend) has independent CI/CD:

1. **CI Workflow**: Tests on PRs and dev branch pushes
2. **Build Docker on Dev**: Builds `-dev` images after successful CI
   - Pushes to `ghcr.io/org/app-dev:latest`
   - Triggers deployment workflow for DEV environment
3. **Release Version**: Creates version tags and PRs from dev to main
4. **Build Docker on Main**: Builds production images with version tags
   - Pushes to `ghcr.io/org/app:version`
   - Triggers deployment workflow for TEST environment
5. **Trigger Deployment**: Deploys images directly to Azure Container Apps
   - Uses `az containerapp update` to deploy new images
   - No interaction with infrastructure repository
   - Automatic: DEV (on dev push), TEST (on main push)
   - Manual: PROD (workflow_dispatch with version selection)

#### Deployment Flow:

```
Application Changes:
  Developer pushes to dev
    ↓
  Build Docker (creates image)
    ↓
  Trigger Deployment (runs az containerapp update)
    ↓
  Container App updated with new image
  
Infrastructure Changes:
  Developer creates PR with Terraform changes
    ↓
  Merge to dev branch
    ↓
  Manual: Run terraform.yml workflow
    ↓
  Infrastructure updated (Terraform apply)
```

## Docker Compose Configuration

This repo aggregates compose definitions from sibling repos via the `include:`
directive, plus a wrapper script that hides the `-f`/profile machinery for
day-to-day use. Default sibling layout (matches CI repo names):

```
<parent>/
├── ismd-validator-backend/
├── ismd-validator-frontend/
├── ismd-tool-backend/        (also defines postgres, keycloak, fuseki)
├── ismd-tool-frontend/
└── ismd-infrastructure/      (this repo)
```

### Quick start

```bash
# Linux/Mac/WSL
./compose.sh up

# Windows PowerShell
.\compose.ps1 up
```

This pulls pre-built images from GHCR for the full backend stack (tool BE,
validator BE, postgres, keycloak, fuseki) and starts them. Frontends are
*not* started by default — most developers run `npm run dev` locally against
the containerized backends.

### Common flags

All flags below work with both `compose.sh` and `compose.ps1`. Examples use
the bash form.

| Goal | Command |
|---|---|
| Full backend stack, all pulled (default) | `./compose.sh up` |
| Also start containerized frontends | `./compose.sh up --frontends` |
| Skip the tool backend (BE dev runs Spring Boot natively) | `./compose.sh up --no-tool-be` |
| Build the tool backend from local source | `./compose.sh up --build tool-be` |
| Build multiple targets | `./compose.sh up --build tool-be fuseki` |
| Build everything from local source | `./compose.sh up --build all` |
| Combine: build tool FE + run other FEs from GHCR | `./compose.sh up --build tool-fe --frontends` |
| Tear down | `./compose.sh down` |
| Pass-through (logs/ps/etc.) | `./compose.sh logs -f backend` |

**Build targets:** `tool-be`, `validator-be`, `fuseki`, `tool-fe`,
`validator-fe`, `all`.

Whatever flags you pass, the script prints the resolved `docker compose ...`
command before running it, so you can see what's happening underneath.

### Configuration via `infrastructure/.env`

Compose auto-loads `.env` from this directory. Useful entries:

```bash
# Required when building images locally (GHCR Maven Packages access).
# Not needed for the default pull-from-GHCR flow.
GITHUB_TOKEN=<PAT with read:packages scope>
GITHUB_ACTOR=<your github username>

# Required for tool backend to obtain Keycloak tokens at startup.
KEYCLOAK_CLIENT_SECRET=<from Keycloak admin UI>

# Sibling-repo path overrides — only set if your local folder names
# differ from the defaults shown above.
VALIDATOR_BACKEND_PATH=../backend
TOOL_BACKEND_PATH=../tool-backend
VALIDATOR_FRONTEND_PATH=../frontend
TOOL_FRONTEND_PATH=../tool-frontend
```

The `GITHUB_TOKEN` is passed to backend builds via a BuildKit secret mount —
it does not appear in image history or build logs. Maven dependencies are
cached in a BuildKit cache mount, so subsequent builds skip the dependency
download.

### Power-user / raw docker compose

The wrapper just composes `-f` chains and the `--profile full-backend` flag.
If you need full control, invoke `docker compose` directly:

```bash
# Equivalent to ./compose.sh up --build tool-be
docker compose -f docker-compose.yml \
               -f ../ismd-tool-backend/docker-compose.build.yml \
               --profile full-backend up --build
```

### Files in this repo

- `docker-compose.yml` — aggregator using `include:` for sibling repos (base backend services).
- `docker-compose.frontends.yml` — optional include for containerized frontends (chained by the wrapper).
- `docker-compose.full-stack.yml` — standalone full-stack entrypoint for raw `docker compose --profile full-backend`; the wrapper does **not** use it (see [`COMPOSE.md`](COMPOSE.md)).
- `compose.sh` / `compose.ps1` — wrapper scripts (recommended entrypoint).
- `compose.env.example` — copy to `.env` for the compose wrapper (Docker Compose auto-loads `.env`). This is distinct from `.env.example`, which is copied to `.env.<env>` for Terraform secrets via `terraw` — two different files for two different purposes.

> See [`COMPOSE.md`](COMPOSE.md) for the standalone full-stack compose path; this section covers the recommended wrapper.

## Configuration Management

### Environment Variables

Key variables managed through Terraform across all container apps:

**Validator:**
- `CORS_ALLOWED_ORIGINS` — allowed origins for the backend
- `BE_URL` — backend base URL used server-side by Next.js rewrites (BFF pattern, not exposed to browser)
- `PORT` — container port (8080)

**Tool:**
- `SPRING_DATASOURCE_URL` / `_USERNAME` / `_PASSWORD` — PostgreSQL connection
- `NEXTAUTH_SECRET` — NextAuth.js session secret
- `KEYCLOAK_CLIENT_ID` / `_SECRET` — OIDC client credentials
- `NEXT_PUBLIC_BASE_PATH` — subpath prefix (`/popisujeme`)

### Security Features

- **Application Gateway**: WAF_v2 with Microsoft Default Rule Set (DRS) 2.2 + rate limiting, pinned modern SSL policy (TLS 1.2+)
- **Monitoring**: Azure Monitor alerts routed to Teams/email via Logic App (gated by `deploy_monitoring`)
- **Restricted Ingress**: Backend and frontend use external ingress restricted to Application Gateway public IP only
- **Resource Protection**: Critical resources have `prevent_destroy` lifecycle rules

## Troubleshooting

### Common Issues

1. **Subnet Size Errors**:
   - Container Apps with dedicated workload profiles require adequate subnet size
   - All environments use D4 workload profile with VNet integration
   - Ensure no subnet overlaps in VNet configuration

2. **Application Gateway Routing**:
   - Backend pools require container app FQDNs (see deployment steps)
   - Path-based routing rules must be in correct order (most specific first)

3. **Resource Import**:

   Resources created outside of Terraform (e.g. auto-created load balancers or IPs) can be imported rather than recreated:
   ```bash
   terraform import module.dev[0].azurerm_resource_group.shared /subscriptions/.../resourceGroups/...
   ```
   The Azure Export for Terraform tool can also generate import blocks for existing resources.

4. **CORS Issues**:
   - Verify `pick_host_name_from_backend_address = true` in App Gateway backend settings
   - Check backend CORS_ALLOWED_ORIGINS configuration matches expected origins

### Useful Commands

```bash
# Check current workspace
terraform workspace show

# List all workspaces
terraform workspace list

# View planned changes without applying
terraform plan -out=plan.tfplan

# Apply specific plan file
terraform apply plan.tfplan
```

## Additional Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Application Gateway Documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Architecture Evolution

### Migration to Shared Environment (v2 Architecture)

The infrastructure underwent a significant architectural migration to consolidate resources and decouple deployments:

#### What Changed:

**Before (v1):**
- Separate Container App Environment per application per environment
- Terraform managed both infrastructure AND container images
- Application repositories triggered Terraform deployments via `repository_dispatch`
- Image updates required full Terraform apply cycles

**After (v2 - Current):**
- Single shared Container App Environment per environment (all apps)
- Terraform manages infrastructure only (lifecycle ignore_changes for images)
- Application repositories deploy images directly via `az containerapp update`
- Image updates are independent of infrastructure changes

#### Migration Benefits:

1. **Cost Efficiency**: Single Container App Environment per region instead of one per application
2. **Faster Deployments**: Image updates complete in seconds without Terraform overhead
3. **Simplified Architecture**: Clear separation between infrastructure and application concerns
4. **Independent Releases**: Applications can deploy independently without infrastructure coordination
5. **Reduced Complexity**: No cross-repository communication or shared secrets needed

#### Infrastructure Changes:

- **Added**: `modules/shared` (consolidated shared environment for all apps)
- **Added**: `modules/tool_apps` (tool backend, frontend, database, and Keycloak)
- **Updated**: All container app definitions include `lifecycle { ignore_changes = [template[0].container[0].image] }`
- **Subnet Planning**: Two `/23` subnets per environment — one for validator, one for tool apps

#### Workflow Changes:

- **Removed**: `repository_dispatch` triggers between infrastructure and application repos
- **Simplified**: Infrastructure workflows run manually only when infrastructure changes
- **Added**: Direct `az containerapp update` commands in application deployment workflows
- **Enhanced**: Image validation before deployment in application workflows


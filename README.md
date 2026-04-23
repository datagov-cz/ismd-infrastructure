# Azure Infrastructure as Terraform Code

This repository contains Terraform configurations for managing Azure Container Apps infrastructure with Application Gateway across multiple environments (dev, test, prod).

## Architecture Overview

- **Shared Container App Environment**: Consolidated environment for all applications (validator and tool) across dev, test, and prod
- **Azure Container Apps**: Serverless container platform with auto-scaling and dedicated workload profiles
- **Application Gateway**: Shared global load balancer with WAF capabilities and dual-stack (IPv4 + IPv6) support
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

Use `load_env_vars.sh` / `load_env_vars.ps1` to switch workspaces — it calls `terraform workspace select` automatically.

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
│   └── tool_apps/               # Tool Frontend, Backend, Database & Keycloak Container Apps
│       ├── backend.tf           # Tool backend container app
│       ├── frontend.tf          # Tool frontend container app
│       ├── database.tf          # PostgreSQL flexible server
│       ├── keycloak.tf          # Keycloak container app
│       ├── outputs.tf           # Module outputs
│       ├── variables.tf         # Core module variables
│       ├── variables_database.tf  # Database-specific variables
│       ├── variables_keycloak.tf  # Keycloak-specific variables
│       └── main.tf              # Documentation
├── shared-global/               # Shared global infrastructure state
│   ├── main.tf                  # Shared global module configuration
│   ├── backend.tf               # Backend configuration
│   ├── variables.tf             # Input variables
│   └── terraform.tfvars         # Global configuration values (gitignored — not committed)
├── .github/workflows/           # CI/CD pipelines
│   ├── terraform.yml                  # Manual infrastructure updates
│   └── terraform-shared-global.yml    # App Gateway management
├── main.tf                      # Root configuration with environment module calls
├── backend.tf                   # Azure Storage backend configuration
├── variables.tf                 # Input variable definitions
├── outputs.tf                   # Root module outputs
├── terraform.tfvars.example     # Example variables (copy to terraform.tfvars)
├── docker-compose.yml           # Base Docker Compose configuration
├── docker-compose.dev.yml       # Development Docker Compose overrides
└── docker-compose.local.yml     # Local development Docker Compose overrides
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

Manages the full tool application stack: frontend, backend, PostgreSQL Flexible Server, and Keycloak.

#### Files:

- **`backend.tf`**: Tool backend container app (Spring Boot, path `/popisujeme`)
- **`frontend.tf`**: Tool frontend container app (Next.js, path `/popisujeme`)
- **`database.tf`**: PostgreSQL Flexible Server for tool data
- **`keycloak.tf`**: Keycloak container app for tool authentication (path `/popisujeme/auth`)
- **`outputs.tf`**: Module outputs (FQDNs, URLs, resource names)
- **`variables.tf`**: Core module variables
- **`variables_database.tf`**: Database-specific variables (password, SKU, storage)
- **`variables_keycloak.tf`**: Keycloak-specific variables (admin password, client secret, realm config)

Keycloak runs as a Container App in the same environment as the tool and is routed by the App Gateway at `/popisujeme/auth`. It can be disabled via `deploy_keycloak = false`.

Same `lifecycle { ignore_changes }` image pattern as the validator module — see above.

### Application Gateway Architecture

The Application Gateway is part of the `shared_global` module. Routing configuration is split across per-application files (`appgw_*_config.tf`) which define locals; `appgw_resource.tf` consumes them via dynamic blocks to produce a single `azurerm_application_gateway` resource.

#### Features:

- **Standard_v2 SKU** with autoscaling (0-10 instances)
- **Zone Redundancy**: Deployed across availability zones 1, 2, 3
- **Dual-Stack Support**: IPv4 + IPv6 frontend configurations
- **TLS 1.2+ enforcement** with Key Vault certificate integration
- **Health Probes**: Custom paths (`/actuator/health` for Spring Boot backends)
- **Path-Based Routing**: Environment-specific URL path maps
  - `/validujeme/api/*` → Validator backend API
  - `/validujeme/api-docs` → Validator API documentation (Swagger UI)
  - `/validujeme/swagger-ui/*` → Validator Swagger UI resources
  - `/validujeme/*` → Validator frontend
  - `/popisujeme/auth`, `/popisujeme/auth/*` → Tool Keycloak
  - `/popisujeme/api/*` → Tool frontend (Next.js API routes)
  - `/popisujeme/api-docs`, `/popisujeme/v3/*` → Tool backend (pass-through)
  - `/popisujeme/swagger-ui/*` → Tool backend Swagger UI
  - `/popisujeme/actuator/*` → Tool backend actuator
  - `/popisujeme/*` → Tool frontend
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

   Sensitive variables (Postgres password, Keycloak secrets, NextAuth secret) are loaded from a `.env.<env>` file which is gitignored:
   ```bash
   # bash
   cp .env.example .env.dev
   ```
   ```powershell
   # PowerShell
   Copy-Item .env.example .env.dev
   ```
   Fill in values in `.env.dev`.

4. **Load secrets and select workspace**:

   ```bash
   # bash
   source load_env_vars.sh dev
   ```
   ```powershell
   # PowerShell
   . .\load_env_vars.ps1 dev
   ```

   Run once per shell session before any `terraform` commands. Use `dev`, `test`, or `prod` as the argument. This exports all `TF_VAR_*` secrets and switches the Terraform workspace.

   In CI, secrets are injected automatically from GitHub Actions secrets — the load scripts are not used.

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

# Load secrets and switch workspace (if not already done)
source load_env_vars.sh dev        # bash
# . .\load_env_vars.ps1 dev        # PowerShell

# Plan and apply changes
terraform plan
terraform apply
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
# Get FQDNs from the terraform outputs
terraform output

# Update shared-global/terraform.tfvars with the FQDNs:
# container_app_environment_domain_dev = "livelydesert-xxx.germanywestcentral.azurecontainerapps.io"
# container_app_environment_domain_test = "mangodune-xxx.germanywestcentral.azurecontainerapps.io"

cd shared-global
terraform plan  # Review the routing changes
terraform apply
```

This updates the Application Gateway backend pools to route traffic to the deployed container apps.

#### Subsequent Deployments

After initial setup, deployments are simplified:

- **Infrastructure changes** (environment variables, ingress, etc.):
  ```bash
  source load_env_vars.sh <env>   # bash — or: . .\load_env_vars.ps1 <env>
  terraform plan
  terraform apply
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

Local development files for testing the application stack:

- `docker-compose.yml` - Base configuration with production settings
- `docker-compose.dev.yml` - Development environment overrides
- `docker-compose.local.yml` - Local image overrides for development

```bash
# Local testing with production images
docker compose up

# Development with local overrides
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

## Configuration Management

### Environment Variables

Key variables managed through Terraform across all container apps:

**Validator:**
- `CORS_ALLOWED_ORIGINS` — allowed origins for the backend
- `NEXT_PUBLIC_BE_URL` — frontend-to-backend URL
- `PORT` — container port (8080)

**Tool:**
- `SPRING_DATASOURCE_URL` / `_USERNAME` / `_PASSWORD` — PostgreSQL connection
- `NEXTAUTH_SECRET` — NextAuth.js session secret
- `KEYCLOAK_CLIENT_ID` / `_SECRET` — OIDC client credentials
- `NEXT_PUBLIC_BASE_PATH` — subpath prefix (`/popisujeme`)

### Security Features

- **Application Gateway**: TLS 1.2+ enforcement, WAF capabilities
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


# Azure Infrastructure as Terraform Code

This repository contains Terraform configurations for managing Azure Container Apps infrastructure with Application Gateway across multiple environments (dev, test, prod).

## Architecture Overview

- **Shared Container App Environment**: Consolidated environment for all validator apps across dev, test, and prod
- **Azure Container Apps**: Serverless container platform with auto-scaling and dedicated workload profiles
- **Application Gateway**: Shared global load balancer with WAF capabilities and dual-stack (IPv4 + IPv6) support
- **Multi-Environment**: Dev, Test, and Prod environments with consistent configuration
- **Networking**: Shared VNet with properly sized subnets for Container Apps, Tool Apps, and App Gateway
- **Decoupled Deployments**: Infrastructure managed via Terraform, container images deployed directly from application repositories
- **State Management**: Azure Storage backend with workspace-based environment isolation
- **Resource Protection**: Critical shared resources protected with prevent_destroy lifecycle rules

## State Management & Workspaces

This project uses Azure Storage to manage the infrastructure state for all environments. Environment separation is handled using **Terraform Workspaces**, with each workspace storing its state in a separate blob.

### Workspace Configuration

- **Separate State Files**: Each environment (dev, test, prod) has its own state file stored as a separate blob in the `tfstate` container.
- **Workspace-Based State Files**: Terraform automatically creates workspace-specific state files with the naming convention `ismd.tfstateenv:<workspace>` (e.g., `ismd.tfstateenv:dev`, `ismd.tfstateenv:test`).
- **Backend Configuration**: The `backend.tf` file is configured with a base key. Terraform appends the workspace name to create the full path.
- **Switching Environments**: To work on a specific environment, you must switch to the corresponding workspace.

### State Storage

- **Resource Group**: `ismd-shared-tfstate`
- **Storage Account**: `ismdtfstate`
- **Container**: `tfstate`

## Directory Structure

```
├── environments/
│   ├── dev/           # Development environment configuration
│   ├── test/          # Test environment configuration
│   └── prod/          # Production environment configuration
├── modules/
│   ├── shared/                  # Shared Container App Environment & networking
│   │   ├── main.tf              # Container App Environment, Log Analytics
│   │   ├── resource_group.tf   # Environment-specific resource group
│   │   ├── networking.tf        # VNet, subnets (validator + tool apps)
│   │   ├── outputs.tf           # Module outputs
│   │   └── variables.tf         # Module variables
│   ├── shared_global/           # Global shared resources (App Gateway, VNet)
│   │   ├── appgw_base_config.tf       # App Gateway base configuration
│   │   ├── appgw_validator_config.tf  # Validator app routing configuration
│   │   ├── appgw_resource.tf          # App Gateway resource (dynamic blocks)
│   │   ├── networking.tf              # VNet, subnets, public IPs
│   │   ├── resource_group.tf          # Global resource group
│   │   ├── outputs.tf                 # Module outputs
│   │   └── variables.tf               # Module variables
│   └── validator_apps/          # Frontend & Backend Container Apps
│       ├── backend.tf           # Backend container app
│       ├── frontend.tf          # Frontend container app
│       ├── outputs.tf           # Module outputs
│       ├── variables.tf         # Module variables
│       └── main.tf              # Documentation
├── shared-global/               # Shared global infrastructure state
│   ├── main.tf                  # Shared global module configuration
│   ├── backend.tf               # Backend configuration
│   ├── variables.tf             # Input variables
│   └── terraform.tfvars         # Global configuration values
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

Manages global shared infrastructure that spans all environments using a **data-driven configuration pattern**.

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
  - Combines base config + validator config
  
- **`networking.tf`**: Network resources
  - Global VNet with dedicated CIDR (IPv4 + IPv6 dual-stack)
  - App Gateway subnet (`/24` IPv4, `/64` IPv6)
  - Public IP addresses (IPv4 + IPv6) with prevent_destroy protection
  
- **`resource_group.tf`**: Resource group definition
  - Global shared resources container (`ismd-shared-global`)

#### Key Features:

- **Data-Driven Architecture**: Configuration defined as data structures, generated via dynamic blocks
- **DRY Principle**: No repetition - patterns defined once and applied to all environments
- **Easy Extension**: Add new applications by creating additional config files (e.g., `appgw_tool_config.tf`)
- **Maintainable**: Clear separation between data (config files) and structure (resource file)
- **Multi-App Ready**: Architecture supports multiple applications with path-based routing (e.g., `/validator/*` for validator app)

### Shared Module (`modules/shared/`)

Manages the shared Container App Environment and networking infrastructure for each environment:

- **Resource Group**: Environment-specific shared resources (`ismd-shared-{env}`)
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Virtual Network**: Environment-specific VNet with VNet peering to shared global VNet
  - Validator subnet (`/23`) - For validator application containers
  - Tool subnet (`/23`) - Reserved for future tool application
- **Container App Environment**: Consolidated environment shared by all applications
  - Dedicated D4 workload profile with VNet integration
  - Zone redundancy enabled in production
  - Single environment per region for cost efficiency and simplified management

### Validator Apps Module (`modules/validator_apps/`)

Manages the application containers with a clear file structure:

#### Files:

- **`backend.tf`**: Backend container app definition
  - Spring Boot API with Spring Actuator health checks
  - Ingress restricted to Application Gateway IP
  - CORS configuration for frontend access
  - Internal port 8080 configuration
  
- **`frontend.tf`**: Frontend container app definition
  - Next.js application
  - Ingress restricted to Application Gateway IP
  - Backend URL configuration via environment variable
  
- **`outputs.tf`**: Module outputs
  - FQDNs, URLs, and resource names for both apps
  
- **`variables.tf`**: Input variables
  - Organized by category (core, gateway, images, workload profile)

#### Key Features:

- **Clear Separation**: Each container app in its own file for easy maintenance
- **Environment Variables**: Automatic configuration for inter-service communication
- **Resource Allocation**: Optimized CPU/memory combinations per environment
- **Conditional Creation**: Support for phased deployments with `create_apps` variable
- **Security**: Ingress restricted to Application Gateway public IP
- **Decoupled Image Deployment**: `lifecycle { ignore_changes = [template[0].container[0].image] }` prevents Terraform from managing container images
  - Container images deployed independently via `az containerapp update` from application repositories
  - Terraform manages infrastructure only (networking, environment variables, ingress, resource allocation)
  - Image tags can be updated without Terraform apply

### Application Gateway Architecture

The Application Gateway is now part of the `shared_global` module and uses a **data-driven dynamic blocks pattern**:

#### How It Works:

1. **Configuration Files Define Data**:
   - `appgw_base_config.tf` defines static configuration (ports, IPs, SSL certs)
   - `appgw_validator_config.tf` defines validator app routing data (pools, probes, listeners)
   - Additional config files can be added for new applications

2. **Resource File Generates Configuration**:
   - `appgw_resource.tf` uses Terraform dynamic blocks
   - Reads data from config files using `local` variables
   - Generates all backend pools, probes, listeners, and routing rules
   - Single `azurerm_application_gateway` resource with dynamic structure

#### Features:

- **Standard_v2 SKU** with autoscaling (0-10 instances)
- **Zone Redundancy**: Deployed across availability zones 1, 2, 3
- **Dual-Stack Support**: IPv4 + IPv6 frontend configurations
- **TLS 1.2+ enforcement** with Key Vault certificate integration
- **Health Probes**: Custom paths (`/actuator/health` for Spring Boot backends)
- **Path-Based Routing**: Environment-specific URL path maps
  - `/validator/api/*` → Backend API
  - `/validator/api-docs` → Backend API documentation (Swagger UI)
  - `/validator/swagger-ui/*` → Backend Swagger UI resources
  - `/validator/*` → Frontend
- **Hostname-Based Routing**: Support for custom domains per environment
- **Lifecycle Protection**: `prevent_destroy` enabled on gateway and public IPs

#### Adding a New Application:

To add a new application:

1. Create a new configuration file in `modules/shared_global/` (e.g., `appgw_newapp_config.tf`)
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
  - Validator subnet (`/23`) - Currently hosts validator backend and frontend
  - Tool subnet (`/23`) - Reserved for future tool application
- **Application Gateway**: Global, shared across all environments
- **Resource Groups**: 
  - `ismd-shared-{env}` - Shared Container App Environment and networking
  - `ismd-validator-{env}` - Validator-specific resources
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
   cd infrastructure
   ```

2. **Configure variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Authenticate to Azure**:

   Uses your Azure AD account with interactive login:
   ```powershell
   # Login to Azure (will prompt for subscription selection)
   az login
   
   # If you need to specify tenant
   az login --tenant <tenant-id>
   
   # Verify you're logged in and using the correct subscription
   az account show
   ```
   
   **Required Azure RBAC permissions:**
   - `Contributor` role on the subscription
   - `Storage Blob Data Contributor` on the tfstate storage account (`ismdtfstate`)
   
   These two roles provide all necessary permissions to deploy and manage the infrastructure.

### Deployment

#### Initial Deployment (First Time Setup)

**Step 1: Deploy Shared Global Infrastructure**

Deploy the Application Gateway and global networking:

```bash
cd shared-global
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
# Return to root directory
cd ..

# Initialize Terraform (only needed once)
terraform init

# Select workspace (environment)
terraform workspace select dev   # or test, or prod

# Plan and apply changes
terraform plan
terraform apply
```

This creates:
- Shared Container App Environment (`ismd-shared-environment-{env}`)
- Container Apps (validator frontend and backend) with auto-generated FQDNs
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
  terraform workspace select <env>
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
- Repository: `ghcr.io/org/ismd-validator-{backend|frontend}-dev`
- Tag: `latest` (rolling tag)
- Deployed automatically on push to dev branch
- Command: `az containerapp update --name ismd-validator-backend-dev --image ghcr.io/org/app-dev:latest`

**Production Images** (test/prod):
- Repository: `ghcr.io/org/ismd-validator-{backend|frontend}`
- Tag: Version numbers (e.g., `1.0.0`, `1.0.0-abc1234`)
- TEST: Deployed automatically when pushed to main branch
- PROD: Deployed manually via workflow_dispatch

#### Image Tag Validation:

Terraform variable validation allows both `latest` and semantic versioning:
```hcl
validation {
  condition     = var.image_tag == "latest" || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.image_tag))
  error_message = "Tag must be 'latest' or valid version (e.g., '1.0.0' or '1.0.0-abc1234')"
}
```

#### Initial Setup Image Variables:

While Terraform doesn't update images during normal operations, initial container app creation requires base image configuration in `terraform.tfvars`:

```hcl
frontend_image = "ghcr.io/org/ismd-validator-frontend-dev"
frontend_image_tag = "latest"
backend_image = "ghcr.io/org/ismd-validator-backend-dev"
backend_image_tag = "latest"
```

After initial creation, images are managed via `az containerapp update` from application repositories

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

Each application repository (backend/frontend) has independent CI/CD:

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

#### Key Benefits:

- **Independent Deployments**: Application images deploy without Terraform
- **Faster Deployments**: No Terraform overhead for image updates
- **Clear Separation**: Infrastructure changes vs application changes
- **No Cross-Repo Secrets**: Each repo authenticates independently
- **Simplified Workflows**: No `repository_dispatch` between repos

## Remote State Configuration

Terraform state is stored in Azure Storage:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "ismd-shared-tfstate"
    storage_account_name = "ismdtfstate"
    container_name       = "tfstate"
    key                  = "workspace.dev.tfstate"
  }
}
```

**Workspace-based state management**:
- Each environment uses the same backend configuration
- Terraform workspaces isolate state between environments
- State files are automatically managed per workspace

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

Key configuration managed through Terraform:

- **CORS_ALLOWED_ORIGINS**: Backend CORS configuration
- **NEXT_PUBLIC_BE_URL**: Frontend-to-backend communication URL
- **PORT**: Container port configuration (8080)

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
   ```bash
   # Import existing resources to avoid destruction
   terraform import module.dev[0].azurerm_resource_group.shared /subscriptions/.../resourceGroups/...
   ```

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

## Architecture Patterns

### Data-Driven Configuration with Dynamic Blocks

The Application Gateway uses a data-driven pattern that separates configuration data from resource structure:

- **Configuration files** (`appgw_*_config.tf`) define data in `locals`
- **Resource file** (`appgw_resource.tf`) uses dynamic blocks to generate configuration
- **Benefits**: Easy to add new applications without modifying existing configuration

#### Adding a New Application

1. Create `modules/shared_global/appgw_newapp_config.tf` with configuration data
2. Update `appgw_resource.tf` to include the new config in dynamic blocks
3. Existing application configurations remain unchanged

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

- **Removed**: `modules/validator_environment` (dedicated per-app environment)
- **Added**: `modules/shared` (consolidated shared environment for all apps)
- **Updated**: All container app definitions include `lifecycle { ignore_changes = [template[0].container[0].image] }`
- **Subnet Planning**: Added tool subnet (`/23`) alongside validator subnet for future applications

#### Workflow Changes:

- **Removed**: `repository_dispatch` triggers between infrastructure and application repos
- **Simplified**: Infrastructure workflows run manually only when infrastructure changes
- **Added**: Direct `az containerapp update` commands in application deployment workflows
- **Enhanced**: Image validation before deployment in application workflows

## Notes

- The load balancer and IP resources that were created automatically when deploying the container application can be imported into Terraform using the `terraform import` command or by using the Azure Export for Terraform tool.
- When adding a new application, follow the data-driven pattern: create a new configuration file and update the resource file to include it.
- Container images should be deployed via application repository workflows, not Terraform.

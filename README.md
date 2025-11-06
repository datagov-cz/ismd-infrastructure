# Azure Infrastructure as Terraform Code

This repository contains Terraform configurations for managing Azure Container Apps infrastructure with Application Gateway across multiple environments (dev, test, prod).

## Architecture Overview

- **Azure Container Apps**: Serverless container platform with auto-scaling
- **Application Gateway**: Shared global load balancer with WAF capabilities and dual-stack (IPv4 + IPv6) support
- **Multi-Environment**: Dev, Test, and Prod environments with consistent configuration
- **Networking**: VNet with properly sized subnets for Container Apps and App Gateway, with VNet peering between environments
- **State Management**: Azure Storage backend for team collaboration
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
│   ├── shared/                  # Environment-specific shared resources
│   ├── shared_global/           # Global shared resources (App Gateway, VNet)
│   │   ├── appgw_base_config.tf       # App Gateway base configuration
│   │   ├── appgw_validator_config.tf  # Validator app routing configuration
│   │   ├── appgw_resource.tf          # App Gateway resource (dynamic blocks)
│   │   ├── networking.tf              # VNet, subnets, public IPs
│   │   ├── resource_group.tf          # Global resource group
│   │   ├── outputs.tf                 # Module outputs
│   │   └── variables.tf               # Module variables
│   ├── validator_environment/   # Container App Environment & Log Analytics
│   └── validator_apps/          # Frontend & Backend Container Apps
│       ├── backend.tf           # Backend container app
│       ├── frontend.tf          # Frontend container app
│       ├── outputs.tf           # Module outputs
│       ├── variables.tf         # Module variables
│       └── main.tf              # Documentation
├── shared-global/               # Shared global infrastructure state
│   ├── main.tf                  # Shared global module configuration
│   ├── backend.tf               # Backend configuration
│   └── variables.tf             # Input variables
├── .github/workflows/           # CI/CD pipelines
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

### Validator Environment Module (`modules/validator_environment/`)

Manages the Container Apps platform infrastructure:

- **Resource Group**: Application-specific resources (`ismd-validator-{env}`)
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Virtual Network**: Environment-specific VNet with VNet peering to shared global VNet
- **Container App Environment**: 
  - All environments (Dev/Test/Prod): Dedicated D4 profile with VNet integration
  - Zone redundancy enabled only in production

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

The infrastructure supports three environments with aligned configurations:

| Environment | Profile | Scaling | Use Case | Shared Resources |
|-------------|---------|---------|----------|------------------|
| **dev** | Consumption | Scale to zero | Development, cost-optimized | App Gateway, Global VNet |
| **test** | Dedicated D4 | Always-on | Testing, staging | App Gateway, Global VNet |
| **prod** | Dedicated D4 | Always-on | Production workloads | App Gateway, Global VNet |

All environments share the same Application Gateway in the global shared resource group and use the same conditional creation and module structure for consistency and maintainability. The environments are fully aligned with identical configuration patterns.

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

The infrastructure requires a specific deployment order due to dependencies between the Application Gateway and Container Apps.

#### Initial Deployment (First Time Setup)

**Step 1: Deploy Shared Global Infrastructure (Initial)**

Deploy the Application Gateway and networking without app-specific routing:

```bash
cd shared-global
terraform init
terraform plan
terraform apply
```

This creates:
- Application Gateway (with base configuration)
- Global VNet and subnets
- Public IP addresses (IPv4 + IPv6)

**Step 2: Deploy Environment-Specific Infrastructure (Container Apps)**

Deploy each environment to create the container apps and get their FQDNs:

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
- Container App Environment
- Container Apps (frontend and backend) with auto-generated FQDNs
- Environment-specific networking and VNet peering

**Step 3: Update Shared Global with App FQDNs**

After deploying the apps, update the shared global default variables with the container app FQDNs:

1. Get the FQDNs from the terraform outputs (from step 2)
2. Update `shared-global/variables.tf` with the actual FQDNs
3. Re-deploy shared global:

```bash
cd shared-global
terraform plan  # Review the routing changes
terraform apply
```

This updates:
- Application Gateway backend pools with actual container app FQDNs
- Routing rules now correctly point to the deployed apps

#### Subsequent Deployments

After initial setup, you can deploy changes independently:

- **Container app updates** (image changes): Deploy from root with appropriate workspace
- **Application Gateway updates** (routing changes): Deploy from `shared-global/`
- **New environments**: Follow the 3-step process above

### Container Image Management

The infrastructure deploys containerized applications with configurable image tags:

```bash
# Deploy with specific image versions
terraform apply \
  -var="frontend_image_tag=0.1.0-c255c74" \
  -var="backend_image_tag=0.0.1-snapshot-deff379"
```

Image variables in `terraform.tfvars`:
- `frontend_image`: Base image URL for the frontend
- `frontend_image_tag`: Specific version tag
- `backend_image`: Base image URL for the backend  
- `backend_image_tag`: Specific version tag

### GitHub Actions CI/CD

The repository includes automated workflows for infrastructure and application deployment:

#### Application Repositories:
- **CI Workflow**: Tests on PRs and dev branch pushes
- **Build Docker on Dev**: Builds images after successful CI on dev branch
- **Release Version**: Creates releases to main with version management
- **Build Docker on Main**: Builds test/production images on main branch

#### Infrastructure Repository:
- **Deploy Infrastructure**: Handles infrastructure deployment with environment selection
  - Supports two-phase apply when needed (for new App Gateway deployment)
  - Automatic detection of existing App Gateway
  - Uses conditional module creation (`create_environment` and `create_apps` variables)
- **Cross-Repo Integration**: App repositories trigger infrastructure deployment with updated images

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

## Notes

- The load balancer and IP resources that were created automatically when deploying the container application can be imported into Terraform using the `terraform import` command or by using the Azure Export for Terraform tool.
- When adding a new application, follow the data-driven pattern: create a new configuration file and update the resource file to include it.

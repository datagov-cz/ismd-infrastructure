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
│   ├── shared/        # Environment-specific shared resources
│   ├── shared_global/ # Global shared resources (App Gateway, VNet)
│   ├── validator_environment/  # Container App Environment & Log Analytics
│   └── validator_apps/         # Frontend & Backend Container Apps
├── .github/workflows/          # CI/CD pipelines
├── main.tf                     # Root configuration with environment module calls
├── backend.tf                  # Azure Storage backend configuration
├── variables.tf                # Input variable definitions
├── outputs.tf                  # Root module outputs
├── terraform.tfvars.example    # Example variables (copy to terraform.tfvars)
├── docker-compose.yml          # Base Docker Compose configuration
├── docker-compose.dev.yml      # Development Docker Compose overrides
└── docker-compose.local.yml    # Local development Docker Compose overrides
```

## Modules

### Shared Global Module (`modules/shared_global/`)

Manages global shared infrastructure that spans all environments:

- **Resource Group**: Global shared resources container (`ismd-shared-global`)
- **Virtual Network**: Global VNet with dedicated CIDR (IPv4 + IPv6 dual-stack)
- **Application Gateway**: Shared load balancer with path-based routing for all environments
- **Public IP**: Static IP addresses (IPv4 + IPv6) with prevent_destroy lifecycle protection
- **Subnets**: App Gateway subnet (`/24` IPv4, `/64` IPv6 - for dual-stack load balancer)

### Validator Environment Module (`modules/validator_environment/`)

Manages the Container Apps platform infrastructure:

- **Resource Group**: Application-specific resources (`ismd-validator-{env}`)
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Virtual Network**: Environment-specific VNet with VNet peering to shared global VNet
- **Container App Environment**: 
  - All environments (Dev/Test/Prod): Dedicated D4 profile with VNet integration
  - Zone redundancy enabled only in production

### Validator Apps Module (`modules/validator_apps/`)

Manages the application containers:

- **Frontend Container App**: Next.js application with external ingress
- **Backend Container App**: Spring Boot API with internal ingress
- **Environment Variables**: Automatic configuration for inter-service communication
- **Resource Allocation**: Optimized CPU/memory combinations per environment
- **Conditional Creation**: Support for phased deployments with `create_apps` variable

### Application Gateway Module (`modules/app_gateway/`)

Manages the load balancer and SSL termination (Note: This module is now integrated into shared_global):

- **Public IP**: Static IP with DNS label for external access and prevent_destroy lifecycle protection
- **Application Gateway**: Standard_v2 SKU with:
  - TLS 1.2+ enforcement
  - Backend health probes with custom paths (`/actuator/health` for backend)
  - Path-based routing rules for multiple environments
  - SSL certificate management
  - Support for multiple backend pools across environments

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

3. **Login to Azure**:
   ```bash
   az login
   ```

4. **Run Terraform commands using the helper script**:
   - PowerShell (Windows):
     ```powershell
     # Run plan
     .\tf.ps1 plan
     
     # Run apply
     .\tf.ps1 apply
     
     # Specify environment (dev/test/prod)
     .\tf.ps1 -Environment test plan
     
     # Pass additional arguments to terraform
     .\tf.ps1 apply -auto-approve
     ```
   
   - Bash (Linux/macOS/WSL):
     ```bash
     # Make the script executable
     chmod +x tf.sh
     
     # Run plan
     ./tf.sh plan
     
     # Run apply
     ./tf.sh apply
     
     # Specify environment (dev/test/prod)
     ./tf.sh plan test
     
     # Pass additional arguments to terraform
     ./tf.sh apply -auto-approve
     ```

   The helper scripts will automatically:
   - Get your Azure subscription ID
   - Set up the required environment variables
   - Initialize Terraform if needed
   - Run the specified command with the correct context

### Deployment

1. **Initialize Terraform**:
   ```bash
   # This only needs to be done once.
   terraform init
   ```

2. **Select workspace** (environment):
   ```bash
   # For development
   terraform workspace select dev
   
   # For test
   terraform workspace select test
   
   # For production
   terraform workspace select prod
   ```

3. **Plan and apply changes**:
   ```bash
   terraform plan
   terraform apply
   ```

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
- **Build Docker on Dev**: Builds images after successful CI
- **Release Version**: Creates releases with version management
- **Build Docker on Main**: Builds production images on main branch

#### Infrastructure Repository:
- **Deploy Infrastructure**: Handles infrastructure deployment with environment selection
  - Supports two-phase apply when needed (for new App Gateway deployment)
  - Automatic detection of existing App Gateway
  - Uses conditional module creation (`create_environment` and `create_apps` variables)
- **Cross-Repo Integration**: App repositories trigger infrastructure deployment with updated images

## Remote State Configuration

Terraform state is stored in Azure Storage for team collaboration:

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
- **Internal Communication**: Backend uses internal ingress (not externally accessible)
- **Resource Protection**: Critical resources have `prevent_destroy` lifecycle rules

## Troubleshooting

### Common Issues

1. **Subnet Size Errors**:
   - Container Apps require `/23` minimum for Consumption profile
   - Ensure no subnet overlaps in VNet configuration

2. **Container App Environment Errors**:
   - Dev (Consumption): `infrastructure_subnet_id` must be `null`
   - Prod (Dedicated): `infrastructure_subnet_id` required

3. **Resource Import**:
   ```bash
   # Import existing resources to avoid destruction
   terraform import module.dev[0].azurerm_resource_group.shared /subscriptions/.../resourceGroups/...
   ```

4. **CORS Issues**:
   - Verify `pick_host_name_from_backend_address = true` in App Gateway
   - Check backend CORS_ALLOWED_ORIGINS includes App Gateway IP

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

## Support

For issues with this infrastructure:

1. Check the troubleshooting section above
2. Review Azure resource logs in the Log Analytics workspace
3. Verify Terraform state consistency
4. Contact the infrastructure team

## Notes

- The load balancer and IP resources that were created automatically when deploying the container application can be imported into Terraform using the `terraform import` command or by using the Azure Export for Terraform tool.
- When adding a new application, create a new module in the `modules` directory and reference it from the environment configurations.

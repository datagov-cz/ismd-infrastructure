# Azure Infrastructure as Terraform Code

This repository contains Terraform configurations for managing Azure Container Apps infrastructure with Application Gateway across multiple environments (dev, test, prod).

## Architecture Overview

- **Azure Container Apps**: Serverless container platform with auto-scaling
- **Application Gateway**: Load balancer with WAF capabilities and dual-stack (IPv4 + IPv6) support
- **Multi-Environment**: Dev (Consumption profile), Test/Prod (Dedicated profiles)
- **Networking**: VNet with properly sized subnets for Container Apps and App Gateway
- **State Management**: Azure Storage backend for team collaboration

## State Management

This project uses Azure Storage for Terraform state management. The state configuration is defined in `backend.tf` but requires explicit key specification during initialization.

### State Files

Each environment has its own dedicated state file:
- Development: `workspace.dev.tfstate`
- Test: `workspace.test.tfstate`
- Production: `workspace.prod.tfstate`

### State Storage

- **Resource Group**: `ismd-shared-tfstate`
- **Storage Account**: `ismdtfstate`
- **Container**: `tfstate`

> **IMPORTANT**: The state file key is intentionally omitted from `backend.tf` and must be specified during initialization to prevent accidental state conflicts.

## Directory Structure

```
├── environments/
│   ├── dev/           # Development environment configuration
│   ├── test/          # Test environment configuration
│   └── prod/          # Production environment configuration
├── modules/
│   ├── shared/        # Shared networking resources
│   ├── validator_environment/  # Container App Environment & Log Analytics
│   ├── validator_apps/         # Frontend & Backend Container Apps
│   └── app_gateway/            # Application Gateway configuration
├── .github/workflows/          # CI/CD pipelines (in development)
├── main.tf                     # Root configuration with workspace logic
├── backend.tf                  # Azure Storage backend configuration
├── variables.tf                # Input variable definitions
├── terraform.tfvars.example    # Example variables (copy to terraform.tfvars)
└── docker-compose*.yml         # Local development files
```

## Modules

### Shared Module (`modules/shared/`)

Manages shared networking infrastructure for each environment:

- **Resource Group**: Shared resources container (`ismd-shared-{env}`)
- **Virtual Network**: Main VNet with environment-specific CIDR (IPv4 + IPv6 dual-stack)
- **Subnets**: 
  - App Gateway subnet (`/24` IPv4, `/64` IPv6 - for dual-stack load balancer)
  - Container Apps subnet (`/23` - for container workloads)

### Validator Environment Module (`modules/validator_environment/`)

Manages the Container Apps platform infrastructure:

- **Resource Group**: Application-specific resources (`ismd-validator-{env}`)
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Container App Environment**: 
  - Dev: Consumption profile (cost-optimized, scales to zero)
  - Test/Prod: Dedicated D4 profile (consistent performance)

### Validator Apps Module (`modules/validator_apps/`)

Manages the application containers:

- **Frontend Container App**: Next.js application with external ingress
- **Backend Container App**: Spring Boot API with internal ingress
- **Environment Variables**: Automatic configuration for inter-service communication
- **Resource Allocation**: Optimized CPU/memory combinations per environment

### Application Gateway Module (`modules/app_gateway/`)

Manages the load balancer and SSL termination:

- **Public IP**: Static IP with DNS label for external access
- **Application Gateway**: Standard_v2 SKU with:
  - TLS 1.2+ enforcement
  - Backend health probes
  - Path-based routing rules
  - SSL certificate management

## Environments

The infrastructure supports three environments with different configurations:

| Environment | Profile | Scaling | Use Case |
|-------------|---------|---------|----------|
| **dev** | Consumption | Scale to zero | Development, cost-optimized |
| **test** | Dedicated D4 | Always-on | Testing, staging |
| **prod** | Dedicated D4 | Always-on | Production workloads |

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
   az account set --subscription "your-subscription-id"
   ```

### Deployment

1. **Initialize Terraform**:
   ```bash
   # IMPORTANT: You must specify the state file key for your environment
   # This ensures the correct state file is used and prevents accidental state conflicts
   
   # For development
   terraform init -backend-config="key=workspace.dev.tfstate"
   
   # For test
   terraform init -backend-config="key=workspace.test.tfstate"
   
   # For production
   terraform init -backend-config="key=workspace.prod.tfstate"
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

The repository includes automated workflows:

- **CI Workflow**: Tests on PRs and dev branch pushes
- **Build Docker on Dev**: Builds images after successful CI
- **Release Version**: Creates releases with version management
- **Build Docker on Main**: Builds production images on main branch

## Remote State Configuration

Terraform state is stored in Azure Storage for team collaboration. The backend configuration in `backend.tf` intentionally omits the key to prevent accidental state conflicts:

```hcl
terraform {
  backend "azurerm" {
    # IMPORTANT: The state file key is intentionally omitted here
    resource_group_name  = "ismd-shared-tfstate"
    storage_account_name = "ismdtfstate"
    container_name       = "tfstate"
    # key must be specified via -backend-config during terraform init
  }
}
```

**Environment-specific state management**:
- Each environment requires explicit key specification during initialization
- Keys follow the pattern `workspace.[environment].tfstate`
- This approach prevents accidental state conflicts between environments

**Example initialization commands**:
```bash
# For development
terraform init -backend-config="key=workspace.dev.tfstate"

# For test
terraform init -backend-config="key=workspace.test.tfstate"

# For production
terraform init -backend-config="key=workspace.prod.tfstate"
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

## Additional Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Application Gateway Documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Notes

- The load balancer and IP resources that were created automatically when deploying the container application can be imported into Terraform using the `terraform import` command or by using the Azure Export for Terraform tool.
- When adding a new application, create a new module in the `modules` directory and reference it from the environment configurations.

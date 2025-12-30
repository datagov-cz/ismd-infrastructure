# Production Environment Configuration

# Variables for the production environment
variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "germanywestcentral"
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
  default     = "ismd-shared-prod"
}

variable "validator_resource_group_name" {
  description = "Name of the validator resource group"
  type        = string
  default     = "ismd-validator-prod"
}

variable "tool_resource_group_name" {
  description = "Name of the tool resource group"
  type        = string
  default     = "ismd-tool-prod"
}

variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend"
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image (e.g., 'latest', '1.0.0' or '1.0.0-abc1234')"
  type        = string
  default     = "latest"

  validation {
    condition     = var.frontend_image_tag == "latest" || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.frontend_image_tag))
    error_message = "The frontend_image_tag must be 'latest' or a valid version number (e.g., '1.0.0' or '1.0.0-abc1234')."
  }
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend"
}

variable "backend_image_tag" {
  description = "Tag for the backend container image (e.g., 'latest', '1.0.0' or '1.0.0-abc1234')"
  type        = string
  default     = "latest"

  validation {
    condition     = var.backend_image_tag == "latest" || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.backend_image_tag))
    error_message = "The backend_image_tag must be 'latest' or a valid version number (e.g., '1.0.0' or '1.0.0-abc1234')."
  }
}

variable "tool_frontend_image" {
  description = "Base container image URL for the tool frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-tool-frontend"
}

variable "tool_frontend_image_tag" {
  description = "Tag for the tool frontend container image"
  type        = string
  default     = "latest"
}

variable "tool_backend_image" {
  description = "Base container image URL for the tool backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-tool-backend"
}

variable "tool_backend_image_tag" {
  description = "Tag for the tool backend container image"
  type        = string
  default     = "latest"
}

# Variables for connecting to the shared global network
variable "shared_global_vnet_id" {
  description = "ID of the shared global VNet"
  type        = string
}

variable "shared_global_vnet_name" {
  description = "Name of the shared global VNet"
  type        = string
}

variable "shared_global_resource_group_name" {
  description = "Name of the shared global resource group"
  type        = string
}

variable "app_gateway_public_ip_address" {
  description = "Public IP address of the shared Application Gateway"
  type        = string
}

variable "app_gateway_hostname" {
  description = "Hostname for the production environment (e.g., xn--slovnk-7va.gov.cz)"
  type        = string
  default     = "xn--slovnk-7va.gov.cz"
}

variable "frontend_app_name" {
  description = "Name of the frontend application"
  type        = string
  default     = "ismd-validator-frontend"
}

variable "backend_app_name" {
  description = "Name of the backend application"
  type        = string
  default     = "ismd-validator-backend"
}

variable "tool_frontend_app_name" {
  description = "Name of the tool frontend application"
  type        = string
  default     = "ismd-tool-frontend"
}

variable "tool_backend_app_name" {
  description = "Name of the tool backend application"
  type        = string
  default     = "ismd-tool-backend"
}

# Tool Database & Fuseki Configuration
variable "tool_postgres_url" {
  description = "JDBC URL for Tool PostgreSQL"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_postgres_user" {
  description = "Tool PostgreSQL username"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_postgres_password" {
  description = "Tool PostgreSQL password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_fuseki_url" {
  description = "URL for Tool Fuseki"
  type        = string
  default     = ""
}

variable "tool_nextauth_secret" {
  description = "NextAuth.js secret for Tool frontend"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_fuseki_admin_password" {
  description = "Admin password for Tool Fuseki"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "additional_cors_origins" {
  description = "List of additional CORS origins to allow"
  type        = list(string)
  default     = []
}

variable "deploy_tool_apps" {
  description = "Whether to deploy Tool apps (set to false to deploy only Validator)"
  type        = bool
  default     = true
}

# Validator resource group
resource "azurerm_resource_group" "validator" {
  name     = var.validator_resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "Validator"
  }
}

resource "azurerm_resource_group" "tool" {
  count    = var.deploy_tool_apps ? 1 : 0
  name     = var.tool_resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "Tool"
  }
}

# Shared resources (networking, resource groups, etc.)
module "shared" {
  source = "../../modules/shared"

  environment                     = var.environment
  location                        = var.location
  resource_group_name             = var.shared_resource_group_name
  vnet_address_space              = "10.3.0.0/16"        # PROD: 10.3.x.x
  vnet_address_space_ipv6         = "fd00:db8:decd::/48" # PROD: unique IPv6
  validator_subnet_address_prefix = "10.3.2.0/23"        # PROD: within 10.3.0.0/16
  tool_subnet_address_prefix      = "10.3.4.0/23"        # PROD: within 10.3.0.0/16
}

# Create validator apps using shared Container App Environment
module "validator_apps" {
  source = "../../modules/validator_apps"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.validator_resource_group_name

  # Required by the module
  shared_resource_group_name               = var.shared_resource_group_name
  container_app_environment_id             = module.shared.shared_container_app_environment_id
  container_app_environment_default_domain = module.shared.shared_container_app_environment_default_domain

  # Container Images
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # IP Restrictions
  app_gateway_public_ip = var.app_gateway_public_ip_address
  app_gateway_hostname  = var.app_gateway_hostname

  # CORS
  additional_cors_origins = var.additional_cors_origins

  # App names
  frontend_app_name = var.frontend_app_name
  backend_app_name  = var.backend_app_name

  # Workload profile configuration
  workload_profile_name = "default"
  workload_profile_type = "D4"
  
  depends_on = [
    module.shared,
    azurerm_resource_group.validator
  ]
}

# Create tool apps using shared Container App Environment
module "tool_apps" {
  count  = var.deploy_tool_apps ? 1 : 0
  source = "../../modules/tool_apps"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.tool_resource_group_name

  # Required by the module
  shared_resource_group_name               = var.shared_resource_group_name
  container_app_environment_id             = module.shared.shared_container_app_environment_id
  container_app_environment_default_domain = module.shared.shared_container_app_environment_default_domain

  # Container Images
  frontend_image     = var.tool_frontend_image
  frontend_image_tag = var.tool_frontend_image_tag
  backend_image      = var.tool_backend_image
  backend_image_tag  = var.tool_backend_image_tag

  # IP Restrictions
  app_gateway_public_ip = var.app_gateway_public_ip_address
  app_gateway_hostname  = var.app_gateway_hostname

  # CORS
  additional_cors_origins = var.additional_cors_origins

  # App names
  frontend_app_name = var.tool_frontend_app_name
  backend_app_name  = var.tool_backend_app_name

  # Workload profile configuration
  workload_profile_name = "default"
  workload_profile_type = "D4"

  # Database & Fuseki Configuration
  deploy_postgres         = true
  deploy_fuseki           = true
  postgres_db_name        = "ismd_tool_db"
  postgres_admin_user     = "ismdadmin"
  postgres_admin_password = var.tool_postgres_password
  postgres_sku_name       = "GP_Standard_D2s_v3"  # General Purpose for prod
  postgres_storage_mb     = 65536                  # 64GB for prod
  fuseki_admin_password   = var.tool_fuseki_admin_password
  
  # Fallback external URLs (used if deploy_postgres/fuseki = false)
  postgres_url      = var.tool_postgres_url
  postgres_user     = var.tool_postgres_user
  postgres_password = var.tool_postgres_password
  fuseki_url        = var.tool_fuseki_url

  # Frontend auth
  nextauth_secret = var.tool_nextauth_secret
  
  depends_on = [
    module.shared,
    azurerm_resource_group.tool[0]
  ]
}

# Outputs
output "shared_resource_group_name" {
  value = module.shared.resource_group_name
}

output "validator_resource_group_name" {
  value = azurerm_resource_group.validator.name
}

output "app_gateway_public_ip" {
  value = var.app_gateway_public_ip_address
}

output "validator_frontend_fqdn" {
  value = module.validator_apps.frontend_fqdn
}

output "validator_backend_fqdn" {
  value = module.validator_apps.backend_fqdn
}

output "tool_frontend_fqdn" {
  value = var.deploy_tool_apps ? module.tool_apps[0].frontend_fqdn : null
}

output "tool_backend_fqdn" {
  value = var.deploy_tool_apps ? module.tool_apps[0].backend_fqdn : null
}

output "shared_container_app_environment_id" {
  description = "ID of the shared Container App Environment"
  value       = module.shared.shared_container_app_environment_id
}

output "shared_container_app_environment_name" {
  description = "Name of the shared Container App Environment"
  value       = module.shared.shared_container_app_environment_name
}

# VNet Peering from this environment's VNet to the shared global VNet
resource "azurerm_virtual_network_peering" "env_to_shared" {
  count                        = var.shared_global_vnet_id != "" ? 1 : 0
  name                         = "peer-${var.environment}-to-global"
  resource_group_name          = module.shared.resource_group_name
  virtual_network_name         = module.shared.virtual_network_name
  remote_virtual_network_id    = var.shared_global_vnet_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = false
  use_remote_gateways          = false # Set to false since there's no gateway in the global VNet
}

# VNet Peering from the shared global VNet back to this environment's VNet
resource "azurerm_virtual_network_peering" "shared_to_env" {
  count                        = var.shared_global_vnet_name != "" ? 1 : 0
  name                         = "peer-global-to-${var.environment}"
  resource_group_name          = var.shared_global_resource_group_name
  virtual_network_name         = var.shared_global_vnet_name
  remote_virtual_network_id    = module.shared.virtual_network_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = false # Set to false since there's no gateway in the global VNet
  use_remote_gateways          = false
}

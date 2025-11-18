# Dev Environment Configuration

# Variables for the dev environment
variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "germanywestcentral"
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
  default     = "ismd-shared-dev"
}

variable "validator_resource_group_name" {
  description = "Name of the validator resource group"
  type        = string
  default     = "ismd-validator-dev"
}

variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend-dev"
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image (e.g., 'latest', '1.0.0' or '1.0.0-abc1234')"
  type        = string

  validation {
    condition     = var.frontend_image_tag == "latest" || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.frontend_image_tag))
    error_message = "The frontend_image_tag must be 'latest' or a valid version number (e.g., '1.0.0' or '1.0.0-abc1234')."
  }
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend-dev"
}



variable "backend_image_tag" {
  description = "Tag for the backend container image (e.g., 'latest', '1.0.0' or '1.0.0-abc1234')"
  type        = string

  validation {
    condition     = var.backend_image_tag == "latest" || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.backend_image_tag))
    error_message = "The backend_image_tag must be 'latest' or a valid version number (e.g., '1.0.0' or '1.0.0-abc1234')."
  }
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
  description = "Hostname for the dev environment (e.g., ismd.oha03.dia.gov.cz)"
  type        = string
  default     = "" # Empty for now - uses IP until DNS is working
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

# Validator resource group (moved from old validator_environment module)
resource "azurerm_resource_group" "validator" {
  name     = var.validator_resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "Validator"
  }
}

# Shared resources (networking, resource groups, etc.)
module "shared" {
  source = "../../modules/shared"

  environment                     = var.environment
  location                        = var.location
  resource_group_name             = var.shared_resource_group_name
  vnet_address_space              = "10.0.0.0/16"        # DEV: 10.0.x.x (default, already deployed)
  vnet_address_space_ipv6         = "fd00:db8:deca::/48" # DEV: default IPv6 (already deployed)
  validator_subnet_address_prefix = "10.0.2.0/23"        # DEV: within 10.0.0.0/16 (already deployed)
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
  resource_group_name          = var.shared_resource_group_name
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

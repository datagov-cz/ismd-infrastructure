# Test Environment Configuration

# Variables for the test environment
variable "create_environment" {
  description = "Whether to create the container app environment"
  type        = bool
  default     = true
}

variable "create_apps" {
  description = "Whether to create the container apps"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "test"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "germanywestcentral"
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
  default     = "ismd-shared-test"
}

variable "validator_resource_group_name" {
  description = "Name of the validator resource group"
  type        = string
  default     = "ismd-validator-test"
}

variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend-test"
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image (e.g., '1.0.0' or '1.0.0-abc1234' for development)"
  type        = string
  
  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.frontend_image_tag))
    error_message = "The frontend_image_tag must be a valid version number (e.g., '1.0.0' or '1.0.0-abc1234')."
  }
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend-test"
}

variable "backend_image_tag" {
  description = "Tag for the backend container image (e.g., '1.0.0' or '1.0.0-abc1234' for development)"
  type        = string
  
  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.backend_image_tag))
    error_message = "The backend_image_tag must be a valid version number (e.g., '1.0.0' or '1.0.0-abc1234')."
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
  description = "Hostname for the test environment (e.g., ismd.xn--slovnk-test-scb.dia.gov.cz)"
  type        = string
  default     = "ismd.xn--slovnk-test-scb.dia.gov.cz"
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

variable "container_app_environment_id" {
  description = "ID of the container app environment"
  type        = string
  default     = ""
}


variable "container_app_environment_default_domain" {
  description = "Default domain of the container app environment"
  type        = string
  default     = ""
}

# Shared resources (networking, resource groups, etc.)
module "shared" {
  # Remove count to ensure stable resource addressing
  # count  = var.create_environment ? 1 : 0
  source = "../../modules/shared"
  
  environment                      = var.environment
  location                         = var.location
  resource_group_name              = var.shared_resource_group_name
  vnet_address_space               = "10.2.0.0/16"        # TEST: 10.2.x.x (avoids conflict with shared-global 10.1.x.x)
  vnet_address_space_ipv6          = "fd00:db8:decc::/48" # TEST: unique IPv6
  validator_subnet_address_prefix  = "10.2.2.0/23"        # TEST: within 10.2.0.0/16
}

# Create the container app environment if requested
module "validator_environment" {
  count  = var.create_environment ? 1 : 0
  source = "../../modules/validator_environment"

  environment        = var.environment
  location           = var.location
  resource_group_name = var.validator_resource_group_name
  subnet_id          = var.create_environment ? module.shared.validator_subnet_id : ""
  
  depends_on = [module.shared]
}

# Create the container apps if requested
module "validator_apps" {
  count  = var.create_apps ? 1 : 0
  source = "../../modules/validator_apps"

  environment        = var.environment
  location           = var.location
  resource_group_name = var.validator_resource_group_name
  
  # Required by the module
  shared_resource_group_name = var.shared_resource_group_name
  container_app_environment_id = var.create_environment ? module.validator_environment[0].container_app_environment_id : var.container_app_environment_id
  container_app_environment_default_domain = var.create_environment ? module.validator_environment[0].default_domain : var.container_app_environment_default_domain
  
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
  
  # Workload profile configuration - using Dedicated profile for VNet integration
  workload_profile_name = "default"
  workload_profile_type = "D4"
  depends_on = [
    module.validator_environment
  ]
}

# Outputs
output "shared_resource_group_name" {
  value = module.shared.resource_group_name
}

output "validator_resource_group_name" {
  value = length(module.validator_environment) > 0 ? module.validator_environment[0].resource_group_name : ""
}

output "app_gateway_public_ip" {
  value = var.app_gateway_public_ip_address
}

output "validator_frontend_fqdn" {
  value = length(module.validator_apps) > 0 ? module.validator_apps[0].frontend_fqdn : ""
}

output "validator_backend_fqdn" {
  value = length(module.validator_apps) > 0 ? module.validator_apps[0].backend_fqdn : ""
}

output "container_app_environment_id" {
  value = length(module.validator_environment) > 0 ? module.validator_environment[0].container_app_environment_id : ""
}

output "container_app_environment_name" {
  value = length(module.validator_environment) > 0 ? module.validator_environment[0].container_app_environment_name : ""
}

# VNet Peering from this environment's VNet to the shared global VNet
resource "azurerm_virtual_network_peering" "env_to_shared" {
  count                       = var.shared_global_vnet_id != "" ? 1 : 0
  name                         = "peer-${var.environment}-to-global"
  resource_group_name          = var.shared_resource_group_name
  virtual_network_name         = module.shared.virtual_network_name
  remote_virtual_network_id    = var.shared_global_vnet_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = false
  use_remote_gateways          = false  # Set to false since there's no gateway in the global VNet
}

# VNet Peering from the shared global VNet back to this environment's VNet
resource "azurerm_virtual_network_peering" "shared_to_env" {
  count                       = var.shared_global_vnet_name != "" ? 1 : 0
  name                         = "peer-global-to-${var.environment}"
  resource_group_name          = var.shared_global_resource_group_name
  virtual_network_name         = var.shared_global_vnet_name
  remote_virtual_network_id    = module.shared.virtual_network_id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = false  # Set to false since there's no gateway in the global VNet
  use_remote_gateways          = false
}

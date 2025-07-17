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

variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend"
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image"
  type        = string
  # No default here - it should be provided by the root module
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend"
}

variable "backend_image_tag" {
  description = "Tag for the backend container image"
  type        = string
  # No default here - it should be provided by the root module
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

# Shared resources module
module "shared" {
  source              = "../../modules/shared"
  environment         = var.environment
  location            = var.location
  resource_group_name = var.shared_resource_group_name
}

# Step 1: Create the container app environment first
module "validator_environment" {
  source = "../../modules/validator_environment"

  environment        = var.environment
  location           = var.location
  resource_group_name = var.validator_resource_group_name
  subnet_id          = module.shared.validator_subnet_id
  
  depends_on = [module.shared]
}

# Step 2: Create the container apps with ingress restriction to the shared App Gateway public IP
module "validator_apps" {
  source = "../../modules/validator_apps"

  environment               = var.environment
  location                  = var.location
  resource_group_name       = var.validator_resource_group_name
  shared_resource_group_name = var.shared_resource_group_name
  container_app_environment_id = module.validator_environment.container_app_environment_id
  app_gateway_public_ip     = var.app_gateway_public_ip_address
  frontend_image            = var.frontend_image
  frontend_image_tag        = var.frontend_image_tag
  backend_image             = var.backend_image
  backend_image_tag         = var.backend_image_tag
  container_app_environment_default_domain = module.validator_environment.default_domain
  
  depends_on = [
    module.validator_environment
  ]
}

# Outputs
output "shared_resource_group_name" {
  value = module.shared.resource_group_name
}

output "validator_resource_group_name" {
  value = module.validator_environment.resource_group_name
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

output "container_app_environment_id" {
  value = module.validator_environment.container_app_environment_id
}

output "container_app_environment_name" {
  value = module.validator_environment.container_app_environment_name
}

# VNet Peering from this environment's VNet to the shared global VNet
resource "azurerm_virtual_network_peering" "env_to_shared" {
  name                         = "peer-${var.environment}-to-global"
  resource_group_name          = module.shared.resource_group_name
  virtual_network_name         = module.shared.virtual_network_name
  remote_virtual_network_id    = var.shared_global_vnet_id
  allow_gateway_transit        = false
  use_remote_gateways          = true # Use the gateway in the shared_global VNet
}

# VNet Peering from the shared global VNet back to this environment's VNet
resource "azurerm_virtual_network_peering" "shared_to_env" {
  name                         = "peer-global-to-${var.environment}"
  resource_group_name          = var.shared_global_resource_group_name
  virtual_network_name         = var.shared_global_vnet_name
  remote_virtual_network_id    = module.shared.virtual_network_id
  allow_gateway_transit        = true # Allow the gateway in this VNet to be used by the peered VNet
  use_remote_gateways          = false
}

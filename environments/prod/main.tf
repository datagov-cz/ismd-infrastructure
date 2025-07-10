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

# Step 2: Create the Application Gateway with constructed FQDNs
module "app_gateway" {
  source = "../../modules/app_gateway"
  
  environment                   = var.environment
  location                      = var.location
  resource_group_name           = var.shared_resource_group_name
  subnet_id                     = module.shared.application_gateway_subnet_id
  frontend_app_name             = "ismd-validator-frontend"
  backend_app_name              = "ismd-validator-backend"
  region                        = var.location
  container_app_environment_default_domain = module.validator_environment.default_domain
  
  depends_on = [
    module.shared,
    module.validator_environment
  ]
}

# Step 3: Get the Application Gateway public IP for outputs and container app ingress
data "azurerm_public_ip" "appgw" {
  name                = "ismd-appgw-pip-${var.environment}"
  resource_group_name = var.shared_resource_group_name
  depends_on          = [module.app_gateway]  # Depend on the app_gateway module
}

# Step 4: Create the container apps with ingress restriction to App Gateway public IP
module "validator_apps" {
  source = "../../modules/validator_apps"

  environment               = var.environment
  location                  = var.location
  resource_group_name       = var.validator_resource_group_name
  shared_resource_group_name = var.shared_resource_group_name
  container_app_environment_id = module.validator_environment.container_app_environment_id
  app_gateway_public_ip     = data.azurerm_public_ip.appgw.ip_address
  frontend_image            = var.frontend_image
  frontend_image_tag        = var.frontend_image_tag
  backend_image             = var.backend_image
  backend_image_tag         = var.backend_image_tag
  container_app_environment_default_domain = module.validator_environment.default_domain
  
  depends_on = [
    module.validator_environment,
    data.azurerm_public_ip.appgw
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
  value = data.azurerm_public_ip.appgw.ip_address
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

output "app_gateway_name" {
  value = module.app_gateway.app_gateway_name
}

output "app_gateway_id" {
  value = module.app_gateway.app_gateway_id
}

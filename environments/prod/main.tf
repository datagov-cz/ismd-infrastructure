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
  description = "Container image for the frontend"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend:latest"
}

variable "backend_image" {
  description = "Container image for the backend"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend:latest"
}

# Modules
module "shared" {
  source = "../../modules/shared"
  
  environment        = var.environment
  resource_group_name = var.shared_resource_group_name
  location           = var.location
}

module "validator" {
  source = "../../modules/validator"
  
  environment        = var.environment
  resource_group_name = var.validator_resource_group_name
  location           = var.location
  subnet_id          = module.shared.validator_subnet_id
  
  # Container images
  frontend_image     = var.frontend_image
  backend_image      = var.backend_image
  
  # Depends on shared module to ensure networking is set up first
  depends_on = [module.shared]
}

# Outputs
output "shared_resource_group_name" {
  value = module.shared.resource_group_name
}

output "validator_resource_group_name" {
  value = module.validator.resource_group_name
}

output "validator_frontend_url" {
  value = module.validator.frontend_url
}

output "validator_backend_name" {
  value = module.validator.backend_name
}

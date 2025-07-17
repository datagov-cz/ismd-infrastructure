terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0"
    }
  }
}

provider "azurerm" {
  features {
    # Allow the provider to delete resources that exist in the state but not in the configuration
    # This is useful for cleaning up resources that are no longer needed
    # but be careful with this in production environments
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Shared global resources (Application Gateway, VNet, etc.)
# This module is not conditional on the workspace as it manages resources shared across all environments.
module "shared_global" {
  source                    = "./modules/shared_global"
  location                 = var.location
  environment              = var.environment
  container_app_environment_name = "whiteforest-fdd5cbd0"  # This should match your Container Apps Environment name
  # For now, we'll use the dev environment's container app environment ID
  # This will need to be updated when we add more environments
  container_app_environment_id = length(module.dev) > 0 ? module.dev[0].container_app_environment_id : ""
}


# Include environment-specific configurations
module "dev" {
  count  = terraform.workspace == "dev" ? 1 : 0
  source = "./environments/dev"

  # Pass through required variables
  environment        = "dev"
  location           = var.location
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # Pass in details of the shared global network for VNet peering
  shared_global_vnet_id               = module.shared_global.vnet_id
  shared_global_vnet_name             = module.shared_global.vnet_name
  shared_global_resource_group_name = module.shared_global.resource_group_name
  app_gateway_public_ip_address     = module.shared_global.public_ip_address
}

# Test environment
module "test" {
  count  = terraform.workspace == "test" ? 1 : 0
  source = "./environments/test"

  # Pass through required variables
  environment        = "test"
  location           = var.location
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # Pass in details of the shared global network for VNet peering
  shared_global_vnet_id               = module.shared_global.vnet_id
  shared_global_vnet_name             = module.shared_global.vnet_name
  shared_global_resource_group_name = module.shared_global.resource_group_name
  app_gateway_public_ip_address     = module.shared_global.public_ip_address
}

# Production environment
module "prod" {
  count  = terraform.workspace == "prod" ? 1 : 0
  source = "./environments/prod"

  # Pass through required variables
  environment        = "prod"
  location           = var.location
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # Pass in details of the shared global network for VNet peering
  shared_global_vnet_id               = module.shared_global.vnet_id
  shared_global_vnet_name             = module.shared_global.vnet_name
  shared_global_resource_group_name = module.shared_global.resource_group_name
  app_gateway_public_ip_address     = module.shared_global.public_ip_address
}

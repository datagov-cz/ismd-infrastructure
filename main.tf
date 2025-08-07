terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.37.0"
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

# Get current subscription ID if not provided
data "azurerm_client_config" "current" {}

# Create shared global resources (App Gateway, etc.)
module "shared_global" {
  source                      = "./modules/shared_global"
  location                    = var.location
  environment                 = terraform.workspace
  container_app_environment_name = "ismd-validator-environment-${terraform.workspace}"
  
  # The App Gateway doesn't need this to function, but we keep it for future use
  container_app_environment_id = ""
  
  # App names for constructing FQDNs
  frontend_app_name = var.frontend_app_name
  backend_app_name  = var.backend_app_name
  
  # Use FQDNs based on the container app environment domain variable
  # This breaks the circular dependency
  frontend_fqdn = "${var.frontend_app_name}-${terraform.workspace}.${var.container_app_environment_domain}"
  backend_fqdn  = "${var.backend_app_name}-${terraform.workspace}.${var.container_app_environment_domain}"
}

# We'll use the environment module from the dev environment instead
# This avoids circular dependencies between modules

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
  
  # Pass through app names
  frontend_app_name = var.frontend_app_name
  backend_app_name  = var.backend_app_name
  
  # Pass through resource group names
  shared_resource_group_name = var.shared_resource_group_name
  validator_resource_group_name = var.validator_resource_group_name
  
  # Pass through container app environment info - these will be dynamically set by the dev module
  # We're not setting these values here because they come from the validator_environment module
  # The dev module will handle passing these values to the validator_apps module
  container_app_environment_id   = ""
  container_app_environment_name = ""
  container_app_environment_default_domain = ""
  
  # Use constructed resource IDs to break circular dependency
  shared_global_vnet_id          = "/subscriptions/${coalesce(var.subscription_id, data.azurerm_client_config.current.subscription_id)}/resourceGroups/ismd-shared-global/providers/Microsoft.Network/virtualNetworks/ismd-vnet-shared-global"
  shared_global_vnet_name        = "ismd-vnet-shared-global"
  shared_global_resource_group_name = "ismd-shared-global"
  # Use the actual App Gateway public IP from the shared_global module
  app_gateway_public_ip_address  = module.shared_global.app_gateway_public_ip_address
  
  # Remove explicit dependency
  # depends_on = [module.shared_global]
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
  
  # Required network variables - using empty strings as placeholders
  shared_global_vnet_id          = ""
  shared_global_vnet_name        = ""
  shared_global_resource_group_name = ""
  app_gateway_public_ip_address  = ""
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
  
  # Required network variables - using empty strings as placeholders
  shared_global_vnet_id          = ""
  shared_global_vnet_name        = ""
  shared_global_resource_group_name = ""
  app_gateway_public_ip_address  = ""
}

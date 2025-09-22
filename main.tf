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

 # Read outputs from the shared-global Terraform state (App Gateway, global VNet, etc.)
 data "terraform_remote_state" "shared_global" {
   backend = "azurerm"
   config = {
     resource_group_name  = "ismd-shared-tfstate"
     storage_account_name = "ismdtfstate"
     container_name       = "tfstate"
     key                  = "ismd-shared-global.tfstate"
   }
 }

# We'll use the environment module from the dev environment instead
# This avoids circular dependencies between modules

### Revert to static modules; Terraform does not allow dynamic expressions for module source

# Dev environment
module "dev" {
  count  = terraform.workspace == "dev" ? 1 : 0
  source = "./environments/dev"

  # Common variables
  environment        = "dev"
  location           = var.location
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # App names
  frontend_app_name = var.frontend_app_name
  backend_app_name  = var.backend_app_name

  # Resource groups
  shared_resource_group_name    = var.shared_resource_group_name
  validator_resource_group_name = var.validator_resource_group_name

  # Container Apps Environment (left empty; env module fills when creating)
  container_app_environment_id             = ""
  container_app_environment_default_domain = ""

  # Remote state (guarded for initial plan)
  shared_global_vnet_id             = try(data.terraform_remote_state.shared_global.outputs.vnet_id, "")
  shared_global_vnet_name           = try(data.terraform_remote_state.shared_global.outputs.vnet_name, "")
  shared_global_resource_group_name = try(data.terraform_remote_state.shared_global.outputs.resource_group_name, "")
  app_gateway_public_ip_address     = try(data.terraform_remote_state.shared_global.outputs.app_gateway_public_ip_address, "")
}

# Test environment
module "test" {
  count  = terraform.workspace == "test" ? 1 : 0
  source = "./environments/test"

  # Common variables
  environment        = "test"
  location           = var.location
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # Remote state (guarded for initial plan)
  shared_global_vnet_id             = try(data.terraform_remote_state.shared_global.outputs.vnet_id, "")
  shared_global_vnet_name           = try(data.terraform_remote_state.shared_global.outputs.vnet_name, "")
  shared_global_resource_group_name = try(data.terraform_remote_state.shared_global.outputs.resource_group_name, "")
  app_gateway_public_ip_address     = try(data.terraform_remote_state.shared_global.outputs.app_gateway_public_ip_address, "")
}

# Production environment
module "prod" {
  count  = terraform.workspace == "prod" ? 1 : 0
  source = "./environments/prod"

  # Common variables
  environment        = "prod"
  location           = var.location
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # Remote state (guarded for initial plan)
  shared_global_vnet_id             = try(data.terraform_remote_state.shared_global.outputs.vnet_id, "")
  shared_global_vnet_name           = try(data.terraform_remote_state.shared_global.outputs.vnet_name, "")
  shared_global_resource_group_name = try(data.terraform_remote_state.shared_global.outputs.resource_group_name, "")
  app_gateway_public_ip_address     = try(data.terraform_remote_state.shared_global.outputs.app_gateway_public_ip_address, "")
}

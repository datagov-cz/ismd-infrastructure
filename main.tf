terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  # This will be replaced with your actual backend configuration
  # backend "azurerm" {
  #   resource_group_name  = "ismd-shared-dev"
  #   storage_account_name = "ismdtfstatedev"
  #   container_name       = "tfstate"
  #   key                  = "terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

# Include environment-specific configurations
module "dev" {
  source = "./environments/dev"
  # Add any variables that need to be passed to the environment module
}

# Uncomment when ready to deploy test environment
# module "test" {
#   source = "./environments/test"
# }

# Uncomment when ready to deploy prod environment
# module "prod" {
#   source = "./environments/prod"
# }

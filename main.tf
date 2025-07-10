terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  # Skip resource provider registration due to limited permissions
  skip_provider_registration = true
}

# Include environment-specific configurations
module "dev" {
  count  = terraform.workspace == "dev" ? 1 : 0
  source = "./environments/dev"
  
  # Pass through required variables
  environment = "dev"
  frontend_image = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image = var.backend_image
  backend_image_tag = var.backend_image_tag
  
  # Pass through other required variables
  shared_resource_group_name = var.shared_resource_group_name
  location = var.location
}

# Test environment
module "test" {
  count  = terraform.workspace == "test" ? 1 : 0
  source = "./environments/test"
  
  # Pass through required variables
  environment = "test"
  frontend_image = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image = var.backend_image
  backend_image_tag = var.backend_image_tag
  
  # Pass through other required variables
  shared_resource_group_name = var.shared_resource_group_name
  location = var.location
}

# Production environment
module "prod" {
  count  = terraform.workspace == "prod" ? 1 : 0
  source = "./environments/prod"
  
  # Pass through required variables
  environment = "prod"
  frontend_image = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image = var.backend_image
  backend_image_tag = var.backend_image_tag
  
  # Pass through other required variables
  shared_resource_group_name = var.shared_resource_group_name
  location = var.location
}

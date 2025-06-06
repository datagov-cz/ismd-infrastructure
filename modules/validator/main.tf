variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the validator resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "germanywestcentral"
}

variable "subnet_id" {
  description = "ID of the subnet for the application"
  type        = string
}

variable "frontend_image" {
  description = "Container image for the frontend"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend-dev:latest"
}

variable "backend_image" {
  description = "Container image for the backend"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend-dev:latest"
}



# Create the validator resource group
resource "azurerm_resource_group" "validator" {
  name     = var.resource_group_name
  location = var.location
  
  tags = {
    Environment = var.environment
    Application = "Validator"
    ManagedBy   = "Terraform"
  }
}

# Log Analytics Workspace for container app environment
resource "azurerm_log_analytics_workspace" "validator" {
  name                = "ismd-validator-log-workspace-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.validator.name
  
  tags = {
    Environment = var.environment
    Application = "Validator"
    ManagedBy   = "Terraform"
  }
}

# Container App Environment
resource "azurerm_container_app_environment" "validator" {
  name                               = "ismd-validator-environment-${var.environment}"
  location                           = var.location
  resource_group_name                = azurerm_resource_group.validator.name
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.validator.id
  infrastructure_subnet_id           = var.subnet_id
  infrastructure_resource_group_name = "ME_ismd-validator-environment-${var.environment}_${azurerm_resource_group.validator.name}_${var.location}"
  zone_redundancy_enabled            = false
  
  # Standard Container App Environment configuration
  
  workload_profile {
    name                  = "ismd-wl-${var.environment}"
    workload_profile_type = "D4"
    maximum_count         = 3
  }
  
  tags = {
    Environment = var.environment
    Application = "Validator"
    ManagedBy   = "Terraform"
  }
}

# Backend Container App
resource "azurerm_container_app" "backend" {
  name                         = "ismd-validator-backend-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.validator.id
  resource_group_name          = azurerm_resource_group.validator.name
  revision_mode                = "Single"
  workload_profile_name        = "ismd-wl-${var.environment}"
  
  # Add ingress for API communication (externally accessible)
  ingress {
    external_enabled = true   # Make the API accessible from the internet
    target_port      = 8080   # Assuming the API runs on port 8080
    transport        = "http" # Explicitly set transport protocol
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
    
    # Ensure the port is exposed internally
    allow_insecure_connections = true
  }
  
  template {
    container {
      name   = "ismd-validator-backend-${var.environment}"
      image  = var.backend_image
      cpu    = 0.5
      memory = "1Gi"
      
      # Environment variables for the backend API
      env {
        name  = "CORS_ALLOWED_ORIGINS"
        value = "https://ismd-validator-frontend-${var.environment}.${azurerm_container_app_environment.validator.default_domain}"
      }
      env {
        name  = "PORT"
        value = "8080"
      }
    }
  }
  
  tags = {
    Environment = var.environment
    Application = "Validator"
    ManagedBy   = "Terraform"
  }
}

# Frontend container app
resource "azurerm_container_app" "frontend" {
  name                         = "ismd-validator-frontend-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.validator.id
  resource_group_name          = azurerm_resource_group.validator.name
  revision_mode                = "Single"
  workload_profile_name        = "ismd-wl-${var.environment}"

  template {
    container {
      name   = "ismd-validator-frontend-${var.environment}"
      image  = var.frontend_image
      cpu    = 0.25
      memory = "1Gi"
      
      # Environment variables for API communication
      # Using the public URL of the backend container app
      env {
        name  = "NEXT_PUBLIC_BE_URL"
        value = "https://ismd-validator-backend-${var.environment}.${azurerm_container_app_environment.validator.default_domain}"
      }
    }
  }
  
  ingress {
    external_enabled = true
    target_port      = 3000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  
  tags = {
    Environment = var.environment
    Application = "Validator"
    ManagedBy   = "Terraform"
  }
}

# Outputs
output "resource_group_id" {
  value = azurerm_resource_group.validator.id
}

output "resource_group_name" {
  value = azurerm_resource_group.validator.name
}

output "frontend_url" {
  value = azurerm_container_app.frontend.ingress[0].fqdn
}

output "backend_name" {
  value = azurerm_container_app.backend.name
}

output "container_app_environment_name" {
  value = azurerm_container_app_environment.validator.name
}

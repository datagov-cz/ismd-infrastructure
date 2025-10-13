# Validator Apps Module
# This module creates the container apps with ingress restriction to App Gateway public IP

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the validator resource group"
  type        = string
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
}

variable "container_app_environment_id" {
  description = "ID of the container app environment"
  type        = string
}

variable "app_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  type        = string
}

variable "app_gateway_hostname" {
  description = "Hostname for the environment (e.g., ismd.oha03.dia.gov.cz for dev)"
  type        = string
  default     = ""
}

variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image"
  type        = string
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
}

variable "backend_image_tag" {
  description = "Tag for the backend container image"
  type        = string
}

variable "container_app_environment_default_domain" {
  description = "Default domain of the container app environment"
  type        = string
}

# Backend container app
resource "azurerm_container_app" "backend" {
  name                         = "${var.backend_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  
  # Set workload profile name based on environment
  # For Consumption profile, set to null
  # For Dedicated profile, use the provided workload profile name
  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name
  
  identity {
    type = "SystemAssigned"
  }
  
  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
    allow_insecure_connections = true
    
    # Restrict ingress to Application Gateway public IP (only when known)
    dynamic "ip_security_restriction" {
      for_each = var.app_gateway_public_ip != "" ? [var.app_gateway_public_ip] : []
      content {
        name             = "AllowAppGateway"
        ip_address_range = "${ip_security_restriction.value}/32"
        action           = "Allow"
      }
    }
  }
  
  template {
    min_replicas = 1
    container {
      name   = "ismd-validator-backend-${var.environment}"
      image  = "${var.backend_image}:${var.backend_image_tag}"
      cpu    = 0.5
      memory = "1Gi"
      
      env {
        name  = "CORS_ALLOWED_ORIGINS"
        # Support both HTTP and HTTPS for dual-protocol access (comma-separated)
        value = var.app_gateway_hostname != "" ? "http://${var.app_gateway_hostname},https://${var.app_gateway_hostname}" : (var.app_gateway_public_ip != "" ? "http://${var.app_gateway_public_ip},https://${var.app_gateway_public_ip}" : "")
      }
      env {
        name  = "PORT"
        value = "8080"
      }
      # TODO: Change profile for production/test environments as needed
      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = "localhost"
      }
      liveness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/actuator/health"
        # Cost optimization: Longer intervals for dev environment
        interval_seconds = var.environment == "dev" ? 30 : 10
      }
      readiness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/actuator/health"
        interval_seconds = 10
      }
      startup_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/actuator/health"
        interval_seconds = 10
      }
    }
  }
  
  tags = {
    Environment = var.environment
    Application = "Validator"
    ManagedBy   = "Terraform"
    Location    = var.location
    SharedRG    = var.shared_resource_group_name
  }
}

# Frontend container app
resource "azurerm_container_app" "frontend" {
  name                         = "${var.frontend_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  
  # Set workload profile name based on environment
  # For Consumption profile, set to null
  # For Dedicated profile, use the provided workload profile name
  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  template {
    min_replicas = 1
    container {
      name   = "ismd-validator-frontend-${var.environment}"
      image  = "${var.frontend_image}:${var.frontend_image_tag}"
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "NEXT_PUBLIC_BE_URL"
        # Just the hostname (no protocol) - frontend will add protocol dynamically
        value = var.app_gateway_hostname != "" ? var.app_gateway_hostname : var.app_gateway_public_ip
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
    
    allow_insecure_connections = true
    
    # Restrict ingress to Application Gateway public IP (only when known)
    dynamic "ip_security_restriction" {
      for_each = var.app_gateway_public_ip != "" ? [var.app_gateway_public_ip] : []
      content {
        name             = "AllowAppGateway"
        ip_address_range = "${ip_security_restriction.value}/32"
        action           = "Allow"
      }
    }
  }
  
  tags = {
    Environment = var.environment
    Application = "Validator"
    ManagedBy   = "Terraform"
    Location    = var.location
    SharedRG    = var.shared_resource_group_name
  }
}

# Outputs
output "frontend_name" {
  description = "The name of the frontend container app"
  value       = azurerm_container_app.frontend.name
}

output "backend_name" {
  description = "The name of the backend container app"
  value       = azurerm_container_app.backend.name
}

output "frontend_fqdn" {
  description = "The FQDN of the frontend container app"
  value       = azurerm_container_app.frontend.ingress[0].fqdn
}

output "backend_fqdn" {
  description = "The FQDN of the backend container app"
  value       = azurerm_container_app.backend.ingress[0].fqdn
}

output "frontend_url" {
  description = "The URL of the frontend container app"
  value       = "https://${azurerm_container_app.frontend.ingress[0].fqdn}"
}

output "backend_url" {
  description = "The URL of the backend container app"
  value       = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
}

# Optional: expose revision-specific FQDNs for troubleshooting
output "frontend_revision_fqdn" {
  description = "The FQDN of the latest frontend revision"
  value       = azurerm_container_app.frontend.latest_revision_fqdn
}

output "backend_revision_fqdn" {
  description = "The FQDN of the latest backend revision"
  value       = azurerm_container_app.backend.latest_revision_fqdn
}

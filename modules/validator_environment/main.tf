# Validator Environment Module
# This module creates the container app environment and its dependencies

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

variable "subnet_id" {
  description = "ID of the subnet for the container app environment"
  type        = string
}

# Create the validator resource group
resource "azurerm_resource_group" "validator" {
  name     = var.resource_group_name
  location = var.location
  
  lifecycle {
    # Protect from accidental deletion - destroying the resource group would:
    # - Delete ALL resources inside it (container apps, environment, logs)
    # - Cause complete service outage
    # - Require full infrastructure rebuild
    prevent_destroy = true
  }
  
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
  
  lifecycle {
    # Protect from accidental deletion - destroying the workspace would:
    # - Lose ALL historical logs and metrics
    # - Break monitoring and alerting
    # - Lose audit trail and troubleshooting data
    prevent_destroy = true
  }
  
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
  # infrastructure_subnet_id only needed for dedicated workload profiles (non-dev)
  # Dev uses Consumption profile which doesn't need infrastructure subnet
  infrastructure_subnet_id           = var.environment == "dev" ? null : var.subnet_id
  # infrastructure_resource_group_name only valid with dedicated workload profiles
  # Dev uses Consumption profile, so this parameter is not needed
  infrastructure_resource_group_name = var.environment == "dev" ? null : "ME_ismd-validator-environment-${var.environment}_${azurerm_resource_group.validator.name}_${var.location}"
  # zone_redundancy_enabled only valid when infrastructure_subnet_id is set (dedicated profiles)
  # Dev uses Consumption profile, so this parameter is not needed
  zone_redundancy_enabled            = var.environment == "dev" ? null : false
  
  lifecycle {
    # Protect from accidental deletion - destroying the environment would:
    # - Stop ALL container apps running in this environment
    # - Lose workload profile configurations
    # - Require complex recreation with networking setup
    prevent_destroy = true
  }
  
  # Container App Environment workload profile configuration
  # Dev uses Consumption profile for maximum cost savings (scale to zero)
  # Production uses dedicated D4 profile for consistent performance
  dynamic "workload_profile" {
    for_each = var.environment == "dev" ? [] : [1]
    content {
      name                  = "ismd-wl-${var.environment}"
      workload_profile_type = "D4"
      maximum_count         = 3
    }
  }
  
  tags = {
    Environment = var.environment
    Application = "Validator"
    ManagedBy   = "Terraform"
  }
}

# Outputs
output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.validator.name
}

output "container_app_environment_id" {
  description = "The ID of the Container App Environment"
  value       = azurerm_container_app_environment.validator.id
}

output "container_app_environment_name" {
  description = "The name of the Container App Environment"
  value       = azurerm_container_app_environment.validator.name
}

output "default_domain" {
  description = "The default domain of the Container App Environment"
  value       = azurerm_container_app_environment.validator.default_domain
}

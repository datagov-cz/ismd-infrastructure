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
  # Enable VNet integration for all environments
  infrastructure_subnet_id           = var.subnet_id
  infrastructure_resource_group_name = "ME_ismd-validator-environment-${var.environment}_${azurerm_resource_group.validator.name}_${var.location}"
  internal_load_balancer_enabled     = false  # Disabled since we're using Application Gateway
  
  # Enable zone redundancy in production only
  zone_redundancy_enabled = var.environment == "prod"
  
  lifecycle {
    # Protect from accidental deletion - destroying the environment would:
    # - Stop ALL container apps running in this environment
    # - Lose workload profile configurations
    # - Require complex recreation with networking setup
    # prevent_destroy = true
  }
  
  # Standard workload profile for all environments
  workload_profile {
    name                  = "default"
    workload_profile_type = "D4"
    minimum_count         = 1
    maximum_count         = 3
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

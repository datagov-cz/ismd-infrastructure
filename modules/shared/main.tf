# Note: All variables are now defined in variables.tf
# This includes:
# - environment
# - resource_group_name
# - location

# Create or reference the shared resource group
resource "azurerm_resource_group" "shared" {
  name     = var.resource_group_name
  location = var.location

  lifecycle {
    # Prevent accidental deletion of the shared resource group
    # Deleting this would:
    # - Delete shared networking resources (VNet, subnets)
    # - Break connectivity for ALL environments
    # - Require complete network infrastructure rebuild
    prevent_destroy = true
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Create a virtual network for the environment
resource "azurerm_virtual_network" "main" {
  name                = "ismd-vnet-${var.environment}"
  address_space       = [var.vnet_address_space, var.vnet_address_space_ipv6]
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Create validator subnet with delegation for Container Apps
# Note: Container Apps require at least /23 subnet size (512 IPs)
resource "azurerm_subnet" "validator" {
  name                 = "ismd-validator-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.validator_subnet_address_prefix]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      name    = "Microsoft.App/environments"
    }
  }
}

# Create tool subnet for shared Container App Environment
# Note: Container Apps require at least /23 subnet size (512 IPs)
resource "azurerm_subnet" "shared_apps" {
  name                 = "ismd-shared-apps-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.tool_subnet_address_prefix]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      name    = "Microsoft.App/environments"
    }
  }
}

# Log Analytics Workspace for shared Container App Environment
resource "azurerm_log_analytics_workspace" "shared" {
  name                = "ismd-shared-log-workspace-${var.environment}"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Shared Container App Environment for all apps in this environment
resource "azurerm_container_app_environment" "shared" {
  name                               = "ismd-shared-environment-${var.environment}"
  location                           = azurerm_resource_group.shared.location
  resource_group_name                = azurerm_resource_group.shared.name
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.shared.id
  infrastructure_subnet_id           = azurerm_subnet.shared_apps.id
  infrastructure_resource_group_name = "ME_ismd-shared-environment-${var.environment}_${azurerm_resource_group.shared.name}_${var.location}"
  internal_load_balancer_enabled     = false

  zone_redundancy_enabled = var.environment == "prod"

  lifecycle {
    prevent_destroy = true
  }

  workload_profile {
    name                  = "default"
    workload_profile_type = var.workload_profile_type
    minimum_count         = var.workload_profile_min_count
    maximum_count         = var.workload_profile_max_count
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Outputs are defined in outputs.tf

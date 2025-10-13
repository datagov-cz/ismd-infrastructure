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
    # Temporarily disabled for test environment rebuild
    # prevent_destroy = true
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

# Outputs are defined in outputs.tf

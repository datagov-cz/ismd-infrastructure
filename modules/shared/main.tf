# Note: All variables are now defined in variables.tf
# This includes:
# - environment
# - resource_group_name
# - location
# - backend_address_pools
# - backend_http_settings
# - probes
# - http_listeners
# - request_routing_rules
# - url_path_maps


# Create or reference the shared resource group
resource "azurerm_resource_group" "shared" {
  name     = var.resource_group_name
  location = var.location
  
  lifecycle {
    # Protect from accidental deletion - destroying the shared resource group would:
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

# Application Gateway resources are defined in application_gateway.tf

# Create a virtual network for the environment
resource "azurerm_virtual_network" "main" {
  name                = "ismd-vnet-${var.environment}"
  address_space       = ["10.0.0.0/16", "fd00:db8:deca::/48"]
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
  address_prefixes     = ["10.0.2.0/23"]
  
  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      name    = "Microsoft.App/environments"
    }
  }
}

# Application Gateway configuration is in application_gateway.tf

# Outputs are defined in outputs.tf

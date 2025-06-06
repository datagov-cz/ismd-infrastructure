variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "germanywestcentral"
}

# Create or reference the shared resource group
resource "azurerm_resource_group" "shared" {
  name     = var.resource_group_name
  location = var.location
  
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Create a virtual network for the environment
resource "azurerm_virtual_network" "main" {
  name                = "ismd-vnet-${var.environment}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Create validator subnet with delegation for Container Apps
resource "azurerm_subnet" "validator" {
  name                 = "ismd-validator-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/26"]
  
  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      name    = "Microsoft.App/environments"
    }
  }
}

# Outputs to be used by other modules
output "resource_group_id" {
  value = azurerm_resource_group.shared.id
}

output "resource_group_name" {
  value = azurerm_resource_group.shared.name
}

output "virtual_network_id" {
  value = azurerm_virtual_network.main.id
}

output "virtual_network_name" {
  value = azurerm_virtual_network.main.name
}

output "validator_subnet_id" {
  value = azurerm_subnet.validator.id
}

output "validator_subnet_name" {
  value = azurerm_subnet.validator.name
}

# Outputs for Terraform state storage are removed as these resources
# will be created manually by an admin

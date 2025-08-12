# Resource Group Output
output "resource_group_name" {
  description = "The name of the shared resource group"
  value       = azurerm_resource_group.shared.name
}

# Virtual Network Outputs
output "virtual_network_id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "validator_subnet_id" {
  description = "The ID of the validator subnet"
  value       = azurerm_subnet.validator.id
}

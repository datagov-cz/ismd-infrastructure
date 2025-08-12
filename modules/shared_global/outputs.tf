output "resource_group_name" {
  description = "The name of the shared global resource group."
  value       = azurerm_resource_group.shared_global.name
}

output "vnet_id" {
  description = "The ID of the shared global virtual network."
  value       = azurerm_virtual_network.shared_global.id
}

output "vnet_name" {
  description = "The name of the shared global virtual network."
  value       = azurerm_virtual_network.shared_global.name
}

output "public_ip_address" {
  description = "The public IP address of the Application Gateway."
  value       = azurerm_public_ip.appgw.ip_address
}

output "app_gateway_public_ip_address" {
  description = "The public IP address of the Application Gateway."
  value       = azurerm_public_ip.appgw.ip_address
}


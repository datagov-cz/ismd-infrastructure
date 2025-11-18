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

output "shared_apps_subnet_id" {
  description = "The ID of the shared apps subnet"
  value       = azurerm_subnet.shared_apps.id
}

output "shared_container_app_environment_id" {
  description = "The ID of the shared Container App Environment"
  value       = azurerm_container_app_environment.shared.id
}

output "shared_container_app_environment_name" {
  description = "The name of the shared Container App Environment"
  value       = azurerm_container_app_environment.shared.name
}

output "shared_container_app_environment_default_domain" {
  description = "The default domain of the shared Container App Environment"
  value       = azurerm_container_app_environment.shared.default_domain
}

output "shared_log_analytics_workspace_id" {
  description = "The ID of the shared Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.shared.id
}

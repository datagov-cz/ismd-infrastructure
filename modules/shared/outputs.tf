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

# Application Insights outputs
output "app_insights_id" {
  description = "The ID of the shared Application Insights resource"
  value       = azurerm_application_insights.shared.id
}

output "app_insights_name" {
  description = "The name of the shared Application Insights resource"
  value       = azurerm_application_insights.shared.name
}

output "app_insights_connection_string" {
  description = "The connection string for the shared Application Insights resource. Inject into apps as APPLICATIONINSIGHTS_CONNECTION_STRING."
  value       = azurerm_application_insights.shared.connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "Legacy instrumentation key. Prefer connection_string for new code."
  value       = azurerm_application_insights.shared.instrumentation_key
  sensitive   = true
}

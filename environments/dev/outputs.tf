# Dev Environment — outputs

output "shared_resource_group_name" {
  value = module.shared.resource_group_name
}

output "validator_resource_group_name" {
  value = azurerm_resource_group.validator.name
}

output "app_gateway_public_ip" {
  value = var.app_gateway_public_ip_address
}

output "validator_frontend_fqdn" {
  value = module.validator_apps.frontend_fqdn
}

output "validator_backend_fqdn" {
  value = module.validator_apps.backend_fqdn
}

output "tool_frontend_fqdn" {
  value = var.deploy_tool_apps ? module.tool_apps[0].frontend_fqdn : null
}

output "tool_backend_fqdn" {
  value = var.deploy_tool_apps ? module.tool_apps[0].backend_fqdn : null
}

output "shared_container_app_environment_id" {
  description = "ID of the shared Container App Environment"
  value       = module.shared.shared_container_app_environment_id
}

output "shared_container_app_environment_name" {
  description = "Name of the shared Container App Environment"
  value       = module.shared.shared_container_app_environment_name
}

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

output "tool_caais_redirect_uri" {
  description = "redirect_uri to register with CAAIS for this environment."
  value       = var.deploy_tool_apps ? module.tool_apps[0].keycloak_caais_redirect_uri : null
}

output "env_keyvault_name" {
  description = "Per-env Key Vault name. Seed secret values with: az keyvault secret set --vault-name <this> --name <secret> ..."
  value       = azurerm_key_vault.env.name
}

output "env_keyvault_uri" {
  description = "Per-env Key Vault URI. Base for versionless secret ids used in key_vault_secret_id references."
  value       = azurerm_key_vault.env.vault_uri
}

output "shared_container_app_environment_id" {
  description = "ID of the shared Container App Environment"
  value       = module.shared.shared_container_app_environment_id
}

output "shared_container_app_environment_name" {
  description = "Name of the shared Container App Environment"
  value       = module.shared.shared_container_app_environment_name
}

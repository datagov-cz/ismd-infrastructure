output "server_id" {
  description = "Resource id of the Flexible Server. Injected into app modules so each creates its own database against it."
  value       = azurerm_postgresql_flexible_server.tool.id
}

output "fqdn" {
  description = "FQDN of the Flexible Server. Stable across a resource-group move (the server name does not change)."
  value       = azurerm_postgresql_flexible_server.tool.fqdn
}

output "name" {
  description = "Name of the Flexible Server"
  value       = azurerm_postgresql_flexible_server.tool.name
}

output "backup_kv_identity_principal_id" {
  description = "Principal (object) id of the backup job's KV identity, or null when logical backups are off. Granted 'get' in environments/<env>/keyvault.tf."
  value       = var.enable_logical_backups ? azurerm_user_assigned_identity.backup_kv[0].principal_id : null
}

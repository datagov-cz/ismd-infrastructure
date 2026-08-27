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

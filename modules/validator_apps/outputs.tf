# Outputs for Validator Apps Module

output "frontend_name" {
  description = "The name of the frontend container app"
  value       = azurerm_container_app.frontend.name
}

output "backend_name" {
  description = "The name of the backend container app"
  value       = azurerm_container_app.backend.name
}

output "frontend_fqdn" {
  description = "The FQDN of the frontend container app"
  value       = azurerm_container_app.frontend.ingress[0].fqdn
}

output "backend_fqdn" {
  description = "The FQDN of the backend container app"
  value       = azurerm_container_app.backend.ingress[0].fqdn
}

output "frontend_url" {
  description = "The URL of the frontend container app"
  value       = "https://${azurerm_container_app.frontend.ingress[0].fqdn}"
}

output "backend_url" {
  description = "The URL of the backend container app"
  value       = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
}

# Optional: expose revision-specific FQDNs for troubleshooting
output "frontend_revision_fqdn" {
  description = "The FQDN of the latest frontend revision"
  value       = azurerm_container_app.frontend.latest_revision_fqdn
}

output "backend_revision_fqdn" {
  description = "The FQDN of the latest backend revision"
  value       = azurerm_container_app.backend.latest_revision_fqdn
}

# Outputs for Validator Apps Module

output "backend_kv_identity_principal_id" {
  description = "Principal (object) id of the validator backend's dedicated KV identity. Grant it 'get' on the per-env vault's secrets (environments/<env>/keyvault.tf)."
  value       = azurerm_user_assigned_identity.backend_kv.principal_id
}

output "frontend_kv_identity_principal_id" {
  description = "Principal (object) id of the validator frontend's dedicated KV identity. Grant it 'get' on the per-env vault's secrets (environments/<env>/keyvault.tf)."
  value       = azurerm_user_assigned_identity.frontend_kv.principal_id
}

output "frontend_name" {
  description = "The name of the frontend container app"
  value       = azurerm_container_app.frontend.name
}

output "frontend_id" {
  description = "The resource ID of the frontend container app. Used by the monitoring module to scope alert rules."
  value       = azurerm_container_app.frontend.id
}

output "backend_name" {
  description = "The name of the backend container app"
  value       = azurerm_container_app.backend.name
}

output "backend_id" {
  description = "The resource ID of the backend container app. Used by the monitoring module to scope alert rules."
  value       = azurerm_container_app.backend.id
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

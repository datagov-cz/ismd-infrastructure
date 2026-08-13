# AI Apps Module — outputs

output "backend_kv_identity_principal_id" {
  description = "Principal (object) id of the AI backend's dedicated KV identity. Grant it 'get' on the per-env vault's secrets (done in environments/<env>/keyvault.tf)."
  value       = azurerm_user_assigned_identity.ai_kv.principal_id
}

output "backend_id" {
  description = "Resource ID of the AI backend container app"
  value       = azurerm_container_app.backend.id
}

output "backend_name" {
  description = "Name of the AI backend container app"
  value       = azurerm_container_app.backend.name
}

output "backend_internal_fqdn" {
  description = "Internal ingress FQDN of the AI backend (reachable app-to-app within the Container App Environment)"
  value       = azurerm_container_app.backend.ingress[0].fqdn
}

# Convenience: the base URL the tool backend uses to reach the AI service over the
# CAE internal network. Ingress listens on port 80 (not the 8080 target port),
# same as the other internal apps.
output "backend_internal_url" {
  description = "Internal base URL for the AI backend"
  value       = "http://${azurerm_container_app.backend.name}"
}

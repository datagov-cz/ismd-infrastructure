# Outputs for Tool Apps Module

output "backend_kv_identity_principal_id" {
  description = "Principal (object) id of the backend's dedicated KV identity. Grant it 'get' on the per-env vault's secrets (done in environments/<env>/keyvault.tf)."
  value       = azurerm_user_assigned_identity.backend_kv.principal_id
}

output "frontend_kv_identity_principal_id" {
  description = "Principal (object) id of the frontend's dedicated KV identity. Grant it 'get' on the per-env vault's secrets (done in environments/<env>/keyvault.tf)."
  value       = azurerm_user_assigned_identity.frontend_kv.principal_id
}

output "keycloak_kv_identity_principal_id" {
  description = "Principal (object) id of the keycloak container's dedicated KV identity (for its own secrets, not CAAIS). Null when keycloak is not deployed. Grant it 'get' on the per-env vault's secrets."
  value       = var.deploy_keycloak ? azurerm_user_assigned_identity.keycloak_kv[0].principal_id : null
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

# Database outputs — the server now lives in modules/postgres, so consumers
# (monitoring alert scopes, ai_apps) take its id/name/fqdn from that module's
# outputs directly rather than through here.

output "fuseki_name" {
  description = "The name of the Fuseki container app"
  value       = var.deploy_fuseki ? azurerm_container_app.fuseki[0].name : null
}

output "fuseki_id" {
  description = "The resource ID of the Fuseki container app. Used by the monitoring module to scope alert rules."
  value       = var.deploy_fuseki ? azurerm_container_app.fuseki[0].id : null
}

output "keycloak_name" {
  description = "The name of the Keycloak container app"
  value       = var.deploy_keycloak ? azurerm_container_app.keycloak[0].name : null
}

output "keycloak_id" {
  description = "The resource ID of the Keycloak container app. Used by the monitoring module to scope alert rules."
  value       = var.deploy_keycloak ? azurerm_container_app.keycloak[0].id : null
}

output "keycloak_fqdn" {
  description = "The FQDN of the Keycloak container app"
  value       = var.deploy_keycloak ? azurerm_container_app.keycloak[0].ingress[0].fqdn : null
}

output "keycloak_issuer_uri" {
  description = "The Keycloak issuer URI used by frontend/backend"
  value       = local.keycloak_issuer_uri
}

output "keycloak_public_base_url" {
  description = "The public Keycloak base URL exposed through the gateway"
  value       = local.keycloak_issuer_host != "" ? "https://${local.keycloak_issuer_host}${local.tool_base_path}/auth" : null
}

output "keycloak_caais_broker_callback_template" {
  description = "Template callback URL to register in CAAIS (replace <idp-alias> with the Keycloak broker alias)"
  value       = local.keycloak_issuer_host != "" ? "https://${local.keycloak_issuer_host}${local.tool_base_path}/auth/realms/${var.keycloak_realm}/broker/<idp-alias>/endpoint" : null
}

output "keycloak_caais_redirect_uri" {
  description = "Concrete redirect_uri to register with CAAIS for the 'caais' broker alias."
  value       = local.keycloak_issuer_host != "" ? "https://${local.keycloak_issuer_host}${local.tool_base_path}/auth/realms/${var.keycloak_realm}/broker/caais/endpoint" : null
}


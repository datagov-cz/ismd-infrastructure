# Outputs for Tool Apps Module

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

# Database outputs
output "postgres_server_name" {
  description = "The name of the PostgreSQL Flexible Server"
  value       = var.deploy_postgres ? azurerm_postgresql_flexible_server.tool[0].name : null
}

output "fuseki_name" {
  description = "The name of the Fuseki container app"
  value       = var.deploy_fuseki ? azurerm_container_app.fuseki[0].name : null
}

output "keycloak_name" {
  description = "The name of the Keycloak container app"
  value       = var.deploy_keycloak ? azurerm_container_app.keycloak[0].name : null
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
  value       = local.keycloak_issuer_host != "" ? "https://${local.keycloak_issuer_host}/auth" : null
}

output "keycloak_caais_broker_callback_template" {
  description = "Template callback URL to register in CAAIS (replace <idp-alias> with the Keycloak broker alias)"
  value       = local.keycloak_issuer_host != "" ? "https://${local.keycloak_issuer_host}/auth/realms/${var.keycloak_realm}/broker/<idp-alias>/endpoint" : null
}

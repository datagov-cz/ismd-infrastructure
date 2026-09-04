output "realm_id" {
  description = "The ismd realm id."
  value       = keycloak_realm.ismd.id
}

output "ismd_app_client_uuid" {
  description = "Internal UUID of the ismd-app client."
  value       = keycloak_openid_client.ismd_app.id
}

output "user_role_name" {
  value = keycloak_role.user.name
}

output "admin_role_name" {
  value = keycloak_role.admin.name
}

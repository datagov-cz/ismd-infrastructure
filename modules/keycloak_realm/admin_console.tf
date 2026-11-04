# The realm's own admin console client (/admin/<realm>/console), created by Keycloak.
#
# Nobody in the ismd realm holds realm-management roles, so any realm user — NIA and
# CAAIS citizens included — could sign in there and land on an empty console. Disabled
# here so they cannot sign in at all. Master admins manage this realm from the MASTER
# console, which uses the master realm's own clients and is unaffected.
#
# Adopted by an import block (keycloak-config/main.tf), not created. Every attribute
# restates the live client as read on TEST 2026-09-18 except enabled. prevent_destroy:
# turning disable_realm_admin_console off must not delete the built-in client — remove
# it from state instead (terraform state rm), then re-enable it in Keycloak.

resource "keycloak_openid_client" "security_admin_console" {
  count = var.disable_realm_admin_console ? 1 : 0

  realm_id  = keycloak_realm.ismd.id
  client_id = "security-admin-console"
  name      = "$${client_security-admin-console}"
  enabled   = false

  access_type = "PUBLIC"
  root_url    = "$${authAdminUrl}"
  base_url    = "/admin/${keycloak_realm.ismd.realm}/console/"

  valid_redirect_uris             = ["/admin/${keycloak_realm.ismd.realm}/console/*"]
  valid_post_logout_redirect_uris = ["+"]
  web_origins                     = ["+"]

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  pkce_code_challenge_method   = "S256"
  full_scope_allowed           = false
  frontchannel_logout_enabled  = false
  consent_required             = false

  # Live values; the provider would otherwise default both to true.
  backchannel_logout_session_required = false
  use_refresh_tokens                  = false

  lifecycle {
    prevent_destroy = true
  }
}

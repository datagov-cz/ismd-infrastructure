terraform {
  required_providers {
    keycloak = {
      source = "keycloak/keycloak"
    }
  }
}

resource "keycloak_realm" "ismd" {
  realm        = var.realm_name
  enabled      = var.realm_enabled
  display_name = var.realm_display_name
  ssl_required = var.ssl_required

  login_with_email_allowed = var.login_with_email_allowed
  registration_allowed     = var.registration_allowed
  reset_password_allowed   = var.reset_password_allowed
  verify_email             = var.verify_email

  # Pin to the realm's current value so import is a no-op (also the KC default).
  default_signature_algorithm = "RS256"

  # Only rendered once real ACS SMTP credentials are supplied (smtp_enabled).
  dynamic "smtp_server" {
    for_each = var.smtp_enabled ? [1] : []
    content {
      host              = var.smtp_host
      port              = var.smtp_port
      from              = var.smtp_from
      from_display_name = var.smtp_from_display_name
      ssl               = false
      starttls          = var.smtp_starttls

      auth {
        username = var.smtp_username
        password = var.smtp_password
      }
    }
  }

  # Changing realm name would destroy+recreate the realm and drop users.
  lifecycle {
    prevent_destroy = true
  }
}

# Custom realm roles (the only non-built-in roles in the export).
resource "keycloak_role" "user" {
  realm_id = keycloak_realm.ismd.id
  name     = "USER"
}

resource "keycloak_role" "admin" {
  realm_id = keycloak_realm.ismd.id
  name     = "ADMIN"
}

# Auto-assign USER to every new user (on top of Keycloak's built-in defaults).
# ADMIN is intentionally NOT here — it stays a deliberate, manual grant.
resource "keycloak_default_roles" "default" {
  realm_id      = keycloak_realm.ismd.id
  default_roles = concat(var.extra_default_roles, [keycloak_role.user.name])
}

# The single custom OIDC client. Public client, standard + direct-access flows
# (matches the DEV realm export).
resource "keycloak_openid_client" "ismd_app" {
  realm_id  = keycloak_realm.ismd.id
  client_id = "ismd-app"
  enabled   = true

  access_type                  = "PUBLIC"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  implicit_flow_enabled        = false
  service_accounts_enabled     = false

  # Matches the current realm (refresh tokens off). The provider default is
  # true; pinned here to avoid silently changing session behavior on import.
  # Flip to true deliberately if we want next-auth refresh-token sessions.
  use_refresh_tokens = false

  root_url                        = var.ismd_app_root_url
  base_url                        = var.ismd_app_root_url
  valid_redirect_uris             = concat(var.ismd_app_valid_redirect_uris, var.additional_redirect_uris)
  web_origins                     = concat(var.ismd_app_web_origins, var.additional_web_origins)
  valid_post_logout_redirect_uris = concat(var.ismd_app_post_logout_redirect_uris, var.additional_post_logout_redirect_uris)
}

# Reusable ismd realm template. Manages only custom resources (realm, ismd-app
# client, ADMIN/USER roles, default-roles, optional SMTP). Keycloak owns its
# built-in clients/roles/flows/scopes — we do not declare those.
#
# Users are NEVER managed here: they are runtime data in Postgres and stay
# environment-local. Re-applying this module never creates or deletes users.

variable "realm_name" {
  description = "Realm id/name. Changing this forces realm replacement (drops users) — do not change."
  type        = string
  default     = "ismd"
}

variable "realm_display_name" {
  type    = string
  default = "ismd"
}

variable "realm_enabled" {
  type    = bool
  default = true
}

variable "ssl_required" {
  description = "Keycloak ssl_required: 'external' (default), 'all', or 'none'."
  type        = string
  default     = "external"
}

# --- Session lifetimes ---

variable "sso_session_idle_timeout" {
  description = "SSO session idle timeout (Go duration, e.g. '10h'). How long with no activity before the session dies. Set ≥ longest expected inactivity gap so a dev isn't logged out over lunch/meetings."
  type        = string
  default     = "10h"
}

variable "sso_session_max_lifespan" {
  description = "SSO session max lifespan (Go duration, e.g. '10h'). Hard ceiling regardless of activity; after this the user must re-authenticate."
  type        = string
  default     = "10h"
}

# --- Login / registration flags ---

variable "login_with_email_allowed" {
  type    = bool
  default = true
}

variable "registration_allowed" {
  description = "Self-registration. Kept false: access is gated by account provisioning, not open sign-up (CAAIS workaround)."
  type        = bool
  default     = false
}

variable "reset_password_allowed" {
  description = "Forgot-password flow. Requires working SMTP — keep false until ACS SMTP creds are live."
  type        = bool
  default     = false
}

variable "verify_email" {
  description = "Email verification on account actions. Requires working SMTP — keep false until ACS SMTP creds are live."
  type        = bool
  default     = false
}

variable "extra_default_roles" {
  description = <<-EOT
    Roles auto-assigned to every new user, on top of the USER role this module
    always appends. Includes Keycloak's built-in defaults (offline_access,
    uma_authorization, and the account client roles) so importing the existing
    realm does NOT strip self-service account management — keycloak_default_roles
    reconciles the whole composite, so anything omitted here gets removed.
  EOT
  type        = list(string)
  default = [
    "offline_access",
    "uma_authorization",
    "account/view-profile",
    "account/manage-account",
  ]
}

# --- ismd-app client ---

variable "ismd_app_root_url" {
  description = "Root/base URL of the app, e.g. https://oha03.dia.gov.cz/popisujeme"
  type        = string
}

variable "ismd_app_valid_redirect_uris" {
  type = list(string)
}

variable "ismd_app_web_origins" {
  description = "CORS web origins for the public client. Avoid '*' — list explicit origins."
  type        = list(string)
}

variable "ismd_app_post_logout_redirect_uris" {
  type    = list(string)
  default = []
}

variable "additional_redirect_uris" {
  description = "Extra valid redirect URIs (e.g. http://localhost:3000/* for the local-frontend → deployed-backend dev loop). Keep empty on TEST/PROD."
  type        = list(string)
  default     = []
}

variable "additional_web_origins" {
  description = "Extra CORS web origins (e.g. http://localhost:3000). DEV-only; keep empty on TEST/PROD."
  type        = list(string)
  default     = []
}

variable "additional_post_logout_redirect_uris" {
  description = "Extra post-logout redirect URIs (e.g. http://localhost:3000/*). DEV-only; keep empty on TEST/PROD."
  type        = list(string)
  default     = []
}

# --- CAAIS identity provider (brokered OIDC, mTLS) ---

variable "enable_caais" {
  description = "Render the CAAIS identity provider + claim mappers. Keep false until the client_id and endpoint URLs are set per env AND the container-side mTLS keystore is live."
  type        = bool
  default     = false
}

variable "caais_client_id" {
  description = "CAAIS-issued Relying Party (AIS) identifier. Not a secret. Required when enable_caais = true."
  type        = string
  default     = ""
}

variable "caais_authorization_url" {
  description = "CAAIS authorization endpoint (rest- host), e.g. https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/authorize"
  type        = string
  default     = ""
}

variable "caais_token_url" {
  description = "CAAIS token endpoint — SEPARATE mTLS host (cert-), e.g. https://cert-openidconnectapi.caais-test-ext.gov.cz/oauth2/token"
  type        = string
  default     = ""
}

variable "caais_jwks_url" {
  description = "CAAIS JWKS endpoint (rest- host), e.g. https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/jwks"
  type        = string
  default     = ""
}

variable "caais_user_info_url" {
  description = "CAAIS userinfo endpoint if used; leave empty to rely on id_token claims."
  type        = string
  default     = ""
}

variable "caais_issuer" {
  description = "CAAIS issuer (iss) for token validation; take from the .well-known/openid-configuration. Empty = skip issuer validation."
  type        = string
  default     = ""
}

variable "caais_logout_url" {
  description = "CAAIS end_session endpoint (rest- host), e.g. https://rest-openidconnectapi.caais-test-ext.gov.cz/oauth2/end_session. Set so Keycloak propagates logout to CAAIS (single-logout). Empty = no IdP logout URL."
  type        = string
  default     = ""
}

variable "caais_default_scopes" {
  description = "Scopes requested from CAAIS. Start minimal; widen later with a plain apply (users re-login to pick up new claims)."
  type        = string
  default     = "openid profile"
}

variable "caais_validate_signature" {
  description = "Validate CAAIS id_token signatures against jwks_url. Requires caais_jwks_url set."
  type        = bool
  default     = true
}

# --- SMTP (ACS) ---

variable "smtp_enabled" {
  description = "Render the realm smtp_server block. Leave false until ACS SMTP username/password (Layer A) are provided."
  type        = bool
  default     = false
}

variable "smtp_host" {
  type    = string
  default = "smtp.azurecomm.net"
}

variable "smtp_port" {
  type    = string
  default = "587"
}

variable "smtp_from" {
  description = "Sender address. ACS managed-domain (DoNotReply@<guid>.azurecomm.net) now; auth.dia.gov.cz later."
  type        = string
  default     = ""
}

variable "smtp_from_display_name" {
  type    = string
  default = "DIA – Digitální informační agentura"
}

variable "smtp_starttls" {
  type    = bool
  default = true
}

variable "smtp_username" {
  type      = string
  default   = ""
  sensitive = true
}

variable "smtp_password" {
  type      = string
  default   = ""
  sensitive = true
}

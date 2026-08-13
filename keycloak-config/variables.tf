# --- Keycloak admin connection ---

variable "keycloak_url" {
  description = "Base URL of the running Keycloak, e.g. https://oha03.dia.gov.cz"
  type        = string
}

# Reuses the same variable names the main state already sets in .env.<env>
# (TF_VAR_tool_keycloak_admin_user / TF_VAR_tool_keycloak_admin_password) — same
# Keycloak, same master admin — so no duplicate secret under a new name.
variable "tool_keycloak_admin_user" {
  description = "Master-realm admin user (KEYCLOAK_ADMIN on the container)."
  type        = string
  default     = "admin"
}

variable "tool_keycloak_admin_password" {
  description = "Master-realm admin password (KEYCLOAK_ADMIN_PASSWORD). Supplied via TF_VAR_tool_keycloak_admin_password in .env.<env>; never in committed tfvars."
  type        = string
  sensitive   = true
}

# --- App / client ---

variable "app_base_url" {
  description = "Public app base URL incl. basePath, e.g. https://oha03.dia.gov.cz/popisujeme"
  type        = string
}

variable "app_origin" {
  description = "CORS origin for the client (scheme+host, no path), e.g. https://oha03.dia.gov.cz"
  type        = string
}

variable "local_dev_origins" {
  description = <<-EOT
    Extra origins to allow on the ismd-app client for the local-frontend →
    deployed-backend dev loop, e.g. ["http://localhost:3000"]. Each becomes a
    valid redirect URI (<origin>/*), a web origin, and a post-logout URI.
    DEV ONLY — leave [] on TEST/PROD so localhost is never trusted there.
  EOT
  type        = list(string)
  default     = []
}

# --- Registration / email flags (default off; flip deliberately) ---

variable "registration_allowed" {
  type    = bool
  default = false
}

variable "reset_password_allowed" {
  type    = bool
  default = false
}

variable "verify_email" {
  type    = bool
  default = false
}

# --- Session lifetimes ---
# Both default to the module's 10h; DEV overrides to 24h so a dev stays logged in
# across a full day of testing. Access tokens stay short and refresh underneath —
# these are the SSO session bounds, not token lifetimes.

variable "sso_session_idle_timeout" {
  description = "SSO session idle timeout (Go duration). How long with no activity before the session dies."
  type        = string
  default     = "10h"
}

variable "sso_session_max_lifespan" {
  description = "SSO session max lifespan (Go duration). Hard ceiling regardless of activity."
  type        = string
  default     = "10h"
}

# --- CAAIS brokered login ---

variable "enable_caais" {
  description = "Render the CAAIS identity provider in the realm. Keep false until client_id is issued and the container mTLS keystore is live."
  type        = bool
  default     = false
}

variable "caais_client_id" {
  description = "CAAIS-issued AIS/client identifier (not a secret)."
  type        = string
  default     = ""
}

variable "caais_authorization_url" {
  description = "CAAIS authorize endpoint (rest- host)."
  type        = string
  default     = ""
}

variable "caais_token_url" {
  description = "CAAIS token endpoint (cert- mTLS host)."
  type        = string
  default     = ""
}

variable "caais_jwks_url" {
  description = "CAAIS JWKS endpoint (rest- host)."
  type        = string
  default     = ""
}

variable "caais_user_info_url" {
  description = "CAAIS userinfo endpoint; empty to rely on id_token claims."
  type        = string
  default     = ""
}

variable "caais_issuer" {
  description = "CAAIS issuer (iss) from .well-known; empty to skip issuer validation."
  type        = string
  default     = ""
}

variable "caais_logout_url" {
  description = "CAAIS end_session endpoint (rest- host) for Keycloak->CAAIS logout propagation."
  type        = string
  default     = ""
}

# --- NIA (direct Národní bod registration) ---

variable "enable_nia" {
  description = "Render the NIA identity provider in the realm. Keep false until the 'Unikátní URL' is registered on identita.gov.cz and usable as client_id."
  type        = bool
  default     = false
}

variable "nia_client_id" {
  description = "The registered 'Unikátní URL' — NIA uses it as the OIDC client_id. Must match the registration exactly."
  type        = string
  default     = ""
}

variable "nia_client_secret" {
  description = "Shared secret for the NIA token endpoint, if one is issued. Supply via TF_VAR_nia_client_secret — never commit."
  type        = string
  default     = ""
  sensitive   = true
}

variable "nia_client_auth_method" {
  description = "Keycloak clientAuthMethod for the NIA token request body."
  type        = string
  default     = "client_secret_post"
}

variable "nia_authorization_url" {
  description = "NIA authorize endpoint."
  type        = string
  default     = ""
}

variable "nia_token_url" {
  description = "NIA token endpoint (same host as authorize)."
  type        = string
  default     = ""
}

variable "nia_jwks_url" {
  description = "NIA JWKS endpoint (from the discovery document, not the handbook)."
  type        = string
  default     = ""
}

variable "nia_user_info_url" {
  description = "NIA userinfo endpoint; empty to rely on id_token claims."
  type        = string
  default     = ""
}

variable "nia_issuer" {
  description = "NIA issuer (iss) — the URN urn:microsoft:cgg2010:fpsts, identical on test and prod. Empty to skip issuer validation."
  type        = string
  default     = ""
}

variable "nia_logout_url" {
  description = "NIA endsession endpoint for Keycloak->NIA logout propagation."
  type        = string
  default     = ""
}

variable "nia_default_scopes" {
  description = "Scopes requested from NIA. 'profile' is NOT supported; append a LoA scope once DIA settles the level."
  type        = string
  default     = "openid"
}

variable "nia_validate_signature" {
  description = "Validate NIA id_token signatures against nia_jwks_url."
  type        = bool
  default     = true
}

# --- SMTP (ACS) — supply once Layer A creds exist ---

variable "smtp_enabled" {
  type    = bool
  default = false
}

variable "smtp_from" {
  type    = string
  default = ""
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

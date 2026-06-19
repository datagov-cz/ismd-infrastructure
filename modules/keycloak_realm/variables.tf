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

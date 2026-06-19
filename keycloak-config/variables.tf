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

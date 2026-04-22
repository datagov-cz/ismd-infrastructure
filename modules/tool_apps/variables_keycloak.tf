# Tool Apps Module — Keycloak and CAAIS variable declarations

variable "deploy_keycloak" {
  description = "Whether to deploy Keycloak as part of tool apps"
  type        = bool
  default     = true
}

variable "enable_caais" {
  description = "Whether CAAIS integration is enabled for Keycloak"
  type        = bool
  default     = true
}

# Keycloak container image
variable "keycloak_image" {
  description = "Base container image URL for Keycloak (without tag)"
  type        = string
  default     = "quay.io/keycloak/keycloak"
}

variable "keycloak_image_tag" {
  description = "Tag for the Keycloak container image"
  type        = string
  default     = "24.0.2"
}

variable "keycloak_app_name" {
  description = "Name of the Keycloak container app"
  type        = string
  default     = "ismd-tool-keycloak"
}

# Keycloak admin credentials
variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
  default     = ""
}

# Keycloak hostname and realm
variable "keycloak_hostname" {
  description = "Optional Keycloak hostname for admin and public endpoints"
  type        = string
  default     = ""
}

variable "keycloak_realm" {
  description = "Keycloak realm used by tool frontend/backend"
  type        = string
  default     = "ismd"
}

variable "keycloak_issuer_uri" {
  description = "Optional explicit issuer URI. If empty, issuer is derived from deployed Keycloak and realm."
  type        = string
  default     = ""
}

# OIDC client
variable "keycloak_client_id" {
  description = "OIDC client ID used by tool frontend/backend"
  type        = string
  default     = "ismd-app"
}

variable "keycloak_client_secret" {
  description = "OIDC client secret used by tool frontend/backend"
  type        = string
  sensitive   = true
  default     = ""
}

# CAAIS federation
variable "caais_client_id" {
  description = "CAAIS client ID configured in Keycloak"
  type        = string
  default     = ""
}

# Keycloak database (uses shared PostgreSQL when deploy_postgres = true)
variable "keycloak_db_name" {
  description = "Database name used by Keycloak"
  type        = string
  default     = "keycloak_db"
}

variable "keycloak_postgres_url" {
  description = "External JDBC URL for Keycloak database when deploy_postgres=false"
  type        = string
  default     = ""
}

variable "keycloak_postgres_user" {
  description = "External PostgreSQL username for Keycloak when deploy_postgres=false"
  type        = string
  default     = ""
}

variable "keycloak_postgres_password" {
  description = "External PostgreSQL password for Keycloak when deploy_postgres=false"
  type        = string
  sensitive   = true
  default     = ""
}

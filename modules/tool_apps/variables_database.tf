# Tool Apps Module — database and Fuseki variable declarations

# Database deployment flags
variable "deploy_postgres" {
  description = "Whether to deploy Azure Database for PostgreSQL Flexible Server"
  type        = bool
  default     = true
}

variable "deploy_fuseki" {
  description = "Whether to deploy Fuseki as a container app"
  type        = bool
  default     = true
}

# PostgreSQL connection (fallback when deploy_postgres = false)
variable "postgres_url" {
  description = "JDBC URL for PostgreSQL"
  type        = string
  sensitive   = true
  default     = "" # Optional until DB is ready
}

variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
  sensitive   = true
  default     = ""
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
  default     = ""
}

# PostgreSQL deployment configuration
variable "postgres_db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "ismd_tool_db"
}

variable "postgres_admin_user" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "ismdadmin"
}

# Per-app user separation (see infrastructure/db/user-separation/). The tool
# backend logs in as this dedicated LOGIN role instead of the server admin.
# Empty = fall back to postgres_admin_user (current behaviour) so this stays a
# no-op until an env flips it. Set to "ismd_tool_app" AFTER running 01-tool.sql
# and pointing the tool's postgres password secret at that role's password.
variable "backend_db_user" {
  description = "Dedicated Postgres LOGIN role for the tool backend. Empty = use the admin login. Set to 'ismd_tool_app' once db/user-separation Phase 1 is applied and the tool password secret holds that role's password."
  type        = string
  default     = ""
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

# The server itself lives in modules/postgres; these are injected from the env
# root so this module can create its databases and build connection URLs.
variable "postgres_server_id" {
  description = "Resource id of the shared Flexible Server (modules/postgres output server_id). The tool and keycloak databases are created against it."
  type        = string
  default     = ""
}

variable "postgres_fqdn" {
  description = "FQDN of the shared Flexible Server (modules/postgres output fqdn), used to build the JDBC URLs."
  type        = string
  default     = ""
}

variable "fuseki_url" {
  description = "URL for Apache Jena Fuseki (external, if not deploying Fuseki container)"
  type        = string
  default     = ""
}

# Fuseki deployment configuration
variable "fuseki_image" {
  description = "Container image for Fuseki (updated by CI after each build)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-tool-fuseki:latest"
}


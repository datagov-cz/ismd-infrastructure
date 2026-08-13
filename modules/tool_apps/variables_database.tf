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

variable "postgres_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server (e.g., B_Standard_B1ms for burstable)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 32768 # 32GB
}

# Network access control for the public Postgres endpoint.
# These two lists are the ONLY sources of allowed inbound IPs — there is no
# longer a blanket "AllowAzureServices" (any Azure tenant) or "AllowAllForDev"
# (entire internet) rule. Empty lists = no inbound access.
variable "allow_azure_services" {
  description = "Allow Azure-resident services (the 0.0.0.0 special rule) to reach Postgres. Required for app connectivity while the Container Apps subnet has no NAT gateway, because outbound egress is Azure's dynamic SNAT rather than a fixed IP. Set false only once a stable NAT egress IP is added to app_outbound_ips."
  type        = bool
  default     = true
}

variable "app_outbound_ips" {
  description = "Stable outbound IP(s) of the apps (e.g. a NAT gateway public IP) allowlisted to reach the public Postgres endpoint. Empty while relying on allow_azure_services. NOTE: the Container Apps env *inbound* static IP is NOT the egress IP — do not use it here."
  type        = list(string)
  default     = []
}

variable "admin_allowed_ips" {
  description = "Operator/admin public IP(s) allowed direct access to Postgres for troubleshooting (each becomes a single-IP firewall rule). Replaces the AllowAllForDev internet-wide rule. Empty = no direct human access."
  type        = list(string)
  default     = []
}

# Fuseki connection (fallback when deploy_fuseki = false)
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


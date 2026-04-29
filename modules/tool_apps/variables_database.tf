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


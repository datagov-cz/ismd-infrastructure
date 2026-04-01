# Core Environment Variables
variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the tool resource group"
  type        = string
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
}

variable "container_app_environment_id" {
  description = "ID of the container app environment"
  type        = string
}

variable "container_app_environment_default_domain" {
  description = "Default domain of the container app environment"
  type        = string
}

# Application Gateway Configuration
variable "app_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  type        = string
}

variable "app_gateway_hostname" {
  description = "Hostname for the environment"
  type        = string
  default     = ""
}

# Container Images
variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image"
  type        = string
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
}

variable "backend_image_tag" {
  description = "Tag for the backend container image"
  type        = string
}

# App Names
variable "frontend_app_name" {
  description = "Name of the frontend container app"
  type        = string
  default     = "ismd-tool-frontend"
}

variable "backend_app_name" {
  description = "Name of the backend container app"
  type        = string
  default     = "ismd-tool-backend"
}

# Workload Profile Configuration
variable "workload_profile_name" {
  description = "Name of the workload profile to use for the container apps"
  type        = string
  default     = "Consumption"
}

variable "workload_profile_type" {
  description = "Type of the workload profile (e.g., 'Consumption', 'D4')"
  type        = string
  default     = "Consumption"
}

variable "additional_cors_origins" {
  description = "List of additional CORS origins to allow"
  type        = list(string)
  default     = []
}

# Database & Fuseki Configuration
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

variable "fuseki_url" {
  description = "URL for Apache Jena Fuseki (external, if not deploying Fuseki container)"
  type        = string
  default     = ""
}

# Database deployment options
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

variable "fuseki_admin_password" {
  description = "Fuseki admin password"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "nextauth_secret" {
  description = "NextAuth.js secret for session encryption"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_base_path" {
  description = "Optional base path prefix for tool app routes (e.g. /popisujeme). Use empty string for root deployment."
  type        = string
  default     = "/popisujeme"
}

# Keycloak / CAAIS
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

variable "keycloak_hostname" {
  description = "Optional Keycloak hostname for admin and public endpoints"
  type        = string
  default     = ""
}

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

variable "keycloak_issuer_uri" {
  description = "Optional explicit issuer URI. If empty, issuer is derived from deployed Keycloak and realm."
  type        = string
  default     = ""
}

variable "keycloak_realm" {
  description = "Keycloak realm used by tool frontend/backend"
  type        = string
  default     = "ismd"
}

variable "caais_client_id" {
  description = "CAAIS client ID configured in Keycloak"
  type        = string
  default     = ""
}

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


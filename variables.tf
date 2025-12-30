variable "environment" {
  description = "The environment (dev, test, prod)"
  type        = string
}


variable "location" {
  description = "The Azure region to deploy to"
  type        = string
  default     = "germanywestcentral"
}

variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend-dev"
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image"
  type        = string
  default     = "latest"
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend-dev"
}

variable "backend_image_tag" {
  description = "Tag for the backend container image"
  type        = string
  default     = "latest"
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
  default     = "ismd-shared-tfstate"
}

variable "validator_resource_group_name" {
  description = "Name of the validator resource group"
  type        = string
}

variable "tool_resource_group_name" {
  description = "Name of the tool resource group"
  type        = string
}

variable "tool_frontend_image" {
  description = "Base container image URL for the tool frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-tool-frontend-dev"
}

variable "tool_frontend_image_tag" {
  description = "Tag for the tool frontend container image"
  type        = string
  default     = "latest"
}

variable "tool_backend_image" {
  description = "Base container image URL for the tool backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-tool-backend-dev"
}

variable "tool_backend_image_tag" {
  description = "Tag for the tool backend container image"
  type        = string
  default     = "latest"
}

variable "tool_frontend_app_name" {
  description = "Base name of the tool frontend container app (without environment suffix)"
  type        = string
  default     = "ismd-tool-frontend"
}

variable "tool_backend_app_name" {
  description = "Base name of the tool backend container app (without environment suffix)"
  type        = string
  default     = "ismd-tool-backend"
}

# Tool Database & Fuseki Configuration
variable "tool_postgres_url" {
  description = "JDBC URL for Tool PostgreSQL"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_postgres_user" {
  description = "Tool PostgreSQL username"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_postgres_password" {
  description = "Tool PostgreSQL password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_fuseki_url" {
  description = "URL for Tool Fuseki"
  type        = string
  default     = ""
}

variable "tool_nextauth_secret" {
  description = "NextAuth.js secret for Tool frontend"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_fuseki_admin_password" {
  description = "Admin password for Tool Fuseki"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "subscription_id" {
  description = "The Azure subscription ID"
  type        = string
  default     = "" # Will be populated from ARM_SUBSCRIPTION_ID environment variable if not specified
}

variable "container_app_environment_domain" {
  description = "The default domain for container apps in the environment"
  type        = string
  default     = "yellowforest-c02e8fbc.germanywestcentral.azurecontainerapps.io"
}

variable "frontend_app_name" {
  description = "Base name of the frontend container app (without environment suffix)"
  type        = string
  default     = "ismd-validator-frontend"
}

variable "backend_app_name" {
  description = "Base name of the backend container app (without environment suffix)"
  type        = string
  default     = "ismd-validator-backend"
}

variable "additional_cors_origins" {
  description = "List of additional CORS origins to allow"
  type        = list(string)
  default     = []
}

variable "app_gateway_hostname" {
  description = "Hostname for the environment (e.g., ismd.oha03.dia.gov.cz)"
  type        = string
  default     = ""
}

variable "deploy_tool_apps" {
  description = "Whether to deploy Tool apps (set to false to deploy only Validator)"
  type        = bool
  default     = true
}

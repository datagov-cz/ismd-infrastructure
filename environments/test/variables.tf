# Test Environment — variable declarations

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "test"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "germanywestcentral"
}

variable "shared_resource_group_name" {
  description = "Name of the shared resource group"
  type        = string
  default     = "ismd-shared-test"
}

variable "validator_resource_group_name" {
  description = "Name of the validator resource group"
  type        = string
  default     = "ismd-validator-test"
}

variable "tool_resource_group_name" {
  description = "Name of the tool resource group"
  type        = string
  default     = "ismd-tool-test"
}

variable "frontend_image" {
  description = "Base container image URL for the frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-frontend"
}

variable "frontend_image_tag" {
  description = "Tag for the frontend container image (e.g., 'latest', '1.0.0' or '1.0.0-abc1234')"
  type        = string
  default     = "latest"

  validation {
    condition     = var.frontend_image_tag == "latest" || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.frontend_image_tag))
    error_message = "The frontend_image_tag must be 'latest' or a valid version number (e.g., '1.0.0' or '1.0.0-abc1234')."
  }
}

variable "backend_image" {
  description = "Base container image URL for the backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-validator-backend"
}

variable "backend_image_tag" {
  description = "Tag for the backend container image (e.g., 'latest', '1.0.0' or '1.0.0-abc1234')"
  type        = string
  default     = "latest"

  validation {
    condition     = var.backend_image_tag == "latest" || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+)?$", var.backend_image_tag))
    error_message = "The backend_image_tag must be 'latest' or a valid version number (e.g., '1.0.0' or '1.0.0-abc1234')."
  }
}

variable "tool_frontend_image" {
  description = "Base container image URL for the tool frontend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-tool-frontend"
}

variable "tool_frontend_image_tag" {
  description = "Tag for the tool frontend container image"
  type        = string
  default     = "latest"
}

variable "tool_backend_image" {
  description = "Base container image URL for the tool backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-tool-backend"
}

variable "tool_backend_image_tag" {
  description = "Tag for the tool backend container image"
  type        = string
  default     = "latest"
}

# Variables for connecting to the shared global network
variable "shared_global_vnet_id" {
  description = "ID of the shared global VNet"
  type        = string
}

variable "shared_global_vnet_name" {
  description = "Name of the shared global VNet"
  type        = string
}

variable "shared_global_resource_group_name" {
  description = "Name of the shared global resource group"
  type        = string
}

variable "app_gateway_public_ip_address" {
  description = "Public IP address of the shared Application Gateway"
  type        = string
}

variable "app_gateway_hostname" {
  description = "Hostname for the test environment"
  type        = string
  default     = "oha03.dia.gov.cz"
}

variable "frontend_app_name" {
  description = "Name of the frontend application"
  type        = string
  default     = "ismd-validator-frontend"
}

variable "backend_app_name" {
  description = "Name of the backend application"
  type        = string
  default     = "ismd-validator-backend"
}

variable "tool_frontend_app_name" {
  description = "Name of the tool frontend application"
  type        = string
  default     = "ismd-tool-frontend"
}

variable "tool_backend_app_name" {
  description = "Name of the tool backend application"
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

variable "tool_base_path" {
  description = "Optional base path prefix for tool app routes (e.g. /popisujeme). Use empty string for root deployment."
  type        = string
  default     = "/popisujeme"
}

variable "tool_deploy_keycloak" {
  description = "Whether to deploy Keycloak in tool apps"
  type        = bool
  default     = true
}

variable "tool_enable_caais" {
  description = "Whether to enable CAAIS integration for Keycloak"
  type        = bool
  default     = true
}

variable "tool_keycloak_image" {
  description = "Base image for Keycloak container app"
  type        = string
  default     = "quay.io/keycloak/keycloak"
}

variable "tool_keycloak_image_tag" {
  description = "Tag for Keycloak container app image"
  type        = string
  default     = "24.0.2"
}

variable "tool_keycloak_app_name" {
  description = "Base name for Keycloak container app"
  type        = string
  default     = "ismd-tool-keycloak"
}

variable "tool_keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "tool_keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_keycloak_hostname" {
  description = "Optional Keycloak hostname for admin and public endpoints"
  type        = string
  default     = ""
}

variable "tool_keycloak_realm" {
  description = "Keycloak realm used by tool apps"
  type        = string
  default     = "ismd"
}

variable "tool_keycloak_issuer_uri" {
  description = "Optional explicit Keycloak issuer URI override"
  type        = string
  default     = ""
}

variable "tool_keycloak_client_id" {
  description = "OIDC client ID used by tool apps"
  type        = string
  default     = "ismd-app"
}

variable "tool_keycloak_client_secret" {
  description = "OIDC client secret used by tool apps"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_caais_client_id" {
  description = "CAAIS client ID configured in Keycloak"
  type        = string
  default     = ""
}

variable "additional_cors_origins" {
  description = "List of additional CORS origins to allow"
  type        = list(string)
  default     = []
}

variable "deploy_tool_apps" {
  description = "Whether to deploy Tool apps (set to false to deploy only Validator)"
  type        = bool
  default     = true
}

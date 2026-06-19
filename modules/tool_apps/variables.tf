# Tool Apps Module — core variable declarations
# Database vars: variables_database.tf | Keycloak/CAAIS vars: variables_keycloak.tf

# Application Insights — connection string injected into every HTTP-speaking app
# as APPLICATIONINSIGHTS_CONNECTION_STRING. Java apps auto-attach via the AI agent;
# Next.js apps need the `applicationinsights` npm package wired explicitly.
variable "app_insights_connection_string" {
  description = "Application Insights connection string for app telemetry. Passed through from modules/shared.app_insights_connection_string."
  type        = string
  sensitive   = true
}

# Core Environment Variables
variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

# DEV-only: expose tool-backend via external ingress so the App Gateway's
# /popisujeme/be/* route (and thus a local frontend) can reach it directly.
# Keep false on TEST/PROD — they stay pure BFF (internal ingress).
variable "backend_external_enabled" {
  description = "Enable external ingress on tool-backend (DEV dev-loop only). False = internal-only BFF."
  type        = bool
  default     = false
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

variable "additional_cors_origins" {
  description = "List of additional CORS origins to allow"
  type        = list(string)
  default     = []
}

# Frontend auth and routing
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

variable "site_status" {
  description = "Frontend gating mode. 'live' serves the app normally; 'coming_soon' and 'maintenance' rewrite all traffic to the matching gated page (the Next.js middleware reads this env var)."
  type        = string
  default     = "live"
  validation {
    condition     = contains(["live", "coming_soon", "maintenance"], var.site_status)
    error_message = "site_status must be one of: live, coming_soon, maintenance."
  }
}

variable "site_preview_secret" {
  description = "Shared secret for bypassing the Coming Soon / Maintenance gate. When non-empty, visiting any URL with ?nahled=<secret> sets a long-lived bypass cookie. Leave empty to disable the bypass entirely. Must not equal the literal 'ne' (reserved for cookie clearing)."
  type        = string
  sensitive   = true
  default     = ""
  validation {
    condition     = var.site_preview_secret != "ne"
    error_message = "site_preview_secret must not equal the literal 'ne' (reserved for cookie clearing via ?nahled=ne)."
  }
}

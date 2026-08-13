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

# Class A pilot: KV secret id for app-insights on the tool backend. Empty = inline
# value (phase 1); a versionless KV secret id flips the backend to a key_vault_secret_id
# reference pulled by its UserAssigned identity (phase 2).
variable "app_insights_kv_secret_id" {
  description = "Versionless KV secret id for the backend's app-insights connection string. Empty keeps the inline value; set (e.g. https://ismd-kv-<env>.vault.azure.net/secrets/app-insights-connection-string) to pull from Key Vault."
  type        = string
  default     = ""
}

variable "enable_app_insights_agent" {
  description = <<-EOT
    Activate the Application Insights Java agent on the backend via JAVA_TOOL_OPTIONS
    (-javaagent). Default false, and it MUST stay false until the jar-bearing image
    is deployed to the env: enabling this injects -javaagent pointing at
    /app/applicationinsights-agent.jar, so if the image doesn't yet carry that jar
    (Dockerfile ADD), the JVM fails to start and the container crashloops. Cut over
    per env (set true) only AFTER the new image ships. The agent auto-reads the
    already-injected APPLICATIONINSIGHTS_CONNECTION_STRING for its destination; an
    empty connection string makes it self-disable regardless.
  EOT
  type        = bool
  default     = false
}

variable "enable_frontend_app_insights" {
  description = <<-EOT
    Activate server-side Application Insights on the Next.js frontend by injecting
    OTEL_SERVICE_NAME (the cloud role name). Separate from enable_app_insights_agent
    because the frontend gates on the @azure/monitor-opentelemetry npm dep being in
    the frontend image, whereas the backend agent gates on the jar — different image
    prerequisites, so they flip independently. Default false; MUST stay false until
    the dep-bearing frontend image ships to the env. The frontend reads the
    already-injected APPLICATIONINSIGHTS_CONNECTION_STRING for its destination.
    Inert (register() no-ops) while OTEL_SERVICE_NAME is unset.
  EOT
  type        = bool
  default     = false
}

variable "outbox_done_retention" {
  description = <<-EOT
    How long DONE outbox rows are kept before the prune scheduler removes them,
    as an ISO-8601 duration (e.g. P30D). Overrides the image default via the
    OUTBOX_DONE_RETENTION env var; no rebuild needed to change it per env.
  EOT
  type        = string
  default     = "P30D"
}

variable "postgres_password_kv_secret_id" {
  description = "Versionless KV secret id for the backend's postgres password. Empty keeps the inline value; set to pull from Key Vault via the backend identity."
  type        = string
  default     = ""
}

variable "keycloak_client_secret_kv_secret_id" {
  description = "Versionless KV secret id for the backend's keycloak client secret. Empty keeps the inline value; set to pull from Key Vault via the backend identity."
  type        = string
  default     = ""
}

# Frontend Class A: KV secret ids, each empty = inline value, set = key_vault_secret_id
# reference pulled by the frontend's UserAssigned identity.
variable "frontend_app_insights_kv_secret_id" {
  description = "Versionless KV secret id for the frontend's app-insights connection string. Empty = inline value."
  type        = string
  default     = ""
}

variable "frontend_nextauth_secret_kv_secret_id" {
  description = "Versionless KV secret id for the frontend's NextAuth secret. Empty = inline value."
  type        = string
  default     = ""
}

variable "frontend_keycloak_client_secret_kv_secret_id" {
  description = "Versionless KV secret id for the frontend's keycloak client secret. Empty = inline value."
  type        = string
  default     = ""
}

variable "frontend_site_preview_secret_kv_secret_id" {
  description = "Versionless KV secret id for the frontend's site-preview bypass secret. Empty = inline value (only present when site_preview_secret is set)."
  type        = string
  default     = ""
}

# Keycloak container Class A: KV secret ids, each empty = inline, set = key_vault_secret_id
# reference pulled by the keycloak_kv identity.
variable "keycloak_admin_password_kv_secret_id" {
  description = "Versionless KV secret id for the keycloak admin password. Empty = inline value."
  type        = string
  default     = ""
}

variable "keycloak_db_password_kv_secret_id" {
  description = "Versionless KV secret id for the keycloak DB password (same value as backend postgres-password when deploy_postgres — point at the single postgres-password secret). Empty = inline value."
  type        = string
  default     = ""
}

variable "keycloak_app_insights_kv_secret_id" {
  description = "Versionless KV secret id for the keycloak container's app-insights connection string. Empty = inline value."
  type        = string
  default     = ""
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

variable "validator_backend_app_name" {
  description = "Full name of the validator backend container app (e.g. ismd-validator-backend-dev). The tool BE calls it internally by app name over the shared Container App Environment; ingress listens on port 80, so no port is appended."
  type        = string
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

# Application Insights — connection string injected into every HTTP-speaking app
# as APPLICATIONINSIGHTS_CONNECTION_STRING. Java apps auto-attach via the AI agent;
# Next.js apps need the `applicationinsights` npm package wired explicitly.
variable "app_insights_connection_string" {
  description = "Application Insights connection string for app telemetry. Passed through from modules/shared.app_insights_connection_string."
  type        = string
  sensitive   = true
}

# Class A: KV secret ids — each empty = inline value, set = key_vault_secret_id
# reference pulled by the respective app's UserAssigned identity.
variable "backend_app_insights_kv_secret_id" {
  description = "Versionless KV secret id for the validator backend's app-insights connection string. Empty = inline value."
  type        = string
  default     = ""
}

variable "enable_app_insights_agent" {
  description = <<-EOT
    Activate the Application Insights Java agent on the validator backend via
    JAVA_TOOL_OPTIONS (-javaagent). Default false, and it MUST stay false until the
    jar-bearing image is deployed to the env: enabling this injects -javaagent
    pointing at /app/applicationinsights-agent.jar, so if the image doesn't yet
    carry that jar (Dockerfile ADD), the JVM fails to start and the container
    crashloops. Cut over per env (set true) only AFTER the new image ships. The
    agent auto-reads the already-injected APPLICATIONINSIGHTS_CONNECTION_STRING for
    its destination; an empty connection string makes it self-disable regardless.
  EOT
  type        = bool
  default     = false
}

variable "frontend_app_insights_kv_secret_id" {
  description = "Versionless KV secret id for the validator frontend's app-insights connection string. Empty = inline value."
  type        = string
  default     = ""
}

variable "frontend_site_preview_secret_kv_secret_id" {
  description = "Versionless KV secret id for the validator frontend's site-preview secret. Empty = inline value (only present when site_preview_secret is set)."
  type        = string
  default     = ""
}

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
  description = "Name of the validator resource group"
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

# Application Gateway Configuration
variable "app_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  type        = string
}

variable "app_gateway_hostname" {
  description = "Hostname for the environment (e.g., ismd.oha03.dia.gov.cz for dev)"
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

variable "backend_port" {
  description = "Port the backend Tomcat binds to; must match the running image's Spring server.port"
  type        = number
}

# App Names
variable "frontend_app_name" {
  description = "Name of the frontend container app"
  type        = string
  default     = "ismd-validator-frontend"
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

variable "backend_app_name" {
  description = "Name of the backend container app"
  type        = string
  default     = "ismd-validator-backend"
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

variable "use_bff" {
  description = "Whether the running frontend image supports the BFF pattern (server-side BE_URL via Next.js rewrites). When true: backend ingress is internal-only and frontend uses BE_URL. When false: legacy mode — backend is externally exposed (restricted to AppGW IP) and frontend uses NEXT_PUBLIC_BE_URL pointing at the public hostname. Set to true ONLY when the deployed frontend image actually supports BFF (v1.0.x with BFF refactor merged)."
  type        = bool
  default     = false
}

variable "public_be_url" {
  description = "Legacy public backend URL used when use_bff = false. Typically https://<app_gateway_hostname>/validujeme."
  type        = string
  default     = ""
}

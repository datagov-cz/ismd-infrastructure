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

variable "deploy_monitoring" {
  description = "Whether to provision the monitoring module (Action Groups + Logic App + Teams notifier). Default false during Phase A rollout; flip true per env once Logic App connector is OAuth-authorized."
  type        = bool
  default     = false
}

variable "paging_email_recipients" {
  description = "Email addresses (or one mail-enabled group address) that receive paging-tier alerts. Empty list → no paging action group is created. Use Plan A (hardcoded individuals) until the Entra mail-enabled group exists; then swap to a single group address."
  type        = list(string)
  default     = []
}

variable "alert_card_language" {
  description = "Language for Teams card labels and severity/status mapping (cs|en). Passed through to the monitoring module."
  type        = string
  default     = "cs"
}

variable "teams_group_id" {
  description = "Teams group (team) ID the Logic App posts alerts to. Set via TF_VAR_teams_group_id in the gitignored .env.<env> (Phase A: maintainer test channel; Phase B: DIA channel)."
  type        = string
  default     = ""
}

variable "teams_channel_id" {
  description = "Teams channel ID within teams_group_id. Set via TF_VAR_teams_channel_id in the gitignored .env.<env>."
  type        = string
  default     = ""
}

# Frontend gating (per-app, per-env). Values: live | coming_soon | maintenance.
variable "validator_site_status" {
  description = "Frontend gating mode for the Validator app."
  type        = string
  default     = "coming_soon"
}

variable "tool_site_status" {
  description = "Frontend gating mode for the Tool app."
  type        = string
  default     = "coming_soon"
}

variable "validator_site_preview_secret" {
  description = "Bypass secret for the Validator app's gate. Empty disables the bypass."
  type        = string
  sensitive   = true
  default     = ""
}

variable "tool_site_preview_secret" {
  description = "Bypass secret for the Tool app's gate. Empty disables the bypass."
  type        = string
  sensitive   = true
  default     = ""
}

variable "validator_use_bff" {
  description = "True if the deployed validator frontend image supports the BFF pattern (server-side BE_URL via Next.js rewrites). False = legacy NEXT_PUBLIC_BE_URL + externally exposed backend."
  type        = bool
  default     = false
}

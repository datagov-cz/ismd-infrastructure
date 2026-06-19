# Core
variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the monitoring resources (typically the shared RG of this env)"
  type        = string
}

# Telemetry plumbing
variable "log_analytics_workspace_id" {
  description = "ID of the LA workspace this env's resources ship logs to. Used as alert scope for log-based rules."
  type        = string
}

variable "application_insights_id" {
  description = "ID of the App Insights resource this env's apps emit telemetry to. Used as alert scope for AI-derived rules and as the parent for availability tests."
  type        = string
}

variable "app_insights_instrumentation_key" {
  description = "Instrumentation key of the App Insights resource. Used by the custom uptime probe Logic App to post custom Availability events to /v2/track. Sensitive."
  type        = string
  sensitive   = true
}

variable "container_app_environment_id" {
  description = "ID of the shared Container App Environment. Used as the scope for management-plane diagnostic settings (fixes the empty CAE Logs blade — gotcha #4/#7 in monitoring-plan.md)."
  type        = string
}

# Localization of the Teams alert card. Affects static labels (Rule/Status/Resource/...)
# and the severity / monitor-condition mapping. Rule names and descriptions in ARM remain
# English so engineers see consistent text on the Azure side.
variable "alert_card_language" {
  description = "Language for Teams card labels and severity/status mapping. One of: cs, en. Default cs to match the rest of the app."
  type        = string
  default     = "cs"

  validation {
    condition     = contains(["cs", "en"], var.alert_card_language)
    error_message = "alert_card_language must be 'cs' or 'en'."
  }
}

# Teams notification target (Logic App posts to this channel)
variable "teams_group_id" {
  description = "Azure AD Group ID of the Teams team that owns the alert channel. Required once Logic App connector is authorized."
  type        = string
  default     = ""
}

variable "teams_channel_id" {
  description = "ID of the Teams channel that receives alert cards (the channel within the team identified by teams_group_id)."
  type        = string
  default     = ""
}

# Container Apps to alert on. Keyed by friendly name (e.g. "tool-be", "validator-fe").
# Each Container App ID becomes the scope of a set of metric alert rules.
variable "container_apps" {
  description = "Map of Container Apps to attach alert rules to. Key = friendly slug (used in alert rule names). Value = { id, name, optional memory_gib }. `memory_gib` is the container's memory allocation in GiB; the memory_high alert threshold is computed as 85%% of it. When unset, defaults to 1 GiB (which yields the 0.85 GiB threshold — fine for the typical FE/BE apps with 1Gi allocation)."
  type = map(object({
    id         = string
    name       = string
    memory_gib = optional(number, 1)
  }))
  default = {}
}

# PostgreSQL Flexible Servers to alert on. Different metric namespace from
# Container Apps (Microsoft.DBforPostgreSQL/flexibleServers), so kept in a
# separate variable + alert file.
variable "postgres_servers" {
  description = "Map of Postgres Flexible Servers to attach alert rules to. Key = friendly slug. Value = { id, name }."
  type = map(object({
    id   = string
    name = string
  }))
  default = {}
}

# Application Gateway alert scope. Optional — when set, the AppGW alert rules
# (backend-unhealthy, 5xx) are deployed and scoped to this AppGW. Cross-state
# reference via data.terraform_remote_state.shared_global from the env's main.tf.
variable "application_gateway_id" {
  description = "Resource ID of the shared Application Gateway. Empty string disables AppGW alert rules."
  type        = string
  default     = ""
}

variable "appgw_excluded_backend_settings" {
  description = "Backend HTTP settings names to exclude from the AppGW unhealthy-host alert. Use for anticipatory pools that point at resources not yet deployed (e.g. tool-prod-* before tool ships to PROD)."
  type        = list(string)
  default     = []
}

# Log Analytics workspace daily ingestion cap — must match the cap configured on the
# workspace itself (in modules/shared). Used to compute the 80%-of-cap alert threshold
# so we get warned BEFORE ingestion silently stops (gotcha #6 in monitoring-plan.md).
variable "log_analytics_daily_cap_gb" {
  description = "Daily ingestion cap (GB) configured on the LA workspace. Used to derive the 80%-of-cap warning threshold. Must match the value passed to modules/shared."
  type        = number
  default     = 0.5
}

# Availability tests — public endpoints monitored by App Insights standard web tests.
# Each entry produces one web test + one metric alert (fail when >= 2 of 3 locations report unhealthy
# over a 10-min window). Set to {} to disable.
variable "availability_tests" {
  description = "Map of public endpoints to probe via App Insights standard web tests. Key = friendly slug (used in test+alert names). Value = { url, expected_status_code (default 200) }."
  type = map(object({
    url                  = string
    expected_status_code = optional(number, 200)
  }))
  default = {}
}

# Paging configuration
variable "paging_email_recipients" {
  description = "Email addresses (or one mail-enabled group address) that receive paging-tier alerts. Empty list → no paging action group is created (typical for dev/test)."
  type        = list(string)
  default     = []
}

# AI Apps Module — variables

variable "environment" {
  description = "Deployment environment (dev, test, prod)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the AI container app"
  type        = string
}

variable "container_app_environment_id" {
  description = "Shared Container App Environment ID"
  type        = string
}

# --- Image ---------------------------------------------------------------

variable "backend_app_name" {
  description = "Base name of the AI backend container app (env suffix appended)"
  type        = string
  default     = "ismd-ai"
}

variable "backend_image" {
  description = "Container image for the AI backend (without tag)"
  type        = string
}

variable "backend_image_tag" {
  description = "Container image tag for the AI backend"
  type        = string
  default     = "latest"
}

# --- Database (shared: tool's Postgres Flexible Server) -------------------

variable "postgres_server_id" {
  description = "Resource ID of the Postgres Flexible Server hosting the ismd_ai database (the tool's server)"
  type        = string
}

variable "postgres_fqdn" {
  description = "FQDN of the Postgres Flexible Server hosting the ismd_ai database"
  type        = string
}

variable "postgres_db_name" {
  description = "Database name for the AI service (created on the shared server)"
  type        = string
  default     = "ismd_ai"
}

variable "postgres_user" {
  description = "Postgres user the AI service connects as (the shared server's admin login)"
  type        = string
}

variable "postgres_password" {
  description = "Inline Postgres password (used only while postgres_password_kv_secret_id is empty)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "postgres_password_kv_secret_id" {
  description = "Key Vault secret id for the Postgres password (empty = use inline value). Two-phase Class A cutover."
  type        = string
  default     = ""
}

# --- LLM -----------------------------------------------------------------

variable "llm_enabled" {
  description = "Enable LLM calls. Keep false until the API key secret is seeded."
  type        = bool
  default     = false
}

variable "llm_provider" {
  description = "LLM provider identifier"
  type        = string
  default     = "OPENAI"
}

variable "llm_model" {
  description = "LLM model name"
  type        = string
  default     = "gpt-4o-mini"
}

variable "llm_endpoint_url" {
  description = "Optional custom LLM endpoint URL (empty = provider default)"
  type        = string
  default     = ""
}

variable "llm_max_tokens" {
  description = "Max tokens per LLM completion"
  type        = number
  default     = 1024
}

variable "llm_temperature" {
  description = "LLM sampling temperature"
  type        = number
  default     = 0.2
}

variable "llm_timeout" {
  description = "LLM request timeout (Spring duration, e.g. 60s)"
  type        = string
  default     = "60s"
}

variable "llm_api_key" {
  description = "Inline LLM API key (used only while llm_api_key_kv_secret_id is empty)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "llm_api_key_kv_secret_id" {
  description = "Key Vault secret id for the LLM API key (empty = use inline value). Two-phase Class A cutover."
  type        = string
  default     = ""
}

# --- SPARQL / tokens -----------------------------------------------------

variable "sparql_endpoint_url" {
  description = "SPARQL endpoint the service queries for class samples"
  type        = string
  default     = "https://opendata.eselpoint.gov.cz/sparql"
}

variable "tokens_max_allowed_per_day" {
  description = "Daily token budget guard. Tracks the app's own default (lowered 100000 → 1000 on 2026-07-14); raise deliberately, not by drift."
  type        = number
  default     = 1000
}

# --- Auth / environment mode ---------------------------------------------

variable "app_environment" {
  description = "App environment mode: 'development' disables OIDC (all endpoints open); 'production' requires valid Keycloak JWTs."
  type        = string
  default     = "development"
}

variable "oidc_issuer_uri" {
  description = "Keycloak OIDC issuer URI (used only when app_environment = production)"
  type        = string
  default     = ""
}

variable "oidc_jwk_set_uri" {
  description = "Keycloak JWKS URI (used only when app_environment = production). Prefer the internal Keycloak URL to avoid public round-trips."
  type        = string
  default     = ""
}

# --- GHCR pull credentials -----------------------------------------------
# ismd-ai is the only private app repo, so its GHCR package is private too and
# the container app cannot pull it anonymously the way the other (public-repo)
# apps do. GHCR does not support Azure managed identity (ACR-only), so a PAT with
# read:packages is required.
#
# This wiring is INERT while both ghcr_token and ghcr_token_kv_secret_id are
# empty — no registry block is emitted. Leave it empty if the ismd-ai package is
# made public (then this module matches the other apps exactly, registries = []).

variable "ghcr_username" {
  description = "GitHub username/bot account owning the read:packages PAT used to pull the private image"
  type        = string
  default     = ""
}

variable "ghcr_token" {
  description = "Inline GHCR PAT with read:packages (used only while ghcr_token_kv_secret_id is empty). Empty = no registry auth."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ghcr_token_kv_secret_id" {
  description = "Key Vault secret id for the GHCR PAT (empty = use inline value). Empty + empty ghcr_token = anonymous pull (public package)."
  type        = string
  default     = ""
}

# --- Telemetry -----------------------------------------------------------

variable "app_insights_connection_string" {
  description = "Application Insights connection string (inline, used while KV secret id is empty)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "app_insights_kv_secret_id" {
  description = "Key Vault secret id for the App Insights connection string (empty = use inline value)"
  type        = string
  default     = ""
}

variable "enable_app_insights_agent" {
  description = <<-EOT
    Activate the Application Insights Java agent on the AI backend via JAVA_TOOL_OPTIONS
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

variable "workload_profile_name" {
  description = "Workload profile name for the container app (Consumption = null)"
  type        = string
  default     = "Consumption"
}

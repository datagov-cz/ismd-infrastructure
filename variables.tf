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

variable "backend_port" {
  description = "Port the backend Tomcat binds to; must match the running image's Spring server.port. Default 8082 (localhost profile); override per-env in tfvars while an env still runs an 8080-binding image."
  type        = number
  default     = 8082
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

variable "keyvault_operator_object_ids" {
  description = "Entra object ids granted data-plane secret management on the per-env Key Vaults (dev/test), so operators can seed/rotate secret values via CLI. Set via TF_VAR_keyvault_operator_object_ids in the gitignored .env.<env>; never commit personal principal ids. Empty = vaults created with no operator policy."
  type        = list(string)
  default     = []
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
variable "admin_allowed_ips" {
  description = "Operator/admin public IP(s) allowed direct access to the Tool Postgres server. Set via TF_VAR_admin_allowed_ips in .env.<env>. Empty = no direct human access."
  type        = list(string)
  default     = []
}

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

variable "tool_keycloak_idp_hint" {
  description = "Keycloak IdP alias to redirect straight to (e.g. \"caais\"), skipping the Keycloak login page. Empty shows the Keycloak page."
  type        = string
  default     = ""
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

# CAAIS mTLS keystore. The p12 id is normally the auto-exposed secret of the CAAIS
# KV Certificate object in ismd-kv-<env> (key generated in-vault, CAAIS-signed cert
# merged in), which yields the PFX in base64. Empty keeps the whole keystore wiring
# inert.
#
# A real password is REQUIRED: KV exports the PFX unprotected, but Keycloak cannot
# use an empty password (Quarkus reads an empty env var as unset -> null ->
# UnrecoverableKeyException). The init container re-wraps the PFX with it and
# Keycloak opens it with the same one.
variable "tool_caais_p12_kv_secret_id" {
  description = "Versionless KV secret id yielding the base64 CAAIS client PKCS12 (the CAAIS certificate's auto-exposed secret). Empty = CAAIS mTLS keystore not wired."
  type        = string
  default     = ""
}

variable "tool_caais_keystore_password_kv_secret_id" {
  description = "Versionless KV secret id for the password the CAAIS p12 is re-wrapped with. Required (alongside the p12 id) for the keystore to render."
  type        = string
  default     = ""
}


variable "tool_nkd_sparql_endpoint" {
  description = "NKD SPARQL endpoint the tool backend queries (NKD_SPARQL_ENDPOINT). One target per environment: pod-develop (DEV), pod-test (TEST), data.gov.cz (PROD). Empty falls back to the image default. Keep the path segment percent-encoded (slovn%C3%ADky). Set via environments/<env>/terraform.tfvars."
  type        = string
  default     = ""
}

variable "tool_app_insights_kv_secret_id" {
  description = "Class A pilot: versionless KV secret id for the tool backend's app-insights connection string. Empty keeps the inline value; set (e.g. https://ismd-kv-<env>.vault.azure.net/secrets/app-insights-connection-string) to pull from Key Vault. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_postgres_password_kv_secret_id" {
  description = "Class A: versionless KV secret id for the tool backend's postgres password. Empty = inline value. Set via .env.<env>."
  type        = string
  default     = ""
}

# Per-app DB user separation (Phase 2 cutover). Empty = admin login (no-op).
# Flip per env via .env.<env>/tfvars once db/user-separation Phase 1 is applied.
variable "tool_backend_db_user" {
  description = "Dedicated Postgres LOGIN role for the tool backend (e.g. ismd_tool_app). Empty = admin login. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_keycloak_db_user" {
  description = "Dedicated Postgres LOGIN role for Keycloak (e.g. ismd_keycloak_app). Empty = admin login. Cut over last. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_keycloak_client_secret_kv_secret_id" {
  description = "Class A: versionless KV secret id for the tool backend's keycloak client secret. Empty = inline value. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_frontend_app_insights_kv_secret_id" {
  description = "Class A: KV secret id for the tool frontend's app-insights connection string. Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_frontend_nextauth_secret_kv_secret_id" {
  description = "Class A: KV secret id for the tool frontend's NextAuth secret. Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_frontend_keycloak_client_secret_kv_secret_id" {
  description = "Class A: KV secret id for the tool frontend's keycloak client secret. Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_frontend_site_preview_secret_kv_secret_id" {
  description = "Class A: KV secret id for the tool frontend's site-preview secret. Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "validator_backend_app_insights_kv_secret_id" {
  description = "Class A: KV secret id for the validator backend's app-insights connection string. Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "validator_frontend_app_insights_kv_secret_id" {
  description = "Class A: KV secret id for the validator frontend's app-insights connection string. Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "validator_frontend_site_preview_secret_kv_secret_id" {
  description = "Class A: KV secret id for the validator frontend's site-preview secret. Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_keycloak_admin_password_kv_secret_id" {
  description = "Class A: KV secret id for the keycloak admin password. Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_keycloak_db_password_kv_secret_id" {
  description = "Class A: KV secret id for the keycloak DB password (same postgres-password secret when deploy_postgres). Empty = inline. Set via .env.<env>."
  type        = string
  default     = ""
}

variable "tool_keycloak_app_insights_kv_secret_id" {
  description = "Class A: KV secret id for the keycloak container's app-insights connection string. Empty = inline. Set via .env.<env>."
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

# --- AI apps (ismd-ai) — DEV only for now --------------------------------

variable "deploy_ai_apps" {
  description = "Whether to deploy the AI apps (ismd-ai). Requires deploy_tool_apps. DEV only for now."
  type        = bool
  default     = false
}

variable "ai_resource_group_name" {
  description = "Resource group for the AI container app"
  type        = string
  default     = "ismd-ai-dev"
}

variable "ai_backend_app_name" {
  description = "Base name of the AI backend container app"
  type        = string
  default     = "ismd-ai"
}

variable "ai_backend_image" {
  description = "Base container image URL for the AI backend (without tag)"
  type        = string
  default     = "ghcr.io/datagov-cz/ismd-ai-dev"
}

variable "ai_backend_image_tag" {
  description = "Tag for the AI backend container image"
  type        = string
  default     = "latest"
}

variable "ai_app_environment" {
  description = "AI app environment mode: 'development' disables OIDC; 'production' requires Keycloak JWTs."
  type        = string
  default     = "development"
}

variable "ai_llm_enabled" {
  description = "Enable LLM calls in the AI service. Keep false until the API key secret is seeded."
  type        = bool
  default     = false
}

variable "ai_llm_provider" {
  description = "LLM provider: OPENAI | AZURE_OPENAI | OPENAI_COMPATIBLE | ANTHROPIC | GOOGLE | MISTRAL | COHERE | OLLAMA"
  type        = string
  default     = "OPENAI"
}

variable "ai_llm_endpoint_url" {
  description = "LLM endpoint URL; selects which AI host this env targets. Empty = provider default. {model} is substituted with ai_llm_model."
  type        = string
  default     = ""
}

variable "ai_llm_model" {
  description = "LLM model name. For AZURE_OPENAI this is the *deployment* name (substituted into {model} in the endpoint URL), e.g. gpt-4o-mini-dev."
  type        = string
  default     = "gpt-4o-mini"
}

variable "ai_llm_api_key" {
  description = "Inline LLM API key (used only while ai_llm_api_key_kv_secret_id is empty)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ai_llm_api_key_kv_secret_id" {
  description = "Key Vault secret id for the LLM API key (empty = inline value)"
  type        = string
  default     = ""
}

variable "ai_app_insights_kv_secret_id" {
  description = "Key Vault secret id for the AI App Insights connection string (empty = inline value)"
  type        = string
  default     = ""
}

variable "ai_postgres_password_kv_secret_id" {
  description = "Key Vault secret id for the AI app's Postgres password (empty = inline value). Class A two-phase: empty on first apply, then set to flip to the KV reference."
  type        = string
  default     = ""
}

# Per-app DB user separation (Phase 2 cutover) for ismd-ai. Defaults to the admin
# login so nothing changes until flipped. Set to "ismd_ai_app" once 03-ai.sql is
# applied and the AI password secret holds that role's password. DEV only (ismd-ai
# is DEV-only today).
variable "ai_db_user" {
  description = "Postgres LOGIN role for the AI app. Defaults to the admin login; set to 'ismd_ai_app' after db/user-separation Phase 1. Set via .env.dev."
  type        = string
  default     = "ismdadmin"
}

# GHCR pull auth — ismd-ai is the only private app repo, so its package is private
# and needs a read:packages PAT. All empty = anonymous pull (public package).

variable "ai_ghcr_username" {
  description = "GitHub username/bot account owning the read:packages PAT"
  type        = string
  default     = ""
}

variable "ai_ghcr_token" {
  description = "Inline GHCR PAT with read:packages (used only while ai_ghcr_token_kv_secret_id is empty)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ai_ghcr_token_kv_secret_id" {
  description = "Key Vault secret id for the GHCR PAT (empty = inline value)"
  type        = string
  default     = ""
}

variable "deploy_monitoring" {
  description = "Whether to provision the monitoring module (Action Groups + Logic App + Teams notifier). Default false during Phase A rollout; flip true per env once Logic App connector is OAuth-authorized."
  type        = bool
  default     = false
}

variable "paging_email_recipients" {
  description = "Email addresses (or one mail-enabled group address) that receive paging-tier alerts. Empty list → no paging action group is created. Use hardcoded individuals until the Entra mail-enabled group exists; then swap to a single group address."
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

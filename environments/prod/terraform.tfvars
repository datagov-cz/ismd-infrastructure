# Prod environment configuration
# Most values come from variable defaults in the root module / environments/prod/variables.tf
# and from TF_VAR_* env vars in CI / .env.prod for secrets.

location                      = "germanywestcentral"
shared_resource_group_name    = "ismd-shared-prod"
validator_resource_group_name = "ismd-validator-prod"
tool_resource_group_name      = "ismd-tool-prod"

# Validator container images (currently mirroring test image so the gated
# coming-soon page is what visitors see)
frontend_image     = "ghcr.io/datagov-cz/ismd-validator-frontend"
frontend_image_tag = "1.0.3"
backend_image      = "ghcr.io/datagov-cz/ismd-validator-backend"
backend_image_tag  = "1.0.1"
# TEMPORARY: this image binds 8080. Delete this override (defaults to 8082) when
# PROD is redeployed with an 8082-binding backend image.
backend_port = 8080

# Tool container images — not deployed in PROD yet, but values must be present
# because the variables are required at the root module. Flip deploy_tool_apps
# to true once tool is ready for PROD.
tool_frontend_image     = "ghcr.io/datagov-cz/ismd-tool-frontend"
tool_frontend_image_tag = "latest"
tool_backend_image      = "ghcr.io/datagov-cz/ismd-tool-backend"
tool_backend_image_tag  = "latest"

# App Gateway hostname for PROD (slovník.gov.cz, IDN-encoded)
app_gateway_hostname   = "xn--slovnk-7va.gov.cz"
tool_keycloak_hostname = "xn--slovnk-7va.gov.cz"

# App names
frontend_app_name = "ismd-validator-frontend"
backend_app_name  = "ismd-validator-backend"

# Tool apps not deployed yet on PROD
deploy_tool_apps = false

# Frontend gating — PROD stays blocked until coordinated public launch
validator_site_status = "coming_soon"
tool_site_status      = "coming_soon"

# Validator runs v1.0.3 (cherry-pick: gate only, no BFF refactor) — keep legacy
# wiring (NEXT_PUBLIC_BE_URL + externally exposed backend with AppGW IP allowlist)
# until a BFF-capable image is released.
validator_use_bff = false

# Monitoring — paging_email_recipients is fed from .env.prod (TF_VAR_paging_email_recipients).
deploy_monitoring = true

# Key Vault secret references (Class A — non-secret pointers; the secret VALUES live
# in ismd-kv-prod). PROD runs the validator only (deploy_tool_apps = false), so only the
# validator app-insights references are set; the tool/keycloak pointers get added here
# when the tool ships to PROD. Safe to commit.
validator_backend_app_insights_kv_secret_id  = "https://ismd-kv-prod.vault.azure.net/secrets/app-insights-connection-string"
validator_frontend_app_insights_kv_secret_id = "https://ismd-kv-prod.vault.azure.net/secrets/app-insights-connection-string"

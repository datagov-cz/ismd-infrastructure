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
tool_frontend_image_tag = "1.0.4" # pinned, not "latest": the NIA login button needs >= 1.0.4
tool_backend_image      = "ghcr.io/datagov-cz/ismd-tool-backend"
tool_backend_image_tag  = "latest"

# NKD SPARQL endpoint the tool backend queries (NKD_SPARQL_ENDPOINT).
tool_nkd_sparql_endpoint = "https://data.gov.cz/slovn%C3%ADky/sparql"

# NKOD catalogue SPARQL endpoint the tool backend queries (NKOD_SPARQL_ENDPOINT).
tool_nkod_sparql_endpoint = "https://data.gov.cz/sparql"

# App Gateway hostname for PROD (slovník.gov.cz, IDN-encoded)
app_gateway_hostname   = "xn--slovnk-7va.gov.cz"
tool_keycloak_hostname = "xn--slovnk-7va.gov.cz"

# Custom Keycloak image (nia-oidc broker), same build as TEST. Terraform ignores the image
# after creation (ignore_changes), so this only takes effect when the prod Keycloak is
# CREATED. Without it, prod starts on stock quay.io 24.0.2 and nia_provider_id = "nia-oidc"
# in keycloak-config/prod.tfvars fails.
tool_keycloak_image     = "ghcr.io/datagov-cz/ismd-tool-keycloak"
tool_keycloak_image_tag = "24.0.2-bdb4e0d"

# Level of Assurance requested per login. Injected as KEYCLOAK_ACR_VALUES; same as TEST.
tool_keycloak_acr_values = "loalow"

# NIA login button (KEYCLOAK_NIA_ENABLED, frontend >= 1.0.4). Moves with enable_nia in
# keycloak-config/prod.tfvars. The id_token decryption key is NOT wired here (no
# tool_nia_p12_kv_secret_id): on Keycloak 24 it is imported into the realm by hand after
# the prod Keycloak is created. It moves to Terraform with the Keycloak 26 upgrade (vault
# references keep the keystore password out of state; 24 has no vault lookup for it).
tool_keycloak_nia_enabled = true

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

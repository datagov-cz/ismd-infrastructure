# Dev environment configuration

location                      = "germanywestcentral"
shared_resource_group_name    = "ismd-shared-dev"
validator_resource_group_name = "ismd-validator-dev"
tool_resource_group_name      = "ismd-tool-dev"

# Validator container images
frontend_image     = "ghcr.io/datagov-cz/ismd-validator-frontend-dev"
frontend_image_tag = "latest"
backend_image      = "ghcr.io/datagov-cz/ismd-validator-backend-dev"
backend_image_tag  = "latest"

# Tool container images
tool_frontend_image     = "ghcr.io/datagov-cz/ismd-tool-frontend-dev"
tool_frontend_image_tag = "0.1.0-6cb62d3"
tool_backend_image      = "ghcr.io/datagov-cz/ismd-tool-backend-dev"
tool_backend_image_tag  = "0.0.1-a9a5d5b"

# NKD SPARQL endpoint the tool backend queries (NKD_SPARQL_ENDPOINT).
tool_nkd_sparql_endpoint = "https://pod-develop.dia.gov.cz/slovn%C3%ADky/sparql"

# App Gateway - DEV hostname (HTTPS)
app_gateway_hostname   = "oha03.dia.gov.cz"
tool_keycloak_hostname = "oha03.dia.gov.cz"

# Send the frontend's authorization request straight to the CAAIS IdP, skipping the
# Keycloak login page. Injected as KEYCLOAK_IDP_HINT; auth.ts turns it into
# kc_idp_hint. Empty (the default) shows the Keycloak page with local accounts.
#
# OFF for now (2026-08-12): it works — verified end to end on dev — but skipping the
# Keycloak page leaves no way in without a CAAIS account, and dev has none. Re-enable
# once CAAIS logins are available here, or when a local-account escape hatch exists.
# tool_keycloak_idp_hint = "caais"

deploy_tool_apps = true

# AI apps (ismd-ai) — internal-only Spring Boot service; DB lives on the tool's
# Postgres server. LLM stays disabled until the API key secret is seeded (then set
# ai_llm_enabled = true and provide ai_llm_api_key or ai_llm_api_key_kv_secret_id).
# Temporarily off: the ai_apps module can't create yet — its ai_kv identity has no
# Key Vault access policy (no principal_id output, no policy in keyvault.tf), and it
# borrows tool's postgres_password_kv_secret_id, so it demands a KV reference on
# first create before any grant exists. Needs the Class A phase-1/phase-2 treatment
# (inline values first, then flip to KV refs). Flip back once that's fixed.
deploy_ai_apps = true

# Frontend gating — DEV is open for the engineering team
validator_site_status = "live"
tool_site_status      = "live"

# DEV uses -dev images built from the dev branch which has the BFF refactor.
validator_use_bff = true

# paging_email_recipients is fed from .env.dev (TF_VAR_paging_email_recipients).
deploy_monitoring = true

# Key Vault secret references (Class A — non-secret pointers; the secret VALUES live
# in ismd-kv-dev). A URL here flips that app's secret from its inline value to a
# key_vault_secret_id reference resolved by the app's managed identity at runtime.
# Safe to commit (vault + secret name only, no secret material).
tool_app_insights_kv_secret_id                    = "https://ismd-kv-dev.vault.azure.net/secrets/app-insights-connection-string"
tool_backend_db_user                              = "ismd_tool_app"
tool_postgres_password_kv_secret_id               = "https://ismd-kv-dev.vault.azure.net/secrets/postgres-password-tool"
tool_keycloak_client_secret_kv_secret_id          = "https://ismd-kv-dev.vault.azure.net/secrets/keycloak-client-secret"
tool_frontend_app_insights_kv_secret_id           = "https://ismd-kv-dev.vault.azure.net/secrets/app-insights-connection-string"
tool_frontend_nextauth_secret_kv_secret_id        = "https://ismd-kv-dev.vault.azure.net/secrets/nextauth-secret"
tool_frontend_keycloak_client_secret_kv_secret_id = "https://ismd-kv-dev.vault.azure.net/secrets/keycloak-client-secret"
tool_keycloak_admin_password_kv_secret_id         = "https://ismd-kv-dev.vault.azure.net/secrets/keycloak-admin-password"
tool_keycloak_db_user                             = "ismd_keycloak_app"
tool_keycloak_db_password_kv_secret_id            = "https://ismd-kv-dev.vault.azure.net/secrets/postgres-password-keycloak"

# AI app — same Class A cutover. It reuses the tool's postgres-password secret (same
# server + admin login). These stayed empty for the first apply only, because the
# container app validates key_vault_secret_id at provision time and the ai_kv grant
# in keyvault.tf could not be ordered ahead of it in the same apply (the grant reads
# the identity's principal id out of the module, so a depends_on would cycle). The
# grant exists now, so both are references like every other app.
ai_app_insights_kv_secret_id = "https://ismd-kv-dev.vault.azure.net/secrets/app-insights-connection-string"
# User separation cutover: ismd-ai now logs in as its own role with its own secret.
ai_db_user                                   = "ismd_ai_app"
ai_postgres_password_kv_secret_id            = "https://ismd-kv-dev.vault.azure.net/secrets/postgres-password-ai"
tool_keycloak_app_insights_kv_secret_id      = "https://ismd-kv-dev.vault.azure.net/secrets/app-insights-connection-string"
validator_backend_app_insights_kv_secret_id  = "https://ismd-kv-dev.vault.azure.net/secrets/app-insights-connection-string"
validator_frontend_app_insights_kv_secret_id = "https://ismd-kv-dev.vault.azure.net/secrets/app-insights-connection-string"

# CAAIS mTLS. The p12 id is the auto-exposed secret of the CAAIS KV Certificate
# object (key generated in-vault, CAAIS-signed cert merged in) — it yields the PFX
# in base64, which the keycloak init container decodes.
# KV exports that PFX unprotected, but Keycloak can't use an empty password (Quarkus
# reads an empty env var as unset -> null -> UnrecoverableKeyException), so the init
# container re-wraps it with caais-keystore-pw and Keycloak opens it with the same.
# caais_client_id is the AIS shortcut ("zkratka") in CAAIS — an identifier, not a secret.
tool_caais_client_id                      = "ISMD_dev"
tool_caais_p12_kv_secret_id               = "https://ismd-kv-dev.vault.azure.net/secrets/ismd-dev-caais-test-cert"
tool_caais_keystore_password_kv_secret_id = "https://ismd-kv-dev.vault.azure.net/secrets/caais-keystore-pw"

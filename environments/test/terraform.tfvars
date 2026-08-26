# Test environment configuration

location                      = "germanywestcentral"
shared_resource_group_name    = "ismd-shared-test"
validator_resource_group_name = "ismd-validator-test"
tool_resource_group_name      = "ismd-tool-test"

# Validator container images
frontend_image     = "ghcr.io/datagov-cz/ismd-validator-frontend"
frontend_image_tag = "1.0.2"
backend_image      = "ghcr.io/datagov-cz/ismd-validator-backend"
backend_image_tag  = "1.0.1"
# TEMPORARY: this image binds 8080. Delete this override (defaults to 8082) when
# TEST is redeployed with an 8082-binding backend image.
backend_port = 8080

# Tool container images (using dev images for TEST)
tool_frontend_image     = "ghcr.io/datagov-cz/ismd-tool-frontend-dev"
tool_frontend_image_tag = "latest"
tool_backend_image      = "ghcr.io/datagov-cz/ismd-tool-backend-dev"
tool_backend_image_tag  = "latest"

# NKD SPARQL endpoint the tool backend queries (NKD_SPARQL_ENDPOINT).
tool_nkd_sparql_endpoint = "https://pod-test.dia.gov.cz/slovn%C3%ADky/sparql"

# App Gateway hostname for TEST
# NOTE: slovnik-test.gov.cz is NOT this environment — it 302s to
# https://datagov-cz.github.io/ssp/. The .dia form below is the real test entry point.
# Its certificate (on DIA's reverse proxy) expired 2026-08-05 12:40 UTC; renewing it is
# a DIA task, not a change here.
app_gateway_hostname   = "xn--slovnk-test-scb.dia.gov.cz"
tool_keycloak_hostname = "xn--slovnk-test-scb.dia.gov.cz"

# Send the frontend's authorization request straight to the CAAIS IdP, skipping the
# Keycloak login page. Injected as KEYCLOAK_IDP_HINT; auth.ts turns it into
# kc_idp_hint. Empty (the default) shows the Keycloak page with local accounts.
tool_keycloak_idp_hint = "caais"

# App names
frontend_app_name = "ismd-validator-frontend"
backend_app_name  = "ismd-validator-backend"

deploy_tool_apps = true

# Frontend gating
# - validator: live
# - tool: coming_soon (still WIP)
validator_site_status = "live"
tool_site_status      = "live"

# Validator runs v1.0.3 (cherry-pick: gate only, no BFF refactor) — keep legacy
# wiring (NEXT_PUBLIC_BE_URL + externally exposed backend with AppGW IP allowlist)
# until a BFF-capable image is released.
validator_use_bff = false

# Monitoring — paging_email_recipients is fed from .env.test (TF_VAR_paging_email_recipients).
deploy_monitoring = true

# Key Vault secret references (Class A — non-secret pointers; the secret VALUES live
# in ismd-kv-test). A URL here flips that app's secret from its inline value to a
# key_vault_secret_id reference resolved by the app's managed identity at runtime.
# Safe to commit (vault + secret name only, no secret material).
tool_app_insights_kv_secret_id                    = "https://ismd-kv-test.vault.azure.net/secrets/app-insights-connection-string"
tool_backend_db_user                              = "ismd_tool_app"
tool_postgres_password_kv_secret_id               = "https://ismd-kv-test.vault.azure.net/secrets/postgres-password-tool"
tool_keycloak_client_secret_kv_secret_id          = "https://ismd-kv-test.vault.azure.net/secrets/keycloak-client-secret"
tool_frontend_app_insights_kv_secret_id           = "https://ismd-kv-test.vault.azure.net/secrets/app-insights-connection-string"
tool_frontend_nextauth_secret_kv_secret_id        = "https://ismd-kv-test.vault.azure.net/secrets/nextauth-secret"
tool_frontend_keycloak_client_secret_kv_secret_id = "https://ismd-kv-test.vault.azure.net/secrets/keycloak-client-secret"
tool_keycloak_admin_password_kv_secret_id         = "https://ismd-kv-test.vault.azure.net/secrets/keycloak-admin-password"
tool_keycloak_db_user                             = "ismd_keycloak_app"
tool_keycloak_db_password_kv_secret_id            = "https://ismd-kv-test.vault.azure.net/secrets/postgres-password-keycloak"
tool_keycloak_app_insights_kv_secret_id           = "https://ismd-kv-test.vault.azure.net/secrets/app-insights-connection-string"
validator_backend_app_insights_kv_secret_id       = "https://ismd-kv-test.vault.azure.net/secrets/app-insights-connection-string"
validator_frontend_app_insights_kv_secret_id      = "https://ismd-kv-test.vault.azure.net/secrets/app-insights-connection-string"

# CAAIS mTLS. The p12 id is the auto-exposed secret of the CAAIS KV Certificate
# object (key generated in-vault, CAAIS-signed cert merged in) — it yields the PFX
# in base64, which the keycloak init container decodes.
# KV exports that PFX unprotected, but Keycloak can't use an empty password (Quarkus
# reads an empty env var as unset -> null -> UnrecoverableKeyException), so the init
# container re-wraps it with caais-keystore-pw and Keycloak opens it with the same.
# caais_client_id is the AIS shortcut ("zkratka") in CAAIS — an identifier, not a
# secret. CAAIS calls our TEST environment "stage", hence ISMD_stage.
# TEST points at PRODUCTION CAAIS (2026-08-12) — see keycloak-config/test.tfvars for
# why, and for the revert path. The cert below is the PRODUCTION client cert copied
# from ismd-kv-prod; the stage cert (ismd-test-caais-test-cert) is still in the vault.
# The PRODUCTION AIS shortcut, same value as caais_client_id in keycloak-config.
tool_caais_client_id                      = "ISMD"
tool_caais_p12_kv_secret_id               = "https://ismd-kv-test.vault.azure.net/secrets/ismd-test-caais-prod-cert"
tool_caais_keystore_password_kv_secret_id = "https://ismd-kv-test.vault.azure.net/secrets/caais-keystore-pw"

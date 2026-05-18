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

# Tool container images (using dev images for TEST)
tool_frontend_image     = "ghcr.io/datagov-cz/ismd-tool-frontend-dev"
tool_frontend_image_tag = "latest"
tool_backend_image      = "ghcr.io/datagov-cz/ismd-tool-backend-dev"
tool_backend_image_tag  = "latest"

# App Gateway hostname for TEST
app_gateway_hostname   = "xn--slovnk-test-scb.dia.gov.cz"
tool_keycloak_hostname = "xn--slovnk-test-scb.dia.gov.cz"

# App names
frontend_app_name = "ismd-validator-frontend"
backend_app_name  = "ismd-validator-backend"

deploy_tool_apps = true

# Frontend gating
# - validator: live
# - tool: coming_soon (still WIP)
validator_site_status = "live"
tool_site_status      = "coming_soon"

# Validator runs v1.0.3 (cherry-pick: gate only, no BFF refactor) — keep legacy
# wiring (NEXT_PUBLIC_BE_URL + externally exposed backend with AppGW IP allowlist)
# until a BFF-capable image is released.
validator_use_bff = false
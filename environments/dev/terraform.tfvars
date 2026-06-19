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

# App Gateway - DEV hostname (HTTPS)
app_gateway_hostname   = "oha03.dia.gov.cz"
tool_keycloak_hostname = "oha03.dia.gov.cz"

deploy_tool_apps = true

# Frontend gating — DEV is open for the engineering team
validator_site_status = "live"
tool_site_status      = "live"

# DEV uses -dev images built from the dev branch which has the BFF refactor.
validator_use_bff = true

# paging_email_recipients is fed from .env.dev (TF_VAR_paging_email_recipients).
deploy_monitoring = true

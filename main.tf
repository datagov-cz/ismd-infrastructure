terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "7d72da57-155c-4d56-883e-0e68a747e9e1" # InformacniSystemModelovaniDat

  features {
    # Allow the provider to delete resources that exist in the state but not in the configuration
    # This is useful for cleaning up resources that are no longer needed
    # but be careful with this in production environments
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Read outputs from the shared-global Terraform state (App Gateway, global VNet, etc.)
data "terraform_remote_state" "shared_global" {
  backend = "azurerm"
  config = {
    resource_group_name  = "ismd-shared-tfstate"
    storage_account_name = "ismdtfstate"
    container_name       = "tfstate"
    key                  = "ismd-shared-global.tfstate"
  }
}

# We'll use the environment module from the dev environment instead
# This avoids circular dependencies between modules

### Revert to static modules; Terraform does not allow dynamic expressions for module source

# Dev environment
module "dev" {
  count  = terraform.workspace == "dev" ? 1 : 0
  source = "./environments/dev"

  # Common variables
  environment        = "dev"
  location           = var.location
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag
  backend_port       = var.backend_port

  # App names
  frontend_app_name = var.frontend_app_name
  backend_app_name  = var.backend_app_name

  # CORS
  additional_cors_origins = var.additional_cors_origins
  app_gateway_hostname    = var.app_gateway_hostname

  # Resource groups
  shared_resource_group_name    = var.shared_resource_group_name
  validator_resource_group_name = var.validator_resource_group_name
  tool_resource_group_name      = var.tool_resource_group_name

  # Per-env Key Vault operator grants (seed/rotate secret values via CLI)
  keyvault_operator_object_ids = var.keyvault_operator_object_ids

  # Tool Apps
  tool_frontend_image     = var.tool_frontend_image
  tool_frontend_image_tag = var.tool_frontend_image_tag
  tool_backend_image      = var.tool_backend_image
  tool_backend_image_tag  = var.tool_backend_image_tag
  tool_frontend_app_name  = var.tool_frontend_app_name
  tool_backend_app_name   = var.tool_backend_app_name

  # NKD SPARQL endpoint (NKD_SPARQL_ENDPOINT) — per-environment target.
  tool_nkd_sparql_endpoint = var.tool_nkd_sparql_endpoint

  # Tool Database & Fuseki
  admin_allowed_ips            = var.admin_allowed_ips
  tool_postgres_url            = var.tool_postgres_url
  tool_postgres_user           = var.tool_postgres_user
  tool_postgres_password       = var.tool_postgres_password
  tool_fuseki_url              = var.tool_fuseki_url
  tool_nextauth_secret         = var.tool_nextauth_secret
  tool_base_path               = var.tool_base_path
  tool_deploy_keycloak         = var.tool_deploy_keycloak
  tool_enable_caais            = var.tool_enable_caais
  tool_keycloak_image          = var.tool_keycloak_image
  tool_keycloak_image_tag      = var.tool_keycloak_image_tag
  tool_keycloak_app_name       = var.tool_keycloak_app_name
  tool_keycloak_admin_user     = var.tool_keycloak_admin_user
  tool_keycloak_admin_password = var.tool_keycloak_admin_password
  tool_keycloak_hostname       = var.tool_keycloak_hostname
  tool_keycloak_realm          = var.tool_keycloak_realm
  tool_keycloak_issuer_uri     = var.tool_keycloak_issuer_uri
  tool_keycloak_client_id      = var.tool_keycloak_client_id
  tool_keycloak_idp_hint       = var.tool_keycloak_idp_hint
  tool_keycloak_client_secret  = var.tool_keycloak_client_secret
  tool_caais_client_id         = var.tool_caais_client_id
  tool_caais_p12_kv_secret_id  = var.tool_caais_p12_kv_secret_id

  tool_caais_keystore_password_kv_secret_id = var.tool_caais_keystore_password_kv_secret_id

  tool_app_insights_kv_secret_id           = var.tool_app_insights_kv_secret_id
  tool_postgres_password_kv_secret_id      = var.tool_postgres_password_kv_secret_id
  tool_keycloak_client_secret_kv_secret_id = var.tool_keycloak_client_secret_kv_secret_id

  tool_frontend_app_insights_kv_secret_id           = var.tool_frontend_app_insights_kv_secret_id
  tool_frontend_nextauth_secret_kv_secret_id        = var.tool_frontend_nextauth_secret_kv_secret_id
  tool_frontend_keycloak_client_secret_kv_secret_id = var.tool_frontend_keycloak_client_secret_kv_secret_id
  tool_frontend_site_preview_secret_kv_secret_id    = var.tool_frontend_site_preview_secret_kv_secret_id

  tool_keycloak_admin_password_kv_secret_id = var.tool_keycloak_admin_password_kv_secret_id
  tool_keycloak_db_password_kv_secret_id    = var.tool_keycloak_db_password_kv_secret_id
  tool_keycloak_app_insights_kv_secret_id   = var.tool_keycloak_app_insights_kv_secret_id

  # Toggle for Tool apps deployment
  deploy_tool_apps = var.deploy_tool_apps

  # AI apps (ismd-ai) — DEV only for now
  deploy_ai_apps                    = var.deploy_ai_apps
  ai_resource_group_name            = var.ai_resource_group_name
  ai_backend_app_name               = var.ai_backend_app_name
  ai_backend_image                  = var.ai_backend_image
  ai_backend_image_tag              = var.ai_backend_image_tag
  ai_app_environment                = var.ai_app_environment
  ai_llm_enabled                    = var.ai_llm_enabled
  ai_llm_provider                   = var.ai_llm_provider
  ai_llm_endpoint_url               = var.ai_llm_endpoint_url
  ai_llm_model                      = var.ai_llm_model
  ai_llm_api_key                    = var.ai_llm_api_key
  ai_llm_api_key_kv_secret_id       = var.ai_llm_api_key_kv_secret_id
  ai_app_insights_kv_secret_id      = var.ai_app_insights_kv_secret_id
  ai_postgres_password_kv_secret_id = var.ai_postgres_password_kv_secret_id
  ai_ghcr_username                  = var.ai_ghcr_username

  # Per-app DB user separation (Phase 2, DEV only). Empty tool_* = admin login;
  # ai_db_user defaults to admin. Flip via .env.dev after db/user-separation Phase 1.
  tool_backend_db_user       = var.tool_backend_db_user
  tool_keycloak_db_user      = var.tool_keycloak_db_user
  ai_db_user                 = var.ai_db_user
  ai_ghcr_token              = var.ai_ghcr_token
  ai_ghcr_token_kv_secret_id = var.ai_ghcr_token_kv_secret_id

  # Toggle for monitoring module deployment
  deploy_monitoring       = var.deploy_monitoring
  paging_email_recipients = var.paging_email_recipients
  alert_card_language     = var.alert_card_language
  teams_group_id          = var.teams_group_id
  teams_channel_id        = var.teams_channel_id

  # Frontend gating
  validator_site_status         = var.validator_site_status
  tool_site_status              = var.tool_site_status
  validator_site_preview_secret = var.validator_site_preview_secret
  tool_site_preview_secret      = var.tool_site_preview_secret

  # Validator BFF mode (false = legacy public backend + NEXT_PUBLIC_BE_URL)
  validator_use_bff = var.validator_use_bff

  # Validator Class A: KV references (empty = inline value)
  validator_backend_app_insights_kv_secret_id         = var.validator_backend_app_insights_kv_secret_id
  validator_frontend_app_insights_kv_secret_id        = var.validator_frontend_app_insights_kv_secret_id
  validator_frontend_site_preview_secret_kv_secret_id = var.validator_frontend_site_preview_secret_kv_secret_id

  # Remote state (guarded for initial plan)
  shared_global_vnet_id             = try(data.terraform_remote_state.shared_global.outputs.vnet_id, "")
  shared_global_vnet_name           = try(data.terraform_remote_state.shared_global.outputs.vnet_name, "")
  shared_global_resource_group_name = try(data.terraform_remote_state.shared_global.outputs.resource_group_name, "")
  app_gateway_public_ip_address     = try(data.terraform_remote_state.shared_global.outputs.app_gateway_public_ip_address, "")
  shared_global_app_gateway_id      = try(data.terraform_remote_state.shared_global.outputs.app_gateway_id, "")
}

# Test environment
module "test" {
  count  = terraform.workspace == "test" ? 1 : 0
  source = "./environments/test"

  # Per-app DB user separation (Phase 2). Empty = admin login until test tfvars
  # flips it. See infrastructure/db/user-separation/README.md.
  tool_backend_db_user  = var.tool_backend_db_user
  tool_keycloak_db_user = var.tool_keycloak_db_user

  # Common variables
  environment = "test"
  location    = var.location

  # Per-env Key Vault operator grants (seed/rotate secret values via CLI)
  keyvault_operator_object_ids = var.keyvault_operator_object_ids

  # Validator Apps
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag
  backend_port       = var.backend_port
  frontend_app_name  = var.frontend_app_name
  backend_app_name   = var.backend_app_name

  # Resource groups
  shared_resource_group_name    = var.shared_resource_group_name
  validator_resource_group_name = var.validator_resource_group_name
  tool_resource_group_name      = var.tool_resource_group_name

  # Tool Apps
  tool_frontend_image     = var.tool_frontend_image
  tool_frontend_image_tag = var.tool_frontend_image_tag
  tool_backend_image      = var.tool_backend_image
  tool_backend_image_tag  = var.tool_backend_image_tag
  tool_frontend_app_name  = var.tool_frontend_app_name
  tool_backend_app_name   = var.tool_backend_app_name

  # NKD SPARQL endpoint (NKD_SPARQL_ENDPOINT) — per-environment target.
  tool_nkd_sparql_endpoint = var.tool_nkd_sparql_endpoint

  # Tool Database & Fuseki
  admin_allowed_ips            = var.admin_allowed_ips
  tool_postgres_url            = var.tool_postgres_url
  tool_postgres_user           = var.tool_postgres_user
  tool_postgres_password       = var.tool_postgres_password
  tool_fuseki_url              = var.tool_fuseki_url
  tool_nextauth_secret         = var.tool_nextauth_secret
  tool_base_path               = var.tool_base_path
  tool_deploy_keycloak         = var.tool_deploy_keycloak
  tool_enable_caais            = var.tool_enable_caais
  tool_keycloak_image          = var.tool_keycloak_image
  tool_keycloak_image_tag      = var.tool_keycloak_image_tag
  tool_keycloak_app_name       = var.tool_keycloak_app_name
  tool_keycloak_admin_user     = var.tool_keycloak_admin_user
  tool_keycloak_admin_password = var.tool_keycloak_admin_password
  tool_keycloak_hostname       = var.tool_keycloak_hostname
  tool_keycloak_realm          = var.tool_keycloak_realm
  tool_keycloak_issuer_uri     = var.tool_keycloak_issuer_uri
  tool_keycloak_client_id      = var.tool_keycloak_client_id
  tool_keycloak_idp_hint       = var.tool_keycloak_idp_hint
  tool_keycloak_client_secret  = var.tool_keycloak_client_secret
  tool_caais_client_id         = var.tool_caais_client_id
  tool_caais_p12_kv_secret_id  = var.tool_caais_p12_kv_secret_id

  tool_caais_keystore_password_kv_secret_id = var.tool_caais_keystore_password_kv_secret_id

  tool_app_insights_kv_secret_id           = var.tool_app_insights_kv_secret_id
  tool_postgres_password_kv_secret_id      = var.tool_postgres_password_kv_secret_id
  tool_keycloak_client_secret_kv_secret_id = var.tool_keycloak_client_secret_kv_secret_id

  tool_frontend_app_insights_kv_secret_id           = var.tool_frontend_app_insights_kv_secret_id
  tool_frontend_nextauth_secret_kv_secret_id        = var.tool_frontend_nextauth_secret_kv_secret_id
  tool_frontend_keycloak_client_secret_kv_secret_id = var.tool_frontend_keycloak_client_secret_kv_secret_id
  tool_frontend_site_preview_secret_kv_secret_id    = var.tool_frontend_site_preview_secret_kv_secret_id

  tool_keycloak_admin_password_kv_secret_id = var.tool_keycloak_admin_password_kv_secret_id
  tool_keycloak_db_password_kv_secret_id    = var.tool_keycloak_db_password_kv_secret_id
  tool_keycloak_app_insights_kv_secret_id   = var.tool_keycloak_app_insights_kv_secret_id

  # CORS
  additional_cors_origins = var.additional_cors_origins
  app_gateway_hostname    = var.app_gateway_hostname

  # Toggle for Tool apps deployment
  deploy_tool_apps = var.deploy_tool_apps

  # Toggle for monitoring module deployment
  deploy_monitoring       = var.deploy_monitoring
  paging_email_recipients = var.paging_email_recipients
  alert_card_language     = var.alert_card_language
  teams_group_id          = var.teams_group_id
  teams_channel_id        = var.teams_channel_id

  # Frontend gating
  validator_site_status         = var.validator_site_status
  tool_site_status              = var.tool_site_status
  validator_site_preview_secret = var.validator_site_preview_secret
  tool_site_preview_secret      = var.tool_site_preview_secret

  # Validator BFF mode (false = legacy public backend + NEXT_PUBLIC_BE_URL)
  validator_use_bff = var.validator_use_bff

  # Validator Class A: KV references (empty = inline value)
  validator_backend_app_insights_kv_secret_id         = var.validator_backend_app_insights_kv_secret_id
  validator_frontend_app_insights_kv_secret_id        = var.validator_frontend_app_insights_kv_secret_id
  validator_frontend_site_preview_secret_kv_secret_id = var.validator_frontend_site_preview_secret_kv_secret_id

  # Remote state (guarded for initial plan)
  shared_global_vnet_id             = try(data.terraform_remote_state.shared_global.outputs.vnet_id, "")
  shared_global_vnet_name           = try(data.terraform_remote_state.shared_global.outputs.vnet_name, "")
  shared_global_resource_group_name = try(data.terraform_remote_state.shared_global.outputs.resource_group_name, "")
  app_gateway_public_ip_address     = try(data.terraform_remote_state.shared_global.outputs.app_gateway_public_ip_address, "")
  shared_global_app_gateway_id      = try(data.terraform_remote_state.shared_global.outputs.app_gateway_id, "")
}

# Production environment
module "prod" {
  count  = terraform.workspace == "prod" ? 1 : 0
  source = "./environments/prod"

  # Common variables
  environment = "prod"
  location    = var.location

  # Per-env Key Vault operator grants (seed/rotate secret values via CLI)
  keyvault_operator_object_ids = var.keyvault_operator_object_ids

  # Validator Apps
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag
  backend_port       = var.backend_port
  frontend_app_name  = var.frontend_app_name
  backend_app_name   = var.backend_app_name

  # Resource groups
  shared_resource_group_name    = var.shared_resource_group_name
  validator_resource_group_name = var.validator_resource_group_name
  tool_resource_group_name      = var.tool_resource_group_name

  # Tool Apps
  tool_frontend_image     = var.tool_frontend_image
  tool_frontend_image_tag = var.tool_frontend_image_tag
  tool_backend_image      = var.tool_backend_image
  tool_backend_image_tag  = var.tool_backend_image_tag
  tool_frontend_app_name  = var.tool_frontend_app_name
  tool_backend_app_name   = var.tool_backend_app_name

  # NKD SPARQL endpoint (NKD_SPARQL_ENDPOINT) — per-environment target.
  tool_nkd_sparql_endpoint = var.tool_nkd_sparql_endpoint

  # Tool Database & Fuseki
  admin_allowed_ips            = var.admin_allowed_ips
  tool_postgres_url            = var.tool_postgres_url
  tool_postgres_user           = var.tool_postgres_user
  tool_postgres_password       = var.tool_postgres_password
  tool_fuseki_url              = var.tool_fuseki_url
  tool_nextauth_secret         = var.tool_nextauth_secret
  tool_base_path               = var.tool_base_path
  tool_deploy_keycloak         = var.tool_deploy_keycloak
  tool_enable_caais            = var.tool_enable_caais
  tool_keycloak_image          = var.tool_keycloak_image
  tool_keycloak_image_tag      = var.tool_keycloak_image_tag
  tool_keycloak_app_name       = var.tool_keycloak_app_name
  tool_keycloak_admin_user     = var.tool_keycloak_admin_user
  tool_keycloak_admin_password = var.tool_keycloak_admin_password
  tool_keycloak_hostname       = var.tool_keycloak_hostname
  tool_keycloak_realm          = var.tool_keycloak_realm
  tool_keycloak_issuer_uri     = var.tool_keycloak_issuer_uri
  tool_keycloak_client_id      = var.tool_keycloak_client_id
  tool_keycloak_idp_hint       = var.tool_keycloak_idp_hint
  tool_keycloak_client_secret  = var.tool_keycloak_client_secret
  tool_caais_client_id         = var.tool_caais_client_id
  tool_caais_p12_kv_secret_id  = var.tool_caais_p12_kv_secret_id

  tool_caais_keystore_password_kv_secret_id = var.tool_caais_keystore_password_kv_secret_id

  tool_app_insights_kv_secret_id           = var.tool_app_insights_kv_secret_id
  tool_postgres_password_kv_secret_id      = var.tool_postgres_password_kv_secret_id
  tool_keycloak_client_secret_kv_secret_id = var.tool_keycloak_client_secret_kv_secret_id

  tool_frontend_app_insights_kv_secret_id           = var.tool_frontend_app_insights_kv_secret_id
  tool_frontend_nextauth_secret_kv_secret_id        = var.tool_frontend_nextauth_secret_kv_secret_id
  tool_frontend_keycloak_client_secret_kv_secret_id = var.tool_frontend_keycloak_client_secret_kv_secret_id
  tool_frontend_site_preview_secret_kv_secret_id    = var.tool_frontend_site_preview_secret_kv_secret_id

  tool_keycloak_admin_password_kv_secret_id = var.tool_keycloak_admin_password_kv_secret_id
  tool_keycloak_db_password_kv_secret_id    = var.tool_keycloak_db_password_kv_secret_id
  tool_keycloak_app_insights_kv_secret_id   = var.tool_keycloak_app_insights_kv_secret_id

  # CORS
  additional_cors_origins = var.additional_cors_origins
  app_gateway_hostname    = var.app_gateway_hostname

  # Toggle for Tool apps deployment
  deploy_tool_apps = var.deploy_tool_apps

  # Toggle for monitoring module deployment
  deploy_monitoring       = var.deploy_monitoring
  paging_email_recipients = var.paging_email_recipients
  alert_card_language     = var.alert_card_language
  teams_group_id          = var.teams_group_id
  teams_channel_id        = var.teams_channel_id

  # Frontend gating
  validator_site_status         = var.validator_site_status
  tool_site_status              = var.tool_site_status
  validator_site_preview_secret = var.validator_site_preview_secret
  tool_site_preview_secret      = var.tool_site_preview_secret

  # Validator BFF mode (false = legacy public backend + NEXT_PUBLIC_BE_URL)
  validator_use_bff = var.validator_use_bff

  # Validator Class A: KV references (empty = inline value)
  validator_backend_app_insights_kv_secret_id         = var.validator_backend_app_insights_kv_secret_id
  validator_frontend_app_insights_kv_secret_id        = var.validator_frontend_app_insights_kv_secret_id
  validator_frontend_site_preview_secret_kv_secret_id = var.validator_frontend_site_preview_secret_kv_secret_id

  # Remote state (guarded for initial plan)
  shared_global_vnet_id             = try(data.terraform_remote_state.shared_global.outputs.vnet_id, "")
  shared_global_vnet_name           = try(data.terraform_remote_state.shared_global.outputs.vnet_name, "")
  shared_global_resource_group_name = try(data.terraform_remote_state.shared_global.outputs.resource_group_name, "")
  app_gateway_public_ip_address     = try(data.terraform_remote_state.shared_global.outputs.app_gateway_public_ip_address, "")
  shared_global_app_gateway_id      = try(data.terraform_remote_state.shared_global.outputs.app_gateway_id, "")
}

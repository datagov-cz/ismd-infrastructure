# Test Environment — module composition
# Variables: variables.tf | Resource groups: resource_groups.tf | Networking: networking.tf | Outputs: outputs.tf

# Shared resources (networking, resource groups, etc.)
module "shared" {
  source = "../../modules/shared"

  environment                     = var.environment
  location                        = var.location
  resource_group_name             = var.shared_resource_group_name
  vnet_address_space              = "10.2.0.0/16"        # TEST: 10.2.x.x (avoids conflict with shared-global 10.1.x.x)
  vnet_address_space_ipv6         = "fd00:db8:decc::/48" # TEST: unique IPv6
  validator_subnet_address_prefix = "10.2.2.0/23"        # TEST: within 10.2.0.0/16
  tool_subnet_address_prefix      = "10.2.4.0/23"        # TEST: within 10.2.0.0/16
}

# Create validator apps using shared Container App Environment
module "validator_apps" {
  source = "../../modules/validator_apps"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.validator_resource_group_name

  # Required by the module
  shared_resource_group_name   = var.shared_resource_group_name
  container_app_environment_id = module.shared.shared_container_app_environment_id
  # Container Images
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # IP Restrictions
  app_gateway_public_ip = var.app_gateway_public_ip_address
  app_gateway_hostname  = var.app_gateway_hostname

  # CORS
  additional_cors_origins = var.additional_cors_origins

  # App names
  frontend_app_name = var.frontend_app_name
  backend_app_name  = var.backend_app_name

  # Workload profile configuration
  workload_profile_name = "default"

  # Frontend gating (live | coming_soon | maintenance)
  site_status         = var.validator_site_status
  site_preview_secret = var.validator_site_preview_secret

  # BFF mode toggle — keep false until the deployed frontend image supports BFF.
  use_bff       = var.validator_use_bff
  public_be_url = "https://${var.app_gateway_hostname}/validujeme"

  # Application Insights telemetry
  app_insights_connection_string = module.shared.app_insights_connection_string

  depends_on = [
    module.shared,
    azurerm_resource_group.validator
  ]
}

# Create tool apps using shared Container App Environment
module "tool_apps" {
  count  = var.deploy_tool_apps ? 1 : 0
  source = "../../modules/tool_apps"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.tool_resource_group_name

  # Required by the module
  shared_resource_group_name               = var.shared_resource_group_name
  container_app_environment_id             = module.shared.shared_container_app_environment_id
  container_app_environment_default_domain = module.shared.shared_container_app_environment_default_domain

  # Container Images
  frontend_image     = var.tool_frontend_image
  frontend_image_tag = var.tool_frontend_image_tag
  backend_image      = var.tool_backend_image
  backend_image_tag  = var.tool_backend_image_tag

  # IP Restrictions
  app_gateway_public_ip = var.app_gateway_public_ip_address
  app_gateway_hostname  = var.app_gateway_hostname

  # CORS
  additional_cors_origins = var.additional_cors_origins

  # App names
  frontend_app_name = var.tool_frontend_app_name
  backend_app_name  = var.tool_backend_app_name

  # Workload profile configuration
  workload_profile_name = "default"

  # Database & Fuseki Configuration
  deploy_postgres         = true
  deploy_fuseki           = true
  postgres_db_name        = "ismd_tool_db"
  postgres_admin_user     = "ismdadmin"
  postgres_admin_password = var.tool_postgres_password
  postgres_sku_name       = "B_Standard_B2s" # Burstable for test
  postgres_storage_mb     = 32768            # 32GB

  # Fallback external URLs (used if deploy_postgres/fuseki = false)
  postgres_url      = var.tool_postgres_url
  postgres_user     = var.tool_postgres_user
  postgres_password = var.tool_postgres_password
  fuseki_url        = var.tool_fuseki_url

  # Frontend auth
  nextauth_secret = var.tool_nextauth_secret
  tool_base_path  = var.tool_base_path

  # Frontend gating (live | coming_soon | maintenance)
  site_status         = var.tool_site_status
  site_preview_secret = var.tool_site_preview_secret

  # Keycloak / CAAIS
  deploy_keycloak         = var.tool_deploy_keycloak
  enable_caais            = var.tool_enable_caais
  keycloak_image          = var.tool_keycloak_image
  keycloak_image_tag      = var.tool_keycloak_image_tag
  keycloak_app_name       = var.tool_keycloak_app_name
  keycloak_admin_user     = var.tool_keycloak_admin_user
  keycloak_admin_password = var.tool_keycloak_admin_password
  keycloak_hostname       = var.tool_keycloak_hostname
  keycloak_realm          = var.tool_keycloak_realm
  keycloak_issuer_uri     = var.tool_keycloak_issuer_uri
  keycloak_client_id      = var.tool_keycloak_client_id
  keycloak_client_secret  = var.tool_keycloak_client_secret
  caais_client_id         = var.tool_caais_client_id

  # Application Insights telemetry
  app_insights_connection_string = module.shared.app_insights_connection_string

  depends_on = [
    module.shared,
    azurerm_resource_group.tool[0]
  ]
}

# Monitoring — Action Groups + Logic App posting alerts to Teams
#
# PHASE A: same Phase A channel as DEV (a maintainer's personal Teams channel)
# until supervisor handoff creates the DIA channels.
module "monitoring" {
  count  = var.deploy_monitoring ? 1 : 0
  source = "../../modules/monitoring"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.shared_resource_group_name

  log_analytics_workspace_id       = module.shared.shared_log_analytics_workspace_id
  application_insights_id          = module.shared.app_insights_id
  app_insights_instrumentation_key = module.shared.app_insights_instrumentation_key
  container_app_environment_id     = module.shared.shared_container_app_environment_id

  # Shared-global AppGW — cross-state lookup.
  application_gateway_id = try(var.shared_global_app_gateway_id, "")

  # Anticipatory pools pointing at resources not yet deployed (tool-prod-*).
  # Same exclusion list as DEV — when tool ships to PROD, drop these entries.
  # Format is "<backendPool>~<backendHttpSettings>" — Azure's BackendSettingsPool
  # metric dimension joins the two names with a tilde.
  appgw_excluded_backend_settings = [
    "tool-prod-fe-pool~tool-prod-fe-http-settings",
    "tool-prod-keycloak-pool~tool-prod-keycloak-http-settings",
  ]

  # Phase B — DIA Teams "ismd-alerts-test" channel (DEV + TEST share the channel).
  # Requires apic-teams-test to be re-authorized in the portal against a DIA identity.
  teams_group_id   = var.teams_group_id
  teams_channel_id = var.teams_channel_id

  paging_email_recipients = var.paging_email_recipients
  alert_card_language     = var.alert_card_language

  # Public-endpoint availability probes.
  # Keycloak omitted: the `ismd` realm doesn't exist in TEST yet.
  # `master` realm exists but probing it doesn't reflect app readiness. Re-add the
  # keycloak probe once the ismd realm is provisioned in TEST.
  availability_tests = {
    "validator-fe" = { url = "https://${var.app_gateway_hostname}/validujeme" }
    "tool-fe"      = { url = "https://${var.app_gateway_hostname}${var.tool_base_path}" }
  }

  # Container Apps to alert on — full set deployed in TEST (same shape as DEV).
  # memory_gib mirrors the container `memory` setting in modules/tool_apps and
  # modules/validator_apps (the modules apply the same value for all envs).
  container_apps = merge(
    {
      "validator-be" = {
        id         = module.validator_apps.backend_id
        name       = module.validator_apps.backend_name
        memory_gib = 1
      }
      "validator-fe" = {
        id         = module.validator_apps.frontend_id
        name       = module.validator_apps.frontend_name
        memory_gib = 1
      }
    },
    var.deploy_tool_apps ? {
      "tool-be" = {
        id         = module.tool_apps[0].backend_id
        name       = module.tool_apps[0].backend_name
        memory_gib = 1
      }
      "tool-fe" = {
        id         = module.tool_apps[0].frontend_id
        name       = module.tool_apps[0].frontend_name
        memory_gib = 1
      }
    } : {},
    var.deploy_tool_apps && var.tool_deploy_keycloak ? {
      "keycloak" = {
        id         = module.tool_apps[0].keycloak_id
        name       = module.tool_apps[0].keycloak_name
        memory_gib = 1
      }
    } : {},
    var.deploy_tool_apps ? {
      "fuseki" = {
        id         = module.tool_apps[0].fuseki_id
        name       = module.tool_apps[0].fuseki_name
        memory_gib = 6 # 2 → 4 (2026-05-26) → 6 (2026-05-27); see modules/tool_apps/database.tf
      }
    } : {},
  )

  postgres_servers = var.deploy_tool_apps ? {
    "tool-postgres" = {
      id   = module.tool_apps[0].postgres_server_id
      name = module.tool_apps[0].postgres_server_name
    }
  } : {}

  depends_on = [
    module.shared,
  ]
}

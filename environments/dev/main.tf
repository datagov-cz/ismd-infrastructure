# Dev Environment — module composition
# Variables: variables.tf | Resource groups: resource_groups.tf | Networking: networking.tf | Outputs: outputs.tf

# Shared resources (networking, resource groups, etc.)
module "shared" {
  source = "../../modules/shared"

  environment                     = var.environment
  location                        = var.location
  resource_group_name             = var.shared_resource_group_name
  vnet_address_space              = "10.0.0.0/16"        # DEV: 10.0.x.x (default, already deployed)
  vnet_address_space_ipv6         = "fd00:db8:deca::/48" # DEV: default IPv6 (already deployed)
  validator_subnet_address_prefix = "10.0.2.0/23"        # DEV: within 10.0.0.0/16 (already deployed)
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

  # BFF mode toggle — DEV uses -dev images which have BFF.
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

  # DEV-only: expose backend externally for the local-frontend → DEV-backend
  # dev loop (App Gateway /popisujeme/be/* route). TEST/PROD leave this default false.
  backend_external_enabled = true

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
  postgres_sku_name       = "B_Standard_B1ms" # Burstable tier for dev
  postgres_storage_mb     = 32768             # 32GB

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
# PHASE A: Logic App connects to a maintainer's personal Teams channel for
# end-to-end verification before swapping to the DIA tenant in Phase B.
# When Phase B is ready, supervisor creates the channel in DIA Teams and
# the IDs below get swapped (group_id + channel_id) + connector re-authorized.
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

  # Shared-global AppGW — cross-state lookup. Empty when remote state doesn't
  # expose the ID (e.g. the output hasn't been added yet); alerts then skip.
  application_gateway_id = try(var.shared_global_app_gateway_id, "")

  # Exclude AppGW backend settings that point to anticipatory pools (resources
  # not yet deployed). When tool ships to PROD, drop the tool-prod-* entries.
  # Format is "<backendPool>~<backendHttpSettings>" — Azure's BackendSettingsPool
  # metric dimension joins the two names with a tilde. Using only the http-settings
  # name silently does not match anything.
  appgw_excluded_backend_settings = [
    "tool-prod-fe-pool~tool-prod-fe-http-settings",
    "tool-prod-keycloak-pool~tool-prod-keycloak-http-settings",
  ]

  # Phase B — DIA Teams "ismd-alerts-test" channel (DEV + TEST share the channel).
  # Requires apic-teams-dev to be re-authorized in the portal against a DIA identity
  # that has access to this team. Without re-auth, posts will fail with auth errors.
  teams_group_id   = var.teams_group_id
  teams_channel_id = var.teams_channel_id

  # DEV paging recipients — driven by tfvars (var.paging_email_recipients).
  # Empty list = no paging action group. Populate via tfvars to test the email
  # path before the Entra mail-enabled group exists (Plan A from monitoring-plan.md).
  paging_email_recipients = var.paging_email_recipients

  # Card localization (cs|en). Defaults to cs in the variable definition.
  alert_card_language = var.alert_card_language

  # Public-endpoint availability probes (5-min cadence, 3 EMEA regions, fail 2/3 → alert).
  # Keycloak's .well-known/openid-configuration is a cheap signed-response endpoint that
  # confirms the realm config is live — better signal than a generic 200 on /.
  # NB: paths intentionally have no trailing slash. The AppGW 308-redirects
  # `/popisujeme/` → `/popisujeme` and similar; standard web tests can be flaky
  # about counting the 308 vs the followed 200 even with follow_redirects on.
  availability_tests = {
    "validator-fe" = { url = "https://${var.app_gateway_hostname}/validujeme" }
    "tool-fe"      = { url = "https://${var.app_gateway_hostname}${var.tool_base_path}" }
    # Keycloak lives under the tool path: AppGW routes /popisujeme/auth/* → keycloak app.
    # The issuer URI in modules/tool_apps/keycloak.tf is also /popisujeme/auth/realms/<realm>.
    "keycloak" = { url = "https://${var.tool_keycloak_hostname}${var.tool_base_path}/auth/realms/${var.tool_keycloak_realm}/.well-known/openid-configuration" }
  }

  # Container Apps to alert on. Expand as more alert rules come online.
  # memory_gib mirrors the container's `memory` setting in modules/tool_apps and
  # modules/validator_apps. If those change, update here so the memory_high alert
  # threshold (85% of memory_gib) stays accurate. Future improvement: expose
  # memory as an output from each *_apps module and pull dynamically.
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

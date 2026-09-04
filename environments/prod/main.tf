# Production Environment — module composition
# Variables: variables.tf | Resource groups: resource_groups.tf | Networking: networking.tf | Outputs: outputs.tf

# Shared resources (networking, resource groups, etc.)
module "shared" {
  source = "../../modules/shared"

  environment                     = var.environment
  location                        = var.location
  resource_group_name             = var.shared_resource_group_name
  vnet_address_space              = "10.3.0.0/16"        # PROD: 10.3.x.x
  vnet_address_space_ipv6         = "fd00:db8:decd::/48" # PROD: unique IPv6
  validator_subnet_address_prefix = "10.3.2.0/23"        # PROD: within 10.3.0.0/16
  tool_subnet_address_prefix      = "10.3.4.0/23"        # PROD: within 10.3.0.0/16
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
  backend_port       = var.backend_port

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

  # Class A: KV references (empty = inline value; two-phase cutover)
  backend_app_insights_kv_secret_id         = var.validator_backend_app_insights_kv_secret_id
  frontend_app_insights_kv_secret_id        = var.validator_frontend_app_insights_kv_secret_id
  frontend_site_preview_secret_kv_secret_id = var.validator_frontend_site_preview_secret_kv_secret_id

  depends_on = [
    module.shared,
    azurerm_resource_group.validator
  ]
}

# Shared per-env Postgres Flexible Server. Owned here rather than by tool_apps
# because tool, keycloak and the AI app all have databases on it. Each app module
# creates its own database against server_id.
#
# resource_group_name: still the TOOL rg. Relocating to ismd-shared-prod is a
# separate step — changing it here forces replacement (total data loss). Move the
# resource with `az resource move`, re-import the addresses, then change it.
# See docs/postgres-shared-move-plan.md.
module "postgres" {
  count  = var.deploy_tool_apps ? 1 : 0
  source = "../../modules/postgres"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.tool_resource_group_name

  postgres_admin_user     = "ismdadmin"
  postgres_admin_password = var.tool_postgres_password
  postgres_sku_name       = "GP_Standard_D2s_v3" # General Purpose for prod
  postgres_storage_mb     = 65536                # 64GB for prod

  # Firewall allowlist. No NAT gateway on the apps subnet yet, so apps egress via
  # dynamic Azure SNAT and need allow_azure_services (default true).
  # app_outbound_ips stays empty until a NAT gateway provides a stable egress IP.
  app_outbound_ips  = []
  admin_allowed_ips = var.admin_allowed_ips
}

# Server extracted from modules/tool_apps into modules/postgres (2026-08-12).
# State-address relocation only — the resources themselves are untouched, and the
# plan MUST show 0 to destroy.
moved {
  from = module.tool_apps[0].azurerm_postgresql_flexible_server.tool[0]
  to   = module.postgres[0].azurerm_postgresql_flexible_server.tool
}

moved {
  from = module.tool_apps[0].azurerm_postgresql_flexible_server_configuration.unaccent[0]
  to   = module.postgres[0].azurerm_postgresql_flexible_server_configuration.unaccent
}

moved {
  from = module.tool_apps[0].azurerm_postgresql_flexible_server_configuration.idle_session_timeout[0]
  to   = module.postgres[0].azurerm_postgresql_flexible_server_configuration.idle_session_timeout
}

moved {
  from = module.tool_apps[0].azurerm_postgresql_flexible_server_configuration.idle_in_transaction_session_timeout[0]
  to   = module.postgres[0].azurerm_postgresql_flexible_server_configuration.idle_in_transaction_session_timeout
}

moved {
  from = module.tool_apps[0].azurerm_postgresql_flexible_server_firewall_rule.allow_azure[0]
  to   = module.postgres[0].azurerm_postgresql_flexible_server_firewall_rule.allow_azure[0]
}

moved {
  from = module.tool_apps[0].azurerm_postgresql_flexible_server_firewall_rule.app_outbound
  to   = module.postgres[0].azurerm_postgresql_flexible_server_firewall_rule.app_outbound
}

moved {
  from = module.tool_apps[0].azurerm_postgresql_flexible_server_firewall_rule.admin
  to   = module.postgres[0].azurerm_postgresql_flexible_server_firewall_rule.admin
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

  # NKD SPARQL endpoint (NKD_SPARQL_ENDPOINT) — per-environment target.
  nkd_sparql_endpoint = var.tool_nkd_sparql_endpoint

  # Validator BE the tool BE calls internally (VALIDATION_SERVICE_URL).
  validator_backend_app_name = module.validator_apps.backend_name

  # Workload profile configuration
  workload_profile_name = "default"

  # Database & Fuseki Configuration
  deploy_postgres         = true
  deploy_fuseki           = true
  postgres_db_name        = "ismd_tool_db"
  postgres_admin_user     = "ismdadmin"
  postgres_admin_password = var.tool_postgres_password

  # The server lives in module.postgres; this module only creates its databases.
  postgres_server_id = module.postgres[0].server_id
  postgres_fqdn      = module.postgres[0].fqdn

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
  keycloak_idp_hint       = var.tool_keycloak_idp_hint
  keycloak_client_secret  = var.tool_keycloak_client_secret
  caais_client_id         = var.tool_caais_client_id

  # CAAIS mTLS keystore — KV secret ids in ismd-kv-<env>. The p12 id normally points
  # at the auto-exposed secret of the CAAIS KV Certificate object (key generated
  # in-vault, signed cert merged in). Empty until that merge lands; the wiring stays
  # inert while empty even with enable_caais = true. See docs/caais-enable.md.
  caais_p12_kv_secret_id               = var.tool_caais_p12_kv_secret_id
  caais_keystore_password_kv_secret_id = var.tool_caais_keystore_password_kv_secret_id

  # Class A: KV references (empty = inline value; two-phase cutover)
  app_insights_kv_secret_id           = var.tool_app_insights_kv_secret_id
  postgres_password_kv_secret_id      = var.tool_postgres_password_kv_secret_id
  keycloak_client_secret_kv_secret_id = var.tool_keycloak_client_secret_kv_secret_id

  frontend_app_insights_kv_secret_id           = var.tool_frontend_app_insights_kv_secret_id
  frontend_nextauth_secret_kv_secret_id        = var.tool_frontend_nextauth_secret_kv_secret_id
  frontend_keycloak_client_secret_kv_secret_id = var.tool_frontend_keycloak_client_secret_kv_secret_id
  frontend_site_preview_secret_kv_secret_id    = var.tool_frontend_site_preview_secret_kv_secret_id

  keycloak_admin_password_kv_secret_id = var.tool_keycloak_admin_password_kv_secret_id
  keycloak_db_password_kv_secret_id    = var.tool_keycloak_db_password_kv_secret_id
  keycloak_app_insights_kv_secret_id   = var.tool_keycloak_app_insights_kv_secret_id

  # Application Insights telemetry
  app_insights_connection_string = module.shared.app_insights_connection_string

  depends_on = [
    module.shared,
    azurerm_resource_group.tool[0]
  ]
}

# Monitoring — Action Groups + Logic App posting alerts to Teams
#
# PHASE A: Logic App connects to a maintainer's personal Teams channel until
# supervisor handoff creates DIA channels. When Phase B is ready, swap teams_group_id +
# teams_channel_id below + re-authorize the Teams API connection in the portal.
#
# Note: PROD currently has only validator deployed (deploy_tool_apps=false).
# When tool ships to PROD, extend the container_apps map and add the
# tool-prod-* entries to appgw_backend_settings.
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

  # PROD's own AppGW backends — scopes the shared gateway's 5xx + unhealthy-host
  # alerts to PROD only, so dev/test traffic no longer fires PROD alerts. Only
  # validator is deployed in PROD; the anticipatory tool-prod-* pools are
  # deliberately omitted (they point at nothing and would 5xx). Add tool-prod-fe
  # and tool-prod-keycloak entries here when tool ships to PROD.
  appgw_backend_settings = [
    { pool = "validator-prod-fe-pool", http_settings = "validator-prod-fe-http-settings" },
  ]

  # Phase B — DIA Teams "ismd-alerts-prod" channel.
  # Requires apic-teams-prod to be re-authorized in the portal against a DIA identity.
  teams_group_id   = var.teams_group_id
  teams_channel_id = var.teams_channel_id

  paging_email_recipients = var.paging_email_recipients
  alert_card_language     = var.alert_card_language

  # Public-endpoint availability probes. Only validator is deployed in PROD;
  # tool-fe and keycloak probes added when tool ships to PROD.
  availability_tests = {
    "validator-fe" = { url = "https://${var.app_gateway_hostname}/validujeme" }
  }

  # Container Apps to alert on — validator only until tool ships to PROD.
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
      id   = module.postgres[0].server_id
      name = module.postgres[0].name
    }
  } : {}

  depends_on = [
    module.shared,
  ]
}

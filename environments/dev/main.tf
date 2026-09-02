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

  # BFF mode toggle — DEV uses -dev images which have BFF.
  use_bff       = var.validator_use_bff
  public_be_url = "https://${var.app_gateway_hostname}/validujeme"

  # Application Insights telemetry
  app_insights_connection_string = module.shared.app_insights_connection_string

  # Activate the App Insights Java agent. Safe here because the jar-bearing
  # validator backend image is deployed on DEV. TEST/PROD stay default false
  # until their jar images ship.
  enable_app_insights_agent = true

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
# resource_group_name: still the TOOL rg. Relocating to ismd-shared-dev is a
# separate step — changing it here forces replacement (total data loss). Move the
# resource with `az resource move`, re-import the addresses, then change it.
# See docs/postgres-shared-move-plan.md.
module "postgres" {
  count  = var.deploy_tool_apps ? 1 : 0
  source = "../../modules/postgres"

  environment = var.environment
  location    = var.location

  # The server lives in the shared RG, not the tool RG: it backs three tenants
  # (ismd_tool_db, keycloak_db, ismd_ai), so it is a per-env shared resource.
  # Moved in Azure with `az resource move` on 2026-09-02 and re-imported; the
  # config change had to follow the move, because changing resource_group_name
  # on an existing server forces replacement and total data loss.
  resource_group_name = var.shared_resource_group_name

  postgres_admin_user     = "ismdadmin"
  postgres_admin_password = var.tool_postgres_password
  postgres_sku_name       = "B_Standard_B1ms" # Burstable tier for dev
  postgres_storage_mb     = 32768             # 32GB

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

  # Per-app DB user separation (Phase 2). Empty = admin login until the env flips
  # it. See infrastructure/db/user-separation/README.md.
  backend_db_user  = var.tool_backend_db_user
  keycloak_db_user = var.tool_keycloak_db_user

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

  # Activate the App Insights Java agent. Safe here because the jar-bearing
  # tool backend image is deployed on DEV. TEST/PROD stay default false until
  # their jar images ship.
  enable_app_insights_agent = true

  # Activate server-side App Insights on the Next.js frontend (injects
  # OTEL_SERVICE_NAME). Safe here because the dep-bearing image is deployed on
  # DEV: ismd-tool-frontend-dev:1.0.2-640eed0 carries @azure/monitor-opentelemetry
  # 1.18.1. TEST stays default false — its released 1.0.2 image predates the dep.
  enable_frontend_app_insights = true

  depends_on = [
    module.shared,
    azurerm_resource_group.tool[0]
  ]
}

# Create AI apps (ismd-ai semantic modeling assistant) on the shared Container
# App Environment. Internal-only; its Postgres database lives on the tool's
# Flexible Server, so deploy_ai_apps requires deploy_tool_apps.
module "ai_apps" {
  count  = var.deploy_ai_apps ? 1 : 0
  source = "../../modules/ai_apps"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.ai_resource_group_name

  container_app_environment_id = module.shared.shared_container_app_environment_id

  # Container image
  backend_app_name  = var.ai_backend_app_name
  backend_image     = var.ai_backend_image
  backend_image_tag = var.ai_backend_image_tag

  # Workload profile configuration
  workload_profile_name = "default"

  # Database — dedicated ismd_ai DB on the tool's Postgres server.
  postgres_server_id = module.postgres[0].server_id
  postgres_fqdn      = module.postgres[0].fqdn
  postgres_db_name   = "ismd_ai"
  # Per-app DB user separation (Phase 2). Defaults to the admin login; flip to
  # ismd_ai_app via var.ai_db_user after db/user-separation Phase 1. Cut over first
  # (lowest risk). Its password rides the same secret as the tool admin today —
  # point ai_postgres_password_kv_secret_id at the ismd_ai_app secret on cutover.
  postgres_user     = var.ai_db_user
  postgres_password = var.tool_postgres_password
  # Reuses the tool's Postgres password KV secret (same server/admin login), but
  # gated on its own var for the Class A two-phase cutover: the container app
  # validates key_vault_secret_id at provision time, and the ai_kv grant in
  # keyvault.tf cannot be forced to land first (the grant reads the identity's
  # principal id out of this module, so a module-level depends_on would cycle).
  # Phase 1: leave empty → inline value, which creates the identity + grant.
  # Phase 2: set to var.tool_postgres_password_kv_secret_id → flips to the KV ref.
  postgres_password_kv_secret_id = var.ai_postgres_password_kv_secret_id

  # LLM — disabled until the API key secret is seeded. provider + endpoint_url
  # are what point this app at a specific AI host, so each env can target either
  # the non-prod or prod Azure OpenAI resource (or OpenAI direct) via tfvars.
  llm_enabled              = var.ai_llm_enabled
  llm_provider             = var.ai_llm_provider
  llm_endpoint_url         = var.ai_llm_endpoint_url
  llm_model                = var.ai_llm_model
  llm_api_key              = var.ai_llm_api_key
  llm_api_key_kv_secret_id = var.ai_llm_api_key_kv_secret_id

  # Auth: development (no OIDC) for now.
  app_environment = var.ai_app_environment

  # GHCR pull auth — only needed while the ismd-ai package is private. Leave
  # empty once the package (or repo) is made public; the registry block then
  # disappears and the app pulls anonymously like the other apps.
  ghcr_username           = var.ai_ghcr_username
  ghcr_token              = var.ai_ghcr_token
  ghcr_token_kv_secret_id = var.ai_ghcr_token_kv_secret_id

  # Telemetry
  app_insights_connection_string = module.shared.app_insights_connection_string
  app_insights_kv_secret_id      = var.ai_app_insights_kv_secret_id

  depends_on = [
    module.shared,
    module.tool_apps,
    azurerm_resource_group.ai[0]
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

  # DEV's own AppGW backends — scopes the shared gateway's 5xx + unhealthy-host
  # alerts to DEV only (the gateway also serves test/prod). validator + tool are
  # both deployed in DEV, including the dev-only tool-be pool. Keep in sync with
  # var.deploy_tool_apps: drop the tool-dev-* entries if tool is undeployed here.
  appgw_backend_settings = [
    { pool = "validator-dev-fe-pool", http_settings = "validator-dev-fe-http-settings" },
    { pool = "tool-dev-fe-pool", http_settings = "tool-dev-fe-http-settings" },
    { pool = "tool-dev-keycloak-pool", http_settings = "tool-dev-keycloak-http-settings" },
    { pool = "tool-dev-be-pool", http_settings = "tool-dev-be-http-settings" },
  ]

  # Phase B — DIA Teams "ismd-alerts-test" channel (DEV + TEST share the channel).
  # Requires apic-teams-dev to be re-authorized in the portal against a DIA identity
  # that has access to this team. Without re-auth, posts will fail with auth errors.
  teams_group_id   = var.teams_group_id
  teams_channel_id = var.teams_channel_id

  # DEV paging recipients — driven by tfvars (var.paging_email_recipients).
  # Empty list = no paging action group. Populate via tfvars to test the email
  # path before the Entra mail-enabled group exists.
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
    var.deploy_ai_apps ? {
      "ai-be" = {
        id         = module.ai_apps[0].backend_id
        name       = module.ai_apps[0].backend_name
        memory_gib = 1
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

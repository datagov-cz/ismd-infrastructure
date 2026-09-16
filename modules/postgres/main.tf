# Azure Database for PostgreSQL Flexible Server — shared per-environment resource.
#
# Extracted from modules/tool_apps (2026-08-12). The server was declared there but
# backs three tenants, which made "tool" the owner of infrastructure that keycloak
# and the AI app also depend on — the layering violation described in
# docs/postgres-shared-move-plan.md.
#
# This module owns the SERVER only. Each app module creates its own database
# against the server_id output — the pattern ai_apps already used.
#
# Tenants on this server today:
#   - ismd_tool_db  (tool backend)   — created in modules/tool_apps
#   - keycloak_db   (keycloak)       — created in modules/tool_apps
#   - ismd_ai       (AI app)         — created in modules/ai_apps
#
# Before changing anything here:
#   - the SKU is small (B_Standard_B1ms in dev) and max_connections is limited, so
#     every tenant's pool is sized defensively against the same ceiling (the Hikari
#     caps on the tool backend, KC_DB_POOL_MAX_CONNECTIONS on keycloak). A new
#     tenant must budget against it too.
#   - per-app LOGIN roles are created by SQL, not Terraform — see
#     db/user-separation/. This module never manages roles.
resource "azurerm_postgresql_flexible_server" "tool" {
  name                = "ismd-tool-postgres-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "16"

  administrator_login    = var.postgres_admin_user
  administrator_password = var.postgres_admin_password

  # Burstable tier - cost-effective for dev/test
  sku_name   = var.postgres_sku_name
  storage_mb = var.postgres_storage_mb

  # Backup configuration
  backup_retention_days        = var.environment == "prod" ? 35 : 7
  geo_redundant_backup_enabled = var.environment == "prod"

  # Zone redundancy for prod only
  # NOTE: Hardcoded to "1" for dev to match existing server state.
  # Change this only if recreating the server.
  zone = "1"

  # Public access for simplicity (can be restricted later with firewall rules)
  public_network_access_enabled = true

  # Custom maintenance window. With the system-managed default Azure picks the slot
  # itself: 2026-09-13 it patched dev at 22:04 UTC and test at 23:33 UTC, the same
  # night, with CPU at ~100% and a restart on each (Service Health TYGS-S5Z). A
  # custom window makes the slot predictable and staggers dev ahead of test.
  # Times are UTC; day_of_week 0 = Sunday.
  dynamic "maintenance_window" {
    for_each = var.maintenance_window == null ? [] : [var.maintenance_window]
    content {
      day_of_week  = maintenance_window.value.day_of_week
      start_hour   = maintenance_window.value.start_hour
      start_minute = maintenance_window.value.start_minute
    }
  }

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Database"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    # administrator_password is NOT ignored. It used to be, but the server was
    # re-imported on 2026-09-02 and import stores no password, so ignore_changes
    # sent null on every update and the provider refused any in-place change
    # ("administrator_password ... is required when password_auth_enabled").
    #
    # The value comes from Key Vault (terraw resolves TF_VAR_tool_postgres_password
    # from ismd-kv-<env>/postgres-password and refuses apply if it is unresolved),
    # so KV is the source of truth. To rotate: set the new KV version, apply, then
    # create a NEW REVISION on every consuming app — a restart does not re-resolve
    # a Key Vault reference.
    ignore_changes = [zone]
  }
}

# Allow the unaccent extension at the server level so the application can
# CREATE EXTENSION unaccent in the ismd_schema. The repositories in
# ismd-tool-backend (ConceptMetadataRepository, OntologyMetadataRepository)
# call ismd_schema.unaccent(...) for diacritic-insensitive search over
# Czech text — without this, those queries fail at runtime.
resource "azurerm_postgresql_flexible_server_configuration" "unaccent" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.tool.id
  value     = "UNACCENT"
}

# Auto-reap abandoned sessions so dead/orphaned connections (e.g. left behind
# when a client's network path drops) free their slot instead of lingering until
# slow TCP keepalive timeouts — which is what tipped the 50-connection server
# into exhaustion during a reconnect storm. Values in milliseconds; both are
# dynamic (no restart). Set comfortably longer than pool keepalive so healthy
# pooled connections aren't churned.
resource "azurerm_postgresql_flexible_server_configuration" "idle_session_timeout" {
  name      = "idle_session_timeout"
  server_id = azurerm_postgresql_flexible_server.tool.id
  value     = "600000" # 10 min — closes sessions idle with no activity
}

resource "azurerm_postgresql_flexible_server_configuration" "idle_in_transaction_session_timeout" {
  name      = "idle_in_transaction_session_timeout"
  server_id = azurerm_postgresql_flexible_server.tool.id
  value     = "300000" # 5 min — guards against leaked open transactions
}

# --- Audit and diagnostics ---------------------------------------------------
# Server logs keep 3 days on the server and were never exported, so the 2026-09-13
# CPU spike could not be attributed. These settings are all dynamic (no restart).
# pgaudit is deliberately NOT here: it needs shared_preload_libraries, which
# restarts the server.

# Statement lines carry no user/db/client with the default "%t-%c-" prefix, so a
# logged statement cannot be traced to anyone.
resource "azurerm_postgresql_flexible_server_configuration" "log_line_prefix" {
  name      = "log_line_prefix"
  server_id = azurerm_postgresql_flexible_server.tool.id
  value     = "%t-%c-user=%u,db=%d,client=%h,app=%a-"
}

# Schema changes only (CREATE/ALTER/DROP). "mod" or "all" would log every
# Hibernate/Keycloak write and blow the Log Analytics daily cap.
resource "azurerm_postgresql_flexible_server_configuration" "log_statement" {
  name      = "log_statement"
  server_id = azurerm_postgresql_flexible_server.tool.id
  value     = "ddl"
}

# Query Store: records the top queries by resource use, including Azure's own
# internal ones. This is what answers "what burned the CPU", which pgaudit does not.
resource "azurerm_postgresql_flexible_server_configuration" "query_store_capture" {
  name      = "pg_qs.query_capture_mode"
  server_id = azurerm_postgresql_flexible_server.tool.id
  value     = "top"
}

resource "azurerm_postgresql_flexible_server_configuration" "wait_sampling_capture" {
  name      = "pgms_wait_sampling.query_capture_mode"
  server_id = azurerm_postgresql_flexible_server.tool.id
  value     = "all"
}

# Export server logs and Query Store to Log Analytics (30-day retention there vs
# 3 days on the server). Metrics are already available via Azure Monitor and
# the metric alerts, so AllMetrics is not shipped.
resource "azurerm_monitor_diagnostic_setting" "postgres" {
  count                      = var.log_analytics_workspace_id == null ? 0 : 1
  name                       = "diag-postgres-${var.environment}"
  target_resource_id         = azurerm_postgresql_flexible_server.tool.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "PostgreSQLLogs"
  }

  enabled_log {
    category = "PostgreSQLFlexQueryStoreRuntime"
  }

  enabled_log {
    category = "PostgreSQLFlexQueryStoreWaitStats"
  }

  # Maps Query Store query ids to SQL text.
  enabled_log {
    category = "PostgreSQLQueryStoreSqlText"
  }
}

# App access — Azure services.
# "AllowAzureServices" (0.0.0.0) admits ANY Azure-hosted resource in ANY tenant, not
# just ours — the password is then the only control. It was needed because the apps
# reached the PUBLIC endpoint via Azure's dynamic SNAT (no NAT gateway, so no stable
# egress IP to allowlist).
#
# With the private endpoint below, the apps no longer use the public endpoint. Set
# allow_azure_services = false once the private path is verified: every app
# connection in pg_stat_activity must come from the Container Apps subnet. The
# NAT-gateway + app_outbound_ips route still works but is no longer needed.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  count            = var.allow_azure_services ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.tool.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# App access — stable egress allowlist (used once a NAT gateway exists).
# Empty until then. When populated, set allow_azure_services = false above.
resource "azurerm_postgresql_flexible_server_firewall_rule" "app_outbound" {
  for_each         = toset(var.app_outbound_ips)
  name             = "app-${replace(each.value, ".", "-")}"
  server_id        = azurerm_postgresql_flexible_server.tool.id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# Admin access: specific operator IPs for troubleshooting.
# Replaces the previous "AllowAllForDev" (0.0.0.0-255.255.255.255) rule, which
# exposed the dev database to the entire internet.
resource "azurerm_postgresql_flexible_server_firewall_rule" "admin" {
  for_each         = toset(var.admin_allowed_ips)
  name             = "admin-${replace(each.value, ".", "-")}"
  server_id        = azurerm_postgresql_flexible_server.tool.id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# Private endpoint — how the apps reach the server once AllowAzureServices is gone.
#
# Additive: a public-access Flexible Server takes a private endpoint without being
# recreated (the live servers advertise the `postgresqlServer` private-link group).
# Do NOT switch to VNet integration (delegated_subnet_id) instead — that forces
# replacement, i.e. total data loss for every tenant.
#
# The privatelink zone is linked to this environment's VNet only, so the unchanged
# FQDN resolves to the private IP from inside the VNet (apps: no config change, no
# new revision) and to the public IP from outside it (operators via admin_allowed_ips).
#
# Gated on enable_private_endpoint, not on private_endpoint_subnet_id != null: the
# subnet id is unknown until the subnet exists, and count cannot depend on it.
resource "azurerm_private_dns_zone" "postgres" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Database"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = var.enable_private_endpoint ? 1 : 0
  name                  = "ismd-vnet-${var.environment}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Database"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    precondition {
      condition     = var.vnet_id != null
      error_message = "enable_private_endpoint requires vnet_id."
    }
  }
}

resource "azurerm_private_endpoint" "postgres" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "${azurerm_postgresql_flexible_server.tool.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${azurerm_postgresql_flexible_server.tool.name}-psc"
    private_connection_resource_id = azurerm_postgresql_flexible_server.tool.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgres[0].id]
  }

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Database"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    precondition {
      condition     = var.private_endpoint_subnet_id != null
      error_message = "enable_private_endpoint requires private_endpoint_subnet_id."
    }
  }
}

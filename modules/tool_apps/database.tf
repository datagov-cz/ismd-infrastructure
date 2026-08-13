# Azure Database for PostgreSQL Flexible Server
# Managed service with automatic backups, HA options, and persistent storage
#
# SHARED / MULTI-TENANT — this one server backs more than the tool. Databases on it:
#   - var.postgres_db_name  (ismd_tool_db)  — tool backend, below
#   - var.keycloak_db_name                  — keycloak container, below
#   - ismd_ai                               — the AI app, created OUT OF MODULE in
#     modules/ai_apps/database.tf, which receives this server's id from the env root
#
# Consequences, before changing anything here:
#   - deploy_ai_apps requires deploy_tool_apps; destroying/renaming this server or
#     flipping deploy_postgres takes the AI app's database with it.
#   - the SKU is small (B_Standard_B1ms in dev) and max_connections is limited, so
#     every tenant's pool is sized defensively (see the Hikari caps on the tool
#     backend and KC_DB_POOL_MAX_CONNECTIONS on keycloak). A new tenant must budget
#     its pool against the same ceiling.
#   - all tenants connect as this admin login, so the same password secret is shared;
#     there is no per-tenant DB user isolation today.
resource "azurerm_postgresql_flexible_server" "tool" {
  count               = var.deploy_postgres ? 1 : 0
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

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Database"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    # administrator_password: seeded once at create, then owned out-of-band (KV is
    # the source of truth; rotate via `az postgres flexible-server update` + KV +
    # app restart). Ignored so a stray `.env`/config drift can't rotate the live DB
    # admin password on apply.
    ignore_changes = [zone, administrator_password]
  }
}

# Allow the unaccent extension at the server level so the application can
# CREATE EXTENSION unaccent in the ismd_schema. The repositories in
# ismd-tool-backend (ConceptMetadataRepository, OntologyMetadataRepository)
# call ismd_schema.unaccent(...) for diacritic-insensitive search over
# Czech text — without this, those queries fail at runtime.
resource "azurerm_postgresql_flexible_server_configuration" "unaccent" {
  count     = var.deploy_postgres ? 1 : 0
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.tool[0].id
  value     = "UNACCENT"
}

# Auto-reap abandoned sessions so dead/orphaned connections (e.g. left behind
# when a client's network path drops) free their slot instead of lingering until
# slow TCP keepalive timeouts — which is what tipped the 50-connection server
# into exhaustion during a reconnect storm. Values in milliseconds; both are
# dynamic (no restart). Set comfortably longer than pool keepalive so healthy
# pooled connections aren't churned.
resource "azurerm_postgresql_flexible_server_configuration" "idle_session_timeout" {
  count     = var.deploy_postgres ? 1 : 0
  name      = "idle_session_timeout"
  server_id = azurerm_postgresql_flexible_server.tool[0].id
  value     = "600000" # 10 min — closes sessions idle with no activity
}

resource "azurerm_postgresql_flexible_server_configuration" "idle_in_transaction_session_timeout" {
  count     = var.deploy_postgres ? 1 : 0
  name      = "idle_in_transaction_session_timeout"
  server_id = azurerm_postgresql_flexible_server.tool[0].id
  value     = "300000" # 5 min — guards against leaked open transactions
}

# Create the application database
resource "azurerm_postgresql_flexible_server_database" "tool" {
  count     = var.deploy_postgres ? 1 : 0
  name      = var.postgres_db_name
  server_id = azurerm_postgresql_flexible_server.tool[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_database" "keycloak" {
  count     = var.deploy_postgres && var.deploy_keycloak ? 1 : 0
  name      = var.keycloak_db_name
  server_id = azurerm_postgresql_flexible_server.tool[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# App access — Azure services.
# The Container Apps subnet has NO NAT gateway, so the apps' outbound traffic to
# the public Postgres endpoint egresses via Azure's *dynamic* SNAT — NOT the
# environment's static (inbound) IP. There is therefore no single stable egress
# IP to allowlist, which is why this blanket "AllowAzureServices" (0.0.0.0) rule
# is required for the apps (backend, keycloak, fuseki) to reach the database.
#
# To tighten this to a real allowlist: add a NAT gateway + static public IP to
# the Container Apps subnet, put that IP in app_outbound_ips, and set
# allow_azure_services = false. See app_outbound rule below.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  count            = var.deploy_postgres && var.allow_azure_services ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.tool[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# App access — stable egress allowlist (used once a NAT gateway exists).
# Empty until then. When populated, set allow_azure_services = false above.
resource "azurerm_postgresql_flexible_server_firewall_rule" "app_outbound" {
  for_each         = var.deploy_postgres ? toset(var.app_outbound_ips) : toset([])
  name             = "app-${replace(each.value, ".", "-")}"
  server_id        = azurerm_postgresql_flexible_server.tool[0].id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# Admin access: specific operator IPs for troubleshooting.
# Replaces the previous "AllowAllForDev" (0.0.0.0-255.255.255.255) rule, which
# exposed the dev database to the entire internet.
resource "azurerm_postgresql_flexible_server_firewall_rule" "admin" {
  for_each         = var.deploy_postgres ? toset(var.admin_allowed_ips) : toset([])
  name             = "admin-${replace(each.value, ".", "-")}"
  server_id        = azurerm_postgresql_flexible_server.tool[0].id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# Storage Account for Fuseki data persistence
resource "azurerm_storage_account" "fuseki" {
  count                    = var.deploy_fuseki ? 1 : 0
  name                     = "ismdtoolfuseki${var.environment}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "GRS" : "LRS"
  min_tls_version          = "TLS1_2"

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Fuseki"
    ManagedBy   = "Terraform"
  }
}

# File Share for Fuseki databases
resource "azurerm_storage_share" "fuseki_data" {
  count              = var.deploy_fuseki ? 1 : 0
  name               = "fuseki-data"
  storage_account_id = azurerm_storage_account.fuseki[0].id
  quota              = 5 # 5GB should be enough for dev
}

# Container App Environment Storage for Fuseki
resource "azurerm_container_app_environment_storage" "fuseki" {
  count                        = var.deploy_fuseki ? 1 : 0
  name                         = "fuseki-storage"
  container_app_environment_id = var.container_app_environment_id
  account_name                 = azurerm_storage_account.fuseki[0].name
  share_name                   = azurerm_storage_share.fuseki_data[0].name
  access_key                   = azurerm_storage_account.fuseki[0].primary_access_key
  access_mode                  = "ReadWrite"
}
# Fuseki Container App for Tool
resource "azurerm_container_app" "fuseki" {
  count                        = var.deploy_fuseki ? 1 : 0
  name                         = "ismd-tool-fuseki-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  template {
    min_replicas = 1
    # LOAD-BEARING — do not scale above 1. This is a data-integrity constraint, not
    # a cost choice. Fuseki stores TDB2 on the Azure Files share mounted below, and
    # TDB2 is strictly single-writer: it guards the dataset with an on-disk lock.
    # A second replica mounting the same share either fails to acquire the lock or,
    # worse, corrupts the dataset — and this holds the tool's actual content, which
    # is NOT in Postgres. Recovering means the clear/reset procedure.
    # Scaling out would require a different store or a real Fuseki HA setup.
    max_replicas = 1

    container {
      name  = "fuseki"
      image = var.fuseki_image
      cpu   = 1.0
      # Bumped 2 → 4 GiB (2026-05-26) after observing OOM-kill restart loop in DEV.
      # Bumped 4 → 6 GiB (2026-05-27) after memory_high alert fired the next day —
      # Fuseki crossed 3.4 GiB (85% of 4 GiB) sustained 15m. Underlying cause still
      # unexplored (Fuseki JVM heap config or dataset growth); bump again to buy
      # headroom. If we see the alert at 5.1 GiB (85% of 6) revisit by either:
      #   - investigating Fuseki -Xmx / dataset size,
      #   - splitting dev/test data smaller,
      #   - or accepting 8+ GiB.
      memory = "6Gi"

      volume_mounts {
        name = "fuseki-data"
        path = "/opt/fuseki/run/databases"
      }

      # Generous startup grace so cold-start AzureFile mount + JVM warmup don't
      # cascade into liveness restarts.
      # Note: Container Apps caps failure_count_threshold at 30. Using 60s
      # interval × 30 threshold = 30 min grace, covering the observed ~22 min
      # cold-start gap with margin.
      startup_probe {
        transport               = "HTTP"
        port                    = 3030
        path                    = "/$/ping"
        interval_seconds        = 60
        failure_count_threshold = 30
        timeout                 = 5
      }

      liveness_probe {
        transport        = "HTTP"
        port             = 3030
        path             = "/$/ping"
        interval_seconds = 30
      }

      readiness_probe {
        transport        = "HTTP"
        port             = 3030
        path             = "/$/ping"
        interval_seconds = 10
      }
    }

    volume {
      name         = "fuseki-data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.fuseki[0].name
    }
  }

  ingress {
    external_enabled = false
    target_port      = 3030
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Fuseki"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    ignore_changes = [
      template[0].container[0].image
    ]
  }

  depends_on = [
    azurerm_container_app_environment_storage.fuseki
  ]
}

# Output the URLs for use by the backend
output "postgres_jdbc_url" {
  description = "JDBC URL for PostgreSQL Flexible Server"
  value       = var.deploy_postgres ? "jdbc:postgresql://${azurerm_postgresql_flexible_server.tool[0].fqdn}:5432/${var.postgres_db_name}?sslmode=require" : var.postgres_url
}

output "postgres_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server"
  value       = var.deploy_postgres ? azurerm_postgresql_flexible_server.tool[0].fqdn : null
}

output "fuseki_internal_url" {
  description = "Internal URL for Fuseki"
  value       = var.deploy_fuseki ? "https://ismd-tool-fuseki-${var.environment}.internal.${var.container_app_environment_default_domain}/ismd-tool-dataset" : var.fuseki_url
}

# Postgres databases for the tool stack.
#
# The SERVER itself lives in modules/postgres (extracted 2026-08-12) — it is a
# shared per-env resource backing tool, keycloak and the AI app, so "tool" no
# longer owns it. This module only creates the databases it needs, against the
# server id injected from the env root. Server-level config (extensions, idle
# timeouts) and the firewall rules moved with the server.
#
# Per-app LOGIN roles are created by SQL, not Terraform — see db/user-separation/.

# Create the application database
resource "azurerm_postgresql_flexible_server_database" "tool" {
  count     = var.deploy_postgres ? 1 : 0
  name      = var.postgres_db_name
  server_id = var.postgres_server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_database" "keycloak" {
  count     = var.deploy_postgres && var.deploy_keycloak ? 1 : 0
  name      = var.keycloak_db_name
  server_id = var.postgres_server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
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
  value       = var.deploy_postgres ? "jdbc:postgresql://${var.postgres_fqdn}:5432/${var.postgres_db_name}?sslmode=require" : var.postgres_url
}

output "postgres_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server"
  value       = var.deploy_postgres ? var.postgres_fqdn : null
}

output "fuseki_internal_url" {
  description = "Internal URL for Fuseki"
  value       = var.deploy_fuseki ? "https://ismd-tool-fuseki-${var.environment}.internal.${var.container_app_environment_default_domain}/ismd-tool-dataset" : var.fuseki_url
}

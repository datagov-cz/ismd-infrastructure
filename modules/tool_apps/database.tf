# Azure Database for PostgreSQL Flexible Server
# Managed service with automatic backups, HA options, and persistent storage

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
  zone = var.environment == "prod" ? "1" : null

  # Public access for simplicity (can be restricted later with firewall rules)
  public_network_access_enabled = true

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Database"
    ManagedBy   = "Terraform"
  }

  # Note: prevent_destroy cannot use variables, set to false for now
  # For prod, consider using a separate module or manual protection
  lifecycle {
    prevent_destroy = false
    ignore_changes = [
      zone # Zone cannot be changed after creation
    ]
  }
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

# Firewall rule to allow Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  count            = var.deploy_postgres ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.tool[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Firewall rule to allow all IPs for dev (restrict in prod)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_all_dev" {
  count            = var.deploy_postgres && var.environment == "dev" ? 1 : 0
  name             = "AllowAllForDev"
  server_id        = azurerm_postgresql_flexible_server.tool[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# Storage Account for Fuseki data persistence
resource "azurerm_storage_account" "fuseki" {
  count                    = var.deploy_fuseki ? 1 : 0
  name                     = "ismdtoolfuseki${var.environment}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "GRS" : "LRS"

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
    max_replicas = 1

    container {
      name   = "fuseki"
      image  = var.fuseki_image
      cpu    = 0.5
      memory = "1Gi"

      volume_mounts {
        name = "fuseki-data"
        path = "/opt/fuseki/run/databases"
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
  value       = var.deploy_fuseki ? "https://ismd-tool-fuseki-${var.environment}.internal.${var.container_app_environment_default_domain}/ds" : var.fuseki_url
}

# Logical-backup storage — destination for per-database pg_dump files.
#
# WHY THIS EXISTS: the server's automatic backup (backup_retention_days on the
# server resource) restores the WHOLE SERVER to a NEW server. It cannot put one
# database back, and this server carries three tenants (ismd_tool_db, keycloak_db,
# ismd_ai). It also cannot copy one database into another environment. Weekly
# logical dumps cover both; see POSTGRES-LOGICAL-BACKUP-PLAN.md in the workspace.
#
# This file is slice 1: storage only. The Container App Job that writes here is
# slice 2, and it will encrypt each dump with ismd-kv-<env>/pg-backup-encryption-key
# before upload (keycloak_db holds names, e-mails, password hashes, BSI pseudonyms
# and brokered CAAIS/NIA tokens).
#
# Retention is enforced by the lifecycle policy, NOT by the job:
#   weekly/   14 days
#   monthly/  90 days
#
# IMMUTABILITY + LIFECYCLE MUST AGREE. A blob cannot be deleted while it is inside
# its immutability window, so each container's immutability period matches its
# lifecycle delete age exactly. Shorten one without the other and the lifecycle
# rule silently fails, leaving blobs forever.
#
# The policies are deliberately UNLOCKED: an unlocked policy can be shortened or
# removed, a locked one never can, by anyone, for any reason. Locking is a separate
# decision once the shape has proven itself.

resource "azurerm_storage_account" "backup" {
  count               = var.enable_logical_backups ? 1 : 0
  name                = "ismdpgbackup${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = var.environment == "prod" ? "GRS" : "LRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # the job authenticates with the account key

  blob_properties {
    # Versioning keeps an overwritten or deleted blob recoverable independently of
    # the immutability window. Cheap at these sizes (dumps are single-digit MB).
    versioning_enabled = true
  }

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "DatabaseBackup"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_storage_container" "backup_weekly" {
  count                 = var.enable_logical_backups ? 1 : 0
  name                  = "weekly"
  storage_account_id    = azurerm_storage_account.backup[0].id
  container_access_type = "private"
}

resource "azurerm_storage_container" "backup_monthly" {
  count                 = var.enable_logical_backups ? 1 : 0
  name                  = "monthly"
  storage_account_id    = azurerm_storage_account.backup[0].id
  container_access_type = "private"
}

resource "azurerm_storage_container_immutability_policy" "backup_weekly" {
  count                                 = var.enable_logical_backups ? 1 : 0
  storage_container_resource_manager_id = azurerm_storage_container.backup_weekly[0].id
  immutability_period_in_days           = var.backup_weekly_retention_days
  protected_append_writes_all_enabled   = false
  locked                                = false
}

resource "azurerm_storage_container_immutability_policy" "backup_monthly" {
  count                                 = var.enable_logical_backups ? 1 : 0
  storage_container_resource_manager_id = azurerm_storage_container.backup_monthly[0].id
  immutability_period_in_days           = var.backup_monthly_retention_days
  protected_append_writes_all_enabled   = false
  locked                                = false
}

# Retention. One rule per prefix; the version rules matter because versioning is on
# and an old version would otherwise outlive the blob it belongs to.
resource "azurerm_storage_management_policy" "backup" {
  count              = var.enable_logical_backups ? 1 : 0
  storage_account_id = azurerm_storage_account.backup[0].id

  rule {
    name    = "weekly-retention"
    enabled = true

    filters {
      prefix_match = ["weekly/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = var.backup_weekly_retention_days
      }
      version {
        delete_after_days_since_creation = var.backup_weekly_retention_days
      }
    }
  }

  rule {
    name    = "monthly-retention"
    enabled = true

    filters {
      prefix_match = ["monthly/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = var.backup_monthly_retention_days
      }
      version {
        delete_after_days_since_creation = var.backup_monthly_retention_days
      }
    }
  }
}

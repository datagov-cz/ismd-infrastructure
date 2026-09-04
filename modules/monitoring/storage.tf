# Monitoring storage account — per-env home for monitoring-related persistent data.
#
# Currently holds:
#   1. Alert-state table — alertId → Teams message ID mapping. Currently UNUSED;
#      Logic App update-in-place flow was reverted pending Key Vault adoption
#      (see logic_app.tf for rationale). Kept here as a foundation placeholder.
#   2. Future env-scoped log archival (CAE diagnostic settings → blob, ACS Email
#      operational logs, etc.) — none wired yet.
#
# AppGW access logs do NOT live here. AppGW is a global resource and its logs
# ship to a dedicated storage account in shared-global (see modules/shared_global).
#
# Cost: ~$0/mo at our volumes (LRS standard, no minimum charge in this region).

resource "azurerm_storage_account" "monitoring" {
  name                     = "ismdmonitoring${var.environment}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS" # Monitoring data is non-critical; ZRS/GRS would burn money for no benefit.

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # Required by Logic App table connector + Diagnostic Settings export.

  blob_properties {
    delete_retention_policy {
      days = 7 # Soft-delete window for accidental blob deletions.
    }
  }

  tags = local.common_tags
}

# Alert-state table — alertId → Teams message ID mapping for update-in-place flow.
# Currently unused by the Logic App; created so the schema is ready when the Logic
# App refactor lands (via KV-stored credential).
resource "azurerm_storage_table" "alert_state" {
  name               = "alertstate"
  storage_account_id = azurerm_storage_account.monitoring.id
}

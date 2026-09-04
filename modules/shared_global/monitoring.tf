# Shared-global monitoring — storage for AppGW access logs + diagnostic settings.
#
# AppGW is a single global resource serving dev/test/prod. Its access logs are
# high-volume per-request data that's rarely queried, so we ship them to blob
# storage (not Log Analytics) for cheap retention with a 90-day lifecycle.
#
# WAF is enabled (Prevention mode), so the firewall log is collected too. Both
# AccessLog and FirewallLog ship to this blob storage account with a 90-day
# lifecycle:
#   Application Gateway → Storage Account (AccessLog, 90d retention)
#   Application Gateway → Storage Account (FirewallLog, 90d retention)

resource "azurerm_storage_account" "monitoring" {
  name                     = "ismdmonglobal"
  resource_group_name      = azurerm_resource_group.shared_global.name
  location                 = azurerm_resource_group.shared_global.location
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS" # Non-critical access logs; LRS is the cheap tier.

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # Required for Diagnostic Settings export.

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = {
    Environment = "shared-global"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
  }
}

# NOTE: Azure Monitor diagnostic settings shipping to a storage account always
# write to an auto-created container named by convention:
#   insights-logs-<category-in-lowercase>
# For ApplicationGatewayAccessLog that's `insights-logs-applicationgatewayaccesslog`.
# Terraform cannot create or manage that container (Azure manages it as part of
# the diag setting), so we don't define an azurerm_storage_container here. The
# lifecycle rule below targets that auto-container's prefix.

# 90-day lifecycle on AppGW access logs. Logs older than that are auto-deleted
# from the hot tier directly (no archive tier transitions at our scale).
# Adjust if the client surfaces a compliance retention requirement.
resource "azurerm_storage_management_policy" "monitoring" {
  storage_account_id = azurerm_storage_account.monitoring.id

  rule {
    name    = "appgw-access-logs-90d"
    enabled = true
    filters {
      prefix_match = ["insights-logs-applicationgatewayaccesslog/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 90
      }
    }
  }

  rule {
    name    = "appgw-firewall-logs-90d"
    enabled = true
    filters {
      prefix_match = ["insights-logs-applicationgatewayfirewalllog/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 90
      }
    }
  }
}

# Diagnostic setting on the AppGW: ship AccessLog (per-request access logs) and
# FirewallLog (WAF matched/blocked requests) to the storage account.
# PerformanceLog skipped — already covered by metrics. FirewallLog is collected
# because the WAF runs in Prevention (blocking) mode; without it there'd be no
# way to see or tune what the WAF blocks.
resource "azurerm_monitor_diagnostic_setting" "appgw_access" {
  name               = "diag-appgw-access-to-storage"
  target_resource_id = azurerm_application_gateway.appgw.id
  storage_account_id = azurerm_storage_account.monitoring.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  # Metrics are already collected platform-side; no need to duplicate to storage.
}

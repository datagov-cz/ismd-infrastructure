# PostgreSQL Flexible Server alerts.
#
# Different metric namespace from Container Apps:
#   Microsoft.DBforPostgreSQL/flexibleServers
#
# The DB is a single point of failure for the tool app — outage = tool down.
# is_db_alive is paging-tier; CPU/memory/storage saturation are quiet warnings.

# --- DB unreachable / replica health ---------------------------------------
# is_db_alive emits 1 when the engine is responsive, 0 when not. Sustained 0
# for 5m means the tool app is broken.
resource "azurerm_monitor_metric_alert" "postgres_db_alive" {
  for_each = var.postgres_servers

  name                = "al-dia-${each.key}-db-alive-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "PostgreSQL server ${each.value.name} is not responding to health probes.${local.runbook_link["postgres-db-alive"]}"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "is_db_alive"
    aggregation      = "Minimum"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = local.enable_paging ? azurerm_monitor_action_group.paging[0].id : azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- CPU sustained high -----------------------------------------------------
resource "azurerm_monitor_metric_alert" "postgres_cpu_high" {
  for_each = var.postgres_servers

  name                = "al-dia-${each.key}-cpu-high-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "PostgreSQL CPU > 80% sustained 15m on ${each.value.name}. Slow queries or hot loop in app code likely; investigate via pg_stat_activity.${local.runbook_link["postgres-cpu-high"]}"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- Memory sustained high --------------------------------------------------
resource "azurerm_monitor_metric_alert" "postgres_memory_high" {
  for_each = var.postgres_servers

  name                = "al-dia-${each.key}-memory-high-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "PostgreSQL memory > 85% sustained 15m on ${each.value.name}. May indicate undersized SKU or runaway connections.${local.runbook_link["postgres-memory-high"]}"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "memory_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- Storage near full ------------------------------------------------------
# storage_percent > 85% gives lead time to scale up the disk before writes start
# failing at 100%. Sustained 30m to avoid alerting on temporary write bursts.
resource "azurerm_monitor_metric_alert" "postgres_storage_high" {
  for_each = var.postgres_servers

  name                = "al-dia-${each.key}-storage-high-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "PostgreSQL storage > 85% on ${each.value.name}. Scale up disk before it hits 100% and blocks writes.${local.runbook_link["postgres-storage-high"]}"
  severity            = 2
  frequency           = "PT15M"
  window_size         = "PT30M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- Connection failures ----------------------------------------------------
# Multiple connection_failed events in 5m = auth misconfiguration, app
# misconfiguration, or network issue.
resource "azurerm_monitor_metric_alert" "postgres_connection_failures" {
  for_each = var.postgres_servers

  name                = "al-dia-${each.key}-connection-failures-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "PostgreSQL connection failures > 5 in 5m on ${each.value.name}. App-side misconfig (wrong password, exhausted pool) or network issue.${local.runbook_link["postgres-connection-failures"]}"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "connections_failed"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# Container App alert rules — parameterized over var.container_apps.
#
# All rules point at the quiet action group by default. Paging-tier upgrades
# (e.g. "Replicas below min in PROD") are handled by a separate paging-scoped
# alert variant where applicable.

# --- App down: replica count drops to zero ---------------------------------
# Replicas metric reflects current running replica count. Threshold 0 = app
# has nothing serving traffic. Sustained 5 min to ride out normal restart blips.
resource "azurerm_monitor_metric_alert" "replicas_zero" {
  for_each = var.container_apps

  name                = "al-dia-${each.key}-replicas-zero-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "Replica count on ${each.value.name} is zero (app is not serving).${local.runbook_link["replicas-zero"]}"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.app/containerapps"
    metric_name      = "Replicas"
    aggregation      = "Average"
    operator         = "LessThanOrEqual"
    threshold        = 0
  }

  action {
    # PROD paging upgrade: if paging action group exists in this env, use it.
    action_group_id = local.enable_paging ? azurerm_monitor_action_group.paging[0].id : azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- HTTP 5xx errors --------------------------------------------------------
# Fires when 5xx requests > 0 in a 5-min window. Quiet tier — backends can blip,
# real signal is sustained. Threshold of 0 catches any 5xx; tune if too noisy.
resource "azurerm_monitor_metric_alert" "http_5xx" {
  for_each = var.container_apps

  name                = "al-dia-${each.key}-5xx-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "HTTP 5xx responses on ${each.value.name}.${local.runbook_link["http-5xx"]}"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.app/containerapps"
    metric_name      = "Requests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "statusCodeCategory"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- CPU sustained high -----------------------------------------------------
# CPU usage in nanocores; expressed as percentage of container's allocated CPU
# is awkward without knowing the allocation. Using raw nanocores with a coarse
# threshold; revisit per-app once we have baseline data.
resource "azurerm_monitor_metric_alert" "cpu_high" {
  for_each = var.container_apps

  name                = "al-dia-${each.key}-cpu-high-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "CPU usage sustained high on ${each.value.name} (>80% of 1 vCPU equivalent over 15m).${local.runbook_link["cpu-high"]}"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.app/containerapps"
    metric_name      = "UsageNanoCores"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 800000000 # 0.8 vCPU equivalent in nanocores
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- Restart count ----------------------------------------------------------
# RestartCount is cumulative replica restarts in the window. The plan calls for
# >3 in 15m. Normal deploy = revision rollover bumps this briefly; the 15m
# window absorbs a typical rollover (~1-2 restarts).
resource "azurerm_monitor_metric_alert" "restart_count" {
  for_each = var.container_apps

  name                = "al-dia-${each.key}-restart-count-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "Replicas on ${each.value.name} are restarting (>3 in 15m). Could be a crashloop or aggressive readiness-probe failures.${local.runbook_link["restart-count"]}"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.app/containerapps"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 3
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- p95 latency ------------------------------------------------------------
# DEFERRED. Container Apps does not expose a latency metric at the platform
# level — the Requests metric is request-count only, not duration. Per-app p95
# latency requires App Insights `requests` (with `duration` field), which in
# turn requires the Next.js + Java apps to be fully AI-instrumented.
# Once that lands, add a scheduled KQL alert on
# `requests | summarize percentile(duration, 95) by cloud_RoleName`
# with threshold 2000ms over a 10m window.

# --- Memory sustained high --------------------------------------------------
# Threshold computed as 85% of the container's memory allocation declared in
# var.container_apps[<key>].memory_gib. This means the alert scales with the
# app's actual sizing — bumping fuseki from 2 to 4 GiB automatically moved the
# alert from "1.7 GiB" to "3.4 GiB" without manual tuning.
# At 85%, the alert lands well before the container OOM-killer kicks in,
# giving headroom to investigate.
resource "azurerm_monitor_metric_alert" "memory_high" {
  for_each = var.container_apps

  name                = "al-dia-${each.key}-memory-high-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.id]
  description         = "Memory usage sustained high on ${each.value.name} (>85% of ${each.value.memory_gib} GiB allocation, sustained 15m).${local.runbook_link["memory-high"]}"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.app/containerapps"
    metric_name      = "WorkingSetBytes"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = floor(each.value.memory_gib * 1073741824 * 0.85) # 85% of memory_gib in bytes
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

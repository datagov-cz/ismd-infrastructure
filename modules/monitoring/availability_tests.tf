# Availability alerts.
#
# IMPORTANT: We do NOT use App Insights Standard Web Tests. They depend on a
# Microsoft-managed WinHTTP client that fails with "The function requested is
# not supported" against our AppGW (HTTP/2 ALPN incompatibility). Documented
# fully in docs/HANDOVER-monitoring.md § "Availability monitoring — design
# decision (2026-05-26)".
#
# Instead, a custom uptime probe Logic App (see uptime_probe.tf) posts
# `Microsoft.ApplicationInsights.Availability` events to AI's /v2/track
# endpoint. Those events land in the same `availabilityResults` table that
# Standard Tests use, so:
#   - the AI portal's Availability blade renders them natively
#   - the `availabilityResults/availabilityPercentage` metric is computed
#   - the metric alerts below fire on failures
# Same alerting pipeline, different probe origin.

resource "azurerm_monitor_metric_alert" "availability" {
  for_each = var.availability_tests

  name                = "al-dia-availability-${each.key}-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.application_insights_id]
  description         = "Availability probe for ${each.value.url} failing (probed every 5 min from custom Logic App, results posted to AI).${local.runbook_link["availability"]}"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100

    dimension {
      name     = "availabilityResult/name"
      operator = "Include"
      values   = [each.key]
    }
  }

  action {
    action_group_id = local.enable_paging ? azurerm_monitor_action_group.paging[0].id : azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

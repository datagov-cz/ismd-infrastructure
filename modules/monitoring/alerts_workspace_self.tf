# LA workspace self-monitoring — daily ingestion approaching cap
#
# Why this matters:
# When daily ingestion hits `daily_quota_gb` on the workspace, Azure SILENTLY
# stops ingestion until UTC midnight. Log-based alerts cannot fire on data that
# is not there. This alert fires at 80% of cap so we can raise the cap before
# losing visibility during the exact incident generating the extra logs.
#
# Implementation: scheduled query against the `Usage` table, summed across the
# rolling 24h window. The Usage table is fed by Azure's own billing pipeline,
# not by ingestion, so it keeps working even if the workspace caps. There is
# typically a 60-90 min reporting lag — fine for this purpose; we want lead time
# on cap-approach, not real-time precision.
#
# Threshold: 80% of `log_analytics_daily_cap_gb`. Quantity in Usage is in MB,
# convert to GB.

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "la_ingestion_near_cap" {
  name                = "al-dia-la-ingestion-near-cap-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  description             = "Log Analytics daily ingestion at ≥80% of cap (${var.log_analytics_daily_cap_gb} GB). Raise the cap before ingestion silently stops at UTC midnight.${local.runbook_link["la-ingestion-near-cap"]}"
  severity                = local.enable_paging ? 1 : 2
  enabled                 = true
  evaluation_frequency    = "PT30M"
  window_duration         = "PT30M"
  scopes                  = [var.log_analytics_workspace_id]
  auto_mitigation_enabled = true

  criteria {
    # Sum billable ingestion over the rolling 24h window (matches the cap's daily reset semantics).
    # threshold is expressed in GB; Quantity in Usage is MB → divide by 1024.
    query = <<-KQL
      Usage
      | where TimeGenerated > ago(24h)
      | where IsBillable == true
      | summarize TotalGB = sum(Quantity) / 1024.0
    KQL

    operator                = "GreaterThanOrEqual"
    threshold               = var.log_analytics_daily_cap_gb * 0.8
    time_aggregation_method = "Total"
    metric_measure_column   = "TotalGB"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    # Paging in PROD (prevents user-visible monitoring blackout during PROD incident),
    # quiet in dev/test (informational — we'll just bump the cap).
    action_groups = [
      local.enable_paging ? azurerm_monitor_action_group.paging[0].id : azurerm_monitor_action_group.quiet.id
    ]
  }

  tags = local.common_tags
}

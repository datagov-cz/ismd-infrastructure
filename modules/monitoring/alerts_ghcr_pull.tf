# GHCR image pull failure detection
#
# Why: there is no ACR resource to monitor (we pull directly from GHCR), so the
# only signal for a failed pull is in the Container App console logs. A
# transient pull failure may self-resolve; sustained failures look like an
# expired GHCR PAT, a deleted image tag, or registry-side outage.
#
# Approach: scheduled KQL alert against ContainerAppConsoleLogs_CL for the
# string "failed to pull image" appearing across any container in the env's
# CAE. Fires on any occurrence within a 10m window — pulls are infrequent
# enough that any failure is alert-worthy.
#
# Scope: the LA workspace (not a specific container app), so a new app added
# later is covered automatically.

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "ghcr_pull_failure" {
  name                = "al-dia-ghcr-pull-failure-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  description             = "Container App reported a failed image pull from GHCR. Likely an expired PAT, deleted tag, or GHCR-side issue.${local.runbook_link["ghcr-pull-failure"]}"
  severity                = 2
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT10M"
  scopes                  = [var.log_analytics_workspace_id]
  auto_mitigation_enabled = true

  criteria {
    query = <<-KQL
      ContainerAppConsoleLogs_CL
      | where Log_s has "failed to pull image" or Log_s has "ImagePullBackOff" or Log_s has "ErrImagePull"
      | project TimeGenerated, ContainerAppName_s, RevisionName_s, Log_s
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.quiet.id]
  }

  tags = local.common_tags
}

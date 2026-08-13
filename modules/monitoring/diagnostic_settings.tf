# Diagnostic settings — ship management-plane logs to LA.
#
# Note on Container App logs: stdout/stderr from each container is already shipped
# to LA via the CAE's appLogsConfiguration (set in modules/shared). Those rows land
# in ContainerAppConsoleLogs_CL + ContainerAppSystemLogs_CL tagged with each
# CHILD app's resource ID, NOT the CAE's.
#
# This file adds the CAE-level diagnostic setting — management-plane events
# (autoscaling, control-plane activity) tagged with the CAE's resource ID. Without
# it the CAE Logs blade in the portal is empty by default.

resource "azurerm_monitor_diagnostic_setting" "cae" {
  name                       = "diag-cae-${var.environment}"
  target_resource_id         = var.container_app_environment_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # categoryGroup "allLogs" covers ContainerAppConsoleLogs + ContainerAppSystemLogs
  # at the CAE scope. Azure exposes these as enabled_log entries; we enable both.
  enabled_log {
    category_group = "allLogs"
  }

  # CAE has no metric categories worth shipping to LA (the per-app metrics live
  # on each Container App). Skip metric block.
}

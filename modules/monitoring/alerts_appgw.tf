# Application Gateway alerts.
#
# AppGW is a shared-global resource referenced via cross-state lookup
# (data.terraform_remote_state.shared_global). The env's main.tf reads the
# AppGW resource ID and passes it as var.application_gateway_id.
#
# Per the monitoring plan, AppGW alerts officially live in the prod env state
# so the prod blast radius owns them. For DEV we still wire them since the
# AppGW serves dev traffic and an outage breaks dev too — same rule set, just
# scoped to the prod env's paging recipients when prod rolls out.
#
# count = 0 when application_gateway_id is empty (e.g. an env that doesn't
# want AppGW alerts), which is the default.

locals {
  appgw_alerts_enabled = var.application_gateway_id != ""
}

# --- Backend pool unhealthy host -------------------------------------------
# UnhealthyHostCount > 0 sustained 3m on any backend pool = one or more
# Container Apps behind the gateway is failing health probes. This is the
# "users can't reach the app" signal that paging tier is reserved for.
resource "azurerm_monitor_metric_alert" "appgw_unhealthy_backend" {
  count = local.appgw_alerts_enabled ? 1 : 0

  name                = "al-dia-appgw-backend-unhealthy-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.application_gateway_id]
  description         = "Application Gateway has unhealthy hosts in a backend pool for >3 min. One or more apps are failing health probes — users likely seeing errors.${local.runbook_link["appgw-backend-unhealthy"]}"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "UnhealthyHostCount"
    aggregation      = "Average" # UnhealthyHostCount only accepts Average per the metric definition.
    operator         = "GreaterThan"
    threshold        = 0

    # Exclude backend HTTP settings for resources that are anticipatory and not
    # yet deployed (tool isn't in PROD yet — its pools always 404). When tool
    # ships to PROD, remove the corresponding exclusions.
    # When new envs/apps are added, audit this list against the AppGW config.
    dynamic "dimension" {
      for_each = length(var.appgw_excluded_backend_settings) > 0 ? [1] : []
      content {
        name     = "BackendSettingsPool"
        operator = "Exclude"
        values   = var.appgw_excluded_backend_settings
      }
    }
  }

  action {
    action_group_id = local.enable_paging ? azurerm_monitor_action_group.paging[0].id : azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- Total 5xx --------------------------------------------------------------
# AppGW response status sliced by status code. Threshold is absolute count
# rather than rate (1% per the plan) — rate-based criteria requires a
# scheduled query with two metrics, while a count threshold is a simple metric
# alert. Tune the count after observing real traffic. Sev2 quiet — duplicate
# with Container App 5xx alerts but at a different layer (gateway-vs-app).
resource "azurerm_monitor_metric_alert" "appgw_5xx" {
  count = local.appgw_alerts_enabled ? 1 : 0

  name                = "al-dia-appgw-5xx-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.application_gateway_id]
  description         = "Application Gateway 5xx responses > 5 in 5m. Could be backend issues or AppGW misconfig (listener/rule problems).${local.runbook_link["appgw-5xx"]}"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "ResponseStatus"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5

    dimension {
      name     = "HttpStatusGroup"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- TLS cert expiry --------------------------------------------------------
# NOTE: AppGW does not emit a metric for SSL certificate expiry directly.
# The cert-expiry signal we DO have is from the App Insights standard web
# tests (`ssl_cert_remaining_lifetime = 7`) which fail when the cert is <7
# days from expiry — those already alert via the availability rules. For the
# <30 day warning called for in the plan, the cleanest implementation is a
# separate availability test with a 30-day threshold (deferred), or a Key
# Vault certificate expiry alert if certs migrate to KV.

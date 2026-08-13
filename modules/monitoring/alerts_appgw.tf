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

  # The shared gateway emits metrics gateway-wide (all envs combined). To scope
  # alerts to THIS env we filter by backend, but the two metrics name the
  # dimension differently:
  #   - BackendResponseStatus  → dimension "BackendHttpSetting" (settings name alone)
  #   - UnhealthyHostCount     → dimension "BackendSettingsPool" (pool~settings, tilde-joined)
  appgw_backend_http_settings  = [for b in var.appgw_backend_settings : b.http_settings]
  appgw_backend_settings_pools = [for b in var.appgw_backend_settings : "${b.pool}~${b.http_settings}"]
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

    # Scope to THIS env's backend pools only. Without this Include filter the
    # rule spans the whole shared gateway, so a dev/test backend going unhealthy
    # would fire prod's alert. var.appgw_backend_settings deliberately omits
    # anticipatory pools (tool-prod-* before tool ships) so they don't count.
    # When new envs/apps are added, audit the list against the AppGW config.
    dynamic "dimension" {
      for_each = length(local.appgw_backend_settings_pools) > 0 ? [1] : []
      content {
        name     = "BackendSettingsPool"
        operator = "Include"
        values   = local.appgw_backend_settings_pools
      }
    }
  }

  action {
    action_group_id = local.enable_paging ? azurerm_monitor_action_group.paging[0].id : azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

# --- Backend 5xx (per-env) --------------------------------------------------
# The gateway is shared across dev/test/prod, so the gateway-wide ResponseStatus
# metric can't tell whose traffic threw a 5xx — a dev error would page prod.
# Instead we use BackendResponseStatus, which carries a BackendHttpSetting
# dimension, and Include-filter THIS env's backends. Trade-off: per Azure docs
# BackendResponseStatus counts only codes the BACKEND returned, NOT codes the
# gateway generated itself (502 backend-unreachable, WAF 403/503, listener/cert
# misconfig). Those are inherently gateway-wide and unattributable to one env;
# the backend-down case is covered per-env by appgw_unhealthy_backend + the
# Container App 5xx / availability alerts.
#
# Threshold is an absolute count (not the 1% rate in the plan) — rate criteria
# needs a two-metric scheduled query; a count threshold is a simple metric
# alert. Tune after observing real traffic. Sev2 quiet — overlaps Container App
# 5xx but at the gateway layer. With the dimension split the threshold applies
# per backend setting (any single env backend > 5 in 5m fires).
resource "azurerm_monitor_metric_alert" "appgw_5xx" {
  count = local.appgw_alerts_enabled ? 1 : 0

  name                = "al-dia-appgw-5xx-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.application_gateway_id]
  description         = "Application Gateway: a ${var.environment} backend returned > 5 5xx responses in 5m. Backend app is erroring (gateway-generated 5xx like 502/WAF are not counted here).${local.runbook_link["appgw-5xx"]}"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "BackendResponseStatus"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5

    dimension {
      name     = "HttpStatusGroup"
      operator = "Include"
      values   = ["5xx"]
    }

    # Scope to THIS env's backends. Without it the rule would still span the
    # whole gateway (every env's backends), recreating the cross-env noise.
    dynamic "dimension" {
      for_each = length(local.appgw_backend_http_settings) > 0 ? [1] : []
      content {
        name     = "BackendHttpSetting"
        operator = "Include"
        values   = local.appgw_backend_http_settings
      }
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

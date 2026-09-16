# Service Health alerts — advance notice of Azure platform maintenance.
#
# 2026-09-13 Azure patched both Postgres servers (Service Health TYGS-S5Z): CPU
# at ~100% on dev, then a restart on each. The notice existed in Service Health
# but nothing routed it anywhere, so the spike looked unexplained. The same had
# happened before with other services.
#
# No services filter: covers every Azure service in the subscription (Postgres,
# Container Apps, Key Vault, App Gateway, Log Analytics, ...). Subscription-scoped,
# so one rule covers every env; gated on enable_service_health_alerts so it is
# created in one env only.
#
# Not every platform update is announced here — Container Apps replica moves
# usually are not. This catches what Azure does publish.

resource "azurerm_monitor_activity_log_alert" "service_health" {
  count               = var.enable_service_health_alerts ? 1 : 0
  name                = "al-dia-service-health"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}"]
  description         = "Azure Service Health notice (planned maintenance, incident, action required, security) for a service in this subscription. Planned maintenance on Postgres restarts the server; Keycloak, tool backend and AI lose the database for a few minutes."

  criteria {
    category = "ServiceHealth"

    service_health {
      events    = ["Maintenance", "Incident", "ActionRequired", "Security"]
      locations = ["Germany West Central", "North Europe", "Global"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.quiet.id
  }

  tags = local.common_tags
}

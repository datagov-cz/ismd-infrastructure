# Notification switch — one alert processing rule that silences this environment's
# alerts while it is switched off (dev on/off: ismd-kv-dev/dev-enabled via terraw).
#
# One rule instead of flipping `enabled` on ~50 alert rules: the alerts keep
# evaluating, only their action groups are not called. The rule always exists
# where enable_notification_switch is set and is toggled through `enabled`, so
# switching never creates or destroys anything.
#
# Scope is the subscription, not the resource group: a processing rule matches on
# the resource an alert FIRED ON, and dev alerts fire on resources in the tool,
# validator and AI groups and on the shared App Gateway. What makes an alert
# "this environment's" is where its RULE lives — every one is created in
# resource_group_name — so the condition selects by alert rule id.
#
# al-dia-service-health is excluded: its rule lives in this group too but watches
# Azure service health for the whole subscription, which still matters while the
# environment is off. It is created outside Terraform, so it is matched by name.

data "azurerm_subscription" "current" {}

resource "azurerm_monitor_alert_processing_rule_suppression" "env_off" {
  count = var.enable_notification_switch ? 1 : 0

  name                = "apr-dia-env-off-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [data.azurerm_subscription.current.id]
  enabled             = var.suppress_notifications
  description         = "Suppresses ${var.environment} alert notifications while the environment is switched off (terraw ${var.environment} on|off)."

  condition {
    alert_rule_id {
      operator = "Contains"
      values   = ["/resourceGroups/${var.resource_group_name}/"]
    }
    alert_rule_name {
      operator = "NotEquals"
      values   = ["al-dia-service-health"]
    }
  }

  tags = local.common_tags
}

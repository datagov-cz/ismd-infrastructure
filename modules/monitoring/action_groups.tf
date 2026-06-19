# Action Groups — alert routing destinations
#
# Two tiers (per the monitoring plan):
#   - quiet:  Teams card only, no email. All envs.
#   - paging: Teams card + email to recipients. Only created when paging_email_recipients is non-empty.
#
# Both groups POST to the Logic App's HTTP trigger callback URL (managed internally
# by this module). The Logic App translates Azure Monitor common alert schema → Teams card.

resource "azurerm_monitor_action_group" "quiet" {
  name                = "ag-dia-quiet-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "diaQuiet${substr(var.environment, 0, 1)}" # max 12 chars

  webhook_receiver {
    name                    = "teams-logic-app"
    service_uri             = azurerm_logic_app_trigger_http_request.alert_in.callback_url
    use_common_alert_schema = true
  }

  tags = local.common_tags
}

resource "azurerm_monitor_action_group" "paging" {
  count               = local.enable_paging ? 1 : 0
  name                = "ag-dia-paging-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "diaPage${substr(var.environment, 0, 1)}" # max 12 chars

  dynamic "email_receiver" {
    for_each = var.paging_email_recipients
    content {
      name                    = "paging-${replace(email_receiver.value, "@", "-at-")}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  webhook_receiver {
    name                    = "teams-logic-app"
    service_uri             = azurerm_logic_app_trigger_http_request.alert_in.callback_url
    use_common_alert_schema = true
  }

  tags = local.common_tags
}

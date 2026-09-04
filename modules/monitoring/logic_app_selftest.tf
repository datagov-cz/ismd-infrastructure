# Self-test Logic App — fires a synthetic common-alert-schema payload at the main
# Logic App so the full card pipeline can be verified without waiting for a real
# alert to fire. Use cases:
#   1. Verifying changes to the card layout / localization after a terraform apply
#   2. Catching silent schema drift (Azure has changed the common alert schema before)
#   3. Catching connector auth lapses (Teams OAuth tokens expire on user identities)
#
# How to invoke:
#   - Portal: open `logic-dia-selftest-${env}` → "Run trigger" → "manual". Posts the
#     synthetic payload to the main Logic App.
#   - curl: POST any JSON body (or empty) to the callback URL exposed by the trigger.
#
# The synthetic payload exercises every field surfaced in the card so you see exactly
# what production alerts will look like — severity, status, description, resource link,
# alert-details link all get realistic values.

resource "azurerm_logic_app_workflow" "selftest" {
  name                = "logic-dia-selftest-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = local.common_tags
}

resource "azurerm_logic_app_trigger_http_request" "selftest_in" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.selftest.id

  # No required body — invokable from "Run trigger" button or with `curl -X POST <url>`.
  schema = jsonencode({
    type = "object"
  })
}

# Monthly recurrence trigger — Phase 4 of the rollout plan. Fires on the 1st of
# every month at 09:00 Prague time, exercising the full pipeline against the
# synthetic payload. Catches:
#   1. Silent common-alert-schema changes (Azure has changed the schema before)
#   2. Teams connector OAuth token lapse (user-identity tokens can expire)
#   3. Logic App misconfig drift from manual portal edits
# When the recurrence fires, you'll see a card in the channel with the
# synthetic-test description. If you do NOT see one within ~1h of the scheduled
# time, the pipeline is broken — investigate.
resource "azurerm_logic_app_trigger_recurrence" "selftest_monthly" {
  name         = "monthly"
  logic_app_id = azurerm_logic_app_workflow.selftest.id

  frequency  = "Month"
  interval   = 1
  time_zone  = "Central European Standard Time"
  start_time = "2026-06-01T09:00:00Z" # First fire: 1st June 2026 09:00 Prague-local. Subsequent firings derived from start_time + interval.

  # NOTE: `schedule` block (on_these_days/hours/minutes) is incompatible with
  # frequency = "Month" per Logic Apps' recurrence semantics. With Month frequency
  # the run cadence is purely (start_time, interval) — no sub-month scheduling.
}

# Action: HTTP POST a synthetic common-alert-schema payload to the main Logic App's
# trigger URL. The payload mirrors Azure Monitor's real schema so the main Logic App's
# card-rendering expressions see the same shape.
resource "azurerm_logic_app_action_custom" "selftest_post" {
  name         = "Post_synthetic_alert_to_main"
  logic_app_id = azurerm_logic_app_workflow.selftest.id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "POST"
      uri    = azurerm_logic_app_trigger_http_request.alert_in.callback_url
      body = {
        schemaId = "azureMonitorCommonAlertSchema"
        data = {
          essentials = {
            # alertId is synthesized — it does NOT correspond to a real alert instance
            # in Microsoft.AlertsManagement, so the "View alert details" link will 404.
            # That's expected: the link only resolves for alerts Azure Monitor itself
            # fires. For self-tests, treat the link as inert.
            alertId          = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.AlertsManagement/alerts/synthetic-${var.environment}"
            alertRule        = "al-dia-selftest-${var.environment}"
            severity         = "Sev2"
            signalType       = "Synthetic"
            monitorCondition = "Fired"
            monitorService   = "Self-test"
            # Point alertTargetIDs at the App Insights resource so the "Zdroj" link
            # lands on a real Azure resource for visual realism. (For real alerts
            # this is the rule's scope — Container App, AI resource, etc.)
            alertTargetIDs      = [var.application_insights_id]
            originAlertId       = "synthetic-${var.environment}"
            firedDateTime       = "@{utcNow()}"
            description         = local.s.selftest_subtitle
            essentialsVersion   = "1.0"
            alertContextVersion = "1.0"
          }
          alertContext = {}
        }
      }
    }
    runAfter = {}
  })

  depends_on = [
    azurerm_logic_app_trigger_http_request.selftest_in,
  ]
}

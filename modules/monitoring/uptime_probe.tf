# Custom external uptime probe — replacement for App Insights Standard Web Tests.
#
# See docs/HANDOVER-monitoring.md § "Availability monitoring — design decision".
# tl;dr: Standard Web Tests fail against our AppGW because of HTTP/2 ALPN.
# This Logic App probes URLs every 5 min and posts custom Availability events
# to AI's /v2/track endpoint, so AI's native portal blade still renders the
# data and existing alert rules still fire.
#
# Architecture:
#   Recurrence trigger (5 min)
#     ├─ Probe_<url1>     (parallel HTTP GET)
#     ├─ Probe_<url2>     (parallel HTTP GET)
#     └─ Probe_<urlN>     (parallel HTTP GET)
#   then for each URL:
#     Post_avail_<urlN>   (runs after Probe_<urlN>, regardless of success/fail)
#       — POSTs a Microsoft.ApplicationInsights.Availability event
#         with success = (statusCode == 200) and duration measured from the probe
#
# Cost: ~$0.50–1/mo per env (Logic App Consumption actions + tiny AI ingestion).

locals {
  # Action-name-safe slug. Logic App action names must be letters/numbers/_/-
  # but the workflow JSON treats `-` specially in some expressions, so use _.
  uptime_action_names = {
    for k, _ in var.availability_tests : k => replace(k, "-", "_")
  }
}

resource "azurerm_logic_app_workflow" "uptime" {
  count = length(var.availability_tests) > 0 ? 1 : 0

  name                = "logic-dia-uptime-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = local.common_tags
}

resource "azurerm_logic_app_trigger_recurrence" "uptime_5min" {
  count = length(var.availability_tests) > 0 ? 1 : 0

  name         = "Every_5_min"
  logic_app_id = azurerm_logic_app_workflow.uptime[0].id

  frequency = "Minute"
  interval  = 5
}

# One probe action per URL. Each is an HTTP GET that captures the status code
# (and start/end timestamps via Logic App's built-in `actions()` output for
# duration tracking). `runAfter = {}` means all probe actions run in parallel
# directly after the trigger.
resource "azurerm_logic_app_action_custom" "probe" {
  for_each = var.availability_tests

  name         = "Probe_${local.uptime_action_names[each.key]}"
  logic_app_id = azurerm_logic_app_workflow.uptime[0].id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "GET"
      uri    = each.value.url
    }
    runAfter = {}
  })

  depends_on = [
    azurerm_logic_app_trigger_recurrence.uptime_5min,
  ]
}

# One AI custom-availability post per URL. Runs after the corresponding probe
# regardless of probe success/failure (so a 5xx response still records as a
# failed availability event in AI). Maps:
#   - probe statusCode == 200 → success = true
#   - else                    → success = false
# Duration is derived from probe action's startTime/endTime ticks (ISO 8601 PT_S).
resource "azurerm_logic_app_action_custom" "post_avail" {
  for_each = var.availability_tests

  name         = "Post_avail_${local.uptime_action_names[each.key]}"
  logic_app_id = azurerm_logic_app_workflow.uptime[0].id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "POST"
      uri    = "https://dc.services.visualstudio.com/v2/track"
      headers = {
        "Content-Type" = "application/json"
      }
      body = {
        name = "Microsoft.ApplicationInsights.Availability"
        time = "@{utcNow()}"
        iKey = var.app_insights_instrumentation_key
        tags = {
          "ai.operation.id" = "@{guid()}"
        }
        data = {
          baseType = "AvailabilityData"
          baseData = {
            ver  = 2
            id   = "@{guid()}"
            name = each.key
            # AI ingest expects .NET TimeSpan format (dd.hh:mm:ss.fffffff), NOT ISO 8601 PT_S.
            # We compute the probe's elapsed time in seconds via ticks() math, add it to
            # the epoch 0001-01-01, then format as HH:mm:ss.fffffff (which gives the right
            # shape because seconds-as-HH:mm:ss is exactly TimeSpan formatting).
            duration     = "@{formatDateTime(addToTime('0001-01-01T00:00:00Z', div(sub(ticks(actions('Probe_${local.uptime_action_names[each.key]}')?['endTime']), ticks(actions('Probe_${local.uptime_action_names[each.key]}')?['startTime'])), 10000000), 'Second'), 'HH:mm:ss.fffffff')}"
            success      = "@{equals(coalesce(outputs('Probe_${local.uptime_action_names[each.key]}')?['statusCode'], 0), 200)}"
            runLocation  = var.location
            message      = "@{string(coalesce(outputs('Probe_${local.uptime_action_names[each.key]}')?['statusCode'], 'no-response'))}"
            properties   = {}
            measurements = {}
          }
        }
      }
    }
    runAfter = {
      "Probe_${local.uptime_action_names[each.key]}" = ["Succeeded", "Failed", "TimedOut"]
    }
  })

  depends_on = [
    azurerm_logic_app_action_custom.probe,
  ]
}

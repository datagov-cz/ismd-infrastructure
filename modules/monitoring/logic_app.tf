# Logic App that translates Azure Monitor "common alert schema" → Teams channel post.
#
# Behavior:
#   - Fired (or any non-Resolved state) → post a top-level card to the channel.
#   - Resolved + paging-tier (Sev0/Sev1) → post a top-level "all clear" card.
#     The card itself reflects the resolved state (status "✅ Vyřešeno", time
#     uses resolvedDateTime) because the content is shared with Fired.
#   - Resolved + low-tier (Sev2/Sev3/Sev4) → skip. Channel stays clean of
#     "Aktivní → Vyřešeno" duplicate pairs for routine warnings; rely on the
#     Azure portal alert details if you want to see auto-mitigation timing.
#
# Update-in-place (true single-card flip) was prototyped but reverted — it required
# either escalating the terraform SP's RBAC (rejected on security grounds) or
# storing a long-lived SAS token in tfstate (rejected pending Key Vault adoption).
# Revisit once KV-backed credentials are established. The alertstate table in
# storage.tf is kept as a placeholder.
#
# Manual post-apply step (unavoidable Microsoft API design):
#   Open the Teams API Connection resource in the portal → click "Authorize" →
#   sign in with the identity that will own the connection (shared/team account
#   preferred). Until this step, the Logic App will fail at the post action
#   because the connector has no auth token.

# Teams connector — Office 365 / Microsoft Teams managed API
resource "azurerm_api_connection" "teams" {
  name                = "apic-teams-${var.environment}"
  resource_group_name = var.resource_group_name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/teams"

  display_name = "Teams (DIA Alerts ${upper(var.environment)})"

  lifecycle {
    ignore_changes = [
      parameter_values,
    ]
  }

  tags = local.common_tags
}

# Subscription context for building the managed API ID
data "azurerm_client_config" "current" {}

# The Logic App workflow
resource "azurerm_logic_app_workflow" "teams_notifier" {
  name                = "logic-dia-teams-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  workflow_parameters = {
    "$connections" = jsonencode({
      defaultValue = {}
      type         = "Object"
    })
  }

  parameters = {
    "$connections" = jsonencode({
      teams = {
        connectionId   = azurerm_api_connection.teams.id
        connectionName = "teams"
        id             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/teams"
      }
    })
  }

  tags = local.common_tags
}

# HTTP trigger that receives Azure Monitor common alert schema POSTs
resource "azurerm_logic_app_trigger_http_request" "alert_in" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.teams_notifier.id

  schema = jsonencode({
    type = "object"
    properties = {
      data = {
        type = "object"
      }
    }
  })
}

# Top-level If: post the card unless (Resolved AND severity ∈ {Sev2,Sev3,Sev4}).
# Inverting the skip predicate to a post predicate so the "post" branch is the
# explicit one and the "skip" branch is the empty else.
resource "azurerm_logic_app_action_custom" "process_alert" {
  name         = "Process_alert"
  logic_app_id = azurerm_logic_app_workflow.teams_notifier.id

  body = jsonencode({
    type = "If"
    expression = {
      or = [
        # Not a Resolved event → always post.
        {
          not = [
            {
              equals = [
                "@triggerBody()?['data']?['essentials']?['monitorCondition']",
                "Resolved"
              ]
            }
          ]
        },
        # Resolved AND paging-tier severity → still post (the "all clear" matters).
        {
          contains = [
            "Sev0,Sev1",
            "@triggerBody()?['data']?['essentials']?['severity']"
          ]
        }
      ]
    }
    actions = {
      Post_alert_to_channel = {
        type = "ApiConnection"
        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['teams']['connectionId']"
            }
          }
          method = "post"
          path   = "/beta/teams/${var.teams_group_id}/channels/${var.teams_channel_id}/messages"
          body = {
            body = {
              content     = local.card_content_full
              contentType = "html"
            }
          }
        }
        runAfter = {}
      }
    }
    else = {
      actions = {}
    }
    runAfter = {}
  })

  depends_on = [
    azurerm_logic_app_trigger_http_request.alert_in,
  ]
}

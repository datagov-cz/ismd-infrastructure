# Monitoring module — composition root
# See README.md for layout and phase rollout.

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
  }

  # Whether to create the paging-tier action group
  enable_paging = length(var.paging_email_recipients) > 0

  # Base URL for runbook links injected into alert descriptions. Each alert
  # appends `<a href="${runbook_url_base}<slug>.md">📖 Runbook</a>` to its
  # description so the Teams card has a clickable jump-to-runbook.
  # Update this if the repo or branch changes.
  runbook_url_base = "https://github.com/datagov-cz/ismd-infrastructure/blob/main/docs/runbooks/"

  # Helper: render the runbook anchor for a given slug. Used in alert descriptions.
  runbook_link = {
    for slug in [
      "replicas-zero", "http-5xx", "cpu-high", "memory-high", "restart-count",
      "postgres-db-alive", "postgres-cpu-high", "postgres-memory-high",
      "postgres-storage-high", "postgres-connection-failures",
      "appgw-backend-unhealthy", "appgw-5xx", "availability",
      "la-ingestion-near-cap", "ghcr-pull-failure",
    ] : slug => " <a href=\"${local.runbook_url_base}${slug}.md\">📖 Runbook</a>"
  }

  # Teams card localization. Static labels are baked in at terraform-time;
  # runtime fields (severity, monitorCondition) are mapped via Logic App
  # workflow expressions using the JSON literals below.
  card_strings = {
    cs = {
      header            = "🚨 DIA upozornění"
      rule              = "Pravidlo"
      status            = "Stav"
      description       = "Popis"
      signal            = "Signál"
      resource          = "Zdroj"
      view_link         = "Zobrazit detaily v Azure Portálu →"
      at                = "v"
      via               = "přes"
      selftest_subtitle = "Syntetický test — ověřuje cestu Logic App → Teams. Odkaz 'Zobrazit detaily' nefunguje (alert v Azure Monitoru neexistuje)."
      severity_map = {
        Sev0 = "🔴 Kritické · Paging"
        Sev1 = "🟠 Vysoké · Paging"
        Sev2 = "🟡 Střední · Quiet"
        Sev3 = "🔵 Nízké · Quiet"
        Sev4 = "⚪ Informační · Quiet"
      }
      condition_map = {
        Fired    = "🔥 Aktivní"
        Resolved = "✅ Vyřešeno"
      }
    }
    en = {
      header            = "🚨 DIA Alert"
      rule              = "Rule"
      status            = "Status"
      description       = "Description"
      signal            = "Signal"
      resource          = "Resource"
      view_link         = "View alert details in Azure Portal →"
      at                = "at"
      via               = "via"
      selftest_subtitle = "Synthetic test — verifies Logic App → Teams path. The 'View alert details' link will not work (no real alert exists in Azure Monitor)."
      severity_map = {
        Sev0 = "🔴 Critical · Paging"
        Sev1 = "🟠 High · Paging"
        Sev2 = "🟡 Medium · Quiet"
        Sev3 = "🔵 Low · Quiet"
        Sev4 = "⚪ Info · Quiet"
      }
      condition_map = {
        Fired    = "🔥 Firing"
        Resolved = "✅ Resolved"
      }
    }
  }

  s = local.card_strings[var.alert_card_language]

  # Severity / status maps as Logic App workflow expressions — JSON literals
  # embedded into the card content; index by the runtime field. Wrapped with
  # coalesce so an unknown value renders the raw severity instead of empty.
  severity_lookup  = "@{coalesce(json('${replace(jsonencode(local.s.severity_map), "'", "''")}')?[triggerBody()?['data']?['essentials']?['severity']], triggerBody()?['data']?['essentials']?['severity'])}"
  condition_lookup = "@{coalesce(json('${replace(jsonencode(local.s.condition_map), "'", "''")}')?[triggerBody()?['data']?['essentials']?['monitorCondition']], triggerBody()?['data']?['essentials']?['monitorCondition'])}"

  # Full alert card content (used for top-level Fired post). Localized labels,
  # localized severity + status, status timestamp adjusted for Resolved using
  # resolvedDateTime, monitorService omitted when empty, portal deep-links.
  card_content_full = join("", [
    "<p><b>${local.s.header} — ${upper(var.environment)} — </b>${local.severity_lookup}</p>",
    "<p><b>${local.s.rule}:</b> @{triggerBody()?['data']?['essentials']?['alertRule']}</p>",
    "<p><b>${local.s.status}:</b> ${local.condition_lookup} ${local.s.at} @{convertTimeZone(if(equals(triggerBody()?['data']?['essentials']?['monitorCondition'], 'Resolved'), coalesce(triggerBody()?['data']?['essentials']?['resolvedDateTime'], triggerBody()?['data']?['essentials']?['firedDateTime']), triggerBody()?['data']?['essentials']?['firedDateTime']), 'UTC', 'Central European Standard Time', 'yyyy-MM-dd HH:mm:ss')}</p>",
    "<p><b>${local.s.description}:</b> @{triggerBody()?['data']?['essentials']?['description']}</p>",
    "<p><b>${local.s.signal}:</b> @{triggerBody()?['data']?['essentials']?['signalType']}@{if(empty(triggerBody()?['data']?['essentials']?['monitorService']), '', concat(' ${local.s.via} ', triggerBody()?['data']?['essentials']?['monitorService']))}</p>",
    "<p><b>${local.s.resource}:</b> <a href=\"https://portal.azure.com/#@/resource@{triggerBody()?['data']?['essentials']?['alertTargetIDs']?[0]}/overview\">@{last(split(string(triggerBody()?['data']?['essentials']?['alertTargetIDs']?[0]), '/'))}</a></p>",
    "<p>🔗 <a href=\"https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AlertDetailsTemplateBlade/alertId/@{encodeUriComponent(triggerBody()?['data']?['essentials']?['alertId'])}\">${local.s.view_link}</a></p>",
  ])

}

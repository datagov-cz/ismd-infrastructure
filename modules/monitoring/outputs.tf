output "action_group_quiet_id" {
  description = "ID of the quiet action group (Teams only, no email). Use as alert rule target for non-paging alerts."
  value       = azurerm_monitor_action_group.quiet.id
}

output "action_group_paging_id" {
  description = "ID of the paging action group (Teams + email). Null when paging_email_recipients is empty. Use for user-facing-outage alerts."
  value       = local.enable_paging ? azurerm_monitor_action_group.paging[0].id : null
}

output "logic_app_trigger_callback_url" {
  description = "HTTP trigger callback URL of the Teams-notifier Logic App. Use to manually POST a test alert payload via curl to verify the end-to-end pipeline."
  value       = azurerm_logic_app_trigger_http_request.alert_in.callback_url
  sensitive   = true
}

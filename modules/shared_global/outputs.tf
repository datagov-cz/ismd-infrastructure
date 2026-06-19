output "resource_group_name" {
  description = "The name of the shared global resource group."
  value       = azurerm_resource_group.shared_global.name
}

output "vnet_id" {
  description = "The ID of the shared global virtual network."
  value       = azurerm_virtual_network.shared_global.id
}

output "vnet_name" {
  description = "The name of the shared global virtual network."
  value       = azurerm_virtual_network.shared_global.name
}

output "public_ip_address" {
  description = "The public IP address of the Application Gateway."
  value       = azurerm_public_ip.appgw.ip_address
}

output "app_gateway_public_ip_address" {
  description = "The public IP address of the Application Gateway."
  value       = azurerm_public_ip.appgw.ip_address
}

output "app_gateway_id" {
  description = "Resource ID of the Application Gateway. Consumed by env states via terraform_remote_state for AppGW alert scoping."
  value       = azurerm_application_gateway.appgw.id
}

output "waf_policy_id" {
  description = "Resource ID of the Application Gateway WAF policy (rate limiting + OWASP CRS)."
  value       = azurerm_web_application_firewall_policy.appgw.id
}

# --- ACS Email outputs ---

output "acs_name" {
  description = "ACS resource name — first segment of the SMTP username."
  value       = var.deploy_acs ? azurerm_communication_service.dia[0].name : null
}

output "acs_id" {
  description = "ACS resource ID — scope for the 'Communication and Email Service Owner' role assignment to the SMTP Entra app."
  value       = var.deploy_acs ? azurerm_communication_service.dia[0].id : null
}

output "acs_managed_sender_domain" {
  description = "Azure-managed sender domain (e.g. <guid>.azurecomm.net). From address is DoNotReply@<this>."
  value       = var.deploy_acs ? azurerm_email_communication_service_domain.managed[0].from_sender_domain : null
}

output "acs_managed_from_address" {
  description = "Ready-to-use From address for the managed domain (works immediately)."
  value       = var.deploy_acs ? "DoNotReply@${azurerm_email_communication_service_domain.managed[0].from_sender_domain}" : null
}

output "acs_custom_domain_verification_records" {
  description = "DNS records (domain TXT, SPF, DKIM x2, DMARC) the client must publish for the custom sender domain. Share verbatim."
  value       = (var.deploy_acs && var.acs_enable_custom_domain) ? azurerm_email_communication_service_domain.custom[0].verification_records : null
}

output "acs_smtp_host" {
  description = "ACS SMTP relay host. Confirm the exact regional hostname in the ACS portal blade at provisioning time."
  value       = var.deploy_acs ? "smtp.azurecomm.net" : null
}


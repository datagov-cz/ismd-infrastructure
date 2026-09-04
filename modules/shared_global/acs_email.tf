# Azure Communication Services (ACS) Email — Keycloak transactional email (SMTP relay)
#
# Provides the sender side of Keycloak's email (password reset, verification) for the
# `ismd` realm across all envs. Lives in shared-global because one ACS instance serves
# DEV/TEST/PROD Keycloak.
#
# IMPORTANT — what this file does NOT create:
#   The SMTP *authentication principal* (Entra app registration + client secret +
#   "Communication and Email Service Owner" role assignment on the ACS resource +
#   the ACS "SMTP Username" mapping) is NOT defined here. The terraform SP is
#   Contributor-only and cannot create role assignments or Entra app registrations.
#   That piece is provisioned out-of-band — see docs/acs-smtp-setup.md.
#
# Domains:
#   - Azure-managed domain: auto-verified, sendable immediately, sender is
#     DoNotReply@<guid>.azurecomm.net. Used to prove the flow now (DEV/TEST).
#   - Custom domain (auth.dia.gov.cz): created so ACS emits the DNS records the
#     client must publish. NOT associated with the ACS until verified — flip
#     acs_custom_domain_verified=true once the client DNS is live and ACS shows
#     the domain as Verified. Intended sender for PROD.

locals {
  acs_enabled          = var.deploy_acs
  acs_custom_enabled   = var.deploy_acs && var.acs_enable_custom_domain
  acs_custom_associate = local.acs_custom_enabled && var.acs_custom_domain_verified
}

resource "azurerm_communication_service" "dia" {
  count               = local.acs_enabled ? 1 : 0
  name                = var.acs_name
  resource_group_name = azurerm_resource_group.shared_global.name
  data_location       = var.acs_data_location

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Keycloak transactional email"
  }
}

resource "azurerm_email_communication_service" "dia" {
  count               = local.acs_enabled ? 1 : 0
  name                = var.acs_email_name
  resource_group_name = azurerm_resource_group.shared_global.name
  data_location       = var.acs_data_location

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Keycloak transactional email"
  }
}

# Azure-managed sender domain — auto-verified, usable immediately.
resource "azurerm_email_communication_service_domain" "managed" {
  count             = local.acs_enabled ? 1 : 0
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.dia[0].id
  domain_management = "AzureManaged"

  tags = {
    ManagedBy = "Terraform"
  }
}

# Custom sender domain — created to emit DNS records for the client to publish.
# domain_management = CustomerManaged means ACS will NOT send from it until the
# client publishes the verification/SPF/DKIM/DMARC records and it flips to Verified.
resource "azurerm_email_communication_service_domain" "custom" {
  count             = local.acs_custom_enabled ? 1 : 0
  name              = var.acs_custom_sender_domain
  email_service_id  = azurerm_email_communication_service.dia[0].id
  domain_management = "CustomerManaged"

  tags = {
    ManagedBy = "Terraform"
  }
}

# Associate the managed domain with the ACS resource so it can be used as a sender now.
resource "azurerm_communication_service_email_domain_association" "managed" {
  count                    = local.acs_enabled ? 1 : 0
  communication_service_id = azurerm_communication_service.dia[0].id
  email_service_domain_id  = azurerm_email_communication_service_domain.managed[0].id
}

# Associate the custom domain ONLY after it is verified (client DNS live).
# Until then this association is not created, so terraform apply succeeds while
# the domain is still pending verification.
resource "azurerm_communication_service_email_domain_association" "custom" {
  count                    = local.acs_custom_associate ? 1 : 0
  communication_service_id = azurerm_communication_service.dia[0].id
  email_service_domain_id  = azurerm_email_communication_service_domain.custom[0].id
}

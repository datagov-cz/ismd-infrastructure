terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "7d72da57-155c-4d56-883e-0e68a747e9e1" # InformacniSystemModelovaniDat
  features {}
}

# Shared Global (App Gateway + Global VNet) - Manages all environments in one deployment
module "shared_global" {
  source   = "../modules/shared_global"
  location = var.location

  # Construct FQDNs from environment-specific domains (backward compatible with old variable)
  frontend_fqdn = var.frontend_fqdn != "" ? var.frontend_fqdn : (
    var.container_app_environment_domain_dev != "" ? "${var.frontend_app_name}-dev.${var.container_app_environment_domain_dev}" :
    (var.container_app_environment_domain != "" ? "${var.frontend_app_name}-dev.${var.container_app_environment_domain}" : "")
  )
  backend_fqdn = var.backend_fqdn != "" ? var.backend_fqdn : (
    var.container_app_environment_domain_dev != "" ? "${var.backend_app_name}-dev.${var.container_app_environment_domain_dev}" :
    (var.container_app_environment_domain != "" ? "${var.backend_app_name}-dev.${var.container_app_environment_domain}" : "")
  )

  # TEST FQDNs
  frontend_fqdn_test = var.frontend_fqdn_test != "" ? var.frontend_fqdn_test : (
    var.container_app_environment_domain_test != "" ? "${var.frontend_app_name}-test.${var.container_app_environment_domain_test}" : ""
  )
  backend_fqdn_test = var.backend_fqdn_test != "" ? var.backend_fqdn_test : (
    var.container_app_environment_domain_test != "" ? "${var.backend_app_name}-test.${var.container_app_environment_domain_test}" : ""
  )

  # PROD FQDNs
  frontend_fqdn_prod = var.frontend_fqdn_prod != "" ? var.frontend_fqdn_prod : (
    var.container_app_environment_domain_prod != "" ? "${var.frontend_app_name}-prod.${var.container_app_environment_domain_prod}" : ""
  )
  backend_fqdn_prod = var.backend_fqdn_prod != "" ? var.backend_fqdn_prod : (
    var.container_app_environment_domain_prod != "" ? "${var.backend_app_name}-prod.${var.container_app_environment_domain_prod}" : ""
  )

  # Hostname-based routing inputs (must be ASCII/punycode)
  dev_hostname  = var.dev_hostname
  test_hostname = var.test_hostname
  prod_hostname = var.prod_hostname

  # Pass app names and environment domains to module for auto-calculation fallback
  frontend_app_name                     = var.frontend_app_name
  backend_app_name                      = var.backend_app_name
  container_app_environment_domain_dev  = var.container_app_environment_domain_dev
  container_app_environment_domain_test = var.container_app_environment_domain_test
  container_app_environment_domain_prod = var.container_app_environment_domain_prod
}

output "resource_group_name" {
  value = module.shared_global.resource_group_name
}

output "vnet_id" {
  value = module.shared_global.vnet_id
}

output "vnet_name" {
  value = module.shared_global.vnet_name
}

output "app_gateway_public_ip_address" {
  value = module.shared_global.app_gateway_public_ip_address
}

output "app_gateway_id" {
  value = module.shared_global.app_gateway_id
}

# --- ACS Email (Keycloak SMTP sender) ---

output "acs_name" {
  value = module.shared_global.acs_name
}

output "acs_id" {
  value = module.shared_global.acs_id
}

output "acs_managed_sender_domain" {
  value = module.shared_global.acs_managed_sender_domain
}

output "acs_managed_from_address" {
  value = module.shared_global.acs_managed_from_address
}

output "acs_smtp_host" {
  value = module.shared_global.acs_smtp_host
}

# DNS records the client must publish for auth.dia.gov.cz (custom sender domain).
output "acs_custom_domain_verification_records" {
  value = module.shared_global.acs_custom_domain_verification_records
}

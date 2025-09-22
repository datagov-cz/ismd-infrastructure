terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.37.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Shared Global (App Gateway + Global VNet), parameterized by environment
module "shared_global" {
  source      = "../modules/shared_global"
  location    = var.location
  environment = var.environment

  # Construct FQDNs from provided domain to avoid circular dep
  # Treat these as DEV defaults when environment == dev
  frontend_fqdn = var.environment == "dev" && var.container_app_environment_domain != "" ? "${var.frontend_app_name}-dev.${var.container_app_environment_domain}" : ""
  backend_fqdn  = var.environment == "dev" && var.container_app_environment_domain != "" ? "${var.backend_app_name}-dev.${var.container_app_environment_domain}" : ""

  # For TEST/PROD, prefer explicit overrides; else construct when this workflow is called with that environment and domain is provided
  frontend_fqdn_test = var.frontend_fqdn_test != "" ? var.frontend_fqdn_test : (var.environment == "test" && var.container_app_environment_domain != "" ? "${var.frontend_app_name}-test.${var.container_app_environment_domain}" : "")
  backend_fqdn_test  = var.backend_fqdn_test  != "" ? var.backend_fqdn_test  : (var.environment == "test" && var.container_app_environment_domain != "" ? "${var.backend_app_name}-test.${var.container_app_environment_domain}"  : "")
  frontend_fqdn_prod = var.frontend_fqdn_prod != "" ? var.frontend_fqdn_prod : (var.environment == "prod" && var.container_app_environment_domain != "" ? "${var.frontend_app_name}-prod.${var.container_app_environment_domain}" : "")
  backend_fqdn_prod  = var.backend_fqdn_prod  != "" ? var.backend_fqdn_prod  : (var.environment == "prod" && var.container_app_environment_domain != "" ? "${var.backend_app_name}-prod.${var.container_app_environment_domain}"  : "")

  # Hostname-based routing inputs (must be ASCII/punycode)
  dev_hostname  = var.dev_hostname
  test_hostname = var.test_hostname
  prod_hostname = var.prod_hostname
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

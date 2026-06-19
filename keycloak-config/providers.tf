# Stage-2 config: manages what lives INSIDE the running Keycloak (the ismd realm
# and its config) via Keycloak's admin REST API. It does NOT deploy Keycloak —
# that's the azurerm container in the per-env state. Apply this AFTER Keycloak
# is deployed and reachable.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Authenticates to the running Keycloak as the master-realm admin (admin-cli).
# base_path matches KC_HTTP_RELATIVE_PATH on the container (/popisujeme/auth).
# Hardening later: swap to a dedicated service-account client with only
# realm-management roles instead of the master admin.
provider "keycloak" {
  client_id = "admin-cli"
  username  = var.tool_keycloak_admin_user
  password  = var.tool_keycloak_admin_password
  url       = var.keycloak_url
  base_path = "/popisujeme/auth"
  realm     = "master"
}

# Present for pulling SMTP creds from Key Vault later (data source); not yet used.
provider "azurerm" {
  subscription_id = "7d72da57-155c-4d56-883e-0e68a747e9e1"
  features {}
}

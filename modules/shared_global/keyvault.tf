# Global Key Vault — source of truth for cross-env secrets, primarily the App
# Gateway TLS cert. Terraform manages the vault + access policies; secret VALUES
# are seeded out-of-band (`az keyvault secret set`) and NEVER stored in state (no
# azurerm_key_vault_secret).
#
# Access-policy mode (not Azure RBAC): the operator is directory-locked out of
# creating RBAC role assignments, so grants are self-serve resource-plane access
# policies. The precedent vault (ismd-keyvault) is also access-policy mode.
#
# Stands up EMPTY for now. The AppGW cert cutover (repoint
# ssl_certificate_keyvault_secret_id here + grant the AppGW identity + seed the
# cert value) is a separate, gated step pending cert-renewal ownership — see the
# migration plan. This file does NOT touch the current cert reference.

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "global" {
  name                = "ismd-kv-global"
  resource_group_name = azurerm_resource_group.shared_global.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = false

  # Blast-radius net for keeping the vault in a TF-managed RG: a destroy
  # soft-deletes (recoverable), never hard-deletes. Irreversible once enabled.
  # Does not affect versioning — cert/secret rotation writes a new version.
  # Global is prod-grade (holds the AppGW cert) → 90-day retention.
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Shared Global Resources"
    Component = "Secrets"
  }
}

# Operator data-plane grant so secret VALUES can be seeded/rotated via CLI
# (`az keyvault secret set`). Object ids come from TF_VAR_keyvault_operator_object_ids
# in the gitignored shared-global env file — never commit personal principal ids.
# The AppGW identity's read grant is added with the cert cutover, not here.
resource "azurerm_key_vault_access_policy" "operators" {
  for_each = toset(var.keyvault_operator_object_ids)

  key_vault_id = azurerm_key_vault.global.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = each.value

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover"]

  # Certificate perms so operators can import/manage the AppGW cert as a KV
  # Certificate object (expiry tracking). The AppGW identity reads it via the
  # auto-exposed secret path (secret get), so it needs no cert perms.
  certificate_permissions = ["Get", "List", "Import", "Create", "Update", "Delete", "Recover", "ManageContacts"]
}

# App Gateway's managed identity — the existing client-owned `ismd-identity` that the
# AppGW already uses to pull its TLS cert. Grant it read on the global vault so the
# AppGW can source the `datagov-cz` cert here once ssl_certificate_keyvault_secret_id
# is repointed. Kept as the existing identity for minimal change; a dedicated AppGW
# identity can follow with the client-RG (ismd-asistent) assimilation.
data "azurerm_user_assigned_identity" "appgw" {
  name                = "ismd-identity"
  resource_group_name = "ismd-asistent-test"
}

resource "azurerm_key_vault_access_policy" "appgw" {
  key_vault_id = azurerm_key_vault.global.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_user_assigned_identity.appgw.principal_id

  # AppGW pulls the cert via the secret path; certificate get included for parity.
  secret_permissions      = ["Get"]
  certificate_permissions = ["Get"]
}

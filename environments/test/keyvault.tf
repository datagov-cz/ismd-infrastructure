# Per-env Key Vault — source of truth for this environment's app secrets and the
# CAAIS mTLS certs/keys. Terraform manages the vault + access policies; secret
# VALUES are seeded out-of-band (`az keyvault secret set`) and NEVER stored in
# state (no azurerm_key_vault_secret).
#
# Access-policy mode (not Azure RBAC): the operator is directory-locked out of
# creating RBAC role assignments, so grants are self-serve resource-plane access
# policies. The precedent vault (ismd-keyvault) is also access-policy mode.

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "env" {
  name                = "ismd-kv-${var.environment}"
  resource_group_name = var.shared_resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = false

  # Blast-radius net for keeping the vault in a TF-managed RG: a destroy
  # soft-deletes (recoverable), never hard-deletes. Irreversible once enabled.
  # Does not affect versioning — secret/cert rotation writes a new version.
  purge_protection_enabled   = true
  soft_delete_retention_days = var.environment == "prod" ? 90 : 7 # dev/test: min retention frees the name sooner during setup churn

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Component   = "Secrets"
  }

  # RG (ismd-shared-<env>) is created by module.shared; the vault references it by
  # name, so make the ordering explicit.
  depends_on = [module.shared]
}

# Operator data-plane grant so secret VALUES can be seeded/rotated via CLI
# (`az keyvault secret set`). Object ids come from TF_VAR_keyvault_operator_object_ids
# in the gitignored .env.<env> — never commit personal principal ids. App/identity
# read grants are their own access-policy resources below.
resource "azurerm_key_vault_access_policy" "operators" {
  for_each = toset(var.keyvault_operator_object_ids)

  key_vault_id = azurerm_key_vault.env.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = each.value

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover"]

  # Certificate perms so operators can import/manage cert objects (CAAIS client
  # certs, and — in global — the AppGW cert). Certs are stored as KV Certificate
  # objects for expiry tracking; consumers still read the auto-exposed secret path
  # via key_vault_secret_id (secret get), so app/AppGW identities need no cert perms.
  certificate_permissions = ["Get", "List", "Import", "Create", "Update", "Delete", "Recover", "ManageContacts"]
}

# Tool backend's KV identity — grant read on this env's secrets so the app can
# resolve its key_vault_secret_id references at runtime. Lives here (env root)
# because the vault does; the principal id comes from the tool_apps module output.
# Created unconditionally (independent of the secret-reference cutover) so the grant
# is in place BEFORE any key_vault_secret_id is validated at apply — the two-phase
# ordering the Class A migration needs.
resource "azurerm_key_vault_access_policy" "tool_backend" {
  count = var.deploy_tool_apps ? 1 : 0

  key_vault_id = azurerm_key_vault.env.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.tool_apps[0].backend_kv_identity_principal_id

  secret_permissions = ["Get", "List"]
}

# Tool frontend's KV identity — same rationale as tool_backend above.
resource "azurerm_key_vault_access_policy" "tool_frontend" {
  count = var.deploy_tool_apps ? 1 : 0

  key_vault_id = azurerm_key_vault.env.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.tool_apps[0].frontend_kv_identity_principal_id

  secret_permissions = ["Get", "List"]
}

# Keycloak container's KV identity — its own admin/db/app-insights secrets AND the
# CAAIS keystore (same identity: both would sit on the same container anyway, and
# this grant is vault-wide, so a separate CAAIS identity buys no isolation).
# Unconditional, so the grant precedes any key_vault_secret_id validation at apply.
resource "azurerm_key_vault_access_policy" "tool_keycloak" {
  count = var.deploy_tool_apps && var.tool_deploy_keycloak ? 1 : 0

  key_vault_id = azurerm_key_vault.env.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.tool_apps[0].keycloak_kv_identity_principal_id

  secret_permissions = ["Get", "List"]
}

# Validator backend + frontend KV identities (validator_apps is always deployed).
resource "azurerm_key_vault_access_policy" "validator_backend" {
  key_vault_id = azurerm_key_vault.env.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.validator_apps.backend_kv_identity_principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_access_policy" "validator_frontend" {
  key_vault_id = azurerm_key_vault.env.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.validator_apps.frontend_kv_identity_principal_id

  secret_permissions = ["Get", "List"]
}

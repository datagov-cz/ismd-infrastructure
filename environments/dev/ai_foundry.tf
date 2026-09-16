# Dev — Azure OpenAI (Foundry) account + model deployment backing ismd-ai.
#
# COST MODEL — read before changing the SKU. A Standard-family deployment is billed
# per token consumed only; an account and a deployment that receive no requests cost
# nothing. That is what makes it safe to create this long before ai_llm_enabled flips
# to true. Any *ProvisionedManaged SKU is the opposite: PTU bills hourly from the
# moment the deployment is created, whether or not anything calls it. The validation
# on ai_foundry_deployment_sku exists to stop that by accident.
#
# SECRETS — the account's access keys DO land in Terraform state:
# azurerm_cognitive_account exports primary_access_key / secondary_access_key and
# there is no way to suppress them. That departs from the KV convention in
# keyvault.tf, and is the reason to move ismd-ai to managed-identity auth
# (local_auth_enabled = false) once LlmClient supports it. The app itself still reads
# the key from Key Vault, not from state. Seed it out of band, then set
# ai_llm_api_key_kv_secret_id:
#
#   f=$(mktemp) \
#   && az cognitiveservices account keys list -n ismd-openai-dev -g ismd-ai-dev \
#        --query key1 -o tsv | tr -d '\r\n' > "$f" \
#   && az keyvault secret set --vault-name ismd-kv-dev -n app-llm-api-key --file "$f" -o none; \
#   rm -f "$f"
#
# From WSL with the Windows az, the temp file must be on a Windows-visible path:
#   mktemp -p /mnt/c/Users/<you>/AppData/Local/Temp  and  --file "$(wslpath -w "$f")"
#
# A short-lived temp file outside the repo, because Windows az cannot read /dev/stdin
# and --value would put the key on the command line. tr strips the tsv newline, which
# would otherwise become part of the api-key header. -o none stops secret set from
# echoing the value back.
#
# The ai_backend access policy in keyvault.tf already grants Get/List on this vault,
# so no further grant is needed.
#
# WIRING — the endpoint is deterministic from custom_subdomain_name, so it goes
# straight into tfvars rather than through an output (root does not re-export
# module.dev outputs):
#
#   ai_llm_provider     = "AZURE_OPENAI"
#   ai_llm_endpoint_url = "https://ismd-openai-dev.openai.azure.com/openai/v1/responses"
#   ai_llm_model        = <ai_foundry_deployment_name>
#
# No {model} placeholder and no api-version: for AZURE_OPENAI, LlmClient posts the
# deployment name in the request body, and the /openai/v1 route is implicitly versioned.

resource "azurerm_cognitive_account" "openai" {
  # Gated on deploy_ai_apps too: this lives in the AI resource group, which
  # resource_groups.tf only creates when the AI apps are deployed.
  count = var.deploy_ai_foundry && var.deploy_ai_apps ? 1 : 0

  name                = "ismd-openai-${var.environment}"
  resource_group_name = var.ai_resource_group_name
  location            = var.ai_foundry_location
  kind                = "OpenAI"
  sku_name            = "S0"

  # Required for the https://<subdomain>.openai.azure.com host that the /openai/v1
  # route lives on. Without it the account answers only on the regional
  # *.api.cognitive.microsoft.com endpoint, which is not the URL shape LlmClient builds.
  custom_subdomain_name = "ismd-openai-${var.environment}"

  # ismd-ai reaches this over the public endpoint from the Container App Environment.
  # Tighten to a private endpoint when the CAE gets one.
  public_network_access_enabled = true

  # LlmClient authenticates with the api-key header only, so key auth must stay on
  # until the app can use its managed identity.
  local_auth_enabled = true

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "AI"
    Component   = "LLM"
  }

  depends_on = [azurerm_resource_group.ai]
}

resource "azurerm_cognitive_deployment" "chat" {
  count = var.deploy_ai_foundry && var.deploy_ai_apps ? 1 : 0

  name                 = var.ai_foundry_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  # Hold the pinned version until Microsoft retires it, then let Azure move it rather
  # than have the deployment stop answering. The provider default
  # (OnceNewDefaultVersionAvailable) would silently change model behaviour and drift
  # from ai_foundry_model_version.
  version_upgrade_option = "OnceCurrentVersionExpired"

  model {
    format  = "OpenAI"
    name    = var.ai_foundry_model_name
    version = var.ai_foundry_model_version
  }

  sku {
    name     = var.ai_foundry_deployment_sku
    capacity = var.ai_foundry_deployment_capacity
  }
}

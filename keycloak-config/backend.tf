# Separate state from the azurerm env states (different plane, different apply
# phase). Environments are separated by terraform WORKSPACE, mirroring the main
# state: terraform stores non-default workspaces at <key>env:<workspace>
# (e.g. ismd-keycloak.tfstateenv:test). Select with `terraform workspace select
# dev|test|prod` or `../terraw.sh switch <env>`. Do not use the default workspace
# for an environment.
terraform {
  backend "azurerm" {
    resource_group_name  = "ismd-shared-tfstate"
    storage_account_name = "ismdtfstate"
    container_name       = "tfstate"
    key                  = "ismd-keycloak.tfstate"
    # Entra ID auth instead of a shared account key (see ../backend.tf).
    use_azuread_auth = true
  }
}

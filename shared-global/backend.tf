terraform {
  backend "azurerm" {
    resource_group_name  = "ismd-shared-tfstate"
    storage_account_name = "ismdtfstate"
    container_name       = "tfstate"
    key                  = "ismd-shared-global.tfstate"
    # Entra ID auth instead of a shared account key (see ../backend.tf).
    use_azuread_auth = true
  }
}

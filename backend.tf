# local state for development
/*terraform {
  backend "local" {
    # Store state in terraform.tfstate by default
    path = "terraform.tfstate"
  }
}*/


terraform {
  backend "azurerm" {
    resource_group_name  = "ismd-shared-tfstate"
    storage_account_name = "ismdtfstate"
    container_name       = "tfstate"
    key                  = "ismd.tfstate"
    # Authenticate to the state account with Entra ID instead of a shared account key,
    # so allow_shared_key_access can be disabled on ismdtfstate.
    use_azuread_auth = true
    # Using Terraform workspaces for environment separation
    # Use 'terraform workspace select <env>' to switch environments
    # Terraform will automatically use <key>env:<workspace> as the actual blob name
  }
}

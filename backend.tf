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
    # Using Terraform workspaces for environment separation
    # Use 'terraform workspace select <env>' to switch environments
    # Terraform will automatically use <key>env:<workspace> as the actual blob name
  }
}

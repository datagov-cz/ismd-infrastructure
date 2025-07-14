# Using local state for development
/*terraform {
  backend "local" {
    # Store state in terraform.tfstate by default
    path = "terraform.tfstate"
  }
}*/


terraform {
  backend "azurerm" {
    # IMPORTANT: The state file key is intentionally omitted here and must be specified during initialization
    # using -backend-config="key=workspace.ENVIRONMENT.tfstate" where ENVIRONMENT is dev, test, or prod
    # Example: terraform init -backend-config="key=workspace.dev.tfstate"
    # This ensures the correct state file is used for each environment and prevents accidental state conflicts
    resource_group_name  = "ismd-shared-tfstate"
    storage_account_name = "ismdtfstate"
    container_name       = "tfstate"
    # key must be specified via -backend-config during terraform init
  }
}

terraform {
  # Backend configuration is commented out for local development
  # Uncomment and configure this once the storage account exists
  # backend "azurerm" {
  #   resource_group_name  = "ismd-shared-tfstate"
  #   storage_account_name = "ismdtfstate"
  #   container_name       = "tfstate"
  #   # The key will be set dynamically based on the environment
  #   # For local testing, you can uncomment and use one of these:
  #   # key                = "dev/terraform.tfstate"
  #   # key                = "test/terraform.tfstate"
  #   # key                = "prod/terraform.tfstate"
  # }
}

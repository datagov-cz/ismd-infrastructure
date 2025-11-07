# Shared Global Resource Group
resource "azurerm_resource_group" "shared_global" {
  name     = "ismd-shared-global"
  location = var.location

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Shared Global Resources"
  }
}

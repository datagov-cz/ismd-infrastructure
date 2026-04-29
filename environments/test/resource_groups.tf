# Test Environment — resource groups

# Validator resource group
resource "azurerm_resource_group" "validator" {
  name     = var.validator_resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "Validator"
  }
}

# Tool resource group
resource "azurerm_resource_group" "tool" {
  count    = var.deploy_tool_apps ? 1 : 0
  name     = var.tool_resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "Tool"
  }
}

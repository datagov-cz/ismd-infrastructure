# Application Gateway Subnet
resource "azurerm_subnet" "appgw" {
  name                 = "ismd-appgw-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24", "fd00:db8:deca::/64"]

  # Note: Application Gateway subnet does not require delegation for v2 SKU
  # IPv6 prefix added for dual-stack support
}

# Outputs
output "application_gateway_subnet_id" {
  value = azurerm_subnet.appgw.id
}

output "application_gateway_subnet_name" {
  value = azurerm_subnet.appgw.name
}

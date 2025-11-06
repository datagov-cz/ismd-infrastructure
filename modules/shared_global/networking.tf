# Shared Global Virtual Network
resource "azurerm_virtual_network" "shared_global" {
  name                = "ismd-vnet-shared-global"
  resource_group_name = azurerm_resource_group.shared_global.name
  location            = azurerm_resource_group.shared_global.location
  address_space       = ["10.1.0.0/16", "fd00:db8:decb::/48"]
  dns_servers         = ["168.63.129.16"] # Azure's internal DNS server

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Shared Global Resources"
  }
}


# Subnet for the Application Gateway within the Shared Global VNet
resource "azurerm_subnet" "appgw" {
  name                 = "ismd-appgw-subnet"
  resource_group_name  = azurerm_resource_group.shared_global.name
  virtual_network_name = azurerm_virtual_network.shared_global.name
  address_prefixes     = ["10.1.0.0/24", "fd00:db8:decb::/64"]
  delegation {
    name = "appgw-delegation"
    service_delegation {
      name    = "Microsoft.Network/applicationGateways"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# IPv4 Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "ismd-appgw-pipv4"
  resource_group_name = azurerm_resource_group.shared_global.name
  location            = azurerm_resource_group.shared_global.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  zones               = ["1", "2", "3"]

  lifecycle {
    prevent_destroy = true
  }
}

# IPv6 Public IP for Application Gateway
resource "azurerm_public_ip" "appgw_ipv6" {
  name                = "ismd-appgw-pipv6"
  resource_group_name = azurerm_resource_group.shared_global.name
  location            = azurerm_resource_group.shared_global.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv6"
  domain_name_label   = var.domain_name_label
  zones               = ["1", "2", "3"]

  lifecycle {
    prevent_destroy = true
  }
}

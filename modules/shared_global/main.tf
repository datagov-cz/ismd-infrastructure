# Shared Global Resource Group
resource "azurerm_resource_group" "shared_global" {
  name     = "ismd-shared-global"
  location = var.location

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Shared Global Resources"
  }
}

# Shared Global Virtual Network
resource "azurerm_virtual_network" "shared_global" {
  name                = "ismd-vnet-shared-global"
  resource_group_name = azurerm_resource_group.shared_global.name
  location            = azurerm_resource_group.shared_global.location
  address_space       = ["10.1.0.0/16", "fd00:db8:decb::/48"]
  dns_servers         = ["168.63.129.16"]  # Azure's internal DNS server

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

# Shared Application Gateway
resource "azurerm_application_gateway" "appgw" {
  name                = "ismd-app-gateway"
  resource_group_name = azurerm_resource_group.shared_global.name
  
  lifecycle {
    prevent_destroy = true
  }
  location            = azurerm_resource_group.shared_global.location
  enable_http2       = true

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
  }

  zones = ["1", "2", "3"]  # Deploy across all availability zones in the region

  autoscale_configuration {
    min_capacity = 0
    max_capacity = 10
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "port_80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIpIPv4"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIpIPv6"
    public_ip_address_id = azurerm_public_ip.appgw_ipv6.id
  }
  
  # Backend Pools - Use provided FQDNs if available, otherwise use default empty pool
  backend_address_pool {
    name  = "validator-${var.environment}-fe-pool"
    fqdns = var.frontend_fqdn != "" ? [var.frontend_fqdn] : []
  }

  backend_address_pool {
    name  = "validator-${var.environment}-be-pool"
    fqdns = var.backend_fqdn != "" ? [var.backend_fqdn] : []
  }
  
  # Health Probes - One per app per environment
  probe {
    name   = "validator-${var.environment}-fe-probe"
    protocol = "Http"
    path   = "/"
    interval = 30
    timeout  = 30
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = true
    
    match {
      status_code = ["200-399"]
    }
  }

  probe {
    name   = "validator-${var.environment}-be-probe"
    protocol = "Http"
    path   = "/actuator/health"
    interval = 30
    timeout  = 30
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = true
    
    match {
      status_code = ["200-399"]
    }
  }
  
  # Backend HTTP Settings
  backend_http_settings {
    name                  = "validator-${var.environment}-fe-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-${var.environment}-fe-probe"
    pick_host_name_from_backend_address = true
    path                  = "/"
  }

  backend_http_settings {
    name                  = "validator-${var.environment}-be-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-${var.environment}-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/api/"
  }
  
  # HTTP Listeners  
  http_listener {
    name                           = "http-ipv4-listener"
    frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
    frontend_port_name             = "port_80"
    protocol                       = "Http"
  }

  http_listener {
    name                           = "http-ipv6-listener"
    frontend_ip_configuration_name = "appGwPublicFrontendIpIPv6"
    frontend_port_name             = "port_80"
    protocol                       = "Http"
  }
  
  # URL Path Maps
  url_path_map {
    name                               = "path-map-${var.environment}"
    default_backend_address_pool_name  = "validator-${var.environment}-fe-pool"
    default_backend_http_settings_name = "validator-${var.environment}-fe-http-settings"

    path_rule {
      name                       = "api-rule-${var.environment}"
      paths                      = ["/validator/api/*", "/validator/api", "/api/*", "/api"]
      backend_address_pool_name  = "validator-${var.environment}-be-pool"
      backend_http_settings_name = "validator-${var.environment}-be-http-settings"
    }
    
    path_rule {
      name                       = "frontend-rule-${var.environment}"
      paths                      = ["/validator/*", "/validator", "/*"]
      backend_address_pool_name  = "validator-${var.environment}-fe-pool"
      backend_http_settings_name = "validator-${var.environment}-fe-http-settings"
    }
  }
  
  # Request Routing Rules  
  request_routing_rule {
    name                       = "http-ipv4-rule"
    rule_type                  = "PathBasedRouting"
    http_listener_name         = "http-ipv4-listener"
    url_path_map_name          = "path-map-${var.environment}"
    priority                   = 100
  }

  request_routing_rule {
    name                       = "http-ipv6-rule"
    rule_type                  = "PathBasedRouting"
    http_listener_name         = "http-ipv6-listener"
    url_path_map_name          = "path-map-${var.environment}"
    priority                   = 101
  }
  
  tags = {
    environment = "shared"
  }
}

# Tags for all resources
locals {
  common_tags = {
    environment = "shared"
  }
}

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
  
  # Backend Pools (DEV default) - Use provided FQDNs if available, otherwise use empty pool
  backend_address_pool {
    name  = "validator-dev-fe-pool"
    fqdns = var.frontend_fqdn != "" ? [var.frontend_fqdn] : []
  }

  backend_address_pool {
    name  = "validator-dev-be-pool"
    fqdns = var.backend_fqdn != "" ? [var.backend_fqdn] : []
  }

  # Additional backend pools for TEST
  backend_address_pool {
    name  = "validator-test-fe-pool"
    fqdns = var.frontend_fqdn_test != "" ? [var.frontend_fqdn_test] : []
  }

  backend_address_pool {
    name  = "validator-test-be-pool"
    fqdns = var.backend_fqdn_test != "" ? [var.backend_fqdn_test] : []
  }

  # Additional backend pools for PROD
  backend_address_pool {
    name  = "validator-prod-fe-pool"
    fqdns = var.frontend_fqdn_prod != "" ? [var.frontend_fqdn_prod] : []
  }

  backend_address_pool {
    name  = "validator-prod-be-pool"
    fqdns = var.backend_fqdn_prod != "" ? [var.backend_fqdn_prod] : []
  }
  
  # Health Probes - DEV default
  probe {
    name   = "validator-dev-fe-probe"
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
    name   = "validator-dev-be-probe"
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
  
  # Health Probes - TEST
  probe {
    name   = "validator-test-fe-probe"
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
    name   = "validator-test-be-probe"
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

  # Health Probes - PROD
  probe {
    name   = "validator-prod-fe-probe"
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
    name   = "validator-prod-be-probe"
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
    name                  = "validator-dev-fe-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-dev-fe-probe"
    pick_host_name_from_backend_address = true
    path                  = "/"
  }

  backend_http_settings {
    name                  = "validator-dev-be-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-dev-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/api/"
  }
    
  # Additional BE settings for Swagger and root-level paths
  backend_http_settings {
    name                  = "validator-dev-be-root-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-dev-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/"
  }

  backend_http_settings {
    name                  = "validator-dev-be-swagger-ui-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-dev-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/swagger-ui/index.html"
  }
  
  # Pass-through BE settings: preserve original request path (no path override)
  backend_http_settings {
    name                  = "validator-dev-be-pass-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-dev-be-probe"
    pick_host_name_from_backend_address = true
  }

  # TEST backend HTTP settings
  backend_http_settings {
    name                  = "validator-test-fe-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-test-fe-probe"
    pick_host_name_from_backend_address = true
    path                  = "/"
  }

  backend_http_settings {
    name                  = "validator-test-be-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-test-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/api/"
  }

  backend_http_settings {
    name                  = "validator-test-be-root-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-test-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/"
  }

  backend_http_settings {
    name                  = "validator-test-be-swagger-ui-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-test-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/swagger-ui/index.html"
  }

  backend_http_settings {
    name                  = "validator-test-be-pass-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-test-be-probe"
    pick_host_name_from_backend_address = true
  }

  # PROD backend HTTP settings
  backend_http_settings {
    name                  = "validator-prod-fe-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-prod-fe-probe"
    pick_host_name_from_backend_address = true
    path                  = "/"
  }

  backend_http_settings {
    name                  = "validator-prod-be-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-prod-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/api/"
  }

  backend_http_settings {
    name                  = "validator-prod-be-root-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-prod-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/"
  }

  backend_http_settings {
    name                  = "validator-prod-be-swagger-ui-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-prod-be-probe"
    pick_host_name_from_backend_address = true
    path                  = "/swagger-ui/index.html"
  }

  backend_http_settings {
    name                  = "validator-prod-be-pass-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "validator-prod-be-probe"
    pick_host_name_from_backend_address = true
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

  # Hostname-based listeners (IPv4) - only created when hostname provided
  dynamic "http_listener" {
    for_each = var.dev_hostname != "" ? [var.dev_hostname] : []
    content {
      name                           = "http-host-dev-listener"
      frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
      frontend_port_name             = "port_80"
      protocol                       = "Http"
      host_name                      = http_listener.value
    }
  }

  dynamic "http_listener" {
    for_each = var.test_hostname != "" ? [var.test_hostname] : []
    content {
      name                           = "http-host-test-listener"
      frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
      frontend_port_name             = "port_80"
      protocol                       = "Http"
      host_name                      = http_listener.value
    }
  }

  dynamic "http_listener" {
    for_each = var.prod_hostname != "" ? [var.prod_hostname] : []
    content {
      name                           = "http-host-prod-listener"
      frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
      frontend_port_name             = "port_80"
      protocol                       = "Http"
      host_name                      = http_listener.value
    }
  }
  
  # URL Path Maps
  url_path_map {
    name                               = "path-map-dev"
    default_backend_address_pool_name  = "validator-dev-fe-pool"
    default_backend_http_settings_name = "validator-dev-fe-http-settings"

    path_rule {
      name                       = "api-rule-dev"
      paths                      = ["/validator/api/*", "/validator/api", "/api/*", "/api"]
      backend_address_pool_name  = "validator-dev-be-pool"
      backend_http_settings_name = "validator-dev-be-http-settings"
    }
    
    # (removed) swagger-docs-rule for now per request

    # Swagger UI static resources and OpenAPI endpoints
    # Also handle direct access to /swagger-ui and /swagger-ui/
    path_rule {
      name                       = "swagger-ui-index-rule-dev"
      paths                      = ["/swagger-ui", "/swagger-ui/"]
      backend_address_pool_name  = "validator-dev-be-pool"
      backend_http_settings_name = "validator-dev-be-swagger-ui-http-settings"
    }

    # Minimal alias to view swagger under /validator/swagger-ui
    # Note: assets are loaded from absolute /swagger-ui/* so no rewrite needed for them
    path_rule {
      name                       = "validator-swagger-ui-index-rule-dev"
      paths                      = ["/validator/swagger-ui", "/validator/swagger-ui/", "/validator/swagger-ui/index.html"]
      backend_address_pool_name  = "validator-dev-be-pool"
      backend_http_settings_name = "validator-dev-be-swagger-ui-http-settings"
    }

    path_rule {
      name                       = "swagger-ui-rule-dev"
      paths                      = ["/swagger-ui/*"]
      backend_address_pool_name  = "validator-dev-be-pool"
      backend_http_settings_name = "validator-dev-be-pass-http-settings"
    }

    path_rule {
      name                       = "openapi-v3-rule-dev"
      paths                      = ["/v3/*", "/v3"]
      backend_address_pool_name  = "validator-dev-be-pool"
      backend_http_settings_name = "validator-dev-be-pass-http-settings"
    }

    path_rule {
      name                       = "frontend-rule-dev"
      paths                      = ["/validator/*", "/validator", "/*"]
      backend_address_pool_name  = "validator-dev-fe-pool"
      backend_http_settings_name = "validator-dev-fe-http-settings"
    }
  }

  url_path_map {
    name                               = "path-map-test"
    default_backend_address_pool_name  = "validator-test-fe-pool"
    default_backend_http_settings_name = "validator-test-fe-http-settings"

    path_rule {
      name                       = "api-rule-test"
      paths                      = ["/validator/api/*", "/validator/api", "/api/*", "/api"]
      backend_address_pool_name  = "validator-test-be-pool"
      backend_http_settings_name = "validator-test-be-http-settings"
    }
    
    # (removed) swagger-docs-rule for now per request

    # Swagger UI static resources and OpenAPI endpoints
    # Also handle direct access to /swagger-ui and /swagger-ui/
    path_rule {
      name                       = "swagger-ui-index-rule-test"
      paths                      = ["/swagger-ui", "/swagger-ui/"]
      backend_address_pool_name  = "validator-test-be-pool"
      backend_http_settings_name = "validator-test-be-swagger-ui-http-settings"
    }

    # Minimal alias to view swagger under /validator/swagger-ui
    # Note: assets are loaded from absolute /swagger-ui/* so no rewrite needed for them
    path_rule {
      name                       = "validator-swagger-ui-index-rule-test"
      paths                      = ["/validator/swagger-ui", "/validator/swagger-ui/", "/validator/swagger-ui/index.html"]
      backend_address_pool_name  = "validator-test-be-pool"
      backend_http_settings_name = "validator-test-be-swagger-ui-http-settings"
    }

    path_rule {
      name                       = "swagger-ui-rule-test"
      paths                      = ["/swagger-ui/*"]
      backend_address_pool_name  = "validator-test-be-pool"
      backend_http_settings_name = "validator-test-be-pass-http-settings"
    }

    path_rule {
      name                       = "openapi-v3-rule-test"
      paths                      = ["/v3/*", "/v3"]
      backend_address_pool_name  = "validator-test-be-pool"
      backend_http_settings_name = "validator-test-be-pass-http-settings"
    }

    path_rule {
      name                       = "frontend-rule-test"
      paths                      = ["/validator/*", "/validator", "/*"]
      backend_address_pool_name  = "validator-test-fe-pool"
      backend_http_settings_name = "validator-test-fe-http-settings"
    }
  }

  url_path_map {
    name                               = "path-map-prod"
    default_backend_address_pool_name  = "validator-prod-fe-pool"
    default_backend_http_settings_name = "validator-prod-fe-http-settings"

    path_rule {
      name                       = "api-rule-prod"
      paths                      = ["/validator/api/*", "/validator/api", "/api/*", "/api"]
      backend_address_pool_name  = "validator-prod-be-pool"
      backend_http_settings_name = "validator-prod-be-http-settings"
    }
    
    # (removed) swagger-docs-rule for now per request

    # Swagger UI static resources and OpenAPI endpoints
    # Also handle direct access to /swagger-ui and /swagger-ui/
    path_rule {
      name                       = "swagger-ui-index-rule-prod"
      paths                      = ["/swagger-ui", "/swagger-ui/"]
      backend_address_pool_name  = "validator-prod-be-pool"
      backend_http_settings_name = "validator-prod-be-swagger-ui-http-settings"
    }

    # Minimal alias to view swagger under /validator/swagger-ui
    # Note: assets are loaded from absolute /swagger-ui/* so no rewrite needed for them
    path_rule {
      name                       = "validator-swagger-ui-index-rule-prod"
      paths                      = ["/validator/swagger-ui", "/validator/swagger-ui/", "/validator/swagger-ui/index.html"]
      backend_address_pool_name  = "validator-prod-be-pool"
      backend_http_settings_name = "validator-prod-be-swagger-ui-http-settings"
    }

    path_rule {
      name                       = "swagger-ui-rule-prod"
      paths                      = ["/swagger-ui/*"]
      backend_address_pool_name  = "validator-prod-be-pool"
      backend_http_settings_name = "validator-prod-be-pass-http-settings"
    }

    path_rule {
      name                       = "openapi-v3-rule-prod"
      paths                      = ["/v3/*", "/v3"]
      backend_address_pool_name  = "validator-prod-be-pool"
      backend_http_settings_name = "validator-prod-be-pass-http-settings"
    }

    path_rule {
      name                       = "frontend-rule-prod"
      paths                      = ["/validator/*", "/validator", "/*"]
      backend_address_pool_name  = "validator-prod-fe-pool"
      backend_http_settings_name = "validator-prod-fe-http-settings"
    }
  }
  
  # Request Routing Rules  
  request_routing_rule {
    name                       = "http-ipv4-rule"
    rule_type                  = "PathBasedRouting"
    http_listener_name         = "http-ipv4-listener"
    url_path_map_name          = "path-map-dev"
    priority                   = 100
  }

  request_routing_rule {
    name                       = "http-ipv6-rule"
    rule_type                  = "PathBasedRouting"
    http_listener_name         = "http-ipv6-listener"
    url_path_map_name          = "path-map-dev"
    priority                   = 101
  }

  # Host-based rules (only active when listeners exist)
  dynamic "request_routing_rule" {
    for_each = var.dev_hostname != "" ? [1] : []
    content {
      name               = "http-host-dev-rule"
      rule_type          = "PathBasedRouting"
      http_listener_name = "http-host-dev-listener"
      url_path_map_name  = "path-map-dev"
      priority           = 150
    }
  }

  dynamic "request_routing_rule" {
    for_each = var.test_hostname != "" ? [1] : []
    content {
      name               = "http-host-test-rule"
      rule_type          = "PathBasedRouting"
      http_listener_name = "http-host-test-listener"
      url_path_map_name  = "path-map-test"
      priority           = 200
    }
  }

  dynamic "request_routing_rule" {
    for_each = var.prod_hostname != "" ? [1] : []
    content {
      name               = "http-host-prod-rule"
      rule_type          = "PathBasedRouting"
      http_listener_name = "http-host-prod-listener"
      url_path_map_name  = "path-map-prod"
      priority           = 250
    }
  }
  
  tags = {
    environment = "shared"
  }
}

# (common_tags removed; not used)

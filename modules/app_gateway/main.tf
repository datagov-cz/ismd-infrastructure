# Application Gateway Module
# This module creates the Application Gateway with backend pools using constructed FQDNs

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group for the Application Gateway"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet for the Application Gateway"
  type        = string
}

variable "frontend_app_name" {
  description = "Name of the frontend container app (without environment suffix)"
  type        = string
  default     = "ismd-validator-frontend"
}

variable "backend_app_name" {
  description = "Name of the backend container app (without environment suffix)"
  type        = string
  default     = "ismd-validator-backend"
}

variable "region" {
  description = "Azure region code for container app FQDN construction"
  type        = string
  default     = "germanywestcentral"
}

variable "container_app_environment_default_domain" {
  description = "Default domain of the container app environment"
  type        = string
}

# IPv4 Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "ismd-appgw-pip-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  
  lifecycle {
    # Protect from accidental deletion - changing the public IP would break:
    # - DNS records pointing to the application
    # - Firewall rules allowing traffic
    # - External integrations referencing this IP
    prevent_destroy = true
  }
  
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IPv6 Public IP for Application Gateway
resource "azurerm_public_ip" "appgw_ipv6" {
  name                = "ismd-appgw-pip-ipv6-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv6"
  
  lifecycle {
    # Protect from accidental deletion - changing the public IP would break:
    # - DNS records pointing to the application
    # - Firewall rules allowing traffic
    # - External integrations referencing this IP
    prevent_destroy = true
  }
  
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = "ismd-app-gateway-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  # Deploy across availability zones for production environments only
  # Dev environment remains single-zone for cost optimization
  zones = var.environment == "prod" ? ["1", "2", "3"] : null

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
  }
  
  # Enforce TLS 1.2 or later for security
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"  # Enforces TLS 1.2+
  }
  
  autoscale_configuration {
    min_capacity = 1
    # Cost optimization: Limit dev environment to fewer instances
    max_capacity = var.environment == "dev" ? 3 : 10
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = var.subnet_id
  }

  # Frontend ports
  frontend_port {
    name = "port_80"
    port = 80
  }

  # IPv4 frontend configuration (keeping original name to avoid breaking changes)
  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIp"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }
  
  # IPv6 frontend configuration
  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIpv6"
    public_ip_address_id = azurerm_public_ip.appgw_ipv6.id
  }

  # Backend pools with constructed FQDNs using container app environment default domain
  backend_address_pool {
    name  = "frontend-pool"
    fqdns = ["${var.frontend_app_name}-${var.environment}.${var.container_app_environment_default_domain}"]
  }

  backend_address_pool {
    name  = "backend-pool"
    fqdns = ["${var.backend_app_name}-${var.environment}.${var.container_app_environment_default_domain}"]
  }

  # Health probes
  probe {
    name                                = "frontend-health-probe"
    protocol                            = "Http"
    path                                = "/"
    port                                = 80
    # Cost optimization: Longer intervals for dev environment
    interval                            = var.environment == "dev" ? 60 : 30
    timeout                             = 30
    unhealthy_threshold                 = 3
    # Use dynamic host resolution to avoid DNS issues
    pick_host_name_from_backend_http_settings = true
  }
  
  probe {
    name                                = "backend-health-probe"
    protocol                            = "Http"
    path                                = "/actuator/health"
    port                                = 80
    # Cost optimization: Longer intervals for dev environment
    interval                            = var.environment == "dev" ? 60 : 30
    timeout                             = 30
    unhealthy_threshold                 = 3
    # Use dynamic host resolution to avoid DNS issues
    pick_host_name_from_backend_http_settings = true
  }
  
  # Backend HTTP settings
  backend_http_settings {
    name                  = "frontend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "frontend-health-probe"
    pick_host_name_from_backend_address = true
    path                  = "/"
  }
  
  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "backend-health-probe"
    pick_host_name_from_backend_address = true
    path                  = "/api/"
  }

  # HTTP listeners
  http_listener {
    name                           = "http-listener-ipv4"
    frontend_ip_configuration_name = "appGwPublicFrontendIp"
    frontend_port_name             = "port_80"
    protocol                       = "Http"
  }
  
  http_listener {
    name                           = "http-listener-ipv6"
    frontend_ip_configuration_name = "appGwPublicFrontendIpv6"
    frontend_port_name             = "port_80"
    protocol                       = "Http"
  }
  

  
  # URL path map for routing
  url_path_map {
    name                               = "validator-path-map"
    default_backend_address_pool_name  = "frontend-pool"
    default_backend_http_settings_name = "frontend-http-settings"
    
    path_rule {
      name                       = "validator-api-rule"
      paths                      = ["/validator/api/*"]
      backend_address_pool_name  = "backend-pool"
      backend_http_settings_name = "backend-http-settings"
    }
    
    path_rule {
      name                       = "validator-rule"
      paths                      = ["/validator/*"]
      backend_address_pool_name  = "frontend-pool"
      backend_http_settings_name = "frontend-http-settings"
    }
  }
  


  # Request routing rules with path-based routing for both IPv4 and IPv6
  request_routing_rule {
    name                       = "validator-rule-ipv4"
    rule_type                  = "PathBasedRouting"
    http_listener_name         = "http-listener-ipv4"
    url_path_map_name          = "validator-path-map"
    priority                   = 100
  }
  
  request_routing_rule {
    name                       = "validator-rule-ipv6"
    rule_type                  = "PathBasedRouting"
    http_listener_name         = "http-listener-ipv6"
    url_path_map_name          = "validator-path-map"
    priority                   = 110
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Outputs
output "public_ip_address" {
  value = azurerm_public_ip.appgw.ip_address
}

output "app_gateway_id" {
  value = azurerm_application_gateway.main.id
}

output "app_gateway_name" {
  value = azurerm_application_gateway.main.name
}

output "resource_group_name" {
  value = var.resource_group_name
}

output "subnet_id" {
  value = var.subnet_id
}

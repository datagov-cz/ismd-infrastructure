# Application Gateway Base Configuration
# This file contains static/base configuration that applies to all apps

locals {
  # Base frontend ports
  appgw_frontend_ports = [
    { name = "port_80", port = 80 },
    { name = "port_443", port = 443 }
  ]

  # Base frontend IP configurations
  appgw_frontend_ip_configurations = [
    {
      name                 = "appGwPublicFrontendIpIPv4"
      public_ip_address_id = azurerm_public_ip.appgw.id
    },
    {
      name                 = "appGwPublicFrontendIpIPv6"
      public_ip_address_id = azurerm_public_ip.appgw_ipv6.id
    }
  ]

  # SSL Certificates
  appgw_ssl_certificates = [
    {
      name                = "datagov-cz"
      key_vault_secret_id = var.ssl_certificate_keyvault_secret_id
    }
  ]

  # Default HTTP listeners (fallback to dev path map)
  appgw_default_http_listeners = [
    {
      name                           = "http-ipv4-listener"
      frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
      frontend_port_name             = "port_80"
      protocol                       = "Http"
      host_name                      = null
      ssl_certificate_name           = null
    },
    {
      name                           = "http-ipv6-listener"
      frontend_ip_configuration_name = "appGwPublicFrontendIpIPv6"
      frontend_port_name             = "port_80"
      protocol                       = "Http"
      host_name                      = null
      ssl_certificate_name           = null
    }
  ]

  # Default request routing rules
  appgw_default_routing_rules = [
    {
      name               = "http-ipv4-rule"
      rule_type          = "PathBasedRouting"
      http_listener_name = "http-ipv4-listener"
      url_path_map_name  = "path-map-dev"
      priority           = 100
    },
    {
      name               = "http-ipv6-rule"
      rule_type          = "PathBasedRouting"
      http_listener_name = "http-ipv6-listener"
      url_path_map_name  = "path-map-dev"
      priority           = 101
    }
  ]
}

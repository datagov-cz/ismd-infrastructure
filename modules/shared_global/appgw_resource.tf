# Application Gateway Main Resource
# This file contains the Application Gateway resource with dynamic blocks
# Configuration data is loaded from:
# - appgw_base_config.tf (base/static configuration)
# - appgw_validator_config.tf (validator app configuration)
# - appgw_tool_config.tf (tool app configuration - FUTURE)

resource "azurerm_application_gateway" "appgw" {
  name                = "ismd-app-gateway"
  resource_group_name = azurerm_resource_group.shared_global.name
  location            = azurerm_resource_group.shared_global.location
  enable_http2        = true

  lifecycle {
    prevent_destroy = true
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      "/subscriptions/7d72da57-155c-4d56-883e-0e68a747e9e1/resourceGroups/ismd-asistent-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/ismd-identity"
    ]
  }

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  zones = ["1", "2", "3"]

  autoscale_configuration {
    min_capacity = 0
    max_capacity = 10
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.appgw.id
  }

  # ========================================
  # Frontend Ports
  # ========================================
  dynamic "frontend_port" {
    for_each = local.appgw_frontend_ports
    content {
      name = frontend_port.value.name
      port = frontend_port.value.port
    }
  }

  # ========================================
  # Frontend IP Configurations
  # ========================================
  dynamic "frontend_ip_configuration" {
    for_each = local.appgw_frontend_ip_configurations
    content {
      name                 = frontend_ip_configuration.value.name
      public_ip_address_id = frontend_ip_configuration.value.public_ip_address_id
    }
  }

  # ========================================
  # SSL Certificates
  # ========================================
  dynamic "ssl_certificate" {
    for_each = local.appgw_ssl_certificates
    content {
      name                = ssl_certificate.value.name
      key_vault_secret_id = ssl_certificate.value.key_vault_secret_id
    }
  }

  # ========================================
  # Backend Address Pools
  # ========================================
  dynamic "backend_address_pool" {
    for_each = local.validator_backend_pools
    content {
      name  = backend_address_pool.value.name
      fqdns = backend_address_pool.value.fqdns
    }
  }

  # ========================================
  # Health Probes
  # ========================================
  dynamic "probe" {
    for_each = local.validator_probes
    content {
      name                                      = probe.value.name
      protocol                                  = probe.value.protocol
      path                                      = probe.value.path
      interval                                  = probe.value.interval
      timeout                                   = probe.value.timeout
      unhealthy_threshold                       = probe.value.unhealthy_threshold
      pick_host_name_from_backend_http_settings = probe.value.pick_host_name_from_backend_http_settings

      match {
        status_code = probe.value.match_status_codes
      }
    }
  }

  # ========================================
  # Backend HTTP Settings
  # ========================================
  dynamic "backend_http_settings" {
    for_each = local.validator_backend_http_settings
    content {
      name                                = backend_http_settings.value.name
      cookie_based_affinity               = backend_http_settings.value.cookie_based_affinity
      port                                = backend_http_settings.value.port
      protocol                            = backend_http_settings.value.protocol
      request_timeout                     = backend_http_settings.value.request_timeout
      probe_name                          = backend_http_settings.value.probe_name
      pick_host_name_from_backend_address = backend_http_settings.value.pick_host_name_from_backend_address
      path                                = backend_http_settings.value.path
    }
  }

  # ========================================
  # HTTP Listeners (default fallback listeners)
  # ========================================
  dynamic "http_listener" {
    for_each = local.appgw_default_http_listeners
    content {
      name                           = http_listener.value.name
      frontend_ip_configuration_name = http_listener.value.frontend_ip_configuration_name
      frontend_port_name             = http_listener.value.frontend_port_name
      protocol                       = http_listener.value.protocol
      host_name                      = http_listener.value.host_name
      ssl_certificate_name           = http_listener.value.ssl_certificate_name
    }
  }

  # ========================================
  # HTTP Listeners (validator app - hostname-based)
  # ========================================
  dynamic "http_listener" {
    for_each = local.validator_http_listeners_enabled
    content {
      name                           = http_listener.value.name
      frontend_ip_configuration_name = http_listener.value.frontend_ip_configuration_name
      frontend_port_name             = http_listener.value.frontend_port_name
      protocol                       = http_listener.value.protocol
      host_name                      = http_listener.value.host_name
      ssl_certificate_name           = http_listener.value.ssl_certificate_name
    }
  }

  # ========================================
  # URL Path Maps
  # ========================================
  dynamic "url_path_map" {
    for_each = local.validator_url_path_maps
    content {
      name                               = url_path_map.value.name
      default_backend_address_pool_name  = url_path_map.value.default_backend_address_pool_name
      default_backend_http_settings_name = url_path_map.value.default_backend_http_settings_name

      dynamic "path_rule" {
        for_each = url_path_map.value.path_rules
        content {
          name                       = path_rule.value.name
          paths                      = path_rule.value.paths
          backend_address_pool_name  = path_rule.value.backend_address_pool_name
          backend_http_settings_name = path_rule.value.backend_http_settings_name
        }
      }
    }
  }

  # ========================================
  # Request Routing Rules (default)
  # ========================================
  dynamic "request_routing_rule" {
    for_each = local.appgw_default_routing_rules
    content {
      name               = request_routing_rule.value.name
      rule_type          = request_routing_rule.value.rule_type
      http_listener_name = request_routing_rule.value.http_listener_name
      url_path_map_name  = request_routing_rule.value.url_path_map_name
      priority           = request_routing_rule.value.priority
    }
  }

  # ========================================
  # Request Routing Rules (validator app)
  # ========================================
  dynamic "request_routing_rule" {
    for_each = local.validator_request_routing_rules_enabled
    content {
      name               = request_routing_rule.value.name
      rule_type          = request_routing_rule.value.rule_type
      http_listener_name = request_routing_rule.value.http_listener_name
      url_path_map_name  = request_routing_rule.value.url_path_map_name
      priority           = request_routing_rule.value.priority
    }
  }

  tags = {
    environment = "shared"
  }
}

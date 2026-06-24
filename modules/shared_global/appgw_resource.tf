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
  http2_enabled       = true

  lifecycle {
    prevent_destroy = true
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      "/subscriptions/7d72da57-155c-4d56-883e-0e68a747e9e1/resourceGroups/ismd-asistent-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/ismd-identity"
    ]
  }

  # WAF_v2 (required for WAF features — rate limiting, OWASP CRS). Bumped from
  # Standard_v2; this is an in-place SKU update, not a replacement.
  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  # Gateway-wide WAF policy (rate limiting + OWASP CRS 3.2). Applies to all
  # listeners/hostnames. See waf_policy.tf.
  firewall_policy_id = azurerm_web_application_firewall_policy.appgw.id

  # Modern predefined SSL policy. Default (sslPolicy = null) inherits Azure's
  # base policy which permits TLS renegotiation on TLS 1.2 connections — that
  # tripped Azure's App Insights Standard Web Test agents with
  # "The function requested is not supported" (Windows ERROR_NOT_SUPPORTED
  # from Schannel when the server requests renegotiation). 20220101 is the
  # current Microsoft-recommended baseline: TLS 1.2 + 1.3, no renegotiation,
  # AEAD ciphers only.
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  zones = ["1", "2", "3"]

  autoscale_configuration {
    # Warm floor of 1 capacity unit so the gateway never serves from a cold
    # zero — scale-out to higher capacity takes minutes, so a 0 floor risks
    # latency/5xx on the first burst after idle. Scales up to max under load.
    min_capacity = 1
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
    for_each = concat(local.validator_backend_pools, local.tool_backend_pools)
    content {
      name  = backend_address_pool.value.name
      fqdns = backend_address_pool.value.fqdns
    }
  }

  # ========================================
  # Health Probes
  # ========================================
  dynamic "probe" {
    for_each = concat(local.validator_probes, local.tool_probes)
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
    for_each = concat(local.validator_backend_http_settings, local.tool_backend_http_settings)
    content {
      name                                = backend_http_settings.value.name
      cookie_based_affinity               = backend_http_settings.value.cookie_based_affinity
      port                                = backend_http_settings.value.port
      protocol                            = backend_http_settings.value.protocol
      request_timeout                     = backend_http_settings.value.request_timeout
      probe_name                          = backend_http_settings.value.probe_name
      pick_host_name_from_backend_address = backend_http_settings.value.pick_host_name_from_backend_address
      host_name                           = try(backend_http_settings.value.host_name, null)
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
  # Redirect Configurations
  # ========================================
  dynamic "redirect_configuration" {
    for_each = concat(local.appgw_redirect_configurations, local.validator_redirect_configurations)
    content {
      name                 = redirect_configuration.value.name
      redirect_type        = redirect_configuration.value.redirect_type
      target_url           = redirect_configuration.value.target_url
      target_listener_name = redirect_configuration.value.target_listener_name
      include_path         = redirect_configuration.value.include_path
      include_query_string = redirect_configuration.value.include_query_string
    }
  }

  # ========================================
  # Rewrite Rule Sets (Keycloak headers)
  # ========================================
  dynamic "rewrite_rule_set" {
    for_each = local.tool_keycloak_rewrite_rule_sets
    content {
      name = rewrite_rule_set.value.name

      rewrite_rule {
        name          = "set-forwarded-headers"
        rule_sequence = 1

        request_header_configuration {
          header_name  = "X-Forwarded-Proto"
          header_value = "https"
        }

        request_header_configuration {
          header_name  = "X-Forwarded-Host"
          header_value = rewrite_rule_set.value.host_name
        }

        request_header_configuration {
          header_name  = "X-Forwarded-Port"
          header_value = "443"
        }

        request_header_configuration {
          header_name  = "Forwarded"
          header_value = "proto=https;host=${rewrite_rule_set.value.host_name}"
        }

        response_header_configuration {
          header_name  = "X-AppGW-Rewrite"
          header_value = "keycloak"
        }

        response_header_configuration {
          header_name  = "X-AppGW-Forwarded-Proto"
          header_value = "https"
        }

        response_header_configuration {
          header_name  = "X-Frame-Options"
          header_value = ""
        }

      }
    }
  }

  # ========================================
  # URL Path Maps
  # ========================================
  dynamic "url_path_map" {
    for_each = local.validator_url_path_maps
    content {
      name                                = url_path_map.value.name
      default_backend_address_pool_name   = url_path_map.value.default_backend_address_pool_name
      default_backend_http_settings_name  = url_path_map.value.default_backend_http_settings_name
      default_redirect_configuration_name = try(url_path_map.value.default_redirect_configuration_name, null)

      dynamic "path_rule" {
        for_each = url_path_map.value.path_rules
        content {
          name                        = path_rule.value.name
          paths                       = path_rule.value.paths
          backend_address_pool_name   = try(path_rule.value.backend_address_pool_name, null)
          backend_http_settings_name  = try(path_rule.value.backend_http_settings_name, null)
          redirect_configuration_name = try(path_rule.value.redirect_configuration_name, null)
          rewrite_rule_set_name       = try(path_rule.value.rewrite_rule_set_name, null)
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

  # ========================================
  # Custom Error Pages
  # ========================================
  custom_error_configuration {
    status_code           = "HttpStatus502"
    custom_error_page_url = "${azurerm_storage_account.error_pages.primary_web_endpoint}502.html"
  }

  custom_error_configuration {
    status_code           = "HttpStatus403"
    custom_error_page_url = "${azurerm_storage_account.error_pages.primary_web_endpoint}403.html"
  }

  tags = {
    environment = "shared"
  }
}

# Application Gateway Configuration for Validator App
# This file contains all configuration data for the Validator application across all environments

locals {
  # Environment-specific settings
  validator_environments = ["dev", "test", "prod"]

  # Backend Address Pools
  validator_backend_pools = flatten([
    for env in local.validator_environments : [
      {
        name  = "validator-${env}-fe-pool"
        fqdns = env == "dev" ? (var.frontend_fqdn != "" ? [var.frontend_fqdn] : []) : env == "test" ? (var.frontend_fqdn_test != "" ? [var.frontend_fqdn_test] : []) : (var.frontend_fqdn_prod != "" ? [var.frontend_fqdn_prod] : [])
      },
      {
        name  = "validator-${env}-be-pool"
        fqdns = env == "dev" ? (var.backend_fqdn != "" ? [var.backend_fqdn] : []) : env == "test" ? (var.backend_fqdn_test != "" ? [var.backend_fqdn_test] : []) : (var.backend_fqdn_prod != "" ? [var.backend_fqdn_prod] : [])
      }
    ]
  ])

  # Health Probes
  validator_probes = flatten([
    for env in local.validator_environments : [
      {
        name                                      = "validator-${env}-fe-probe"
        protocol                                  = "Http"
        path                                      = "/"
        interval                                  = 30
        timeout                                   = 30
        unhealthy_threshold                       = 3
        pick_host_name_from_backend_http_settings = true
        match_status_codes                        = ["200-399"]
      },
      {
        name                                      = "validator-${env}-be-probe"
        protocol                                  = "Http"
        path                                      = "/actuator/health"
        interval                                  = 30
        timeout                                   = 30
        unhealthy_threshold                       = 3
        pick_host_name_from_backend_http_settings = true
        match_status_codes                        = ["200-399"]
      }
    ]
  ])

  # Backend HTTP Settings
  validator_backend_http_settings = flatten([
    for env in local.validator_environments : [
      # Frontend settings
      {
        name                                = "validator-${env}-fe-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "validator-${env}-fe-probe"
        pick_host_name_from_backend_address = true
        path                                = "/"
      },
      # Backend API settings (with /api/ path)
      {
        name                                = "validator-${env}-be-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "validator-${env}-be-probe"
        pick_host_name_from_backend_address = true
        path                                = "/api/"
      },
      # Backend root settings (no path rewrite)
      {
        name                                = "validator-${env}-be-root-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "validator-${env}-be-probe"
        pick_host_name_from_backend_address = true
        path                                = "/"
      },
      # Backend swagger UI settings
      {
        name                                = "validator-${env}-be-swagger-ui-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "validator-${env}-be-probe"
        pick_host_name_from_backend_address = true
        path                                = "/swagger-ui/index.html"
      },
      # Backend pass-through settings (no path override)
      {
        name                                = "validator-${env}-be-pass-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "validator-${env}-be-probe"
        pick_host_name_from_backend_address = true
        path                                = null
      }
    ]
  ])

  # HTTP Listeners (hostname-based)
  validator_http_listeners = flatten([
    for env in local.validator_environments : [
      # HTTP listener IPv4
      {
        name                           = "http-host-${env}-listener"
        frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
        frontend_port_name             = "port_80"
        protocol                       = "Http"
        host_name = env == "dev" ? var.dev_hostname : env == "test" ? var.test_hostname : var.prod_hostname
        ssl_certificate_name           = null
        enabled                        = env == "dev" ? var.dev_hostname != "" : env == "test" ? var.test_hostname != "" : var.prod_hostname != ""
      },
      # HTTPS listener IPv4
      {
        name                           = "https-host-${env}-listener"
        frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
        frontend_port_name             = "port_443"
        protocol                       = "Https"
        host_name                      = env == "dev" ? var.dev_hostname : env == "test" ? var.test_hostname : var.prod_hostname
        ssl_certificate_name           = "datagov-cz"
        enabled                        = env == "dev" ? var.dev_hostname != "" : env == "test" ? var.test_hostname != "" : var.prod_hostname != ""
      },
      # HTTP listener IPv6
      {
        name                           = "http-host-${env}-listener-ipv6"
        frontend_ip_configuration_name = "appGwPublicFrontendIpIPv6"
        frontend_port_name             = "port_80"
        protocol                       = "Http"
        host_name                      = env == "dev" ? var.dev_hostname : env == "test" ? var.test_hostname : var.prod_hostname
        ssl_certificate_name           = null
        enabled                        = env == "dev" ? var.dev_hostname != "" : env == "test" ? var.test_hostname != "" : var.prod_hostname != ""
      },
      # HTTPS listener IPv6
      {
        name                           = "https-host-${env}-listener-ipv6"
        frontend_ip_configuration_name = "appGwPublicFrontendIpIPv6"
        frontend_port_name             = "port_443"
        protocol                       = "Https"
        host_name                      = env == "dev" ? var.dev_hostname : env == "test" ? var.test_hostname : var.prod_hostname
        ssl_certificate_name           = "datagov-cz"
        enabled                        = env == "dev" ? var.dev_hostname != "" : env == "test" ? var.test_hostname != "" : var.prod_hostname != ""
      }
    ]
  ])

  # Filter enabled listeners
  validator_http_listeners_enabled = [
    for listener in local.validator_http_listeners : listener if listener.enabled
  ]

  # URL Path Maps
  validator_url_path_maps = [
    for env in local.validator_environments : {
      name                               = "path-map-${env}"
      default_backend_address_pool_name  = "validator-${env}-fe-pool"
      default_backend_http_settings_name = "validator-${env}-fe-http-settings"
      path_rules = [
        {
          name                       = "api-rule-${env}"
          paths                      = ["/validator/api/*", "/validator/api", "/api/*", "/api"]
          backend_address_pool_name  = "validator-${env}-be-pool"
          backend_http_settings_name = "validator-${env}-be-http-settings"
        },
        {
          name                       = "swagger-ui-index-rule-${env}"
          paths                      = ["/swagger-ui", "/swagger-ui/"]
          backend_address_pool_name  = "validator-${env}-be-pool"
          backend_http_settings_name = "validator-${env}-be-swagger-ui-http-settings"
        },
        {
          name                       = "validator-swagger-ui-index-rule-${env}"
          paths                      = ["/validator/swagger-ui", "/validator/swagger-ui/", "/validator/swagger-ui/index.html"]
          backend_address_pool_name  = "validator-${env}-be-pool"
          backend_http_settings_name = "validator-${env}-be-swagger-ui-http-settings"
        },
        {
          name                       = "swagger-ui-rule-${env}"
          paths                      = ["/swagger-ui/*"]
          backend_address_pool_name  = "validator-${env}-be-pool"
          backend_http_settings_name = "validator-${env}-be-pass-http-settings"
        },
        {
          name                       = "openapi-v3-rule-${env}"
          paths                      = ["/v3/*", "/v3"]
          backend_address_pool_name  = "validator-${env}-be-pool"
          backend_http_settings_name = "validator-${env}-be-pass-http-settings"
        },
        {
          name                       = "frontend-rule-${env}"
          paths                      = ["/validator/*", "/validator", "/*"]
          backend_address_pool_name  = "validator-${env}-fe-pool"
          backend_http_settings_name = "validator-${env}-fe-http-settings"
        }
      ]
    }
  ]

  # Request Routing Rules
  validator_request_routing_rules = flatten([
    for env in local.validator_environments : [
      # HTTP rule IPv4
      {
        name               = "http-host-${env}-rule"
        rule_type          = "PathBasedRouting"
        http_listener_name = "http-host-${env}-listener"
        url_path_map_name  = "path-map-${env}"
        priority           = env == "dev" ? 150 : env == "test" ? 200 : 250
        enabled            = env == "dev" ? var.dev_hostname != "" : env == "test" ? var.test_hostname != "" : var.prod_hostname != ""
      },
      # HTTPS rule IPv4
      {
        name               = "https-host-${env}-rule"
        rule_type          = "PathBasedRouting"
        http_listener_name = "https-host-${env}-listener"
        url_path_map_name  = "path-map-${env}"
        priority           = env == "dev" ? 151 : env == "test" ? 201 : 251
        enabled            = env == "dev" ? var.dev_hostname != "" : env == "test" ? var.test_hostname != "" : var.prod_hostname != ""
      },
      # HTTP rule IPv6
      {
        name               = "http-host-${env}-rule-ipv6"
        rule_type          = "PathBasedRouting"
        http_listener_name = "http-host-${env}-listener-ipv6"
        url_path_map_name  = "path-map-${env}"
        priority           = env == "dev" ? 152 : env == "test" ? 202 : 252
        enabled            = env == "dev" ? var.dev_hostname != "" : env == "test" ? var.test_hostname != "" : var.prod_hostname != ""
      },
      # HTTPS rule IPv6
      {
        name               = "https-host-${env}-rule-ipv6"
        rule_type          = "PathBasedRouting"
        http_listener_name = "https-host-${env}-listener-ipv6"
        url_path_map_name  = "path-map-${env}"
        priority           = env == "dev" ? 153 : env == "test" ? 203 : 253
        enabled            = env == "dev" ? var.dev_hostname != "" : env == "test" ? var.test_hostname != "" : var.prod_hostname != ""
      }
    ]
  ])

  # Filter enabled routing rules
  validator_request_routing_rules_enabled = [
    for rule in local.validator_request_routing_rules : rule if rule.enabled
  ]
}

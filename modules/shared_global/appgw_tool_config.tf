# Application Gateway Configuration for Tool App
# This file contains all configuration data for the Tool application across all environments

locals {
  # Environment-specific settings for tool
  tool_environments = ["dev", "test", "prod"]
  tool_hostnames = {
    dev  = var.dev_hostname
    test = var.test_hostname
    prod = var.prod_hostname
  }

  # Tool Backend Address Pools
  tool_backend_pools = flatten([
    for env in local.tool_environments : [
      {
        name  = "tool-${env}-fe-pool"
        fqdns = var.container_app_environment_domain_dev != "" && env == "dev" ? ["ismd-tool-frontend-dev.${var.container_app_environment_domain_dev}"] : var.container_app_environment_domain_test != "" && env == "test" ? ["ismd-tool-frontend-test.${var.container_app_environment_domain_test}"] : var.container_app_environment_domain_prod != "" && env == "prod" ? ["ismd-tool-frontend-prod.${var.container_app_environment_domain_prod}"] : []
      },
      {
        name  = "tool-${env}-be-pool"
        fqdns = var.container_app_environment_domain_dev != "" && env == "dev" ? ["ismd-tool-backend-dev.${var.container_app_environment_domain_dev}"] : var.container_app_environment_domain_test != "" && env == "test" ? ["ismd-tool-backend-test.${var.container_app_environment_domain_test}"] : var.container_app_environment_domain_prod != "" && env == "prod" ? ["ismd-tool-backend-prod.${var.container_app_environment_domain_prod}"] : []
      },
      {
        name  = "tool-${env}-keycloak-pool"
        fqdns = var.container_app_environment_domain_dev != "" && env == "dev" ? ["ismd-tool-keycloak-dev.${var.container_app_environment_domain_dev}"] : var.container_app_environment_domain_test != "" && env == "test" ? ["ismd-tool-keycloak-test.${var.container_app_environment_domain_test}"] : var.container_app_environment_domain_prod != "" && env == "prod" ? ["ismd-tool-keycloak-prod.${var.container_app_environment_domain_prod}"] : []
      }
    ]
  ])

  tool_keycloak_rewrite_rule_sets = flatten([
    for env in local.tool_environments : (
      local.tool_hostnames[env] != "" && length(regexall("^[\\x20-\\x7E]+$", local.tool_hostnames[env])) > 0 ? [
        {
          name      = "tool-keycloak-headers-${env}"
          host_name = local.tool_hostnames[env]
        }
      ] : []
    )
  ])

  # Tool Health Probes
  tool_probes = flatten([
    for env in local.tool_environments : [
      {
        name                                      = "tool-${env}-fe-probe"
        protocol                                  = "Http"
        path                                      = "/popisujeme"
        interval                                  = 30
        timeout                                   = 30
        unhealthy_threshold                       = 3
        pick_host_name_from_backend_http_settings = true
        match_status_codes                        = ["200-399"]
      },
      {
        name                                      = "tool-${env}-be-probe"
        protocol                                  = "Http"
        path                                      = "/popisujeme/actuator/health"
        interval                                  = 30
        timeout                                   = 30
        unhealthy_threshold                       = 3
        pick_host_name_from_backend_http_settings = true
        match_status_codes                        = ["200-399"]
      },
      {
        name                                      = "tool-${env}-keycloak-probe"
        protocol                                  = "Http"
        path                                      = "/popisujeme/auth/health/ready"
        interval                                  = 30
        timeout                                   = 30
        unhealthy_threshold                       = 3
        pick_host_name_from_backend_http_settings = true
        match_status_codes                        = ["200-399"]
      }
    ]
  ])

  # Tool Backend HTTP Settings
  tool_backend_http_settings = flatten([
    for env in local.tool_environments : [
      # Frontend settings
      {
        name                                = "tool-${env}-fe-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "tool-${env}-fe-probe"
        pick_host_name_from_backend_address = true
        path                                = null
      },
      # Backend API settings (rewrites /popisujeme/be/api/* → /popisujeme/api/*)
      {
        name                                = "tool-${env}-be-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "tool-${env}-be-probe"
        pick_host_name_from_backend_address = true
        path                                = "/popisujeme/api/"
      },
      # Backend pass-through settings
      {
        name                                = "tool-${env}-be-pass-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "tool-${env}-be-probe"
        pick_host_name_from_backend_address = true
        path                                = null
      },
      # Keycloak settings
      {
        name                                = "tool-${env}-keycloak-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "tool-${env}-keycloak-probe"
        pick_host_name_from_backend_address = false
        host_name                           = env == "dev" && var.container_app_environment_domain_dev != "" ? "ismd-tool-keycloak-dev.${var.container_app_environment_domain_dev}" : env == "test" && var.container_app_environment_domain_test != "" ? "ismd-tool-keycloak-test.${var.container_app_environment_domain_test}" : env == "prod" && var.container_app_environment_domain_prod != "" ? "ismd-tool-keycloak-prod.${var.container_app_environment_domain_prod}" : null
        path                                = null
      }
    ]
  ])

  # Tool path rules to be added to existing URL path maps
  tool_path_rules = {
    for env in local.tool_environments : env => [
      {
        name                       = "tool-keycloak-rule-${env}"
        paths                      = ["/popisujeme/auth", "/popisujeme/auth/*"]
        backend_address_pool_name  = "tool-${env}-keycloak-pool"
        backend_http_settings_name = "tool-${env}-keycloak-http-settings"
        rewrite_rule_set_name      = local.tool_hostnames[env] != "" && length(regexall("^[\\x20-\\x7E]+$", local.tool_hostnames[env])) > 0 ? "tool-keycloak-headers-${env}" : null
      },
      {
        name                       = "tool-api-rule-${env}"
        paths                      = ["/popisujeme/api/*", "/popisujeme/api"]
        backend_address_pool_name  = "tool-${env}-fe-pool"
        backend_http_settings_name = "tool-${env}-fe-http-settings"
      },
      {
        name                       = "tool-api-docs-rule-${env}"
        paths                      = ["/popisujeme/api-docs", "/popisujeme/api-docs/*"]
        backend_address_pool_name  = "tool-${env}-be-pool"
        backend_http_settings_name = "tool-${env}-be-pass-http-settings"
      },
      {
        name                       = "tool-v3-api-docs-rule-${env}"
        paths                      = ["/popisujeme/v3/*"]
        backend_address_pool_name  = "tool-${env}-be-pool"
        backend_http_settings_name = "tool-${env}-be-pass-http-settings"
      },
      {
        name                       = "tool-swagger-ui-rule-${env}"
        paths                      = ["/popisujeme/swagger-ui/*", "/popisujeme/swagger-ui", "/popisujeme/swagger-ui.html"]
        backend_address_pool_name  = "tool-${env}-be-pool"
        backend_http_settings_name = "tool-${env}-be-pass-http-settings"
      },
      {
        name                       = "tool-actuator-rule-${env}"
        paths                      = ["/popisujeme/actuator/*"]
        backend_address_pool_name  = "tool-${env}-be-pool"
        backend_http_settings_name = "tool-${env}-be-pass-http-settings"
      },
      {
        name                       = "tool-frontend-rule-${env}"
        paths                      = ["/popisujeme/*", "/popisujeme"]
        backend_address_pool_name  = "tool-${env}-fe-pool"
        backend_http_settings_name = "tool-${env}-fe-http-settings"
      }
    ]
  }
}

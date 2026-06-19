# Application Gateway Configuration for Tool App
# This file contains all configuration data for the Tool application across all environments
#
# Architecture note: tool-backend uses internal ingress (BFF) on TEST/PROD —
# browser traffic routes through tool-frontend, which proxies to the backend
# internally; App Gateway routes only to tool-frontend and tool-keycloak there.
#
# DEV exception: tool-backend is external-enabled and App Gateway exposes a
# dedicated direct route /popisujeme/be/* → tool-dev-be-pool (the /be prefix is
# stripped to /popisujeme/* by the backend HTTP setting). This enables the
# local-frontend → DEV-backend dev loop without colliding with the frontend's
# own /popisujeme/api/* routes. TEST/PROD do NOT get this — pure BFF.

locals {
  # Environment-specific settings for tool
  tool_environments = ["dev", "test", "prod"]
  tool_hostnames = {
    dev  = var.dev_hostname
    test = var.test_hostname
    prod = var.prod_hostname
  }

  # Tool Backend Address Pools. DEV also gets a backend pool for the direct
  # local-frontend → DEV-backend dev loop; TEST/PROD stay BFF-only.
  tool_backend_pools = flatten([
    for env in local.tool_environments : concat([
      {
        name  = "tool-${env}-fe-pool"
        fqdns = var.container_app_environment_domain_dev != "" && env == "dev" ? ["ismd-tool-frontend-dev.${var.container_app_environment_domain_dev}"] : var.container_app_environment_domain_test != "" && env == "test" ? ["ismd-tool-frontend-test.${var.container_app_environment_domain_test}"] : var.container_app_environment_domain_prod != "" && env == "prod" ? ["ismd-tool-frontend-prod.${var.container_app_environment_domain_prod}"] : []
      },
      {
        name  = "tool-${env}-keycloak-pool"
        fqdns = var.container_app_environment_domain_dev != "" && env == "dev" ? ["ismd-tool-keycloak-dev.${var.container_app_environment_domain_dev}"] : var.container_app_environment_domain_test != "" && env == "test" ? ["ismd-tool-keycloak-test.${var.container_app_environment_domain_test}"] : var.container_app_environment_domain_prod != "" && env == "prod" ? ["ismd-tool-keycloak-prod.${var.container_app_environment_domain_prod}"] : []
      }
      ], env == "dev" && var.container_app_environment_domain_dev != "" ? [
      {
        name  = "tool-dev-be-pool"
        fqdns = ["ismd-tool-backend-dev.${var.container_app_environment_domain_dev}"]
      }
    ] : [])
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
    for env in local.tool_environments : concat([
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
        name                                      = "tool-${env}-keycloak-probe"
        protocol                                  = "Http"
        path                                      = "/popisujeme/auth/health/ready"
        interval                                  = 30
        timeout                                   = 30
        unhealthy_threshold                       = 3
        pick_host_name_from_backend_http_settings = true
        match_status_codes                        = ["200-399"]
      }
      ], env == "dev" && var.container_app_environment_domain_dev != "" ? [
      {
        name                                      = "tool-dev-be-probe"
        protocol                                  = "Http"
        path                                      = "/popisujeme/actuator/health"
        interval                                  = 30
        timeout                                   = 30
        unhealthy_threshold                       = 3
        pick_host_name_from_backend_http_settings = true
        match_status_codes                        = ["200-399"]
      }
    ] : [])
  ])

  # Tool Backend HTTP Settings
  tool_backend_http_settings = flatten([
    for env in local.tool_environments : concat([
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
      ], env == "dev" && var.container_app_environment_domain_dev != "" ? [
      # Backend direct-route settings: strips the /be prefix so
      # /popisujeme/be/* reaches the backend as /popisujeme/*.
      {
        name                                = "tool-dev-be-http-settings"
        cookie_based_affinity               = "Disabled"
        port                                = 80
        protocol                            = "Http"
        request_timeout                     = 60
        probe_name                          = "tool-dev-be-probe"
        pick_host_name_from_backend_address = true
        path                                = "/popisujeme/"
      }
    ] : [])
  ])

  # Tool path rules to be added to existing URL path maps.
  # DEV inserts a direct backend route (/popisujeme/be/*) ahead of the
  # frontend catch-all; TEST/PROD keep only fe + keycloak (pure BFF).
  tool_path_rules = {
    for env in local.tool_environments : env => concat([
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
      }
      ], env == "dev" && var.container_app_environment_domain_dev != "" ? [
      {
        name                       = "tool-dev-be-direct-rule"
        paths                      = ["/popisujeme/be/*"]
        backend_address_pool_name  = "tool-dev-be-pool"
        backend_http_settings_name = "tool-dev-be-http-settings"
      }
      ] : [], [
      {
        name                       = "tool-frontend-rule-${env}"
        paths                      = ["/popisujeme/*", "/popisujeme"]
        backend_address_pool_name  = "tool-${env}-fe-pool"
        backend_http_settings_name = "tool-${env}-fe-http-settings"
      }
    ])
  }
}

# Test Environment — module composition
# Variables: variables.tf | Resource groups: resource_groups.tf | Networking: networking.tf | Outputs: outputs.tf

# Shared resources (networking, resource groups, etc.)
module "shared" {
  source = "../../modules/shared"

  environment                     = var.environment
  location                        = var.location
  resource_group_name             = var.shared_resource_group_name
  vnet_address_space              = "10.2.0.0/16"        # TEST: 10.2.x.x (avoids conflict with shared-global 10.1.x.x)
  vnet_address_space_ipv6         = "fd00:db8:decc::/48" # TEST: unique IPv6
  validator_subnet_address_prefix = "10.2.2.0/23"        # TEST: within 10.2.0.0/16
  tool_subnet_address_prefix      = "10.2.4.0/23"        # TEST: within 10.2.0.0/16
}

# Create validator apps using shared Container App Environment
module "validator_apps" {
  source = "../../modules/validator_apps"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.validator_resource_group_name

  # Required by the module
  shared_resource_group_name   = var.shared_resource_group_name
  container_app_environment_id = module.shared.shared_container_app_environment_id
  # Container Images
  frontend_image     = var.frontend_image
  frontend_image_tag = var.frontend_image_tag
  backend_image      = var.backend_image
  backend_image_tag  = var.backend_image_tag

  # IP Restrictions
  app_gateway_public_ip = var.app_gateway_public_ip_address
  app_gateway_hostname  = var.app_gateway_hostname

  # CORS
  additional_cors_origins = var.additional_cors_origins

  # App names
  frontend_app_name = var.frontend_app_name
  backend_app_name  = var.backend_app_name

  # Workload profile configuration
  workload_profile_name = "default"

  # Frontend gating (live | coming_soon | maintenance)
  site_status         = var.validator_site_status
  site_preview_secret = var.validator_site_preview_secret

  depends_on = [
    module.shared,
    azurerm_resource_group.validator
  ]
}

# Create tool apps using shared Container App Environment
module "tool_apps" {
  count  = var.deploy_tool_apps ? 1 : 0
  source = "../../modules/tool_apps"

  environment         = var.environment
  location            = var.location
  resource_group_name = var.tool_resource_group_name

  # Required by the module
  shared_resource_group_name               = var.shared_resource_group_name
  container_app_environment_id             = module.shared.shared_container_app_environment_id
  container_app_environment_default_domain = module.shared.shared_container_app_environment_default_domain

  # Container Images
  frontend_image     = var.tool_frontend_image
  frontend_image_tag = var.tool_frontend_image_tag
  backend_image      = var.tool_backend_image
  backend_image_tag  = var.tool_backend_image_tag

  # IP Restrictions
  app_gateway_public_ip = var.app_gateway_public_ip_address
  app_gateway_hostname  = var.app_gateway_hostname

  # CORS
  additional_cors_origins = var.additional_cors_origins

  # App names
  frontend_app_name = var.tool_frontend_app_name
  backend_app_name  = var.tool_backend_app_name

  # Workload profile configuration
  workload_profile_name = "default"

  # Database & Fuseki Configuration
  deploy_postgres         = true
  deploy_fuseki           = true
  postgres_db_name        = "ismd_tool_db"
  postgres_admin_user     = "ismdadmin"
  postgres_admin_password = var.tool_postgres_password
  postgres_sku_name       = "B_Standard_B2s" # Burstable for test
  postgres_storage_mb     = 32768            # 32GB

  # Fallback external URLs (used if deploy_postgres/fuseki = false)
  postgres_url      = var.tool_postgres_url
  postgres_user     = var.tool_postgres_user
  postgres_password = var.tool_postgres_password
  fuseki_url        = var.tool_fuseki_url

  # Frontend auth
  nextauth_secret = var.tool_nextauth_secret
  tool_base_path  = var.tool_base_path

  # Frontend gating (live | coming_soon | maintenance)
  site_status         = var.tool_site_status
  site_preview_secret = var.tool_site_preview_secret

  # Keycloak / CAAIS
  deploy_keycloak         = var.tool_deploy_keycloak
  enable_caais            = var.tool_enable_caais
  keycloak_image          = var.tool_keycloak_image
  keycloak_image_tag      = var.tool_keycloak_image_tag
  keycloak_app_name       = var.tool_keycloak_app_name
  keycloak_admin_user     = var.tool_keycloak_admin_user
  keycloak_admin_password = var.tool_keycloak_admin_password
  keycloak_hostname       = var.tool_keycloak_hostname
  keycloak_realm          = var.tool_keycloak_realm
  keycloak_issuer_uri     = var.tool_keycloak_issuer_uri
  keycloak_client_id      = var.tool_keycloak_client_id
  keycloak_client_secret  = var.tool_keycloak_client_secret
  caais_client_id         = var.tool_caais_client_id

  depends_on = [
    module.shared,
    azurerm_resource_group.tool[0]
  ]
}

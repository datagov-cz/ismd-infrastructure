# Frontend Container App for Tool

locals {
  tool_frontend_scheme = var.environment == "dev" && var.app_gateway_hostname == "" ? "http" : "https"
  tool_frontend_host   = var.app_gateway_hostname != "" ? var.app_gateway_hostname : var.app_gateway_public_ip
  tool_base_path       = trimspace(var.tool_base_path) == "" ? "" : (startswith(trimspace(var.tool_base_path), "/") ? trimsuffix(trimspace(var.tool_base_path), "/") : "/${trimsuffix(trimspace(var.tool_base_path), "/")}")

  tool_frontend_base_url = "${local.tool_frontend_scheme}://${local.tool_frontend_host}${local.tool_base_path}"
  tool_nextauth_url      = "${local.tool_frontend_base_url}/api/auth"
}

resource "azurerm_container_app" "frontend" {
  name                         = "${var.frontend_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  # Set workload profile name based on environment
  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  template {
    min_replicas = 1
    container {
      name   = "ismd-tool-frontend-${var.environment}"
      image  = "${var.frontend_image}:${var.frontend_image_tag}"
      cpu    = 0.5
      memory = "1Gi"
      env {
        name = "NEXT_PUBLIC_BE_URL"
        # Include protocol and optional tool base path prefix
        value = local.tool_frontend_base_url
      }
      env {
        name  = "NEXT_PUBLIC_BASE_PATH"
        value = local.tool_base_path
      }
      env {
        name  = "KEYCLOAK_ISSUER"
        value = local.keycloak_issuer_uri
      }
      env {
        name  = "KEYCLOAK_CLIENT_ID"
        value = var.keycloak_client_id
      }
      env {
        name        = "KEYCLOAK_CLIENT_SECRET"
        secret_name = "keycloak-client-secret"
      }
      env {
        name  = "NEXTAUTH_URL"
        value = local.tool_nextauth_url
      }
      env {
        name  = "NODE_ENV"
        value = var.environment == "prod" ? "production" : "development"
      }
      env {
        name        = "NEXTAUTH_SECRET"
        secret_name = "nextauth-secret"
      }
    }
  }

  secret {
    name  = "nextauth-secret"
    value = var.nextauth_secret
  }

  secret {
    name  = "keycloak-client-secret"
    value = var.keycloak_client_secret
  }

  ingress {
    external_enabled = true
    target_port      = 3000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }

    allow_insecure_connections = true

    # Restrict ingress to Application Gateway public IP (only when known)
    dynamic "ip_security_restriction" {
      for_each = var.app_gateway_public_ip != "" ? [var.app_gateway_public_ip] : []
      content {
        name             = "AllowAppGateway"
        ip_address_range = "${ip_security_restriction.value}/32"
        action           = "Allow"
      }
    }
  }

  tags = {
    Environment = var.environment
    Application = "Tool"
    ManagedBy   = "Terraform"
    Location    = var.location
    SharedRG    = var.shared_resource_group_name
  }

  lifecycle {
    ignore_changes = [
      template[0].container[0].image
    ]
  }
}

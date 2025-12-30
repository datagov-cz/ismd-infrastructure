# Frontend Container App for Tool

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
        # Include protocol and /popisujeme path
        value = var.environment == "dev" ? (var.app_gateway_hostname != "" ? "http://${var.app_gateway_hostname}/popisujeme" : "http://${var.app_gateway_public_ip}/popisujeme") : (var.app_gateway_hostname != "" ? "https://${var.app_gateway_hostname}/popisujeme" : "https://${var.app_gateway_public_ip}/popisujeme")
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

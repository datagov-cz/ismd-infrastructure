# Backend Container App for Validator

resource "azurerm_container_app" "backend" {
  name                         = "${var.backend_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  # Set workload profile name based on environment
  # For Consumption profile, set to null
  # For Dedicated profile, use the provided workload profile name
  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  identity {
    type = "SystemAssigned"
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

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

  template {
    min_replicas = 1
    container {
      name   = "ismd-validator-backend-${var.environment}"
      image  = "${var.backend_image}:${var.backend_image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name = "CORS_ALLOWED_ORIGINS"
        # Support both HTTP and HTTPS for dual-protocol access
        # Include both domain and IP for environments where both are used (e.g., DEV)
        value = var.app_gateway_hostname != "" && var.app_gateway_public_ip != "" ? "http://${var.app_gateway_hostname},https://${var.app_gateway_hostname},http://${var.app_gateway_public_ip},https://${var.app_gateway_public_ip}" : var.app_gateway_hostname != "" ? "http://${var.app_gateway_hostname},https://${var.app_gateway_hostname}" : var.app_gateway_public_ip != "" ? "http://${var.app_gateway_public_ip},https://${var.app_gateway_public_ip}" : ""
      }
      env {
        name  = "PORT"
        value = "8080"
      }
      # TODO: Change profile for production/test environments as needed
      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = "localhost"
      }
      liveness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/actuator/health"
        # Cost optimization: Longer intervals for dev environment
        interval_seconds = var.environment == "dev" ? 30 : 10
      }
      readiness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/actuator/health"
        interval_seconds = 10
      }
      startup_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/actuator/health"
        interval_seconds = 10
      }
    }
  }

  tags = {
    Environment = var.environment
    Application = "Validator"
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

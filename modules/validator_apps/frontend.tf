# Frontend Container App for Validator

resource "azurerm_container_app" "frontend" {
  name                         = "${var.frontend_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  # Set workload profile name based on environment
  # For Consumption profile, set to null
  # For Dedicated profile, use the provided workload profile name
  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  template {
    min_replicas = 1
    container {
      name   = "ismd-validator-frontend-${var.environment}"
      image  = "${var.frontend_image}:${var.frontend_image_tag}"
      cpu    = 0.5
      memory = "1Gi"
      env {
        # Server-side only — Next.js rewrites proxy /validujeme/api/* → backend internally.
        # Backend has internal ingress only; never exposed to the browser.
        name  = "BE_URL"
        value = "http://${azurerm_container_app.backend.name}/validujeme"
      }

      liveness_probe {
        transport               = "TCP"
        port                    = 3000
        interval_seconds        = 10
        failure_count_threshold = 3
        timeout                 = 5
      }

      readiness_probe {
        transport               = "TCP"
        port                    = 3000
        interval_seconds        = 8
        failure_count_threshold = 30
        success_count_threshold = 1
        timeout                 = 5
      }

      startup_probe {
        transport               = "TCP"
        port                    = 3000
        interval_seconds        = 8
        failure_count_threshold = 30
        timeout                 = 3
      }
    }
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

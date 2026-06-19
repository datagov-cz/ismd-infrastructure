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
      # BFF (use_bff=true): server-side BE_URL, Next.js proxies /validujeme/api/* → internal backend.
      # Legacy (use_bff=false): NEXT_PUBLIC_BE_URL baked at build time, browser hits backend directly via AppGW.
      dynamic "env" {
        for_each = var.use_bff ? [1] : []
        content {
          name  = "BE_URL"
          value = "http://${azurerm_container_app.backend.name}/validujeme"
        }
      }
      dynamic "env" {
        for_each = var.use_bff ? [] : [1]
        content {
          name  = "NEXT_PUBLIC_BE_URL"
          value = var.public_be_url
        }
      }
      env {
        name  = "SITE_STATUS"
        value = var.site_status
      }
      dynamic "env" {
        for_each = var.site_preview_secret != "" ? [1] : []
        content {
          name        = "SITE_PREVIEW_SECRET"
          secret_name = "site-preview-secret"
        }
      }
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = 3000
        path                    = "/validujeme"
        interval_seconds        = 10
        failure_count_threshold = 3
        timeout                 = 5
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = 3000
        path                    = "/validujeme"
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

  dynamic "secret" {
    for_each = var.site_preview_secret != "" ? [1] : []
    content {
      name  = "site-preview-secret"
      value = var.site_preview_secret
    }
  }

  secret {
    name  = "app-insights-connection-string"
    value = var.app_insights_connection_string
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

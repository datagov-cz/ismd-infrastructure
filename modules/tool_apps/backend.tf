# Backend Container App for Tool

locals {
  base_origins = compact([
    var.app_gateway_hostname != "" ? "http://${var.app_gateway_hostname}" : "",
    var.app_gateway_hostname != "" ? "https://${var.app_gateway_hostname}" : "",
    var.app_gateway_public_ip != "" ? "http://${var.app_gateway_public_ip}" : "",
    var.app_gateway_public_ip != "" ? "https://${var.app_gateway_public_ip}" : ""
  ])
  all_origins = concat(local.base_origins, var.additional_cors_origins)
}

resource "azurerm_container_app" "backend" {
  name                         = "${var.backend_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  # Set workload profile name based on environment
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
      name   = "ismd-tool-backend-${var.environment}"
      image  = "${var.backend_image}:${var.backend_image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "CORS_ALLOWED_ORIGINS"
        value = join(",", local.all_origins)
      }
      env {
        name  = "PORT"
        value = "8080"
      }
      env {
        name  = "SPRING_PROFILES_ACTIVE"
        # TODO: switch test back to "stage" once stage profile reads env vars (FUSEKI_URL, CORS_ALLOWED_ORIGINS)
        value = var.environment == "prod" ? "production" : "dev"
      }
      env {
        name  = "POSTGRES_URL"
        value = var.deploy_postgres ? "jdbc:postgresql://ismd-tool-postgres-${var.environment}.postgres.database.azure.com:5432/${var.postgres_db_name}?sslmode=require" : var.postgres_url
      }
      env {
        name  = "POSTGRES_USER"
        value = var.deploy_postgres ? var.postgres_admin_user : var.postgres_user
      }
      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "postgres-password"
      }
      env {
        name  = "FUSEKI_URL"
        value = var.deploy_fuseki ? "https://ismd-tool-fuseki-${var.environment}.internal.${var.container_app_environment_default_domain}/ds" : var.fuseki_url
      }
      env {
        name  = "KEYCLOAK_ISSUER_URI"
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
      liveness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/popisujeme/actuator/health"
        interval_seconds = var.environment == "dev" ? 30 : 10
      }
      readiness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/popisujeme/actuator/health"
        interval_seconds = 10
      }
      startup_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/popisujeme/actuator/health"
        interval_seconds        = 10
        failure_count_threshold = 12
        timeout                 = 5
      }
    }
  }

  secret {
    name  = "postgres-password"
    value = var.deploy_postgres ? var.postgres_admin_password : var.postgres_password
  }

  secret {
    name  = "keycloak-client-secret"
    value = var.keycloak_client_secret
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

# Keycloak Container App for Tool

locals {
  keycloak_jdbc_url = var.deploy_postgres ? "jdbc:postgresql://ismd-tool-postgres-${var.environment}.postgres.database.azure.com:5432/${var.keycloak_db_name}?sslmode=require" : var.keycloak_postgres_url
  keycloak_fqdn     = var.deploy_keycloak ? azurerm_container_app.keycloak[0].ingress[0].fqdn : ""

  # Only enforce a strict hostname when explicitly set via keycloak_hostname.
  # Falling back to app_gateway_hostname breaks direct admin console access.
  keycloak_hostname_effective = trimspace(var.keycloak_hostname)

  keycloak_issuer_host = local.keycloak_hostname_effective != "" ? local.keycloak_hostname_effective : local.keycloak_fqdn
  keycloak_issuer_uri  = var.keycloak_issuer_uri != "" ? var.keycloak_issuer_uri : (var.deploy_keycloak ? "https://${local.keycloak_issuer_host}/popisujeme/auth/realms/${var.keycloak_realm}" : "")
}

resource "azurerm_container_app" "keycloak" {
  count                        = var.deploy_keycloak ? 1 : 0
  name                         = "${var.keycloak_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "ismd-tool-keycloak-${var.environment}"
      image  = "${var.keycloak_image}:${var.keycloak_image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      args = concat([
        "start",
        "--http-enabled=true",
        "--http-port=8080",
        "--proxy-headers=forwarded"
        ], local.keycloak_hostname_effective == "" ? [] : [
        "--hostname=${local.keycloak_hostname_effective}",
        "--hostname-admin=${local.keycloak_hostname_effective}"
      ])

      env {
        name  = "KC_DB"
        value = "postgres"
      }
      env {
        name  = "KC_HTTP_PORT"
        value = "8080"
      }
      env {
        name  = "QUARKUS_HTTP_PORT"
        value = "8080"
      }
      env {
        name  = "QUARKUS_HTTP_HOST"
        value = "0.0.0.0"
      }
      env {
        # Keep strict mode off — Keycloak accepts requests from any hostname.
        # This avoids redirect loops when accessed directly or via App Gateway.
        # URL generation is controlled by KC_HOSTNAME + KC_HOSTNAME_STRICT_HTTPS instead.
        name  = "KC_HOSTNAME_STRICT"
        value = "false"
      }

      env {
        name  = "KC_HOSTNAME"
        value = local.keycloak_hostname_effective
      }
      env {
        name  = "KC_HOSTNAME_ADMIN"
        value = local.keycloak_hostname_effective
      }

      env {
        name  = "KC_HTTP_RELATIVE_PATH"
        value = "/popisujeme/auth"
      }
      env {
        name  = "PORT"
        value = "8080"
      }
      env {
        name  = "KC_DB_URL"
        value = local.keycloak_jdbc_url
      }
      env {
        name  = "KC_DB_USERNAME"
        value = var.deploy_postgres ? var.postgres_admin_user : var.keycloak_postgres_user
      }
      env {
        name        = "KC_DB_PASSWORD"
        secret_name = "keycloak-db-password"
      }
      env {
        name  = "KEYCLOAK_ADMIN"
        value = var.keycloak_admin_user
      }
      env {
        name        = "KEYCLOAK_ADMIN_PASSWORD"
        secret_name = "keycloak-admin-password"
      }
      env {
        name  = "KC_HEALTH_ENABLED"
        value = "true"
      }
      env {
        name  = "KC_SPI_SECURITY_HEADERS_DEFAULT_X_FRAME_OPTIONS"
        value = "SAMEORIGIN"
      }
      env {
        name  = "CAAIS_CLIENT_ID"
        value = var.enable_caais ? var.caais_client_id : ""
      }

      liveness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/popisujeme/auth/health/live"
        interval_seconds = 30
      }

      readiness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/popisujeme/auth/health/ready"
        interval_seconds = 10
      }

      startup_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/popisujeme/auth/health/ready"
        interval_seconds        = 15
        failure_count_threshold = 30
        timeout                 = 5
      }

    }
  }

  secret {
    name  = "keycloak-admin-password"
    value = var.keycloak_admin_password
  }

  secret {
    name  = "keycloak-db-password"
    value = var.deploy_postgres ? var.postgres_admin_password : var.keycloak_postgres_password
  }

  ingress {
    external_enabled           = true
    target_port                = 8080
    transport                  = "auto"
    allow_insecure_connections = true

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Keycloak"
    ManagedBy   = "Terraform"
    Location    = var.location
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      template[0].container[0].image
    ]
  }
}

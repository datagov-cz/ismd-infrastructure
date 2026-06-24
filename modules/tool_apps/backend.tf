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
    # BFF pattern: backend is internal-only by default. DEV flips this on
    # (backend_external_enabled) for the direct local-frontend → DEV-backend
    # dev loop via the App Gateway /popisujeme/be/* route. TEST/PROD stay false.
    external_enabled = var.backend_external_enabled
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
    allow_insecure_connections = true
  }

  template {
    min_replicas = 1
    max_replicas = 1 # Pinned to singleton: avoids DB connection pool exhaustion, no concurrency hardening needed
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
        name = "SPRING_PROFILES_ACTIVE"
        # Map env → Spring profile. application-<profile>.properties files exist
        # for dev, test, and production — all env-var-driven for env-specific
        # values (POSTGRES_URL, FUSEKI_URL, KEYCLOAK_ISSUER_URI, CORS_ALLOWED_ORIGINS).
        value = var.environment == "prod" ? "production" : var.environment
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
        value = var.deploy_fuseki ? "https://ismd-tool-fuseki-${var.environment}.internal.${var.container_app_environment_default_domain}/ismd-tool-dataset" : var.fuseki_url
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
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
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
        transport = "HTTP"
        port      = 8080
        path      = "/popisujeme/actuator/health"
        # 30 × 10s = 300s budget. Backend runs as a singleton (min=max=1),
        # so after a platform node-maintenance eviction the cold JVM boot (image pull +
        # Spring start + Postgres/Fuseki/Keycloak deps) is the whole outage window. A
        # tight budget kills the still-booting replica into a restart loop, extending the
        # gap and tripping the restart-count alert. 300s lets the cold start finish in one go.
        interval_seconds        = 10
        failure_count_threshold = 30
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

  secret {
    name  = "app-insights-connection-string"
    value = var.app_insights_connection_string
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

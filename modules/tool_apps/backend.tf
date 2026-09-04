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

# Dedicated identity for pulling this app's secrets from the per-env Key Vault.
# Pre-grantable, unlike SystemAssigned — the access policy can be created before the
# app exists. Declaration was lost in the nb/recovery restore while the resource stayed
# in state (and in Azure); restored 2026-08-06 so code matches reality, and so the
# backend_kv_identity_principal_id output resolves.
resource "azurerm_user_assigned_identity" "backend_kv" {
  name                = "${var.backend_app_name}-kv-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Backend-KV"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_container_app" "backend" {
  name                         = "${var.backend_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  # Set workload profile name based on environment
  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.backend_kv.id]
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
        name = "POSTGRES_USER"
        # Per-app user separation: dedicated role when set, else admin login. See backend_db_user.
        value = var.backend_db_user != "" ? var.backend_db_user : (var.deploy_postgres ? var.postgres_admin_user : var.postgres_user)
      }
      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "postgres-password"
      }
      # Hikari pool caps. LOAD-BEARING — the Postgres server is small and its
      # max_connections is limited, and every tenant on it (tool, keycloak, ai)
      # sizes its pool against the same ceiling. A reconnect storm has already
      # exhausted the 50-connection server once; see the idle-session timeouts in
      # database.tf. Do not raise without re-budgeting the other tenants.
      # Declaration was lost in the nb/recovery restore while the deployed apps
      # kept the values — restored 2026-08-12 so code matches reality.
      env {
        name  = "SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE"
        value = "10"
      }
      env {
        name  = "SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE"
        value = "2"
      }
      env {
        name  = "OUTBOX_DONE_RETENTION"
        value = var.outbox_done_retention
      }
      env {
        name  = "FUSEKI_URL"
        value = var.deploy_fuseki ? "https://ismd-tool-fuseki-${var.environment}.internal.${var.container_app_environment_default_domain}/ismd-tool-dataset" : var.fuseki_url
      }
      # Internal call to the validator backend over the shared Container App
      # Environment — app name only, ingress listens on 80, so no port. Also lost
      # in the nb/recovery restore; the variable survived, the env block didn't.
      # NKD SPARQL endpoint, one target per environment. Empty leaves the image
      # default (production NKD) in place — see application.properties.
      env {
        name  = "NKD_SPARQL_ENDPOINT"
        value = var.nkd_sparql_endpoint
      }
      env {
        name  = "VALIDATION_SERVICE_URL"
        value = "http://${var.validator_backend_app_name}/validujeme"
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
      # App Insights Java agent activation. The agent jar is baked into the image;
      # these envs (a) tell the JVM to load it and (b) pin cloud_RoleName so KQL /
      # the Failures blade filter cleanly. Gated so instrumentation is a per-env
      # config toggle with no image rebuild — see enable_app_insights_agent for the
      # image-must-ship-first ordering constraint. DEV only today; TEST/PROD leave
      # it false until their jar-bearing images ship.
      # Lost in the nb/recovery restore (the variable survived, these blocks did
      # not) — restored 2026-08-12 so code matches the deployed DEV backend.
      dynamic "env" {
        for_each = var.enable_app_insights_agent ? [1] : []
        content {
          name  = "JAVA_TOOL_OPTIONS"
          value = "-javaagent:/app/applicationinsights-agent.jar"
        }
      }
      dynamic "env" {
        for_each = var.enable_app_insights_agent ? [1] : []
        content {
          name  = "APPLICATIONINSIGHTS_ROLE_NAME"
          value = "${var.backend_app_name}-${var.environment}"
        }
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

  # Class A secrets: empty KV id = inline value, set = key_vault_secret_id reference
  # pulled by the backend's UserAssigned identity. The KV form was lost in the
  # nb/recovery restore while the deployed apps kept the references — restored
  # 2026-08-12 so code matches reality. Applying the inline form against an env
  # whose TF_VAR_* secrets are unset would overwrite live secrets with "".
  dynamic "secret" {
    for_each = var.postgres_password_kv_secret_id == "" ? [1] : []
    content {
      name  = "postgres-password"
      value = var.deploy_postgres ? var.postgres_admin_password : var.postgres_password
    }
  }
  dynamic "secret" {
    for_each = var.postgres_password_kv_secret_id != "" ? [1] : []
    content {
      name                = "postgres-password"
      key_vault_secret_id = var.postgres_password_kv_secret_id
      identity            = azurerm_user_assigned_identity.backend_kv.id
    }
  }

  dynamic "secret" {
    for_each = var.keycloak_client_secret_kv_secret_id == "" ? [1] : []
    content {
      name  = "keycloak-client-secret"
      value = var.keycloak_client_secret
    }
  }
  dynamic "secret" {
    for_each = var.keycloak_client_secret_kv_secret_id != "" ? [1] : []
    content {
      name                = "keycloak-client-secret"
      key_vault_secret_id = var.keycloak_client_secret_kv_secret_id
      identity            = azurerm_user_assigned_identity.backend_kv.id
    }
  }

  dynamic "secret" {
    for_each = var.app_insights_kv_secret_id == "" ? [1] : []
    content {
      name  = "app-insights-connection-string"
      value = var.app_insights_connection_string
    }
  }
  dynamic "secret" {
    for_each = var.app_insights_kv_secret_id != "" ? [1] : []
    content {
      name                = "app-insights-connection-string"
      key_vault_secret_id = var.app_insights_kv_secret_id
      identity            = azurerm_user_assigned_identity.backend_kv.id
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

# Backend Container App for Validator

locals {
  base_origins = compact([
    var.app_gateway_hostname != "" ? "http://${var.app_gateway_hostname}" : "",
    var.app_gateway_hostname != "" ? "https://${var.app_gateway_hostname}" : "",
    var.app_gateway_public_ip != "" ? "http://${var.app_gateway_public_ip}" : "",
    var.app_gateway_public_ip != "" ? "https://${var.app_gateway_public_ip}" : ""
  ])
  all_origins = concat(local.base_origins, var.additional_cors_origins)

  # App listen port. The backend runs the Spring "localhost" profile, whose
  # server.port is 8082 (a local-dev convention: 8080=keycloak, 8081=tool,
  # 8082=validator). The image ignores the PORT env var, so ingress + probes
  # must target wherever Tomcat actually binds. Sourced from var.backend_port so
  # each env can pin it to whatever its currently-deployed image binds.
  backend_port = var.backend_port
}

# Dedicated identity for pulling this app's secrets from the per-env Key Vault
# (see tool_apps/backend.tf for rationale — pre-grantable, unlike SystemAssigned).
resource "azurerm_user_assigned_identity" "backend_kv" {
  name                = "${var.backend_app_name}-kv-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = {
    Environment = var.environment
    Application = "Validator"
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
  # For Consumption profile, set to null
  # For Dedicated profile, use the provided workload profile name
  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.backend_kv.id]
  }

  ingress {
    # BFF (use_bff=true): internal only — all browser traffic via Next.js frontend.
    # Legacy (use_bff=false): externally exposed, restricted to AppGW public IP.
    external_enabled = !var.use_bff
    target_port      = local.backend_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }

    # Only relevant in legacy mode where ingress is external.
    dynamic "ip_security_restriction" {
      for_each = !var.use_bff && var.app_gateway_public_ip != "" ? [var.app_gateway_public_ip] : []
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
        # Also includes additional origins if specified
        value = join(",", local.all_origins)
      }
      env {
        name  = "PORT"
        value = tostring(local.backend_port)
      }
      # TODO: Change profile for production/test environments as needed
      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = "localhost"
      }
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
      }
      # App Insights Java agent activation. The agent jar is baked into the image;
      # these envs (a) tell the JVM to load it and (b) pin cloud_RoleName so KQL /
      # the Failures blade filter cleanly. Gated so instrumentation is a per-env
      # config toggle with no image rebuild — see enable_app_insights_agent for the
      # image-must-ship-first ordering constraint.
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
        transport = "HTTP"
        port      = local.backend_port
        path      = "/validujeme/actuator/health"
        # Cost optimization: Longer intervals for dev environment
        interval_seconds = var.environment == "dev" ? 30 : 10
      }
      readiness_probe {
        transport        = "HTTP"
        port             = local.backend_port
        path             = "/validujeme/actuator/health"
        interval_seconds = 10
      }
      startup_probe {
        transport = "HTTP"
        port      = local.backend_port
        path      = "/validujeme/actuator/health"
        # 30 × 10s = 300s budget. Matches the tool backend: a tight budget kills a
        # still-booting replica into a restart loop after a platform node-maintenance
        # eviction, extending the outage and tripping the restart-count alert. 300s lets
        # the cold JVM/Spring start finish in one pass.
        interval_seconds        = 10
        failure_count_threshold = 30
        timeout                 = 5
      }
    }
  }

  # app-insights: two-phase KV migration (Class A). Inline until its kv secret id
  # is set, then a Key Vault reference pulled by the backend's UserAssigned identity.
  dynamic "secret" {
    for_each = var.backend_app_insights_kv_secret_id == "" ? [1] : []
    content {
      name  = "app-insights-connection-string"
      value = var.app_insights_connection_string
    }
  }
  dynamic "secret" {
    for_each = var.backend_app_insights_kv_secret_id != "" ? [1] : []
    content {
      name                = "app-insights-connection-string"
      key_vault_secret_id = var.backend_app_insights_kv_secret_id
      identity            = azurerm_user_assigned_identity.backend_kv.id
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

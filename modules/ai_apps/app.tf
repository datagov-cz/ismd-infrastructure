# AI backend container app (internal-only)

locals {
  app_name = "${var.backend_app_name}-${var.environment}"

  # Force sslmode=require. The app's application.properties builds the JDBC URL
  # from APP_DB_* without an ssl parameter; Azure Postgres requires TLS, so we
  # override the whole datasource URL via Spring's SPRING_DATASOURCE_URL (relaxed
  # binding wins over the property template).
  datasource_url = "jdbc:postgresql://${var.postgres_fqdn}:5432/${var.postgres_db_name}?sslmode=require"

  # Emit a registry block only when a PAT is supplied. Empty = anonymous pull,
  # which is what the other (public-package) apps do.
  ghcr_auth_enabled = var.ghcr_token != "" || var.ghcr_token_kv_secret_id != ""

  # Whether an LLM API key exists at all (inline or in KV). While llm_enabled =
  # false no key is issued, and Container Apps rejects an empty secret value — so
  # the secret is only created when there is something to put in it.
  llm_api_key_present = var.llm_api_key != "" || var.llm_api_key_kv_secret_id != ""
}

# Dedicated identity for pulling this app's secrets from Key Vault. A pre-creatable
# UserAssigned identity can be granted KV access BEFORE the container app validates
# any key_vault_secret_id at apply — same pattern as the tool backend.
resource "azurerm_user_assigned_identity" "ai_kv" {
  name                = "${local.app_name}-kv"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = {
    Environment = var.environment
    Application = "AI"
    Component   = "Backend-KV"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_container_app" "backend" {
  name                         = local.app_name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ai_kv.id]
  }

  ingress {
    # Internal-only: consumed app-to-app over the CAE network (tool backend).
    external_enabled = false
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
    # LOAD-BEARING — do not scale above 1. This is a correctness constraint, not a
    # cost or capacity choice. SuggestionJobService keeps suggestion jobs AND the
    # per-user daily token budget in in-memory ConcurrentHashMaps, not in Postgres
    # (only feedback_records + legal_acts are persisted). With >1 replica:
    #   - a job created on replica A 404s when its status is polled on replica B;
    #   - feedback on that job fails (FeedbackService resolves the job from memory);
    #   - the daily budget is enforced per-replica, so N replicas = N× the cap.
    # Raising this requires moving that state into the DB first — an app change.
    max_replicas = 1

    container {
      name   = local.app_name
      image  = "${var.backend_image}:${var.backend_image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      # Auth / environment mode. 'development' disables OIDC (all endpoints open).
      env {
        name  = "APP_ENVIRONMENT"
        value = var.app_environment
      }
      # OIDC (only consulted when APP_ENVIRONMENT = production).
      dynamic "env" {
        for_each = var.oidc_issuer_uri != "" ? [1] : []
        content {
          name  = "OIDC_ISSUER_URI"
          value = var.oidc_issuer_uri
        }
      }
      dynamic "env" {
        for_each = var.oidc_jwk_set_uri != "" ? [1] : []
        content {
          name  = "OIDC_JWK_SET_URI"
          value = var.oidc_jwk_set_uri
        }
      }

      # Database — dedicated ismd_ai DB on the tool's Postgres server.
      env {
        name  = "SPRING_DATASOURCE_URL"
        value = local.datasource_url
      }
      env {
        name  = "APP_DB_USER"
        value = var.postgres_user
      }
      env {
        name        = "APP_DB_PASSWORD"
        secret_name = "app-db-password"
      }

      # LLM
      env {
        name  = "APP_LLM_ENABLED"
        value = var.llm_enabled ? "true" : "false"
      }
      env {
        name  = "APP_LLM_PROVIDER"
        value = var.llm_provider
      }
      env {
        name  = "APP_LLM_MODEL"
        value = var.llm_model
      }
      env {
        name  = "APP_LLM_ENDPOINT_URL"
        value = var.llm_endpoint_url
      }
      env {
        name  = "APP_LLM_MAX_TOKENS"
        value = tostring(var.llm_max_tokens)
      }
      env {
        name  = "APP_LLM_TEMPERATURE"
        value = tostring(var.llm_temperature)
      }
      env {
        name  = "APP_LLM_TIMEOUT"
        value = var.llm_timeout
      }
      # Falls back to a plain empty value when no key exists (llm_enabled = false),
      # since the backing secret is only created once a key is supplied.
      dynamic "env" {
        for_each = local.llm_api_key_present ? [1] : []
        content {
          name        = "APP_LLM_API_KEY"
          secret_name = "app-llm-api-key"
        }
      }
      dynamic "env" {
        for_each = local.llm_api_key_present ? [] : [1]
        content {
          name  = "APP_LLM_API_KEY"
          value = ""
        }
      }

      # SPARQL / token budget
      env {
        name  = "APP_SPARQL_ENDPOINT_URL"
        value = var.sparql_endpoint_url
      }
      env {
        name  = "APP_TOKENS_MAX_ALLOWED_PER_DAY"
        value = tostring(var.tokens_max_allowed_per_day)
      }

      # Telemetry
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
          value = local.app_name
        }
      }

      # No Spring Actuator in this app. springdoc's /v3/api-docs is permitAll in
      # both dev and prod security config, so it is a safe unauthenticated probe
      # target that confirms Spring MVC is serving.
      liveness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/v3/api-docs"
        interval_seconds = 30
      }
      readiness_probe {
        transport        = "HTTP"
        port             = 8080
        path             = "/v3/api-docs"
        interval_seconds = 10
      }
      startup_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/v3/api-docs"
        # 30 × 10s = 300s budget for the cold JVM boot (image pull + Spring start
        # + schema init). Matches the tool backend's startup grace.
        interval_seconds        = 10
        failure_count_threshold = 30
        timeout                 = 5
      }
    }
  }

  # GHCR pull auth for the private ismd-ai package. Omitted entirely when no PAT
  # is supplied (i.e. once the package/repo is public).
  dynamic "registry" {
    for_each = local.ghcr_auth_enabled ? [1] : []
    content {
      server               = "ghcr.io"
      username             = var.ghcr_username
      password_secret_name = "ghcr-token"
    }
  }

  # ghcr-token: two-phase KV migration (Class A), mirroring the other secrets.
  dynamic "secret" {
    for_each = local.ghcr_auth_enabled && var.ghcr_token_kv_secret_id == "" ? [1] : []
    content {
      name  = "ghcr-token"
      value = var.ghcr_token
    }
  }
  dynamic "secret" {
    for_each = var.ghcr_token_kv_secret_id != "" ? [1] : []
    content {
      name                = "ghcr-token"
      key_vault_secret_id = var.ghcr_token_kv_secret_id
      identity            = azurerm_user_assigned_identity.ai_kv.id
    }
  }

  # app-db-password: two-phase KV migration (Class A). Reuses the tool's Postgres
  # password secret (same server/admin login).
  dynamic "secret" {
    for_each = var.postgres_password_kv_secret_id == "" ? [1] : []
    content {
      name  = "app-db-password"
      value = var.postgres_password
    }
  }
  dynamic "secret" {
    for_each = var.postgres_password_kv_secret_id != "" ? [1] : []
    content {
      name                = "app-db-password"
      key_vault_secret_id = var.postgres_password_kv_secret_id
      identity            = azurerm_user_assigned_identity.ai_kv.id
    }
  }

  # app-llm-api-key: two-phase KV migration (Class A). The inline form only renders
  # when a key is actually set — Container Apps rejects a secret with an empty value
  # ("value or keyVaultUrl and identity should be provided"), which is the normal
  # state while llm_enabled = false and no key has been issued.
  dynamic "secret" {
    for_each = var.llm_api_key_kv_secret_id == "" && var.llm_api_key != "" ? [1] : []
    content {
      name  = "app-llm-api-key"
      value = var.llm_api_key
    }
  }
  dynamic "secret" {
    for_each = var.llm_api_key_kv_secret_id != "" ? [1] : []
    content {
      name                = "app-llm-api-key"
      key_vault_secret_id = var.llm_api_key_kv_secret_id
      identity            = azurerm_user_assigned_identity.ai_kv.id
    }
  }

  # app-insights-connection-string: two-phase KV migration (Class A).
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
      identity            = azurerm_user_assigned_identity.ai_kv.id
    }
  }

  tags = {
    Environment = var.environment
    Application = "AI"
    ManagedBy   = "Terraform"
    Location    = var.location
  }

  # CI/CD owns the deployed image tag (az containerapp update), same as the other
  # apps — Terraform must not revert it on apply.
  lifecycle {
    ignore_changes = [
      template[0].container[0].image
    ]
  }

  depends_on = [
    azurerm_postgresql_flexible_server_database.ai
  ]
}

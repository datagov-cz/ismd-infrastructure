# Frontend Container App for Tool

locals {
  tool_frontend_scheme = var.environment == "dev" && var.app_gateway_hostname == "" ? "http" : "https"
  tool_frontend_host   = var.app_gateway_hostname != "" ? var.app_gateway_hostname : var.app_gateway_public_ip
  tool_base_path       = trimspace(var.tool_base_path) == "" ? "" : (startswith(trimspace(var.tool_base_path), "/") ? trimsuffix(trimspace(var.tool_base_path), "/") : "/${trimsuffix(trimspace(var.tool_base_path), "/")}")

  tool_frontend_base_url = "${local.tool_frontend_scheme}://${local.tool_frontend_host}${local.tool_base_path}"
  tool_nextauth_url      = "${local.tool_frontend_base_url}/api/auth"
}

# Dedicated identity for pulling this app's secrets from the per-env Key Vault
# (same rationale as backend_kv). The frontend had no identity before Class A —
# added here as UserAssigned so it can be granted KV access ahead of any reference.
resource "azurerm_user_assigned_identity" "frontend_kv" {
  name                = "${var.frontend_app_name}-kv-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Frontend-KV"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_container_app" "frontend" {
  name                         = "${var.frontend_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  # Set workload profile name based on environment
  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.frontend_kv.id]
  }

  template {
    min_replicas = 1
    container {
      name   = "ismd-tool-frontend-${var.environment}"
      image  = "${var.frontend_image}:${var.frontend_image_tag}"
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "BE_URL"
        value = "http://${azurerm_container_app.backend.name}${local.tool_base_path}"
      }
      env {
        name  = "NEXT_PUBLIC_BASE_PATH"
        value = local.tool_base_path
      }
      env {
        name  = "KEYCLOAK_ISSUER"
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
      # Skip Keycloak's login page and redirect straight to this IdP alias.
      # Emitted only when set, so an empty value leaves the Keycloak page
      # reachable. A config toggle with no rebuild — auth.ts reads it at runtime.
      dynamic "env" {
        for_each = var.keycloak_idp_hint != "" ? [1] : []
        content {
          name  = "KEYCLOAK_IDP_HINT"
          value = var.keycloak_idp_hint
        }
      }
      env {
        name  = "NEXTAUTH_URL"
        value = local.tool_nextauth_url
      }
      env {
        name  = "NODE_ENV"
        value = var.environment == "prod" ? "production" : "development"
      }
      env {
        name        = "NEXTAUTH_SECRET"
        secret_name = "nextauth-secret"
      }
      env {
        name  = "SITE_STATUS"
        value = var.site_status
      }
      dynamic "env" {
        for_each = var.site_preview_secret != "" || var.frontend_site_preview_secret_kv_secret_id != "" ? [1] : []
        content {
          name        = "SITE_PREVIEW_SECRET"
          secret_name = "site-preview-secret"
        }
      }
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
      }
      # Server-side App Insights activation for the Next.js server. OTEL_SERVICE_NAME
      # is both the per-env activation signal (instrumentation.node.ts is inert until
      # it's set) and the cloud role name. Gated so it's a config toggle with no
      # rebuild — see enable_frontend_app_insights for the dep-must-ship-first guard.
      dynamic "env" {
        for_each = var.enable_frontend_app_insights ? [1] : []
        content {
          name  = "OTEL_SERVICE_NAME"
          value = "${var.frontend_app_name}-${var.environment}"
        }
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = 3000
        path                    = "/popisujeme"
        interval_seconds        = 10
        failure_count_threshold = 3
        timeout                 = 5
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = 3000
        path                    = "/popisujeme"
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

  # Class A two-phase KV migration — each secret stays inline until its
  # *_kv_secret_id var is set, then flips to a Key Vault reference pulled by the
  # frontend's UserAssigned identity. Same shape as the backend.
  dynamic "secret" {
    for_each = var.frontend_nextauth_secret_kv_secret_id == "" ? [1] : []
    content {
      name  = "nextauth-secret"
      value = var.nextauth_secret
    }
  }
  dynamic "secret" {
    for_each = var.frontend_nextauth_secret_kv_secret_id != "" ? [1] : []
    content {
      name                = "nextauth-secret"
      key_vault_secret_id = var.frontend_nextauth_secret_kv_secret_id
      identity            = azurerm_user_assigned_identity.frontend_kv.id
    }
  }

  dynamic "secret" {
    for_each = var.frontend_keycloak_client_secret_kv_secret_id == "" ? [1] : []
    content {
      name  = "keycloak-client-secret"
      value = var.keycloak_client_secret
    }
  }
  dynamic "secret" {
    for_each = var.frontend_keycloak_client_secret_kv_secret_id != "" ? [1] : []
    content {
      name                = "keycloak-client-secret"
      key_vault_secret_id = var.frontend_keycloak_client_secret_kv_secret_id
      identity            = azurerm_user_assigned_identity.frontend_kv.id
    }
  }

  # site-preview: inline only when a preview secret is set AND not yet in KV;
  # KV reference when its secret id is supplied; absent otherwise.
  dynamic "secret" {
    for_each = var.site_preview_secret != "" && var.frontend_site_preview_secret_kv_secret_id == "" ? [1] : []
    content {
      name  = "site-preview-secret"
      value = var.site_preview_secret
    }
  }
  dynamic "secret" {
    for_each = var.frontend_site_preview_secret_kv_secret_id != "" ? [1] : []
    content {
      name                = "site-preview-secret"
      key_vault_secret_id = var.frontend_site_preview_secret_kv_secret_id
      identity            = azurerm_user_assigned_identity.frontend_kv.id
    }
  }

  dynamic "secret" {
    for_each = var.frontend_app_insights_kv_secret_id == "" ? [1] : []
    content {
      name  = "app-insights-connection-string"
      value = var.app_insights_connection_string
    }
  }
  dynamic "secret" {
    for_each = var.frontend_app_insights_kv_secret_id != "" ? [1] : []
    content {
      name                = "app-insights-connection-string"
      key_vault_secret_id = var.frontend_app_insights_kv_secret_id
      identity            = azurerm_user_assigned_identity.frontend_kv.id
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

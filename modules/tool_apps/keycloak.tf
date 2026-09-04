# Keycloak Container App for Tool

locals {
  keycloak_jdbc_url = var.deploy_postgres ? "jdbc:postgresql://ismd-tool-postgres-${var.environment}.postgres.database.azure.com:5432/${var.keycloak_db_name}?sslmode=require" : var.keycloak_postgres_url
  keycloak_fqdn     = var.deploy_keycloak ? azurerm_container_app.keycloak[0].ingress[0].fqdn : ""

  # Only enforce a strict hostname when explicitly set via keycloak_hostname.
  # Falling back to app_gateway_hostname breaks direct admin console access.
  keycloak_hostname_effective = trimspace(var.keycloak_hostname)

  keycloak_issuer_host = local.keycloak_hostname_effective != "" ? local.keycloak_hostname_effective : local.keycloak_fqdn
  keycloak_issuer_uri  = var.keycloak_issuer_uri != "" ? var.keycloak_issuer_uri : (var.deploy_keycloak ? "https://${local.keycloak_issuer_host}${local.tool_base_path}/auth/realms/${var.keycloak_realm}" : "")

  # CAAIS mTLS keystore renders once the KV secret ids are supplied. The CAAIS cert
  # lives in the per-env vault as a KV Certificate object (key generated in-vault,
  # signed cert merged in); its auto-exposed secret yields the PFX, which is what
  # caais_p12_kv_secret_id points at. Read by the keycloak_kv identity — no separate
  # CAAIS identity: both would be attached to the same container, and keycloak_kv
  # already holds Get/List on the whole vault, so a second one buys no isolation.
  # Its access policy is created unconditionally in the env root, so the grant is
  # always in place before a secret reference is validated at apply — no two-phase.
  # Stays inert (empty defaults) so this can sit merged ahead of the signed cert.
  # A real password is REQUIRED. KV exports the PFX unprotected, but Keycloak can't
  # use an empty password: Quarkus reads an empty env var as unset -> null ->
  # UnrecoverableKeyException. So the init container re-wraps the PFX with this
  # password and Keycloak opens it with the same one.
  caais_keystore_pw_from_kv = var.caais_keystore_password_kv_secret_id != ""
  caais_keystore_pw_ready   = local.caais_keystore_pw_from_kv || var.caais_keystore_password != ""

  caais_keystore_ready = var.deploy_keycloak && var.enable_caais && var.caais_client_id != "" && var.caais_p12_kv_secret_id != "" && local.caais_keystore_pw_ready
  caais_keystore_path  = "/opt/keycloak/conf/caais/caais.p12"
}

# Identity for pulling keycloak's secrets (admin/db passwords, app-insights, and the
# CAAIS keystore) from the per-env Key Vault. Always created when keycloak is
# deployed, so it can be granted KV access ahead of the reference cutover.
resource "azurerm_user_assigned_identity" "keycloak_kv" {
  count               = var.deploy_keycloak ? 1 : 0
  name                = "${var.keycloak_app_name}-kv-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "Keycloak-KV"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_container_app" "keycloak" {
  count                        = var.deploy_keycloak ? 1 : 0
  name                         = "${var.keycloak_app_name}-${var.environment}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  workload_profile_name = var.workload_profile_name == "Consumption" ? null : var.workload_profile_name

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.keycloak_kv[0].id]
  }

  template {
    min_replicas = 1
    # LOAD-BEARING — do not scale above 1. No cache/cluster stack is configured
    # (no KC_CACHE / jgroups / Infinispan settings), so each replica keeps its own
    # local caches. A second replica would break login: user sessions and the OIDC
    # authentication-code flow live in those caches, so requests landing on a
    # different replica mid-flow fail to find their session.
    # Scaling out requires KC_CACHE=ispn with a working discovery stack first.
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
        name = "KC_DB_USERNAME"
        # Per-app user separation: dedicated role when set, else admin login. See keycloak_db_user.
        value = var.keycloak_db_user != "" ? var.keycloak_db_user : (var.deploy_postgres ? var.postgres_admin_user : var.keycloak_postgres_user)
      }
      env {
        name        = "KC_DB_PASSWORD"
        secret_name = "keycloak-db-password"
      }
      # Bound the Keycloak DB pool. Default max is 100 — larger than the whole
      # server's max_connections (50), which is what let a reconnect storm
      # exhaust the slots. 20 is ample for this app's modest login concurrency
      # (user sessions live in Keycloak's cache, not as DB connections).
      env {
        name  = "KC_DB_POOL_MAX_CONNECTIONS"
        value = "20"
      }
      env {
        name  = "KC_DB_POOL_INITIAL_SIZE"
        value = "2"
      }
      env {
        name  = "KC_DB_POOL_MIN_SIZE"
        value = "2"
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

      # CAAIS mTLS: point Keycloak's global outbound HTTP client at the client
      # keystore the init container decoded into the shared volume. Server-wide
      # (spi-connections-http-client-default-*) — only the CAAIS token call needs
      # mTLS, and it is the only outbound mTLS target.
      dynamic "env" {
        for_each = local.caais_keystore_ready ? [1] : []
        content {
          name  = "KC_SPI_CONNECTIONS_HTTP_CLIENT_DEFAULT_CLIENT_KEYSTORE"
          value = local.caais_keystore_path
        }
      }
      # Both options get the SAME password — the init container re-wrapped the p12 with
      # it, and `openssl pkcs12 -export` protects the file with a single password.
      # Keycloak requires both to be set (and non-null) whenever client-keystore is.
      dynamic "env" {
        for_each = local.caais_keystore_ready ? toset(["KC_SPI_CONNECTIONS_HTTP_CLIENT_DEFAULT_CLIENT_KEYSTORE_PASSWORD", "KC_SPI_CONNECTIONS_HTTP_CLIENT_DEFAULT_CLIENT_KEY_PASSWORD"]) : toset([])
        content {
          name        = env.value
          value       = local.caais_keystore_pw_from_kv ? null : var.caais_keystore_password
          secret_name = local.caais_keystore_pw_from_kv ? "caais-keystore-pw" : null
        }
      }

      dynamic "volume_mounts" {
        for_each = local.caais_keystore_ready ? [1] : []
        content {
          name = "caais-keystore"
          path = "/opt/keycloak/conf/caais"
        }
      }

      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "app-insights-connection-string"
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

    # Decode the base64 KV secret into a binary PKCS12 on a shared volume before
    # Keycloak starts. Needed because the stock Keycloak image is ubi-micro (no
    # shell/base64), and Container Apps secrets carry text, not binary keystores.
    dynamic "init_container" {
      for_each = local.caais_keystore_ready ? [1] : []
      content {
        name  = "caais-cert-init"
        image = var.caais_keystore_init_image
        # Must be an explicit valid CPU/memory pair — omitting them makes the
        # provider send cpu '0', which Azure rejects (ContainerAppInvalidCpuResource).
        cpu     = 0.25
        memory  = "0.5Gi"
        command = ["/bin/sh", "-c"]
        # 1. decode the KV export (tr strips stray CR/whitespace — strict base64 -d
        #    fails on it), 2. re-wrap it with a real password, because KV exports the
        #    PFX unprotected and Keycloak cannot use an empty password (empty env var
        #    -> unset -> null -> UnrecoverableKeyException).
        # -passin pass: is the empty source password; -passout sets the new one.
        # World-readable: init runs as root, Keycloak as uid 1000, and the volume is
        # an ephemeral in-pod EmptyDir.
        args = [
          "set -e; printf '%s' \"$CAAIS_P12_B64\" | tr -d '\\r\\n ' | base64 -d > /caais/raw.p12; openssl pkcs12 -in /caais/raw.p12 -passin pass: -nodes | openssl pkcs12 -export -out /caais/caais.p12 -passout env:CAAIS_KEYSTORE_PW; rm -f /caais/raw.p12; chmod 644 /caais/caais.p12"
        ]

        env {
          name        = "CAAIS_P12_B64"
          secret_name = "caais-p12-b64"
        }

        dynamic "env" {
          for_each = local.caais_keystore_pw_from_kv ? [1] : []
          content {
            name        = "CAAIS_KEYSTORE_PW"
            secret_name = "caais-keystore-pw"
          }
        }
        dynamic "env" {
          for_each = local.caais_keystore_pw_from_kv ? [] : [1]
          content {
            name  = "CAAIS_KEYSTORE_PW"
            value = var.caais_keystore_password
          }
        }

        volume_mounts {
          name = "caais-keystore"
          path = "/caais"
        }
      }
    }

    dynamic "volume" {
      for_each = local.caais_keystore_ready ? [1] : []
      content {
        name         = "caais-keystore"
        storage_type = "EmptyDir"
      }
    }
  }

  # Class A two-phase KV migration — each stays inline until its *_kv_secret_id var
  # is set, then flips to a Key Vault reference pulled by the keycloak_kv identity.
  dynamic "secret" {
    for_each = var.keycloak_admin_password_kv_secret_id == "" ? [1] : []
    content {
      name  = "keycloak-admin-password"
      value = var.keycloak_admin_password
    }
  }
  dynamic "secret" {
    for_each = var.keycloak_admin_password_kv_secret_id != "" ? [1] : []
    content {
      name                = "keycloak-admin-password"
      key_vault_secret_id = var.keycloak_admin_password_kv_secret_id
      identity            = azurerm_user_assigned_identity.keycloak_kv[0].id
    }
  }

  # keycloak-db-password: same value as the backend's postgres-password when
  # deploy_postgres — point both at the single KV `postgres-password` secret.
  dynamic "secret" {
    for_each = var.keycloak_db_password_kv_secret_id == "" ? [1] : []
    content {
      name  = "keycloak-db-password"
      value = var.deploy_postgres ? var.postgres_admin_password : var.keycloak_postgres_password
    }
  }
  dynamic "secret" {
    for_each = var.keycloak_db_password_kv_secret_id != "" ? [1] : []
    content {
      name                = "keycloak-db-password"
      key_vault_secret_id = var.keycloak_db_password_kv_secret_id
      identity            = azurerm_user_assigned_identity.keycloak_kv[0].id
    }
  }

  dynamic "secret" {
    for_each = var.keycloak_app_insights_kv_secret_id == "" ? [1] : []
    content {
      name  = "app-insights-connection-string"
      value = var.app_insights_connection_string
    }
  }
  dynamic "secret" {
    for_each = var.keycloak_app_insights_kv_secret_id != "" ? [1] : []
    content {
      name                = "app-insights-connection-string"
      key_vault_secret_id = var.keycloak_app_insights_kv_secret_id
      identity            = azurerm_user_assigned_identity.keycloak_kv[0].id
    }
  }

  # KV-backed CAAIS keystore secrets, pulled at runtime by the keycloak_kv identity.
  # caais_p12_kv_secret_id normally points at the auto-exposed secret of the CAAIS
  # KV Certificate object (…/secrets/<cert-name>), which returns the PFX in base64.
  dynamic "secret" {
    for_each = local.caais_keystore_ready ? [1] : []
    content {
      name                = "caais-p12-b64"
      key_vault_secret_id = var.caais_p12_kv_secret_id
      identity            = azurerm_user_assigned_identity.keycloak_kv[0].id
    }
  }
  # The p12 password, when KV-backed. Read by both the init container (to re-wrap)
  # and Keycloak (to open). Inline passwords go through as plain env values instead —
  # Container Apps rejects a secret whose value is empty.
  dynamic "secret" {
    for_each = local.caais_keystore_ready && local.caais_keystore_pw_from_kv ? [1] : []
    content {
      name                = "caais-keystore-pw"
      key_vault_secret_id = var.caais_keystore_password_kv_secret_id
      identity            = azurerm_user_assigned_identity.keycloak_kv[0].id
    }
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

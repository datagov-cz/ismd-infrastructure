# Logical-backup job — weekly pg_dump per database, encrypted, into blob storage.
#
# Slice 2 of POSTGRES-LOGICAL-BACKUP-PLAN.md. Storage lives in backup_storage.tf.
#
# TWO STOCK IMAGES, NO CUSTOM BUILD. postgres:16 has pg_dump and openssl but no
# uploader (no curl, no wget, no python3 — verified). mcr azure-cli has `az` but no
# pg_dump. An init_container runs to completion before the main container starts,
# which is exactly the sequencing we need: dump+encrypt, then upload. The shared
# volume is EmptyDir, so plaintext never lands anywhere persistent — and it never
# exists even there, because pg_dump is piped straight into openssl.
#
# The job runs in the shared Container Apps environment, so it reaches the server
# over the private endpoint. The admin firewall rule is not involved.
#
# ENCRYPTION: the passphrase lives ONLY in ismd-kv-<env>/pg-backup-encryption-key
# (terraw resolves TF_VAR_pg_backup_encryption_key). No personal escrow — the estate
# hands over to DIA. Lose it and every dump is unreadable, and the containers'
# immutability policies block deleting them early. Decrypt with:
#   openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_KEY -in X.dump.enc
#
# RETENTION is enforced by the lifecycle policy in backup_storage.tf, not here. Azure
# matches lifecycle prefixMatch against the CONTAINER name, so "weekly/" covers
# everything in the weekly container; the job only has to put files in the right one.

locals {
  backup_date_fmt = "%Y-%m-%d"

  # Dump + encrypt. Runs as the server admin: objects are owned by the per-app roles
  # (ismd_tool_app, ismd_keycloak_app, ismd_ai_app) and ismdadmin is a member of each,
  # so one login covers every database.
  backup_dump_script = <<-SCRIPT
    set -eu
    mkdir -p /dumps
    for db in $DATABASES; do
      echo "dumping $db"
      pg_dump -Fc -h "$PGHOST" -U "$PGUSER" -d "$db" \
        | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -pass env:BACKUP_KEY \
          -out "/dumps/$db-$(date -u +${local.backup_date_fmt}).dump.enc"
    done
    ls -l /dumps
  SCRIPT

  # Upload. --overwrite false fails loudly on a name collision rather than silently
  # skipping; with immutability on, an overwrite would be rejected anyway.
  # On the 1st of the month the same files also go to the 90-day container.
  backup_upload_script = <<-SCRIPT
    set -eu
    az storage blob upload-batch --destination weekly --source /dumps \
      --account-name "$ACCOUNT" --account-key "$STORAGE_KEY" --overwrite false --output none
    echo "uploaded to weekly"
    if [ "$(date -u +%d)" = "01" ]; then
      az storage blob upload-batch --destination monthly --source /dumps \
        --account-name "$ACCOUNT" --account-key "$STORAGE_KEY" --overwrite false --output none
      echo "uploaded to monthly"
    fi
    az storage blob list --container-name weekly --account-name "$ACCOUNT" \
      --account-key "$STORAGE_KEY" --query "[].name" --output tsv
  SCRIPT
}

resource "azurerm_container_app_job" "backup" {
  count                        = var.enable_logical_backups ? 1 : 0
  name                         = "ismd-pg-backup-${var.environment}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = var.container_app_environment_id

  # Explicit: left unset, Azure reports "Consumption" and every plan shows a diff.
  workload_profile_name = "Consumption"

  # 30 min ceiling: the databases are single-digit MB, so a normal run is seconds.
  # One retry, because a transient DNS or storage blip should not skip a week.
  replica_timeout_in_seconds = 1800
  replica_retry_limit        = 1

  schedule_trigger_config {
    cron_expression          = var.backup_cron_expression
    parallelism              = 1
    replica_completion_count = 1
  }

  secret {
    name  = "pgpassword"
    value = var.postgres_admin_password
  }

  secret {
    name  = "backupkey"
    value = var.backup_encryption_key
  }

  secret {
    name  = "storagekey"
    value = azurerm_storage_account.backup[0].primary_access_key
  }

  template {
    volume {
      name         = "dumps"
      storage_type = "EmptyDir"
    }

    init_container {
      name    = "dump"
      image   = "postgres:16"
      cpu     = 0.5
      memory  = "1Gi"
      command = ["/bin/sh", "-c"]
      args    = [local.backup_dump_script]

      env {
        name  = "PGHOST"
        value = azurerm_postgresql_flexible_server.tool.fqdn
      }

      env {
        name  = "PGUSER"
        value = var.postgres_admin_user
      }

      env {
        name        = "PGPASSWORD"
        secret_name = "pgpassword"
      }

      env {
        name        = "BACKUP_KEY"
        secret_name = "backupkey"
      }

      # Azure Postgres requires TLS; be explicit rather than relying on defaults.
      env {
        name  = "PGSSLMODE"
        value = "require"
      }

      # Space-separated, so test (no ismd_ai) differs by tfvars, not by code.
      env {
        name  = "DATABASES"
        value = join(" ", var.backup_databases)
      }

      volume_mounts {
        name = "dumps"
        path = "/dumps"
      }
    }

    container {
      name    = "upload"
      image   = "mcr.microsoft.com/azure-cli:latest"
      cpu     = 0.5
      memory  = "1Gi"
      command = ["/bin/sh", "-c"]
      args    = [local.backup_upload_script]

      env {
        name  = "ACCOUNT"
        value = azurerm_storage_account.backup[0].name
      }

      env {
        name        = "STORAGE_KEY"
        secret_name = "storagekey"
      }

      volume_mounts {
        name = "dumps"
        path = "/dumps"
      }
    }
  }

  tags = {
    Environment = var.environment
    Application = "Tool"
    Component   = "DatabaseBackup"
    ManagedBy   = "Terraform"
  }
}

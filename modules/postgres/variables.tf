variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "location" {
  description = "Azure region for the server"
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Resource group holding the Flexible Server. Intended to be the per-env shared
    RG (ismd-shared-<env>), since the server is shared by tool, keycloak and ai.

    CHANGING THIS FORCES REPLACEMENT — destroy + recreate, i.e. total data loss for
    every database on the server. To relocate the server, move it out of band with
    `az resource move`, then `terraform state rm` + `terraform import` each address
    at its new id, and only then change this value. See
    docs/postgres-shared-move-plan.md.
  EOT
  type        = string
}

variable "postgres_admin_user" {
  description = "PostgreSQL admin (server) login. Apps authenticate as their own LOGIN role; this stays for break-glass and migrations."
  type        = string
  default     = "ismdadmin"
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password, resolved from Key Vault by terraw. Managed by Terraform: a new KV version plus an apply rotates the live password."
  type        = string
  sensitive   = true
}

variable "postgres_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server (e.g., B_Standard_B1ms for burstable)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Storage in MB for the Flexible Server"
  type        = number
  default     = 32768
}

variable "allow_azure_services" {
  description = "Emit the blanket AllowAzureServices (0.0.0.0) firewall rule, which admits any Azure-hosted resource in any tenant. Only needed while apps reach the PUBLIC endpoint; set false once they use the private endpoint."
  type        = bool
  default     = true
}

variable "app_outbound_ips" {
  description = "Stable app egress IPs to allowlist. Empty until a NAT gateway provides one; when populated, set allow_azure_services = false."
  type        = list(string)
  default     = []
}

variable "admin_allowed_ips" {
  description = "Operator/admin public IP(s) allowed direct access for troubleshooting. Set via TF_VAR_admin_allowed_ips in .env.<env>."
  type        = list(string)
  default     = []
}

variable "maintenance_window" {
  description = "Custom maintenance window, UTC. day_of_week 0 = Sunday. null = system-managed (Azure picks the slot)."
  type = object({
    day_of_week  = number
    start_hour   = number
    start_minute = number
  })
  default = null
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for server logs and Query Store. null = no diagnostic setting."
  type        = string
  default     = null
}

variable "enable_private_endpoint" {
  description = "Create the private endpoint, privatelink DNS zone and VNet link. An explicit bool rather than a null check on the subnet id, because count cannot depend on a value unknown until apply."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the server's private endpoint (must not be delegated). Required when enable_private_endpoint is true."
  type        = string
  default     = null
}

variable "vnet_id" {
  description = "VNet the privatelink DNS zone is linked to, so the server FQDN resolves to the private endpoint from inside it. Required when enable_private_endpoint is true."
  type        = string
  default     = null
}

variable "enable_logical_backups" {
  description = <<-EOT
    Create the logical-backup storage account, containers, immutability and lifecycle
    policies for this environment. The Container App Job that writes dumps is added
    separately (slice 2). Off everywhere until an environment is explicitly opted in.
  EOT
  type        = bool
  default     = false
}

variable "backup_weekly_retention_days" {
  description = "Retention for weekly/ dumps, in days. Sets BOTH the immutability period and the lifecycle delete age — they must stay equal, or the lifecycle delete fails against the immutability window."
  type        = number
  default     = 14
}

variable "backup_monthly_retention_days" {
  description = "Retention for monthly/ dumps, in days. Sets BOTH the immutability period and the lifecycle delete age — see backup_weekly_retention_days."
  type        = number
  default     = 90
}

variable "container_app_environment_id" {
  description = "Shared Container Apps environment the backup job runs in. VNet-integrated, so the job reaches the server over the private endpoint. Required when enable_logical_backups is true."
  type        = string
  default     = null
}

variable "backup_databases" {
  description = "Databases to dump, one entry each. Differs per environment (test has no ismd_ai), so it is set in tfvars rather than inferred."
  type        = list(string)
  default     = []
}

variable "backup_cron_expression" {
  description = "Cron for the backup job, UTC. Default Sunday 01:30, clear of the Sunday 00:00 maintenance window on dev."
  type        = string
  default     = "30 1 * * 0"
}

variable "backup_encryption_key" {
  description = "Passphrase for openssl encryption of the dumps, from ismd-kv-<env>/pg-backup-encryption-key via terraw. Key Vault is the only copy."
  type        = string
  sensitive   = true
  default     = ""
}

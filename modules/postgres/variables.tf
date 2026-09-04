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
  description = "PostgreSQL admin password. Seeded once at create, then owned out-of-band (Key Vault is the source of truth) — see ignore_changes on the server."
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
  description = "Emit the blanket AllowAzureServices (0.0.0.0) firewall rule. Required while the Container Apps subnet has no NAT gateway and egresses via dynamic Azure SNAT."
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

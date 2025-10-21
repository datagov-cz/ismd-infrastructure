variable "location" {
  description = "The Azure region where all resources should be created"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "domain_name_label" {
  description = "The domain name label for the IPv6 public IP"
  type        = string
  default     = "ismd-appgw-ipv6"
}

variable "frontend_fqdn" {
  description = "FQDN of the frontend container app (if already known)"
  type        = string
  default     = ""
}

variable "backend_fqdn" {
  description = "FQDN of the backend container app (if already known)"
  type        = string
  default     = ""
}

# Optional hostnames for host-based routing (use punycode for IDNs)
variable "dev_hostname" {
  description = "Hostname for DEV (e.g., ismd.oha03.dia.gov.cz)"
  type        = string
  default     = ""
}

variable "test_hostname" {
  description = "Hostname for TEST (e.g., ismd.slovník-test.dia.gov.cz) — use punycode"
  type        = string
  default     = ""
}

variable "prod_hostname" {
  description = "Hostname for PROD (e.g., ismd.slovník.gov.cz) — use punycode"
  type        = string
  default     = ""
}

# Optional FQDNs for other environments (if known)
variable "frontend_fqdn_test" {
  description = "FQDN of the frontend container app in TEST"
  type        = string
  default     = ""
}

variable "backend_fqdn_test" {
  description = "FQDN of the backend container app in TEST"
  type        = string
  default     = ""
}

variable "frontend_fqdn_prod" {
  description = "FQDN of the frontend container app in PROD"
  type        = string
  default     = ""
}

variable "backend_fqdn_prod" {
  description = "FQDN of the backend container app in PROD"
  type        = string
  default     = ""
}

variable "ssl_certificate_keyvault_secret_id" {
  description = "Key Vault secret ID for SSL certificate (supports versioned or versionless URLs)"
  type        = string
  default     = "https://ismd-keyvault.vault.azure.net/secrets/datagov-cz"
}

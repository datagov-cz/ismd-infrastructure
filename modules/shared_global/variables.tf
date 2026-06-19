variable "location" {
  description = "The Azure region where all resources should be created"
  type        = string
}

variable "domain_name_label" {
  description = "The domain name label for the IPv6 public IP"
  type        = string
  default     = "ismd-appgw-ipv6"
}

# --- Azure Communication Services (ACS) Email — Keycloak SMTP sender ---

variable "deploy_acs" {
  description = "Provision ACS Email resources (communication service + email service + domains) for Keycloak transactional email."
  type        = bool
  default     = true
}

variable "acs_name" {
  description = "Name of the Azure Communication Service resource. Also forms the first segment of the SMTP username (<acs_name>.<entra-app-id>.<tenant-id>)."
  type        = string
  default     = "ismd-acs"
}

variable "acs_email_name" {
  description = "Name of the Email Communication Service subresource."
  type        = string
  default     = "ismd-email"
}

variable "acs_data_location" {
  description = "Data residency location for ACS (where email metadata is stored). 'Europe' keeps data in the EU; 'Germany' matches the germanywestcentral region exactly."
  type        = string
  default     = "Europe"
}

variable "acs_enable_custom_domain" {
  description = "Create the CustomerManaged custom sender domain resource so ACS emits the DNS records the client must publish. Does not enable sending until verified."
  type        = bool
  default     = true
}

variable "acs_custom_sender_domain" {
  description = "Custom sender domain for ACS Email (client must publish DNS). Intended PROD sender domain."
  type        = string
  default     = "slovnik.gov.cz"
}

variable "acs_custom_domain_verified" {
  description = "Flip to true ONLY after the client has published DNS and the custom domain shows Verified in ACS. Associates the custom domain with the ACS resource so it can be used as a sender."
  type        = bool
  default     = false
}

# --- Application Gateway WAF (rate limiting + OWASP CRS) ---

variable "waf_mode" {
  description = "WAF policy mode. 'Prevention' blocks matching requests (REQUIRED for the rate-limit rule to enforce); 'Detection' only logs. Mode is policy-wide and governs OWASP managed rules too."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be either 'Detection' or 'Prevention'."
  }
}

variable "waf_rate_limit_threshold" {
  description = "Max requests per client IP within waf_rate_limit_duration before the rate-limit rule blocks (HTTP 429)."
  type        = number
  default     = 300
}

variable "waf_rate_limit_duration" {
  description = "Sliding window for the rate-limit rule. Allowed values: 'OneMin', 'FiveMins'."
  type        = string
  default     = "OneMin"

  validation {
    condition     = contains(["OneMin", "FiveMins"], var.waf_rate_limit_duration)
    error_message = "waf_rate_limit_duration must be 'OneMin' or 'FiveMins'."
  }
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

variable "frontend_app_name" {
  description = "Base name of the frontend container app"
  type        = string
  default     = "ismd-validator-frontend"
}

variable "backend_app_name" {
  description = "Base name of the backend container app"
  type        = string
  default     = "ismd-validator-backend"
}

variable "container_app_environment_domain_dev" {
  description = "Default domain of the DEV Container Apps environment"
  type        = string
  default     = ""
}

variable "container_app_environment_domain_test" {
  description = "Default domain of the TEST Container Apps environment"
  type        = string
  default     = ""
}

variable "container_app_environment_domain_prod" {
  description = "Default domain of the PROD Container Apps environment"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev, test, prod). Note: current gateway config is environment-specific; run this stack for one environment at a time."
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "germanywestcentral"
}

variable "frontend_app_name" {
  description = "Base name of the frontend container app (without environment suffix)"
  type        = string
  default     = "ismd-validator-frontend"
}

variable "backend_app_name" {
  description = "Base name of the backend container app (without environment suffix)"
  type        = string
  default     = "ismd-validator-backend"
}

variable "container_app_environment_domain" {
  description = "DEPRECATED: Use container_app_environment_domain_dev/test/prod instead"
  type        = string
  default     = ""
}

variable "container_app_environment_domain_dev" {
  description = "Default domain of the DEV Container Apps environment (e.g., yellowforest-xyz.germanywestcentral.azurecontainerapps.io)"
  type        = string
  default     = ""
}

variable "container_app_environment_domain_test" {
  description = "Default domain of the TEST Container Apps environment (e.g., greenocean-xyz.germanywestcentral.azurecontainerapps.io)"
  type        = string
  default     = ""
}

variable "container_app_environment_domain_prod" {
  description = "Default domain of the PROD Container Apps environment (e.g., bluemountain-xyz.germanywestcentral.azurecontainerapps.io)"
  type        = string
  default     = ""
}

# Optional explicit DEV FQDNs (used to preserve DEV pools when applying other environments)
variable "frontend_fqdn" {
  description = "Frontend FQDN for DEV"
  type        = string
  default     = ""
}

variable "backend_fqdn" {
  description = "Backend FQDN for DEV"
  type        = string
  default     = ""
}

variable "dev_hostname" {
  description = "Hostname for DEV (ASCII/punycode)"
  type        = string
  default     = ""
}

variable "test_hostname" {
  description = "Hostname for TEST (ASCII/punycode)"
  type        = string
  default     = ""
}

variable "prod_hostname" {
  description = "Hostname for PROD (ASCII/punycode)"
  type        = string
  default     = ""
}

# Optional explicit FQDNs for TEST/PROD if known
variable "frontend_fqdn_test" {
  description = "Frontend FQDN for TEST"
  type        = string
  default     = ""
}

variable "backend_fqdn_test" {
  description = "Backend FQDN for TEST"
  type        = string
  default     = ""
}

variable "frontend_fqdn_prod" {
  description = "Frontend FQDN for PROD"
  type        = string
  default     = ""
}

variable "backend_fqdn_prod" {
  description = "Backend FQDN for PROD"
  type        = string
  default     = ""
}

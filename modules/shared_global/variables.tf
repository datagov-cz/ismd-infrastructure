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

variable "container_app_environment_name" {
  description = "The name of the Container Apps Environment"
  type        = string
  default     = ""
}

variable "container_app_environment_id" {
  description = "The ID of the Container Apps Environment to depend on (optional)"
  type        = string
  default     = ""
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
